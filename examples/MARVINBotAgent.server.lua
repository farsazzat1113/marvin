-- MARVIN NPC bot-agent server adapter (for an experience you own)
-- Install as ServerScriptService > Script.
-- Put an NPC Model named BotAgentTemplate in ServerStorage.
-- The model must contain a Humanoid and HumanoidRootPart.
-- This creates server-controlled NPC agents, NOT separate Roblox accounts/servers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local MAX_BOTS_PER_OWNER = 5
local botsById = {}

local remote = ReplicatedStorage:FindFirstChild("MARVINBotManager")
if not remote then
    remote = Instance.new("RemoteFunction")
    remote.Name = "MARVINBotManager"
    remote.Parent = ReplicatedStorage
end

local function authorized(player)
    -- User-owned experiences: only the experience creator can manage NPC agents.
    -- For group-owned experiences, replace this check with your own group-role allowlist.
    return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function countBots(ownerUserId)
    local count = 0
    for _, bot in pairs(botsById) do
        if bot.ownerUserId == ownerUserId then count += 1 end
    end
    return count
end

local function serialize(bot)
    return {
        id = bot.id,
        name = bot.name,
        kind = "bot",
        status = bot.running and "RUNNING" or "STOPPED",
        detail = "NPC agent",
        placeId = game.PlaceId,
        jobId = game.JobId,
    }
end

local function getBot(player, payload)
    if type(payload) ~= "table" or type(payload.id) ~= "string" then return nil end
    local bot = botsById[payload.id]
    if bot and bot.ownerUserId == player.UserId then return bot end
    return nil
end

local function spawnBot(player)
    if countBots(player.UserId) >= MAX_BOTS_PER_OWNER then
        return { ok = false, error = "Maximum of " .. MAX_BOTS_PER_OWNER .. " NPC agents reached." }
    end

    local template = ServerStorage:FindFirstChild("BotAgentTemplate")
    if not template or not template:IsA("Model") then
        return { ok = false, error = "Add a Model named BotAgentTemplate to ServerStorage." }
    end

    local character = player.Character
    local ownerRoot = character and character:FindFirstChild("HumanoidRootPart")
    if not ownerRoot then return { ok = false, error = "Your character is not ready." } end

    local npc = template:Clone()
    local humanoid = npc:FindFirstChildOfClass("Humanoid")
    local root = npc:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or not root:IsA("BasePart") then
        npc:Destroy()
        return { ok = false, error = "BotAgentTemplate needs Humanoid and HumanoidRootPart." }
    end

    local id = HttpService:GenerateGUID(false)
    npc.Name = "MARVIN_Bot_" .. string.sub(id, 1, 8)
    npc:PivotTo(ownerRoot.CFrame * CFrame.new(4, 0, 4))
    npc.Parent = workspace

    local bot = {
        id = id,
        name = npc.Name,
        ownerUserId = player.UserId,
        model = npc,
        running = true,
    }
    botsById[id] = bot

    task.spawn(function()
        while botsById[id] == bot and npc.Parent and humanoid.Health > 0 do
            if bot.running then
                local currentCharacter = player.Character
                local currentRoot = currentCharacter and currentCharacter:FindFirstChild("HumanoidRootPart")
                if currentRoot then
                    humanoid:MoveTo(currentRoot.Position + currentRoot.CFrame.RightVector * 4)
                end
            end
            task.wait(2)
        end
        if botsById[id] == bot then
            botsById[id] = nil
        end
    end)

    return { ok = true, session = serialize(bot) }
end

remote.OnServerInvoke = function(player, action, payload)
    if not authorized(player) then
        return { ok = false, error = "Only the experience owner can manage these NPC agents." }
    end

    if action == "list" then
        local result = {}
        for _, bot in pairs(botsById) do
            if bot.ownerUserId == player.UserId and bot.model and bot.model.Parent then
                table.insert(result, serialize(bot))
            end
        end
        return result
    elseif action == "create" then
        return spawnBot(player)
    elseif action == "start" then
        local bot = getBot(player, payload)
        if not bot or not bot.model or not bot.model.Parent then
            return { ok = false, error = "NPC agent not found." }
        end
        bot.running = true
        return { ok = true }
    elseif action == "stop" then
        local bot = getBot(player, payload)
        if not bot then return { ok = false, error = "NPC agent not found." } end
        bot.running = false
        local humanoid = bot.model:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:MoveTo(bot.model:GetPivot().Position) end
        return { ok = true }
    end

    return { ok = false, error = "Unknown action." }
end

Players.PlayerRemoving:Connect(function(player)
    for id, bot in pairs(botsById) do
        if bot.ownerUserId == player.UserId then
            if bot.model then bot.model:Destroy() end
            botsById[id] = nil
        end
    end
end)
