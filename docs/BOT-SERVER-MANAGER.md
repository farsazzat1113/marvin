# MARVIN Bot & Server Manager — implementation notes

## What this change contains
- An isolated Luau ModuleScript at `modules/BotServerManager.lua`.
- Three UI filters: All, Bot Servers, and Normal Servers.
- A session registry API: `SetSessions`, `UpsertSession`, `RemoveSession`.
- Optional callbacks for selecting a session, creating a bot configuration, and requesting start/stop actions.
- No changes to `UNKNOWN.lua`, Smart Join, Egg Finder, key validation, network endpoints, or existing settings.

## Important scope boundary
This module is a **UI and session-registry foundation**, not a Roblox account bot runner. A normal LocalScript cannot securely create/login to extra Roblox accounts or keep another player's client running after the user's device is off. Do not store Roblox passwords, session cookies, or authentication tokens in MARVIN. Do not automate public-game accounts in ways that violate Roblox Terms or game rules.

For a game experience you own, the supported path for autonomous characters is server-side NPC agents (Humanoids controlled by your server scripts). For authorized QA, use Roblox Studio test clients / approved test infrastructure and feed their status into this manager through an adapter you control.

## Installation (safe, isolated)
1. Keep the current `UNKNOWN.lua` and your backup unchanged.
2. In Roblox Studio, create a ModuleScript named `BotServerManager` and paste the contents of `modules/BotServerManager.lua`.
3. Create a ScreenGui/Frame in your own experience and require the module from a LocalScript:
   ```lua
   local BotServerManager = require(path.To.BotServerManager)
   local manager = BotServerManager.new({
       parent = script.Parent,
       onCreateBot = function()
           -- Open your own NPC/test-agent configuration screen here.
       end,
       onSelect = function(session)
           print("Selected session:", session.id)
       end,
       onStart = function(session)
           -- Call your authorized server-side NPC/test harness.
       end,
       onStop = function(session)
           -- Stop the NPC/test harness you own.
       end,
   })

   manager:SetSessions({
       { id = "npc-001", name = "Farm Helper", kind = "bot", status = "IDLE", detail = "NPC" },
       { id = "server-001", name = "Current server", kind = "normal", status = "CONNECTED" },
   })
   ```
4. Connect the callbacks to your own server-authoritative NPC/test-agent system. The client UI itself must not be treated as trusted authority.
5. Call `UpsertSession(session)` when a session changes and `RemoveSession(id)` when it ends.

## Session schema
```lua
{
    id = "stable-unique-id",
    name = "Display name",
    kind = "bot", -- or "normal"; set explicitly from trusted metadata
    placeId = 123, -- optional
    jobId = "server-job-id", -- optional
    status = "RUNNING", -- optional display state
    detail = "NPC / test client", -- optional
}
```

## Integration status
- [x] New isolated manager module committed on a feature branch.
- [x] Existing script left untouched.
- [ ] Wire the module into the existing MARVIN UI after its actual UI host/container and data contract are confirmed.
- [ ] Add a trusted backend/session adapter for permitted NPCs or QA sessions.
- [ ] Test in a private Roblox experience before any production rollout.

The existing Finder feed contains public server/egg discovery data; it does not by itself identify which server belongs to an independently authenticated bot account. The category must come from explicit trusted metadata, not guesses based on usernames or server names.
