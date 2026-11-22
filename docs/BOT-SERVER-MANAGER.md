# MARVIN Bot & Server Manager

This feature branch keeps the existing `UNKNOWN.lua` unchanged and adds an isolated server-manager UI plus an optional NPC adapter for Roblox experiences you own.

## Files
- `modules/BotServerManager.lua`: reusable UI and session registry.
- `examples/MARVINBotManager.client.lua`: client LocalScript example that displays the current server separately from NPC-agent sessions.
- `examples/MARVINBotAgent.server.lua`: server-side NPC agent adapter.
- This is **not** a separate Roblox account bot, and it does not create additional Roblox servers or log into accounts.

## Install in your own Roblox experience
1. In `ReplicatedStorage`, create a Folder named `Modules`.
2. Add a ModuleScript named `BotServerManager` and paste `modules/BotServerManager.lua`.
3. In `ServerStorage`, add a rig Model named `BotAgentTemplate`. It must contain a `Humanoid` and `HumanoidRootPart`.
4. Add `examples/MARVINBotAgent.server.lua` as a Script under `ServerScriptService`.
5. Add `examples/MARVINBotManager.client.lua` as a LocalScript under `StarterPlayer/StarterPlayerScripts`.
6. Publish/test in a private test place. The server adapter allows only the user who owns a user-owned experience. For a group-owned experience, replace `authorized()` with a group-role allowlist.

## What works
- Separate All / Bot Servers / Normal Servers filters.
- Current Roblox server appears as a normal session.
- Create, list, start, and stop server-controlled NPC agents.
- NPCs follow the owner in the experience; they are not independent accounts or separate servers.
- The client requests actions through a RemoteFunction; the server validates ownership and owns the NPC state.

## Limitations
- A normal Roblox LocalScript cannot create or authenticate extra Roblox accounts, run other clients after your device is off, or enumerate arbitrary public servers as logged-in bots.
- Do not put Roblox passwords, session cookies, or authentication tokens in the script.
- This example is a supported NPC/test-agent pattern for an experience you control. It does not automate or exploit another game's public servers.
- No changes were made to `UNKNOWN.lua`, Egg Finder, Smart Join, or the existing key flow.
