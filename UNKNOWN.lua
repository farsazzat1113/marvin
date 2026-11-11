--================================================================================================--
-- UNKNOWN · Public v0.5.0 / UI21 "Obsidian"
-- Single-file client. Grounded walking only; no character CFrame/Position/PivotTo writes.
-- [1] Pure policy + bounded tasks   [2] Obsidian UI   [3] Ground navigation / traps
-- [4] Perks / steal state machine   [5] Finder feed / join / broadcast
-- [6] Replicated scanner           [7] Key session
-- A first launch always needs valid=true. A recent, one-hop validated session may start
-- immediately on the destination while its key is revalidated in the background.
--================================================================================================--

local BUILD = {
    name = 'UI21 · Obsidian',
    -- Publish this build to Marvin (or override UNKNOWN_SCRIPT_URL before execution).
    sourceUrl = 'https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/UNKNOWN.lua?v=ui21',
    verifyUrl = 'https://unknown.unknownsystem.workers.dev/validate',
    sessionKey = 'UNKNOWNValidatedHopV1',
    joinedKey = 'UNKNOWNJoinedEggV1',
}
local function environment()
    local env = _G
    pcall(function()
        if type(getgenv) == 'function' then
            local candidate = getgenv()
            if type(candidate) == 'table' then env = candidate end
        end
    end)
    return env
end

-- BEGIN POLICY (also executed directly by tests; no Roblox services or HTTP)
local Policy = {}
function Policy.finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < math.huge
end
function Policy.number(value, fallback, low, high)
    return Policy.finite(value) and math.clamp(value, low, high) or fallback
end
function Policy.backoff(attempt, base, cap)
    return math.min(cap, base * 2 ^ math.clamp(attempt - 1, 0, 8))
end
function Policy.id(entry)
    return tostring(entry.placeId or '') .. ':' .. tostring(entry.jobId or '') .. ':' .. tostring(entry.uid or '')
end
function Policy.remoteEligible(entry, now, currentJob, minRate, minRank)
    return type(entry) == 'table' and type(entry.jobId) == 'string' and entry.jobId ~= ''
        and entry.jobId ~= currentJob and Policy.finite(entry.placeId) and entry.placeId > 0
        and entry.placeId % 1 == 0 and entry.uid ~= nil and tostring(entry.uid) ~= ''
        and Policy.finite(entry.expiresAt) and entry.expiresAt > now
        and Policy.finite(entry.rate) and entry.rate >= minRate
        and Policy.number(entry.rank or entry.localTier, 0, 0, 100) >= minRank
        and entry.full ~= true and entry.unavailable ~= true and entry.takenConfirmed ~= true
        and entry.source ~= 'event'
end
function Policy.joinDeadline(entry, claim)
    local expiry = Policy.finite(entry.expiresAt) and entry.expiresAt or 0
    if Policy.finite(claim.expiresAt) then expiry = math.min(expiry, claim.expiresAt) end
    return expiry
end
function Policy.webhook(value)
    if type(value) ~= 'string' then return nil end
    local url = value:match('^%s*(.-)%s*$'):gsub('%?wait=true$', '')
    local host, id, token = url:match('^https://([^/]+)/api/webhooks/(%d+)/([%w%._%-]+)$')
    if not host or (host:lower() ~= 'discord.com' and host:lower() ~= 'discordapp.com')
        or #id < 17 or #id > 25 or #token < 20 or #token > 200 then return nil end
    return 'https://' .. host:lower() .. '/api/webhooks/' .. id .. '/' .. token
end
function Policy.resume(session, key, placeId, jobId, now)
    return type(session) == 'table' and session.version == 1 and type(key) == 'string' and key ~= ''
        and session.key == key and session.placeId == placeId and session.jobId == jobId
        and type(session.fromJob) == 'string' and session.fromJob ~= jobId
        and Policy.finite(session.verifiedAt) and session.verifiedAt <= now + 5
        and now - session.verifiedAt <= 120 and Policy.finite(session.hopAt)
        and session.hopAt <= now + 5 and now - session.hopAt <= 45
        and (session.expiresAt == nil or Policy.finite(session.expiresAt) and session.expiresAt > now)
end
function Policy.carryUid(carry)
    if type(carry) ~= 'table' then return nil end
    local uid = carry.Uid or carry.EggUid or carry.CarriedUid or carry.CarryingUid
    if type(carry.Egg) == 'table' then uid = uid or carry.Egg.Uid end
    return uid ~= nil and tostring(uid) or nil
end
-- Closed slab intersection in a hitbox's own axes. Padding includes the avatar's
-- radius + a safety margin; unlike an XZ point check this catches thin/rotated traps.
function Policy.segmentHitsBox(a, b, frame, size, padding)
    local p, q = frame:PointToObjectSpace(a), frame:PointToObjectSpace(b)
    local half = size * 0.5 + padding
    local low, high = 0, 1
    for _, axis in ipairs({'X', 'Y', 'Z'}) do
        local origin, delta, extent = p[axis], q[axis] - p[axis], half[axis]
        if math.abs(delta) < 1e-7 then
            if math.abs(origin) > extent then return false end
        else
            local first, last = (-extent - origin) / delta, (extent - origin) / delta
            if first > last then first, last = last, first end
            low, high = math.max(low, first), math.min(high, last)
            if low > high then return false end
        end
    end
    return true
end
-- END POLICY

-- Timeouts own their worker, not a global network lock. Late results are ignored.
local function boundedCall(timeout, live, callback)
    if not live() then return false, 'cancelled' end
    local done, result = false, nil
    local worker = task.spawn(function()
        result = table.pack(pcall(callback))
        done = true
    end)
    local deadline = os.clock() + timeout
    while not done and live() and os.clock() < deadline do task.wait() end
    if not done or not live() then
        pcall(task.cancel, worker)
        return false, live() and 'timeout' or 'cancelled'
    end
    return table.unpack(result, 1, result.n)
end

local Palette = {
    bg = Color3.fromRGB(12, 15, 20), surface = Color3.fromRGB(22, 27, 34),
    raised = Color3.fromRGB(31, 38, 47), line = Color3.fromRGB(54, 64, 76),
    text = Color3.fromRGB(241, 239, 232), muted = Color3.fromRGB(146, 158, 172),
    accent = Color3.fromRGB(224, 199, 147), teal = Color3.fromRGB(102, 224, 196),
    danger = Color3.fromRGB(255, 113, 130),
    rarity = {
        divine = Color3.fromRGB(255, 211, 111), eternal = Color3.fromRGB(198, 177, 255),
        secret = Color3.fromRGB(226, 242, 255), cosmic = Color3.fromRGB(165, 136, 255),
        mythic = Color3.fromRGB(255, 108, 141), legendary = Color3.fromRGB(255, 179, 102),
        epic = Color3.fromRGB(223, 141, 243), rare = Color3.fromRGB(104, 181, 255),
        uncommon = Color3.fromRGB(126, 219, 158), common = Color3.fromRGB(175, 189, 204),
    },
}
local Kit = {}
function Kit.z(parent) return parent:IsA('GuiObject') and parent.ZIndex + 1 or 2 end
function Kit.make(class, props, parent)
    local obj = Instance.new(class)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = parent
    return obj
end
function Kit.round(obj, radius)
    Kit.make('UICorner', {CornerRadius = UDim.new(0, radius or 14)}, obj)
end
function Kit.stroke(obj, color, transparency, thickness)
    return Kit.make('UIStroke', {Color = color or Palette.line, Transparency = transparency or 0,
        Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, obj)
end
function Kit.text(parent, text, pos, size, color, fontSize)
    return Kit.make('TextLabel', {Text = text, Position = pos, Size = size, BackgroundTransparency = 1,
        TextColor3 = color or Palette.text, Font = Enum.Font.GothamMedium, TextSize = fontSize or 14,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        BorderSizePixel = 0, ZIndex = Kit.z(parent)}, parent)
end
function Kit.button(parent, text, pos, size)
    local button = Kit.make('TextButton', {Text = text, Position = pos, Size = size,
        BackgroundColor3 = Palette.raised, BorderSizePixel = 0, TextColor3 = Palette.text,
        Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = false, ZIndex = Kit.z(parent)}, parent)
    Kit.round(button, 12)
    return button
end
function Kit.input(parent, placeholder, pos, size)
    local input = Kit.make('TextBox', {Text = '', PlaceholderText = placeholder, Position = pos, Size = size,
        BackgroundColor3 = Palette.bg, BorderSizePixel = 0, TextColor3 = Palette.text,
        PlaceholderColor3 = Palette.muted, Font = Enum.Font.GothamMedium, TextSize = 14,
        ClearTextOnFocus = false, ZIndex = Kit.z(parent)}, parent)
    Kit.round(input, 12); Kit.stroke(input, Palette.line)
    Kit.make('UIPadding', {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, input)
    return input
end

-- [2] OBSIDIAN · bottom-anchored, thumb-sized controls; no downloaded UI assets.
local function createObsidianUI(D, settings, actions)
    local ui = {active = true, cards = {}, tweens = {}, pressed = {}, connections = {}, visible = true}
    local Input, Tweens, Run = game:GetService('UserInputService'), game:GetService('TweenService'), game:GetService('RunService')
    local function animate(obj, properties, duration)
        if ui.tweens[obj] then ui.tweens[obj]:Cancel() end
        if settings.reducedMotion then
            for key, value in pairs(properties) do obj[key] = value end
            return
        end
        local tween = Tweens:Create(obj, TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), properties)
        ui.tweens[obj] = tween
        tween.Completed:Once(function() if ui.tweens[obj] == tween then ui.tweens[obj] = nil end end)
        tween:Play()
    end
    local function motion(button)
        local scale = Kit.make('UIScale', {Scale = 1}, button)
        button.InputBegan:Connect(function(input)
            if not button.Active then return end
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                ui.pressed[button] = {input = input, scale = scale}
                animate(scale, {Scale = 0.975}, 0.1)
            end
        end)
        button.Destroying:Connect(function()
            ui.pressed[button] = nil
            if ui.tweens[scale] then ui.tweens[scale]:Cancel(); ui.tweens[scale] = nil end
        end)
    end
    local panel = Kit.make('Frame', {Name = 'ObsidianPanel', AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -12, 1, -12), Size = UDim2.fromOffset(402, 690),
        BackgroundTransparency = 1, BorderSizePixel = 0}, D.gui)
    ui.panel = panel
    ui.scale = Kit.make('UIScale', {Scale = 1}, panel)
    local shadow = Kit.make('Frame', {Name = 'SoftEdge', Size = UDim2.new(1, 8, 1, 8),
        Position = UDim2.fromOffset(-4, -4), BackgroundTransparency = 1, ZIndex = 1}, panel)
    Kit.round(shadow, 25); Kit.stroke(shadow, Palette.accent, 0.92, 7)
    local surface = Kit.make('CanvasGroup', {Name = 'Surface', Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Palette.bg, BorderSizePixel = 0, GroupTransparency = 0, ZIndex = 2}, panel)
    Kit.round(surface, 22); Kit.stroke(surface, Palette.line, 0.25)
    Kit.make('UIGradient', {Rotation = 100, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(195, 202, 212))}, surface)
    local monogram = Kit.text(surface, 'U', UDim2.fromOffset(18, 15), UDim2.fromOffset(38, 38), Palette.accent, 25)
    monogram.Font = Enum.Font.GothamBlack; monogram.TextXAlignment = Enum.TextXAlignment.Center
    monogram.BackgroundColor3 = Palette.surface; monogram.BackgroundTransparency = 0
    Kit.round(monogram, 11); Kit.stroke(monogram, Palette.accent, 0.7)
    local heading = Kit.text(surface, 'UNKNOWN', UDim2.fromOffset(68, 15), UDim2.new(1, -146, 0, 23), Palette.text, 20)
    heading.Font = Enum.Font.GothamBold
    ui.status = Kit.text(surface, 'LIVE EGG INTELLIGENCE', UDim2.fromOffset(68, 40), UDim2.new(1, -146, 0, 17), Palette.muted, 10)
    ui.resetTimer = Kit.text(surface, 'RESET --:--', UDim2.fromOffset(20, 68), UDim2.new(1, -92, 0, 18), Palette.muted, 11)
    ui.refresh = Kit.button(surface, '↻', UDim2.new(1, -68, 0, 14), UDim2.fromOffset(50, 52))
    ui.refresh.Name = 'Refresh'; ui.refresh.TextSize = 25; motion(ui.refresh)
    ui.feedCount = Kit.text(surface, 'SHARED FEED', UDim2.new(0.5, 0, 0, 68), UDim2.new(0.5, -20, 0, 18), Palette.teal, 10)
    ui.feedCount.TextXAlignment = Enum.TextXAlignment.Right
    ui.list = Kit.make('ScrollingFrame', {Name = 'EggFeed', Position = UDim2.fromOffset(12, 96),
        Size = UDim2.new(1, -24, 1, -274), BackgroundTransparency = 1, BorderSizePixel = 0,
        CanvasSize = UDim2.new(), ScrollBarThickness = 3, ScrollBarImageColor3 = Palette.accent,
        ScrollBarImageTransparency = 0.35, ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable, ZIndex = 4}, surface)
    Kit.make('UIListLayout', {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, ui.list)
    Kit.make('UIPadding', {PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3)}, ui.list)
    ui.empty = Kit.text(ui.list, 'Reading field eggs…', UDim2.new(), UDim2.new(1, -8, 0, 84), Palette.muted, 13)
    ui.empty.TextWrapped = true; ui.empty.TextXAlignment = Enum.TextXAlignment.Center

    local dock = Kit.make('Frame', {Name = 'ThumbDock', AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 172), BackgroundColor3 = Palette.surface,
        BorderSizePixel = 0, ZIndex = 8}, surface)
    Kit.round(dock, 20)
    ui.phase = Kit.text(dock, '●  READY', UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 18), Palette.teal, 11)
    ui.summary = Kit.text(dock, '', UDim2.fromOffset(16, 30), UDim2.new(1, -32, 0, 16), Palette.muted, 10)
    local tabs = Kit.make('Frame', {Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 48),
        BackgroundColor3 = Palette.bg, BorderSizePixel = 0, ZIndex = 9}, dock)
    Kit.round(tabs, 12)
    ui.scope = Kit.button(tabs, 'ALL SERVERS', UDim2.fromOffset(3, 0), UDim2.new(0.5, -5, 1, 0))
    ui.myScope = Kit.button(tabs, 'MY SERVER', UDim2.new(0.5, 2, 0, 0), UDim2.new(0.5, -5, 1, 0))
    for _, button in ipairs({ui.scope, ui.myScope}) do motion(button) end
    ui.autoJoin = Kit.button(dock, 'AUTO JOIN · OFF', UDim2.new(0, 12, 1, -64), UDim2.new(1, -108, 0, 56))
    ui.settingsButton = Kit.button(dock, 'SETTINGS', UDim2.new(1, -88, 1, -64), UDim2.fromOffset(76, 56))
    ui.settingsButton.TextSize = 10
    motion(ui.autoJoin); motion(ui.settingsButton)

    local launcher = Kit.button(D.gui, 'U', UDim2.new(1, -76, 1, -76), UDim2.fromOffset(62, 62))
    launcher.Name = 'UNKNOWNLauncher'; launcher.Font = Enum.Font.GothamBlack; launcher.TextSize = 26
    launcher.TextColor3 = Palette.accent; launcher.BackgroundColor3 = Palette.bg
    Kit.stroke(launcher, Palette.accent, 0.3, 1.5); motion(launcher)
    ui.launcher = launcher; launcher.Visible = false
    local visibilitySerial = 0
    function ui:setVisible(value)
        self.visible = value; visibilitySerial += 1
        local serial = visibilitySerial
        if value then panel.Visible = true; launcher.Visible = false end
        animate(surface, {GroupTransparency = value and 0 or 1}, 0.22)
        if not value then
            launcher.Visible = true
            task.delay(settings.reducedMotion and 0 or 0.22, function()
                if self.active and serial == visibilitySerial then panel.Visible = false end
            end)
        end
    end
    launcher.Activated:Connect(function() ui:setVisible(true) end)
    local minimize = Kit.button(surface, '−', UDim2.new(1, -124, 0, 14), UDim2.fromOffset(48, 52))
    minimize.TextSize = 23; heading.Size = UDim2.new(1, -198, 0, 23); ui.status.Size = UDim2.new(1, -198, 0, 17)
    motion(minimize); minimize.Activated:Connect(function() ui:setVisible(false) end)

    -- A full-height scrollable settings sheet, with the close action in the thumb zone.
    local sheet = Kit.make('Frame', {Name = 'SettingsSheet', Visible = false, Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Palette.bg, BorderSizePixel = 0, ZIndex = 40}, surface)
    Kit.round(sheet, 22)
    Kit.text(sheet, 'Make it yours.', UDim2.fromOffset(20, 20), UDim2.new(1, -40, 0, 30), Palette.text, 23).Font = Enum.Font.GothamBold
    Kit.text(sheet, 'CONTROL / MOVEMENT / NOTIFICATIONS', UDim2.fromOffset(20, 53), UDim2.new(1, -40, 0, 16), Palette.muted, 9)
    local scroll = Kit.make('ScrollingFrame', {Position = UDim2.fromOffset(14, 84), Size = UDim2.new(1, -28, 1, -190),
        BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = Palette.accent, ZIndex = 41}, sheet)
    Kit.make('UIListLayout', {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
    Kit.make('UIPadding', {PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 5)}, scroll)
    local order = 0
    local function row(height)
        order += 1
        local frame = Kit.make('Frame', {Size = UDim2.new(1, -4, 0, height), BackgroundColor3 = Palette.surface,
            BorderSizePixel = 0, LayoutOrder = order, ZIndex = 42}, scroll)
        Kit.round(frame, 14)
        return frame
    end
    local toggles = {}
    local function toggle(key, title, hint)
        local frame = row(76)
        Kit.text(frame, title, UDim2.fromOffset(14, 12), UDim2.new(1, -102, 0, 22), Palette.text, 13)
        local description = Kit.text(frame, hint, UDim2.fromOffset(14, 37), UDim2.new(1, -102, 0, 28), Palette.muted, 10)
        description.TextWrapped = true
        local button = Kit.button(frame, '', UDim2.new(1, -84, 0, 10), UDim2.fromOffset(72, 56))
        local function paint()
            button.Text = settings[key] and 'ON' or 'OFF'
            button.BackgroundColor3 = settings[key] and Palette.teal or Palette.raised
            button.TextColor3 = settings[key] and Palette.bg or Palette.muted
        end
        motion(button); paint(); toggles[key] = paint
        button.Activated:Connect(function() actions.change(key, not settings[key]); paint() end)
    end
    toggle('autoExecute', 'Auto execute', 'Run again after a server hop')
    toggle('autoSteal', 'Auto steal', 'Tracked egg → grounded route → home')
    toggle('speedBoost', 'Speed boost', 'Manual play only; paused during a route')
    toggle('infiniteJump', 'Infinite jump', 'Jump button; paused during a route')
    toggle('reducedMotion', 'Reduce motion', 'Static rarity glow; instant transitions')
    local speedRow = row(90)
    Kit.text(speedRow, 'BOOST SPEED · 16–32', UDim2.fromOffset(14, 8), UDim2.new(1, -28, 0, 18), Palette.muted, 10)
    local minus = Kit.button(speedRow, '−', UDim2.fromOffset(14, 31), UDim2.fromOffset(56, 52))
    local plus = Kit.button(speedRow, '+', UDim2.new(1, -70, 0, 31), UDim2.fromOffset(56, 52))
    local speedValue = Kit.text(speedRow, tostring(settings.boostSpeed), UDim2.fromOffset(76, 31), UDim2.new(1, -152, 0, 52), Palette.accent, 20)
    speedValue.TextXAlignment = Enum.TextXAlignment.Center
    for _, spec in ipairs({{minus, -2}, {plus, 2}}) do
        motion(spec[1]); spec[1].Activated:Connect(function()
            actions.change('boostSpeed', math.clamp(settings.boostSpeed + spec[2], 16, 32)); speedValue.Text = tostring(settings.boostSpeed)
        end)
    end
    local function threshold(key, title)
        local frame = row(94)
        Kit.text(frame, title, UDim2.fromOffset(14, 9), UDim2.new(1, -28, 0, 18), Palette.muted, 10)
        local input = Kit.input(frame, '1B – 50B', UDim2.fromOffset(12, 34), UDim2.new(1, -24, 0, 52))
        input.Text = string.format('%gB', settings[key] / 1e9)
        input.FocusLost:Connect(function()
            local amount = tonumber(input.Text:match('^%s*(%d+%.?%d*)%s*[bB]%s*$'))
            if amount and amount >= 1 and amount <= 50 then actions.change(key, amount * 1e9)
            else actions.notice('Use 1B–50B, for example 1.5B') end
            input.Text = string.format('%gB', settings[key] / 1e9)
        end)
    end
    threshold('serversMinValue', 'SHARED FEED MINIMUM / SECOND')
    threshold('autoJoinMinValue', 'AUTO JOIN MINIMUM / SECOND')
    toggle('webhookEnabled', 'Discord webhook', 'Opt-in: confirmed plants + manual tests')
    local webhookRow = row(200)
    Kit.text(webhookRow, 'YOUR WEBHOOK URL', UDim2.fromOffset(14, 10), UDim2.new(1, -28, 0, 20), Palette.muted, 10)
    local urlInput = Kit.input(webhookRow, 'https://discord.com/api/webhooks/…', UDim2.fromOffset(12, 38), UDim2.new(1, -24, 0, 52))
    local function maskUrl() urlInput.Text = settings.webhookUrl ~= '' and 'Saved locally · ••••••••' or '' end
    maskUrl()
    urlInput.Focused:Connect(function() urlInput.Text = settings.webhookUrl end)
    urlInput.FocusLost:Connect(function()
        local raw = urlInput.Text:match('^%s*(.-)%s*$')
        if raw == '' then actions.change('webhookUrl', '')
        else
            local url = Policy.webhook(raw)
            if url then actions.change('webhookUrl', url)
            else actions.notice('Use a valid Discord webhook URL') end
        end
        maskUrl()
    end)
    local test = Kit.button(webhookRow, 'SEND TEST', UDim2.fromOffset(12, 102), UDim2.new(1, -24, 0, 56)); motion(test)
    test.Activated:Connect(actions.testWebhook)
    local privacy = Kit.text(webhookRow, 'Stored in your executor settings. Only egg details + server ID are sent. Never your access key.',
        UDim2.fromOffset(14, 164), UDim2.new(1, -28, 0, 30), Palette.muted, 9)
    privacy.TextWrapped = true
    local sizeRow = row(90)
    Kit.text(sizeRow, 'DESKTOP SIZE · MOBILE STAYS TOUCH-SIZED', UDim2.fromOffset(14, 9), UDim2.new(1, -28, 0, 18), Palette.muted, 9)
    local smaller = Kit.button(sizeRow, '−', UDim2.fromOffset(14, 32), UDim2.fromOffset(56, 52))
    local larger = Kit.button(sizeRow, '+', UDim2.new(1, -70, 0, 32), UDim2.fromOffset(56, 52))
    local sizeValue = Kit.text(sizeRow, tostring(settings.sizePercent) .. '%', UDim2.fromOffset(76, 32), UDim2.new(1, -152, 0, 52), Palette.accent, 18)
    sizeValue.TextXAlignment = Enum.TextXAlignment.Center
    for _, spec in ipairs({{smaller, -10}, {larger, 10}}) do
        motion(spec[1]); spec[1].Activated:Connect(function()
            actions.change('sizePercent', math.clamp(settings.sizePercent + spec[2], 70, 150)); sizeValue.Text = tostring(settings.sizePercent) .. '%'; ui:fit()
        end)
    end
    ui.settingsStatus = Kit.text(sheet, 'Changes save automatically.', UDim2.new(0, 18, 1, -100), UDim2.new(1, -36, 0, 22), Palette.muted, 10)
    local done = Kit.button(sheet, 'DONE', UDim2.new(0, 14, 1, -70), UDim2.new(1, -28, 0, 56)); motion(done)
    done.BackgroundColor3 = Palette.accent; done.TextColor3 = Palette.bg
    done.Activated:Connect(function() sheet.Visible = false end)
    ui.settingsButton.Activated:Connect(function() sheet.Visible = true; for _, paint in pairs(toggles) do paint() end end)

    function ui:fit()
        local view = D.gui.AbsoluteSize
        if view.X <= 0 or view.Y <= 0 then return end
        local mobile = Input.TouchEnabled or view.X < 600
        local scale = mobile and 1 or math.max(0.85, settings.sizePercent / 100)
        local width = math.min(402, (view.X - 24) / scale)
        local height = math.min(720, (view.Y - 24) / scale)
        self.scale.Scale = scale; panel.Size = UDim2.fromOffset(width, height)
        panel.Position = UDim2.new(1, -12, 1, -12)
        self.compact = height < 480
        local dockHeight = self.compact and 120 or 172
        dock.Size = UDim2.new(1, 0, 0, dockHeight)
        tabs.Position = UDim2.fromOffset(12, self.compact and 0 or 52)
        self.phase.Visible = not self.compact; self.summary.Visible = not self.compact
        self.resetTimer.Visible = not self.compact; self.feedCount.Visible = not self.compact
        self.list.Position = UDim2.fromOffset(12, self.compact and 66 or 96)
        self.list.Size = UDim2.new(1, -24, 1, -(dockHeight + (self.compact and 74 or 104)))
    end
    function ui:paintScope(localOnly)
        self.scope.BackgroundColor3 = localOnly and Palette.bg or Palette.raised
        self.myScope.BackgroundColor3 = localOnly and Palette.raised or Palette.bg
        self.scope.TextColor3 = localOnly and Palette.muted or Palette.accent
        self.myScope.TextColor3 = localOnly and Palette.accent or Palette.muted
    end
    function ui:paintAuto(enabled)
        self.autoJoin.Text = enabled and 'AUTO JOIN · ON' or 'AUTO JOIN · OFF'
        self.autoJoin.BackgroundColor3 = enabled and Palette.teal or Palette.raised
        self.autoJoin.TextColor3 = enabled and Palette.bg or Palette.text
        self.summary.Text = string.format('FEED ≥ %gB/s    /    JOIN ≥ %gB/s', settings.serversMinValue / 1e9, settings.autoJoinMinValue / 1e9)
    end
    function ui:phaseText(phase, detail)
        self.phase.Text = '●  ' .. phase .. (detail ~= '' and '  /  ' .. detail or '')
        self.phase.TextColor3 = phase == 'COOLDOWN' and Palette.accent or Palette.teal
    end
    function ui:createCard(entry, onJoin)
        local card = {}
        card.row = Kit.make('Frame', {Name = 'EggCard', Size = UDim2.new(1, -8, 0, 144),
            BackgroundColor3 = Palette.surface, BorderSizePixel = 0, ZIndex = 5}, self.list)
        Kit.round(card.row, 16)
        card.border = Kit.stroke(card.row, Palette.line, 0.2)
        card.aura = Kit.make('Frame', {Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(56, 56),
            BackgroundTransparency = 0.91, BorderSizePixel = 0, ZIndex = 6}, card.row)
        Kit.round(card.aura, 16); card.glow = Kit.stroke(card.aura, Palette.accent, 0.83, 5)
        card.icon = Kit.make('ImageLabel', {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
            Image = '', ScaleType = Enum.ScaleType.Fit, ZIndex = 7}, card.aura)
        card.name = Kit.text(card.row, '', UDim2.fromOffset(80, 14), UDim2.new(1, -128, 0, 24), Palette.text, 15)
        card.name.Font = Enum.Font.GothamBold
        card.rank = Kit.text(card.row, '', UDim2.new(1, -45, 0, 17), UDim2.fromOffset(33, 20), Palette.muted, 11)
        card.rank.TextXAlignment = Enum.TextXAlignment.Right
        card.rarity = Kit.text(card.row, '', UDim2.fromOffset(80, 42), UDim2.new(1, -92, 0, 18), Palette.accent, 10)
        card.income = Kit.text(card.row, '', UDim2.fromOffset(14, 86), UDim2.new(1, -126, 0, 23), Palette.teal, 17)
        card.income.Font = Enum.Font.GothamBold
        card.meta = Kit.text(card.row, '', UDim2.fromOffset(14, 113), UDim2.new(1, -126, 0, 18), Palette.muted, 10)
        card.join = Kit.button(card.row, 'JOIN', UDim2.new(1, -108, 1, -68), UDim2.fromOffset(96, 56))
        motion(card.join); card.join.Activated:Connect(function() onJoin(card.entry) end)
        card.row.Destroying:Connect(function() self.cards[card] = nil end)
        self.cards[card] = true
        return card
    end
    function ui:updateCard(card, entry, rank, money, presentation)
        card.entry = entry; card.row.LayoutOrder = rank
        local color = Palette.rarity[tostring(entry.rarity):lower():gsub('%s+', '')] or Palette.accent
        card.icon.Image = entry.icon or ''; card.aura.BackgroundColor3 = color; card.glow.Color = color
        card.border.Color = color; card.border.Transparency = 0.72; card.rarity.TextColor3 = color
        card.name.Text = tostring(entry.name or 'Unknown egg'); card.rank.Text = '#' .. tostring(entry.displayRank or rank)
        local traits = tostring(entry.mutations or '')
        card.rarity.Text = string.upper(tostring(entry.rarity or 'UNKNOWN')) .. (traits ~= '' and '  ·  ' .. traits or '')
        card.income.Text = entry.missingRate and 'Income unavailable' or money(entry.rate)
        local weight = Policy.finite(entry.weight) and string.format('%.1f kg', entry.weight)
            or Policy.finite(entry.scale) and string.format('×%.2f scale', entry.scale) or 'Weight unknown'
        card.meta.Text = weight .. (entry.jobId == game.JobId and '  /  THIS SERVER' or '  /  LIVE REPORT')
        local caption, buttonColor, enabled = presentation(entry)
        card.join.Text = caption; card.join.BackgroundColor3 = buttonColor; card.join.TextColor3 = enabled and Palette.bg or Palette.muted
        card.join.Active = enabled; card.join.Selectable = enabled
    end
    table.insert(ui.connections, Input.InputEnded:Connect(function(input)
        for button, state in pairs(ui.pressed) do
            if state.input == input or state.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1 then
                if button.Parent then animate(state.scale, {Scale = 1}, 0.18) end
                ui.pressed[button] = nil
            end
        end
    end))
    table.insert(ui.connections, Input.InputBegan:Connect(function(input, processed)
        if not processed and not Input:GetFocusedTextBox() and input.KeyCode == Enum.KeyCode.F then ui:setVisible(not ui.visible) end
    end))
    table.insert(ui.connections, D.gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function() ui:fit() end))
    local lastGlow = 0
    table.insert(ui.connections, Run.Heartbeat:Connect(function()
        local now = os.clock()
        if not ui.visible or sheet.Visible or now - lastGlow < 0.05 then return end
        lastGlow = now
        for card in pairs(ui.cards) do
            card.glow.Transparency = settings.reducedMotion and 0.85 or 0.83 + math.sin(now * 1.8 + card.row.LayoutOrder) * 0.07
        end
    end))
    D.gui.Destroying:Connect(function()
        ui.active = false
        for _, connection in ipairs(ui.connections) do connection:Disconnect() end
        for _, tween in pairs(ui.tweens) do tween:Cancel() end
        table.clear(ui.tweens); table.clear(ui.pressed); table.clear(ui.cards)
    end)
    ui:fit(); task.defer(function() if ui.active then ui:fit() end end)
    surface.GroupTransparency = settings.reducedMotion and 0 or 1; animate(surface, {GroupTransparency = 0}, 0.28)
    return ui
end

-- [3] TRAPS + GROUNDED NAVIGATION
local function createTrapIndex(deps)
    local world, tags = deps.world, deps.tags
    local index = {roots = {}, connections = {}, version = 0, ready = false, alive = true}
    local function add(obj)
        if index.roots[obj] then return end
        index.roots[obj] = true; index.version += 1
    end
    local function looksLikeTrap(obj)
        local cursor = obj
        for _ = 1, 6 do
            if not cursor or cursor == world then break end
            if cursor.Name:lower():find('trap', 1, true) or cursor:GetAttribute('TrapActive') ~= nil then return true end
            cursor = cursor.Parent
        end
        return false
    end
    local function inspect(obj)
        if obj:IsA('BasePart') and (obj.Name:lower() == 'hitbox' and looksLikeTrap(obj)
            or obj.Name:lower():find('trap', 1, true)) then add(obj) end
    end
    -- The game's authoritative tag is PlacedTrap. Trap is a compatibility fallback.
    local names = {'PlacedTrap', 'Trap'}
    if type(deps.placedTag) == 'string' and deps.placedTag ~= '' then table.insert(names, deps.placedTag) end
    for _, name in ipairs(names) do
        for _, obj in ipairs(tags:GetTagged(name)) do add(obj) end
        table.insert(index.connections, tags:GetInstanceAddedSignal(name):Connect(add))
        table.insert(index.connections, tags:GetInstanceRemovedSignal(name):Connect(function(obj)
            index.roots[obj] = nil; index.version += 1
        end))
    end
    table.insert(index.connections, world.DescendantAdded:Connect(inspect))
    table.insert(index.connections, world.DescendantRemoving:Connect(function(obj)
        if index.roots[obj] then index.roots[obj] = nil; index.version += 1 end
    end))
    -- No full-Workspace scan in the movement/Heartbeat hot path.
    task.spawn(function()
        for i, obj in ipairs(world:GetDescendants()) do
            if not index.alive then return end
            inspect(obj)
            if i % 500 == 0 then task.wait() end
        end
        index.ready = true
    end)
    function index:bounds()
        local result, seen = {}, {}
        for root in pairs(self.roots) do
            if root.Parent then
                local hitboxes = {}
                if root:IsA('BasePart') and root.Name:lower() == 'hitbox' then hitboxes[1] = root end
                for _, child in ipairs(root:GetDescendants()) do
                    if child:IsA('BasePart') and child.Name:lower() == 'hitbox' then hitboxes[#hitboxes + 1] = child end
                end
                if #hitboxes == 0 and root:IsA('BasePart') then hitboxes[1] = root end
                if #hitboxes == 0 and root:IsA('Model') then
                    local ok, frame, size = pcall(root.GetBoundingBox, root)
                    if ok then result[#result + 1] = {frame = frame, size = size, instance = root} end
                end
                for _, part in ipairs(hitboxes) do
                    if not seen[part] then
                        seen[part] = true
                        result[#result + 1] = {frame = part.CFrame, size = part.Size, instance = part}
                    end
                end
            else self.roots[root] = nil end
        end
        return result
    end
    function index:destroy()
        self.alive = false
        for _, connection in ipairs(self.connections) do connection:Disconnect() end
        table.clear(self.roots)
    end
    return index
end

-- BEGIN NAVIGATOR
local function createGroundNavigator(deps)
    local world, run, player, traps = deps.world, deps.run, deps.player, deps.traps
    local nav = {busy = false, serial = 0, context = nil, direction = Vector3.zero, nextPoint = nil}
    local limits = {speed = 12, step = 1.15, rise = 1.1, drop = 0.85, radius = 2.1,
        arrival = 0.4, slope = 0.72, stuck = 2.0, planning = 4}
    nav.limits = limits
    local binding = 'UNKNOWN_Ground_' .. tostring(player.UserId)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude; params.IgnoreWater = false
    params.RespectCanCollide = true
    local filterVersion = -1
    local function flat(v) return Vector3.new(v.X, 0, v.Z) end
    local function distance(a, b) return flat(a - b).Magnitude end
    local function enforceAttribute() pcall(function() world:SetAttribute('ClientObbyAntiTp', false) end) end
    enforceAttribute()
    local connections = {}
    local function updateFilter()
        local ignored = {}
        for _, member in ipairs(deps.players:GetPlayers()) do if member.Character then ignored[#ignored + 1] = member.Character end end
        local eggs = world:FindFirstChild('AreaEggSlotsClient')
        if eggs then ignored[#ignored + 1] = eggs end
        if nav.ignoreModel then ignored[#ignored + 1] = nav.ignoreModel end
        for root in pairs(traps.roots) do if root.Parent then ignored[#ignored + 1] = root end end
        params.FilterDescendantsInstances = ignored; filterVersion = traps.version
    end
    local function ray(origin, delta)
        if filterVersion ~= traps.version then updateFilter() end
        return world:Raycast(origin, delta, params)
    end
    local function floorAt(position, rise, drop)
        rise, drop = rise or limits.rise, drop or limits.drop
        local hit = ray(position + Vector3.new(0, rise + 0.25, 0), Vector3.new(0, -(rise + drop + 0.5), 0))
        if not hit or hit.Normal.Y < limits.slope or hit.Material == Enum.Material.Water then return nil end
        return hit.Position
    end
    local function underRoot(context)
        local hit = ray(context.root.Position + Vector3.new(0, 0.2, 0), Vector3.new(0, -8, 0))
        if not hit or hit.Normal.Y < limits.slope or hit.Material == Enum.Material.Water then return nil end
        if context.root.Position.Y - hit.Position.Y > math.max(4.5, context.humanoid.HipHeight + context.root.Size.Y * 0.5 + 1) then return nil end
        return hit.Position
    end
    local function hazard(a, b)
        for _, box in ipairs(traps:bounds()) do
            if Policy.segmentHitsBox(a, b, box.frame, box.size, Vector3.new(limits.radius, 4, limits.radius)) then return box end
        end
        return nil
    end
    local function supported(point)
        for _, offset in ipairs({Vector3.zero, Vector3.new(0.75, 0, 0), Vector3.new(-0.75, 0, 0), Vector3.new(0, 0, 0.75), Vector3.new(0, 0, -0.75)}) do
            local hit = floorAt(point + offset)
            if not hit or math.abs(hit.Y - point.Y) > limits.rise then return false end
        end
        return true
    end
    local function edge(a, b)
        if hazard(a, b) then return false, 'trap' end
        local delta = b - a
        local length = distance(a, b)
        if length > 350 then return false, 'long segment' end
        if length > 0.01 then
            local side = Vector3.new(-delta.Z, 0, delta.X).Unit * 0.9
            for _, offset in ipairs({Vector3.new(0, 2, 0), Vector3.new(0, 3.8, 0), side + Vector3.new(0, 2, 0), -side + Vector3.new(0, 2, 0)}) do
                if ray(a + offset, delta) then return false, 'obstacle' end
            end
        end
        local previous = a
        local samples = math.max(1, math.ceil(length / limits.step))
        for i = 0, samples do
            local point = floorAt(a:Lerp(b, i / samples))
            if not point or point.Y - previous.Y > limits.rise or previous.Y - point.Y > limits.drop or not supported(point) then return false, 'unsafe ground' end
            previous = point
        end
        return true
    end
    function nav:isLive(token)
        return deps.live() and self.busy and self.context == token and token.serial == self.serial
            and player.Character == token.character and token.root.Parent ~= nil and token.humanoid.Health > 0
    end
    function nav:stop()
        self.direction = Vector3.zero; self.nextPoint = nil
        if self.context and self.context.humanoid.Parent then self.context.humanoid:Move(Vector3.zero, false) end
    end
    function nav:release(token)
        if self.context ~= token then return end
        self:stop(); self.busy = false; self.context = nil
        run:UnbindFromRenderStep(binding)
        if token.speedConnection then token.speedConnection:Disconnect() end
        if token.died then token.died:Disconnect() end
        if token.humanoid.Parent then token.humanoid.WalkSpeed = token.resumeSpeed end
        if deps.onRelease then deps.onRelease() end
    end
    function nav:cancel(reason)
        self.serial += 1; self.reason = reason or 'cancelled'
        if self.context then self:release(self.context) end
    end
    function nav:acquire(ignoreModel)
        if self.busy or not traps.ready then return nil, 'Waiting for trap map' end
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass('Humanoid')
        local root = character and character:FindFirstChild('HumanoidRootPart')
        if not humanoid or not root or not root:IsA('BasePart') or humanoid.Health <= 0
            or humanoid.FloorMaterial == Enum.Material.Air or root.Anchored then return nil, 'Waiting for a grounded character' end
        if deps.onAcquire then deps.onAcquire() end
        self.serial += 1; self.ignoreModel = ignoreModel; updateFilter(); enforceAttribute()
        local token = {serial = self.serial, character = character, humanoid = humanoid, root = root,
            resumeSpeed = humanoid.WalkSpeed, speed = math.min(limits.speed, humanoid.WalkSpeed), writing = false}
        self.context = token; self.busy = true; self.reason = nil
        token.speedConnection = humanoid:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
            if not token.writing and self.context == token then
                token.resumeSpeed = humanoid.WalkSpeed; token.speed = math.min(limits.speed, humanoid.WalkSpeed)
            end
        end)
        token.died = humanoid.Died:Connect(function() self:cancel('Character died') end)
        run:BindToRenderStep(binding, Enum.RenderPriority.Input.Value + 1, function(dt)
            if not self:isLive(token) then self:stop(); return end
            if self.nextPoint then
                local floor = underRoot(token)
                if not floor or hazard(floor, self.nextPoint) then
                    token.blocked = true; self:stop(); return
                end
            end
            token.writing = true
            humanoid.WalkSpeed = math.max(0, math.min(token.speed, limits.step / math.max(dt, 1/60), (self.remaining or limits.step) / math.max(dt, 1/60)))
            token.writing = false
            humanoid:Move(self.direction, false)
        end)
        return token
    end
    function nav:destination(position)
        local point = floorAt(position, 8, 24)
        if point and supported(point) and not hazard(point, point) then return point end
        return nil
    end
    function nav:standNear(position, token, radius)
        local choices = {}
        for i = 0, 7 do
            local angle = i * math.pi / 4
            local point = self:destination(position + Vector3.new(math.cos(angle) * (radius or 3.25), 0, math.sin(angle) * (radius or 3.25)))
            if point then choices[#choices + 1] = point end
        end
        table.sort(choices, function(a, b) return distance(a, token.root.Position) < distance(b, token.root.Position) end)
        return choices[1]
    end
    local function detour(a, b, token)
        local nodes = {a, b}
        local boxes = traps:bounds()
        local center = (a + b) * 0.5
        table.sort(boxes, function(x, y) return distance(x.frame.Position, center) < distance(y.frame.Position, center) end)
        for i = 1, math.min(12, #boxes) do
            local box = boxes[i]
            if distance(box.frame.Position, center) < distance(a, b) * 0.5 + 24 then
                local half = box.size * 0.5 + Vector3.new(limits.radius + 0.8, 0, limits.radius + 0.8)
                for _, signs in ipairs({{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}) do
                    local corner = box.frame:PointToWorldSpace(Vector3.new(signs[1] * half.X, 0, signs[2] * half.Z))
                    local t = math.clamp(distance(a, corner) / math.max(0.01, distance(a, b)), 0, 1)
                    local point = floorAt(Vector3.new(corner.X, a.Y + (b.Y - a.Y) * t, corner.Z))
                    if point and supported(point) and not hazard(point, point) then nodes[#nodes + 1] = point end
                end
            end
        end
        local cost, parent, closed, cached = {[1] = 0}, {}, {}, {}
        local deadline, slice = os.clock() + limits.planning, os.clock()
        while nav:isLive(token) and os.clock() < deadline do
            local current, best = nil, math.huge
            for i, value in pairs(cost) do
                local score = value + distance(nodes[i], b)
                if not closed[i] and score < best then current, best = i, score end
            end
            if not current then return nil end
            if current == 2 then
                local result, cursor = {}, 2
                while cursor and cursor ~= 1 do table.insert(result, 1, nodes[cursor]); cursor = parent[cursor] end
                return result
            end
            closed[current] = true
            for nextIndex, point in ipairs(nodes) do
                if not closed[nextIndex] then
                    local key = math.min(current, nextIndex) .. ':' .. math.max(current, nextIndex)
                    if cached[key] == nil then cached[key] = edge(nodes[current], point) end
                    if cached[key] then
                        local candidate = cost[current] + distance(nodes[current], point)
                        if not cost[nextIndex] or candidate < cost[nextIndex] then cost[nextIndex], parent[nextIndex] = candidate, current end
                    end
                end
                if os.clock() - slice > 0.004 then task.wait(); slice = os.clock(); if not nav:isLive(token) then return nil end end
            end
        end
        return nil
    end
    local function plan(a, goal, token)
        local clear, reason = edge(a, goal)
        if clear then return {goal} end
        if reason == 'trap' then
            local route = detour(a, goal, token)
            if route then return route end
        end
        local path = deps.pathfinding:CreatePath({AgentRadius = limits.radius, AgentHeight = 5,
            AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 3, Costs = {Water = math.huge}})
        local ok = boundedCall(limits.planning, function() return nav:isLive(token) end, function()
            path:ComputeAsync(a + Vector3.new(0, 2, 0), goal + Vector3.new(0, 2, 0))
        end)
        if not ok or path.Status ~= Enum.PathStatus.Success then return nil, 'No grounded route' end
        local route, previous = {}, a
        local waypoints = path:GetWaypoints()
        waypoints[#waypoints + 1] = {Position = goal, Action = Enum.PathWaypointAction.Walk}
        for _, waypoint in ipairs(waypoints) do
            if waypoint.Action == Enum.PathWaypointAction.Jump then return nil, 'Route needs a jump' end
            local point = floorAt(waypoint.Position, 3, 5)
            if not point then return nil, 'No ground at waypoint' end
            if distance(point, previous) > 0.25 then
                local segment
                local safe, blockedBy = edge(previous, point)
                if safe then segment = {point}
                elseif blockedBy == 'trap' then segment = detour(previous, point, token) end
                if not segment then return nil, 'Unsafe route segment' end
                for _, step in ipairs(segment) do route[#route + 1] = step end
                previous = point
            end
        end
        return route
    end
    function nav:moveTo(goal, token, validate)
        if not self:isLive(token) then return false, self.reason or 'Character changed' end
        local start = underRoot(token)
        if not start then return false, 'No ground below character' end
        local route, reason = plan(start, goal, token)
        if not route then return false, reason or 'Trap blocks route' end
        local deadline = os.clock() + math.clamp(distance(start, goal) / math.max(1, token.speed) * 3 + 12, 12, 100)
        local lastProgress, progressAt = token.root.Position, os.clock()
        for _, waypoint in ipairs(route) do
            while self:isLive(token) do
                if validate and not validate() then self:stop(); return false, 'Egg no longer available' end
                if os.clock() > deadline then self:stop(); return false, 'Route timed out' end
                local floor = underRoot(token)
                if not floor or token.humanoid.FloorMaterial == Enum.Material.Air then self:stop(); return false, 'Ground contact lost' end
                local delta = flat(waypoint - floor)
                if delta.Magnitude <= limits.arrival then break end
                local step = floorAt(floor + delta.Unit * math.min(limits.step, delta.Magnitude))
                if token.blocked or not step or not edge(floor, step) then self:stop(); return false, 'Route changed / trap ahead' end
                self.nextPoint = step; self.direction = delta.Unit; self.remaining = delta.Magnitude
                if distance(token.root.Position, lastProgress) >= 0.2 then lastProgress, progressAt = token.root.Position, os.clock() end
                if os.clock() - progressAt > limits.stuck then self:stop(); return false, 'Movement blocked' end
                run.Heartbeat:Wait()
            end
            if not self:isLive(token) then return false, self.reason or 'Character changed' end
        end
        self:stop()
        local floor = underRoot(token)
        if not floor or not supported(floor) or hazard(floor, floor) or token.humanoid.FloorMaterial == Enum.Material.Air then return false, 'Unsafe arrival' end
        return distance(floor, goal) <= limits.arrival + 0.1
    end
    table.insert(connections, player.CharacterRemoving:Connect(function() nav:cancel('Respawn'); filterVersion = -1 end))
    table.insert(connections, player.CharacterAdded:Connect(function() nav:cancel('Respawn'); filterVersion = -1; enforceAttribute() end))
    table.insert(connections, world:GetAttributeChangedSignal('ClientObbyAntiTp'):Connect(function()
        if deps.live() and world:GetAttribute('ClientObbyAntiTp') ~= false then enforceAttribute() end
    end))
    function nav:destroy()
        self:cancel('Stopped')
        for _, connection in ipairs(connections) do connection:Disconnect() end
    end
    return nav
end
-- END NAVIGATOR

-- [4] MANUAL PERKS + SINGLE-OWNER STEAL STATE MACHINE
local function createMovementPerks(deps)
    local perks = {suspended = false, humanoid = nil, baseline = nil, applied = nil, writing = false, alive = true}
    local connections, speedConnection, childConnection = {}, nil, nil
    function perks:apply()
        local humanoid = self.humanoid
        if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then return end
        local enabled = deps.settings.speedBoost and not self.suspended
        local target = enabled and deps.settings.boostSpeed or self.baseline
        if not enabled and self.applied == nil then return end
        self.writing = true
        if target then humanoid.WalkSpeed = target end
        self.writing = false; self.applied = enabled and target or nil
    end
    local function attach(humanoid)
        if speedConnection then speedConnection:Disconnect() end
        perks.humanoid = humanoid; perks.baseline = humanoid.WalkSpeed; perks.applied = nil
        speedConnection = humanoid:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
            if perks.writing or perks.suspended then return end
            if humanoid.WalkSpeed ~= perks.applied then
                perks.baseline = humanoid.WalkSpeed
                perks:apply()
            end
        end)
        perks:apply()
    end
    local function bind(character)
        if childConnection then childConnection:Disconnect(); childConnection = nil end
        if speedConnection then speedConnection:Disconnect(); speedConnection = nil end
        perks.humanoid = nil; perks.applied = nil; perks.suspended = false
        local humanoid = character:FindFirstChildOfClass('Humanoid')
        if humanoid then attach(humanoid)
        else childConnection = character.ChildAdded:Connect(function(child)
            if child:IsA('Humanoid') then
                if childConnection then childConnection:Disconnect(); childConnection = nil end
                attach(child)
            end
        end) end
    end
    function perks:suspend()
        self.suspended = true; self:apply()
    end
    function perks:resume()
        self.suspended = false
        if self.humanoid and self.humanoid.Parent then self.baseline = self.humanoid.WalkSpeed end
        self.applied = nil; self:apply()
    end
    table.insert(connections, deps.player.CharacterAdded:Connect(bind))
    if deps.player.Character then bind(deps.player.Character) end
    local lastJump = -math.huge
    table.insert(connections, deps.input.JumpRequest:Connect(function()
        local humanoid = perks.humanoid
        if not perks.alive or perks.suspended or not deps.settings.infiniteJump or not humanoid
            or not humanoid.Parent or humanoid.Health <= 0 or humanoid.Sit or os.clock() - lastJump < 0.16 then return end
        lastJump = os.clock(); humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end))
    function perks:destroy()
        self.alive = false; self.suspended = true; self:apply()
        if speedConnection then speedConnection:Disconnect() end
        if childConnection then childConnection:Disconnect() end
        for _, connection in ipairs(connections) do connection:Disconnect() end
    end
    return perks
end

-- BEGIN STEAL CONTROLLER
local function createStealController(deps)
    local control = {busy = false, phase = 'READY', detail = '', cooldowns = {}, completed = {},
        pendingUid = nil, target = nil, nextHomeAt = 0, homeFailures = 0, alive = true}
    local nav, eggState = deps.nav, deps.eggState
    local function phase(name, detail)
        control.phase, control.detail = name, detail or ''
        if deps.phase then deps.phase(name, detail or '') end
    end
    local function readCarry()
        if type(eggState.ReadCarryState) ~= 'function' then return nil end
        local ok, value = pcall(eggState.ReadCarryState)
        return ok and type(value) == 'table' and value or nil
    end
    local function carryingUid()
        local carry = readCarry()
        if not carry or not carry.IsCarrying then return nil, carry end
        local recent = control.recent
        local lateUid = recent and recent.character == deps.player.Character and os.clock() - recent.at < 20 and recent.uid or nil
        return Policy.carryUid(carry) or control.pendingUid or lateUid, carry
    end
    local function cooldown(uid, reason)
        local old = control.cooldowns[uid]
        local attempts = (old and old.attempts or 0) + 1
        local delay = Policy.backoff(attempts, 2, 24)
        control.cooldowns[uid] = {attempts = attempts, untilAt = os.clock() + delay, lastAt = os.clock()}
        phase('COOLDOWN', tostring(reason or 'Attempt failed') .. ' · ' .. delay .. 's')
    end
    function control:blocksJoin()
        local _, carry = carryingUid()
        return self.busy or nav.busy or carry and carry.IsCarrying == true
    end
    function control:cancel(reason)
        nav:cancel(reason or 'Auto steal disabled')
    end
    local function targetAvailable(uid)
        local target = deps.resolve(uid)
        return target and target.pickable == true
    end
    local function waitForCarry(uid, token)
        local deadline = os.clock() + 1.2
        repeat
            if not nav:isLive(token) then return false end
            local carry = readCarry()
            local actual = Policy.carryUid(carry)
            if carry and carry.IsCarrying and (not actual or actual == uid) then return true end
            deps.run.Heartbeat:Wait()
        until os.clock() >= deadline
        return false
    end
    local function carryHome(uid, token)
        phase('HOME', 'Walking to your plot')
        local plotDeadline = os.clock() + 3
        while nav:isLive(token) and (not deps.plot or type(deps.plot.ResolvePlot) ~= 'function') and os.clock() < plotDeadline do deps.run.Heartbeat:Wait() end
        if not deps.plot or type(deps.plot.ResolvePlot) ~= 'function' then return false, 'Plot module not ready' end
        local ok, plot = boundedCall(3, function() return nav:isLive(token) end, deps.plot.ResolvePlot)
        if not ok or not plot or not plot.CenterPoint then return false, 'Your plot is not ready' end
        local center = plot.CenterPoint
        local position = typeof(center) == 'Vector3' and center or center.Position
        if typeof(position) ~= 'Vector3' then return false, 'Plot center unavailable' end
        local home = nav:destination(position) or nav:standNear(position, token, 3)
        if not home then return false, 'No safe ground at home' end
        local reached, why = nav:moveTo(home, token, function()
            local actual, carry = carryingUid()
            return carry and carry.IsCarrying and (not actual or actual == uid)
        end)
        if not reached then return false, why end
        if not nav:isLive(token) then return false, 'Respawn' end
        phase('PLANT', 'Confirming placement')
        -- This CFrame is the game's relative planting offset, NEVER a character move.
        local planted, result = boundedCall(3, function() return nav:isLive(token) end, function()
            return eggState.PlantEgg(uid, CFrame.new(0, 0, 0))
        end)
        if not planted or result ~= true then return false, 'Plant not acknowledged' end
        control.completed[uid] = {at = os.clock(), leftField = false}; control.cooldowns[uid] = nil
        control.pendingUid = nil; control.recent = nil; control.homeFailures = 0; control.nextHomeAt = 0
        if deps.planted then deps.planted(uid, control.target) end
        phase('PLANTED', control.target and tostring(control.target.name or uid) or uid)
        return true
    end
    local function attempt(target, resume)
        local uid = tostring(target.uid)
        local token, why = nav:acquire(target.model)
        if not token then return false, why, true end -- not ready is not a failed remote attempt
        local ok, success, reason = pcall(function()
            if not resume then
                phase('ROUTE', tostring(target.name or uid))
                local point = target.worldPos
                if typeof(point) ~= 'Vector3' and target.model and target.model.Parent then point = target.model:GetPivot().Position end
                if typeof(point) ~= 'Vector3' then return false, 'Waiting for egg position' end
                -- Choose ONE parking point during planning; never circle/teleport between spots.
                local stand = nav:standNear(point, token, 3.25)
                if not stand then return false, 'Trap / unsafe ground beside egg' end
                local reached, message = nav:moveTo(stand, token, function() return targetAvailable(uid) end)
                if not reached then return false, message end
                local current = deps.resolve(uid)
                if not nav:isLive(token) or not current or not current.pickable then return false, 'Egg no longer available' end
                local eggPoint = current.worldPos or point
                local delta = token.root.Position - eggPoint
                if Vector3.new(delta.X, 0, delta.Z).Magnitude > 5.5 then return false, 'Egg moved out of reach' end
                local slotKey
                if deps.identity and current.areaKey ~= nil and current.nestId ~= nil
                    and deps.identity.LooksLikeFirstAreaUid(uid) then slotKey = deps.identity.SlotKey(current.areaKey, current.nestId) end
                phase('PICKUP', tostring(target.name or uid))
                -- No settle timer or extra frame here: call carry on the arrival frame.
                control.pendingUid = uid
                control.recent = {uid = uid, character = token.character, at = os.clock()}
                local called, result = boundedCall(3, function() return nav:isLive(token) end, function()
                    return eggState.CarryFieldEgg(uid, slotKey)
                end)
                if not called or result == false then return false, 'Carry rejected / timed out' end
                if not waitForCarry(uid, token) then return false, 'Carry state not confirmed' end
                if deps.picked then deps.picked(uid) end
            end
            control.pendingUid = uid
            return carryHome(uid, token)
        end)
        nav:release(token)
        if not ok then return false, 'Game API / route error' end
        return success, reason
    end
    local function choose()
        local tracked = deps.tracked()
        if tracked and not control.completed[tostring(tracked.uid)] then
            local target = deps.resolve(tostring(tracked.uid))
            if target and target.pickable then
                -- A slow asset directory must not gate a tracked UID's pickup.
                if target.rarity == 'Unknown' then
                    target.name = tracked.name or target.name; target.rarity = tracked.rarity or target.rarity
                    target.tier = tracked.rank or target.tier; target.icon = tracked.icon or target.icon
                end
                target.rate = target.rate or tracked.rate
                return target
            end
        end
        if not deps.autoJoin() then return nil end
        local best
        for _, target in ipairs(deps.entries()) do
            local retry = control.cooldowns[tostring(target.uid)]
            if target.pickable and not control.completed[tostring(target.uid)] and (not retry or retry.untilAt <= os.clock())
                and (target.rate or 0) >= deps.minimum() and (target.tier or 0) >= deps.minRank()
                and (not best or (target.rate or 0) > (best.rate or 0)) then best = target end
        end
        return best
    end
    local queued, lastRetireCheck = false, -math.huge
    function control:wake()
        if queued or self.busy or not self.alive or not deps.live() or not deps.enabled() or deps.joining() then return end
        queued = true
        task.defer(function()
            queued = false
            if self.busy or not self.alive or not deps.live() or not deps.enabled() or deps.joining() then return end
            if os.clock() - lastRetireCheck >= 0.15 then
                lastRetireCheck = os.clock()
                for uid, done in pairs(self.completed) do
                    local current = deps.resolve(uid)
                    if not current or not current.pickable then done.leftField = true
                    elseif done.leftField and os.clock() - done.at >= 1 then self.completed[uid] = nil; self.cooldowns[uid] = nil end
                    if not current and os.clock() - done.at > 300 then self.completed[uid] = nil end
                end
                for uid, retry in pairs(self.cooldowns) do if os.clock() - retry.lastAt > 120 then self.cooldowns[uid] = nil end end
            end
            local carried, carry = carryingUid()
            local resume = carry and carry.IsCarrying
            if resume and not carried then phase('WAITING', 'Carry UID not replicated yet'); return end
            if resume and os.clock() < self.nextHomeAt then return end
            local previous = self.target and tostring(self.target.uid) == carried and self.target or nil
            local target = resume and (deps.resolve(carried) or previous or {uid = carried}) or choose()
            if not target then return end
            local uid = tostring(target.uid)
            local retry = self.cooldowns[uid]
            if not resume and retry and retry.untilAt > os.clock() then return end
            self.busy = true; self.target = target
            local ok, success, reason, notReady = pcall(attempt, target, resume)
            self.busy = false
            if not self.alive or not deps.live() then return end
            if not ok then success, reason = false, 'Unexpected game API error' end
            if not success and not notReady then
                local _, stillCarrying = carryingUid()
                if stillCarrying and stillCarrying.IsCarrying then
                    self.homeFailures += 1; self.nextHomeAt = os.clock() + Policy.backoff(self.homeFailures, 3, 24)
                end
                cooldown(uid, reason)
            elseif notReady then phase('WAITING', tostring(reason)) end
            if not success then
                local _, stillCarrying = carryingUid()
                if not stillCarrying or not stillCarrying.IsCarrying then self.pendingUid = nil end
            end
        end)
    end
    -- Heartbeat sees a tracked UID directly from EggState: no UI scan, feed HTTP,
    -- render interval, key refresh or arbitrary startup sleep is a prerequisite.
    local beat = deps.run.Heartbeat:Connect(function()
        if deps.live() then control:wake() end
    end)
    local removing = deps.player.CharacterRemoving:Connect(function()
        control:cancel('Respawn')
        if control.target then cooldown(tostring(control.target.uid), 'Respawn') end
    end)
    function control:destroy()
        self.alive = false; self:cancel('Stopped'); beat:Disconnect(); removing:Disconnect()
    end
    control:wake()
    return control
end
-- END STEAL CONTROLLER

local function createWebhook(deps)
    local hook = {queue = {}, sent = {}, running = false, alive = true, nextAt = 0}
    local function status(text) if deps.notice and hook.alive then deps.notice(text) end end
    function hook:send(event, test)
        local url = Policy.webhook(deps.settings.webhookUrl)
        if not url then if test then status('Save a valid Discord webhook URL first') end; return end
        if not test and not deps.settings.webhookEnabled then return end
        local id = if test then nil else Policy.id(event) .. ':' .. tostring(event.confirmedAt or '')
        if id and self.sent[id] then return end
        if #self.queue >= 10 then return end
        if id then self.sent[id] = true end
        self.queue[#self.queue + 1] = {event = event, test = test, id = id, url = url}
        if self.running then return end
        self.running = true
        task.spawn(function()
            while self.alive and deps.live() and #self.queue > 0 do
                local item = table.remove(self.queue, 1)
                if Policy.webhook(deps.settings.webhookUrl) == item.url and (item.test or deps.settings.webhookEnabled) then
                    local color = Palette.rarity[tostring(item.event.rarity):lower()] or Palette.accent
                    local body = deps.http:JSONEncode({username = 'UNKNOWN', allowed_mentions = {parse = {}}, embeds = {{
                        title = item.test and 'UNKNOWN · Webhook connected' or 'Egg planted at home',
                        description = item.test and 'Notifications are ready. Your access key is never included.' or tostring(item.event.name or 'Unknown egg'):sub(1, 200),
                        color = math.floor(color.R * 255) * 65536 + math.floor(color.G * 255) * 256 + math.floor(color.B * 255),
                        fields = item.test and {} or {
                            {name = 'Income', value = deps.money(item.event.rate), inline = true},
                            {name = 'Rarity', value = tostring(item.event.rarity or 'Unknown'), inline = true},
                            {name = 'Server', value = tostring(game.PlaceId) .. ' / ' .. tostring(game.JobId)},
                        }, footer = {text = BUILD.name},
                    }}})
                    for attempt = 1, 3 do
                        while self.alive and deps.live() and os.clock() < self.nextAt do task.wait(0.1) end
                        if not self.alive or not deps.live() or Policy.webhook(deps.settings.webhookUrl) ~= item.url
                            or not item.test and not deps.settings.webhookEnabled then break end
                        local ok, response = boundedCall(8, function() return self.alive and deps.live() end, function()
                            return deps.request({Url = item.url, Method = 'POST', Timeout = 6,
                                Headers = {['Content-Type'] = 'application/json'}, Body = body})
                        end)
                        local code = ok and type(response) == 'table' and tonumber(response.StatusCode or response.Status)
                        self.nextAt = os.clock() + 2
                        if code and code >= 200 and code < 300 then if item.test then status('Discord test delivered') end; break end
                        if code == 429 then
                            local parsed, data = pcall(deps.http.JSONDecode, deps.http, response.Body or '')
                            local retry = parsed and type(data) == 'table' and tonumber(data.retry_after) or 5
                            self.nextAt = os.clock() + Policy.number(retry, 5, 1, 120)
                        elseif code and code >= 400 and code < 500 then status('Discord refused the webhook (HTTP ' .. code .. ')'); break
                        else
                            self.nextAt = os.clock() + Policy.backoff(attempt, 2, 20)
                            if attempt == 3 then status('Webhook unavailable; gameplay was not interrupted') end
                        end
                    end
                end
            end
            self.running = false
        end)
    end
    function hook:destroy() self.alive = false; table.clear(self.queue) end
    return hook
end

-- [5] FINDER · independent claim/feed/broadcast lanes and pre-claim hop preparation.
local function startUnknown(access)
    local Players = game:GetService('Players')
    local RS = game:GetService('ReplicatedStorage')
    local HttpService = game:GetService('HttpService')
    local Teleports = game:GetService('TeleportService')
    local player = Players.LocalPlayer
    if not player then return end
    local env = environment()
    if type(env.__UNKNOWN_STOP_ACTIVE) == 'function' then pcall(env.__UNKNOWN_STOP_ACTIVE) end
    local parent = player:FindFirstChild('PlayerGui') or player:WaitForChild('PlayerGui', 15)
    assert(parent, 'PlayerGui unavailable')
    local old = parent:FindFirstChild('UNKNOWN')
    if old then old:Destroy() end
    local gui = Kit.make('ScreenGui', {Name = 'UNKNOWN', ResetOnSpawn = false, IgnoreGuiInset = false,
        DisplayOrder = 1200, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, parent)
    pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
    gui:SetAttribute('UnknownBuild', BUILD.name)
    gui:SetAttribute('TenshiUIBuild', 'PUBLIC-V050-UI21')
    local alive = true
    local stop
    stop = function()
        alive = false
        if gui.Parent then gui:Destroy() end
        if env.__UNKNOWN_STOP_ACTIVE == stop then env.__UNKNOWN_STOP_ACTIVE = nil end
        if env.__UNKNOWN_RUNNING_JOB == game.JobId then env.__UNKNOWN_RUNNING_JOB = nil end
    end
    env.__UNKNOWN_STOP_ACTIVE = stop
    env.__UNKNOWN_RUNNING_JOB = game.JobId
    gui.Destroying:Connect(function()
        alive = false
        if env.__UNKNOWN_STOP_ACTIVE == stop then env.__UNKNOWN_STOP_ACTIVE = nil end
        if env.__UNKNOWN_RUNNING_JOB == game.JobId then env.__UNKNOWN_RUNNING_JOB = nil end
    end)
    pcall(function() workspace:SetAttribute('ClientObbyAntiTp', false) end)
    local autoExecuteEnabled, autoExecuteQueued = true, false
    local rawUrl = type(env.UNKNOWN_SCRIPT_URL) == 'string' and env.UNKNOWN_SCRIPT_URL or BUILD.sourceUrl
    local function queueAutoExecute()
        if not autoExecuteEnabled then return true end
        if autoExecuteQueued then return true end
        local candidates = {}
        local function add(callback) if type(callback) == 'function' then candidates[#candidates + 1] = callback end end
        add(queue_on_teleport); add(queueonteleport)
        if type(syn) == 'table' then add(syn.queue_on_teleport) end
        if type(fluxus) == 'table' then add(fluxus.queue_on_teleport) end
        -- %q quotes the override safely. No key or webhook URL is embedded in queued code.
        local quotedUrl = string.format('%q', rawUrl)
        local payload = 'local t=game:GetService("TeleportService");local h=game:GetService("HttpService");local a=t:GetTeleportSetting("UNKNOWNAutoExecuteV1");if type(a)~="boolean" then local ok,s=pcall(function()return h:JSONDecode(readfile("tenshi_beta_ui.json"))end);a=not ok or type(s)~="table" or s.autoExecute~=false end;if a then local e=_G;pcall(function()if type(getgenv)=="function" then e=getgenv()end end);e.UNKNOWN_SCRIPT_URL=' .. quotedUrl .. ';loadstring(game:HttpGet(' .. quotedUrl .. '))() end'
        local available = false
        for _, callback in pairs(candidates) do
            if type(callback) == 'function' then
                available = true
                if pcall(callback, payload) then autoExecuteQueued = true; return true end
            end
        end
        return not available -- unsupported executors can still use manual joins
    end
    local function module(path)
        local obj = RS
        for part in path:gmatch('[^.]+') do obj = obj:FindFirstChild(part); assert(obj, 'Missing game module: ' .. path) end
        return require(obj)
    end
    local function numberField(record, keys)
        for _, key in ipairs(keys) do if Policy.finite(record and record[key]) then return record[key] end end
        return nil
    end
    local function modelFor(uid)
        uid = tostring(uid or '')
        local folder = workspace:FindFirstChild('AreaEggSlotsClient')
        local obj = folder and folder:FindFirstChild(uid) or workspace:FindFirstChild(uid)
        return obj and obj:IsA('Model') and obj or nil
    end
    local function displayedRate(model)
        if not model then return nil end
        for _, obj in ipairs(model:GetDescendants()) do
            if obj:IsA('TextLabel') or obj:IsA('TextButton') then
                local text = obj.Text:gsub('<[^>]+>', ''):gsub(',', '')
                local amount, suffix = text:match('%$?%s*(%d+%.?%d*)%s*(%a*)%s*/[sS]')
                local factor = suffix and ({['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,q=1e15,qi=1e18})[suffix:lower()]
                if amount and factor then return tonumber(amount) * factor end
            end
        end
        return nil
    end
    local function money(value)
        if not Policy.finite(value) then return 'Income unavailable' end
        for _, entry in ipairs({{1e18,'Qi'},{1e15,'Qa'},{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'K'}}) do
            if value >= entry[1] then return string.format('$%.2f%s/s', value / entry[1], entry[2]) end
        end
        return string.format('$%.2f/s', value)
    end
    local function valid(value) return Policy.finite(value) and value >= 0 end
    local function computedRate(base, scale, muts, mutationModule)
        if not valid(base) or not valid(scale) or scale == 0 or type(muts) ~= 'table' then return nil end
        local multi = 1
        if next(muts) then
            if not mutationModule or type(mutationModule.EarningsFor) ~= 'function' then return nil end
            local ok, result = pcall(mutationModule.EarningsFor, muts)
            if not ok or not valid(result) then return nil end
            multi = result
        end
        local factor = scale > 5 and (scale / 5)^1.2 * 19.637875755794113 or scale^1.85
        local result = base * factor * multi
        return valid(result) and result or nil
    end
    local function isHalloweenEgg(entry)
        local source = tostring(entry and (entry.source or (entry.isEvent and 'event')) or ''):lower()
        local area = tostring(entry and (entry.area or entry.areaKey) or ''):lower()
        return source == 'event' or area:find('halloween', 1, true) ~= nil or area:match('^hw[%s/]') ~= nil
    end
    local function readTraitNames(record)
        local names, seen = {}, {}
        local known = record.Mutations ~= nil or record.BaseMutation ~= nil
        local function add(value)
            if type(value) == 'string' and value ~= '' and value ~= 'None' and value ~= 'Normal' and not seen[value] then seen[value] = true; names[#names + 1] = value end
        end
        if type(record.Mutations) == 'table' then
            for key, value in pairs(record.Mutations) do
                if value == true and type(key) == 'string' then add(key)
                elseif type(value) == 'string' then add(value)
                elseif type(value) == 'table' then local id = value.Id or value._id or value.Name; if type(id) == 'string' then add(id) else known = false end end
            end
        elseif type(record.Mutations) == 'string' then for value in record.Mutations:gmatch('[^,;|]+') do add(value:match('^%s*(.-)%s*$')) end end
        add(record.BaseMutation); table.sort(names)
        return names, known
    end

    local function createFinder(D)

    local cycleModule = D.cycle
    local function cycleInfo()
        cycleModule = cycleModule or D.cycle
        if not cycleModule then return nil end
        local ok,info=pcall(function()
            local now=workspace:GetServerTimeNow()
            local running=cycleModule.IsRunning()
            local remaining=cycleModule.SecondsUntilReset(now)
            local respawnAt
            if type(cycleModule.PeriodStartTime)=='function' and type(cycleModule.PeriodIndexAt)=='function' then
                local known,value=pcall(function() return cycleModule.PeriodStartTime(cycleModule.PeriodIndexAt(now))*1000 end)
                if known and type(value)=='number' then respawnAt=value end
            end
            return {resetAt=cycleModule.NextResetTime(now)*1000,respawnAt=respawnAt,remaining=remaining,running=running}
        end)
        return ok and info or nil
    end
    -- Preserve reset/tombstone rules, but never delay a fresh report's first display.
    D.publicPrioritySeen={}
    D.publicPriorityVisible=function() return true end -- new reports are visible immediately
    D.publicSightings={}
    D.publicSightingsDirty=false
    D.publicSightingsWriteAt=-math.huge
    D.publicSightingsPath='tenshi_public_sighting_lifecycle_v1.json'
    if type(readfile)=='function' then
        pcall(function()
            local saved=game:GetService('HttpService'):JSONDecode(readfile(D.publicSightingsPath))
            if type(saved)=='table' and saved.version==1 and type(saved.items)=='table' then
                local count=0
                for key,value in pairs(saved.items) do
                    if count>=60000 then break end
                    if type(key)=='string' and #key<=512 and type(value)=='table' and (value.retired==true or type(value.deadline)=='number' and value.deadline==value.deadline and math.abs(value.deadline)<math.huge) then D.publicSightings[key]=value;count+=1 end
                end
            end
        end)
    end
    -- This exact sighting was confirmed to predate multiple resets.
    D.publicSightings['107778070777162:10d3ade5-36f6-42c6-b25e-b4cbaa61977e:845e5200c4984a26bb83680e068ac9c5']={retired=true}
    D.publicEntryAllowed=function(entry,now)
        if type(entry)~='table' then return false end
        local key=entry.key
        if type(key)~='string' then return true end
        if not D.publicPrioritySeen[key] then D.publicPrioritySeen[key]=os.clock() end
        local prior=D.publicSightings[key]
        if prior and prior.retired then return false end
        if prior and prior.deadline<=now then prior.retired=true;D.publicSightingsDirty=true;return false end
        if entry.resetEstimated==false and type(entry.expiresAt)=='number' then
            if not prior then
                prior={deadline=entry.expiresAt};D.publicSightings[key]=prior;D.publicSightingsDirty=true
            elseif entry.expiresAt<prior.deadline then prior.deadline=entry.expiresAt;D.publicSightingsDirty=true end
            if prior.deadline<=now then prior.retired=true;return false end
        end
        return true
    end
    D.savePublicSightings=function()
        if not D.publicSightingsDirty or os.clock()-D.publicSightingsWriteAt<2 or type(writefile)~='function' then return end
        D.publicSightingsWriteAt=os.clock()
        local ok=pcall(function() writefile(D.publicSightingsPath,game:GetService('HttpService'):JSONEncode({version=1,items=D.publicSightings})) end)
        if ok then D.publicSightingsDirty=false end
    end


        local Http = HttpService
        local requestFn = request or http_request or (syn and syn.request) or (http and http.request)
        local active, othersOnly = true, false
        D.gui.Destroying:Connect(function() active = false end)
        local state = {autoJoin = false, joining = false, joinSerial = 0, joiningKey = nil,
            failed = {}, phase = 'READY', detail = '', feedRevision = 0, nextJoinAt = 0}
        local reporterId = Http:GenerateGUID(false)
        local config, publicBroadcastConfig, featureConfig, configAt = nil, nil, nil, -math.huge
        local feed, feedAt, localStates, feedStore = {}, 0, {}, {}
        local clockOffset = os.time() - os.clock()
        local reportStatus, queryStatus = 'Connecting', ''
        local minRate, minRank, serversMinValue, autoJoinMinValue = 1e9, 0, 1e9, 1e9
        local queryEpoch = 0
        local settingsPath = 'tenshi_beta_ui.json'
        local saved = {}
        if type(readfile) == 'function' then pcall(function() local data = Http:JSONDecode(readfile(settingsPath)); if type(data) == 'table' then saved = data end end) end
        local settings = {
            myServer = saved.myServer == true, autoExecute = saved.autoExecute ~= false, autoSteal = saved.autoSteal ~= false,
            autoJoinEnabled = saved.autoJoinEnabled == true, speedBoost = saved.speedBoost == true, infiniteJump = saved.infiniteJump == true,
            boostSpeed = Policy.number(saved.boostSpeed, 24, 16, 32), reducedMotion = saved.reducedMotion == true,
            webhookEnabled = saved.webhookEnabled == true, webhookUrl = Policy.webhook(saved.webhookUrl) or '',
            serversMinValue = Policy.number(saved.serversMinValue, 1e9, 1e9, 50e9),
            autoJoinMinValue = Policy.number(saved.autoJoinMinValue, 1e9, 1e9, 50e9),
            sizePercent = Policy.number(saved.sizePercent, 100, 70, 150),
        }
        pcall(function()
            local value = Teleports:GetTeleportSetting('UNKNOWNAutoJoinMinValueV1')
            if Policy.finite(value) and value >= 1e9 and value <= 50e9 then settings.autoJoinMinValue = value end
            local enabled = Teleports:GetTeleportSetting('UNKNOWNAutoJoinEnabledV1')
            if type(enabled) == 'boolean' then settings.autoJoinEnabled = enabled end
            local execute = Teleports:GetTeleportSetting('UNKNOWNAutoExecuteV1')
            if type(execute) == 'boolean' then settings.autoExecute = execute end
        end)
        othersOnly, serversMinValue, autoJoinMinValue = settings.myServer, settings.serversMinValue, settings.autoJoinMinValue
        state.autoJoin = settings.autoJoinEnabled; autoExecuteEnabled = settings.autoExecute
        local joinedEgg
        pcall(function()
            local value = Teleports:GetTeleportSetting(BUILD.joinedKey)
            if type(value) == 'table' and type(value.uid) == 'string' and type(value.jobId) == 'string' and Policy.finite(value.placeId) then joinedEgg = value end
        end)
        D.joinedEgg = joinedEgg
        local ui, steal, webhook, wakeAutoJoin, queueRender
        local lastSaved = ''
        local function saveSettings()
            local data = Http:JSONEncode(settings)
            if data == lastSaved then return end
            pcall(function()
                Teleports:SetTeleportSetting('UNKNOWNAutoJoinMinValueV1', settings.autoJoinMinValue)
                Teleports:SetTeleportSetting('UNKNOWNAutoJoinEnabledV1', settings.autoJoinEnabled)
                Teleports:SetTeleportSetting('UNKNOWNAutoExecuteV1', settings.autoExecute)
            end)
            if type(writefile) == 'function' then pcall(writefile, settingsPath, data) end
            lastSaved = data
        end
        local function saveJoined()
            D.joinedEgg = joinedEgg
            pcall(function() Teleports:SetTeleportSetting(BUILD.joinedKey, joinedEgg or {}) end)
        end
        local function trackedHere()
            if joinedEgg and joinedEgg.placeId == game.PlaceId and joinedEgg.jobId == game.JobId
                and not joinedEgg.plantedAt and (not joinedEgg.takenAt or joinedEgg.pickedByUs) then return joinedEgg end
            return nil
        end
        local perks = createMovementPerks({player = D.player, input = game:GetService('UserInputService'), settings = settings})
        local traps = createTrapIndex({world = workspace, tags = game:GetService('CollectionService')})
        local nav = createGroundNavigator({world = workspace, run = game:GetService('RunService'), player = D.player,
            players = Players, traps = traps, pathfinding = game:GetService('PathfindingService'), live = function() return active end,
            onAcquire = function() perks:suspend() end, onRelease = function() perks:resume() end})
        local stealDeps = {
            nav = nav, eggState = D.eggState, identity = D.identity, plot = D.plot, player = D.player, run = game:GetService('RunService'),
            resolve = D.resolve, entries = D.entries, live = function() return active end,
            enabled = function() return settings.autoSteal end, autoJoin = function() return state.autoJoin end,
            joining = function() return state.joining end, minimum = function() return autoJoinMinValue end,
            minRank = function() return minRank end, tracked = trackedHere,
            phase = function(name, detail)
                state.phase, state.detail = name, detail
                if ui then ui:phaseText(name, detail) end
            end,
            picked = function(uid)
                if joinedEgg and joinedEgg.uid == uid and joinedEgg.jobId == game.JobId then
                    joinedEgg.takenAt = os.time(); joinedEgg.pickedByUs = true; saveJoined()
                end
            end,
            planted = function(uid, target)
                if joinedEgg and joinedEgg.uid == uid and joinedEgg.jobId == game.JobId then joinedEgg.plantedAt = os.time(); saveJoined() end
                if webhook then
                    local event = table.clone(target or {uid = uid, name = uid})
                    event.placeId, event.jobId, event.confirmedAt = game.PlaceId, game.JobId, workspace:GetServerTimeNow()
                    webhook:send(event, false)
                end
            end,
        }
        -- Start the controller BEFORE constructing the interface or starting any HTTP.
        steal = createStealController(stealDeps)
        local function notice(text)
            queryStatus = text; state.noticeUntil = os.clock() + 5
            if ui then ui.status.Text = text; ui.settingsStatus.Text = text end
        end
        webhook = createWebhook({settings = settings, request = requestFn, http = Http, money = money,
            live = function() return active end, notice = notice})
        ui = createObsidianUI(D, settings, {
            notice = notice,
            testWebhook = function() webhook:send({}, true) end,
            change = function(key, value)
                settings[key] = value
                if key == 'autoExecute' then autoExecuteEnabled = value; if value then task.defer(queueAutoExecute) end
                elseif key == 'autoSteal' then if not value then steal:cancel('Auto steal disabled') else steal:wake() end
                elseif key == 'speedBoost' or key == 'boostSpeed' then perks:apply()
                elseif key == 'autoJoinMinValue' then
                    autoJoinMinValue = value; state.failed = {}; feedAt = -math.huge
                    if wakeAutoJoin then wakeAutoJoin() end
                elseif key == 'serversMinValue' then serversMinValue = value; if queueRender then queueRender() end end
                saveSettings(); if ui then ui:paintAuto(state.autoJoin) end
            end,
        })
        local list, status, refreshButton, resetTimer = ui.list, ui.status, ui.refresh, ui.resetTimer
        local aliveMessage = ui.empty
        local loadingVisible, refreshing = true, false
        local function loadingText(now) return 'Reading live eggs' .. string.rep('·', math.floor(now / 0.35) % 3 + 1) end
        ui:paintScope(othersOnly); ui:paintAuto(state.autoJoin); ui:phaseText(state.phase, state.detail)
        D.gui.Destroying:Connect(function()
            steal:destroy(); nav:destroy(); perks:destroy(); traps:destroy(); webhook:destroy()
        end)
        -- A late-replicating optional module is retried without gating startup.
        task.spawn(function()
            while active and (not stealDeps.plot or not stealDeps.identity) do
                stealDeps.plot = stealDeps.plot or D.plot
                stealDeps.identity = stealDeps.identity or D.identity
                task.wait(0.1)
            end
        end)
        task.defer(queueAutoExecute)
        saveSettings()
        local function setScope(value)
            if othersOnly == value then return end
            othersOnly = value; settings.myServer = value; queryEpoch += 1; feedAt = -math.huge
            ui:paintScope(value); list.CanvasPosition = Vector2.zero; saveSettings()
            if queueRender then queueRender() end
        end
        ui.scope.Activated:Connect(function() setScope(false) end)
        ui.myScope.Activated:Connect(function() setScope(true) end)
        ui.autoJoin.Activated:Connect(function()
            state.autoJoin = not state.autoJoin; settings.autoJoinEnabled = state.autoJoin
            state.failed = {}; state.nextJoinAt = 0; feedAt = -math.huge
            ui:paintAuto(state.autoJoin); saveSettings()
            if state.autoJoin then if wakeAutoJoin then wakeAutoJoin() end; steal:wake() end
        end)

        -- Each lane owns its timeout. Broadcast/pagination can never hold up a claim.
        local lanes = {}
        local function network(url, method, body, headers, raw, lane)
            if type(requestFn) ~= 'function' then return nil, 'Executor HTTP unavailable' end
            lane = lane or (url:find('/v1/join', 1, true) and 'claim' or url:find('/v1/report', 1, true) and 'broadcast' or 'config')
            if lanes[lane] then return nil, 'Request already pending' end
            local ticket = {}; lanes[lane] = ticket
            local timeout = lane == 'claim' and 3 or lane == 'head' and 3 or 6
            local ok, response = boundedCall(timeout + 1, function() return active end, function()
                return requestFn({Url = url, Method = method, Headers = headers or {}, Body = body, Timeout = timeout})
            end)
            if lanes[lane] == ticket then lanes[lane] = nil end
            if not ok or type(response) ~= 'table' then return nil, ok and 'Invalid response' or 'Request failed / timed out' end
            local code = tonumber(response.StatusCode or response.Status)
            local decoded, data = pcall(Http.JSONDecode, Http, response.Body or '')
            if code ~= 200 then
                local retry = type(response.Headers) == 'table' and tonumber(response.Headers['Retry-After'] or response.Headers['retry-after'])
                return nil, 'HTTP ' .. tostring(code), code == 429 and math.clamp(retry or 2, 1, 120) or nil
            end
            if raw then return response.Body end
            if not decoded or type(data) ~= 'table' then return nil, 'Invalid JSON response' end
            return data
        end
        local featureSending = false
        local function optionalFeatureSync(payload)
            if not featureConfig or featureSending or type(requestFn) ~= 'function' then return end
            featureSending = true
            task.spawn(function()
                local cfg = featureConfig
                local data = network(cfg.endpoint .. '/v1/report', 'POST', Http:JSONEncode(payload),
                    {['Content-Type'] = 'application/json', ['X-NYX-Room'] = cfg.roomKey}, nil, 'feature')
                featureSending = false
                if active then D.gui:SetAttribute('TenshiFeatureReportOK', data ~= nil) end
            end)
        end
        local function acceptConfig(data)
            return type(data) == 'table' and type(data.endpoint) == 'string'
                and data.endpoint:match('^https://[%w%.%-]+$') and type(data.roomKey) == 'string'
        end
        local function loadConfig()
            local data, err = network('https://raw.githubusercontent.com/syss1211/Tenshi-script/main/NYX-Finder-Config.json?nyx=' .. os.time(), 'GET')
            if not acceptConfig(data) then return false, err or 'Finder configuration unavailable' end
            publicBroadcastConfig = data; config = featureConfig or data; configAt = os.clock()
            pcall(function() Teleports:SetTeleportSetting('UNKNOWNFinderConfigV1', data) end)
            return true
        end
        pcall(function()
            local cached = Teleports:GetTeleportSetting('UNKNOWNFinderConfigV1')
            if acceptConfig(cached) then publicBroadcastConfig, config = cached, cached end
        end)
        local function headers() return {['Content-Type'] = 'application/json', ['X-NYX-Room'] = config.roomKey} end
        local broadcastInterval = 5
        local function snapshot()
            local eggs = {}
            for _, entry in ipairs(D.entries()) do
                if not entry.unresolved and entry.uid and entry.rate and entry.rate > 0 then
                    eggs[#eggs + 1] = {uid = tostring(entry.uid), name = entry.name, category = entry.category, rarity = entry.rarity,
                        rank = entry.tier, rate = entry.rate, scale = entry.scale, weight = entry.weight, icon = entry.icon,
                        area = entry.areaKey or entry.area, mutations = entry.mutationText or '', traitsKnown = entry.traitsKnown ~= false,
                        estimated = entry.estimated == true, visualId = entry.visualId == true, source = entry.isEvent and 'event' or 'field'}
                end
            end
            table.sort(eggs, function(a, b) return a.rate > b.rate end)
            while #eggs > 10 do eggs[#eggs] = nil end
            return eggs
        end
        local function report()
            if game.JobId == '' then return false, 'No live server ID' end
            if not D.ready() then return false, 'Waiting for field scan' end
            if not publicBroadcastConfig then return false, 'Connecting to Finder' end
            local eggs, metadata = snapshot(), D.metadata()
            local classicEggs = eggs
            if metadata and type(metadata.states) == 'table' then
                local states, filtered = {}, {}
                for _, item in ipairs(metadata.states) do states[item.uid] = item.state end
                for _, egg in ipairs(eggs) do if egg.source == 'event' or states[egg.uid] == D.states.Slot then filtered[#filtered + 1] = egg end end
                classicEggs = filtered
            end
            local body = {placeId = game.PlaceId, jobId = game.JobId, reporterId = reporterId, eggs = classicEggs}
            local cfg = publicBroadcastConfig
            local data, err = network(cfg.endpoint .. '/v1/report', 'POST', Http:JSONEncode(body),
                {['Content-Type'] = 'application/json', ['X-NYX-Room'] = cfg.roomKey})
            if not data or data.ok ~= true or not Policy.finite(data.accepted) then return false, err or 'Broadcast not acknowledged' end
            if #classicEggs > 0 and data.accepted <= 0 then return false, 'Broadcast accepted zero eggs' end
            D.gui:SetAttribute('TenshiPublicAccepted', data.accepted); D.gui:SetAttribute('TenshiPublicSent', #classicEggs)
            local native = {placeId = game.PlaceId, jobId = game.JobId, reporterId = reporterId, eggs = eggs,
                publicDirect = true, primaryAccepted = data.accepted, primarySent = #classicEggs}
            if metadata then
                native.eggStates = metadata.states; native.resetAt = metadata.resetAt; native.scanAt = metadata.scanAt
                native.scanAgeMs = math.max(0, (os.clock() - metadata.scanClock) * 1000)
                native.resetRemainingMs = metadata.resetAt and math.max(0, metadata.resetAt - workspace:GetServerTimeNow() * 1000)
            end
            native.userId = D.player.UserId; native.playerIds = {}
            for _, member in ipairs(Players:GetPlayers()) do native.playerIds[#native.playerIds + 1] = member.UserId end
            optionalFeatureSync(native)
            return true, 'Shared ' .. tostring(data.accepted) .. ' eggs'
        end
        D.flushReport = report

        local function feedChanged()
            state.feedRevision += 1
            if wakeAutoJoin then wakeAutoJoin() end
            if queueRender then queueRender() end
        end
        local function normalizeEntry(raw)
            if type(raw) ~= 'table' or not Policy.finite(raw.expiresAt) or not Policy.finite(raw.rate)
                or type(raw.jobId) ~= 'string' or raw.uid == nil or not Policy.finite(raw.placeId) then return nil end
            local entry = table.clone(raw)
            entry.uid = tostring(raw.uid):sub(1, 160); entry.jobId = raw.jobId:sub(1, 160)
            entry.key = type(raw.key) == 'string' and raw.key:sub(1, 512) or Policy.id(entry)
            entry.name = tostring(raw.name or 'Unknown egg'):sub(1, 160)
            entry.rarity = tostring(raw.rarity or 'Unknown'):sub(1, 50)
            entry.mutations = tostring(raw.mutations or ''):sub(1, 200)
            entry.rank = Policy.number(raw.rank, 0, 0, 100)
            return entry
        end
        local function refreshPage(offset, forceAll, lane)
            if not config then return nil, 'Finder connecting' end
            local epoch = queryEpoch
            local query = '?localJob=' .. Http:UrlEncode(game.JobId) .. '&placeId=' .. game.PlaceId
                .. '&limit=10&tier=public&minRate=' .. minRate .. '&minRank=' .. minRank .. '&offset=' .. offset
            local cycle = cycleInfo()
            if cycle then query ..= '&cycleRemainingMs=' .. math.max(0, cycle.remaining * 1000) .. '&cycleId=' .. cycle.resetAt end
            if othersOnly and not forceAll then query ..= '&onlyJob=' .. Http:UrlEncode(game.JobId) end
            local data, err, retry = network(config.endpoint .. '/v1/eggs' .. query, 'GET', nil, headers(), nil, lane)
            if epoch ~= queryEpoch then return nil, 'Query changed' end
            if not data or type(data.items) ~= 'table' then return nil, err or 'Invalid feed', retry end
            if Policy.finite(data.serverTime) then clockOffset = data.serverTime / 1000 - os.clock() end
            local now = (os.clock() + clockOffset) * 1000
            local signature = {}
            for _, raw in ipairs(data.items) do
                local entry = normalizeEntry(raw)
                if entry and D.publicEntryAllowed(entry, now) then
                    feedStore[entry.key] = entry; signature[#signature + 1] = entry.key
                end
            end
            for _, raw in ipairs(data.localStates or {}) do
                if type(raw) == 'table' and type(raw.key) == 'string' and Policy.finite(raw.expiresAt) then localStates[raw.key] = raw end
            end
            feed = {}
            for key, entry in pairs(feedStore) do
                if entry.expiresAt <= now or not D.publicEntryAllowed(entry, now) then feedStore[key] = nil
                else feed[#feed + 1] = entry end
            end
            table.sort(feed, function(a, b) if a.rate ~= b.rate then return a.rate > b.rate end; return a.key < b.key end)
            while #feed > 600 do local old = table.remove(feed); feedStore[old.key] = nil end
            for key, entry in pairs(localStates) do if entry.expiresAt <= now then localStates[key] = nil end end
            if offset == 0 then feedAt = os.clock(); refreshing = false; refreshButton.Text = '↻' end
            D.savePublicSightings(); feedChanged()
            return {nextOffset = tonumber(data.nextOffset), signature = table.concat(signature, '|'), count = #data.items}
        end
        local function localBestAutoJoinRate()
            local best = 0
            for _, egg in ipairs(D.entries()) do
                local cooldown = steal.cooldowns[tostring(egg.uid)]
                if (not cooldown or cooldown.untilAt <= os.clock()) and egg.pickable and (egg.rate or 0) >= autoJoinMinValue and (egg.tier or 0) >= minRank
                    and not steal.completed[tostring(egg.uid)] then best = math.max(best, egg.rate or 0) end
            end
            return best
        end
        local currentTrip
        local function failTrip(trip, reason, permanent)
            if currentTrip ~= trip then return end
            state.joining = false; state.joiningKey = nil; currentTrip = nil; state.joinSerial += 1
            local id = Policy.id(trip.target)
            local old = state.failed[id]
            local attempts = (old and old.attempts or 0) + 1
            state.failed[id] = {attempts = attempts, untilAt = os.clock() + Policy.backoff(attempts, 1, 20)}
            if permanent then trip.target.unavailable = true end
            joinedEgg = trip.previous; saveJoined()
            access:clearHop()
            notice(reason)
            if active and state.autoJoin and wakeAutoJoin then wakeAutoJoin() end
        end
        local function rememberJoinedEgg(entry)
            joinedEgg = {placeId = entry.placeId, jobId = entry.jobId, uid = tostring(entry.uid), name = entry.name,
                rate = entry.rate, missingRate = entry.missingRate, scale = entry.scale, weight = entry.weight,
                icon = entry.icon, rarity = entry.rarity, rank = entry.rank or entry.localTier or 0,
                mutations = entry.mutations, traitsKnown = entry.traitsKnown ~= false, area = entry.area, source = entry.source or 'field'}
            saveJoined()
        end
        local function attemptJoin(target, automatic)
            if not active or state.joining or os.clock() < state.nextJoinAt or steal:blocksJoin() then return end
            local now = (os.clock() + clockOffset) * 1000
            if not Policy.remoteEligible(target, now, game.JobId, automatic and autoJoinMinValue or minRate, minRank)
                or not D.publicEntryAllowed(target, now) then return end
            local failed = state.failed[Policy.id(target)]
            if failed and failed.untilAt > os.clock() then return end
            if not config then notice('Finder connecting'); return end
            state.joinSerial += 1
            local trip = {target = target, previous = joinedEgg, serial = state.joinSerial, automatic = automatic,
                placeId = target.placeId, jobId = target.jobId, who = D.player}
            currentTrip = trip; state.joining = true; state.joiningKey = target.key
            local prepared = pcall(function()
                -- Everything that can save/queue/serialize is done BEFORE the reservation.
                if not queueAutoExecute() then error('Auto execute queue failed') end
                saveSettings(); rememberJoinedEgg(target); access:prepareHop(target.placeId, target.jobId)
                trip.claimBody = Http:JSONEncode({placeId = target.placeId, jobId = target.jobId, uid = target.uid,
                    reporterId = reporterId, userId = D.player.UserId})
                trip.headers = headers(); trip.endpoint = config.endpoint .. '/v1/join'
            end)
            if not prepared then failTrip(trip, 'Hop preparation failed; retrying', false); return end
            notice('Claiming ' .. tostring(target.name))
            local claim, claimError, retryAfter = network(trip.endpoint, 'POST', trip.claimBody, trip.headers, nil, 'claim')
            if retryAfter then state.nextJoinAt = os.clock() + retryAfter end
            if not active or currentTrip ~= trip then return end
            if automatic and not state.autoJoin then failTrip(trip, 'Auto Join disabled', false); return end
            if not claim or claim.allowed ~= true then
                failTrip(trip, claim and 'Egg / server unavailable; trying next' or 'Claim failed: ' .. tostring(claimError),
                    claim and (claim.taken == true or claim.takenConfirmed == true or claim.unavailable == true))
                return
            end
            -- Recompute the clock AFTER the HTTP response, not before it.
            local freshNow = (os.clock() + clockOffset) * 1000
            if freshNow >= Policy.joinDeadline(target, claim) then failTrip(trip, 'Report expired during claim; refreshing', true); return end
            if not Policy.remoteEligible(target, freshNow, game.JobId, automatic and autoJoinMinValue or minRate, minRank) then
                failTrip(trip, 'Join criteria changed while claiming', false); return
            end
            if steal:blocksJoin() then failTrip(trip, 'Carrying an egg; stay in this server', false); return end
            notice('Joining ' .. tostring(target.name))
            -- No sleep, report, disk write, queue registration or key request after ACK.
            local ok = pcall(Teleports.TeleportToPlaceInstance, Teleports, trip.placeId, trip.jobId, trip.who)
            if not ok then failTrip(trip, 'Teleport failed; trying next', false); return end
            task.delay(12, function()
                if active and currentTrip == trip then failTrip(trip, 'Teleport timed out; trying next', false) end
            end)
        end
        local joinQueued, joinWorker = false, false
        wakeAutoJoin = function()
            if joinQueued or joinWorker or not active or not state.autoJoin or state.joining or os.clock() < state.nextJoinAt then return end
            joinQueued = true
            task.defer(function()
                joinQueued = false
                if not active or not state.autoJoin or state.joining or steal:blocksJoin() then return end
                joinWorker = true
                local ok = pcall(function()
                    local now = (os.clock() + clockOffset) * 1000
                    local best
                    for _, entry in ipairs(feed) do
                        local failed = state.failed[Policy.id(entry)]
                        if Policy.remoteEligible(entry, now, game.JobId, autoJoinMinValue, minRank)
                            and D.publicEntryAllowed(entry, now) and (not failed or failed.untilAt <= os.clock())
                            and (not best or entry.rate > best.rate) then best = entry end
                    end
                    local localBest = localBestAutoJoinRate()
                    if localBest > 0 and (not best or localBest >= best.rate) then steal:wake(); return end
                    if best then attemptJoin(best, true) end
                end)
                joinWorker = false
                if not ok and currentTrip then failTrip(currentTrip, 'Join worker error; retrying', false) end
            end)
        end
        local failed = Teleports.TeleportInitFailed:Connect(function(who, _, _, placeId, options)
            local trip, destination = currentTrip, nil
            if options then pcall(function() destination = options.ServerInstanceId end) end
            if who == D.player and trip and (not placeId or placeId == trip.placeId)
                and (not destination or destination == '' or destination == trip.jobId) then
                failTrip(trip, 'Teleport rejected; trying next', false)
            end
        end)
        local lastRetryWake = 0
        local retryBeat = game:GetService('RunService').Heartbeat:Connect(function()
            if os.clock() - lastRetryWake >= 0.1 then lastRetryWake = os.clock(); wakeAutoJoin() end
        end)
        D.gui.Destroying:Connect(function() failed:Disconnect(); retryBeat:Disconnect() end)
        local function joinPresentation(entry)
            if entry.takenConfirmed then return 'TAKEN', Palette.raised, false end
            if entry.full or entry.unavailable then return 'FULL', Palette.raised, false end
            if entry.jobId == game.JobId or entry.isLocal then return 'HERE', Palette.raised, false end
            if state.joining and state.joiningKey == entry.key then return 'JOINING…', Palette.accent, false end
            return 'JOIN →', Palette.accent, not state.joining
        end
        local cardsByKey = {}
        local function updateCard(card, entry, rank) ui:updateCard(card, entry, rank, money, joinPresentation) end

    local top5Cache={}
    local top5PendingCache
    local top5Retired={}
    local top5CacheFile='tenshi_beta_top5_cycle_v2.json'
    local top5Saved=''
    local top5WriteAt=-math.huge
    if type(readfile)=='function' then
        pcall(function()
            local saved=Http:JSONDecode(readfile(top5CacheFile))
            if saved.version==1 and type(saved.items)=='table' and type(saved.retired)=='table' then
                top5PendingCache=saved
            end
        end)
    end
    local function saveTop5Cache()
        if type(writefile)~='function' or os.clock()-top5WriteAt<1 then return end
        top5WriteAt=os.clock()
        pcall(function()
            local bytes=Http:JSONEncode({version=1,items=top5Cache,retired=top5Retired})
            if bytes~=top5Saved then writefile(top5CacheFile,bytes);top5Saved=bytes end
        end)
    end

    local retainedLocal={}
    local retiredLocal={}
    local render
    local rendering,renderPending,renderQueued=false,false,false
    queueRender = function()
        if renderQueued or not active then return end
        renderQueued=true
        task.defer(function() renderQueued=false;if active then render() end end)
    end
    local function renderOnce()
        local passEpoch,passScope=queryEpoch,othersOnly
        local batchStarted=os.clock()
        local passDeadline=math.huge
        local function checkpoint()
            if os.clock()-batchStarted<0.003 then return true end
            task.wait()
            batchStarted=os.clock()
            if not active then return false end
            if queryEpoch~=passEpoch or othersOnly~=passScope or (os.clock()+clockOffset)*1000>=passDeadline then
                renderPending=true
                return false
            end
            return true
        end
        local now=(os.clock()+clockOffset)*1000
        local entries={}
        local source,seen={},{}
        local stateByKey={}
        for key,e in pairs(localStates) do if e.expiresAt>now then stateByKey[key]=e end end
        for _,e in ipairs(feed) do if e.expiresAt>now and not isHalloweenEgg(e) then stateByKey[e.key]=e end end
        local metadata=D.metadata and D.metadata()
        local gameNow=workspace:GetServerTimeNow()*1000
        local validLocal=not metadata or not metadata.resetAt or metadata.resetAt-2000>gameNow
        local current=validLocal and D.entries() or {}
        if othersOnly then
            -- MY SERVER is a live local view. ALL-only cache/tombstone rules
            -- must never suppress a record returned by the current field scan.
            local live=D.entries()
            local localCycle=cycleInfo()
            for _,e in ipairs(live) do
                if (e.rate or 0)>=minRate and (e.tier or 0)>=minRank then
                    local uid=tostring(e.uid or e.key)
                    source[#source+1]={key=game.PlaceId..':'..game.JobId..':'..uid,uid=uid,
                        name=e.name,rate=e.rate or 0,missingRate=e.rate==nil,scale=e.scale,weight=e.weight,
                        icon=e.icon,rarity=e.rarity,rank=e.tier,localTier=e.tier,mutations=e.mutationText,
                        traitsKnown=e.traitsKnown~=false,area=e.areaKey or e.area,model=e.model,isLocal=true,
                        source=e.isEvent and 'event' or 'field',estimated=e.estimated or e.unmutatedRate~=nil,
                        placeId=game.PlaceId,jobId=game.JobId,expiresAt=now+5000,seenAt=0,
                        spawnedAt=not e.isEvent and localCycle and localCycle.respawnAt or nil}
                end
            end
            local tracked=D.joinedEgg
            if tracked and not isHalloweenEgg(tracked) and tracked.placeId==game.PlaceId and tracked.jobId==game.JobId then
                -- Missing/streaming records are not proof that another player took the egg.
                if type(tracked.takenAt)=='number' then
                    source[#source+1]={
                        key=game.PlaceId..':'..game.JobId..':joined-taken:'..tracked.uid,uid=tracked.uid,
                        name=tracked.name,rate=tracked.rate or 0,missingRate=tracked.missingRate,
                        scale=tracked.scale,weight=tracked.weight,icon=tracked.icon,rarity=tracked.rarity,
                        rank=tracked.rank or 0,localTier=tracked.rank or 0,mutations=tracked.mutations,
                        traitsKnown=tracked.traitsKnown,area=tracked.area,isLocal=true,source=tracked.source,
                        placeId=game.PlaceId,jobId=game.JobId,expiresAt=now+5000,seenAt=0,
                        takenConfirmed=true,takenAt=tracked.takenAt,trackedTaken=true
                    }
                end
            end
            if D.gui then pcall(function() D.gui:SetAttribute('TenshiLocalScanCount',#live);D.gui:SetAttribute('TenshiLocalVisibleCount',#source) end) end
        else
        for key,e in pairs(retainedLocal) do
            if e.expiresAt<=now then retainedLocal[key]=nil;retiredLocal[key]=now+600000 end
        end
        for key,expiry in pairs(retiredLocal) do if expiry<=now then retiredLocal[key]=nil end end
        if not othersOnly then
            for _,e in ipairs(feed) do
                if not isHalloweenEgg(e) and (e.jobId~=game.JobId or e.unavailable) and (e.rate or 0)>=minRate and (e.rank or 0)>=minRank and type(e.expiresAt)=='number' and e.expiresAt>now then source[#source+1]=e;seen[e.key]=true end
            end
        end
        if metadata and metadata.resetAt and metadata.resetAt>gameNow then
            local states={}
            for _,state in ipairs(metadata.states or {}) do states[state.uid]=state.state end
            for key,e in pairs(retainedLocal) do
                if not isHalloweenEgg(e) and (not states[e.uid] or states[e.uid]==D.states.Claimed) then
                    e.unavailable=true;e.full=true;e.takenConfirmed=true
                    stateByKey[key]=e
                    if not othersOnly and not seen[key] and e.rate>=minRate and (e.localTier or 0)>=minRank then source[#source+1]=e;seen[key]=true end
                end
            end
        end
            local localCycle=cycleInfo()
            for _,e in ipairs(current) do
                if (e.rate or 0)>=minRate and (e.tier or 0)>=minRank then
                    local key=game.PlaceId..':'..game.JobId..':'..tostring(e.uid or e.key)
                    local state=not othersOnly and stateByKey[key] or nil
                    if state and state.unavailable and top5Cache[key] then top5Cache[key].unavailable=true;top5Cache[key].full=true end
                    if not seen[key] and not retiredLocal[key] and not (state and state.unavailable) then
                        seen[key]=true
                        source[#source+1]={key=key,uid=tostring(e.uid or e.key),name=e.name,rate=e.rate or 0,missingRate=e.rate==nil,scale=e.scale,weight=e.weight,icon=e.icon,rarity=e.rarity,mutations=e.mutationText,traitsKnown=e.traitsKnown~=false,area=e.areaKey or e.area,model=e.model,isLocal=true,localTier=e.tier,full=not othersOnly and state and state.full or false,source=e.isEvent and 'event' or 'field',estimated=e.estimated or e.unmutatedRate~=nil,placeId=game.PlaceId,jobId=game.JobId,expiresAt=now+5000,seenAt=0,spawnedAt=not e.isEvent and localCycle and localCycle.respawnAt or nil,spawnTimeKnown=not e.isEvent and localCycle~=nil and type(localCycle.respawnAt)=='number'}
                        if metadata and metadata.resetAt and not e.isEvent then
                            local saved=table.clone(source[#source]);saved.expiresAt=now+metadata.resetAt-gameNow-2000;saved.localTier=e.tier
                            retainedLocal[key]=saved
                        end
                    end
                end
            end
            local cycle=cycleInfo()
            if top5PendingCache and feedAt>0 then
                top5Cache=top5PendingCache.items;top5Retired=top5PendingCache.retired;top5PendingCache=nil
            end
            local cycleEnd=cycle and type(cycle.resetAt)=='number' and now+cycle.resetAt-gameNow-2000 or nil
            local cycleStart=cycleEnd and cycleEnd-298000 or nil
            -- Keep deadlines in the host clock across teleports. Never assign
            -- an old sighting to the next world just because it became FULL late.
            for key,expiry in pairs(top5Retired) do if type(expiry)~='number' or expiry<=now then top5Retired[key]=nil end end
            for key,saved in pairs(top5Cache) do
                if type(saved)~='table' or type(saved.expiresAt)~='number' or saved.expiresAt<=now or saved.expiresAt>now+305000 then
                    top5Cache[key]=nil;top5Retired[key]=now+600000
                end
            end
            local combined,live={},{}
            for _,e in ipairs(source) do
                local old=top5Cache[e.key]
                local expiredLegacy=not e.retentionPinned and e.resetEstimated==true and cycleStart and type(e.seenAt)=='number' and e.seenAt>0 and e.seenAt<cycleStart
                if not top5Retired[e.key] and not expiredLegacy then
                    if old and not e.retentionPinned and not othersOnly then
                        e.expiresAt=math.min(e.expiresAt>now and e.expiresAt or old.expiresAt,old.expiresAt)
                        -- A 90s feed TTL is not the retained card's reset deadline.
                        if old.resetEstimated then e.expiresAt=old.expiresAt end
                        if old.unavailable then e.unavailable=true;e.full=true;e.takenConfirmed=old.takenConfirmed end
                    end
                    combined[#combined+1]=e;live[e.key]=true
                elseif expiredLegacy then
                    top5Cache[e.key]=nil;top5Retired[e.key]=now+600000
                end
            end
            if not othersOnly then
                for key,saved in pairs(top5Cache) do
                    if not live[key] and not top5Retired[key] and saved.expiresAt>now and (saved.rate or 0)>=minRate and (saved.rank or 0)>=minRank then
                        local e=table.clone(saved);e.full=true;e.isLocal=nil
                        combined[#combined+1]=e
                    end
                end
            end
            table.sort(combined,function(a,b) if a.rate~=b.rate then return a.rate>b.rate end;return a.key<b.key end)
            source={}
            local keep={}
            for rank,e in ipairs(combined) do
                local full=e.full or e.unavailable
                if rank<=5 or not full then
                    if not (othersOnly and e.unavailable) then source[#source+1]=e end
                end
                if not othersOnly and rank<=5 and not top5Retired[e.key] then
                    local previous=top5Cache[e.key]
                    local expiry=e.retentionPinned and e.expiresAt or previous and previous.expiresAt
                    if not expiry then
                        if e.isLocal and metadata and metadata.resetAt then expiry=now+metadata.resetAt-gameNow-2000
                        elseif e.resetEstimated==true then expiry=cycleEnd
                        else expiry=e.expiresAt end
                    end
                    if expiry and expiry>now then
                        local saved={}
                        for _,name in ipairs({'key','uid','name','rate','scale','weight','icon','rarity','mutations','traitsKnown','area','source','estimated','placeId','jobId','seenAt','unavailable','resetEstimated','full','retentionPinned','takenConfirmed'}) do saved[name]=e[name] end
                        saved.rank=e.rank or (e.isLocal and e.localTier) or 0
                        saved.expiresAt=expiry;saved.resetEstimated=e.resetEstimated==true
                        top5Cache[e.key]=saved;keep[e.key]=true
                        e.expiresAt=expiry
                    end
                end
            end
            -- Filters and MY SERVER never erase the saved ALL SERVER cards.
            if not othersOnly and minRate==0 and minRank==0 then
                for key in pairs(top5Cache) do if not keep[key] then top5Cache[key]=nil end end
            end
            if not top5PendingCache then saveTop5Cache() end

        end
            if not othersOnly then
                for i=#source,1,-1 do
                    if (tonumber(source[i].rate) or 0)<serversMinValue then table.remove(source,i) end
                end
            end
            table.sort(source,function(a,b) if othersOnly and a.trackedTaken~=b.trackedTaken then return a.trackedTaken==true end; if a.rate~=b.rate then return a.rate>b.rate end; return a.key<b.key end)
            local limit=8
            while #source>limit do source[#source]=nil end
            for i,e in ipairs(source) do e.displayRank=i end
        for priorityRank,entry in ipairs(source) do
            if type(entry)=='table' and type(entry.expiresAt)=='number' and now<entry.expiresAt and type(entry.rate)=='number' and type(entry.jobId)=='string' and D.publicEntryAllowed(entry,now) and (othersOnly or D.publicPriorityVisible(entry,priorityRank)) then
                local visible=table.clone(entry)
                visible.displayRank=#entries+1
                entries[#entries+1]=visible
            end
        end

        local savedScroll = list.CanvasPosition
        local canvasHeight = #entries == 0 and 84 or 4
        local wanted = {}
        for _, entry in ipairs(entries) do wanted[entry.key] = true; passDeadline = math.min(passDeadline, entry.expiresAt) end
        for key, card in pairs(cardsByKey) do
            if not wanted[key] then card.row:Destroy(); cardsByKey[key] = nil end
        end
        loadingVisible = #entries == 0 and (othersOnly and not D.ready() or not othersOnly and feedAt <= 0)
        aliveMessage.Visible = #entries == 0
        aliveMessage.Text = loadingVisible and loadingText(os.clock()) or othersOnly and 'No matching eggs in this server' or 'No matching live reports right now'
        for i, entry in ipairs(entries) do
            local card = cardsByKey[entry.key]
            if not card or not card.row.Parent then
                card = ui:createCard(entry, function(target)
                    if steal:blocksJoin() then notice('Finish the grounded carry before joining another server'); return end
                    local ok = pcall(attemptJoin, target, false)
                    if not ok and currentTrip then failTrip(currentTrip, 'Join failed; try again', false) end
                end)
                cardsByKey[entry.key] = card
            end
            updateCard(card, entry, i)
            canvasHeight += card.row.Size.Y.Offset + 10
            if not checkpoint() then return end
        end
        list.CanvasSize = UDim2.fromOffset(0, canvasHeight)
        list.CanvasPosition = savedScroll; list.Visible = true
        ui.feedCount.Text = tostring(#feed) .. ' LIVE REPORTS'
    end
    render = function()
        if not active then return end
        if rendering then renderPending = true; return end
        rendering = true
        local ok = pcall(renderOnce)
        rendering = false
        if renderPending then renderPending = false; queueRender() end
        if not ok then list.Visible = true; queryStatus = 'Feed display retrying' end
    end
    refreshButton.Activated:Connect(function()
        if not active or refreshing then return end
        refreshing = true; refreshButton.Text = '…'; feedAt = -math.huge
        D.requestScan(); queueRender()
        task.delay(5, function() if active and refreshing then refreshing = false; refreshButton.Text = '↻' end end)
    end)
    D.onScan = function() steal:wake(); if ui.visible then queueRender() end end
    queueRender()

    -- Config and optional feature discovery are independent of reporting and claiming.
    task.spawn(function()
        local nextAttempt = 0
        while active do
            if os.clock() >= nextAttempt and (not publicBroadcastConfig or os.clock() - configAt >= 60) then
                local ok, loaded = pcall(loadConfig)
                nextAttempt = os.clock() + (ok and loaded and 60 or 3)
                if not ok or not loaded then reportStatus = 'Finder connecting; local automation remains ready' end
            end
            task.wait(0.1)
        end
    end)
    task.spawn(function()
        while active do
            local data = network('https://raw.githubusercontent.com/syss1211/Tenshi-script/experimental/NYX-Finder-Experimental-Config.json?features=' .. os.time(), 'GET', nil, nil, nil, 'featureConfig')
            if acceptConfig(data) then
                featureConfig = data
                if publicBroadcastConfig then config = data; feedAt = -math.huge end
            end
            task.wait(60)
        end
    end)
    -- Fast, single-flight HEAD polling. Publish each response and wake the join worker
    -- immediately, instead of waiting for 30 pages, a report, or a quarter-second timer.
    state.feedRetryAt = 0
    task.spawn(function()
        local failures = 0
        while active do
            local interval = state.autoJoin and 0.2 or 0.8
            if config and not state.joining and os.clock() >= state.feedRetryAt and os.clock() - feedAt >= interval then
                local ok, result, err, retry = pcall(refreshPage, 0, state.autoJoin, 'head')
                if ok and result then
                    state.headCursor = result.nextOffset; failures = 0
                    if queryStatus:sub(1, 5) == 'Feed:' then queryStatus = '' end
                else
                    failures += 1
                    state.feedRetryAt = os.clock() + (retry or Policy.backoff(failures, 0.5, 12))
                    queryStatus = 'Feed: ' .. tostring(ok and err or 'retrying after response error')
                end
            end
            task.wait(0.03)
        end
    end)
    -- Lower-priority pagination has its OWN lane. It cannot delay a fresh first page.
    task.spawn(function()
        while active do
            if config and feedAt > 0 and not state.joining and (state.autoJoin or not othersOnly) and os.clock() >= state.feedRetryAt then
                local epoch, offset, count, previous = queryEpoch, state.headCursor, 1, nil
                while active and not state.joining and epoch == queryEpoch and Policy.finite(offset) and offset > 0 and count < 30 do
                    local ok, data, _, retry = pcall(refreshPage, offset, true, 'pages')
                    if not ok or not data then
                        if retry then state.feedRetryAt = os.clock() + retry end
                        break
                    end
                    count += 1
                    if data.count == 0 or data.signature == previous or not Policy.finite(data.nextOffset) or data.nextOffset <= offset then break end
                    previous, offset = data.signature, data.nextOffset
                    task.wait(0.12)
                end
            end
            task.wait(state.autoJoin and 0.6 or 2)
        end
    end)
    task.spawn(function()
        local lastReport, nextAttempt, lastSignature, failures = -math.huge, 0, nil, 0
        while active do
            if publicBroadcastConfig and not state.joining and os.clock() >= nextAttempt then
                local parts = {}
                for _, egg in ipairs(snapshot()) do
                    parts[#parts + 1] = table.concat({tostring(egg.uid), tostring(egg.rate), tostring(egg.scale), tostring(egg.weight), tostring(egg.mutations)}, ':')
                end
                local metadata = D.metadata()
                for _, item in ipairs(metadata and metadata.states or {}) do parts[#parts + 1] = tostring(item.uid) .. '=' .. tostring(item.state) end
                table.sort(parts)
                local signature = table.concat(parts, ';')
                if signature ~= lastSignature or os.clock() - lastReport >= broadcastInterval then
                    local ok, shared, message = pcall(report)
                    if ok and shared then
                        lastSignature = signature; lastReport = os.clock(); failures = 0; reportStatus = message; nextAttempt = os.clock() + 0.15
                    else
                        failures += 1; nextAttempt = os.clock() + Policy.backoff(failures, 1, 12)
                        reportStatus = ok and tostring(message) or 'Broadcast retrying'
                    end
                end
            end
            task.wait(0.05)
        end
    end)
    task.spawn(function()
        while active do
            status.Text = state.noticeUntil and os.clock() < state.noticeUntil and queryStatus or state.joining and 'JOINING SERVER…' or state.phase ~= 'READY' and (state.phase .. ' / ' .. state.detail)
                or queryStatus ~= '' and queryStatus or reportStatus
            local cycle = cycleInfo()
            if cycle then
                local seconds = math.max(0, math.ceil(cycle.remaining))
                resetTimer.Text = cycle.running and string.format('RESET %02d:%02d', math.floor(seconds / 60), seconds % 60) or 'RESET PAUSED'
                resetTimer.TextColor3 = seconds <= 60 and Palette.danger or Palette.muted
            else resetTimer.Text = 'RESET --:--' end
            if ui.visible then queueRender() end
            D.gui:SetAttribute('UnknownStealPhase', state.phase)
            D.gui:SetAttribute('UnknownGroundRouteActive', nav.busy)
            task.wait(0.2)
        end
    end)
    end -- createFinder

    -- [6] Replicated field scanner. A tracked UID is resolved directly between scans.
    local function runFinder()
        local EggState, Assets, States
        while alive do
            local ok = pcall(function()
                EggState = module('Client.EggState'); States = module('Shared.Types.AreaEggs').States
                assert(type(EggState.ReadFieldEggs) == 'function' and States.Slot ~= nil, 'Game schema not ready')
            end)
            if ok then break end
            task.wait(0.1)
        end
        if not alive then return end
        local mutations, eggRecords, cycle
        local latestEntries, latestMetadata, lastScan = {}, nil, -math.huge
        local D = {gui = gui, player = player, eggState = EggState, states = States,
            entries = function() return os.clock() - lastScan < 2 and latestEntries or {} end,
            metadata = function() return latestMetadata end, ready = function() return os.clock() - lastScan < 2 end, money = money}
        local function warm(path, accept)
            task.spawn(function()
                while alive do
                    local ok, value = pcall(module, path)
                    if ok and value ~= nil then accept(value); return end
                    task.wait(0.1)
                end
            end)
        end
        -- Optional requires run independently: even an internally yielding module
        -- cannot delay a tracked pickup or the other module loaders.
        warm('Data.Assets', function(value) Assets = value end)
        warm('Shared.Modules.Mutations', function(value) mutations = value end)
        warm('Shared.Util.EggRecords', function(value) eggRecords = value end)
        warm('Shared.Util.AreaEggSlotIdentity', function(value) D.identity = value end)
        warm('Client.PlotState', function(value) D.plot = value end)
        warm('Shared.Util.AreaEggCycle', function(value) cycle = value; D.cycle = value end)
        local function entryFor(key, record, enrich)
            local asset = Assets and type(Assets.Directory) == 'table' and Assets.Directory[record.AssetCategory] or {}
            local rarity, uid = asset.Rarity or {}, record.Uid or key
            local model = modelFor(uid)
            local scale = numberField(record, {'AssetScale'})
            local weight
            if enrich and eggRecords and type(eggRecords.WeightKg) == 'function' then
                local ok, value = pcall(eggRecords.WeightKg, record); if ok and valid(value) then weight = value end
            end
            local rate = enrich and displayedRate(model) or nil
            local estimated = false
            if not rate then rate = computedRate(asset.EarningRate, scale, record.Mutations or {}, mutations); estimated = rate ~= nil end
            local traits, known = readTraitNames(record)
            local position = typeof(record.BottomCFrame) == 'CFrame' and record.BottomCFrame.Position
                or model and model:GetPivot().Position or nil
            return {key = 'field:' .. tostring(uid), uid = tostring(uid), traitsKnown = known, category = record.AssetCategory,
                areaKey = record.AreaId, nestId = record.NestId, worldPos = position, area = tostring(record.AreaId), model = model,
                icon = asset.Icon, name = asset.DisplayName or record.AssetCategory or 'Unknown', rarity = rarity.DisplayName or rarity._id or 'Unknown',
                tier = tonumber(rarity.Rank) or 0, scale = scale, weight = weight, rate = rate, estimated = estimated,
                mutationText = #traits > 0 and table.concat(traits, ', ') or known and 'None' or 'UNKNOWN',
                pickable = record.State == States.Slot or record.State == States.Dropped, fieldState = record.State}
        end
        D.resolve = function(uid)
            local ok, snapshot = pcall(EggState.ReadFieldEggs)
            if not ok or type(snapshot) ~= 'table' or type(snapshot.Records) ~= 'table' then return nil end
            for key, record in pairs(snapshot.Records) do
                if type(record) == 'table' and tostring(record.Uid or key) == uid then return entryFor(key, record, false) end
            end
            return nil
        end
        local scanning = false
        local function scan()
            if scanning or not alive then return end
            scanning = true
            local ok = pcall(function()
                local snapshot = EggState.ReadFieldEggs()
                assert(type(snapshot) == 'table' and type(snapshot.Records) == 'table', 'Field snapshot not ready')
                local eggs, fieldStates = {}, {}
                local scanClock, scanAt, resetAt = os.clock(), workspace:GetServerTimeNow() * 1000, nil
                if cycle then pcall(function() if cycle.IsRunning() then resetAt = cycle.NextResetTime(scanAt / 1000) * 1000 end end) end
                for key, record in pairs(snapshot.Records) do
                    if type(record) == 'table' then
                        fieldStates[#fieldStates + 1] = {uid = tostring(record.Uid or key), state = record.State}
                        if record.State == States.Slot or record.State == States.Dropped or record.State == States.Carried or record.State == States.GuardCarried then eggs[#eggs + 1] = entryFor(key, record, true) end
                    end
                end
                latestEntries = eggs; latestMetadata = {states = fieldStates, resetAt = resetAt, scanAt = scanAt, scanClock = scanClock}; lastScan = os.clock()
            end)
            scanning = false
            if ok and D.onScan then D.onScan() end
        end
        D.requestScan = function() task.defer(scan) end
        scan() -- a fresh local snapshot exists before UI/network startup
        createFinder(D)
        while alive do scan(); task.wait(0.15) end
    end
    task.spawn(function()
        local ok, err = pcall(runFinder)
        if not ok then
            warn('[UNKNOWN] Finder stopped: ' .. tostring(err))
            stop()
        end
    end)
    return function() return alive end
end

-- [7] KEY GATE · first launch online; recent one-use hop session + background check.
local function runAccessSystem()
    local env = environment()
    if env.__UNKNOWN_RUNNING_JOB == game.JobId and env.__UNKNOWN_BUILD == BUILD.name and type(env.__UNKNOWN_STOP_ACTIVE) == 'function' then return end
    if type(env.__UNKNOWN_AUTH_STOP) == 'function' then pcall(env.__UNKNOWN_AUTH_STOP) end
    local Http, Teleports = game:GetService('HttpService'), game:GetService('TeleportService')
    local player = game:GetService('Players').LocalPlayer
    if not player then return end
    local req = request or http_request or (syn and syn.request) or (http and http.request)
    local auth = {active = true, running = false, key = nil, verifiedAt = -math.huge, expiresAt = nil, checker = false, busy = false}
    local gate, liveFinder, makeGate, checkLoop
    env.__UNKNOWN_AUTH_STOP = function()
        auth.active = false
        if gate and gate.gui.Parent then gate.gui:Destroy() end
    end
    function auth:clearHop() pcall(function() Teleports:SetTeleportSetting(BUILD.sessionKey, {}) end) end
    function auth:prepareHop(placeId, jobId)
        local now = os.time()
        if not self.key or now - self.verifiedAt > 120 or self.expiresAt and now >= self.expiresAt then self:clearHop(); return end
        pcall(function()
            Teleports:SetTeleportSetting(BUILD.sessionKey, {version = 1, key = self.key, verifiedAt = self.verifiedAt,
                expiresAt = self.expiresAt, hopAt = now, fromJob = game.JobId, placeId = placeId, jobId = jobId})
        end)
    end
    local function verify(key)
        if type(req) ~= 'function' then return 'transient', 'Executor HTTP is unavailable.' end
        local ok, response = boundedCall(8, function() return auth.active end, function()
            return req({Url = BUILD.verifyUrl, Method = 'POST', Timeout = 6,
                Headers = {['Content-Type'] = 'application/json'}, Body = Http:JSONEncode({key = key})})
        end)
        if not ok or type(response) ~= 'table' then return 'transient', 'Connection failed. Try again.' end
        local code = tonumber(response.StatusCode or response.Status)
        local decoded, data = pcall(Http.JSONDecode, Http, response.Body or response.body or '')
        if not decoded or type(data) ~= 'table' then return 'transient', 'Validation is temporarily unavailable.' end
        if code == 200 and data.valid == true then return 'valid', data end
        if (code == 200 or code == 401 or code == 403) and data.valid == false then
            return 'invalid', data.reason == 'expired' and 'Key expired. Enter a new key.' or 'Invalid or revoked key.'
        end
        return 'transient', 'Validation is temporarily unavailable.'
    end
    local function accept(key, data)
        auth.key = key; auth.verifiedAt = os.time(); auth.expiresAt = nil
        if Policy.finite(data.expiresAt) then auth.expiresAt = data.expiresAt > 1e11 and data.expiresAt / 1000 or data.expiresAt end
        if type(writefile) == 'function' then pcall(writefile, 'unknown_saved_access_key.txt', key) end
    end
    local function launch()
        if auth.running or not auth.active then return end
        if gate and gate.gui.Parent then gate.gui:Destroy(); gate = nil end
        env.__UNKNOWN_RUNNING_JOB = game.JobId; env.__UNKNOWN_BUILD = BUILD.name
        local ok, live = pcall(startUnknown, auth)
        if not ok or type(live) ~= 'function' then
            env.__UNKNOWN_RUNNING_JOB = nil; auth.running = false
            makeGate(); if gate then gate:setStatus('Startup failed. Check the game is fully loaded.', Palette.danger) end
            return
        end
        liveFinder = live; auth.running = true
    end
    local function revoke(reason)
        auth.running = false; auth:clearHop()
        if type(env.__UNKNOWN_STOP_ACTIVE) == 'function' then pcall(env.__UNKNOWN_STOP_ACTIVE) end
        if type(delfile) == 'function' then pcall(delfile, 'unknown_saved_access_key.txt') end
        if auth.active then makeGate(); if gate then gate:setStatus(reason, Palette.danger) end end
    end
    checkLoop = function(immediate)
        if auth.checker then return end
        auth.checker = true
        task.spawn(function()
            local nextCheck, failures = os.clock() + (immediate and 0 or 60), 0
            while auth.active and auth.running and liveFinder and liveFinder() do
                if auth.expiresAt and os.time() >= auth.expiresAt then revoke('Key expired. Enter a new key.'); break end
                if os.clock() >= nextCheck then
                    local result, data = verify(auth.key)
                    if not auth.active or not auth.running or not liveFinder or not liveFinder() then break end
                    if result == 'invalid' then revoke(data); break
                    elseif result == 'valid' then accept(auth.key, data); failures = 0; nextCheck = os.clock() + 60
                    else failures += 1; nextCheck = os.clock() + Policy.backoff(failures, 5, 30) end
                end
                task.wait(0.2)
            end
            auth.checker = false
        end)
    end
    local function submit()
        if auth.busy or not auth.active or not gate then return end
        local key = gate.input.Text:match('^%s*(.-)%s*$')
        if key == '' then gate:setStatus('Enter your access key.', Palette.accent); return end
        auth.busy = true; gate.button.Text = 'CHECKING…'; gate:setStatus('Securely checking your key…', Palette.muted)
        local result, data = verify(key)
        auth.busy = false
        if not auth.active or not gate then return end
        gate.button.Text = 'UNLOCK UNKNOWN'
        if result == 'valid' then
            accept(key, data); launch(); checkLoop(false)
        else gate:setStatus(data, result == 'invalid' and Palette.danger or Palette.accent) end
    end
    makeGate = function()
        if gate and gate.gui.Parent then return end
        local parent = player:FindFirstChild('PlayerGui') or player:WaitForChild('PlayerGui', 15)
        if not parent then return end
        local old = parent:FindFirstChild('UNKNOWN_KeySystem'); if old then old:Destroy() end
        local gui = Kit.make('ScreenGui', {Name = 'UNKNOWN_KeySystem', ResetOnSpawn = false, IgnoreGuiInset = false,
            DisplayOrder = 1200, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, parent)
        pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
        local frame = Kit.make('CanvasGroup', {Name = 'AccessCard', AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(380, 326), BackgroundColor3 = Palette.bg,
            BorderSizePixel = 0, ZIndex = 2}, gui)
        Kit.round(frame, 22); Kit.stroke(frame, Palette.accent, 0.6)
        local kicker = Kit.text(frame, 'UNKNOWN  /  OBSIDIAN', UDim2.fromOffset(22, 22), UDim2.new(1, -44, 0, 20), Palette.accent, 11)
        kicker.Font = Enum.Font.GothamBold
        Kit.text(frame, 'Your next discovery.', UDim2.fromOffset(22, 53), UDim2.new(1, -44, 0, 32), Palette.text, 24).Font = Enum.Font.GothamBold
        Kit.text(frame, 'One key. A quieter kind of power.', UDim2.fromOffset(22, 93), UDim2.new(1, -44, 0, 22), Palette.muted, 12)
        local input = Kit.input(frame, 'TF-XXXX-XXXX', UDim2.fromOffset(22, 136), UDim2.new(1, -44, 0, 56))
        local button = Kit.button(frame, 'UNLOCK UNKNOWN', UDim2.fromOffset(22, 206), UDim2.new(1, -44, 0, 56))
        button.BackgroundColor3 = Palette.accent; button.TextColor3 = Palette.bg
        local status = Kit.text(frame, 'An online check is required on first launch.', UDim2.fromOffset(22, 278), UDim2.new(1, -44, 0, 32), Palette.muted, 11)
        status.TextWrapped = true; status.TextXAlignment = Enum.TextXAlignment.Center
        gate = {gui = gui, input = input, button = button}
        function gate:setStatus(text, color) if status.Parent then status.Text = text; status.TextColor3 = color end end
        local gateScale = Kit.make('UIScale', {Scale = 1}, frame)
        local function fit()
            local view = gui.AbsoluteSize
            if view.X <= 0 or view.Y <= 0 then return end
            local scale = math.min(1, (view.Y - 24) / 326)
            gateScale.Scale = scale
            frame.Size = UDim2.fromOffset(math.min(380, (view.X - 24) / scale), 326)
        end
        local resize = gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(fit)
        gui.Destroying:Connect(function() resize:Disconnect() end)
        fit(); task.defer(fit)
        button.Activated:Connect(function() task.spawn(submit) end)
        input.FocusLost:Connect(function(enter) if enter then task.spawn(submit) end end)
        frame.GroupTransparency = 1
        game:GetService('TweenService'):Create(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {GroupTransparency = 0}):Play()
    end

    local savedKey, session
    if type(readfile) == 'function' then pcall(function() savedKey = readfile('unknown_saved_access_key.txt'):match('^%s*(.-)%s*$') end) end
    pcall(function() session = Teleports:GetTeleportSetting(BUILD.sessionKey) end)
    local candidate = type(savedKey) == 'string' and savedKey ~= '' and savedKey or type(session) == 'table' and session.key
    local resume = Policy.resume(session, candidate, game.PlaceId, game.JobId, os.time())
    auth:clearHop() -- consume once, including malformed/stale/wrong-destination tickets
    if resume then
        auth.key, auth.verifiedAt, auth.expiresAt = candidate, session.verifiedAt, session.expiresAt
        launch() -- no validation HTTP or key UI in the hop's startup path
        checkLoop(true)
    else
        makeGate()
        if gate and type(savedKey) == 'string' and savedKey ~= '' then gate.input.Text = savedKey; task.defer(submit) end
    end
end
runAccessSystem()
