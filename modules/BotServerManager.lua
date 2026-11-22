--!strict
-- MARVIN Bot/Normal Server Manager (isolated module)
-- UI + session registry only. It does not log into Roblox accounts or automate game clients.
-- Place as a ModuleScript named BotServerManager in an authorized Roblox experience.

local BotServerManager = {}
BotServerManager.__index = BotServerManager

export type Session = {
    id: string,
    name: string,
    kind: "bot" | "normal",
    placeId: number?,
    jobId: string?,
    status: string?,
    detail: string?,
}

export type Options = {
    parent: Instance,
    onSelect: ((Session) -> ())?,
    onCreateBot: (() -> ())?,
    onStart: ((Session) -> ())?,
    onStop: ((Session) -> ())?,
}

local COLORS = {
    background = Color3.fromRGB(18, 21, 30),
    panel = Color3.fromRGB(27, 32, 44),
    selected = Color3.fromRGB(55, 91, 150),
    text = Color3.fromRGB(239, 243, 250),
    muted = Color3.fromRGB(157, 169, 188),
    green = Color3.fromRGB(47, 166, 111),
    red = Color3.fromRGB(190, 72, 72),
}

local function make(className: string, props: {[string]: any}, parent: Instance): Instance
    local obj = Instance.new(className)
    for key, value in pairs(props) do
        (obj :: any)[key] = value
    end
    obj.Parent = parent
    return obj
end

local function corner(parent: Instance, radius: number)
    make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function BotServerManager.new(options: Options)
    assert(options and options.parent, "BotServerManager requires options.parent")
    local self = setmetatable({}, BotServerManager)
    self._options = options
    self._sessions = {} :: {Session}
    self._filter = "all"
    self._selectedId = nil

    local root = make("Frame", {
        Name = "MarvinServerManager",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = COLORS.background,
        BorderSizePixel = 0,
    }, options.parent)
    self.Root = root
    corner(root, 12)

    make("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(16, 12),
        Size = UDim2.new(1, -32, 0, 30),
        BackgroundTransparency = 1,
        Text = "MARVIN  /  SERVER MANAGER",
        TextColor3 = COLORS.text,
        TextSize = 17,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, root)

    local tabs = make("Frame", {
        Name = "CategoryTabs",
        Position = UDim2.fromOffset(12, 52),
        Size = UDim2.new(1, -24, 0, 38),
        BackgroundTransparency = 1,
    }, root)
    local tabLayout = make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, tabs)
    tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local list = make("ScrollingFrame", {
        Name = "SessionList",
        Position = UDim2.fromOffset(12, 100),
        Size = UDim2.new(1, -24, 1, -112),
        BackgroundColor3 = COLORS.panel,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        CanvasSize = UDim2.fromOffset(0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, root)
    corner(list, 9)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
    }, list)
    make("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, list)

    self._list = list
    self._tabButtons = {}

    local function setFilter(filter: string)
        self._filter = filter
        for name, button in pairs(self._tabButtons) do
            button.BackgroundColor3 = (name == filter) and COLORS.selected or COLORS.panel
        end
        self:Render()
    end

    local definitions = {
        { id = "all", label = "ALL" },
        { id = "bot", label = "🤖 BOT SERVERS" },
        { id = "normal", label = "👥 NORMAL SERVERS" },
    }
    for index, definition in ipairs(definitions) do
        local button = make("TextButton", {
            Name = definition.id .. "Tab",
            Size = UDim2.new(0, index == 1 and 66 or 150, 1, 0),
            BackgroundColor3 = COLORS.panel,
            BorderSizePixel = 0,
            Text = definition.label,
            TextColor3 = COLORS.text,
            TextSize = 11,
            Font = Enum.Font.GothamBold,
            LayoutOrder = index,
            AutoButtonColor = true,
        }, tabs)
        corner(button, 8)
        self._tabButtons[definition.id] = button
        button.Activated:Connect(function()
            setFilter(definition.id)
        end)
    end

    if options.onCreateBot then
        local create = make("TextButton", {
            Name = "CreateBot",
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -12, 0, 12),
            Size = UDim2.fromOffset(112, 30),
            BackgroundColor3 = COLORS.green,
            BorderSizePixel = 0,
            Text = "+ CREATE BOT",
            TextColor3 = COLORS.text,
            TextSize = 11,
            Font = Enum.Font.GothamBold,
        }, root)
        corner(create, 8)
        create.Activated:Connect(options.onCreateBot)
    end

    setFilter("all")
    return self
end

function BotServerManager:SetSessions(sessions: {Session})
    self._sessions = {}
    for _, session in ipairs(sessions) do
        if type(session.id) == "string"
            and type(session.name) == "string"
            and (session.kind == "bot" or session.kind == "normal") then
            table.insert(self._sessions, session)
        end
    end
    self:Render()
end

function BotServerManager:UpsertSession(session: Session)
    if session.kind ~= "bot" and session.kind ~= "normal" then
        return false, "kind must be 'bot' or 'normal'"
    end
    for index, existing in ipairs(self._sessions) do
        if existing.id == session.id then
            self._sessions[index] = session
            self:Render()
            return true
        end
    end
    table.insert(self._sessions, session)
    self:Render()
    return true
end

function BotServerManager:RemoveSession(id: string)
    for index, session in ipairs(self._sessions) do
        if session.id == id then
            table.remove(self._sessions, index)
            self:Render()
            return true
        end
    end
    return false
end

function BotServerManager:Render()
    for _, child in ipairs(self._list:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local count = 0
    for _, session in ipairs(self._sessions) do
        if self._filter == "all" or session.kind == self._filter then
            count += 1
            local card = make("Frame", {
                Name = "Session_" .. session.id,
                Size = UDim2.new(1, -2, 0, 66),
                BackgroundColor3 = COLORS.background,
                BorderSizePixel = 0,
                LayoutOrder = count,
            }, self._list)
            corner(card, 8)

            local category = session.kind == "bot" and "BOT" or "NORMAL"
            make("TextLabel", {
                Position = UDim2.fromOffset(10, 7),
                Size = UDim2.new(1, -112, 0, 22),
                BackgroundTransparency = 1,
                Text = category .. "  •  " .. session.name,
                TextColor3 = COLORS.text,
                TextSize = 13,
                Font = Enum.Font.GothamBold,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, card)
            make("TextLabel", {
                Position = UDim2.fromOffset(10, 32),
                Size = UDim2.new(1, -112, 0, 22),
                BackgroundTransparency = 1,
                Text = (session.status or "UNKNOWN") .. (session.detail and ("  /  " .. session.detail) or ""),
                TextColor3 = COLORS.muted,
                TextSize = 10,
                Font = Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, card)

            local action = make("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -8, 0.5, 0),
                Size = UDim2.fromOffset(88, 30),
                BackgroundColor3 = session.status == "RUNNING" and COLORS.red or COLORS.green,
                BorderSizePixel = 0,
                Text = session.status == "RUNNING" and "STOP" or "OPEN",
                TextColor3 = COLORS.text,
                TextSize = 11,
                Font = Enum.Font.GothamBold,
            }, card)
            corner(action, 7)
            action.Activated:Connect(function()
                self._selectedId = session.id
                if self._options.onSelect then
                    self._options.onSelect(session)
                end
                if session.status == "RUNNING" then
                    if self._options.onStop then self._options.onStop(session) end
                elseif self._options.onStart then
                    self._options.onStart(session)
                end
            end)
        end
    end

    if count == 0 then
        make("TextLabel", {
            Name = "EmptyState",
            Size = UDim2.new(1, -4, 0, 48),
            BackgroundTransparency = 1,
            Text = self._filter == "bot" and "No bot sessions registered yet."
                or self._filter == "normal" and "No normal servers registered yet."
                or "No server sessions registered yet.",
            TextColor3 = COLORS.muted,
            TextSize = 12,
            Font = Enum.Font.Gotham,
        }, self._list)
    end
end

function BotServerManager:Destroy()
    if self.Root then self.Root:Destroy() end
end

return BotServerManager
