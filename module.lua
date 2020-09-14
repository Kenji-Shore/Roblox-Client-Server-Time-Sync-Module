--[[
	Code written by Fluffmiceter 9/9-9/12
	Some Notes:
		1. This system takes a few seconds to calibrate, so do not expect completely accurate values from GetTime() within the first 10 seconds or so. 
		2. Under certain conditions of extremely high client data send, such as creating a new part in workspace every frame from the client, the system can deviate from the correct value by ~30ms. Upon the removal of this load, it will self-correct and converge back to the true time.
			a. I have done testing of heavy server load, high ping, heavy client load, and other situations and the system seems to hold up fine.
		3. Validating the accuracy of this system:
			a. This is a tricky problem to solve because there is no "official synced timer" to compare it against.
			b. In Play Solo testing, I have observed that the simulated client and server read the same tick() values. You can use this to your advantage to validate this system by recording the difference between GetTime() and tick() (since the server time we sync to is the server tick())
			c. In a live server, you can somewhat see the accuracy of this system by printing the synced time from the client and server every frame, and quickly comparing the values being printed by each on the developer console. I know, terrible method. Sorry :P
		4. Security:
			a. Do note that if you use these synchronized clocks to time events on the client and server, remember that the client can spoof what they send in via remote and pretend that their time is something that it is not. Just keep this in mind, while this code does synchronize a clock on your client and server it does not do anything special to protect against exploits.
		5. How it works:
			a. In a nutshell, the special thing about this code versus other client-server clock syncers is that I have studied the intricacies of how Roblox times sending out remote signals, and factoring these in when calculating time offsets.
				i. If you've ever tried to measure the one-directional-travel time of a signal, you can observe that your values will be rapidly fluctuating between certain values.
				ii. If we isolate these values, we find that these values come in increments of the framerate. Subtracting all other factors such as network latency, we find common values such as 0ms, 16ms, 32ms, 48ms (for a game running at 60fps on the server).
				iii. Essentially what is happening is that Roblox does not send out a remote signal the instant you fire it. Instead, it waits until the next "networking cycle", which is always 1 frame on the client and can vary from 1 to 3 frames on the server (though most commonly 2 frames).
				iv. By keeping track of what stage of the cycle we are in using some hacky logic, we can offset our timings by these values to provide for far more accurate syncing.
			b. If any of the behaviors described above change, this whole script could potentially become consistently off by several milliseconds. Until Roblox provides with more access to the internals, unfortunately this is the best we can do.
		6. Troubleshooting:
			a. If there are problems with this system, feel free to message me on Roblox (Fluffmiceter) or Twitter (@Fluffmiceter)
--]]
local module = {}

-----------------------------------------------------------------------------------------------------
--SERVICES
-----------------------------------------------------------------------------------------------------
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

-----------------------------------------------------------------------------------------------------
--MAIN DEFINITIONS
-----------------------------------------------------------------------------------------------------
local clockSyncSignal = replicatedStorage:WaitForChild("ClockSync")

-----------------------------------------------------------------------------------------------------
--CODE
-----------------------------------------------------------------------------------------------------
local isClient = runService:IsClient()

function module:GetTime(overwriteTick) --Not recommended to use this on the client upon join because it takes a few seconds to calibrate. The initial values may be extremely off. OverwriteTick is a tick() value you can pass in if you want to figure out the synced time at an earlier point in time.
	if isClient then
		local offset = self.ServerTimeOffset or 0
		return (overwriteTick or tick()) + offset
	else
		return (overwriteTick or tick())
	end
end

function module:Update() --Hook this to runService.Heartbeat or runService.Stepped for proper operation.
	local newUpdate = tick()
	self.AverageFrameTime = self.AverageFrameTime * 0.9 + (newUpdate - self.LastUpdate) * 0.1
	self.LastUpdate = newUpdate
	
	if not isClient then
		for player, pastAverage in pairs(self.AverageDelays) do
			local cache = self.PlayerCaches[player]
			
			for grouping, groupInfo in pairs(cache) do
				if (newUpdate - groupInfo[1]) > 10 then
					cache[grouping] = nil --Clear any group data that has sat around for too long (dropped calls). Prevent memory buildup.
				end
			end
			
			coroutine.resume(coroutine.create(function()
				local success, clientTimeRaw, clientFrameTime, newGrouping, grouping, groupCount, sendData = pcall(function()
					return clockSyncSignal:InvokeClient(player, newUpdate, pastAverage, self.AverageFrameTime)
				end)
				local delta = tick() - newUpdate
				
				if success and self.PlayerCaches[player] then
					if sendData then
						local sendDataGrouping = sendData[1]
						local group = cache[sendDataGrouping]
						if group then
							for order, info in ipairs(sendData[2]) do
								local delta = group[2][order]
								if delta then
									local sendTime = 0.5 * (delta - (info[1] + info[2]))
									self.AverageDelays[player] = self.AverageDelays[player] * 0.9 + sendTime * 0.1
								end
							end
							
							cache[sendDataGrouping] = nil
						end
					end
					
					if (not cache[grouping]) and newGrouping then
						cache[grouping] = {tick(), {}}
					end
					
					local group = cache[grouping]
					if group then
						group[2][groupCount] = delta
					end
				end
			end))
		end
	end
end

if isClient then
	function module:InvokeSignal(serverTimeRaw, travelDelay, serverFrameTime) --This call is guaranteed to be in order by Roblox, let's make use of that.
		local receiveTick = tick()
		
		local delta = receiveTick - (serverTimeRaw + travelDelay)
		if not self.LastDelta then
			self.LastDelta = delta
		end
		
		local shift = delta - self.LastDelta
		local frameShift = shift / serverFrameTime
		self.LastDelta = delta
		
		frameShift = math.floor(frameShift + 0.5)
		
		local resetCache = false
		local sendDataGrouping = nil
		local newGrouping = false
		if (not self.CurrentReference) or (frameShift >= 0) then
			self.TotalShift = frameShift
			sendDataGrouping = self.Grouping
			
			self.Grouping = (self.Grouping + 1) % 1000
			newGrouping = true
			resetCache = true
			self.CurrentReference = 0
		else
			self.CurrentReference = self.CurrentReference - frameShift
		end
		
		local sendData = nil
		if resetCache then
			if #self.Cache > 0 then
				local maxFrame = self.Cache[#self.Cache][1] + 1
				local average = 0
				
				local sendDataTable = {}
				sendData = {sendDataGrouping, sendDataTable}
				
				for i = 1, #self.Cache do
					local data = self.Cache[i]
					
					local taskSchedulerDelay = (maxFrame - data[1]) * data[3]
					average += data[5] + data[4] + taskSchedulerDelay
					
					sendDataTable[i] = {data[2], taskSchedulerDelay}
				end
				
				average /= #self.Cache
				if not self.ServerTimeOffset then
					self.ServerTimeOffset = average
				else
					self.ServerTimeOffset = self.ServerTimeOffset * 0.98 + average * 0.02
				end
			end
			
			self.Cache = {}
		end
		
		local groupCount = #self.Cache + 1 --The index of this request in its group
		self.Cache[groupCount] = {self.CurrentReference, self.AverageFrameTime, serverFrameTime, travelDelay, serverTimeRaw - receiveTick}
		
		return receiveTick, self.AverageFrameTime, newGrouping, self.Grouping, groupCount, sendData
	end
else
	function module:PlayerAdded(player)
		self.AverageDelays[player] = 0
		self.PlayerCaches[player] = {}
	end
	
	function module:PlayerRemoving(player)
		self.AverageDelays[player] = nil
		self.PlayerCaches[player] = nil
	end
end

function module:Initialize()
	self.AverageFrameTime = 0.0167
	self.LastUpdate = tick()
	
	runService.Heartbeat:connect(function()
		self:Update()
	end)
	
	if isClient then
		self.ServerTimeOffset = nil
		
		self.LastDelta = nil
		self.CurrentReference = nil
		self.Cache = {}
		self.Grouping = 0
		self.TotalShift = 0
		
		function clockSyncSignal.OnClientInvoke(...)
			self:InvokeSignal(...)
		end
	else
		self.AverageDelays = {}
		self.PlayerCaches = {}
		
		players.PlayerAdded:connect(function(player)
			self:PlayerAdded(player)
		end)
		
		players.PlayerRemoving:connect(function(player)
			self:PlayerRemoving(player)
		end)
	end
end

return module
