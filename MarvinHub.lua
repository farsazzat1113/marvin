--[[
    👑 MARVIN HUB - Official Universal Script Loader
    Repository: farsazzat1113/marvin
    Key System & Web Portal: https://farsazzat1113.github.io/marvin/
    Execution: loadstring(game:HttpGet("https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/MarvinHub.lua"))()
--]]

local SCRIPT_NAME = "MARVIN VIP HUB"
local VERSION = "v2.4"

local CANDIDATE_URLS = {
    "https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/UNKNOWN.obfuscated.lua",
    "https://raw.githubusercontent.com/farsazzat1113/marvin/main/UNKNOWN.obfuscated.lua",
    "https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/UNKNOWN.lua",
    "https://raw.githubusercontent.com/farsazzat1113/marvin/main/UNKNOWN.lua"
}

print("--------------------------------------------------")
print(string.format("👑 [%s] Loading %s...", SCRIPT_NAME, VERSION))
print("👑 Portal: https://farsazzat1113.github.io/marvin/")
print("--------------------------------------------------")

-- Ensure game context is loaded
local gameId = game.GameId
while gameId == 0 and game.PlaceId == 0 do
    task.wait()
    gameId = game.GameId
end

local function fetchScript()
    for _, url in ipairs(CANDIDATE_URLS) do
        for attempt = 1, 2 do
            local ok, source = pcall(game.HttpGet, game, url .. "?t=" .. tostring(os.time()), true)
            if ok and type(source) == "string" and #source > 100 then
                local chunk, loadErr = loadstring(source)
                if chunk then
                    return chunk
                else
                    warn(string.format("[%s] Compile error on %s: %s", SCRIPT_NAME, url, tostring(loadErr)))
                end
            end
            task.wait(0.3)
        end
    end
    return nil
end

local chunk = fetchScript()
if chunk then
    print(string.format("👑 [%s] Initialized successfully!", SCRIPT_NAME))
    chunk()
else
    warn(string.format("❌ [%s] Failed to download script. Please check your internet connection or executor HTTP permissions.", SCRIPT_NAME))
end
