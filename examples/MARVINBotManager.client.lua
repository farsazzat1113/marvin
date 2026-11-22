-- MARVIN Bot Manager client example
-- Install as StarterPlayer > StarterPlayerScripts > LocalScript.
-- Requires ReplicatedStorage.Modules.BotServerManager and the server adapter below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("MARVINBotManager", 15)
assert(remote and remote:IsA("RemoteFunction"), "MARVINBotManager RemoteFunction missing")

local moduleFolder = ReplicatedStorage:WaitForChild("Modules")
local BotServerManager = require(moduleFolder:WaitForChild("BotServerManager"))

local gui = Instance.new("ScreenGui")
gui.Name = "MARVIN_ServerManager"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1200
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "ManagerPanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -18, 0.5, 0)
panel.Size = UDim2.new(0, 390, 0, 360)
panel.Parent = gui

local function invoke(action, payload)
    local ok, result = pcall(function()
        return remote:InvokeServer(action, payload)
    end)
    if not ok then
        warn("[MARVIN] Bot manager request failed:", result)
        return nil
    end
    if type(result) == "table" and result.ok == false then
        warn("[MARVIN] " .. tostring(result.error or "Request rejected"))
        return nil
    end
    return result
end

local manager
local function refresh()
    if not manager then return end
    local data = invoke("list")
    if type(data) ~= "table" then return end
    local sessions = {
        {
            id = "current-server",
            name = "Current Roblox server",
            kind = "normal",
            status = "CONNECTED",
            detail = "JobId: " .. string.sub(game.JobId, 1, 8),
            placeId = game.PlaceId,
            jobId = game.JobId,
        },
    }
    for _, item in ipairs(data) do
        table.insert(sessions, item)
    end
    manager:SetSessions(sessions)
end

manager = BotServerManager.new({
    parent = panel,
    onCreateBot = function()
        local result = invoke("create")
        if result and result.ok then
            refresh()
        end
    end,
    onStart = function(session)
        if session.kind == "bot" then
            invoke("start", { id = session.id })
            refresh()
        end
    end,
    onStop = function(session)
        if session.kind == "bot" then
            invoke("stop", { id = session.id })
            refresh()
        end
    end,
    onSelect = function(session)
        print("[MARVIN] Selected:", session.id, session.kind)
    end,
})

refresh()
task.spawn(function()
    while gui.Parent do
        task.wait(5)
        refresh()
    end
end)

gui.Destroying:Connect(function()
    if manager then manager:Destroy() end
end)
