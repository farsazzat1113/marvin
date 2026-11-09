-- ==========================================
-- MARVIN | Key Gate System (Lightweight)
-- ==========================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return end

local VERIFY_URL = "https://unknown.unknownsystem.workers.dev/validate" -- رابط التحقق الخاص بك

local function launchMarvin()
    local runtimeEnv = _G
    pcall(function() if type(getgenv) == "function" then runtimeEnv = getgenv() end end)
    if type(runtimeEnv) == "table" then
        if runtimeEnv["__MARVIN_RUNNING_JOB"] == game.JobId then return end
        runtimeEnv["__MARVIN_RUNNING_JOB"] = game.JobId
    end
    -- هنا يتم تشغيل السكربت الأصلي الخاص بك
    pcall(function() loadstring(game:HttpGet("https://raw.githubusercontent.com/mostafaezzatrqm700-droid/UNKNOWN/UNKNOWN/UNKNOWN.lua"))() end)
end

local function httpRequest(options)
    local req = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
    if type(req) == "function" then return req(options) end
    error("MARVIN: Executor HTTP not supported.")
end

-- إنشاء الواجهة
local gui = Instance.new("ScreenGui")
gui.Name = "MARVIN_KeySystem"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(320, 190)
frame.Position = UDim2.new(0.5, -160, 0.5, -95)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 25) -- لون داكن فخم
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 215, 0) -- حدود ذهبية
stroke.Thickness = 2

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 40)
title.Position = UDim2.fromOffset(10, 5)
title.BackgroundTransparency = 1
title.Text = "👑 MARVIN"
title.TextColor3 = Color3.fromRGB(255, 215, 0) -- نص ذهبي
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.TextStrokeColor3 = Color3.fromRGB(180, 140, 0)
title.TextStrokeTransparency = 0.4
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -20, 0, 20)
subtitle.Position = UDim2.fromOffset(10, 40)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Enter your access key to continue"
subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.Parent = frame

local keyBox = Instance.new("TextBox")
keyBox.Size = UDim2.new(1, -30, 0, 36)
keyBox.Position = UDim2.fromOffset(15, 70)
keyBox.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
keyBox.BorderSizePixel = 0
keyBox.PlaceholderText = "MARVIN-XXXX-XXXX"
keyBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
keyBox.TextColor3 = Color3.fromRGB(255, 255, 255)
keyBox.Font = Enum.Font.GothamBold
keyBox.TextSize = 14
keyBox.ClearTextOnFocus = false
keyBox.Parent = frame
Instance.new("UICorner", keyBox).CornerRadius = UDim.new(0, 6)

local verifyButton = Instance.new("TextButton")
verifyButton.Size = UDim2.new(1, -30, 0, 36)
verifyButton.Position = UDim2.fromOffset(15, 115)
verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- زر ذهبي
verifyButton.BorderSizePixel = 0
verifyButton.Text = "VERIFY KEY"
verifyButton.TextColor3 = Color3.fromRGB(0, 0, 0) -- نص أسود للتباين
verifyButton.Font = Enum.Font.GothamBold
verifyButton.TextSize = 14
verifyButton.Parent = frame
Instance.new("UICorner", verifyButton).CornerRadius = UDim.new(0, 6)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -30, 0, 20)
status.Position = UDim2.fromOffset(15, 160)
status.BackgroundTransparency = 1
status.Text = "Waiting for key..."
status.TextColor3 = Color3.fromRGB(180, 180, 180)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame

local busy = false
local function setStatus(msg, color)
    status.Text = msg
    status.TextColor3 = color or Color3.fromRGB(180, 180, 180)
end

local function verifyKey()
    if busy then return end
    local key = keyBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then
        setStatus("⚠️ Please enter your key.", Color3.fromRGB(255, 170, 0))
        return
    end

    busy = true
    verifyButton.Text = "CHECKING..."
    verifyButton.BackgroundColor3 = Color3.fromRGB(200, 170, 0)
    setStatus("🔄 Checking with server...", Color3.fromRGB(255, 255, 255))

    local ok, response = pcall(function()
        return httpRequest({
            Url = VERIFY_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({ key = key })
        })
    end)

    if not ok or type(response) ~= "table" then
        setStatus("❌ Connection failed. Check executor.", Color3.fromRGB(255, 80, 80))
        verifyButton.Text = "VERIFY KEY"
        verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        busy = false
        return
    end

    local body = response.Body or response.body or ""
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(body) end)

    if not decodedOk or type(data) ~= "table" or data.valid ~= true then
        local reason = (decodedOk and type(data.reason) == "string") and data.reason or "Invalid or revoked key."
        setStatus("❌ " .. reason, Color3.fromRGB(255, 80, 80))
        verifyButton.Text = "VERIFY KEY"
        verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        busy = false
        return
    end

    -- حفظ المفتاح محلياً
    if type(writefile) == "function" then
        pcall(function() writefile("marvin_saved_key.txt", key) end)
    end

    setStatus("✅ Key accepted! Loading MARVIN...", Color3.fromRGB(80, 255, 120))
    verifyButton.Text = "ACCEPTED"
    verifyButton.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
    
    task.delay(0.5, function()
        gui:Destroy()
        launchMarvin()
    end)
end

verifyButton.MouseButton1Click:Connect(verifyKey)
keyBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then verifyKey() end
end)

-- تحميل المفتاح المحفوظ تلقائياً
if type(readfile) == "function" then
    local savedKey
    pcall(function() savedKey = readfile("marvin_saved_key.txt") end)
    if type(savedKey) == "string" and savedKey:gsub("%s+", "") ~= "" then
        keyBox.Text = savedKey
        task.defer(verifyKey)
    end
end
