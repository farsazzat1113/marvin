-- Deterministic, deliberately small Roblox/executor simulator. No live services,
-- credentials, HTTP, executor or Roblox installation is used by these tests.
local Scheduler = {now = 0, jobs = {}, errors = {}, bindings = {}}
local task = {}
local function resumeThread(thread, ...)
    if Scheduler.cancelled and Scheduler.cancelled[thread] then return end
    local ok, kind, value = coroutine.resume(thread, ...)
    if not ok then Scheduler.errors[#Scheduler.errors + 1] = tostring(kind) .. '\n' .. debug.traceback(thread); return end
    if coroutine.status(thread) ~= 'dead' then
        if kind == 'sleep' then Scheduler.jobs[#Scheduler.jobs + 1] = {thread = thread, at = value}
        elseif kind == 'signal' then value.waiters[#value.waiters + 1] = thread
        else error('Unrecognized yield: ' .. tostring(kind)) end
    end
end
function task.spawn(fn, ...)
    local thread = type(fn) == 'thread' and fn or coroutine.create(fn)
    resumeThread(thread, ...)
    return thread
end
function task.defer(fn, ...)
    local args = table.pack(...)
    local thread = coroutine.create(function() fn(table.unpack(args, 1, args.n)) end)
    Scheduler.jobs[#Scheduler.jobs + 1] = {thread = thread, at = Scheduler.now}
    return thread
end
function task.wait(seconds)
    Scheduler.sleeps = (Scheduler.sleeps or 0) + 1
    local duration = seconds or 1/60
    Scheduler.sleepHistogram = Scheduler.sleepHistogram or {}
    Scheduler.sleepHistogram[duration] = (Scheduler.sleepHistogram[duration] or 0) + 1
    return coroutine.yield('sleep', Scheduler.now + duration)
end
function task.delay(seconds, fn, ...)
    local args = table.pack(...)
    local thread = coroutine.create(function() fn(table.unpack(args, 1, args.n)) end)
    Scheduler.jobs[#Scheduler.jobs + 1] = {thread = thread, at = Scheduler.now + seconds}
    return thread
end
function task.cancel(thread) Scheduler.cancelled[thread] = true end
function Scheduler.flush()
    local passes = 0
    while true do
        local due, remaining = {}, {}
        for _, job in ipairs(Scheduler.jobs) do
            if job.at <= Scheduler.now + 1e-9 then due[#due + 1] = job else remaining[#remaining + 1] = job end
        end
        Scheduler.jobs = remaining
        if #due == 0 then break end
        passes += 1; assert(passes < 1000, 'Scheduler runaway')
        for _, job in ipairs(due) do resumeThread(job.thread) end
    end
end
local function signal()
    local result = {listeners = {}, waiters = {}}
    function result:Connect(fn)
        local connection = {Connected = true}
        function connection:Disconnect() self.Connected = false end
        self.listeners[#self.listeners + 1] = {callback = fn, connection = connection}
        return connection
    end
    function result:Once(fn)
        local connection
        connection = self:Connect(function(...) connection:Disconnect(); fn(...) end)
        return connection
    end
    function result:Wait() return coroutine.yield('signal', self) end
    function result:Fire(...)
        local waiting = self.waiters; self.waiters = {}
        for _, listener in ipairs(table.clone(self.listeners)) do if listener.connection.Connected then task.spawn(listener.callback, ...) end end
        for _, thread in ipairs(waiting) do resumeThread(thread, ...) end
    end
    return result
end

local Vector3, vectorMeta = {}, {}
function Vector3.new(x, y, z) return setmetatable({X = x or 0, Y = y or 0, Z = z or 0, __type = 'Vector3'}, vectorMeta) end
Vector3.zero = Vector3.new()
vectorMeta.__index = function(v, key)
    if key == 'Magnitude' then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
    if key == 'Unit' then return v / math.max(1e-12, v.Magnitude) end
    if key == 'Lerp' then return function(a, b, t) return a + (b - a) * t end end
end
vectorMeta.__add = function(a, b) return Vector3.new(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
vectorMeta.__sub = function(a, b) return Vector3.new(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
vectorMeta.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
vectorMeta.__mul = function(a, b) if type(a) == 'number' then return b * a end; return Vector3.new(a.X*b, a.Y*b, a.Z*b) end
vectorMeta.__div = function(a, b) return Vector3.new(a.X/b, a.Y/b, a.Z/b) end
local Vector2 = {new = function(x, y) return {X = x or 0, Y = y or 0, __type = 'Vector2'} end}
Vector2.zero = Vector2.new()
local CFrame, frameMeta = {}, {}
function CFrame.new(x, y, z)
    return setmetatable({Position = type(x) == 'table' and x or Vector3.new(x, y, z), yaw = 0, __type = 'CFrame'}, frameMeta)
end
function CFrame.Angles(_, yaw, _) local f = CFrame.new(); f.yaw = yaw; return f end
local function rotate(v, angle)
    return Vector3.new(v.X*math.cos(angle) - v.Z*math.sin(angle), v.Y, v.X*math.sin(angle) + v.Z*math.cos(angle))
end
frameMeta.__index = {
    PointToObjectSpace = function(f, p) return rotate(p - f.Position, -f.yaw) end,
    PointToWorldSpace = function(f, p) return f.Position + rotate(p, f.yaw) end,
}
frameMeta.__mul = function(a, b) local f = CFrame.new(a:PointToWorldSpace(b.Position)); f.yaw = a.yaw + b.yaw; return f end
local Color3 = {new = function(r,g,b) return {R=r,G=g,B=b,__type='Color3'} end}
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
local UDim = {new = function(scale, offset) return {Scale=scale or 0,Offset=offset or 0} end}
local UDim2 = {new = function(xs,xo,ys,yo) return {X=UDim.new(xs,xo),Y=UDim.new(ys,yo),__type='UDim2'} end}
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local ColorSequence = {new = function(...) return {...} end}
local NumberSequence = {new = function(...) return {...} end}
local NumberSequenceKeypoint = {new = function(time,value) return {Time=time,Value=value} end}
local TweenInfo = {new = function(duration,...) return {Time = duration} end}
local RaycastParams = {new = function() return {} end}
local Enum = setmetatable({}, {__index = function(t, category)
    local values = setmetatable({}, {__index = function(v, name)
        local item = {Name=name,Value=category == 'RenderPriority' and 100 or 1}; rawset(v,name,item); return item
    end}); rawset(t,category,values); return values
end})
local function typeof(value) return type(value) == 'table' and value.__type or type(value) end
local os = {clock = function() return Scheduler.now end, time = function() return 1794355200 + math.floor(Scheduler.now) end}
local function clone(value)
    if type(value) ~= 'table' or value.__type then return value end
    local result = {}; for key, entry in pairs(value) do result[key] = clone(entry) end; return result
end
local _G, game, request, readfile, writefile, delfile, queue_on_teleport, queueonteleport = {}, nil, nil, nil, nil, nil, nil, nil
local syn, http, http_request, fluxus, getgenv = nil, nil, nil, nil, function() return _G end
local openurl, open_url, setclipboard, toclipboard
local state
local methods, instanceMeta, Instance = {}, {}, {}
local function isGui(class) return ({Frame=true,CanvasGroup=true,ScrollingFrame=true,TextLabel=true,TextButton=true,ImageButton=true,ImageLabel=true,TextBox=true,ViewportFrame=true})[class] end
local function getSignal(obj, key)
    if not obj._signals[key] then obj._signals[key] = signal() end
    return obj._signals[key]
end
local events = {Destroying=true,DescendantAdded=true,DescendantRemoving=true,ChildAdded=true,ChildRemoved=true,
    CharacterAdded=true,CharacterRemoving=true,Died=true,Activated=true,InputBegan=true,InputEnded=true,Focused=true,FocusLost=true,
    OnTeleport=true,MouseEnter=true,MouseLeave=true,SelectionGained=true,SelectionLost=true,IsLoaded=true}
-- GUI coordinates stay logical until the complete UIScale ancestry is applied.
-- ScreenGui has a configurable safe-area origin; scrolling offsets and vertical
-- UIListLayout are modeled for geometry assertions, not pixel rendering/hit testing.
local function logicalSize(obj)
    if not obj or obj.ClassName == 'ScreenGui' then return state.viewport end
    local size = obj._props.Size
    if not size or size.__type ~= 'UDim2' then return size or state.viewport end
    local parent = logicalSize(obj.Parent)
    return Vector2.new(parent.X * size.X.Scale + size.X.Offset, parent.Y * size.Y.Scale + size.Y.Offset)
end
local function ownScale(obj)
    local scale = 1
    for _, child in ipairs(obj._children) do if child.ClassName == 'UIScale' then scale *= child.Scale end end
    return scale
end
local function totalScale(obj)
    if not obj or obj.ClassName == 'ScreenGui' or not isGui(obj.ClassName) then return 1 end
    return ownScale(obj) * totalScale(obj.Parent)
end
local function absoluteSize(obj)
    local size = logicalSize(obj)
    if size.__type ~= 'Vector2' then return size end
    local scale = totalScale(obj)
    return Vector2.new(size.X * scale, size.Y * scale)
end
local function absolutePosition(obj)
    if not obj or obj.ClassName == 'ScreenGui' or not isGui(obj.ClassName) then return state.origin end
    local parent = obj.Parent
    local origin, area = absolutePosition(parent), logicalSize(parent)
    local p, anchor = obj.Position, obj.AnchorPoint
    local x, y = area.X * p.X.Scale + p.X.Offset, area.Y * p.Y.Scale + p.Y.Offset
    local layout, padding
    if parent then
        for _,child in ipairs(parent._children) do
            if child.ClassName == 'UIListLayout' then layout = child end
            if child.ClassName == 'UIPadding' then padding = child end
        end
    end
    if layout then
        x, y = 0, 0
        local siblings = {}
        for i, child in ipairs(parent._children) do
            if isGui(child.ClassName) and child.Visible then siblings[#siblings+1] = {obj=child, index=i} end
        end
        table.sort(siblings,function(a,b)
            if (a.obj.LayoutOrder or 0) ~= (b.obj.LayoutOrder or 0) then return (a.obj.LayoutOrder or 0) < (b.obj.LayoutOrder or 0) end
            return a.index < b.index
        end)
        for _,entry in ipairs(siblings) do
            if entry.obj == obj then break end
            y += logicalSize(entry.obj).Y * ownScale(entry.obj) + (layout.Padding and layout.Padding.Offset or 0)
        end
        if padding then
            x += padding.PaddingLeft and area.X * padding.PaddingLeft.Scale + padding.PaddingLeft.Offset or 0
            y += padding.PaddingTop and area.Y * padding.PaddingTop.Scale + padding.PaddingTop.Offset or 0
        end
    end
    if parent and parent.ClassName == 'ScrollingFrame' then x -= parent.CanvasPosition.X; y -= parent.CanvasPosition.Y end
    local scale, size = totalScale(parent), absoluteSize(obj)
    return Vector2.new(origin.X + x * scale - size.X * anchor.X, origin.Y + y * scale - size.Y * anchor.Y)
end
instanceMeta.__index = function(obj, key)
    if methods[key] then return methods[key] end
    if events[key] then return getSignal(obj,key) end
    if key == 'AbsoluteSize' then return absoluteSize(obj) end
    if key == 'AbsolutePosition' then return absolutePosition(obj) end
    return obj._props[key]
end
instanceMeta.__newindex = function(obj,key,value)
    local old = obj._props[key]
    if state and state.metrics and obj._props.ClassName then
        local bucket = obj._props.ClassName .. '.' .. tostring(key)
        state.metrics.propWrites[bucket] = (state.metrics.propWrites[bucket] or 0) + 1
        if old ~= value then
            local changed = 'changed:' .. bucket
            state.metrics.propWrites[changed] = (state.metrics.propWrites[changed] or 0) + 1
        end
    end
    if key == 'Parent' and old ~= value then
        if old then
            old.DescendantRemoving:Fire(obj)
            local i = table.find(old._children,obj); if i then table.remove(old._children,i) end
        end
        obj._props[key] = value
        if value then
            value._children[#value._children+1] = obj; value.ChildAdded:Fire(obj)
            local cursor=value
            while cursor do cursor.DescendantAdded:Fire(obj); cursor=cursor.Parent end
        end
    else obj._props[key] = value end
    if old ~= value then getSignal(obj,'property:'..key):Fire() end
end
function Instance.new(class)
    if state and state.metrics then state.metrics.instances += 1 end
    local obj = setmetatable({_props={ClassName=class,Name=class,Visible=true,Active=true,Selectable=true,ZIndex=1,
        BackgroundTransparency=0,Text='',Image='',CanvasPosition=Vector2.zero,Position=UDim2.new(),Size=UDim2.new(),AnchorPoint=Vector2.zero},
        _children={},_signals={},_attrs={}},instanceMeta)
    if class == 'UIScale' then obj.Scale=1 end
    if class == 'Part' or class == 'MeshPart' then obj.Position=Vector3.zero;obj.Size=Vector3.new(2,2,2);obj.CFrame=CFrame.new();obj.Anchored=false end
    return obj
end
function methods:IsA(class)
    return self.ClassName == class or class=='BasePart' and (self.ClassName=='Part' or self.ClassName=='MeshPart')
        or class=='GuiObject' and isGui(self.ClassName) or class=='GuiButton' and (self.ClassName=='TextButton' or self.ClassName=='ImageButton')
end
function methods:FindFirstChild(name, recursive)
    for _, child in ipairs(self._children) do if child.Name==name then return child end end
    if recursive then for _, child in ipairs(self._children) do local result=child:FindFirstChild(name,true);if result then return result end end end
end
function methods:FindFirstChildOfClass(class) for _, child in ipairs(self._children) do if child:IsA(class) then return child end end end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
    local result={}
    local function walk(obj) for _,child in ipairs(obj._children) do result[#result+1]=child;walk(child) end end
    walk(self);return result
end
function methods:GetPropertyChangedSignal(key) return getSignal(self,'property:'..key) end
function methods:GetAttributeChangedSignal(key) return getSignal(self,'attribute:'..key) end
function methods:GetAttribute(key) return self._attrs[key] end
function methods:SetAttribute(key,value) local old=self._attrs[key];self._attrs[key]=value;if old~=value then getSignal(self,'attribute:'..key):Fire() end end
function methods:GetPivot() return self.PrimaryPart and self.PrimaryPart.CFrame or self.Pivot or CFrame.new() end
function methods:GetBoundingBox() return self:GetPivot(), Vector3.new(4,1,4) end
function methods:Destroy()
    if self._destroyed then return end; self._destroyed=true;self.Destroying:Fire()
    for _,child in ipairs(table.clone(self._children)) do child:Destroy() end
    self.Parent=nil
    for _,sig in pairs(self._signals) do for _,item in ipairs(sig.listeners) do item.connection:Disconnect() end end
end
function methods:Clone()
    if self.Archivable == false then return nil end
    local copies = {}
    local function copy(original)
        local obj = Instance.new(original.ClassName); copies[original] = obj
        for key,value in pairs(original._props) do if key ~= 'Parent' and key ~= 'ClassName' then obj[key] = value end end
        for key,value in pairs(original._attrs) do obj:SetAttribute(key,value) end
        for _,child in ipairs(original:GetChildren()) do local item=copy(child);item.Parent=obj end
        return obj
    end
    local result=copy(self)
    for original,obj in pairs(copies) do
        for key,value in pairs(original._props) do if type(value)=='table' and copies[value] then obj[key]=copies[value] end end
    end
    return result
end
function methods:Move(direction) self.MoveDirection=direction end
function methods:ChangeState(value) state.jumps+=1;self.State=value end
local require = function(module)
    Scheduler.requireCalls = Scheduler.requireCalls or {}
    Scheduler.requireCalls[module.Name] = (Scheduler.requireCalls[module.Name] or 0) + 1
    assert(module.Module,'Missing mock module: '..module.Name)
    if module.Delay and not module.Loaded then task.wait(module.Delay);module.Loaded=true end
    return module.Module
end
local workspace
local function log(kind, info) state.log[#state.log+1]={kind=kind,info=info,at=Scheduler.now} end
local function reset(options)
    options=options or {}
    Scheduler.now=0;Scheduler.jobs={};Scheduler.errors={};Scheduler.cancelled={};Scheduler.bindings={}
    _G={}
    state={options=options,viewport=Vector2.new(options.width or 390,options.height or 844),origin=Vector2.new(options.insetX or 0,options.insetY or 0),tweens={},log={},requests={},files={},teleports={},writes={},carryCalls={},plantCalls={},metrics={instances=0,sleeps=0,propWrites={}},
        jumps=0,carry={IsCarrying=false},records={},fixtures={},codec={},nextCodec=0,tags={},tagAdded={},tagRemoved={}}
    local function encode(value)
        local function canonical(v)
            if type(v)~='table' then return type(v)..':'..tostring(v) end
            local keys={};for key in pairs(v) do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
            local result={};for _,key in ipairs(keys)do result[#result+1]=tostring(key)..'='..canonical(v[key])end;return '{'..table.concat(result,',')..'}'
        end
        local id=canonical(value);state.codec[id]=clone(value);return id
    end
    local Http={GenerateGUID=function()return 'mock-guid'end,JSONEncode=function(_,value)return encode(value)end,
        JSONDecode=function(_,body)assert(state.codec[body]~=nil,'Invalid mock JSON');return clone(state.codec[body])end,
        UrlEncode=function(_,value)return value end}
    local world=Instance.new('Workspace');world.Name='Workspace';workspace=world
    local RS=Instance.new('ReplicatedStorage')
    local player=Instance.new('Player');player.Name='Tester';player.UserId=123
    local playerGui=Instance.new('PlayerGui');playerGui.Name='PlayerGui';playerGui.Parent=player
    local function characterAt(x,z)
        local character=Instance.new('Model');character.Name='Character';character.Parent=world
        local humanoid=Instance.new('Humanoid');humanoid.Health=100;humanoid.HipHeight=2;humanoid.WalkSpeed=16;humanoid.FloorMaterial=Enum.Material.Grass;humanoid.Parent=character
        local root=Instance.new('Part');root.Name='HumanoidRootPart';root.Position=Vector3.new(x,3,z);root.CFrame=CFrame.new(root.Position);root.Size=Vector3.new(2,2,1);root.Parent=character
        player.Character=character;state.character=character;state.humanoid=humanoid;state.root=root
        return character
    end
    state.characterAt=characterAt;characterAt(options.startX or 0,options.startZ or 0)
    local Players={LocalPlayer=player,GetPlayers=function()return {player}end}
    local Run={Heartbeat=signal(),BindToRenderStep=function(_,name,_,fn)Scheduler.bindings[name]=fn end,
        UnbindFromRenderStep=function(_,name)Scheduler.bindings[name]=nil end}
    local Input={InputBegan=signal(),InputChanged=signal(),InputEnded=signal(),WindowFocusReleased=signal(),JumpRequest=signal(),
        TouchEnabled=options.touch~=false,GetFocusedTextBox=function()return state.focused end}
    local teleSettings={UNKNOWNAutoJoinEnabledV1=options.autoJoin==true,UNKNOWNAutoJoinMinValueV1=options.autoJoinMinValue or 1e9}
    if options.tracked~=false then teleSettings.UNKNOWNJoinedEggV1={uid='egg-1',jobId='current-job',placeId=42,name='Aurora',rate=2e9,rarity='Divine'}end
    local Teleports={TeleportInitFailed=signal(),GetTeleportSetting=function(_,key)return clone(teleSettings[key])end,
        SetTeleportSetting=function(_,key,value)teleSettings[key]=clone(value);log('teleSetting',key)end,
        TeleportToPlaceInstance=function(_,place,job,who)log('teleport',job);state.teleports[#state.teleports+1]={place=place,job=job,who=who,at=Scheduler.now}end}
    local Tags={GetTagged=function(_,tag)return table.clone(state.tags[tag]or{})end,
        GetInstanceAddedSignal=function(_,tag)if not state.tagAdded[tag]then state.tagAdded[tag]=signal()end;return state.tagAdded[tag]end,
        GetInstanceRemovedSignal=function(_,tag)if not state.tagRemoved[tag]then state.tagRemoved[tag]=signal()end;return state.tagRemoved[tag]end}
    local Tweens={Create=function(_,obj,info,props)
        local tween={Completed=signal(),cancelled=false,object=obj,properties=props}; state.tweens[#state.tweens+1]=tween
        function tween:Cancel()self.cancelled=true end
        function tween:Play()task.delay(info.Time,function()if not self.cancelled and not obj._destroyed then for key,value in pairs(props)do obj[key]=value end;self.Completed:Fire()end end)end
        return tween
    end}
    local Pathfinding={CreatePath=function(_,config)
        state.lastPathConfig=config
        local path={Status=Enum.PathStatus.NoPath}
        function path:ComputeAsync()if options.path then self.Status=Enum.PathStatus.Success end end
        function path:GetWaypoints()return options.path or{}end
        return path
    end}
    local services={Players=Players,ReplicatedStorage=RS,HttpService=Http,TeleportService=Teleports,RunService=Run,CollectionService=Tags,
        UserInputService=Input,PathfindingService=Pathfinding,TweenService=Tweens,
        GuiService={OpenBrowserWindow=function(_,url) if not options.browser then error('Browser unavailable') end;state.opened=url end},
        StarterGui={SetCore=function(_,key,value)state.notification={key=key,value=value}end}}
    game={PlaceId=42,JobId='current-job',GetService=function(_,key)assert(services[key],'Unknown service '..key);return services[key]end}
    function world:GetServerTimeNow()return 1794355200+Scheduler.now end
    function world:Raycast(origin,delta)
        if delta.Y < -0.001 then
            local y=0
            if options.gap and origin.X>options.gap[1]and origin.X<options.gap[2]then return nil end
            if options.groundHeight then y=options.groundHeight(origin.X,origin.Z)end
            local t=(y-origin.Y)/delta.Y
            if t>=0 and t<=1 then return {Position=Vector3.new(origin.X+delta.X*t,y,origin.Z+delta.Z*t),Normal=Vector3.new(0,1,0),Material=Enum.Material.Grass}end
        end
        if options.wall and math.abs(delta.X)>0.001 then
            local t=(options.wall-origin.X)/delta.X
            if t>0 and t<1 then return {Position=origin+delta*t,Normal=Vector3.new(-1,0,0),Material=Enum.Material.Grass}end
        end
    end
    local eggs=Instance.new('Folder');eggs.Name='AreaEggSlotsClient';eggs.Parent=world
    local eggModel=Instance.new('Model');eggModel.Name='egg-1';eggModel.Pivot=CFrame.new(options.eggX or 12,0,options.eggZ or 0);eggModel.Parent=eggs
    local eggPosition=eggModel.Pivot.Position
    state.records['egg-1']={Uid='egg-1',AssetCategory='TestEgg',AssetScale=1,Mutations={},AreaId='Field',NestId=1,BottomCFrame=CFrame.new(eggPosition),State='Slot'}
    local center=Instance.new('Part');center.Name='Home';center.Position=Vector3.new(options.homeX or 30,0,options.homeZ or 0);center.CFrame=CFrame.new(center.Position);center.Parent=world
    local function horizontal(a,b)local d=a-b;return Vector3.new(d.X,0,d.Z).Magnitude end
    local EggState={ReadFieldEggs=function()return {Records=state.records}end,ReadCarryState=function()return clone(state.carry)end,
        CarryFieldEgg=function(uid,slot)
            state.carryCalls[#state.carryCalls+1]={uid=uid,slot=slot,at=Scheduler.now,position=state.root.Position};log('carry',uid)
            if options.lateCarry then
                task.delay(4,function()state.carry={IsCarrying=true};state.records[uid].State='Carried'end)
                task.wait(5)
                return true
            end
            if options.carryDelay then task.wait(options.carryDelay)end
            if options.rejectCarry or horizontal(state.root.Position,eggPosition)>5.5 or state.humanoid.Health<=0 then return false end
            state.carry={IsCarrying=true};if not options.noCarryUid then state.carry.Uid=uid end;state.records[uid].State='Carried';return true
        end,
        PlantEgg=function(uid,offset)
            state.plantCalls[#state.plantCalls+1]={uid=uid,at=Scheduler.now,position=state.root.Position};log('plant',uid)
            if options.rejectPlant then return false end
            if not state.carry.IsCarrying or horizontal(state.root.Position,center.Position)>5 then return false end
            state.carry={IsCarrying=false};state.records[uid].State='Claimed';return true
        end}
    local modules={['Client.EggState']=EggState,['Client.PlotState']={ResolvePlot=function()return {CenterPoint=center}end},
        ['Data.Assets']={Directory={TestEgg={DisplayName='Aurora',Icon=options.icon or '',EarningRate=options.localRate or 2e9,Rarity={DisplayName='Divine',Rank=10}}}},
        ['Shared.Types.AreaEggs']={States={Slot='Slot',Carried='Carried',Dropped='Dropped',GuardCarried='GuardCarried',Claimed='Claimed'}},
        ['Shared.Modules.Mutations']={EarningsFor=function()return 1 end},['Shared.Util.EggRecords']={WeightKg=function()return 1 end},
        ['Shared.Util.AreaEggSlotIdentity']={LooksLikeFirstAreaUid=function()return false end,SlotKey=function(a,b)return a..':'..b end},
        ['Shared.Util.AreaEggCycle']={IsRunning=function()return true end,SecondsUntilReset=function()return 200 end,
            NextResetTime=function(now)return now+200 end,PeriodIndexAt=function()return 1 end,PeriodStartTime=function()return 1794355100 end}}
    for path,module in pairs(modules)do
        local holder=RS;local parts=string.split(path,'.')
        for i,name in ipairs(parts)do
            local child=holder:FindFirstChild(name)
            if not child then child=Instance.new(i==#parts and'ModuleScript'or'Folder');child.Name=name;child.Parent=holder end
            holder=child
        end
        holder.Module=module;holder.Delay=options.moduleDelays and options.moduleDelays[path]
    end
    state.settings={autoExecute=true,autoSteal=options.autoSteal~=false,autoJoinEnabled=options.autoJoin==true,
        autoJoinMinValue=options.autoJoinMinValue or 1e9,serversMinValue=options.serversMinValue or 1e9,
        autoStealMinValue=options.autoStealMinValue or 0,targetValue=options.targetValue or 1e9,
        targetValueEnabled=options.targetValueEnabled==true,targetValueMode=options.targetValueMode or 'exact',
        uiRevision=2,myServer=options.myServer~=false,speedBoost=options.speedBoost==true,boostSpeed=24,infiniteJump=options.infiniteJump==true,
        windowPosition=options.windowPosition,launcherPosition=options.launcherPosition,topFourOnly=options.topFourOnly==true,
        minRank=options.minRank or 0,sizePercent=options.sizePercent or 100,reducedMotion=options.reducedMotion==true,
        webhookEnabled=options.webhook==true,webhookUrl=options.webhookUrl or(options.webhook and'https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwx'or'')}
    state.files['tenshi_beta_ui.json']=encode(state.settings)
    state.files['unknown_saved_access_key.txt']='TEST-KEY'
    if not options.cold then teleSettings.UNKNOWNValidatedHopV1={version=1,key='TEST-KEY',verifiedAt=os.time(),hopAt=os.time(),fromJob='old-job',placeId=42,jobId='current-job'}end
    local config={endpoint='https://finder.example',roomKey='public-test-room'}
    teleSettings.UNKNOWNFinderConfigV1=clone(config)
    readfile=function(path)assert(state.files[path]~=nil,'No such mock file');return state.files[path]end
    writefile=function(path,body)state.files[path]=body;state.writes[#state.writes+1]={path=path,at=Scheduler.now};log('file',path)end
    delfile=function(path)state.files[path]=nil end
    queue_on_teleport=function(payload)log('queue',payload);state.queuePayload=payload end
    request=function(args)
        state.requests[#state.requests+1]={url=args.Url,at=Scheduler.now,body=args.Body};log('request',args.Url)
        if args.Url:find('/validate',1,true)then
            task.wait(options.keyDelay or 0.02)
            return {StatusCode=options.keyCode or 200,Body=encode({valid=not options.invalidKey,reason=options.invalidKey and'expired'or nil})}
        end
        if args.Url:find('Config.json',1,true)then return {StatusCode=200,Body=encode(config)}end
        if args.Url:find('/v1/eggs',1,true)then
            local offset=tonumber(args.Url:match('&offset=(%d+)'))or 0
            task.wait(offset>0 and(options.pageDelay or options.feedDelay or 0.02)or(options.feedDelay or 0.02))
            local items={}
            if options.remote then items[1]={placeId=42,jobId='remote-job',uid='remote-egg',name='Remote Aurora',rate=options.remoteRate or 50e9,rank=10,rarity='Divine',
                expiresAt=(1794355200+(options.expiry or 200))*1000,key='remote-key',source='field'}end
            if options.remoteSecond then
                items[#items+1]={placeId=42,jobId='second-job',uid='second-egg',name='Second Aurora',rate=49e9,rank=10,rarity='Divine',
                    expiresAt=(1794355200+200)*1000,key='second-key',source='field'}
            end
            if options.feedItems then items=clone(options.feedItems) end
            log('feedAck',#items)
            return {StatusCode=options.feedCode or 200,Headers=options.feedCode==429 and{['Retry-After']='3'}or{},
                Body=encode({items=items,serverTime=world:GetServerTimeNow()*1000,nextOffset=options.repeatPage and offset+10 or nil})}
        end
        if args.Url:find('/v1/join',1,true)then
            task.wait(options.claimDelay or 0.05);log('claimAck')
            return {StatusCode=200,Body=encode({allowed=not options.rejectClaim,expiresAt=(1794355200+(options.expiry or 200))*1000})}
        end
        if args.Url:find('/v1/report',1,true)then
            task.wait(options.reportDelay or 0.02)
            local body=Http:JSONDecode(args.Body)
            return {StatusCode=200,Body=encode({ok=true,accepted=#body.eggs})}
        end
        if args.Url:find('/api/webhooks/',1,true)then
            if options.hookDelay then task.wait(options.hookDelay)end
            state.hookAttempts=(state.hookAttempts or 0)+1
            if options.hook429 and state.hookAttempts==1 then return {StatusCode=429,Body=encode({retry_after=3})}end
            return {StatusCode=204,Body=''}
        end
        error('Unexpected mock request: '..args.Url)
    end
    openurl=nil;open_url=nil;setclipboard=nil;toclipboard=nil
    state.services=services;state.player=player;state.playerGui=playerGui;state.teleSettings=teleSettings;state.world=world;state.http=Http;state.modules=modules
    function state.input(kind,x,y)
        local input=Instance.new('InputObject');input.UserInputType=Enum.UserInputType[kind]
        input.Position=Vector3.new(x,y,0);input.UserInputState=Enum.UserInputState.Begin
        return input
    end
    function state.resize(width,height)
        state.viewport=Vector2.new(width,height)
        for _,gui in ipairs(playerGui:GetChildren())do getSignal(gui,'property:AbsoluteSize'):Fire() end
    end
    function state.addTrap(x,z,width,depth,yaw)
        local root=Instance.new('Part');root.Name='BearTrap';root.Position=Vector3.new(x,0.2,z);root.CFrame=CFrame.new(root.Position);root.Parent=world
        local hitbox=Instance.new('Part');hitbox.Name='Hitbox';hitbox.Size=Vector3.new(width or 2,0.4,depth or 2)
        hitbox.Position=Vector3.new(x,0.2,z);hitbox.CFrame=CFrame.new(hitbox.Position)*CFrame.Angles(0,yaw or 0,0);hitbox.Parent=root
        state.tags.PlacedTrap=state.tags.PlacedTrap or{};table.insert(state.tags.PlacedTrap,root)
        if state.tagAdded.PlacedTrap then state.tagAdded.PlacedTrap:Fire(root)end
        return hitbox
    end
    return state
end
function Scheduler.advance(seconds, dt)
    dt=dt or 1/60
    local untilAt=Scheduler.now+seconds
    Scheduler.flush()
    while Scheduler.now<untilAt-1e-9 do
        local step=math.min(dt,untilAt-Scheduler.now);Scheduler.now+=step
        for _,fn in pairs(table.clone(Scheduler.bindings))do fn(step)end
        local humanoid,root=state.humanoid,state.root
        if humanoid.Health>0 and humanoid.MoveDirection and humanoid.MoveDirection.Magnitude>0 then
            root.Position=root.Position+humanoid.MoveDirection*humanoid.WalkSpeed*step;root.CFrame=CFrame.new(root.Position)
            state.trajectory=state.trajectory or{};state.trajectory[#state.trajectory+1]=root.Position
        end
        state.services.RunService.Heartbeat:Fire(step);Scheduler.flush()
    end
    if #Scheduler.errors>0 then error(table.concat(Scheduler.errors,'\n'))end
end
local warnings={}
local warn=function(message)warnings[#warnings+1]=message end
local function findButton(text)
    for _,obj in ipairs(state.playerGui:GetDescendants())do if obj:IsA('TextButton')and obj.Text==text then return obj end end
end
local function expect(condition, message)assert(condition,message or'Expectation failed')end
local function near(a,b,epsilon)expect(math.abs(a-b)<(epsilon or 1e-6),tostring(a)..' ~= '..tostring(b))end
local passed=0
local function test(name,fn)
    fn();passed+=1;print('PASS '..name)
end
