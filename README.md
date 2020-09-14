# Roblox-Client-Server-Time-Sync-Module

Syncs time between multiple clients and the server with accuracy of within 1 millisecond. Exploits patterns in Roblox networking, mainly how Roblox packages network requests into larger chunks every few frames, to determine a far greater accuracy for time syncing than what would otherwise be possible. Read more here: https://devforum.roblox.com/t/high-precision-clock-syncing-tech-between-clients-and-server-with-accuracy-of-1ms/769346

You can try out this module in a sample demonstration place here: https://www.roblox.com/games/5673596036/Client-Server-Clock-Sync-Tool?refPageId=52f40730-a656-4c57-b29f-ab4f521791de (note that it is uncopylocked, so you can see exactly how this module is meant to be used).

Validating accuracy:
Check out this video, pause and advance through it frame by frame, to observe the accuracy of this system: https://www.youtube.com/watch?v=YGYGRquqi-c
The window on the left is a virtual client, the window on the right is a virtual server. As you can see, the blue block on the server and the red block on the client are synced using this time sync module. On the client, you also see a copy of the blue block -- this is what Roblox replicates to the client; notice the ~20 ms delay in movement of that replicated blue block. By using this time sync module, the client and the server will see the exact same information happening at the exact same time, instead of the client seeing the server's information at a delay determined by the network latency.
