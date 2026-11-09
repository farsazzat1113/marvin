-- ===== UNKNOWN | Golden Crown Key Gate =====
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
if not player then return end

local VERIFY_URL = "https://unknown.unknownsystem.workers.dev/validate"

local function launchUnknown()
    local runtimeEnv = _G
    pcall(function() if type(getgenv) == "function" then runtimeEnv = getgenv() end end)
    if type(runtimeEnv) == "table" then
        local runningJob = "__UNKNOWN_RUNNING_JOB"
        if runtimeEnv[runningJob] == game.JobId then return end
        runtimeEnv[runningJob] = game.JobId
    end
    pcall(startUnknown)
end

local function httpRequest(options)
    local req = request or http_request or (syn and syn.request) or (fluxus and fluxus.request)
    if type(req) == "function" then return req(options) end
    error("HTTP غير متاح في هذا الـ executor")
end

-- إنشاء الواجهة
local gui = Instance.new("ScreenGui")
gui.Name = "UNKNOWN_KeySystem"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true

local parent
pcall(function() parent = gethui() end)
if not parent then parent = player:WaitForChild("PlayerGui", 15) or player:FindFirstChild("PlayerGui") end
if not parent then return end
gui.Parent = parent

-- الإطار الرئيسي (ثيم ذهبي)
local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(340, 205)
frame.Position = UDim2.new(0.5, -170, 0.5, -102)
frame.BackgroundColor3 = Color3.fromRGB(20, 15, 10)  -- أسود/بني داكن
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(255, 215, 0)  -- ذهبي
stroke.Thickness = 2

local gradient = Instance.new("UIGradient", frame)
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 15, 10)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 30, 15))
})
gradient.Rotation = 135

-- العنوان
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 38)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.Text = "👑 UNKNOWN"
title.TextColor3 = Color3.fromRGB(255, 215, 0)  -- ذهبي
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextStrokeColor3 = Color3.fromRGB(180, 140, 40)
title.TextStrokeTransparency = 0.4
title.Parent = frame

-- العنوان الفرعي
local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -24, 0, 22)
subtitle.Position = UDim2.fromOffset(12, 43)
subtitle.BackgroundTransparency = 1
subtitle.Text = "أدخل مفتاح الوصول للمتابعة"
subtitle.TextColor3 = Color3.fromRGB(200, 180, 140)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.Parent = frame

-- صندوق المفتاح
local keyBox = Instance.new("TextBox")
keyBox.Size = UDim2.new(1, -32, 0, 40)
keyBox.Position = UDim2.fromOffset(16, 77)
keyBox.BackgroundColor3 = Color3.fromRGB(35, 25, 15)
keyBox.BorderSizePixel = 0
keyBox.PlaceholderText = "TF-..."
keyBox.PlaceholderColor3 = Color3.fromRGB(120, 100, 70)
keyBox.Text = ""
keyBox.TextColor3 = Color3.fromRGB(255, 245, 220)
keyBox.Font = Enum.Font.GothamBold
keyBox.TextSize = 14
keyBox.ClearTextOnFocus = false
keyBox.Parent = frame

Instance.new("UICorner", keyBox).CornerRadius = UDim.new(0, 7)
local boxStroke = Instance.new("UIStroke", keyBox)
boxStroke.Color = Color3.fromRGB(255, 215, 0)
boxStroke.Thickness = 1
boxStroke.Transparency = 0.5

-- زر التحقق
local verifyButton = Instance.new("TextButton")
verifyButton.Size = UDim2.new(1, -32, 0, 36)
verifyButton.Position = UDim2.fromOffset(16, 128)
verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)  -- ذهبي
verifyButton.BorderSizePixel = 0
verifyButton.Text = "VERIFY KEY"
verifyButton.TextColor3 = Color3.fromRGB(20, 15, 10)  -- داكن للتباين
verifyButton.Font = Enum.Font.GothamBold
verifyButton.TextSize = 13
verifyButton.Parent = frame

Instance.new("UICorner", verifyButton).CornerRadius = UDim.new(0, 7)
local btnStroke = Instance.new("UIStroke", verifyButton)
btnStroke.Color = Color3.fromRGB(255, 200, 50)
btnStroke.Thickness = 1

-- تأثير Hover
verifyButton.MouseEnter:Connect(function()
    TweenService:Create(verifyButton, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(255, 230, 80)
    }):Play()
end)
verifyButton.MouseLeave:Connect(function()
    TweenService:Create(verifyButton, TweenInfo.new(0.15), {
        BackgroundColor3 = Color3.fromRGB(255, 215, 0)
    }):Play()
end)

-- حالة
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -32, 0, 22)
status.Position = UDim2.fromOffset(16, 168)
status.BackgroundTransparency = 1
status.Text = "في انتظار المفتاح..."
status.TextColor3 = Color3.fromRGB(200, 180, 140)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = frame

local busy = false
local function setStatus(msg, color)
    status.Text = msg
    status.TextColor3 = color or Color3.fromRGB(200, 180, 140)
end

local function verifyKey()
    if busy then return end
    local key = keyBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then
        setStatus("⚠️ أدخل المفتاح أولاً", Color3.fromRGB(255, 190, 90))
        return
    end

    busy = true
    verifyButton.Text = "جاري التحقق..."
    verifyButton.BackgroundColor3 = Color3.fromRGB(200, 170, 50)
    setStatus("🔍 الاتصال بالخادم...", Color3.fromRGB(255, 245, 220))

    local ok, response = pcall(function()
        return httpRequest({
            Url = VERIFY_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({key = key, hwid = HttpService:GenerateGUID(false)})
        })
    end)

    if not ok or type(response) ~= "table" then
        setStatus("❌ فشل الاتصال - تحقق من الـ executor", Color3.fromRGB(255, 80, 80))
        verifyButton.Text = "VERIFY KEY"
        verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        busy = false
        task.delay(2.5, function() if verifyButton.Text ~= "ACCEPTED" then setStatus("في انتظار المفتاح...") end end)
        return
    end

    local statusCode = tonumber(response.StatusCode or response.Status)
    local body = response.Body or response.body or ""

    if statusCode ~= 200 then
        setStatus("❌ خطأ من الخادم (" .. tostring(statusCode) .. ")", Color3.fromRGB(255, 80, 80))
        verifyButton.Text = "VERIFY KEY"
        verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        busy = false
        task.delay(2.5, function() if verifyButton.Text ~= "ACCEPTED" then setStatus("في انتظار المفتاح...") end end)
        return
    end

    local decodedOk, data = pcall(function() return HttpService:JSONDecode(body) end)

    if not decodedOk or type(data) ~= "table" or data.valid ~= true then
        local reason = "مفتاح غير صالح أو منتهي"
        if decodedOk and type(data.reason) == "string" then
            if data.reason == "expired" then reason = "⏰ المفتاح منتهي الصلاحية"
            elseif data.reason == "invalid" then reason = "❌ صيغة المفتاح خاطئة"
            else reason = "⚠️ " .. data.reason end
        end
        setStatus(reason, Color3.fromRGB(255, 80, 80))
        verifyButton.Text = "VERIFY KEY"
        verifyButton.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
        busy = false
        task.delay(2.5, function() if verifyButton.Text ~= "ACCEPTED" then setStatus("في انتظار المفتاح...") end end)
        return
    end

    -- نجاح!
    if type(writefile) == "function" then
        pcall(function() writefile("unknown_saved_access_key.txt", key) end)
    end

    setStatus("✅ تم القبول! جاري التحميل...", Color3.fromRGB(80, 255, 120))
    verifyButton.Text = "✓ ACCEPTED"
    verifyButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
    verifyButton.TextColor3 = Color3.fromRGB(255, 255, 255)

    task.delay(0.5, function()
        gui:Destroy()
        launchUnknown()
    end)
end

verifyButton.MouseButton1Click:Connect(verifyKey)
keyBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then verifyKey() end
end)

-- تحميل المفتاح المحفوظ
if type(readfile) == "function" then
    local savedKey
    pcall(function() savedKey = readfile("unknown_saved_access_key.txt") end)
    if type(savedKey) == "string" and savedKey:gsub("%s+", "") ~= "" then
        keyBox.Text = savedKey
        task.defer(verifyKey)
    end
end
