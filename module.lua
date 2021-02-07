--[[
	Clock sync version 2.0
	Should be a lot more stable on high latency situations; also a lot simpler. 
	
	2/7/21 Fluffmiceter
]]

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
		return (overwriteTick or tick()) + self.ServerOffset
	else
		return (overwriteTick or tick())
	end
end

if isClient then
	function module:OnClientEvent(serverSentTick, delayVal)
		self.TimeDelay = delayVal
		self.LastSentTick = serverSentTick
		self.ReceiveTick = tick()
	end

	function module:AddOffsetValue(newOffsetValue)
		self.ServerOffsetBuffer[#self.ServerOffsetBuffer + 1] = newOffsetValue
		if #self.ServerOffsetBuffer > 50 then
			table.remove(self.ServerOffsetBuffer, 1)
		end

		self.LastOffset = self.ServerOffset
		local count = #self.ServerOffsetBuffer
		local sum = 0
		local taken = {}
		local total = ((count < 50) and count) or (count - 10)
		for i = 1, total do
			local smallestDiff, smallestIndex
			for j = 1, count do
				if not taken[j] then
					local diff = math.abs(self.ServerOffsetBuffer[j] - self.LastOffset)
					if (not smallestDiff) or (diff < smallestDiff) then
						smallestDiff = diff
						smallestIndex = j
					end
				end
			end
			taken[smallestIndex] = true
			sum += self.ServerOffsetBuffer[smallestIndex]
		end

		self.ServerOffset = sum / total
	end
else
	function module:PlayerAdded(player)
		self.TimeDelays[player] = 0
	end

	function module:PlayerRemoving(player)
		self.TimeDelays[player] = nil
	end

	function module:OnServerEvent(player, originalSentTick, processingDelay)
		if self.TimeDelays[player] then
			local roundTripTime = tick() - originalSentTick
			self.TimeDelays[player] = 0.5 * (roundTripTime - processingDelay)
		end
	end
end

function module:Heartbeat(step) --Hook this to runService.Heartbeat for proper operation.
	if isClient then
		self.ReplicationPressure = self.ReplicationPressure * 0.8 + (self.Tally / step) * 0.2
		self.Tally = 0

		if self.LastSentTick then
			if self.ReplicationPressure < self.Threshold then --We do not modify the serverOffset value when we are experiencing sufficiently high network load. This is also experienced on game join, so don't expect a synced time for the first few seconds upon joining.
				local currentTick = tick()
				local newOffsetValue = (self.LastSentTick + self.TimeDelay) - currentTick --Add current client tick to offset value to get the synced time, aka tick() of the server at that instant.

				self:AddOffsetValue(newOffsetValue)

				clockSyncSignal:FireServer(self.LastSentTick, currentTick - self.ReceiveTick)
			end
			self.LastSentTick = nil
		end
	else
		for _, player in ipairs(players:GetPlayers()) do
			if self.TimeDelays[player] then
				clockSyncSignal:FireAllClients(tick(), self.TimeDelays[player])
			end
		end
	end
end

function module:Initialize()
	runService.Heartbeat:connect(function(step)
		self:Heartbeat(step)
	end)

	if isClient then
		self.LastOffset = nil
		self.ServerOffset = 0

		self.ServerOffsetBuffer = {}
		self.LastSentTick = nil
		self.ReceiveTick = nil
		self.TimeDelay = nil

		self.Tally = 0
		self.ReplicationPressure = 0
		self.Threshold = 100

		clockSyncSignal.OnClientEvent:connect(function(...)
			self:OnClientEvent(...)
		end)

		game.DescendantAdded:connect(function()
			self.Tally += 1
		end)
	else
		self.TimeDelays = {}

		players.PlayerAdded:connect(function(player)
			self:PlayerAdded(player)
		end)

		players.PlayerRemoving:connect(function(player)
			self:PlayerRemoving(player)
		end)

		clockSyncSignal.OnServerEvent:connect(function(...)
			self:OnServerEvent(...)
		end)
	end
end

return module
