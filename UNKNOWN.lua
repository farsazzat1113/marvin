--================================================================================================--
--   UNKNOWN  ::  Shared Egg Finder + Cloudflare Key Gate
--================================================================================================--
--   File      : UNKNOWN.lua
--   Build     : Public v0.4.3 / UI20 "Glass Premium + Auto Steal"
--   Theme     : Glass Premium - translucent panels, gradient strokes, animated starfield
--   Key gate  : the Finder boots only after the endpoint returns valid=true, and is
--               re-validated every 60 s while running.
--
--   Contents
--     [1] Bootstrap .......... auto-execute queue + shared-runtime registration
--     [2] Finder core ........ services, GUI factory, parsing/formatting helpers
--     [3] Glass Premium UI ... panel theme, header, settings overlay, animations
--     [4] Network ............ config loader, broadcast, feed pagination, auto-join
--     [5] Card renderer ...... egg cards, rarity/mutation glyphs, join flow
--     [6] Scan loop .......... field-egg reader feeding the UI and the broadcaster
--     [7] Key gate ........... glass key window, online validation + periodic recheck
--================================================================================================--

-- Finder code starts only after the key validation endpoint returns valid=true.
local function startUnknown()

--============================================================================--
--  [1] BOOTSTRAP - auto-execute is registered once per server hop; all retries
--      are silent so a failed registration never breaks the session.
--============================================================================--

local HttpService = game:GetService("HttpService")
local RAW_SCRIPT_URL = "https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/UNKNOWN.lua?v=" .. tostring(os.time())
local autoExecuteEnabled = true
if type(readfile) == "function" then
    pcall(function()
        local saved = HttpService:JSONDecode(readfile("tenshi_beta_ui.json"))
        if type(saved) == "table" and type(saved.autoExecute) == "boolean" then
            autoExecuteEnabled = saved.autoExecute
        end
    end)
end
local autoExecuteQueued = false
local function queueAutoExecute()
    if not autoExecuteEnabled or autoExecuteQueued then return autoExecuteQueued end
    local candidates = {}
    if type(queue_on_teleport) == "function" then table.insert(candidates, queue_on_teleport) end
    if type(queueonteleport) == "function" then table.insert(candidates, queueonteleport) end
    if type(syn) == "table" and type(syn.queue_on_teleport) == "function" then
        table.insert(candidates, syn.queue_on_teleport)
    end
    if type(fluxus) == "table" and type(fluxus.queue_on_teleport) == "function" then
        table.insert(candidates, fluxus.queue_on_teleport)
    end
    local payload = 'local h=game:GetService("HttpService");local ok,s=pcall(function()return h:JSONDecode(readfile("tenshi_beta_ui.json"))end);if not ok or type(s)~="table" or s.autoExecute~=false then loadstring(game:HttpGet("' .. RAW_SCRIPT_URL .. '"))() end'
    for _, callback in ipairs(candidates) do
        for attempt = 1, 3 do
            local ok = pcall(callback, payload)
            if ok then
                autoExecuteQueued = true
                return true
            end
            if attempt < 3 then task.wait(0.15) end
        end
    end
    return false
end
queueAutoExecute()
--============================================================================--
--  [2] FINDER CORE - services, shared state and the GUI factory helpers every
--      later section builds on.
--============================================================================--
-- UNKNOWN public v0.4.3 / UI20
-- Based on public commit 7fd7826415b94846abc924aa0ce9308b541c0653.
-- Public host/config; broadcast contract preserved from public v0.4.3.
-- NYX Spawn Panel: current-server field eggs, read-only display.
-- Schema reference: monthonsova/Steal-An-Egg, EggESP/esp/EggData.lua.
-- Reports egg sightings and server IDs to the shared Finder host.
-- V4: field snapshot + separately replicated Halloween world eggs.
-- Records are never filtered by distance or by model availability.
local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')

-- Teleport queues and executors can run before the client finishes joining.
-- Wait for the local player instead of silently terminating the script.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local player = Players.LocalPlayer
local playerDeadline = os.clock() + 60
while not player and os.clock() < playerDeadline do
    task.wait(0.1)
    player = Players.LocalPlayer
end
assert(player, 'LocalPlayer did not become available within 60 seconds')

local parent = player:WaitForChild('PlayerGui', 60)
assert(parent, 'PlayerGui unavailable after waiting 60 seconds')
local old = parent:FindFirstChild('MARVIN') or parent:FindFirstChild('TENSHI_'..'FINDER_BETA')
if old then old:Destroy() end
local gui = Instance.new('ScreenGui')
gui.Name = 'MARVIN'
gui:SetAttribute('TenshiUIBuild','PUBLIC-V05-TOP10')
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
pcall(function() gui.ClipToDeviceSafeArea = false end)
gui.DisplayOrder = 1200
gui.Parent = parent

-- Visible startup feedback while Roblox finishes loading its client modules.
local startupNotice = Instance.new("TextLabel")
startupNotice.Name = "MARVIN_StartupNotice"
startupNotice.AnchorPoint = Vector2.new(0.5, 0.5)
startupNotice.Position = UDim2.fromScale(0.5, 0.5)
startupNotice.Size = UDim2.fromOffset(380, 54)
startupNotice.BackgroundColor3 = Color3.fromRGB(12, 9, 24)
startupNotice.BackgroundTransparency = 0.08
startupNotice.BorderSizePixel = 0
startupNotice.Text = "MARVIN • WAITING FOR GAME DATA"
startupNotice.TextColor3 = Color3.fromRGB(220, 230, 255)
startupNotice.Font = Enum.Font.GothamBold
startupNotice.TextSize = 16
startupNotice.ZIndex = 100
startupNotice.Parent = gui
Instance.new("UICorner", startupNotice).CornerRadius = UDim.new(0, 12)
local startupStroke = Instance.new("UIStroke")
startupStroke.Color = Color3.fromRGB(147, 92, 255)
startupStroke.Thickness = 1.5
startupStroke.Parent = startupNotice

local alive = true
local finderCreating = false
local sharedRuntime = _G
pcall(function()
    if type(getgenv) == "function" then sharedRuntime = getgenv() end
end)
sharedRuntime.__UNKNOWN_STOP_ACTIVE = function()
    alive = false
    if gui and gui.Parent then
        pcall(function() gui:Destroy() end)
    end
end
local highlight
gui.Destroying:Connect(function() alive = false; if highlight then highlight:Destroy() end end)
local function make(class, props, holder)
    local obj = Instance.new(class)
    for key, value in pairs(props) do obj[key] = value end
    obj.Parent = holder
    return obj
end
local function label(holder, text, pos, size, color, fontSize)
    return make('TextLabel', {Text=text,Position=pos,Size=size,BackgroundTransparency=1,TextColor3=color or Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=fontSize or 13,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},holder)
end
local function module(path)
    local obj = RS
    for part in path:gmatch('[^.]+') do
        local child = obj:FindFirstChild(part)
        if not child then
            child = obj:WaitForChild(part, 45)
        end
        assert(child, 'Missing game module after waiting: '..path..' ['..part..']')
        obj = child
    end
    return require(obj)
end
local function numberField(record, keys)
    for _, key in ipairs(keys) do
        local value = record and record[key]
        if type(value)=='number' and value==value and math.abs(value)<math.huge then return value end
    end
end
local function modelFor(uid)
    if type(uid)~='string' then return end
    local folder = workspace:FindFirstChild('AreaEggSlotsClient')
    local obj = (folder and folder:FindFirstChild(uid)) or workspace:FindFirstChild(uid)
    if obj and obj:IsA('Model') then return obj end
end
local function displayedRate(model)
    if not model then return end
    for _,obj in ipairs(model:GetDescendants()) do
        if obj:IsA('TextLabel') or obj:IsA('TextButton') then
            local text=obj.Text:gsub('<[^>]+>',''):gsub(',','')
            local amount,suffix=text:match('%$?%s*(%d+%.?%d*)%s*(%a*)%s*/[sS]')
            local powers={['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,q=1e15,qi=1e18}
            local factor=suffix and powers[suffix:lower()]
            if amount and factor then return tonumber(amount)*factor end
        end
    end
end
local function money(value)
    if not value then return 'Income unavailable' end
    for _,entry in ipairs({{1e18,'Qi'},{1e15,'Qa'},{1e12,'T'},{1e9,'B'},{1e6,'M'},{1e3,'K'}}) do
        if value>=entry[1] then return string.format('$%.2f%s/s',value/entry[1],entry[2]) end
    end
    return string.format('$%.2f/s',value)
end
local function valid(value)
    return type(value)=='number' and value==value and value>=0 and value<math.huge
end
local function computedRate(base, scale, muts, mutationModule)
    if not valid(base) or not valid(scale) or scale==0 then return nil end
    local multi=1
    if type(muts)~='table' then return nil end
    if next(muts) then
        local fn=mutationModule and mutationModule.EarningsFor
        if type(fn)~='function' then return nil end
        local ok,result=pcall(fn,muts)
        if not ok or not valid(result) then return nil end
        multi=result
    end
    -- Observed public implementation; displayed model income takes precedence.
    local factor=scale>5 and (scale/5)^1.2*19.637875755794113 or scale^1.85
    local result=base*factor*multi
    return valid(result) and result or nil
end
local function compare(a,b,sortMode)
    -- Unknown event species are visibly pinned for inspection, not called Divine.
    local av,bv
    if sortMode==1 then av,bv=a.rate,b.rate
    elseif sortMode==2 then av,bv=a.scale,b.scale
    else av,bv=a.tier,b.tier end
    -- Unavailable values are never replaced with invented zeroes.
    if av==nil and bv~=nil then return false end
    if bv==nil and av~=nil then return true end
    if av~=bv then return av>bv end
    if sortMode~=1 and a.rate~=b.rate then return (a.rate or -1)>(b.rate or -1) end
    if a.tier~=b.tier then return a.tier>b.tier end
    return tostring(a.key)<tostring(b.key)
end
local function canonical(value)
    return tostring(value or ''):lower():gsub('^halloween%s*',''):gsub('%s*egg$',''):gsub('[^%w]','')
end
local function isHalloweenEgg(entry)
    local source=tostring(entry and (entry.source or (entry.isEvent and 'event')) or ''):lower()
    local area=tostring(entry and (entry.area or entry.areaKey) or ''):lower()
    return source=='event' or area:find('halloween',1,true)~=nil or area:match('^hw[%s/]')~=nil
end
local function resolveSpec(specs, source, modelName)
    if source and specs[source] then return specs[source] end
    local result
    local wanted=canonical(source or modelName)
    if wanted=='' then return nil end
    for key,spec in pairs(specs) do
        if type(spec)=='table' then
            for _,alias in pairs({key,spec.Id,spec.DisplayName,spec.Source,spec.EggSource,spec.EggModel}) do
                if canonical(alias)==wanted then
                    if result and result~=spec then return nil end -- ambiguous aliases stay unresolved
                    result=spec
                end
            end
        end
    end
    return result
end
local function eventTraits(model,record)
    local names,seen,sources={},{},{}
    local known=false
    local function insert(v)
        if type(v)=='string' and v~='' and v~='None' and v~='Normal' and not seen[v] then
            seen[v]=true; names[#names+1]=v
        end
    end
    local function parse(value)
        if type(value)=='table' then
            for key,v in pairs(value) do
                if v==true and type(key)=='string' then insert(key)
                elseif type(v)=='string' then insert(v) end
            end
        elseif type(value)=='string' then
            local ok,parsed=pcall(function() return game:GetService('HttpService'):JSONDecode(value) end)
            if ok and type(parsed)=='table' then parse(parsed)
            else for v in value:gmatch('[^,;|]+') do insert(v:match('^%s*(.-)%s*$')) end end
        end
    end
    local keys={'Mutations','Mutation','BaseMutation','MutationIds','MutationId'}
    local function inspect(attrs,source,authoritative)
        for _,key in ipairs(keys) do
            local value=attrs[key]
            if type(value)=='string' or type(value)=='table' then
                parse(value)
                if authoritative or #names>0 then known=true end
                sources[source]=true
            end
        end
    end
    if type(record)=='table' then inspect(record,'UID record',true) end
    inspect(model:GetAttributes(),'model attrs',true)
    for _,child in ipairs(model:GetDescendants()) do
        inspect(child:GetAttributes(),'child attrs',false)
        if child:IsA('StringValue') then
            for _,key in ipairs(keys) do
                if child.Name==key then parse(child.Value); sources['StringValue']=true; if #names>0 then known=true end end
            end
        end
    end
    table.sort(names)
    local origin={}; for source in pairs(sources) do origin[#origin+1]=source end; table.sort(origin)
    return names,known,table.concat(origin,' + ')
end
local function meshSignature(model)
    local ids={}
    for _,obj in ipairs(model:GetDescendants()) do
        if obj:IsA('MeshPart') or obj:IsA('SpecialMesh') then
            local id=tostring(obj.MeshId):match('%d+')
            if id then ids[#ids+1]=id end
        end
    end
    table.sort(ids)
    return #ids>0 and table.concat(ids,':') or nil
end
local function uniqueMatch(candidates)
    local found
    for _,candidate in ipairs(candidates) do
        if found and found~=candidate then return nil end
        found=candidate
    end
    return found
end
local function readTraitNames(record)
    local names,seen={},{}
    local known=record.Mutations~=nil or record.BaseMutation~=nil
    local function add(value)
        if type(value)=='string' and value~='' and value~='None' and value~='Normal' and not seen[value] then seen[value]=true;names[#names+1]=value end
    end
    if type(record.Mutations)=='table' then
        for key,value in pairs(record.Mutations) do
            if value==true and type(key)=='string' then add(key)
            elseif type(value)=='string' then add(value)
            elseif type(value)=='table' then local id=value.Id or value._id or value.Name; if type(id)=='string' then add(id) else known=false end end
        end
    elseif type(record.Mutations)=='string' then
        for value in record.Mutations:gmatch('[^,;|]+') do add(value:match('^%s*(.-)%s*$')) end
    end
    add(record.BaseMutation);table.sort(names)
    return names,known
end
--============================================================================--
--  [3-5] FINDER UI + NETWORK + RENDERER - createFinder(D) wires the glass
--        panel, the broadcast/feed networking and the egg-card list together.
--============================================================================--
local function createFinder(D)
    local cycleModule
    pcall(function() cycleModule=module('Shared.Util.AreaEggCycle') end)
    local function cycleInfo()
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
    -- Display/join quarantine only. This never filters broadcast snapshots.
    D.publicPrioritySeen={}
    D.publicPriorityVisible=function(entry,rank)
        if rank~=1 then return true end
        local first=D.publicPrioritySeen[entry.key]
        if not first then first=os.clock();D.publicPrioritySeen[entry.key]=first end
        return os.clock()-first>=5
    end
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

    local originalMake,originalLabel=D.make,D.label
    D.make=function(class,props,parent)
        if class=='TextButton' or class=='TextBox' then props.Font=Enum.Font.GothamBold;props.TextSize=math.max(props.TextSize or 15,15) end
        if class=='TextBox' then props.TextColor3=Color3.fromRGB(25,25,30) end
        local obj=originalMake(class,props,parent)
        if class=='TextButton' or class=='TextBox' then originalMake('UICorner',{CornerRadius=UDim.new(0,5)},obj) end
        return obj
    end
    D.label=function(parent,text,pos,size,color,fontSize)
        local obj=originalLabel(parent,text,pos,size,color or Color3.fromRGB(240,242,255),math.max(fontSize or 15,14))
        obj.Font=Enum.Font.GothamBold;obj.TextStrokeColor3=Color3.new(0,0,0);obj.TextStrokeTransparency=0.45;return obj
    end
    local DISCORD='https://discord.com/users/1078459357185970268'
    local Http=game:GetService('HttpService')
    local Teleports=game:GetService('TeleportService')
    local requestFn=request or http_request or (syn and syn.request) or (http and http.request)
    local active,othersOnly=true,false
    local reporterId=Http:GenerateGUID(false)
    local config,configAt=nil,-math.huge
    local feed,feedAt={},0
    local clockOffset=0
    local networkBusy=false
    local networkTicket=0
    local localStates={}
    local reportStatus='Connecting'
    local queryStatus=''
    local minRate,minRank=1e9,6
    local serversMinValue=1e9
    local joining=false
    local joinedEggSettingKey='UNKNOWNJoinedEggV1'
    local joinedEgg
    pcall(function()
        local saved=Teleports:GetTeleportSetting(joinedEggSettingKey)
        if type(saved)=='table' and type(saved.uid)=='string' and type(saved.jobId)=='string' and type(saved.placeId)=='number' then joinedEgg=saved end
    end)
    local function rememberJoinedEgg(entry)
        if type(entry)~='table' or entry.uid==nil or tonumber(entry.placeId)==nil or type(entry.jobId)~='string' then return end
        local saved={
            placeId=tonumber(entry.placeId),jobId=entry.jobId,uid=tostring(entry.uid),
            name=tostring(entry.name or 'Unknown egg'),rate=tonumber(entry.rate) or 0,
            missingRate=entry.missingRate==true,scale=tonumber(entry.scale),weight=tonumber(entry.weight),
            icon=type(entry.icon)=='string' and entry.icon or '',rarity=tostring(entry.rarity or 'Unknown'),
            rank=tonumber(entry.rank or entry.localTier) or 0,
            mutations=tostring(entry.mutations or entry.mutationText or ''),
            traitsKnown=entry.traitsKnown~=false,area=tostring(entry.area or ''),
            source=tostring(entry.source or 'field')
        }
        joinedEgg=saved
        pcall(function() Teleports:SetTeleportSetting(joinedEggSettingKey,saved) end)
    end
    D.joinedEgg=joinedEgg
    local localHighlight
    local pageOffset,nextOffset=0,nil
    local queryEpoch=0
    local settingsPath='tenshi_beta_ui.json'
    local settings={}
    if type(readfile)=='function' then pcall(function() local data=Http:JSONDecode(readfile(settingsPath));if type(data)=='table' then settings=data end end) end
    -- Auto Steal defaults ON. It only acts on eggs the join flow tracked, plus
    -- the best local egg while Auto Join is armed - never on random field eggs.
    local autoStealEnabled=type(settings.autoSteal)~='boolean' or settings.autoSteal
    local autoJoinMinValue=1e9
    local autoJoinMinValueSettingKey='UNKNOWNAutoJoinMinValueV1'
    -- TeleportSetting is the freshest value across a server hop; local JSON may be stale.
    local teleportSavedAutoJoinValue
    pcall(function()
        local saved=Teleports:GetTeleportSetting(autoJoinMinValueSettingKey)
        if type(saved)=='number' and saved>=1e9 and saved<=50e9 then teleportSavedAutoJoinValue=saved end
    end)
    if teleportSavedAutoJoinValue then
        autoJoinMinValue=teleportSavedAutoJoinValue
    elseif type(settings.autoJoinMinValue)=='number' and settings.autoJoinMinValue>=1e9 and settings.autoJoinMinValue<=50e9 then
        autoJoinMinValue=settings.autoJoinMinValue
    end
    if type(settings.myServer)=='boolean' then othersOnly=settings.myServer end
    if type(settings.serversMinValue)=='number' and settings.serversMinValue>=1e9 and settings.serversMinValue<=50e9 then serversMinValue=settings.serversMinValue end
    if type(settings.minRank)=='number' then
        local saved=math.floor(settings.minRank)
        if saved>=6 and saved<=10 then minRank=saved
        elseif saved==0 and settings.rarityMenu=='mythic-up-v1' then minRank=0 end
    end
    local menuHotkey=Enum.KeyCode.F
    local sharingNotice=D.label(D.gui,'EGG FINDER ON • Sharing egg sightings & server ID',UDim2.new(0,12,1,-28),UDim2.new(1,-24,0,22),Color3.fromRGB(245,245,245),12)
    sharingNotice.Visible=false;sharingNotice.TextSize=12;sharingNotice.TextWrapped=true;sharingNotice.TextStrokeTransparency=0.15
    local panel=D.make('Frame',{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-18,0.5,0),Size=UDim2.new(0.94,0,0.86,0),BackgroundColor3=Color3.fromRGB(22,23,27),Visible=false},D.gui)
    local responsiveScale=D.make('UIScale',{Scale=0.8},panel)

    D.make('UICorner',{CornerRadius=UDim.new(0,4)},panel)
    D.make('UIStroke',{Color=Color3.fromRGB(125,128,138),Thickness=2},panel)
    local bar=D.make('Frame',{Position=UDim2.fromOffset(1,1),Size=UDim2.new(1,-2,0,45),BackgroundColor3=Color3.fromRGB(0,0,0),BorderSizePixel=0},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,4)},bar)
    local heading=D.label(panel,'MARVIN',UDim2.fromOffset(14,8),UDim2.new(1,-55,0,32),nil,22)
    local open=D.make('ImageButton',{Image='',Position=UDim2.fromOffset(18,80),Size=UDim2.fromOffset(90,90),BackgroundColor3=Color3.fromRGB(250,250,250),ScaleType=Enum.ScaleType.Fit,ClipsDescendants=true},D.gui)
    D.make('UICorner',{CornerRadius=UDim.new(1,0)},open)
    local fallback=D.label(open,'MARVIN',UDim2.new(),UDim2.fromScale(1,1),Color3.fromRGB(150,25,40),19)
    local iconCaption=D.label(open,'MARVIN',UDim2.new(0.5,-48,1,5),UDim2.fromOffset(96,27),Color3.new(1,1,1),18)
    open.ClipsDescendants=true
    -- Original icon only; no decorative portal or black-hole effects.
    iconCaption.TextStrokeTransparency=0.15;iconCaption.TextXAlignment=Enum.TextXAlignment.Center
    local function restorePosition(target,value)
        if type(value)~='table' then return end
        for i=1,4 do if type(value[i])~='number' or value[i]~=value[i] or math.abs(value[i])>5000 then return end end
        target.Position=UDim2.new(value[1],value[2],value[3],value[4])
    end
    if settings.desktopLayoutVersion==2 then restorePosition(panel,settings.panel) end
    restorePosition(open,settings.icon)
    D.publicGuiPercent=function(value,factor)
        local n=tonumber(value) or (tonumber(factor) or 1)*100
        if n~=n or math.abs(n)==math.huge then n=100 end
        return math.clamp(math.floor(n/10+0.5)*10,70,150)
    end
    do
        local latest
        local function consider(value)
            if type(value)=='table' and type(value.percent)=='number' and value.percent>=70 and value.percent<=150 and type(value.at)=='number' and (not latest or value.at>latest.at) then latest=value end
        end
        if type(readfile)=='function' then pcall(function() consider(Http:JSONDecode(readfile('tenshi_public_gui_size_v2.json'))) end) end
        pcall(function() local data=Teleports:GetTeleportSetting('TenshiPublicGuiSizeV2');if type(data)=='string' then consider(Http:JSONDecode(data)) end end)
        if latest then settings.sizePercent=latest.percent end
    end
    D.savePublicGuiSize=function(percent)
        local data=Http:JSONEncode({percent=percent,at=workspace:GetServerTimeNow()*1000})
        if type(writefile)=='function' then pcall(writefile,'tenshi_public_gui_size_v2.json',data) end
        pcall(function() Teleports:SetTeleportSetting('TenshiPublicGuiSizeV2',data) end)
    end
    local sizePercent=D.publicGuiPercent(settings.sizePercent,settings.sizeFactor)
    local sizeFactor=sizePercent/100
    local launcherScale=D.make('UIScale',{Scale=0.8},open)
    local function fitFinder()
        local view=D.gui.AbsoluteSize
        if view.X<=0 or view.Y<=0 then return end
        local baseWidth,baseHeight=1500,850
        local scale=math.min(1.08*sizeFactor,view.X*0.90/baseWidth,view.Y*0.88/baseHeight)
        scale=math.max(0.42,scale)
        responsiveScale.Scale=scale
        panel.AnchorPoint=Vector2.new(0.5,0.5)
        panel.Position=UDim2.fromScale(0.5,0.5)
        panel.Size=UDim2.fromOffset(baseWidth,baseHeight)
        launcherScale.Scale=math.min(0.8,math.max(0.5,math.min(view.X,view.Y)/650))
        local function keepVisible(target,caption)
            local size=target.AbsoluteSize
            local p=target.Position
            local anchor=target.AnchorPoint
            local x=p.X.Scale*view.X+p.X.Offset
            local y=p.Y.Scale*view.Y+p.Y.Offset
            x=math.clamp(x,8+size.X*anchor.X,math.max(8+size.X*anchor.X,view.X-8-size.X*(1-anchor.X)))
            y=math.clamp(y,8+size.Y*anchor.Y,math.max(8+size.Y*anchor.Y,view.Y-8-caption-size.Y*(1-anchor.Y)))
            target.Position=UDim2.fromScale(x/view.X,y/view.Y)
        end
        task.defer(function()
            if panel.Parent then keepVisible(panel,0);keepVisible(open,28*launcherScale.Scale) end
        end)
    end
    local resizeConnection=D.gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(fitFinder)
    D.gui.Destroying:Connect(function() resizeConnection:Disconnect() end)
    task.defer(fitFinder)

    local function saveSettings()
        pcall(D.savePublicGuiSize,sizePercent)
        if type(writefile)~='function' then return end
        pcall(function()
            local function coords(p) return {p.X.Scale,p.X.Offset,p.Y.Scale,p.Y.Offset} end
            writefile(settingsPath,Http:JSONEncode({desktopLayoutVersion=2,myServer=othersOnly,minRank=minRank,rarityMenu='mythic-up-v1',serversMinValue=serversMinValue,autoJoinMinValue=autoJoinMinValue,autoExecute=autoExecuteEnabled,autoSteal=autoStealEnabled,sizeFactor=sizeFactor,sizePercent=sizePercent,panel=coords(panel.Position),icon=coords(open.Position)}))
        end)
    end
    local settingsButton=D.make('TextButton',{Name='SettingsButton',Text='SETTINGS',Position=UDim2.new(0,0,0,7),Size=UDim2.fromOffset(92,34),BackgroundColor3=Color3.fromRGB(42,44,52),BackgroundTransparency=0,TextColor3=Color3.fromRGB(255,255,255),TextSize=12,Font=Enum.Font.GothamBold,BorderSizePixel=0,ZIndex=20},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,5)},settingsButton)
    local settingsOverlay=D.make('Frame',{Name='SettingsOverlay',Position=UDim2.fromScale(0,0),Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(18,20,26),BackgroundTransparency=0.04,BorderSizePixel=0,Visible=false,ZIndex=30},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,5)},settingsOverlay)
    local settingsTitle=D.label(settingsOverlay,'SETTINGS',UDim2.fromOffset(14,12),UDim2.new(1,-70,0,34),Color3.fromRGB(255,255,255),19)
    settingsTitle.ZIndex=31
    local settingsClose=D.make('TextButton',{Name='SettingsClose',Text='X',Position=UDim2.new(1,-46,0,10),Size=UDim2.fromOffset(32,30),BackgroundColor3=Color3.fromRGB(150,45,50),TextColor3=Color3.new(1,1,1),TextSize=14,Font=Enum.Font.GothamBold,BorderSizePixel=0,ZIndex=31},settingsOverlay)
    D.make('UICorner',{CornerRadius=UDim.new(0,5)},settingsClose)
    local autoExecuteToggle=D.make('TextButton',{Name='AutoExecuteToggle',Text='',Position=UDim2.fromOffset(14,62),Size=UDim2.new(1,-28,0,46),BackgroundColor3=Color3.fromRGB(67,70,80),TextColor3=Color3.fromRGB(255,255,255),TextSize=14,Font=Enum.Font.GothamBold,BorderSizePixel=0,ZIndex=31},settingsOverlay)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},autoExecuteToggle)
    local discordAccountButton=D.make('TextButton',{Name='DiscordAccountButton',Text='DISCORD ACCOUNT',Position=UDim2.fromOffset(14,120),Size=UDim2.new(1,-28,0,46),BackgroundColor3=Color3.fromRGB(88,70,150),TextColor3=Color3.fromRGB(255,255,255),TextSize=14,Font=Enum.Font.GothamBold,BorderSizePixel=0,ZIndex=31},settingsOverlay)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},discordAccountButton)
    discordAccountButton.Activated:Connect(function()
        local discordUrl='https://discord.com/users/1078459357185970268'
        local opened=false
        local openers={
            function() if type(openurl)=='function' then openurl(discordUrl);return true end end,
            function() if type(open_url)=='function' then open_url(discordUrl);return true end end,
            function() if syn and type(syn.open_url)=='function' then syn.open_url(discordUrl);return true end end,
            function() game:GetService('GuiService'):OpenBrowserWindow(discordUrl);return true end
        }
        for _,tryOpen in ipairs(openers) do
            local ok,result=pcall(tryOpen)
            if ok and result==true then opened=true;break end
        end
        if not opened then
            local copied=false
            if type(setclipboard)=='function' then copied=pcall(setclipboard,discordUrl)
            elseif type(toclipboard)=='function' then copied=pcall(toclipboard,discordUrl) end
            pcall(function()
                game:GetService('StarterGui'):SetCore('SendNotification',{
                    Title='MARVIN • Discord',
                    Text=copied and 'Could not open Discord automatically. Profile link copied; paste it in your browser.' or 'Could not open Discord automatically. Use the Discord link shown at the top of the menu.',
                    Duration=6
                })
            end)
        end
    end)
    local function refreshAutoExecuteToggle()
        autoExecuteToggle.Text=autoExecuteEnabled and 'AUTO EXECUTE: ON' or 'AUTO EXECUTE: OFF'
        autoExecuteToggle.BackgroundColor3=autoExecuteEnabled and Color3.fromRGB(40,135,75) or Color3.fromRGB(155,48,52)
    end
    refreshAutoExecuteToggle()
    settingsButton.Activated:Connect(function() settingsOverlay.Visible=not settingsOverlay.Visible end)
    settingsClose.Activated:Connect(function() settingsOverlay.Visible=false end)
    autoExecuteToggle.Activated:Connect(function()
        autoExecuteEnabled=not autoExecuteEnabled
        refreshAutoExecuteToggle()
        saveSettings()
        if not autoExecuteEnabled then autoExecuteQueued=false end
    end)
    local autoStealToggle=D.make('TextButton',{Name='AutoStealToggle',Text='',Position=UDim2.fromOffset(14,178),Size=UDim2.new(1,-28,0,46),BackgroundColor3=Color3.fromRGB(40,135,75),TextColor3=Color3.fromRGB(255,255,255),TextSize=14,Font=Enum.Font.GothamBold,BorderSizePixel=0,ZIndex=31},settingsOverlay)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},autoStealToggle)
    local function refreshAutoStealToggle()
        autoStealToggle.Text=autoStealEnabled and 'AUTO STEAL: ON' or 'AUTO STEAL: OFF'
        autoStealToggle.BackgroundColor3=autoStealEnabled and Color3.fromRGB(40,135,75) or Color3.fromRGB(155,48,52)
    end
    refreshAutoStealToggle()
    autoStealToggle.Activated:Connect(function()
        autoStealEnabled=not autoStealEnabled
        refreshAutoStealToggle()
        saveSettings()
    end)
    D.saveGuiBeforeTeleport=saveSettings
    heading.Size=UDim2.fromOffset(185,32)
    heading.TextSize=19
    local brandLogo=D.make('ImageLabel',{Name='TenshiBrandLogo',Position=UDim2.fromOffset(10,2),Size=UDim2.fromOffset(180,42),BackgroundTransparency=1,Image='',ScaleType=Enum.ScaleType.Fit,Active=true},panel)
    brandLogo.Visible=false
    heading.Text='MARVIN'
    heading.TextSize=18
    heading.Font=Enum.Font.Arcade
    heading.TextScaled=true
    heading.TextWrapped=false
    heading.TextTruncate=Enum.TextTruncate.None
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=20},heading)
    heading.Size=UDim2.fromOffset(205,25)
    heading.Position=UDim2.fromOffset(10,2)
    heading.TextStrokeTransparency=0.65
    open.BackgroundTransparency=1
    iconCaption.Visible=false
    task.spawn(function()
        local asset=getcustomasset or getsynasset
        if type(asset)~='function' or type(writefile)~='function' then return end
        local ok,result=pcall(function()
            local bytes=game:HttpGet('https://i.scdn.co/image/ab67616d0000b273d85c932f1ebfa1ad27758dfc')
            if #bytes<100 then return end
            writefile('unknown_purple_eclipse_icon_v1.png',bytes)
            return asset('unknown_purple_eclipse_icon_v1.png')
        end)
        if ok and type(result)=='string' and open.Parent then open.Image=result;fallback.Visible=false end
    end)

    -- Original circular image is restored without overlay effects.

    -- Main-panel red close button intentionally removed.
    local suppressOpenUntil=0
    open.Activated:Connect(function() if os.clock()<suppressOpenUntil then return end; panel.Visible=not panel.Visible; D.localPanel.Visible=not panel.Visible end)
    local Input=game:GetService('UserInputService')
    local drag
    local function draggable(target,handle,isLauncher)
        handle.Active=true
        handle.InputBegan:Connect(function(input)
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            drag={target=target,input=input,start=input.Position,position=target.Position,absolute=target.AbsolutePosition,size=target.AbsoluteSize,launcher=isLauncher,moved=false}
        end)
    end
    draggable(panel,heading,false)
    draggable(panel,brandLogo,false)
    -- Window dragging is confined to its header; scrollbar has no drag overlay.
    draggable(panel,bar,false)

    draggable(open,open,true)
    local launcherHit=D.make('TextButton',{Name='LauncherHitArea',Text='',AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.fromOffset(-8,-8),Size=UDim2.new(1,16,1,16),ZIndex=5},open)
    draggable(open,launcherHit,true)
    launcherHit.Activated:Connect(function()
        if os.clock()<suppressOpenUntil then return end
        panel.Visible=not panel.Visible;D.localPanel.Visible=not panel.Visible
    end)
    local moveConnection=Input.InputChanged:Connect(function(input)
        if not drag then return end
        local mouse=drag.input.UserInputType==Enum.UserInputType.MouseButton1
        if (mouse and input.UserInputType~=Enum.UserInputType.MouseMovement) or (not mouse and input~=drag.input) then return end
        local dx,dy=input.Position.X-drag.start.X,input.Position.Y-drag.start.Y
        if dx*dx+dy*dy>25 then drag.moved=true end
        if not drag.moved then return end
        if drag.launcher then suppressOpenUntil=os.clock()+0.5 end
        local view=D.gui.AbsoluteSize
        local origin=D.gui.AbsolutePosition
        if view.X<=0 or view.Y<=0 then return end
        local left=drag.absolute.X-origin.X
        local top=drag.absolute.Y-origin.Y
        local x=math.clamp(left+dx,0,math.max(0,view.X-drag.size.X))
        local y=math.clamp(top+dy,0,math.max(0,view.Y-drag.size.Y-(drag.launcher and 28*launcherScale.Scale or 0)))
        local anchor=drag.target.AnchorPoint
        drag.target.Position=UDim2.fromScale((x+anchor.X*drag.size.X)/view.X,(y+anchor.Y*drag.size.Y)/view.Y)
    end)
    local endConnection=Input.InputEnded:Connect(function(input)
        if drag and (input==drag.input or input.UserInputType==Enum.UserInputType.MouseButton1) then
            if drag.moved and drag.launcher then suppressOpenUntil=os.clock()+0.3 end
            if drag.moved then saveSettings() end
            drag=nil
        end
    end)
    D.gui.Destroying:Connect(function() moveConnection:Disconnect();endConnection:Disconnect();drag=nil end)
    local status=D.label(panel,'Connecting…',UDim2.fromOffset(14,52),UDim2.new(1,-28,0,48),Color3.fromRGB(210,218,240),14)
    status.Visible=true
    status.TextWrapped=true
    local discordSubtitle=D.label(panel,DISCORD,UDim2.fromOffset(10,27),UDim2.fromOffset(205,14),Color3.new(1,1,1),11)
    discordSubtitle.TextSize=11
    discordSubtitle.TextScaled=true;discordSubtitle.TextWrapped=false;discordSubtitle.Visible=true
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=11},discordSubtitle)
    local page={Text=''}
    local scope=D.make('TextButton',{Name='AllServers',Text='ALL SERVERS',Position=UDim2.new(0,10,1,-176),Size=UDim2.new(0.5,-15,0,34),BackgroundColor3=Color3.fromRGB(67,70,80),TextColor3=Color3.new(1,1,1),TextSize=14},panel)
    local myScope=D.make('TextButton',{Name='MyServer',Text='MY SERVER',Position=UDim2.new(0.5,5,1,-176),Size=UDim2.new(0.5,-15,0,34),BackgroundColor3=Color3.fromRGB(67,70,80),TextColor3=Color3.new(1,1,1),TextSize=14},panel)
    for _,button in ipairs({scope,myScope}) do
        button.TextScaled=true;button.TextWrapped=false
        D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=14},button)
    end
    local function styleScope()
        scope.BackgroundColor3=othersOnly and Color3.fromRGB(67,70,80) or Color3.fromRGB(45,130,75)
        myScope.BackgroundColor3=othersOnly and Color3.fromRGB(45,130,75) or Color3.fromRGB(67,70,80)
        scope.TextColor3=Color3.new(1,1,1);myScope.TextColor3=Color3.new(1,1,1)
    end
    local requestScopeRender
    local function setScope(myServer)
        if othersOnly==myServer then return end
        othersOnly=myServer;styleScope()
        page.Text=othersOnly and 'LOCAL EGGS' or 'TOP 10'
        queryEpoch+=1;pageOffset=0;feedAt=-math.huge;task.defer(saveSettings)
        if requestScopeRender then requestScopeRender() end
    end
    scope.Activated:Connect(function() setScope(false) end)
    myScope.Activated:Connect(function() setScope(true) end)
    styleScope()
    local rarityOptions={{name='Mythic',rank=6},{name='Cosmic',rank=7},{name='Secret',rank=8},{name='Eternal',rank=9},{name='Divine',rank=10},{name='Any',rank=0}}
    local rarityIndex=#rarityOptions
    minRank=0
    local function rarityButtonText()
        local name=rarityOptions[rarityIndex].name
        local colors={Mythic='#FF4B55',Cosmic='#BE55FF',Secret='#FFFFFF',Eternal='#DACAEC',Divine='#FFCD37',Any='#FFFFFF'}
        return 'MIN RARITY: <font color="'..colors[name]..'">'..name..'</font>'
    end
    local rarity=D.make('TextButton',{Text=rarityButtonText(),RichText=true,Position=UDim2.new(0,10,1,-96),Size=UDim2.new(0.60,-15,0,36),BackgroundColor3=Color3.fromRGB(45,90,175),TextColor3=Color3.new(1,1,1),TextSize=12},panel)
    rarity.Visible=false;rarity.Active=false
    rarity.Activated:Connect(function()
        rarityIndex=rarityIndex%#rarityOptions+1;minRank=rarityOptions[rarityIndex].rank
        rarity.Text=rarityButtonText()
        queryEpoch+=1;feed={};pageOffset=0;feedAt=-math.huge;saveSettings()
    end)
    local refreshButton=D.make('TextButton',{Text='REFRESH',Position=UDim2.fromOffset(10,54),Size=UDim2.new(1,-20,0,30),BackgroundColor3=Color3.fromRGB(115,215,45),BackgroundTransparency=0.15,TextColor3=Color3.new(1,1,1),TextSize=14},panel)
    local resetTimer=D.label(refreshButton,'RESET --:--',UDim2.fromOffset(8,0),UDim2.new(0.28,-8,1,0),Color3.fromRGB(230,245,255),13)
    resetTimer.TextXAlignment=Enum.TextXAlignment.Left
    resetTimer.TextTruncate=Enum.TextTruncate.AtEnd
    resetTimer.Active=false
    local refreshing=false
    local list=D.make('ScrollingFrame',{Position=UDim2.fromOffset(14,92),Size=UDim2.new(1,-16,1,-278),BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.None,CanvasSize=UDim2.new(),ScrollBarThickness=6,ScrollBarImageColor3=Color3.fromRGB(150,132,190),ScrollBarImageTransparency=0.1},panel)
    
    --========================================================================--
    --  [3] MARVIN DESKTOP THEME 2.0 (visual-only)
    --  Wide midnight dashboard, animated energy sweep, moving nebulae and
    --  restrained neon accents. No gameplay callbacks or data flow are changed.
    --========================================================================--
    local Theme = {
        bg        = Color3.fromRGB(5, 10, 22),
        bgDeep    = Color3.fromRGB(4, 8, 18),
        glass     = Color3.fromRGB(13, 24, 42),
        glassHigh = Color3.fromRGB(20, 38, 61),
        accent    = Color3.fromRGB(53, 216, 255),
        accentHot = Color3.fromRGB(159, 93, 255),
        cyan      = Color3.fromRGB(92, 231, 255),
        text      = Color3.fromRGB(239, 247, 255),
        muted     = Color3.fromRGB(143, 166, 195),
        green     = Color3.fromRGB(65, 238, 167),
        tabActive = Color3.fromRGB(24, 93, 131),
    }
    D.theme = Theme
    local starTweens = {}
    local TweenService = game:GetService('TweenService')

    panel.BackgroundColor3 = Theme.bg
    panel.BackgroundTransparency = 0
    panel.ClipsDescendants = true
    local glassCorner = panel:FindFirstChildOfClass('UICorner')
    if glassCorner then glassCorner.CornerRadius = UDim.new(0, 20) end

    local panelGradient = D.make('UIGradient', {
        Rotation = 24,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(5, 11, 25)),
            ColorSequenceKeypoint.new(0.48, Color3.fromRGB(11, 18, 39)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 10, 36)),
        }),
    }, panel)
    local panelMotion = TweenService:Create(panelGradient,
        TweenInfo.new(26, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Rotation = 204})
    panelMotion:Play()
    table.insert(starTweens, panelMotion)

    local glassStroke = panel:FindFirstChildOfClass('UIStroke')
    if glassStroke then
        glassStroke.Color = Theme.accent
        glassStroke.Thickness = 2
        glassStroke.Transparency = 0.08
        glassStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        local borderGradient = D.make('UIGradient', {
            Rotation = 0,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Theme.accent),
                ColorSequenceKeypoint.new(0.48, Theme.accentHot),
                ColorSequenceKeypoint.new(1, Theme.cyan),
            }),
        }, glassStroke)
        local borderMotion = TweenService:Create(borderGradient,
            TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
            {Rotation = 360})
        borderMotion:Play()
        table.insert(starTweens, borderMotion)
    end

    local edgeGlow = D.make('Frame', {
        Name = 'DesktopOuterGlow', BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4),
        Active = false, ZIndex = 1,
    }, panel)
    D.make('UICorner', {CornerRadius = UDim.new(0, 18)}, edgeGlow)
    D.make('UIStroke', {
        Color = Theme.accent, Thickness = 2, Transparency = 0.72,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, edgeGlow)

    if bar then
        bar.Size = UDim2.new(1, -2, 0, 88)
        bar.BackgroundColor3 = Theme.bgDeep
        bar.BackgroundTransparency = 0.02
        local barCorner = bar:FindFirstChildOfClass('UICorner')
        if barCorner then barCorner.CornerRadius = UDim.new(0, 18) end
        D.make('UIGradient', {
            Rotation = 0,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 17, 34)),
                ColorSequenceKeypoint.new(0.55, Color3.fromRGB(17, 22, 49)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(28, 13, 48)),
            }),
        }, bar)
    end

    local headerAccent = D.make('Frame', {
        Name = 'DesktopHeaderAccent', BorderSizePixel = 0, Active = false,
        Position = UDim2.new(0, 18, 0, 86), Size = UDim2.new(1, -36, 0, 2),
        BackgroundColor3 = Theme.accent, ZIndex = 4,
    }, panel)
    D.make('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.accent),
            ColorSequenceKeypoint.new(0.5, Theme.accentHot),
            ColorSequenceKeypoint.new(1, Theme.cyan),
        }),
    }, headerAccent)

    if heading then
        heading.TextColor3 = Theme.text
        heading.TextStrokeColor3 = Theme.accent
        heading.TextStrokeTransparency = 0.55
    end
    if status then
        status.TextColor3 = Theme.cyan
        status.TextStrokeTransparency = 1
    end

    local starfield = D.make('Frame', {
        Name = 'MARVIN_DesktopAmbient', BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0),
        Active = false, ZIndex = 2,
    }, panel)
    local starRandom = Random.new(7319)

    for i = 1, 38 do
        local dot = D.make('Frame', {
            Name = 'DesktopStar' .. i, BorderSizePixel = 0, Active = false, ZIndex = 2,
            Position = UDim2.fromScale(starRandom:NextNumber(0.02, 0.98), starRandom:NextNumber(0.12, 0.98)),
            BackgroundColor3 = (i % 5 == 0) and Theme.cyan or (i % 3 == 0) and Theme.accentHot or Color3.fromRGB(210, 232, 255),
        }, starfield)
        local dotSize = starRandom:NextInteger(2, 4)
        dot.Size = UDim2.fromOffset(dotSize, dotSize)
        dot.BackgroundTransparency = starRandom:NextNumber(0.36, 0.72)
        D.make('UICorner', {CornerRadius = UDim.new(1, 0)}, dot)
        local pulse = TweenService:Create(dot,
            TweenInfo.new(starRandom:NextNumber(1.8, 4.2), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {BackgroundTransparency = 0.9, Size = UDim2.fromOffset(dotSize + 2, dotSize + 2)})
        pulse:Play()
        table.insert(starTweens, pulse)
    end

    for i, spec in ipairs({
        {210, Theme.accent, 0.965, 0.10, 0.24},
        {170, Theme.accentHot, 0.968, 0.68, 0.62},
        {125, Theme.cyan, 0.972, 0.42, 0.78},
    }) do
        local nebula = D.make('Frame', {
            Name = 'DesktopNebula' .. i, BorderSizePixel = 0, Active = false, ZIndex = 2,
            Position = UDim2.fromScale(spec[4], spec[5]),
            Size = UDim2.fromOffset(spec[1], spec[1]),
            BackgroundColor3 = spec[2], BackgroundTransparency = spec[3],
        }, starfield)
        D.make('UICorner', {CornerRadius = UDim.new(1, 0)}, nebula)
        local drift = TweenService:Create(nebula,
            TweenInfo.new(9 + i * 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
            {Position = UDim2.fromScale(math.clamp(spec[4] + 0.08, 0.02, 0.82), math.clamp(spec[5] + 0.06, 0.12, 0.82)),
             BackgroundTransparency = 0.982})
        drift:Play()
        table.insert(starTweens, drift)
    end

    -- User-supplied portrait panel. Kept in its natural portrait ratio rather
    -- than cropping it across the entire 16:9 desktop dashboard.
    local portraitPanel = D.make('Frame', {
        Name = 'MARVIN_PortraitPanel',
        Position = UDim2.new(0.70, 0, 0, 100),
        Size = UDim2.new(0.28, -14, 1, -206),
        BackgroundColor3 = Color3.fromRGB(5, 12, 25),
        BackgroundTransparency = 0.02,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 3,
    }, panel)
    D.make('UICorner', {CornerRadius = UDim.new(0, 16)}, portraitPanel)
    local portraitStroke = D.make('UIStroke', {
        Color = Theme.cyan, Thickness = 1.5, Transparency = 0.18,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, portraitPanel)

    local portraitImage = D.make('ImageLabel', {
        Name = 'UserPortrait',
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Image = '',
        ImageTransparency = 0.08,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 3,
    }, portraitPanel)

    local portraitTint = D.make('Frame', {
        Name = 'PortraitGlassTint',
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(4, 12, 28),
        BackgroundTransparency = 0.60,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, portraitPanel)
    D.make('UICorner', {CornerRadius = UDim.new(0, 16)}, portraitTint)
    D.make('UIGradient', {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 9, 20)),
            ColorSequenceKeypoint.new(0.48, Color3.fromRGB(5, 22, 42)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 8, 18)),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.24),
            NumberSequenceKeypoint.new(0.50, 0.62),
            NumberSequenceKeypoint.new(1, 0.18),
        }),
    }, portraitTint)

    task.spawn(function()
        local customAsset = getcustomasset or getsynasset
        if type(customAsset) ~= 'function' or type(writefile) ~= 'function' then
            warn('[MARVIN] Portrait needs getcustomasset/getsynasset and writefile support.')
            return
        end
        local ok, assetOrError = pcall(function()
            local bytes = game:HttpGet('https://raw.githubusercontent.com/farsazzat1113/marvin/Marvin/assets/marvin_photo_background.jpg')
            assert(type(bytes) == 'string' and #bytes > 1000, 'Portrait download was empty')
            writefile('marvin_desktop_photo_v1.jpg', bytes)
            return customAsset('marvin_desktop_photo_v1.jpg')
        end)
        if ok and type(assetOrError) == 'string' and portraitImage.Parent then
            portraitImage.Image = assetOrError
        else
            warn('[MARVIN] Could not load portrait: '..tostring(assetOrError))
        end
    end)

    local energySweep = D.make('Frame', {
        Name = 'DesktopEnergySweep', BorderSizePixel = 0, Active = false,
        Position = UDim2.new(0, 0, 0.12, 0), Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.cyan, BackgroundTransparency = 0.55, ZIndex = 2,
    }, starfield)
    D.make('UIGradient', {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.18, 0.35),
            NumberSequenceKeypoint.new(0.82, 0.35),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, energySweep)
    local sweepMotion = TweenService:Create(energySweep,
        TweenInfo.new(8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Position = UDim2.new(0, 0, 0.94, 0)})
    sweepMotion:Play()
    table.insert(starTweens, sweepMotion)

    local function liftAboveBackdrop(obj)
        if obj:IsA('GuiObject') and obj ~= starfield and obj ~= edgeGlow
            and not obj:IsDescendantOf(starfield) and obj.ZIndex <= 2 then
            obj.ZIndex = 3
        end
    end
    for _, obj in ipairs(panel:GetDescendants()) do liftAboveBackdrop(obj) end
    panel.DescendantAdded:Connect(function(obj)
        if obj ~= starfield and obj ~= edgeGlow and not obj:IsDescendantOf(starfield) then
            task.defer(function()
                if obj.Parent then liftAboveBackdrop(obj) end
            end)
        end
    end)

    local function styleGlassControl(obj)
        if obj:IsA('TextButton') then
            if obj.Name ~= 'JoinStatusButton' and obj.Name ~= 'AutoJoin' then
                obj.BackgroundColor3 = Theme.glass
                obj.BackgroundTransparency = 0.02
            end
            obj.TextColor3 = Theme.text
            obj.Font = Enum.Font.GothamBold
            obj.AutoButtonColor = false
            local stroke = obj:FindFirstChildOfClass('UIStroke')
            if not stroke then
                stroke = Instance.new('UIStroke')
                stroke.Thickness = 1
                stroke.Parent = obj
            end
            stroke.Color = Theme.accent
            stroke.Transparency = 0.34
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            local corner = obj:FindFirstChildOfClass('UICorner')
            if not corner then
                corner = Instance.new('UICorner')
                corner.Parent = obj
            end
            corner.CornerRadius = UDim.new(0, 10)
            if obj == refreshButton then
                obj.BackgroundColor3 = Color3.fromRGB(33, 114, 160)
                stroke.Color = Theme.cyan
                stroke.Transparency = 0.08
                stroke.Thickness = 1.6
            elseif obj == settingsButton then
                obj.BackgroundColor3 = Theme.glassHigh
            elseif obj == scope or obj == myScope then
                obj.BackgroundColor3 = Theme.glass
            end
        elseif obj:IsA('TextBox') then
            obj.BackgroundColor3 = Theme.glassHigh
            obj.TextColor3 = Theme.text
            obj.Font = Enum.Font.GothamBold
            local stroke = obj:FindFirstChildOfClass('UIStroke')
            if not stroke then
                stroke = Instance.new('UIStroke')
                stroke.Thickness = 1
                stroke.Parent = obj
            end
            stroke.Color = Theme.accent
            stroke.Transparency = 0.38
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            local corner = obj:FindFirstChildOfClass('UICorner')
            if corner then corner.CornerRadius = UDim.new(0, 8) end
        elseif obj:IsA('Frame') then
            if obj.Name == 'ValueOfServers' or obj.Name == 'MinAutoJoinValue' then
                obj.BackgroundColor3 = Theme.glass
                local corner = obj:FindFirstChildOfClass('UICorner')
                if corner then corner.CornerRadius = UDim.new(0, 10) end
                D.make('UIStroke', {
                    Color = Theme.accent, Thickness = 1, Transparency = 0.52,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                }, obj)
            elseif obj.Name == 'SettingsOverlay' then
                obj.BackgroundColor3 = Theme.bg
                obj.BackgroundTransparency = 0.01
                local corner = obj:FindFirstChildOfClass('UICorner')
                if corner then corner.CornerRadius = UDim.new(0, 18) end
                D.make('UIStroke', {
                    Color = Theme.accent, Thickness = 2, Transparency = 0.18,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                }, obj)
            end
        elseif obj:IsA('TextLabel') then
            if obj.TextColor3 ~= Theme.green then
                obj.TextStrokeColor3 = Color3.fromRGB(1, 5, 16)
                obj.TextStrokeTransparency = math.min(obj.TextStrokeTransparency, 0.72)
            end
        end
    end
    for _, obj in ipairs(panel:GetDescendants()) do styleGlassControl(obj) end
    panel.DescendantAdded:Connect(function(obj)
        if obj ~= starfield and obj ~= edgeGlow and not obj:IsDescendantOf(starfield) then
            task.defer(function()
                if obj.Parent then styleGlassControl(obj) end
            end)
        end
    end)

    local function refreshGlassScope()
        if scope then scope.BackgroundColor3 = othersOnly and Theme.glass or Theme.tabActive end
        if myScope then myScope.BackgroundColor3 = othersOnly and Theme.tabActive or Theme.glass end
    end
    if scope then scope.Activated:Connect(function() task.defer(refreshGlassScope) end) end
    if myScope then myScope.Activated:Connect(function() task.defer(refreshGlassScope) end) end
    refreshGlassScope()

    if open then
        D.make('UIStroke', {
            Color = Theme.cyan, Thickness = 2.5, Transparency = 0.08,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, open)
    end

    local popTween
    panel:GetPropertyChangedSignal('Visible'):Connect(function()
        if not panel.Visible then return end
        local target = responsiveScale.Scale
        if type(target) ~= 'number' or target <= 0 then return end
        responsiveScale.Scale = target * 0.965
        if popTween then popTween:Cancel() end
        popTween = TweenService:Create(responsiveScale,
            TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {Scale = target})
        popTween:Play()
    end)

    gui.Destroying:Connect(function()
        for _, tween in ipairs(starTweens) do pcall(function() tween:Cancel() end) end
        if popTween then pcall(function() popTween:Cancel() end) end
    end)
    D.make('UIListLayout',{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},list)
    local loadingVisible=true
    local function loadingText(now)
        return 'Loading '..string.rep('.',math.floor(now/0.4)%3+1)
    end
    local aliveMessage=D.label(list,loadingText(os.clock()),UDim2.new(),UDim2.new(1,-10,0,40),nil,12)
    local function network(url,method,body,headers,raw)
        if type(requestFn)~='function' then return nil,'Executor HTTP POST unavailable' end
        if networkBusy then return nil,'Network request still pending' end
        networkBusy=true
        networkTicket+=1
        local ticket=networkTicket
        local done,result=false,nil
        local worker=task.spawn(function()
            result=table.pack(pcall(requestFn,{Url=url,Method=method,Headers=headers or {},Body=body,Timeout=10}))
            done=true; if networkTicket==ticket then networkBusy=false end
        end)
        local deadline=os.clock()+12
        while active and not done and os.clock()<deadline do task.wait(0.1) end
        if not done then
            if networkTicket==ticket then networkTicket+=1;networkBusy=false end
            pcall(task.cancel,worker)
            return nil,'Network timeout'
        end
        if not result[1] then return nil,'Network request failed' end
        local response=result[2]
        if type(response)~='table' then return nil,'Invalid HTTP response' end
        local code=tonumber(response.StatusCode or response.Status)
        if code~=200 then
            local message='HTTP '..tostring(code)
            local good,details=pcall(Http.JSONDecode,Http,response.Body or '')
            if good and type(details)=='table' and type(details.error)=='string' then message=message..': '..details.error:sub(1,120) end
            return nil,message
        end
        if raw then return response.Body end
        local ok,decoded=pcall(Http.JSONDecode,Http,response.Body or '')
        if not ok then return nil,'Invalid JSON response' end
        return decoded
    end
    -- Roblox public-server directory, independent of the Finder report feed.
    status.Size=UDim2.new(0.53,-14,0,24)
    status.TextSize=11
    -- Independent minimum income shown in ALL SERVERS; Auto Join keeps its own threshold.
    local serversValueFrame=D.make('Frame',{Name='ValueOfServers',Position=UDim2.new(0,10,1,-136),Size=UDim2.new(1,-20,0,34),BackgroundColor3=Color3.fromRGB(67,70,80),BorderSizePixel=0},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},serversValueFrame)
    local serversValueLabel=D.label(serversValueFrame,'VALUE OF SERVERS',UDim2.fromOffset(8,0),UDim2.new(0.62,-8,1,0),Color3.new(1,1,1),11)
    serversValueLabel.TextXAlignment=Enum.TextXAlignment.Left
    local serversValueInput=D.make('TextBox',{Name='ValueOfServersInput',Text=string.format('%gB',serversMinValue/1e9),PlaceholderText='1B - 50B',ClearTextOnFocus=false,Position=UDim2.new(0.64,0,0,3),Size=UDim2.new(0.36,-5,1,-6),BackgroundColor3=Color3.fromRGB(45,90,175),TextColor3=Color3.new(1,1,1),PlaceholderColor3=Color3.fromRGB(205,210,220),TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Center,BorderSizePixel=0},serversValueFrame)
    D.make('UICorner',{CornerRadius=UDim.new(0,5)},serversValueInput)
    serversValueInput.TextColor3=Color3.fromRGB(255,255,255)
    local function parseServersMinValue(value)
        if type(value)~='string' then return nil end
        local number=value:match('^%s*(%d+%.?%d*)%s*[bB]%s*$')
        local amount=tonumber(number)
        if not amount or amount<1 or amount>50 then return nil end
        return amount*1e9
    end
    serversValueInput.FocusLost:Connect(function()
        local parsed=parseServersMinValue(serversValueInput.Text)
        if parsed then
            serversMinValue=parsed
            serversValueInput.Text=serversValueInput.Text:match('^%s*(.-)%s*$'):upper()
            saveSettings()
            if requestScopeRender then requestScopeRender() end
            queryStatus='ALL SERVERS minimum set to '..serversValueInput.Text
        else
            serversValueInput.Text=string.format('%gB',serversMinValue/1e9)
            queryStatus='Enter a value from 1B to 50B (example: 1.5B)'
        end
    end)
    -- Auto Join minimum is loaded from persistent settings above.
    local minValueFrame=D.make('Frame',{Name='MinAutoJoinValue',Position=UDim2.new(0,10,1,-94),Size=UDim2.new(1,-20,0,34),BackgroundColor3=Color3.fromRGB(67,70,80),BorderSizePixel=0},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},minValueFrame)
    local minValueLabel=D.label(minValueFrame,'MIN AUTO JOIN VALUE',UDim2.fromOffset(8,0),UDim2.new(0.62,-8,1,0),Color3.new(1,1,1),11)
    minValueLabel.TextXAlignment=Enum.TextXAlignment.Left
    local minValueInput=D.make('TextBox',{Name='MinAutoJoinValueInput',Text=string.format('%gB',autoJoinMinValue/1e9),PlaceholderText='1B - 50B',ClearTextOnFocus=false,Position=UDim2.new(0.64,0,0,3),Size=UDim2.new(0.36,-5,1,-6),BackgroundColor3=Color3.fromRGB(45,90,175),TextColor3=Color3.new(1,1,1),PlaceholderColor3=Color3.fromRGB(205,210,220),TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Center,BorderSizePixel=0},minValueFrame)
    D.make('UICorner',{CornerRadius=UDim.new(0,5)},minValueInput)
    minValueInput.TextColor3=Color3.fromRGB(255,255,255)
    local function parseAutoJoinMinValue(value)
        if type(value)~='string' then return nil end
        local number=value:match('^%s*(%d+%.?%d*)%s*[bB]%s*$')
        local amount=tonumber(number)
        if not amount or amount<1 or amount>50 then return nil end
        return amount*1e9
    end
    minValueInput.FocusLost:Connect(function()
        local parsed=parseAutoJoinMinValue(minValueInput.Text)
        if parsed then
            autoJoinMinValue=parsed
            pcall(function() Teleports:SetTeleportSetting(autoJoinMinValueSettingKey,autoJoinMinValue) end)
            minValueInput.Text=minValueInput.Text:match("^%s*(.-)%s*$")
            saveSettings()
            autoJoinCandidates={};autoJoinCandidateIndex=1;autoJoinRetryRequested=false
            queryStatus='Auto Join minimum set to '..minValueInput.Text
        else
            minValueInput.Text=string.format('%.0fB',autoJoinMinValue/1e9)
            queryStatus='Enter a value from 1B to 50B (example: 1.5B)'
        end
    end)
    -- Beast Auto Join: selects the highest-income valid egg from the shared Finder feed.
    local autoJoinEnabled=false
    local autoJoinBusy=false
    local autoJoinCandidates={}
    local autoJoinCandidateIndex=1
    local autoJoinRetryRequested=false
    local autoJoinButton=D.make('TextButton',{Name='AutoJoin',Text='AUTO JOIN: OFF',Position=UDim2.new(0,10,1,-52),Size=UDim2.new(1,-20,0,40),BackgroundColor3=Color3.fromRGB(200,45,45),TextColor3=Color3.new(1,1,1),TextSize=13,Font=Enum.Font.GothamBold},panel)
    D.make('UICorner',{CornerRadius=UDim.new(0,6)},autoJoinButton)
    autoJoinButton.TextScaled=true;autoJoinButton.TextWrapped=false
    D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=14},autoJoinButton)
    local function paintAutoJoin()
        autoJoinButton.Text=autoJoinEnabled and 'AUTO JOIN: ON' or 'AUTO JOIN: OFF'
        autoJoinButton.BackgroundColor3=autoJoinEnabled and Color3.fromRGB(30,155,85) or Color3.fromRGB(200,45,45)
    end
    autoJoinButton.Activated:Connect(function()
        if not active then return end
        autoJoinEnabled=not autoJoinEnabled
        autoJoinCandidates={};autoJoinCandidateIndex=1;autoJoinRetryRequested=false
        if autoJoinEnabled then feedAt=-math.huge end
        paintAutoJoin()
        queryStatus=autoJoinEnabled and 'Auto Join enabled: checking all available pages' or 'Auto Join disabled'
    end)
    local publicBroadcastConfig=nil
    local featureConfig=nil
    local featureSending=false
    local featureTicket=0
    local function optionalFeatureSync(payload)
        if not featureConfig or featureSending or type(requestFn)~='function' then return end
        local endpoint,key=featureConfig.endpoint,featureConfig.roomKey
        featureSending=true;featureTicket+=1
        local ticket=featureTicket
        local worker=task.spawn(function()
            local ok,response=pcall(function()
                return requestFn({Url=endpoint..'/v1/report',Method='POST',Timeout=6,
                    Headers={['Content-Type']='application/json',['X-NYX-Room']=key},Body=Http:JSONEncode(payload)})
            end)
            if featureTicket~=ticket then return end
            featureSending=false
            if D.gui then pcall(function() D.gui:SetAttribute('TenshiFeatureReportOK',ok and type(response)=='table' and tonumber(response.StatusCode or response.Status)==200) end) end
        end)
        task.delay(8,function()
            if featureTicket==ticket and featureSending then featureTicket+=1;featureSending=false;pcall(task.cancel,worker) end
        end)
    end
    -- Feature configuration is optional. Its requests never own the primary
    -- broadcast/feed network lock and cannot gate the classic public sender.
    task.spawn(function()
        while active do
            local ok,data=pcall(function()
                local response=requestFn({Url='https://raw.githubusercontent.com/syss1211/Tenshi-script/experimental/NYX-Finder-Experimental-Config.json?features='..os.time(),Method='GET',Timeout=6})
                if tonumber(response.StatusCode or response.Status)~=200 then return nil end
                return Http:JSONDecode(response.Body)
            end)
            if ok and type(data)=='table' and type(data.endpoint)=='string' and data.endpoint:match('^https://[%w%.%-]+$') and type(data.roomKey)=='string' then
                featureConfig=data
                if publicBroadcastConfig then config=data;feedAt=-math.huge end
            end
            task.wait(60)
        end
    end)
    local function loadConfig()
        local data,err=network('https://raw.githubusercontent.com/syss1211/Tenshi-script/main/NYX-Finder-Config.json?nyx='..os.time(),'GET')
        if not data then return false,err end
        if type(data.endpoint)~='string' or not data.endpoint:match('^https://[%w%.%-]+$') or type(data.roomKey)~='string' then return false,'Finder configuration unavailable' end
        publicBroadcastConfig=data;config=featureConfig or data; configAt=os.clock()
        if false and type(writefile)=='function' then
            local asset=getcustomasset or getsynasset
            if type(asset)=='function' then
                local bytes=network(config.endpoint..'/assets/finder.jpg','GET',nil,nil,true)
                if bytes then
                    pcall(function() writefile('nyx_finder_icon_v19.jpg',bytes);open.Image=asset('nyx_finder_icon_v19.jpg');fallback.Visible=false end)
                end
            end
        end
        return true
    end
    local function headers() return {['Content-Type']='application/json',['X-NYX-Room']=config.roomKey} end
    local broadcastInterval=5
    local function snapshot()
        local eggs={}
        for _,entry in ipairs(D.entries()) do
            if not entry.unresolved and entry.uid and entry.rate and entry.rate>0 then
                eggs[#eggs+1]={uid=tostring(entry.uid),name=entry.name,category=entry.category,rarity=entry.rarity,rank=entry.tier,rate=entry.rate,scale=entry.scale,weight=entry.weight,icon=entry.icon,area=entry.areaKey or entry.area,mutations=entry.mutationText or (entry.traitsKnown==false and 'UNKNOWN' or ''),traitsKnown=entry.traitsKnown~=false,estimated=entry.estimated==true or entry.unmutatedRate~=nil or entry.scaleFromModel==true,visualId=entry.visualId==true,source=entry.isEvent and 'event' or 'field'}
            end
        end
        table.sort(eggs,function(a,b) return a.rate>b.rate end)
        while #eggs>10 do eggs[#eggs]=nil end
        return eggs
    end
    local function report()
        if game.JobId=='' then return false,'No live server ID' end
        if not D.ready() then return false,'Waiting for a fresh field scan' end
        if not publicBroadcastConfig then return false,'Public broadcast configuration unavailable' end
        local eggs=snapshot()
        local good,metadata=pcall(function() return D.metadata and D.metadata() end)
        if not good then metadata=nil end
        local classicEggs=eggs
        -- Match the classic sender's native spawn-slot behavior. Optional state
        -- parsing is protected and never becomes a prerequisite for reporting.
        if metadata and type(metadata.states)=='table' then
            local parsed,filtered=pcall(function()
                local states={}
                for _,state in ipairs(metadata.states) do states[state.uid]=state.state end
                local values={}
                for _,e in ipairs(eggs) do if e.source=='event' or states[e.uid]=='Slot' then values[#values+1]=e end end
                return values
            end)
            if parsed then classicEggs=filtered end
        end
        local body={placeId=game.PlaceId,jobId=game.JobId,reporterId=reporterId,eggs=classicEggs}
        local data,err=network(publicBroadcastConfig.endpoint..'/v1/report','POST',Http:JSONEncode(body),
            {['Content-Type']='application/json',['X-NYX-Room']=publicBroadcastConfig.roomKey})
        if not data or data.ok~=true or type(data.accepted)~='number' then return false,err or 'Public broadcast not acknowledged' end
        if #classicEggs>0 and data.accepted<=0 then return false,'Public broadcast accepted zero eggs' end
        if D.gui then pcall(function() D.gui:SetAttribute('TenshiPublicAccepted',data.accepted);D.gui:SetAttribute('TenshiPublicSent',#classicEggs) end) end
        -- A separate, bounded worker sends feature metadata after primary ACK.
        -- The feature service must not relay this already-published report.
        local native={placeId=game.PlaceId,jobId=game.JobId,reporterId=reporterId,eggs=eggs,publicDirect=true,primaryAccepted=data.accepted,primarySent=#classicEggs}
        pcall(function()
            if metadata then
                native.eggStates=metadata.states;native.resetAt=metadata.resetAt;native.scanAt=metadata.scanAt
                native.scanAgeMs=math.max(0,(os.clock()-metadata.scanClock)*1000)
                native.resetRemainingMs=metadata.resetAt and math.max(0,metadata.resetAt-workspace:GetServerTimeNow()*1000) or nil
            end
            native.userId=D.player.UserId;native.playerIds={}
            for _,member in ipairs(game:GetService('Players'):GetPlayers()) do native.playerIds[#native.playerIds+1]=member.UserId end
            optionalFeatureSync(native)
        end)
        return true,'Shared '..tostring(data.accepted)..' eggs'
    end
    D.flushReport=report
    local function refresh(forceAllServers)
        local epoch=queryEpoch
        local baseQuery='?localJob='..Http:UrlEncode(game.JobId)..'&placeId='..game.PlaceId..'&limit=10&tier=public&minRate='..tostring(minRate)..'&minRank='..tostring(minRank)
        local requestedCycle=cycleInfo()
        if requestedCycle then baseQuery=baseQuery..'&cycleRemainingMs='..tostring(math.max(0,requestedCycle.remaining*1000))..'&cycleId='..tostring(requestedCycle.resetAt) end
        if othersOnly and not forceAllServers then baseQuery=baseQuery..'&onlyJob='..Http:UrlEncode(game.JobId) end

        -- Follow the Finder API's nextOffset cursor, with strict bounds and
        -- duplicate-page protection so a malformed cursor cannot loop forever.
        local allItems,seenItems={},{}
        local mergedStates={}
        local offset,maxPages=0,30
        local pageCount=0
        local pageLimitReached=false
        local lastPageSignature=nil
        local serverTime=nil
        while pageCount<maxPages do
            local requestQuery=baseQuery..'&offset='..tostring(offset)
            local data,err=network(config.endpoint..'/v1/eggs'..requestQuery,'GET',nil,headers())
            if epoch~=queryEpoch then return true end
            if not data or type(data.items)~='table' then
                if pageCount==0 then return false,err or 'Invalid finder feed' end
                queryStatus='Finder pagination stopped: '..tostring(err or 'invalid page')
                break
            end

            pageCount+=1
            serverTime=tonumber(data.serverTime) or serverTime
            for _,entry in ipairs(data.localStates or {}) do
                if type(entry)=='table' and entry.key~=nil then mergedStates[entry.key]=entry end
            end

            local signatureParts={}
            for _,entry in ipairs(data.items) do
                local identity
                if type(entry)=='table' then
                    identity=type(entry.key)=='string' and entry.key
                        or (tostring(entry.placeId or '')..':'..tostring(entry.jobId or '')..':'..tostring(entry.uid or ''))
                end
                if identity and identity~='::' then
                    signatureParts[#signatureParts+1]=identity
                    if not seenItems[identity] then
                        seenItems[identity]=true
                        allItems[#allItems+1]=entry
                    end
                end
            end
            local signature=table.concat(signatureParts,'|')
            if #data.items==0 or signature=='' or signature==lastPageSignature then
                nextOffset=nil
                break
            end
            lastPageSignature=signature
            local following=tonumber(data.nextOffset)
            if not following or following<=offset then
                nextOffset=following
                break
            end
            nextOffset=following
            if following==offset then break end
            offset=following
            task.wait(0.12)
        end

        if epoch~=queryEpoch then return true end
        pageLimitReached=pageCount>=maxPages
        clockOffset=(serverTime or os.time()*1000)/1000-os.clock()
        localStates=mergedStates
        feed={}
        for _,entry in ipairs(allItems) do
            if D.publicEntryAllowed(entry,(os.clock()+clockOffset)*1000) then
                feed[#feed+1]=entry
            end
        end
        D.savePublicSightings()
        feedAt=os.clock()
        if pageLimitReached then
            queryStatus='Updated '..tostring(#feed)..' reports (30-page safety limit; more may exist)'
        else
            queryStatus='Updated '..tostring(#feed)..' reports from '..tostring(pageCount)..' pages'
        end
        page.Text='TOP '..tostring(#feed)
        return true
    end
    local function localBestAutoJoinRate()
        local best=0
        if not D.ready() then return best end
        for _,egg in ipairs(snapshot()) do
            local rate=tonumber(egg.rate) or 0
            local rank=tonumber(egg.rank) or 0
            if rate>=autoJoinMinValue and rank>=minRank and rate>best then best=rate end
        end
        return best
    end
    -- Auto Join compares the best eligible local egg against every public server.
    -- It stays local on ties and only teleports when a strictly better remote egg exists.
    -- Reservation failures and asynchronous teleport failures advance to the next candidate.
    task.spawn(function()
        while active do
            if autoJoinEnabled and not autoJoinBusy and not joining then
                autoJoinBusy=true
                local ok,err=pcall(function()
                    if not config then
                        queryStatus='Auto Join: waiting for Finder connection'
                        return
                    end
                    if #autoJoinCandidates==0 then
                        if os.clock()-feedAt>6 then
                            local refreshed,message=refresh(true)
                            if not refreshed then
                                queryStatus='Auto Join: '..tostring(message or 'feed refresh failed')
                                return
                            end
                        end
                        local now=(os.clock()+clockOffset)*1000
                        local candidates={}
                        for _,entry in ipairs(feed) do
                            local rate=tonumber(entry.rate)
                            local job=type(entry.jobId)=='string' and entry.jobId or ''
                            local place=tonumber(entry.placeId)
                            local expiry=tonumber(entry.expiresAt)
                            local validEntry=job~='' and job~=game.JobId and place and place>0
                                and expiry and expiry>now and rate and rate>0
                                and entry.uid~=nil and entry.full~=true and entry.unavailable~=true
                                and entry.takenConfirmed~=true
                                and rate>=autoJoinMinValue
                                and D.publicEntryAllowed(entry,now)
                            if validEntry then candidates[#candidates+1]=entry end
                        end
                        table.sort(candidates,function(a,b)
                            local ar,br=tonumber(a.rate) or 0,tonumber(b.rate) or 0
                            if ar~=br then return ar>br end
                            return tostring(a.jobId)<tostring(b.jobId)
                        end)
                        local localBest=localBestAutoJoinRate()
                        local remoteBest=#candidates>0 and (tonumber(candidates[1].rate) or 0) or 0
                        if localBest>0 and localBest>=remoteBest then
                            autoJoinCandidates={};autoJoinCandidateIndex=1;autoJoinRetryRequested=false
                            queryStatus='Auto Join: best eligible egg is already in this server'
                            return
                        end
                        for i=1,#candidates do autoJoinCandidates[i]=candidates[i] end
                        autoJoinCandidateIndex=1
                        autoJoinRetryRequested=false
                    end
                    if autoJoinCandidateIndex>#autoJoinCandidates then
                        queryStatus='Auto Join: all available candidates failed'
                        autoJoinCandidates={};autoJoinCandidateIndex=1;autoJoinRetryRequested=false
                        feedAt=0
                        return
                    end
                    local target=autoJoinCandidates[autoJoinCandidateIndex]
                    local localBest=localBestAutoJoinRate()
                    if localBest>0 and localBest>=(tonumber(target and target.rate) or 0) then
                        autoJoinCandidates={};autoJoinCandidateIndex=1;autoJoinRetryRequested=false
                        queryStatus='Auto Join: best eligible egg is already in this server'
                        return
                    end
                    local now=(os.clock()+clockOffset)*1000
                    if not target or tonumber(target.expiresAt or 0)<=now then
                        autoJoinCandidateIndex+=1
                        autoJoinRetryRequested=true
                        queryStatus='Auto Join: report expired; trying next server'
                        return
                    end
                    queryStatus='Auto Join: trying #'..tostring(autoJoinCandidateIndex)..' '..tostring(target.name)..' ('..tostring(target.rate)..'/s)'
                    local claim,claimError=network(config.endpoint..'/v1/join','POST',
                        Http:JSONEncode({placeId=target.placeId,jobId=target.jobId,uid=target.uid,reporterId=reporterId,userId=D.player.UserId}),
                        headers())
                    if not claim or claim.allowed~=true then
                        if claim and (claim.unavailable or claim.full or claim.taken) then
                            target.full=true;target.unavailable=claim.unavailable==true
                        end
                        autoJoinCandidateIndex+=1
                        autoJoinRetryRequested=true
                        feedAt=0
                        queryStatus='Auto Join: server #'..tostring(autoJoinCandidateIndex-1)..' unavailable; trying next'
                        return
                    end
                    local joinExpiry=math.min(tonumber(target.expiresAt) or math.huge,tonumber(claim.expiresAt) or math.huge)
                    if now>=joinExpiry then
                        autoJoinCandidateIndex+=1;autoJoinRetryRequested=true;feedAt=0
                        queryStatus='Auto Join: report expired; trying next server'
                        return
                    end
                    joining=true
                    queryStatus='Auto Join: joining server #'..tostring(autoJoinCandidateIndex)
                    queueAutoExecute()
                    D.saveGuiBeforeTeleport()
                    D.stopFarm()
                    rememberJoinedEgg(target)
                    local teleported,teleportError=pcall(function()
                        Teleports:TeleportToPlaceInstance(target.placeId,target.jobId,D.player)
                    end)
                    if not teleported then
                        joining=false
                        autoJoinCandidateIndex+=1;autoJoinRetryRequested=true
                        queryStatus='Auto Join: teleport failed; trying next server'
                        warn('Tenshi Beast Auto Join teleport:',teleportError)
                    end
                end)
                if not ok then
                    joining=false
                    autoJoinCandidateIndex+=1
                    autoJoinRetryRequested=true
                    queryStatus='Auto Join error: '..tostring(err)
                    warn('Tenshi Beast Auto Join:',err)
                end
                autoJoinBusy=false
            end
            task.wait(0.25)
        end
    end)

    --========================================================================--
    --  AUTO STEAL: hands-free carry + plant. Picks up the egg a join tracked
    --  (joinedEgg), or - while Auto Join is armed - the best local egg over the
    --  Auto Join minimum. Server-side range rules still apply, so the character
    --  is parked next to the egg first and returned home to plant after.
    --========================================================================--
    local stealEggState,stealIdentity,stealPlot
    pcall(function() stealEggState=module('Client.EggState') end)
    pcall(function() stealIdentity=module('Shared.Util.AreaEggSlotIdentity') end)
    pcall(function() stealPlot=module('Client.PlotState') end)
    local stealDoneFor=nil
    local stealAttempts={}
    local function parkAt(cframe)
        local character=D.player.Character
        local root=character and character:FindFirstChild('HumanoidRootPart')
        if root and root:IsA('BasePart') then
            root.CFrame=cframe
            pcall(function()
                root.AssemblyLinearVelocity=Vector3.zero
                root.AssemblyAngularVelocity=Vector3.zero
            end)
        end
        return root
    end
    local function carryHome(uid)
        if not (stealEggState and stealPlot) then return end
        pcall(function()
            local plot=stealPlot.ResolvePlot()
            if not (plot and plot.CenterPoint) then return end
            task.wait(0.3)
            local homeCFrame=plot.CenterPoint.CFrame*CFrame.new(0,3,0)
            if typeof(plot.RespawnPointCFrame)=='CFrame' then
                homeCFrame=plot.RespawnPointCFrame*CFrame.new(0,3,0)
            end
            parkAt(homeCFrame)
            task.wait(0.35)
            local placed=stealEggState.PlantEgg(uid,CFrame.new(0,0,0))
            if not placed then
                task.wait(0.2)
                placed=stealEggState.PlantEgg(uid,CFrame.new(0,1,0))
            end
            if placed then queryStatus='Auto Steal: planted at your plot' end
        end)
    end
    task.spawn(function()
        while active do
            local ok,err=pcall(function()
                if not autoStealEnabled or not stealEggState then return end
                if type(D.ready)=='function' and not D.ready() then return end
                local carrying=stealEggState.ReadCarryState and stealEggState.ReadCarryState()
                if carrying and carrying.IsCarrying then
                    local carriedUid=tostring(carrying.Uid or '')
                    if carriedUid~='' then
                        carryHome(carriedUid)
                        task.wait(1.5)
                    end
                    return
                end
                local target,trackedEgg
                if joinedEgg and not joinedEgg.takenAt and joinedEgg.placeId==game.PlaceId and joinedEgg.jobId==game.JobId and stealDoneFor~=tostring(joinedEgg.uid) then
                    trackedEgg=joinedEgg
                    for _,egg in ipairs(D.entries()) do
                        if tostring(egg.uid)==tostring(trackedEgg.uid) then target=egg break end
                    end
                end
                if not target and (autoJoinEnabled or autoStealEnabled) then
                    local best,bestRate=nil,autoJoinMinValue or 1e9
                    for _,egg in ipairs(D.entries()) do
                        local rate=tonumber(egg.rate) or 0
                        local uid=tostring(egg.uid or '')
                        if rate>=bestRate and (egg.tier or 0)>=minRank and uid~=stealDoneFor and (stealAttempts[uid] or 0)<3 then
                            best,bestRate=egg,rate
                        end
                    end
                    target=best
                end
                if not target then return end
                local uid=tostring(target.uid)
                local model=target.model or modelFor(uid)
                local pos=(model and model.Parent and model:GetPivot().Position) or (typeof(target.worldPos)=='Vector3' and target.worldPos)
                if not pos then return end
                parkAt(CFrame.new(pos+Vector3.new(0,3,2),pos))
                task.wait(0.35)
                local slotKey
                if stealIdentity and target.areaKey and target.nestId and stealIdentity.LooksLikeFirstAreaUid(uid) then
                    slotKey=stealIdentity.SlotKey(target.areaKey,target.nestId)
                end
                local carried=stealEggState.CarryFieldEgg(uid,slotKey)
                if carried then
                    stealDoneFor=uid
                    queryStatus='Auto Steal: carried '..tostring(target.name or uid)
                    if trackedEgg then
                        trackedEgg.takenAt=os.time()
                        local saved=table.clone(trackedEgg)
                        saved._lastScanAt=nil;saved._missingScans=nil
                        pcall(function() Teleports:SetTeleportSetting(joinedEggSettingKey,saved) end)
                    end
                    carryHome(uid)
                    task.wait(1.5)
                else
                    stealAttempts[uid]=(stealAttempts[uid] or 0)+1
                    if stealAttempts[uid]>=3 then
                        stealDoneFor=uid
                        queryStatus='Auto Steal: could not carry '..tostring(target.name or uid)
                    end
                end
            end)
            if not ok then warn('MARVIN auto steal:',err) end
            task.wait(0.75)
        end
    end)

    local lastRender
    local rarityColors={
        divine=Color3.fromRGB(255,205,55),eternal=Color3.fromRGB(218,202,236),
        secret=Color3.fromRGB(255,255,255),cosmic=Color3.fromRGB(190,85,255),
        mythic=Color3.fromRGB(255,75,85),legendary=Color3.fromRGB(255,155,45),
        epic=Color3.fromRGB(255,110,200),rare=Color3.fromRGB(65,165,255),
        uncommon=Color3.fromRGB(105,220,120),common=Color3.fromRGB(220,225,235)
    }
    local function weightPresentation(entry)
        local isKg=type(entry.weight)=='number'
        local value=isKg and entry.weight or entry.scale
        local neutral=Color3.fromRGB(220,224,235)
        if type(value)~='number' or value~=value or value<0 or value==math.huge then return '—',neutral end
        local compact=value>=1000
        local number
        if value>=1e15 then number=string.format('%.2g',value)
        elseif value>=1e12 then number=string.format('%.2f',value/1e12):gsub('0+$',''):gsub('%.$','')..'T'
        elseif value>=1e9 then number=string.format('%.2f',value/1e9):gsub('0+$',''):gsub('%.$','')..'B'
        elseif value>=1e6 then number=string.format('%.2f',value/1e6):gsub('0+$',''):gsub('%.$','')..'M'
        elseif compact then number=string.format('%.2f',value/1000):gsub('0+$',''):gsub('%.$','')..'K'
        else number=string.format('%.2f',value) end
        local color=neutral
        if not isKg and not compact then
            if value<0.60 then color=Color3.fromRGB(245,85,85)
            elseif value<0.80 then color=Color3.fromRGB(255,210,75)
            elseif value>2.50 then color=Color3.fromRGB(100,240,140) end
        end
        return (isKg and number..' KG' or '×'..number),color
    end
    local function mutationNames(entry)
        if entry.isEvent or entry.source=='event' then return {} end
        local raw=tostring(entry.mutations or entry.mutationText or ''):gsub('%s*%[[^%]]*%]',''):match('^%s*(.-)%s*$')
        raw=raw:gsub('^[Mm]utation[sS]?%s*:%s*','')
        local lower=raw:lower()
        if entry.traitsKnown==false or lower:find('unknown',1,true) or lower:find('unverified',1,true) then return {'Unknown'} end
        if raw=='' or lower=='none' or lower=='normal' or lower=='none (explicit data)' then return {} end
        local result,seen={},{}
        for token in raw:gmatch('[^,;|+]+') do
            local name=token:match('^%s*(.-)%s*$')
            local key=name:lower()
            if key=='gold' or key=='golden' then name='Golden';key='golden'
            elseif key=='silver' then name='Silver'
            elseif key=='rainbow' then name='Rainbow' end
            if name~='' and not seen[key] then result[#result+1]=name;seen[key]=true end
        end
        local order={golden=1,silver=2,rainbow=3}
        table.sort(result,function(a,b)
            local left,right=order[a:lower()] or 4,order[b:lower()] or 4
            if left~=right then return left<right end
            return a:lower()<b:lower()
        end)
        return result
    end
    -- Glyph masks rendered from Minecraft.ttf by Craftron Gaming:
    -- https://www.dafont.com/minecraft.font
    local mutationSpriteData={
        studs_v05={width=512,height=512,data='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'},
        kindly_full={width=82,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAFIAAAAgCAYAAACBxi9RAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAPTSURBVGhD7ZqNUeMwEEYpIA3QAA3QABVQAR3QQVqgBWqgCbqgmHDvW1ZCsn6d081ALm9GY0W7+iStZdmyc3Plys/n8/PzcDqdHklH0psSZVWwfZBeyN579QzKpSW7Qf7opgzKn91FPq+kOzcVYLslpZrvHB7cPM0qnSqIPX7JfkOZBvbqP5uorssYFCmI7yQFW502bY5ZMPld1aa8GkzKNeAIv+1Ec3x2lylW6RSg8SAhoUY8vW5tPfC/NTFQXS+TztEcvjm4T3HiAtg+TCiBsjs3qz+hTweS5bHH9nus0qmijpM06FuJcoyX2yzUeZIW2Xvpccwu7QRbCrBls2IL9myW67fqeD4uOeTtRHG09kes0imgYjhDCkBzloygrl0WHLUcqLM6KTVsLfJ8E+nILyB9T6G/GbK5a5dVOgVU1KDtUnKts/CO6RIRrdkobEZ6foQtA0IDDMltGSp31y6rdApcVFP8/ktqP9R/cS2dlBdSazYKC47nR8Q7qfpIWhHIJToFLnpWIKmndTWuZeT12GTBdJcM+bvrVCDxj4MirwDoJK0I5F/rFFBRa5oW/nBZGpS9uV2PL0/uY5BvPZ5YJ92tQDruOhtIm+lC2l5cBft0IL1KlVmdgpFwDerEAaa4uQn14qOFF3VR39z9YgMZB5ji5irUiZe14Lcekbqk7Yz6if0yAklxd42lznZXM2w3bWfkj/3/CCRke9mZdtN2Rv7Yf2Ugs12HoHg0I7MblDrspibqm7tfXiDxr77FwdQNpLtF1GE3NcHnsu7a+BQzcAs+1S1XwN0iFA2fW9NBKe/FVVLfHqt0Cqg4DKS7DnH3FnG7J/g9DCSkO5vfH0iovrzd4r4tMg3affLyJvikr+Z+fCCbO5HAjk42T4racTej5yuwZ+8kKQrvDqvgb7sz99WbLNv6krLXYtiW6BTI0RQ64FPdyWwZaWG3tVad8qIm+GQ3NYpmloIqaKV7/CU6BRhnAtkWSMCve8PZA1rZm2qKsncBe9E4V+oUYOtO9YC7D6Gh4dZvBBpn7eVHuMwynQw6PTWL5OdVuuiMeZWzQaP63YTymRtjkzCGVToFbh8xe+f+N5cOYNt+SNtL+F60RKdg8gxNf/eV71eVfdCP7DvNFlzOvlEIl1mmU8AAhh+98Jm6tAP4Dx+rUhREDtlDew38zlqDqZfN9FU6BTj03mxPPf5sUaMu0WXYuQTcd812tBWw4mpSmTlM0tKpgqMeQOO/H1R5zyBrUN/+HiItlzX4bQ+5ZIezcItrhm9NGZTZnxtI+jzSvYqwL9G5cuWncHPzB0AK0axMbE74AAAAAElFTkSuQmCC'},
        filter_divine={width=111,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAG8AAAAsCAYAAABrCeaiAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQDSURBVHhe7ZoNcdwwEIUD4AiEQAgcgSIIgjAog1AIhWAIibIomLTv2c/u6VZayTr5nHT2m/HE2j/Jeo4se+4hCIL/nc/Pzycc738Ezj9ok3t3ju7/24K5Os1TZsEEPipsN9DNof3vCi7gp67FRXfrG45nNE9Kr4L4l7mChX0rbDeO7n9XeAG6lk0gj0JW71yvPnyvCtuNo/vfFe/iWkD+i0ploV+hBvatsN04uv9d4QXoWrpBjTeVM8Adz7y9GCEe8QSEL3abe4CLGCIeQS13CQ0GM1I80bwTDW7EEw++D8U84nhmW64irDcVDvaHk615N1Asha3AfJ69ZRQ6gaYXf2YM+nlUO8ePqVAG+uYQC2sqpto/8eZBIYwxNzDafJaudVpQnXccv+cqM6yNg7vjttULwZvEI7A/KaTEOuE4b5285EIWYPc2Qm8KS2AthQwRD5zgd1cdb5wLCDtzbHOGD+KelVbGGzQHrDBDJW9dOtFsnbyqENfQp7AE1lLIEPHg+6VTl8t+r4GPX6Y2wTEpPU9l0EXx4Pben9Y8NFsnr3hx8Jn3MdrkNrCWwoaItxGzzNM2u7ooPja6xSP0KzThMg/N1slrEmOBNrkNrKWwu4uHOslKAROX3KalMsd1vQRv0PDdTTyCvOzyBLtZjmiTO4E1FDIB073/8ziG9QMAzjcvl9ewhsqleIOGr1e8dQLR3CLeq+wGhazIbGANhUzANEQ8+HmzTLtA/PVqMnZ9VuG8+LyEb/qogVP+d2ZvRgLf+1TsGnakGAN8d/3PQ9vb+l/ezd5uN3lGoH2zePCZyfPGAN/l9WdBTG41Ke5oFZKChC7x4B66YSFoezXXT288lzlH8o6E9gjxst9BeZ0KSYB9WnmYJ9PNTB1eUxl0UbxK3uZXhQX2KV8C7Ovdz3OZE5irkBWYbxZPIYZaDv54fW/FzFVNhKx4sA9/SV9omUQ1DcxVyArMId4CzNUBKXQCzU3i0Ta7stA3tJ7C7i4ecqtfZKq0iIe/3R+mYdo02UQ+A2vzUNOg9ASYDxOPqFkie/3NeAPopGvDcAnGVHym8VAzgTlKT4DrUPEQ435ag5+vCGYeYOejid9CXxjDtlz/gHGYeKhlXiZh7hHP201mYY7SE+A6WrybX9KFnStvAFtAnewaDlePeJu32MxRegJch4pHENf9eeyCfcRDjeLDF+7N4hH5m1GaAa6vIN6I973x4iHf/d0KQrrEQ93scy8HY5VmgPtw8QhibxVwnHjIa/rRLUJ7xWt+VjBWaQa4v4R4BGb3G2aFfvEQ1/Vzd8T2iuf9NCKBsUozwP1lxFuAmyLy1YvzWdo9L/PN3Wb2eR4EQRAEQRAEQRAEQRAEQfB9eHj4C9ICM72pnaD1AAAAAElFTkSuQmCC'},
        filter_cosmic={width=126,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAH4AAAAsCAYAAACjZQx0AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAATbSURBVHhe7ZsLcdwwEIYDIARKoARCoAiCIAzKoBRCIRhKIiwKJu336357zqeHJfvuEnf2m9HE2l2t1lo/JPnyEARBENybj4+P75S3v4bj35JZHfyPkOfHU7pzSP43m30eCoLyQnmjvDu2GWR/KLpSf1Ge3SxYgbF68RBmoPtps/tD/08EMD+GenHzYAUl10OWge6Xze4H/T6q41MI49hNsAJj/HXuePpU0rPH+Qh2FazAUH2Ndzz97U66sLugA8b782f16tT978LugiNA0p+dt93YZXAESPwf562KH0PPlMX7B5XeVU+UH+juPxsNtqGEUZoo4TbfBa40j5j2BLKLDZkuLum7Jzc007JTewjZqwrZO+WVkl2w1IvLKeS/rdf+xavFCep6Hz8lBxegUx/zHEnHFPXxaJMFyHWz1Cj2MYFe46j+ansraV+Fw7ofDBYndwn63UnHzfASUXFRqheAdJTueYls3TRBvZp4yndXi6BfjAn16hiiU2Ky5CMbTjxyjWN1/V+hnHwcVR/z6BaDtQV8aOa6+ippkAWOrLoUqnF5LtRrie+N9Yf9rF7Q2LynTs9APJR4fGwdxzzxCJsDSEe77nbaf7OrXeik7TJBvfmUKkGbrsT3QnttVXefH7aLsUTUnXjqwxf6GcXEtzrPBnwU2l9liahB5k96XOpvEg6iWFJQhvquxAvH1YVs3XUCUXfiFbvlWxhPvM02QfPVSeMISpT9NmOuocFLgRn5s+pu0Od8I1HtSryOT6LN3DfxnGTzAw967R3Mkx6OtRys7hyiS3cMh9WY1SdlnhDqGLFm/T9VLE6ofmpVJQ0YdtU99Qls9OrRxEsTztY5zDFQ7Uo8bdbGUed2ucTWOWvWr9VO/tSWQWpdodioE7sochnoBCoNXmvgNMFpvVfThKsH/FQTj25k1r54hLfiQ/dms+7Eu14Ef9vyQ9ubTO4UkF1koGt+ecKk9YqYZtLVdx463fVKqq761nKwdccvll/UqzHhJ9u0Qla8eJHPrxuqq4nHvjWO+zbLcFCdoJwHOgJNu67mEuirFyPxTO/55pPhHJ0fJbuA5csmGTaZwbZ1F7/YbAZZ8QmBfCjx+nuqFmmO4yq1ICfQD9/1NLtp4icUmwbT6iayc7OEfFm14NJuwuoS2fn0+Kb6uYnHwdW3bLG/6aO+BH51V2qC2Hofz33r2OIFyL9M4rG/3aNe4GR1PaqgKdmeNyrdoTqJxUcatalx6WMC1erkzqZNFIebLJBvmxwi8cL1IvjbPPlO4ODqn2XxeZPlnOBYH3LUXoN37kMXYfMJZtPDJJ4211/OnYPBVXbZ7G7txIYhvvPH9OZY7eIwidfxSbSZLL4FGHTPlFvYXUInavEu8DNv2Yqtfmk3r6M5PkTihdpZvoV24gVGu5NvVwl8tTZbusHP4nG1dSBoN09SOT5M4qk391tWWE+8wFDJv9rPq/F19c+yGkDruqHNq5snqB8m8YK21/ss28IdNScWJdx8AeLhiwn76g8xkA8lHvtsCSmZ1Qvk2yYLrC5xl8QL5BrHou8GY4mfoCN9eNAMUYkoDrjklNV/ocJUge/+6ZX0tpOfLCZk2q2TruoL+eESP4Fe46ic6ByzV7P6oehG25b0IAiCIAiCIAiCIAiCIAiCIAhuwMPDP7/xa7YQIwtaAAAAAElFTkSuQmCC'},
        filter_prefix={width=213,height=44,data='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'},
        filter_eternal={width=124,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAHwAAAAsCAYAAACnkNxJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQCSURBVHhe7ZqLcdwwDERdgBtwA27ADbgCV3AdpAO34BZcQ5pwFynmkl3e6ksSJCUmR2fwZjSSCCwACrJ+5wfHcRzHcb431+v1x+8TUK9Qzh2w+gfbT7kteMO/N0M1HLYLk06Lhp2O8PirFRHJY24JaqBeoSJg+yW3gIadjgzTcJhebx4LMjkdGabhTCaXGZmcjgzRcIw9ybxBZqcjXRueFFQA3btCbJDZ6chdGg7Xl5uiDcmTIPcblk8smwc/1oTlgs1HuUbAnpwTtXIJNWP/A8vXzbrUk9MTuUz1bW5b2P/E6kUuWeD3JP07Y2DZzJFwTLZDcyXUy22hWZAArt0ajmE2IjoAKeD3JtmG3Jw4H6wetY6Q3DwmIKufgP1DoZKU9CmguUi+waqVeeS2YAksJA9gt0vDUcubTNWwfslncnPC+BcX7UZIXjqIWf0a+GWbDltzwwnrUoiZQq3jNhy70WtcA68KEzg7p6P6BJu6JtgI2ZuB9klhAlatzCO3haOTkzyA3VMNxyYvk1WX8RTUKlTg7JyO6vfs65rA+JmGb64cVq3MI7cFS2AheQC7pxqOGpov5XsYQ+FOz+moPgViPSvsDMYON5woTMCqlXnktnB0cpJHWPHkEgFN9r4IW3hYwSavAh+30RjYPkMwYNUwwZxY+KScaoiph511hCdnrM2TnbFC0BUcUw4+oG7ycx8Ln/azrDWKkwS2MRsucwRiRQ8+nITMEXIpzol2uSax9LDNJ9YExp5ljoAtPugVMI9CpJhf/Qq1jtdw+GcPVisKWToIUcP2FPTRFYFgPHkiYvxLLk0wj0JEwFZ1+2JNcltoFhSw4sllA4YP3f8zhDO/MKdkw9a0zoG0aDDE21P46fjmscAx2rD5eBuJYS6Fau9fs6CAFU8uGzD8TxsekhY4oq/VwK/HA+r/2XDEMr9Y5cjVUDuf1jmQGg02z3xrmGEuhWzvX7OggBVPLhEy5yh+m96Tq6F2PkfmUKOBT/JbA8b5xjB/UMG2eRVgLrmaeWFra3gN6+SkEC/35cn8XAk7X4OixmOcDzZ8teH9kD+EhPsz1skaMH63hrM27aZIzS37NsJccjPzMobcFixBDevkBEPVl62pIKxP39eEeQ+f8pXI6YlcIkoarKxb17f+C0/+80OKdUHYPvxpdcWwDYe92+snc4WkwMoL299vOMGY+aVoYl0QtnsckGEbTuDT46QesuFVf+X7grB/tulDNxybYz+l17BOvgbjxealCsKw+c28wNANJ/Ab9z28hnXyPTBnvyiRZEECZmr54wafvrN62Zmj+IMC/eViktMTuUS0aDB0vy9tzrio+akl+a9djuM4juM4juM4juM4juM4TkceHv4APa4U8/FY6EsAAAAASUVORK5CYII='},
        filter_mythic={width=119,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAHcAAAAsCAYAAABfcCe+AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAASiSURBVHhe7ZuNVeMwEIQpgAZogAZogAquguuADmiBFqiBJuiCYribkUfGykpryYkdO+h7zy/R/mglT+zIdnLX6XQ6HY/v7+9HbO//BN5/0CZ356hAy/tBUgsEflDYOqDAiwr9kemisF/1/yLTLon7IQd8HwprBrl/1Y1h9X0ynRTeX1Rg9qeuf7O4Xr+vCluH0+JoX0Rg9JN8YllHrk3hOLDxOy5sMhs4Pg3V4OXNgdx9HLkR2M4SGPlv6mpk9YkUQN0vDSEgsyG3HyLwLRYX6df/zj0F9kUCI88IS1hHIZuBss9D9R/kMpT2A4FvsbgE+ddZLaOIN6kmgRGfFZawjsI2AzU/VH5ELsPMfjhL3KvhTYrAXyUw4orCEtZR6Cag3oNKJ8ht8PYDfLcpLkGMKzD8rrCEdRS+Caj3qtIJchu8/QDf7YpLEJcVGPZZYQnrKMWtqZAEmJ8Gb5anipgioQDwxgRfEBevf/he5gDa/C4NY8hBXwjMU8wj8N+r5ju2zyHlB44FGz/E+X7grBKXIDYRGO0qYQnrKO2I4n5yUzML/G/qKgGuZnFhp6jVugjbV2sniA8CczIyVcE6oSDwaiokAearilsL94m6G4G5SVz0wZV1cvlWyfniEuSYVegcrKOSNyuueFaXAbSrxUW7eE1cwWXEXcJvERf9fKnLAEzV4iK3+aCZ0MU9JRQAl9wP6Gu8QYFmlbh8P5gWc7viTmntn8ztB/nvGYtXV4jpXNGsGjtyxjtYOdgntuR2JcxPsHE1/YrN3vFi0pBugY9L7dpLHXOZMIV1VPJw4nJeChuB7VFuwzQezaqxq52FtRTWRs2k8OoKDH9cQf8acQns2csj2hVSNXbEex+U5Y8FkVw1KRaROQH28dqX8TIbWEdhbk2FJMC8V3Fn6+Dt7Nj5OjSzmPlV0zIptMeH74RtuQKMl8vAOgqr2ilTYO7iLqF1UrDFn80kwhLGh8QMrKOwuZrmGSds2bOGOLy46Oe6p+UpsGcfMjNeqQbWURjjkjPAlGkcgYm34rw7NocXl6idBXXWW1DVwnilGlhHYYwrflIJ/HGB9oDNvUQATeKC5A5SxMuBb3Vx5+bJWtgueymksCoYr1QD6ygsgPaS+6c5jLiwmV9glIhz5PhkMsSYU7wchbQcuV5cDWY/XFPcYt1Gckdu9kF9jjhHbzwx5hQvRyHV4hLWkX0J+xEXpnNukk+xkwKoN3c6D8Q5cnwyGWLMKV6OQprERXu7BwelSZVgvFINrKOwEdiKC6spiPOepZbErTp6OWbFX11cgj63eeRXmlQJxivVwDoKS4DdFRh+3h1r2kER5LoLN8IxK3YX4hLY139YX5pUCcYr1cA6CjPAzVVfchpVO6xs8bpIXAI/d1T4YfoQnkI74/C6G3Ej8J/3M5sjwAkO08ly3Il1/DMCCI/hOgdk5qgdT3+dHQHR3rTxj1L8XkqOQNrop4Al4H9XeGdPQBjvVFtL/77dI+eKy3x11dkbFxB33b8/dpazVFzkfWFb9gissw1LxEUOF1j90mfvUCRszxCMzyl5pyV3B4b/0eHdGa6ou6idTudmubv7DwiIO8uNEMiQAAAAAElFTkSuQmCC'},
        filter_secret={width=113,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAHEAAAAsCAYAAABSblf5AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAQSSURBVHhe7ZrrVa0wEEYtwAZswAZswAqswA7swBZswRpswi5uMXr3FwYuHPKAZI7eH7PXYkGSL0MmA+Rxzk0QBEEQBG2+vr7uOV44Pjj+fGewMh3SPZF1a9WD34RgKHgfU5hO82Bmgt/C3qYRIogOEIdnvUjzYdltEN9ZIEaIIDpALDbDl2W3oeKb1RkhgjgIffg4deU/rKiN6UeJIA6iz6f15YIV1aHivelHiSAOUBrSrLgOuodJngfjn5z0mm+WEBb8B84aiN+UtqKgA/rvVf19iRXXQdcK4p1Jh8DOE8c7x2bgJq1Z2DOXp9aZ0q9s6kHbYHbVMcsXgvTLVLpFWpOk/iCth3KxaUVZ0HX5RX6130tY9S3cqDozVblJu8CEOiW7YXAJuierVgSZgpcNRoUUyFI98jUWyW52jZxufAHZQ36R7RdEYeVZaMA7p67dGDV+snIc6rxY9R2UaTPiUMdd0Aripw5L7kg3X4F22C+yfINYcm4NGi1DHq1KE2lTxT529yHvdirqohrEFqkBBkkXv7h2fxP1KSk+iZdYQIuzUcpkr+eNSaiumVogr3c7ULgEkUs3v0j6BlFwg9OfKvQavHezUvJGt/BkexlHSHY5vMIliJ5+cekfRIFGT9rp3RvqbAJJuvhWU/YsDZfVe1H2noyBri07C+X6JWUzASNbEw/NHF85Uvukm2qUQaPxUfVyD6erXzPkFdtlkvNg9I5Dzh9+M1XHqsuRLGjeTLJAXvEzaZKiPUH9w+tTtNUgqtykWUy2o9evmVq7TDIGdtK6aTJZBk16wjh77QAlB2r2KHuV5ijoi501t7+Et19rau0yiQ/Y02ei+lkDzSBHx681slWzV5xc5WgEsfpGI3H1y8wmfiyIAputaX6r08/yY0E0SREk/28QMaDx79C4gs2hIHKf3djRQm2z6jsoc/mckt/88RWZq19rSu0SJqmDbmmcGsOh/T6Ng7nZXmutlhazdl3i1NsjrF4W2jQ8sZFfJqli8hKn/ZoptUuYpA46988EjapuHFCe3SwgP/vLCOerLjHIPxREdK5+zZAuBhHau2SI3IJIY1JHch5eFBupQ3Sekt3MD9doEF39miF9eCsv21byXYKI8U8zmSDdvT21YnFWjbe8HlyCKLz9Etg8/B+nbFvJ93oTN689N/NYVy3Ocn21DfBsxxTw9msGu63lWyLbVvKHg6jOMXMbHBy+fGKv9VPU4SAKb78ENg+9jdm2qjLHoafgEuqpQ6sDL+Vd+7HGzlnyZK82EcjhGkRBNVe/BPaaD0e1rZSrUfNsTr9OZGdiVqa/PbRnTSvQz/Y1O8uOb2Y7LXM4qksH5LM9179nnIXq1/BLuqItkwZBEARBEARBEARBEARBEAQ7bm7+AieAv2/JJn6AAAAAAElFTkSuQmCC'},
        filter_any={width=73,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAEkAAAAsCAYAAAApSpU1AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAMISURBVGhD7ZoNceMwEIUDIARK4AiEQBAcgmMQBkehFIqhJMoiYNJ7b/PsiSxpLfnvppa/GY9r7Y+9L7aqdXI6ODg4+Gk8Ho+P7woU1haqvRiI+kuhbcCCVXsxiPmj8DZgwaq9GD6eCm8DFqzaq1B4G6jmaiDum1LsGxaqmqtB7G+l2TcsVDVXg9h3pdk3LFQ1V4PYu9JEwHaTW4Rc7APC9qlhA8ecHy9yiSjJ+wqGL09rkux5AnDSuwKSwP6lP5PAnpyXvGLAGfZAnCGwJ+9SL69cAjA8TyQWKGePq/ZJkCM5L3nFwOYK3wG/SCgvr1wCMDxPJDi5AhD64cKydxtsfy3ZAK+YSq5KaWwuEguUcxLYbcHIvYYiYPuyZAO8YmpAnmDe8/LKJQDDs0Uam2+s9eBeQznOlvAFr5hakKvvE728cgnA8HSR4HB++rlYEl6kjnMEjwQZEwl2/lc1cbH3CqHvzZKCrUUqmo86NJQEFx7NS14xsEV9H8ayHwRsn3LbViTvZOT1wgiOvXkp8CVeftiSr1mYRy4BGO/nPS+vXAIwPEskd51Si9L21BZDSmI2FUlOSxKc8MeLROPTZzl48Upv/A+RYItW/xjzljl5kbwTTQU5h3PYWiJlG3LGy83AENsfr+1yRVp0PupQeqOk4CElMfBxlyOwW5uE/Ru2sZeJ7uO2CixAp1hNJAI/tymvIC0SC5HD4iB3/+XAyiJl/SrJiuS2GLAne7EO2uUaAVu/SPQKkUtEaQwOS7qFErIiuc8p7O7bRtjdplhuq4pE4Fv0RhV+Xn+aFknGLDy5XJPAZez9ks1LNQV31MbwWmVOAjv7w7p1EguQMQt83G9A4OLe6rxw+mG/ukgEpgvigqdDx9Z0Yz99xd0K/NAkSIpDJAKRvDVh9B6sOUbuouwjvAtQ/Ls2Lmc45wR3BMdopxA5YN/3bxlQ4BJt1b7no7kiMV6p9ssCIu3/hx5TRULcHVsbv9CbIhJi+m9nmoDFYrui8BsFwxb1ZxzD9oGN/wGP9dDBJpxO/wBE6iojlRTS+wAAAABJRU5ErkJggg=='},
        varesco_b08={width=157,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAJ0AAAAgCAYAAAAIcnp9AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAUxSURBVHhe7ZyNcds4FIRdgBtIA24gDaSCVOAOroO0kBZcQ5pwFynGd7vU4gnEHx9AUPQl/GY0JPEWuwCM6IfS5Oni4uLi7+Hj4+Off51A+47HGx6vuHyWRZEB3594fMdl05f0eJdg/9iHuYvxZDQfyyMhswRqvyRz61JQ/npTlZHslLkbIXwE9P2JQ3GT7PRl3+rm2+NN2D/1wfnUxaefrFcLH2emoPbwTUdw/pC5G3H4Dr7Kztjri/589nuR3YoJ3tmmI7iesvjw4SuBEfJImhmD2imbjuD68LkbafgOVhtvli98vsjS2OsdFqLkg7Zdi4/+fPZfEfJIKTOA2mmbjqDt0LkbpfAd2EviLF/4vMvS2OsdFqLmg/ahxUe/bNFJyCO1TILaqZuOoP2wuRu18BEYLNvZvquF2OvN/ls+aeYW0BcXnYQ8spF5+qYjqB0yd6MVPoJsp/rC67dsF/Z6h4XY8kHdtfjQVRedhDzSykTtU2w6gvr0uRutcNTiRXhpaSOW93advs2BE2jsvZ3Xe4uWTwCa5uKj7hn7/27TEWimzt1ohaOWTQ5tLyoXQf1Vul5f+5hd4Zuk3d41Wj4xHJu6rED75qIT5qiLe+xeXQrK0zYdgW7a3I1WOGrFyalcJIQc5UtGvEu0fFKgXS0+rl2LTpijbu6xe3UpKE/ddATaKXM3WuGoZZND2yHPdETlIvSTrGvBYtTd6PWBfll8HN2LTrxjR+1TbjoC/e65G61w1OJFOOQ9XQBtU15eW6i7MeLDsevUDXMU6V4Xry4F5UM2HWGuTt0wR5F3RsJbyLZncad+kGih7saoTy/MUWTPurh0KSgftulGYI4i78wMh9dR9+lWN4hHvdXdmDnGFsxRZDMTtWvTDTD9GwlhL61k1FvdjTMWvpWJ2rXpOjnqu9c3WRqj3uputHxQ+4WH600zdN+p12UGcxS5mSmZW5eC8u5NR388ps/dYKPqe5j+KxMCj3ccsp84jXqru9HyQW35w+LYXHzUw6e6P2rTSTN17gYbVe9Gg5r+ezqC/j9kldHyRq36B0nx+nAsal6Bdrt/Rb2aM5gjWU/m0BxRnrbpCM6nzd1go+qbQHvIL4dT0Lf4O7pAyxu16ZuO4Hp1S4fXKi1Qr1IGcyRzZ27oVt9Fx6C2+j1bimTucRBcT5m7wUbVM2gmWTcbvr9Z51FNK1iTTZEN70M2HUHbsvg8qsmgfulYgDmSuTNbOoL6chM+Bs3PaC+uKWFN0lPmbrBR9QyaSdaNxxfH6r9K9scjvjfH+3nLNWuSZaDmHvOITxhDCvXqmsEcydyZuGy+TBLo7RUH51wfvgeugrp9KMP5w+dujIR78Pji2PxKLYWeW94ePD6odc2denXNCHmkJ1PN04B//D7s4XM3ZobHeH1x3vzXGUNP9al6e/D4oHb6pmtpB3HdR03HsQX16prBHMnuzAyP8frifOs7V4Oe6rPrj+HxQe30TYem51tlP/BevQfsGccW1KtrBnMkuzMzPKbHF9euZzt6Sl/19uDxQe30TUfQ/O1WHQe+XTfYS+NoQb26ZjBHsjszw2N6fHHtem9HT+mr3h48Pqh9ik1H0O5+NUhB3zccum6w18ZRg3p1zWCOZHdmhsf0+qJtc+PRU9qqtwePD2qfZtMR1PjptJpRAvrstkpgdBwlWuNijmR3ZobHjPiixPtMr6zflDd4jQfvjIfbA1VvD+y/5cNMarxQr64ZIY/szYSGm+8HtepmoM3+ew7Jq0Dz8LlfXFxc/Ok8Pf0HcLxyU2WIgC4AAAAASUVORK5CYII='},
        varesco_b12={width=169,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAKkAAAAgCAYAAABpalg/AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAT/SURBVHhe7ZwNceMwEIULoARKoARKoAgOQRkcg6NQCsVwJI5FwfTue87Kozj6WclKqtz4m/FEXj09b6RNnDpOHw4ODg4ObsXX19fPvxno+22yKmif2N7YPtj+mMWKYtYnzZMNq4LWlZ90bDruo4VctPhb+IKtju1qedRA/oj+B9u7xp0czlHcNh3zxYbOiyWaRE/EZFmQvUh3GuHHxlQnyJtf0PHYVCCt/ilSOh6vkkcOZFqHj9MIPx7vb6d3cujWK7Z5Urbg8YuH7GJ684t1tN0F0uO/JaejPTyPLXRrHd5PynZK3tPQMznEn9m0AEMwr+RievPb6kqeMb3+MSUd+0PziCG+ex1y3lPROjmE9cr9PCnGYZN9sZje/FK6nGfMHv9ATUdsWB4Bwo+n3n2kvKejdXIUs+7h4P1hh1nx5pfTES8WyF5/4dERH5JHwPx2k/KejpbJYf+HdV2TVzvcgje/ii5bIIP8b5aHYP/Nunaz9Z6SxsmpnuY1hk2XQNbLTGpbrPoujObThi2wv7s4BP3JAhnh79UJ+nflISxchDGfbCrmiysoxJ8U51Fr8mbheSFJ1+Sw+3qK5tGTNnkWTYrJS6wT682vpAuguSiQEf5eXQDNnjyqZzN5mfz/oGFyipc56He/IkvHFPT/MmlLftXiCKB9tmFD/L26LWh78ihe9qN//nfGVhomJ3uqp++Pydx4/WgPLw6BfimQEf5eXQr0TXlYKEms+6/wTA7N4uUOdNXT/BbGFE/7JrtacQjG6Drjbn+vLgdjXHnQbFoHby7Bf1qck/NyimRp/v5XY05D03Ds5Q8vT36ipCvBuOzp0+t/qzxo1uZs/fggvLkE/2kpPRHv5CxGjTDMVfie/ERJ14vX/1Z50GxaB28ucf5TUnoivZPjgWFHkToJ/jSPIt3inRyY+nRPn24T1GWfJhr8b5IHzaZ1KOUSE/ynpfREosm56z+cpONB9xw0FUiLv8munoeFkqArXn7K5Rb7T0kucREnT/tuL0EFHc2mAmn1Fx4dzT15lObt7Nu6LfQnc4v9p4QEdT9nkjh52nd7MT/WsesukB5/r47d3jxq6/Bu0gvoS+YW+08JCZZemfGk3u3XorFOEHIVSI+/VycINefBrmcd9DOdi5/oEJuzSMlh+VkB29nNBnoSbE2vSvazBR1AM90NJrEuQLhaID3+Xl2AcFMegv3qOgh0Wt9XHovfam39bw451P4izKInZTYL7N/rrXrJRaCrWCA9/l5dDF3uPASh6rtpC7E/u8plffOivdxNZd0LhIdoVujvLlK4uLTEge7qpmcR67bQnS2QHn+vbgvdrjwCxIpnwRZif7UtvGV98xilWSHYXaRmcQZhTabrdNMCnlqgq9/vmQJJskB6/L26FEiqeQQIZ4u6leDPo+4zTaJjjdScQbyrSDHL3pNI3/Q/xIuJdTmQXSx6j79XlwNZMY8YuqQd8YvdxZ9msVZGas4g1lykNknJogmof9AEDf9J85ZYVwLpWYH0+Ht1JZBm80hBv+eKSZbgz+P3vJMSfLZ+F+j1WaJYoDFop/rnECliXQ3ka4H0+Ht1NZAn88hhev33lOaPYrG/2hbecr3PpIIOPQFdAkr+6xVi+k55uVxhQ5ph/Lf/mx0LXxDrPDBkKZAef6/OA0Mu8vCAfrk/lS25FkKe1i/deosfXTrmbf+6Pzg4ODjo4uHhHx0JHOY9OmuWAAAAAElFTkSuQmCC'},
        varesco_b13={width=288,height=32,data='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'},
        varesco_b05={width=346,height=33,data='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'},
        varesco_b07={width=295,height=42,data='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'},
        varesco_b04={width=335,height=32,data='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'},
        varesco_b03={width=347,height=34,data='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'},
        varesco_b09={width=221,height=32,data='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'},
        varesco_b10={width=389,height=32,data='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'},
        varesco_b02={width=342,height=44,data='iVBORw0KGgoAAAANSUhEUgAAAVYAAAAsCAYAAAA+YZCQAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAxASURBVHhe7Z2Ntds2DIUzQBfIAl0gC2SCTpANukFWyAqZoUt0iwyT9F7qWqVEAgQlS35J8J3jY4m4AEiJgvVjv/cuSZIkSZIkSZIkSZJX8/3797/x+vZDcF2mJEmSZBYWUdXTDWj/LMk1PBLj/S81PRXGVfz1U+KRswds/0j2+KT5F81/qClENP4Mcg/BHOr7n3Kfhr4KFwL6T3I1kTTE7BjkZvGBGsbU+inYL8Uz9zN56CzO+j8D5Zme4xEYU7F/qOnNwj46lPlzBPl3keQa6smF5acWV8ZT6M0krXPugW1TWNU2NfGi8WeQ+zTMh7fpiQG/T0uEGNB/lauJpNNExrAoTS4prFj8Y2lx6c4bxHgvexfYv0l6KUrHfE8troylmAU1v1nUTYtLCit4+ofZCiepkhSw/pTiijibwsA8MjU5a2BrCivBcnjiRePPIPfDsE8KFQL6r3INI1cTyQ7jjUESi0sKK+GymrtYfUb7F0m6wH7JFdwepSsg51OKK+K8V6wVmW4FaVnceeXzeJnbdOmlySWFVZJrwGCbieltgAjwbyYt88jsHgywdQsrwXpo4kXjzyD3UyB3+L6OXKZAfPeyXbJTWGOQ2eKywopVHrzrgwmDzZyB/k2crRKlXEHuU8UV/t1bSDLfCvqyXrESrJ/6YD4CcyrGBrTfc491DzeKJFPAr3smwDySmDkJbGZhJWgbTrxo/Bnk/gw+KqQJ+jh1f/UB/Nz7rJI9g2YMare4rLASrG8O4D2wf5G0wHWZujCepJejlBuQ/1BxhZ85byS5FY1jBeu3F1bCvHjd+60AJlG+BtimJhj05oStBzPI6RZWgnZ34kXjzyD30yD/8GwImqn7qw/gtykgeyQ7TW8MMllcWlgJ+yRzF9jfS/dmzlaJ0jagH1PFFXr3w1iy20DKD0vm/0EfX1JYXwIHq853gT1UXKEbnQU8rbAS2MyJF40/g9yfAvrgblPY3W1pAT+3KEj2FPZjULPFHYU1dNaK99G961sPYuXsgr6Giit0wyscSW+D21upV9CWhbUGmtOFoN6oXk7YQoWVwN6deNH4M8jdoux4vPN+3194jc6e3DPLkb8HfMuZWQ9JLE6NQc0W5oFB2yLpI1mIQJ9HxXc4NyDb9Dfi46EwJog/ujoL3TaS/BaQrvttDfQ1C+se6LrFFe2hs6t6o3o5YQsXVgJNM/Gi8WeQu8Vmx2N981WXPbRJ2gCbe6k6Av7mh6AkFqfGoGaLWwor5B8Xr8MMD2BqFukCtsOlhZVoP/ROIML34uVSUFMD4nULH8coyYZ67JbGo86nJosP0PKbDl/wWj88sfwvY2DR++AZ9t0Cmj/x+tyLgTbm/ooXT0Lakxk0hgorYRC5FbAevmRlHrm5OWGbKqwPoF2fiEfjzyB3i+aAHPVdsgb4uWdVBBrzzAw282xYEotTY1CTxS2FlaDPh2430E8hXCC9vbAS5NkUV6yHiyqRW0FNDYj5JgsrdJEr4u43Yqx+sV2SBphZyMPj6cZCY7h4EehLccV7uKgS5ikJgZcTtnpnzfatbNxo/BnkbvHMwupuV9j5KWlqYDPvs0pi8UsUVri48RzMPtZQt8gXsI0OzacHChMCuUpxxftUUSVKV1BTA/e3JBs4Rkk21GO3NB51PjWdAvGa4hrpew3aP0sSphsLjVPFi1id9WAepXRz1p082DeevofizyB3i81BifUztwJMPwL7J7xGZ7XdSyPZLE6NQc0WtxVWgr5NzU/oh79auwp1IYy3TzyUrqCmBsT+2Qtrc1xF+v6A/ZF5il6sw8FmYR6ldHPWnTzaN/iZT37r+DPI3aIUDryzGB1+eAXT8Cea8OUHx+iMpftdWdksTo1BzRa3Fla4TZ21YizmA7+rURcuR+kKamrAdvipCytBzP3tylBhRdPRK50mVoGDk/1SmEcp3Zx1J6/oWx1/Brk/C6vwDR++SOr2B2M88uuoWTZjUJvFrYWVcD8rhAt07jc0rkbduBylK6ipgcebJBusbcl2ScLbu6bOp6bTIObm6iPSd3Kk/w/2sQpozMIaQO6nQX7vNoB7f2e3bbyz8m4OmU/Tiy+TxSsKa+g+JHQvO1sl6sblKF1BTQ3YFocLa43MDVZ8IkkX+PH2R31F5T6HKAFFpO9YdueKYmxOJNDGb+/wIRd/1dWOi43FuwMD4hV6SAUdLx/Nqs88SjnMKdlIx687TN9vquPPIPfTIL/5e/7ReGCvt+Ho11nNfVa1n6Y3Bpksbi+sBP0cPQh86dkqUVe6BPZxATrOG/dqR+kKampAnDdZWEEzfxDL+6HHqo/0nf1ScwNsx+bIIGhJzuBq6gL745sCdxZW5nIfsPSo488g91Mgt/kdUyKZRz1hRmdkzWRU+ymsMchs8ZLCCnc3Nsby0rNVoq5Y8IxodDbF+c978+HtqKYGxPppCivavA+S9ewy0ncse0Xa/I6sCwerAA275N3LVLSvBxr1am5gHslmcg51WJwqrnX8GeR+COT8hpd5pkogcw+MWZCvmcQyHWI0Bsks3mRhleylqCsWZbtxu3P7q20FbaWoKs5vVViJbA11nkjfI5pp2AnFadgHxvrmaz5cl6lAvUwNzCNZOGdUh9Vwca39ZpD7NMgX+iqPN9Yj9MYp0zSRMUhqkYXVQF2xWLcbljdzXMvr2RSWs7CKOk+k7xHNNOyE4jT0AqOtFFe+q2mF+uLYgXkkC+eM6giaQsV17xdF7l0Qkz+1826XDC8n2C9pn4ZCr6i5y9kxSGORhdVAXbHYbDeslznOF5fVXKCWDhaSFdTUwP0vyQqaza8AQt89lmRugP6tFtbX3QqoQXv33hT1cm1gHsnCOaO6B2geFteeXwS5W5Qdr+UG9Wm974Plck9MqwXqLmAmx6kxUOOw6UcNbYukj2SHgPsvVVgJ2rjdm4OdWjpYSFbAvvS+o7yJDa35AM06lmRugP6tFlavzlz38CoK9XJtYB7JwjmjuhqY3OJq+Y2Qu0XZ8YjtffI1lMAAi+5BcRRuP6UoqNni7Bg8srAaqCsW5nbbQ+3i0keygrePacOrnDjh/dBfA5O5gXq8dc8AF4XJ1YX1/q9bSRaCerk21MmjOaO6PTCbxdXz85C7RdnxeJ/660olMPDGeQbE3dwbVbPFqTFo1SILq4G6YnFVYR3+oZ8I1rGEdveqccdj3nl0t4NsDTyeJGFfhoWVWLoI+1gFdkL2hq6Dg9c55pEsnDOq6wFJt7iO/CzkbrHueMR3fwpaIxf6TJ0lzqAUBTVZnBqDVi3MAkHbIukj2SHgnoVVSFbAqnnfdAbrWEJ76LvvooxRyxbd7SBbA/JPF1Y0udvPo7sd2AnZG7oODtYgCPNIFs4Z1VlA1hTXiF8PuVusOx7L4TM+uYxik81lSA1ti6QPxrt+RUpNFleOwSwQtC2SPpIdAu5Pjw23Tcyj8+mBwliY220PtYtLH8lW0G/z2IpijZ1zTpIIZYxatuhuB9kaODZJzJrU6zv9ZJ6iF+t08aqhXq4NzCNZOGdU5wHpprhG/fbI3WKz45Ej9Ikt7XASQmN+kR1m9+wDvus/GFSTxeExEK1amAWCtkXSR7JDwD0Lq5BsBU3us4ga6LpXMN7YYYv++b0yRi1bdLeDbA3Ifaiwkol+r3RjsROyN1jJLaiXawPzSBbOGdWNgHydRDN+NfR1aHY88gwLk3TuzxZhj/zzQfMAgW29z6omi8NjIFq1MAsEbYukj2SHgHsWViHZBjQPiyvs/HHCVHF6AHvkw7mMUcsW3e0gWwPyHi6sBOZr/9C1l7yH1xnmkSycM6qLAJcyiWb9HixZTawdzx20/3cS/AUT76mWy3stm9C/BHOAxvyUZT7JLhsDWSwmZoGgbZH0kewQcM/CKiRrgInHBZ9s11d13L+cU+UJPse4WLawvQRxgKyZPzvKGLVsYc3NLsh1qrA+gOb4v2ZJkiTxQOGYvhWQJEmSGKB+mmfCKKzdv/ubJEmSGKB2uvdgYVsfjCZJkvzWoCaWhzN48RnGR7xv/moZ1vmvpiP/nsf9i21JkiS/DaiJ7oOuCCiqeX81SZLkAeri6cIKwt9YSJIk+eVhUVxq4zFwtpoPrZIkSWpQGw8X1iyqSZIkHVAfpwurHmSZf7MiSZLkt4dP9PH6hBd/FWX+Ogkv/gIr76cmSZIkSZIkyS/Au3f/Ad/k8396nXlfAAAAAElFTkSuQmCC'},
        varesco_b14={width=192,height=32,data='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'},
        varesco_b00={width=224,height=32,data='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'},
        varesco_b01={width=196,height=32,data='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'},
        varesco_b06={width=333,height=34,data='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'},
        varesco_b11={width=223,height=32,data='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'},
        kindly_b01={width=83,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAFMAAAAgCAYAAABuBERvAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAASbSURBVGhD7ZmBUdwwEEUpgAZogAZogAqogA7ogBZogRpoIl2kGMj7e1+KZa9lOafJJDO8Gc9Ju1/rtSzJsu/mm2/+D76+vm4/Pz/f+f3i9wfHvV0brP2w9tXmQ9DecTxzvHP8VPuC6hwf8lO9dZNdpEH7xJHFUpw3io+WD0GbOfkher00+w22O7sbFNSSgPqLXSmKk7RRci+ublAbN9+wbEdZF37P8WRTA3ad58lNU/DPy08OC9TrjyoL6m+WVLDd270mvVtFz+8Pfh51Do6fdsuvEbRBdksqmJczIkYOv68+mpG0Br/Os8kR+7T8AhwxKl2OqV4IwYKiXYP92ZIG7LrDSjQuhN+HaAC2p+D7iAALZLNbN1wd2+3ANejfHaqiGBxT8gtKI36bjhTYmrVTQexqyIKrrd2xdlFPb0QG2ubCqZdprItVR+5eaA/Fccip+QUYyxR/4djcaWzNiLM5xZKK2hZ7KZ+geXjQXg/FmKoqXyTnUVuHnJpfIKM8KhNwM+qw1YcL5ej4Dg+WBujfFNPl4SmpdhFggV0P+PZGT5n66Rq3xCGn5hfg0IgsAbPOrNOXal1PMtA2o1htfRzdhACdlpnmhgjZQuAbv4Z2dbQJm3vEOWblV5FAAV3udibldPtRwN/sOW0r07NCXefc3fqsQXt03makUE/X9UI5t8tX51ehUdwdlR2rofgE5d19l1hqhc0Z+3c3YeC8zT5XediVYtm0/CqcuDzJ0/2jErN0Wmeiy9ecHdB3n7LyWyptd8rir09hmzacza/i9tERLl6FwwY2pXA+7e9iVtgUUN+8rRzlhj/WTIojT/o66lxPIc5wfhVrpuGwgU2nIeGhve0SNIfbJTTN3tDm06zzq9g/DYcNbDoNyZ5aA0dwZzevkxfPedb5VeyfhsMGNp2GZJsn6bWdmXWkuHjPs86vYv80HDawaRiSjC9Abl65pjNpu/tFy5Jh9vKrWDcNhw0GOkFfaQ73cwNxUmjX/dY6K78K4sPXKEsPO55YzZsI9c2HkwK+7jfGJWivGZnxPu9QDbPyqxwlKr+lI53Z7DOp9/alm42xbLoIjtlrprY52fIxJb8Kju6HAfzLTftRxzebXUzpu7RAG1OQYvrxAltNeOC8Q52NrhltmKbkV8E4/Fajss0pimVpgOn24jkPseqNobw7HYXOq8PVLuhqh1Kdkl8F+9GXoNpBlI9GwGZq0OZwM52hcznEyA2Xf7hj0NcpPyO/BvtTaFTvpJPusVnoaXP2o2uwTJbq7nQUyks65WpTl2XsGfk14NhdN/HVtYFqb43ZfsYHXH80lYh35uPFmdkTWD4lv4a9ZJWYJRW7MnY/W+nE1gyjnNw8oL67hcO3nD1DH3otD2bk16CErFuSrYGbqY4tH/IGyal/EtFu/unMzlvAt+749HNiAX8zqjBdnd8GdNoG6H8RTfveSKsXRllP2nRTvARd9wILiu0mDbjSC8aWTjedb0efvqdLf1H0QZfm99chl/jDa32R1PXdUH/+708dwK8OijWRX23EuxeGTOerU5jy7tuQkE8axY4GhvpQft988y9xc/ML94+tDW2BbUAAAAAASUVORK5CYII='},
        kindly_b00={width=80,height=32,data='iVBORw0KGgoAAAANSUhEUgAAAFAAAAAgCAYAAACFM/9sAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAS/SURBVGhD7ZqLbdw4FEVdgBtwA2kgDbiCVOAO0kFa2BZcg5twFynG2XOfLglS/I4yATYLH4AQ9X6i+B9qHj755O/j4+PjhfTzlyH/ncuj1Uuw/0Z6PbwPFI/0j3Q2W4Lbo3yOCBHjjfTF6i7oVdaA/Dtp+DzFIr3ZPN7TqusQJArM9cX3UZFc38NgAmZ64XfZC8UiVRUpHPOr3YbI//Bo6DZmsvczc1l8bXyQ506SQHa9EnH+5iAK/Mw1t46YBUd9rrxoea4vFjUkmx6oH22jMkQ+oZg2yyD+emgPvWL7NuC+6gBn/Ynt0VZBUA0RdfsfDtRg0wb5Si//MOSFyI96UAabbiWiigpB//0ch/tXm2VkQ9I08UTKDVmCPHcA8sN3RNc00BY4qgLjIY7VgL55YcmsS8N+WXEl2D9FoAJkeS47g+7NZhnLd54fvUsxfN8gf9ncjBxJqwpsgiNTy8dLcf1i022Sbwmy1EOqqUGc7RGl3hoNofwIbNLUMqvApjxb4KjhsqrAn2FsEKW555nUvOwu+FW9kHuNhtQozWQfRgZ97BqUR6VyDMEu5kLFtqhBOtncDL6at8L5CDUkT7LY/yBF4bkOh90KxYmARuWQDFW1gCRsFshO9s7vTB9q6D9Wgakyhg+AvAXBTouOCt28qGOosMthjU3Vs+VLUoPk1bXEZkGydX5nBDQ7jDMR+FbwS5WgihyuUpArUDcqPJdm6CDPm17ys21DouzZUSmO3WCzABs14nTqKcFWc/20p0bgK9h/Cg+P1Y5smrz1sk3LR8ACi2eUPXu7AnWP3StpuOc8M4qbcOjbsf8UPdy23eElsGnmEWTT4YU+b5HkL3tS80tG2Cyw6CaI2yxMJQ59O/afwsOvVuB03klxxcrWZoFFd8Whb2dVcIFN9BSywy2D4kTAglVs9P+LCtxZxWKu0vW4bblYgfkn1F9bgfafwsvF6kp2WIEiAhasKgXKRWS2C/hvViB+3U3rGZsvK5BKqH5dWDwkNYwgP1wl1RA2Cyy+Kw7dooKpACStbrnFBffTn0ECv+pYyOIRzzbTc5ebaZsGKqfFDSq/zQLdW3UXzvEzKJphoYKSnshu/Y5VDIcLuB9uB9DlgwflLe6CvjqiQrS9QOneqiHYTLctJef4AUJV0j3IvUoQd1Ux6nnToS6wq47JEG0vUNxPN8VC8Z1dco4fIF8Ozx0cLoPoLnGhOgXmJYYNjq46UtusnDgocX4Kdnk7lZHQ+st0A4PVlyFu9wDT6oZzObjfOYNUj95qbOK1J9J6qPW/Q/dbwe/Gxr85kRbIu/OWnmeTzMi2IBbMDTtRLa6BhIfuGjy4bRWDemv706NXGQl03SHX80G2dbqC3XK427QF5+2VqESFc4gh2GyfhCTw6W8XDPrRZrrpIdgOhzG681njsB7QNR+sMuhvnvAJuKy8hGzttgRbbZm6U0ICm25vQd79uI58q8cimq3wzUezilGheiyDdcBnWYnYxFG9XYbIJhwK8K16Uwm60crdPEvvZl0G2fLPA4EeRNJ3hGrjzL2+rulgUsGXLzgCX20Zzn/tiO/NpO6CMQLX+MzgGPoFtfprR/67hvxm9pjoaD/H5nL5nT/55E/w8PAv+DyTfMwCFGMAAAAASUVORK5CYII='},
        kindly_b02={width=109,height=32,data='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'},
        title_v05={width=262,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAQYAAAAcCAYAAACDDxF1AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAATgSURBVHhe7dFBkts4EATA+f+ndy/JOqijAw2YIytk5s2FKlAY/zwej8fj8XjM/Xcz134tzwzxNvMQj5mF+PGh/De11MbMjrmmp3cb134tzwzxNvMQj5mF+PGh/De11MbMjrmmp3cb134tzwzxNvMQj5mF+OP4eSH+53h+S23M7Jhrenq3ce3X8swQbzMP8ZhZiD+Onxfif47nt9TGzI655px7Qvw1PGtJ/WP+Hj4f4o/j54X463luiFtqIW6phfh9fDfEX8OzltQ/5u/h8yH+OH5eiL+e54a4pRbillqI38d3Q7zNfMxse3cxX1JfUv+1v4d4zCzEt3P9mNlypxbibeYfx88LceG4cNxSC/H7+G6It5mPmW3vLuZL6kvqv/b3EI+Zhfh2rh8zW+7UQrzN/OP4eSEuHBeOW2ohfh/fDfE28zGz7d3FvHAc4jGzEIc4xIXjEI+ZhTjELbUl9TGz7e+Lt5l/HD8vxIXjwnFLLcTv47sh3mY+Zra9u5gXjkM8ZhbiEIe4cBziMbMQh7iltqQ+Zrb9ffE284/j54W4cFw4bqmF+H18N8RL6iFuqYX49u/7Z4jHzEIc4hAXjkM8ZhbiELfUCschbqmFOMQhvo1rQzxmFuIxsxDflnfUQvw+vhviJfUQt9RCfPv3/TPEY2YhDnGIC8chHjMLcYhbaoXjELfUQhziEN/GtSEeMwvxmFmIb8s7aiF+H98N8ZL6Mdfc9n1x4bhwXDhuqYU4xMfvupi11FpqIV7eu+KaEId4SX2b+ZhZiMfMQnxbPmU2ZnbOPSFeUj/mmtu+Ly4cF44Lxy21EIf4+F0Xs5ZaSy3Ey3tXXBPiEC+pbzMfMwvxmFmIb8unzMbMzrknxEvqY2aF4xAvqYe4cFw4Lhy31EIc4uN3Xcxaai21EC/vfWXWUgvxkvo28zGzEI+Zhbj9/Y4LxyEeMxszO+eeEC+pj5kVjkO8pB7iwnHhuHDcUgtxiI/fdTFrqbXUQry895VZSy3ES+rbzMfMQjxmFuL29zsuHId4zGzM7Jx7QrykHuJt5iFeUg/xmFmIt+9VC/Gv/b4psxD/8b2vXBPiwnGIl9RDfMw1IQ5xiAvHhePCcYhbasfvNQ/xnF2Il9RDvM08xEvqIR4zC/H2vWoh/rXfN2UW4j++95VrQlw4DvGSeoiPuSbEIQ5x4bhwXDgOcUvt+L3mIZ6zC/GSeohbaiF+2/dfmYX4r7/rYhbiMbMQ3/a+izjEheMQL6mH+JhrQhziEBeOQ9xSC3FL7fi95iGeswvxknqIW2ohftv3X5mF+K+/62IW4jGzEN/2vos4xIXjEC+ph/iYa0Ic4hAXjkPcUgtxS+34veYhnrML8TbzMbPj76uHePw71AvHIW6phfj4XRezY65ZUh8za6mFuHC8zfw2rg3xNvOWWuE4xCHeZn7OPSHeZj5mdvx99RCPf4d64TjELbUQH7/rYnbMNUvqY2YttRAXjreZ38a1Id5m3lIrHIc4xNvMz7knxNvMx8yOv68e4vHvUC8ch7ilFuLjd13MjrlmSX3MrKUW4sLxNvPbuDbE28xbaoXjEId4m/k594R4m/mY2fH31UM8/h3qheMQt9RCfPyui9kx1yypj5m11EJcON5mfhvXhnibeUutcBziEG8zfzwej8fj8dj28/M/9r5ff6xApwwAAAAASUVORK5CYII='},
        rainbow={width=138,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAIoAAAAcCAYAAAC+uCc6AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAK+SURBVGhD7dBBbuQwDEXB3P/SM5vy10IgaNqGg6C7dnmiaHV+vr6+vp737yHWvcZnQ36c9SF/Hr//Nute47MhP876kD+P33+bda/x2ZAfZ33In8fvv8261/hsyI+zPuTP4/eHPOZ6yH+enxPy5/H7Qx5zPeQ/z88J+fP4/SGPuR5yyGOubxyH/Np3nmZ9ydjv8Y6Qx1wPOeQx1zeOQ37tO0+zvmTs93jHbdaVjI25vnEc8mvfOcglYy3jJWMbxyGPuR7yot9mXcnYmOsbxyG/9p2DXDLWMl4ytnEc8pjrIS/6bdY9zvqQx71jPOR2n1wytnEccslYyOM9FddDXvTbrHuc9SE//o8zHnK7Ty4Z2zgOuWQs5PGeiushL3rIJWMhj7k+5nr5Dn+G3DIecvtOYyVjIY/faSzk8Z6K6yEvesglYyGPuT7mevkOf4bcMh5y+05jJWMhj99pLOTxnorrIS96yCVjIY+5PuZ6+Q5/htwyHnL7TmMlYyGP32ks5NN7HIcccsiLHnLJWMhjro+5Xr7DnyG3jIfcvtNYyVjI43caC/n0Hschhxzyood8mmshbxyH3DIe8rh3jId8ed/BtZDHe42FfHqP45BDDnnRQz7NtZA3jkNuGQ953DvGQ7687+BayOO9xkI+vcdxyCGHvOghn+ZayBvHIbeMhzzuHeMhX953cC3k8V5jIZ/e4zjkkENe9JBPcy3kjeOQW8ZDHveO8ZAv7zu4FvJ4r7GQT+9xHHLIIS96yJdZE/LG8Zjr5Xf8GXLLeMiX33mwpmW8ZKxl/DbrFj3ky6wJeeN4zPXyO/4MuWU85MvvPFjTMl4y1jJ+m3WLHvJl1oS8cTzmevkdf4bcMh7y5XcerGkZLxlrGb/NukUP+TJrQt44HnO9/I4/Q24ZD/nyOw/WtIyXjLWM32bd19fX12N+fv4D7uAs7aIGXtcAAAAASUVORK5CYII='},
        silver={width=90,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAFoAAAAcCAYAAADhqahzAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAGiSURBVGhD7dBBboRADEXBuf+lk03xF2MhbGgRKVDL5zYNfF6vZ/g5yXrZl3f7Y/kPY9bfH93lP4xZf390l/8wZv390Xt8d8jLeXzIz+G7Q17O40N+Dt8d8mkeE/Kf/2jXtllrf8/GuDIP+TSPCXn5PVOubbPW/p6N8THnDzleGIe82+/i2jZr472N9X3OHXK8MA75/dHfnDvkeGEc8rh3WQt5/FzHQi59Y1wYH3+Hc4ccL4xDHvcuayGPn+tYyKVvjAvj8Xfs8ryQl/UuayGXPuUxl9/vMveGvKx3WQu59CmPufx+l7k35GW9y1rIpR+xVhiHfB/3hrysd1kLufQj1grjkO/j3pDH/ZtxyCGHXBiHPGY95Pu4N+Rx/2YccsghF8Yhj1kP+T7uDXncvxmHHHLIhXHIuxwLefyc5dwb8uUXNg455JAL45B3ORby+Dm77I9ZL4xDPv3Cjoc8Zr3N2rL7xy+wsV4Yh3z6hR0Pecx6m7Vl949fYGO9MA759As7HvKY9TZry+4fv8DGemEc8ukXdjzkMett1pbd/3r9B5/PL5VzNHWy6yc2AAAAAElFTkSuQmCC'},
        golden={width=106,height=28,data='iVBORw0KGgoAAAANSUhEUgAAAGoAAAAcCAYAAACJWipLAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAIZSURBVGhD7c5BjuMwDATA/P/Tu5dS+0AQMpNMnACuY7NJ6XG73T7h35s49zbOhnjMeoh/j/+/zLm3cTbEY9ZD/Hv8/2XOvY2zIR6zHuLf4/8vc+5tnA3xmPUQfz//DfHX8b0Qj1kP8ffz3xB/Hd8L8Zj1EH8//w3xn/FMS60wDnFhfJq1wvg0a+O9xXpPL8R/xjMttcI4xIXxadYK49OsjfcW6z29EG+pt9QK45ZaYRziwvg0a4XxadbGe4v1nl6It9RbaoVxS60wDnFhfJq1wvg0a+O9xXpPL8Rb6i218X21EI/zjlqIL7uzqIf4IA/xlnpLbXxfLcTjvKMW4svuLOohPshDPGY9xOP7aiH++P0pZ8b/WdRDfJCHeMx6iMf31UL88ftTzoz/s6iH+CAP8Zj1EI/vq4X44/d3rBXGId5SD/FBHuIx6yEe31cL8cfv71grjEO8pR7igzzEY9ZDPL6vFuLL7k9ZD/GWeogP8hCPWQ/x+L5aiC+7P2U9xFvqIT7IQzxmPcTj+2ohvux+Ry3E4zuLeogP8hCPWQ/x+L5aiC+731EL8fjOoh7int6Y9S31llphHOKn/7s4UxifZq395456iHt6Y9a31FtqhXGIn/7v4kxhfJq19p876iHu6Y1Z31JvqRXGIX76v4szhfFp1tp/7qiHuKc3Zn1LvaVWGIf46f8uzhTGp1lr/7mjHuLb7fZGj8d/InGwMdQW1FoAAAAASUVORK5CYII='}
    }
    local mutationSprites={}
    do
        local asset=getcustomasset or getsynasset
        if type(asset)=='function' and type(writefile)=='function' then
            local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            local values={}
            for i=1,#alphabet do values[alphabet:sub(i,i)]=i-1 end
            local function decode(value)
                local out,buffer,bits={},0,0
                for i=1,#value do
                    local digit=values[value:sub(i,i)]
                    if digit then
                        buffer=buffer*64+digit;bits+=6
                        if bits>=8 then
                            bits-=8;out[#out+1]=string.char(math.floor(buffer/2^bits)%256);buffer=buffer%2^bits
                        end
                    end
                end
                return table.concat(out)
            end
            D.decodeAsset=decode
            for key,spec in pairs(mutationSpriteData) do
                local ok,uri=pcall(function()
                    local filename='tenshi_minecraft_'..key..'_v1.png'
                    writefile(filename,decode(spec.data))
                    return asset(filename)
                end)
                if ok and type(uri)=='string' then mutationSprites[key]={image=uri,width=spec.width,height=spec.height} end
            end
        end
    end
    local function styleRaisedButton(button)
        if button:FindFirstChild('StuddedSurface') then return end
        local corner=button:FindFirstChildOfClass('UICorner')
        if corner then corner.CornerRadius=UDim.new(0,3) end
        button.ClipsDescendants=true
        local spec=mutationSprites.studs_v05
        local texture=D.make('ImageLabel',{Name='StuddedSurface',Image=spec and spec.image or '',Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
            ImageTransparency=0.65,ImageColor3=button.BackgroundColor3,ScaleType=Enum.ScaleType.Tile,TileSize=UDim2.fromOffset(256,256),Active=false,ZIndex=button.ZIndex},button)
        local function tint() texture.ImageColor3=button.BackgroundColor3 end
        button:GetPropertyChangedSignal('BackgroundColor3'):Connect(tint)
        D.make('UIStroke',{Color=Color3.fromRGB(5,12,24),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},button)
        D.make('UIGradient',{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(165,175,195)),Rotation=90},button)
        D.make('Frame',{Position=UDim2.fromOffset(3,2),Size=UDim2.new(1,-6,0,1),BackgroundColor3=Color3.new(1,1,1),BackgroundTransparency=0.55,BorderSizePixel=0,Active=false,ZIndex=button.ZIndex+1},button)
        D.make('Frame',{Position=UDim2.new(0,3,1,-3),Size=UDim2.new(1,-6,0,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=0.25,BorderSizePixel=0,Active=false,ZIndex=button.ZIndex+1},button)
        local caption=D.make('TextLabel',{Name='RaisedCaption',Text=button.Text,RichText=button.RichText,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
            TextColor3=button.TextColor3,TextSize=button.TextSize,Font=button.Font,TextScaled=button.TextScaled,TextWrapped=false,
            TextTransparency=0,TextStrokeColor3=Color3.fromRGB(5,10,20),TextStrokeTransparency=0.35,Active=false,ZIndex=button.ZIndex+5},button)
        local function sync()
            local glyph=button:FindFirstChild('CustomButtonFont')
            caption.Text=button.Text;caption.TextColor3=button.TextColor3
            caption.TextTransparency=glyph and glyph.ImageTransparency==0 and 1 or 0
            if button.TextTransparency~=1 then button.TextTransparency=1 end
        end
        local glyph=button:FindFirstChild('CustomButtonFont')
        if glyph then glyph:GetPropertyChangedSignal('ImageTransparency'):Connect(sync) end
        sync()
        button:GetPropertyChangedSignal('Text'):Connect(sync)
        button:GetPropertyChangedSignal('TextTransparency'):Connect(sync)
        button:GetPropertyChangedSignal('TextColor3'):Connect(sync)
        for _,child in ipairs(button:GetDescendants()) do
            if child:IsA('GuiObject') and child~=texture and child~=caption and child.Name~='StuddedSurface' then child.ZIndex=math.max(child.ZIndex,button.ZIndex+3) end
        end
    end

    -- Keep the title and Discord header strip solid black; no gray texture or gradient.
    local buttonFontLookup={
        ["FULL"]='kindly_full',
        ["JOINING..."]='varesco_b12',
        ["MATCHMAKING..."]='varesco_b13',
        ["MIN RARITY: Eternal"]='varesco_b05',
        ["MIN RARITY: Any"]='varesco_b07',
        ["MIN RARITY: Secret"]='varesco_b04',
        ["MIN RARITY: Cosmic"]='varesco_b03',
        ["MIN RARITY: Mythic"]='varesco_b02',
        ["TRY AGAIN"]='varesco_b14',
        ["ALL SERVERS"]='varesco_b00',
        ["MY SERVER"]='varesco_b01',
        ["MIN RARITY: Divine"]='varesco_b06',
        ["SEARCHING..."]='varesco_b11',
        ["HERE"]='kindly_b01',
        ["JOIN"]='kindly_b00',
        ["TAKEN"]='kindly_b02',
    }
    local function applyButtonFont(button)
        local glyph=D.make('ImageLabel',{Name='CustomButtonFont',Image='',ImageTransparency=1,BackgroundTransparency=1,ImageColor3=Color3.new(1,1,1),AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.new(1,-14,0,20),ScaleType=Enum.ScaleType.Fit,Active=false},button)
        local function ready()
            local key=buttonFontLookup[button.Text]
            local spec=key and mutationSprites[key]
            if spec and glyph.Image==spec.image and glyph.IsLoaded then
                button.TextTransparency=1;glyph.ImageTransparency=0
            end
        end
        local function refreshFont()
            button.TextTransparency=0;glyph.ImageTransparency=1
            local key=buttonFontLookup[button.Text]
            local spec=key and mutationSprites[key]
            if not spec then glyph.Image='';return end
            glyph.Image=spec.image
            ready()
        end
        button:GetPropertyChangedSignal('Text'):Connect(refreshFont)
        glyph:GetPropertyChangedSignal('IsLoaded'):Connect(ready)
        refreshFont()
    end
    -- Bottom options use crisp native rounded text instead of bitmap captions.
    for _,button in ipairs({scope,myScope,rarity,refreshButton}) do styleRaisedButton(button) end
    for _,button in ipairs({scope,myScope,rarity}) do
        button.Font=Enum.Font.FredokaOne
        local caption=button:FindFirstChild('RaisedCaption')
        if caption then
            caption.Font=Enum.Font.FredokaOne;caption.TextScaled=true;caption.TextSize=20
            caption.TextStrokeTransparency=1
            caption.Position=UDim2.fromOffset(6,2);caption.Size=UDim2.new(1,-12,1,-4)
            D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=20},caption)
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=2},caption)
        end
    end
    do
    -- Header title and subtitle styling.
    heading.Text='MARVIN'
    heading.AnchorPoint=Vector2.new(0.5,0)
    heading.Position=UDim2.new(0.5,-10,0,2);heading.Size=UDim2.new(1,-112,0,24)
    heading.TextXAlignment=Enum.TextXAlignment.Center
    heading.Font=Enum.Font.Arcade;heading.TextTransparency=0
    discordSubtitle.AnchorPoint=Vector2.new(0,0)
    discordSubtitle.Position=UDim2.fromOffset(100,27);discordSubtitle.Size=UDim2.new(1,-112,0,14)
    discordSubtitle.TextXAlignment=Enum.TextXAlignment.Left
    do
        local service=game:GetService('TextService')
        heading.Font=discordSubtitle.Font
        local available=(panel.Size.X.Offset>0 and panel.Size.X.Offset or 402)-100
        local fontSize=22
        local textWidth
        repeat
            textWidth=math.ceil(service:GetTextSize(heading.Text,fontSize,discordSubtitle.Font,Vector2.new(1000,1000)).X)+4
            if textWidth<=available or fontSize<=14 then break end
            fontSize-=1
        until false
        heading.AnchorPoint=Vector2.new(0.5,0);heading.Position=UDim2.new(0.5,0,0,1);heading.Size=UDim2.fromOffset(textWidth,26)
        heading.TextSize=fontSize;heading.TextScaled=false;heading.TextXAlignment=Enum.TextXAlignment.Center;heading.TextStrokeTransparency=1
        local limit=heading:FindFirstChildOfClass('UITextSizeConstraint');if limit then limit.MaxTextSize=22 end
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.4},heading)
        discordSubtitle.TextSize=14;discordSubtitle.TextScaled=true;discordSubtitle.Size=UDim2.new(1,-112,0,16)
        discordSubtitle.AnchorPoint=Vector2.new(0,0);discordSubtitle.Position=UDim2.fromOffset(100,27);discordSubtitle.TextXAlignment=Enum.TextXAlignment.Left;discordSubtitle.TextStrokeTransparency=1
        local discordLimit=discordSubtitle:FindFirstChildOfClass('UITextSizeConstraint');if discordLimit then discordLimit.MaxTextSize=14 end
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.3},discordSubtitle)
    end
    refreshButton.Font=Enum.Font.FredokaOne
    local refreshCaption=refreshButton:FindFirstChild('RaisedCaption')
    if refreshCaption then
        refreshCaption.Font=Enum.Font.FredokaOne;refreshCaption.TextSize=20;refreshCaption.TextScaled=true;refreshCaption.TextStrokeTransparency=1
        refreshCaption.Position=UDim2.fromOffset(4,2);refreshCaption.Size=UDim2.new(1,-8,1,-4)
        D.make('UITextSizeConstraint',{MinTextSize=12,MaxTextSize=20},refreshCaption)
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.7},refreshCaption)
    end
    resetTimer.Font=Enum.Font.FredokaOne;resetTimer.TextSize=16;resetTimer.TextScaled=true;resetTimer.TextStrokeTransparency=1
    D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=16},resetTimer)
    D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.4},resetTimer)
    local hotkeyConnection=Input.InputBegan:Connect(function(input,processed)
        if processed or Input:GetFocusedTextBox() then return end
        if input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode==menuHotkey then
            panel.Visible=not panel.Visible
            D.localPanel.Visible=not panel.Visible
        end
    end)
    D.gui.Destroying:Connect(function() hotkeyConnection:Disconnect() end)
    end
    local mutationPalettes={
        title={Color3.fromRGB(223,221,221),Color3.fromRGB(225,223,223),Color3.fromRGB(226,225,225),Color3.fromRGB(228,227,227),Color3.fromRGB(230,229,229),Color3.fromRGB(231,231,231),Color3.fromRGB(233,233,233),Color3.fromRGB(236,236,236),Color3.fromRGB(239,239,239),Color3.fromRGB(242,242,242),Color3.fromRGB(246,246,246),Color3.fromRGB(249,249,249),Color3.fromRGB(252,252,252),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255),Color3.fromRGB(252,252,252),Color3.fromRGB(249,249,249),Color3.fromRGB(246,246,246),Color3.fromRGB(242,242,242),Color3.fromRGB(239,239,239),Color3.fromRGB(236,236,236),Color3.fromRGB(233,233,233),Color3.fromRGB(230,230,230),Color3.fromRGB(227,227,227),Color3.fromRGB(224,224,224),Color3.fromRGB(220,220,220),Color3.fromRGB(217,217,217),Color3.fromRGB(214,214,214)},
        discord={Color3.fromRGB(255,0,225),Color3.fromRGB(251,0,226),Color3.fromRGB(247,0,227),Color3.fromRGB(244,0,229),Color3.fromRGB(240,0,230),Color3.fromRGB(236,0,231),Color3.fromRGB(232,0,232),Color3.fromRGB(229,0,233),Color3.fromRGB(225,0,235),Color3.fromRGB(221,0,236),Color3.fromRGB(217,0,237),Color3.fromRGB(214,0,238),Color3.fromRGB(210,0,239),Color3.fromRGB(206,0,241),Color3.fromRGB(202,0,242),Color3.fromRGB(199,0,243),Color3.fromRGB(195,0,244),Color3.fromRGB(191,0,245),Color3.fromRGB(187,0,247),Color3.fromRGB(184,0,248),Color3.fromRGB(180,0,249),Color3.fromRGB(176,0,250),Color3.fromRGB(172,0,251),Color3.fromRGB(169,0,253),Color3.fromRGB(165,0,254),Color3.fromRGB(161,0,255)},
        golden={Color3.fromRGB(206,164,0),Color3.fromRGB(222,173,0),Color3.fromRGB(239,182,0),Color3.fromRGB(255,191,0),Color3.fromRGB(254,209,46),Color3.fromRGB(253,227,92)},
        rainbow={Color3.fromRGB(255,0,0),Color3.fromRGB(255,113,0),Color3.fromRGB(255,169,0),Color3.fromRGB(255,248,0),Color3.fromRGB(139,255,0),Color3.fromRGB(0,255,7),Color3.fromRGB(0,255,154)},
        silver={Color3.fromRGB(71,71,71),Color3.fromRGB(104,104,104),Color3.fromRGB(137,137,137),Color3.fromRGB(170,170,170),Color3.fromRGB(137,137,137),Color3.fromRGB(104,104,104),Color3.fromRGB(71,71,71)}
    }
    local mutationGradients={golden={},silver={},rainbow={},discord={},title={}}
    local function mutationSequence(palette,now)
        local phase=(now/4)%1
        local points={}
        for i=0,16 do
            local sample=((i/16-phase)%1)*#palette
            local index=math.floor(sample)
            points[#points+1]=ColorSequenceKeypoint.new(i/16,palette[index+1]:Lerp(palette[(index+1)%#palette+1],sample-index))
        end
        return ColorSequence.new(points)
    end
    local function mutationStyle(object,name)
        local key=name:lower()
        if key=='gold' then key='golden' end
        local palette=mutationPalettes[key]
        if not palette then return end
        if object:IsA('TextLabel') then
            object.TextColor3=Color3.new(1,1,1);object.TextStrokeTransparency=1
        else object.ImageColor3=Color3.new(1,1,1) end
        local gradient=D.make('UIGradient',{Color=mutationSequence(palette,os.clock()),Rotation=0},object)
        local bucket=mutationGradients[key];bucket[#bucket+1]=gradient
    end
    mutationStyle(discordSubtitle,'discord')
    heading.TextColor3=Theme.cyan
    local filterPalettes={
        cosmic={Color3.fromRGB(67,37,239),Color3.fromRGB(113,29,255),Color3.fromRGB(90,37,230),Color3.fromRGB(67,44,204),Color3.fromRGB(63,44,244),Color3.fromRGB(41,12,217)},
        secret={Color3.fromRGB(40,40,40),Color3.fromRGB(66,62,59),Color3.fromRGB(90,90,87),Color3.fromRGB(118,124,118),Color3.fromRGB(144,152,152),Color3.fromRGB(195,195,201)},
        eternal={Color3.fromRGB(143,203,193),Color3.fromRGB(179,236,227),Color3.fromRGB(192,236,229),Color3.fromRGB(205,236,230),Color3.fromRGB(216,236,232),Color3.fromRGB(227,236,234),Color3.fromRGB(182,165,198),Color3.fromRGB(82,28,125),Color3.fromRGB(141,92,164),Color3.fromRGB(183,125,193),Color3.fromRGB(216,151,220),Color3.fromRGB(230,171,234),Color3.fromRGB(227,187,236),Color3.fromRGB(218,202,236),Color3.fromRGB(212,216,236)}
    }
    local filterWords=D.make('Frame',{Name='RarityFontParts',AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(1,26),BackgroundTransparency=1,Active=false,ZIndex=rarity.ZIndex+5},rarity)
    local function filterLabel(text)
        local label=D.make('TextLabel',{Text=text,Font=Enum.Font.FredokaOne,TextSize=20,TextColor3=Color3.new(1,1,1),TextStrokeTransparency=1,BackgroundTransparency=1,TextWrapped=false,TextScaled=false,Active=false,ZIndex=filterWords.ZIndex},filterWords)
        D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=2},label)
        return label
    end
    local filterPrefix=filterLabel('MIN RARITY:')
    local filterWord=filterLabel('Any')
    local filterGradient=D.make('UIGradient',{Enabled=false,Rotation=0},filterWord)
    local filterName=rarityOptions[rarityIndex].name:lower()
    local function updateFilterColor(now)
        local palette=filterPalettes[filterName]
        if palette then
            filterWord.TextColor3=Color3.new(1,1,1);filterGradient.Enabled=true
            filterGradient.Color=mutationSequence(palette,now)
        else
            filterGradient.Enabled=false;filterWord.TextColor3=rarityColors[filterName] or Color3.new(1,1,1)
        end
    end
    local function refreshFilterWord()
        local name=rarityOptions[rarityIndex].name
        filterName=name:lower();filterWord.Text=name
        filterGradient.Rotation=filterName=='eternal' and 90 or 0
        rarity.TextTransparency=1
        local caption=rarity:FindFirstChild('RaisedCaption');if caption then caption.Visible=false end
        local panelWidth=panel.Size.X.Offset>0 and panel.Size.X.Offset or 402
        local available=math.max(20,panelWidth*rarity.Size.X.Scale+rarity.Size.X.Offset-20)
        local service=game:GetService('TextService')
        local size,prefixWidth,wordWidth=22,0,0
        repeat
            prefixWidth=math.ceil(service:GetTextSize(filterPrefix.Text,size,Enum.Font.FredokaOne,Vector2.new(1000,1000)).X)+4
            wordWidth=math.ceil(service:GetTextSize(name,size,Enum.Font.FredokaOne,Vector2.new(1000,1000)).X)+4
            if prefixWidth+wordWidth+6<=available or size<=10 then break end
            size-=1
        until false
        filterWords.Size=UDim2.fromOffset(prefixWidth+wordWidth+6,26)
        filterPrefix.Position=UDim2.new();filterPrefix.Size=UDim2.fromOffset(prefixWidth,26);filterPrefix.TextSize=size
        filterWord.Position=UDim2.fromOffset(prefixWidth+6,0);filterWord.Size=UDim2.fromOffset(wordWidth,26);filterWord.TextSize=size
        updateFilterColor(os.clock())
    end
    rarity:GetPropertyChangedSignal('Text'):Connect(refreshFilterWord)
    refreshFilterWord()
    -- Keep the internal rarity filter at Any, but remove its control from the visible UI.
    rarity.Visible=false
    rarity.Active=false
    rarity.Size=UDim2.fromOffset(0,0)
    local rarityGradientBuckets={cosmic={},secret={},eternal={}}
    local function styleRarityLabel(label,key)
        local palette=filterPalettes[key]
        if not palette then return end
        label.TextColor3=Color3.new(1,1,1)
        if key=='secret' then label.TextStrokeColor3=Color3.new(0,0,0);label.TextStrokeTransparency=0.25 end
        local gradient=D.make('UIGradient',{Color=mutationSequence(palette,os.clock()),Rotation=key=='eternal' and 90 or 0},label)
        rarityGradientBuckets[key][gradient]=true
    end
    local lastMutationUpdate=0
    local mutationMotion=game:GetService('RunService').Heartbeat:Connect(function()
        local now=os.clock()
        if now-lastMutationUpdate<1/20 then return end
        lastMutationUpdate=now
        if refreshing then
            local text='REFRESHING'..string.rep('.',math.floor(now/0.4)%3+1)
            if refreshButton.Text~=text then refreshButton.Text=text end
        end
        if loadingVisible and aliveMessage.Visible then
            local text=loadingText(now);if aliveMessage.Text~=text then aliveMessage.Text=text end
        end
        updateFilterColor(now)
        for key,bucket in pairs(rarityGradientBuckets) do
            if next(bucket) then
                local colors=mutationSequence(filterPalettes[key],now)
                for gradient in pairs(bucket) do
                    if gradient.Parent then gradient.Color=colors else bucket[gradient]=nil end
                end
            end
        end
        for key,bucket in pairs(mutationGradients) do
            if #bucket>0 then
                local colors=mutationSequence(mutationPalettes[key],now)
                for i=#bucket,1,-1 do
                    local gradient=bucket[i]
                    if not gradient.Parent then table.remove(bucket,i) else gradient.Color=colors end
                end
            end
        end
    end)
    D.gui.Destroying:Connect(function() mutationMotion:Disconnect() end)
    local function mutationWidth(name,textService,available)
        local spec=mutationSpriteData[name:lower()]
        if spec then return math.min(available,math.ceil(spec.width/spec.height*24)+8) end
        return math.min(available,math.ceil(textService:GetTextSize(name,22,Enum.Font.Arcade,Vector2.new(1000,28)).X)+8)
    end
    local function mutationWord(row,name,position,width)
        local word=D.label(row,name,position,UDim2.fromOffset(width,28),Color3.fromRGB(245,210,125),22)
        word.Font=Enum.Font.Arcade
        word.TextXAlignment=Enum.TextXAlignment.Center
        word.TextTruncate=Enum.TextTruncate.None;word.TextScaled=true;word.TextWrapped=false
        D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=22},word)
        mutationStyle(word,name)
        word.TextStrokeColor3=Color3.new(0,0,0);word.TextStrokeTransparency=0
        local fallbackStroke=D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},word)
        local spec=mutationSprites[name:lower()]
        if spec then
            local glyph=D.make('ImageLabel',{Image=spec.image,ImageTransparency=1,BackgroundTransparency=1,ImageColor3=Color3.new(1,1,1),Size=UDim2.new(1,-4,1,-4),Position=UDim2.fromOffset(2,2),ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=word.ZIndex+2},word)
            pcall(function() glyph.ResampleMode=Enum.ResamplerMode.Pixelated end)
            local shadows={}
            for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                local shadow=D.make('ImageLabel',{Image=spec.image,ImageTransparency=1,ImageColor3=Color3.new(0,0,0),BackgroundTransparency=1,Size=UDim2.new(1,-4,1,-4),Position=UDim2.fromOffset(2+offset[1],2+offset[2]),ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=word.ZIndex+1},word)
                pcall(function() shadow.ResampleMode=Enum.ResamplerMode.Pixelated end)
                shadows[#shadows+1]=shadow
            end
            mutationStyle(glyph,name)
            local function ready()
                if glyph.IsLoaded then fallbackStroke.Enabled=false;word.TextStrokeTransparency=1;word.TextTransparency=1;glyph.ImageTransparency=0;for _,shadow in ipairs(shadows) do shadow.ImageTransparency=0 end end
            end
            glyph:GetPropertyChangedSignal('IsLoaded'):Connect(ready)
            ready()
        end
        return word
    end
    local joiningKey=nil
    local joinRetryAt=0
    local cardsByKey={}
    local function compactCardHeight()
        return math.clamp(math.floor((panel.Size.Y.Offset-238-16)/5),96,108)
    end
    local function joinPresentation(entry)
        local here=entry.isLocal or entry.jobId==game.JobId
        if entry.takenConfirmed then return 'TAKEN',Color3.fromRGB(235,55,65),false end
        if othersOnly and here then return 'HERE',Color3.fromRGB(255,255,255),false end
        if entry.full or entry.unavailable then return 'FULL',Color3.fromRGB(255,75,85),false end
        if here then return 'HERE',Color3.fromRGB(255,255,255),false end
        if joining and joiningKey==entry.key then return 'JOINING...',Color3.fromRGB(40,160,85),false end
        return 'JOIN',Color3.fromRGB(40,160,85),true
    end
    local rankWidthCache={}
    local raritySizeCache={}
    local function cardSignature(entry)
        return Http:JSONEncode({tostring(entry.rarity),tostring(entry.mutations),tostring(entry.mutationText),tostring(entry.traitsKnown),tostring(entry.isEvent),tostring(entry.source)})
    end
    local function compactWeightToFit(text,available,size,service)
        local function fits(value) return service:GetTextSize(value,size,Enum.Font.GothamBlack,Vector2.new(1000,1000)).X<=available end
        local result=text
        while not fits(result) do
            local prefix,whole,fraction,suffix=result:match('^(.-)(%d+)%.(%d+)(.*)$')
            if not fraction then break end
            fraction=fraction:sub(1,-2)
            result=prefix..whole..(#fraction>0 and '.'..fraction or '')..suffix
        end
        return result
    end
    local function fitFinanceText(card)
        local listWidth=list.AbsoluteSize.X>0 and list.AbsoluteSize.X or panel.Size.X.Offset*0.68
        local rowWidth=listWidth-28
        local width=rowWidth-220
        local service=game:GetService('TextService')
        local weightSize=type(card.entry.weight)=='number' and 16 or 19
        local weightAvailable=width*0.46-10
        local text=weightPresentation(card.entry)
        card.weightLabel.Text=compactWeightToFit(text,weightAvailable,weightSize,service)
        for _,spec in ipairs({{card.incomeLabel,width*0.54-10,20},{card.weightLabel,weightAvailable,weightSize}}) do
            local label,available,size=spec[1],spec[2],spec[3]
            while size>8 and service:GetTextSize(label.Text,size,Enum.Font.GothamBlack,Vector2.new(1000,1000)).X>available do size-=1 end
            label.TextSize=size
        end
    end
    local function updateCard(card,entry,i)
        local height=compactCardHeight()
        if card.compactHeight~=height or card.renderScale~=responsiveScale.Scale then
            card.renderScale=responsiveScale.Scale
            card.compactHeight=height;card.row.Size=UDim2.new(1,-12,0,height)
            local renderScale=responsiveScale.Scale
            if type(renderScale)~='number' or renderScale<=0 then renderScale=1 end
            local iconSize=math.floor(math.min(88,height-16)*renderScale)/renderScale
            card.icon.Size=UDim2.fromOffset(iconSize,iconSize);card.icon.Position=UDim2.fromOffset(math.floor((4+(78-iconSize)/2)*renderScale)/renderScale,0)
            card.spotlight.Position=card.icon.Position
            card.spotlight.Size=card.icon.Size
            card.join.Position=UDim2.new(1,-98,0,math.min(29,height-54))
        end
        local rankText='#'..tostring(entry.displayRank or entry.globalRank or i)
        if card.rankLabel.Text~=rankText then
            local width=rankWidthCache[rankText]
            if not width then
                width=math.ceil(game:GetService('TextService'):GetTextSize(rankText,20,Enum.Font.FredokaOne,Vector2.new(1000,28)).X)+4
                rankWidthCache[rankText]=width
            end
            card.rankLabel.Text=rankText;card.rankLabel.Size=UDim2.fromOffset(width,28)
            card.nameLabel.Position=UDim2.fromOffset(110+width,3);card.nameLabel.Size=UDim2.new(1,-118-width,0,26)
        end
        if card.nameLabel.Text~=tostring(entry.name) then card.nameLabel.Text=tostring(entry.name) end
        card.nameLabel.Size=UDim2.new(1,-118-card.rankLabel.Size.X.Offset,0,26)
        if card.icon.Image~=(entry.icon or '') then card.icon.Image=entry.icon or '' end
        if not card.financeReady or card.rate~=entry.rate or card.missingRate~=entry.missingRate then
            card.incomeLabel.Text=entry.missingRate and 'Income unavailable' or D.money(entry.rate)
            card.rate=entry.rate;card.missingRate=entry.missingRate
        end
        if not card.financeReady or card.scale~=entry.scale or card.weight~=entry.weight then
            local text,color=weightPresentation(entry)
            local isScale=type(entry.weight)~='number' and type(entry.scale)=='number'
            card.weightLabel.Text=text;card.weightLabel.TextColor3=color
            card.weightLabel.Font=Enum.Font.GothamBlack
            card.weightLabel.TextSize=isScale and 19 or 16
            card.weightLimit.MaxTextSize=isScale and 19 or 16
            card.scale=entry.scale;card.weight=entry.weight
        end
        if not card.financeReady or card.fittedRate~=entry.rate or card.fittedWeight~=entry.weight or card.fittedScale~=entry.scale then
            fitFinanceText(card);card.fittedRate=entry.rate;card.fittedWeight=entry.weight;card.fittedScale=entry.scale
        end
        card.financeReady=true
        local text,color,enabled=joinPresentation(entry)
        -- Keep the local taken state label-only; never append an elapsed-time counter.
        if entry.takenConfirmed then text='TAKEN' end
        card.join.TextWrapped=false
        if card.join.Text~=text then card.join.Text=text end
        -- Always apply the current status color, even when the label/enabled state is unchanged.
        card.join.BackgroundColor3=color
        if card.buttonText~=text or card.buttonEnabled~=enabled then
            card.join.Active=enabled;card.join.AutoButtonColor=enabled;card.join.Selectable=enabled
            card.buttonText=text;card.buttonEnabled=enabled
        end
    end
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
    local function queueRender()
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
                local scan=D.metadata and D.metadata()
                if type(D.ready)=='function' and D.ready() and scan and type(scan.scanAt)=='number' and tracked._lastScanAt~=scan.scanAt then
                    tracked._lastScanAt=scan.scanAt
                    local present=false
                    for _,e in ipairs(D.entries()) do
                        if tostring(e.uid or e.key)==tracked.uid then present=true;break end
                    end
                    if present then
                        tracked._missingScans=0
                    else
                        tracked._missingScans=(tracked._missingScans or 0)+1
                    end
                    if tracked._missingScans>=2 and not tracked.takenAt then
                        tracked.takenAt=os.time()
                        local saved=table.clone(tracked)
                        saved._lastScanAt=nil;saved._missingScans=nil
                        pcall(function() Teleports:SetTeleportSetting(joinedEggSettingKey,saved) end)
                    end
                end
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
                if not isHalloweenEgg(e) and (not states[e.uid] or states[e.uid]=='Claimed') then
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
        -- Keep the old canvas extent while rebuilding so Roblox does not clamp
        -- the scroll position to zero when the rows are temporarily removed.
        local savedScroll=list.CanvasPosition
        local canvasHeight=#entries==0 and 40 or 0
        local wanted={}
        for _,entry in ipairs(entries) do wanted[entry.key]=true;passDeadline=math.min(passDeadline,entry.expiresAt) end
        for key,card in pairs(cardsByKey) do
            if not wanted[key] then
                card.row:Destroy();cardsByKey[key]=nil
                if not checkpoint() then return end
            end
        end
        loadingVisible=#entries==0 and (othersOnly and type(D.ready)=='function' and not D.ready() or not othersOnly and feedAt<=0)
        aliveMessage.Visible=#entries==0
        aliveMessage.Text=loadingVisible and loadingText(os.clock()) or othersOnly and (type(D.ready)=='function' and not D.ready() and 'Reading current server eggs...' or 'No matching eggs in this server') or 'No matching eggs right now'
        for i,entry in ipairs(entries) do
            local signature=cardSignature(entry)
            local card=cardsByKey[entry.key]
            if not card or not card.row.Parent or card.signature~=signature then
            if card and card.row.Parent then card.row:Destroy() end
            card={entry=entry,signature=signature}
            local row=D.make('Frame',{Size=UDim2.new(1,-12,0,108),LayoutOrder=i,BackgroundColor3=Color3.fromRGB(11,23,42),BackgroundTransparency=0.035,BorderSizePixel=0},list)
            card.row=row
            row.ClipsDescendants=true
            D.make('UICorner',{CornerRadius=UDim.new(0,13)},row)
            local cardGradient=D.make('UIGradient',{
                Color=ColorSequence.new({
                    ColorSequenceKeypoint.new(0,Color3.fromRGB(13,30,52)),
                    ColorSequenceKeypoint.new(0.55,Color3.fromRGB(16,23,48)),
                    ColorSequenceKeypoint.new(1,Color3.fromRGB(28,17,48)),
                }),
                Rotation=0
            },row)
            local cardMotion=TweenService:Create(cardGradient,
                TweenInfo.new(22,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),
                {Rotation=180})
            cardMotion:Play()
            table.insert(starTweens,cardMotion)
            D.make('UIStroke',{Color=Theme.accent,Transparency=0.48,Thickness=1.2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},row)
            D.make('Frame',{Name='CardAccentRail',Position=UDim2.fromOffset(0,12),Size=UDim2.fromOffset(3,84),BackgroundColor3=Theme.cyan,BackgroundTransparency=0.08,BorderSizePixel=0,Active=false},row)
            D.make('Frame',{Name='CardBevelTop',Position=UDim2.fromOffset(3,1),Size=UDim2.new(1,-6,0,1),BackgroundColor3=Color3.fromRGB(235,230,255),BackgroundTransparency=0.55,BorderSizePixel=0,Active=false},row)
            D.make('Frame',{Name='CardBevelBottom',Position=UDim2.new(0,3,1,-2),Size=UDim2.new(1,-6,0,1),BackgroundColor3=Color3.fromRGB(10,6,22),BackgroundTransparency=0,BorderSizePixel=0,Active=false},row)
            -- Static native UI rays: no downloads, image compression or animation work.
            local spotlight=D.make('Frame',{Name='PetSpotlight',Position=UDim2.fromOffset(2,0),Size=UDim2.new(0,82,1,-22),BackgroundTransparency=1,BorderSizePixel=0,ClipsDescendants=false,Active=false,ZIndex=row.ZIndex+1},row)
            -- Pet icon intentionally has no white rays or center-glow overlay.
            card.spotlight=spotlight
            card.icon=D.make('ImageLabel',{Name='PetIcon',Image=entry.icon or '',ZIndex=spotlight.ZIndex+1,BackgroundTransparency=1,Size=UDim2.fromOffset(88,88),Position=UDim2.fromOffset(4,4),ScaleType=Enum.ScaleType.Fit},row)
            local rarityKey=tostring(entry.rarity):lower():gsub('%s+','')
            local nameColor=rarityColors[rarityKey] or Color3.fromRGB(225,225,235)
            local rankText='#'..tostring(entry.displayRank or entry.globalRank or i)
            local textService=game:GetService('TextService')
            local rankWidth=rankWidthCache[rankText]
            if not rankWidth then
                rankWidth=math.ceil(textService:GetTextSize(rankText,20,Enum.Font.FredokaOne,Vector2.new(1000,28)).X)+4
                rankWidthCache[rankText]=rankWidth
            end
            local rankLabel=D.label(row,rankText,UDim2.fromOffset(110,3),UDim2.fromOffset(rankWidth,26),Color3.fromRGB(220,224,235),20)
            rankLabel.Font=Enum.Font.FredokaOne
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.5},rankLabel)
            card.rankLabel=rankLabel
            rankLabel.TextTruncate=Enum.TextTruncate.None
            local nameLabel=D.label(row,tostring(entry.name),UDim2.fromOffset(110+rankWidth,3),UDim2.new(1,-118-rankWidth,0,26),nameColor,21)
            card.nameLabel=nameLabel
            nameLabel.Font=Enum.Font.GothamBlack
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},nameLabel)
            nameLabel.TextStrokeColor3=Color3.new(0,0,0);nameLabel.TextStrokeTransparency=1
            rankLabel.TextStrokeColor3=Color3.new(0,0,0);rankLabel.TextStrokeTransparency=1
            pcall(function() card.icon.ResampleMode=Enum.ResamplerMode.Default end)
            local rarityCell=D.make('Frame',{Name='RarityCell',Position=UDim2.fromOffset(110,57),Size=UDim2.fromOffset(160,20),BackgroundTransparency=1,ClipsDescendants=true},row)
            local rarityText=tostring(entry.rarity)
            local rarityTextSize=raritySizeCache[rarityText]
            if not rarityTextSize then
                rarityTextSize=20
                while rarityTextSize>1 do
                    local bounds=textService:GetTextSize(rarityText,rarityTextSize,Enum.Font.GothamBlack,Vector2.new(1000,1000))
                    if bounds.X<=148 and bounds.Y<=18 then break end
                    rarityTextSize-=1
                end
                raritySizeCache[rarityText]=rarityTextSize
            end
            local rarityLabel=D.label(rarityCell,rarityText,UDim2.fromOffset(3,1),UDim2.new(1,-6,1,-2),nameColor,rarityTextSize)
            rarityLabel.Font=Enum.Font.GothamBlack
            rarityLabel.TextStrokeColor3=Color3.new(0,0,0);rarityLabel.TextStrokeTransparency=0.2
            rarityLabel.TextXAlignment=Enum.TextXAlignment.Center
            rarityLabel.TextYAlignment=Enum.TextYAlignment.Center
            rarityLabel.TextTruncate=Enum.TextTruncate.None
            rarityLabel.TextScaled=false
            rarityLabel.TextWrapped=false
            styleRarityLabel(nameLabel,rarityKey)
            local finance=D.make('Frame',{Name='IncomeAndWeight',Position=UDim2.fromOffset(110,31),Size=UDim2.new(1,-220,0,22),BackgroundTransparency=1},row)
            local incomeCell=D.make('Frame',{Name='IncomeCell',Position=UDim2.new(),Size=UDim2.new(0.54,-4,1,0),BackgroundTransparency=1,ClipsDescendants=false},finance)
            local incomeLabel=D.label(incomeCell,entry.missingRate and 'Income unavailable' or D.money(entry.rate),UDim2.fromOffset(3,2),UDim2.new(1,-6,1,-4),Color3.fromRGB(135,240,140),20)
            card.incomeLabel=incomeLabel
            incomeLabel.TextStrokeColor3=Color3.new(0,0,0);incomeLabel.TextStrokeTransparency=1
            incomeLabel.Font=Enum.Font.GothamBlack
            incomeLabel.TextXAlignment=Enum.TextXAlignment.Center
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},incomeLabel)
            incomeLabel.TextTruncate=Enum.TextTruncate.None
            incomeLabel.TextScaled=false
            incomeLabel.TextWrapped=false
            D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=20},incomeLabel)
            local weightText,weightColor=weightPresentation(entry)
            local isScale=type(entry.weight)~='number' and type(entry.scale)=='number'
            local weightCell=D.make('Frame',{Name='WeightCell',Position=UDim2.new(0.54,4,0,0),Size=UDim2.new(0.46,-4,1,0),BackgroundTransparency=1,ClipsDescendants=false},finance)
            local weightLabel=D.label(weightCell,weightText,UDim2.fromOffset(3,2),UDim2.new(1,-6,1,-4),weightColor,isScale and 19 or 16)
            card.weightLabel=weightLabel
            D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=1.1},weightLabel)
            weightLabel.TextStrokeColor3=Color3.new(0,0,0);weightLabel.TextStrokeTransparency=1
            weightLabel.Font=Enum.Font.GothamBlack
            weightLabel.TextXAlignment=Enum.TextXAlignment.Center
            weightLabel.TextTruncate=Enum.TextTruncate.None
            weightLabel.TextScaled=false
            weightLabel.TextWrapped=false
            card.weightLimit=D.make('UITextSizeConstraint',{MinTextSize=1,MaxTextSize=isScale and 19 or 16},weightLabel)
            rarityLabel.TextColor3=nameLabel.TextColor3
            local nameGradient=nameLabel:FindFirstChildOfClass('UIGradient')
            if nameGradient then
                local gradient=nameGradient:Clone();gradient.Parent=rarityLabel
                rarityGradientBuckets[rarityKey][gradient]=true
            end

            local names=mutationNames(entry)
            local listWidth=list.AbsoluteSize.X>0 and list.AbsoluteSize.X or panel.Size.X.Offset*0.68
            local available=math.max(100,listWidth-130)
            local widths,total={},0
            for i,name in ipairs(names) do widths[i]=mutationWidth(name,textService,available);total+=widths[i]+5 end
            local strip=D.make('Frame',{Name='MutationStrip',Position=UDim2.new(0,110,1,-29),Size=UDim2.new(1,-218,0,28),BackgroundTransparency=1,ClipsDescendants=true},row)
            local words=D.make('Frame',{Name='MutationWords',Position=UDim2.fromOffset(4,0),Size=UDim2.fromOffset(math.max(1,total),28),BackgroundTransparency=1},strip)
            D.make('UIScale',{Scale=math.min(1,available/math.max(1,total))},words)
            local x=0
            for i,name in ipairs(names) do mutationWord(words,name,UDim2.fromOffset(x,0),widths[i]);x+=widths[i]+5 end
            row.Size=UDim2.new(1,-12,0,compactCardHeight())
            local here=entry.isLocal or entry.jobId==game.JobId
            local join=D.make('TextButton',{Name='JoinStatusButton',Text=select(1,joinPresentation(entry)),Position=UDim2.new(1,-98,0,29),Size=UDim2.fromOffset(90,32),BackgroundColor3=entry.takenConfirmed and Color3.fromRGB(235,55,65) or (entry.full or entry.unavailable) and Color3.fromRGB(255,75,85) or here and Color3.fromRGB(86,90,100) or Color3.fromRGB(40,160,85),TextColor3=Color3.new(1,1,1),TextSize=13},row)
            card.join=join
            local joinCorner=join:FindFirstChildOfClass('UICorner')
            if joinCorner then joinCorner.CornerRadius=UDim.new(0,8) end
            join.Font=Enum.Font.FredokaOne
            styleRaisedButton(join)
            local caption=join:FindFirstChild('RaisedCaption')
            if caption then
                caption.Font=Enum.Font.FredokaOne;caption.TextScaled=true;caption.TextSize=20
                caption.TextStrokeTransparency=1
                caption.Position=UDim2.fromOffset(5,2);caption.Size=UDim2.new(1,-10,1,-4)
                D.make('UITextSizeConstraint',{MinTextSize=10,MaxTextSize=20},caption)
                D.make('UIStroke',{Color=Color3.new(0,0,0),Thickness=2},caption)
            end
            join.Active=not (entry.full or entry.unavailable)
            join.AutoButtonColor=not (entry.full or entry.unavailable)
            join.Selectable=not (entry.full or entry.unavailable)
            join.Activated:Connect(function()
                local entry=card.entry
                if not D.publicEntryAllowed(entry,(os.clock()+clockOffset)*1000) or entry.takenConfirmed or entry.full or entry.unavailable or joining or os.clock()<joinRetryAt or entry.jobId==game.JobId then return end
                if (os.clock()+clockOffset)*1000>=entry.expiresAt then queryStatus='Report expired; refreshing'; feedAt=0; return end
                joining=true;joiningKey=entry.key;joinRetryAt=os.clock()+0.25
                queryStatus='Joining '..entry.name
                updateCard(card,entry,card.row.LayoutOrder or 1)
                -- removed unnecessary pre-join delay
                entry=card.entry
                if not active then joining=false;joiningKey=nil;return end
                if not D.publicEntryAllowed(entry,(os.clock()+clockOffset)*1000) or entry.takenConfirmed or entry.full or entry.unavailable then
                    joining=false;joiningKey=nil;updateCard(card,entry,card.row.LayoutOrder or 1);return
                end
                if (os.clock()+clockOffset)*1000>=entry.expiresAt then
                    joining=false;joiningKey=nil;feedAt=-math.huge;render();return
                end
                if not config then joining=false;joiningKey=nil;queryStatus='Finder not connected';return end
                local claim,claimError=network(config.endpoint..'/v1/join','POST',Http:JSONEncode({placeId=entry.placeId,jobId=entry.jobId,uid=entry.uid,reporterId=reporterId,userId=D.player.UserId}),headers())
                if claim and claim.allowed~=true and (claim.unavailable or claim.full) then
                    joining=false;joiningKey=nil;entry.full=true;entry.unavailable=claim.unavailable==true;entry.takenConfirmed=claim.takenConfirmed==true;lastRender=nil
                    queryStatus='Egg no longer available';render();return
                end
                if not claim or claim.allowed~=true then
                    joining=false;joiningKey=nil;feedAt=-math.huge
                    if claim and not claim.retryable then
                        for _,item in ipairs(feed) do if item.jobId==entry.jobId then item.full=true end end
                        render()
                    end
                    queryStatus=claim and (claim.error or 'Server reserved; choose another') or ('Join reservation failed: '..tostring(claimError))
                    return
                end
                -- Best-effort background report; never block a successful JOIN on reporting.
                task.spawn(function()
                    local shared,shareError=report()
                    if not shared then warn('Pre-teleport report: '..tostring(shareError)) end
                end)
                local joinExpiry=math.min(entry.expiresAt,tonumber(claim.expiresAt) or entry.expiresAt)
                if (os.clock()+clockOffset)*1000>=joinExpiry then
                    joining=false;joiningKey=nil;feedAt=-math.huge;entry.expiresAt=joinExpiry;render()
                    queryStatus='Reset reached; refreshing';return
                end
                queueAutoExecute()
                D.saveGuiBeforeTeleport()
                D.stopFarm()
                rememberJoinedEgg(entry)
                local ok,err=pcall(function() Teleports:TeleportToPlaceInstance(entry.placeId,entry.jobId,D.player) end)
                if not ok then queryStatus='Join failed: '..tostring(err); joining=false;joiningKey=nil end
                task.delay(12,function() joining=false;joiningKey=nil end)
            end)
            end
            card.entry=entry
            updateCard(card,entry,i)
            card.row.LayoutOrder=i
            cardsByKey[entry.key]=card
            canvasHeight+=card.row.Size.Y.Offset+4
            if not checkpoint() then return end
        end
        list.CanvasSize=UDim2.fromOffset(0,canvasHeight)
        list.CanvasPosition=savedScroll
        list.Visible=true
    end
    render=function()
        if not active then return end
        if rendering then renderPending=true;return end
        rendering=true
        local ok,err=pcall(renderOnce)
        rendering=false
        if renderPending then renderPending=false;queueRender() end
        if not ok then list.Visible=true;error(err) end
    end
    requestScopeRender=function()
        -- Hide old-tab rows immediately; never expose remote JOINs as MY SERVER.
        list.Visible=false
        list.CanvasPosition=Vector2.new(0,0)
        queueRender()
    end
    refreshButton.Activated:Connect(function()
        if refreshing or not active then return end
        refreshing=true;refreshButton.Text='REFRESHING.'
        task.spawn(function()
            local ok,err=pcall(function()
                local deadline=os.clock()+12
                while active and networkBusy and os.clock()<deadline do task.wait(0.1) end
                if not active then return end
                if networkBusy then error('Network busy; try again') end
                if not config or os.clock()-configAt>60 then
                    local loaded,message=loadConfig();if not loaded then error(message) end
                end
                if not othersOnly then
                    local loaded,message=refresh();if not loaded then error(message) end
                end
                lastRender=nil;render()
            end)
            refreshing=false
            if active then
                refreshButton.Text='REFRESH'
                queryStatus=ok and 'List refreshed' or ('Refresh failed: '..tostring(err))
            end
        end)
    end)
    do
        local Tweens=game:GetService('TweenService')
        local states={}
        local function attachButtonMotion(button)
            if not (button:IsA('TextButton') or button:IsA('ImageButton')) then return end
            if button.Name=='SettingsOverlay' or button.Name=='LauncherHitArea' or button:GetAttribute('TenshiButtonMotion') then return end
            button:SetAttribute('TenshiButtonMotion',true)
            local motion=D.make('UIScale',{Name='ButtonMotion',Scale=1},button)
            local state={button=button,motion=motion,base=button.Position,hover=false,input=nil,tween=nil,writing=false,alive=true}
            states[button]=state
            local function enabled() return button.Active~=false and button.Selectable~=false end
            local function center()
                if not state.alive or not button.Parent then return end
                local delta=motion.Scale-1
                local x,y=0.5-button.AnchorPoint.X,0.5-button.AnchorPoint.Y
                local size=button.Size
                local goal=UDim2.new(state.base.X.Scale-size.X.Scale*delta*x,state.base.X.Offset-size.X.Offset*delta*x,state.base.Y.Scale-size.Y.Scale*delta*y,state.base.Y.Offset-size.Y.Offset*delta*y)
                state.lastPosition=goal
                if button.Position==goal then return end
                state.writing=true
                button.Position=goal
                state.writing=false
            end
            local function update()
                if not state.alive then return end
                if state.tween then state.tween:Cancel();state.tween=nil end
                local target=1
                if enabled() then
                    if state.input then target=0.95
                    elseif state.hover then
                        local width=math.max(1,button.AbsoluteSize.X/math.max(0.01,motion.Scale))
                        target=math.min(1.06,1+5/width)
                    end
                else state.input=nil;state.hover=false end
                state.tween=Tweens:Create(motion,TweenInfo.new(state.input and 0.08 or 0.13,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=target})
                state.tween:Play()
            end
            state.update=update
            motion:GetPropertyChangedSignal('Scale'):Connect(center)
            button:GetPropertyChangedSignal('Position'):Connect(function()
                if not state.writing and button.Position~=state.lastPosition then state.base=button.Position;center() end
            end)
            button:GetPropertyChangedSignal('Size'):Connect(center)
            button:GetPropertyChangedSignal('AnchorPoint'):Connect(center)
            button:GetPropertyChangedSignal('Active'):Connect(update)
            button:GetPropertyChangedSignal('Selectable'):Connect(update)
            button.MouseEnter:Connect(function()
                if Input:GetLastInputType()==Enum.UserInputType.Touch then return end
                state.hover=true;update()
            end)
            button.MouseLeave:Connect(function() state.hover=false;update() end)
            button.SelectionGained:Connect(function() state.hover=true;update() end)
            button.SelectionLost:Connect(function() state.hover=false;update() end)
            button.InputBegan:Connect(function(input)
                if not enabled() then return end
                if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                    if input.UserInputType==Enum.UserInputType.Touch then state.hover=false end
                    state.input=input;update()
                end
            end)
            button.Destroying:Connect(function()
                state.alive=false
                if state.tween then state.tween:Cancel() end
                states[button]=nil
            end)
        end
        local release=Input.InputEnded:Connect(function(input)
            for _,state in pairs(states) do
                if state.input and (state.input==input or state.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then
                    state.input=nil;state.update()
                end
            end
        end)
        for _,button in ipairs(panel:GetDescendants()) do attachButtonMotion(button) end
        local added=panel.DescendantAdded:Connect(function(button)
            if button:IsA('TextButton') or button:IsA('ImageButton') then
                task.defer(function() if active and button.Parent then attachButtonMotion(button) end end)
            end
        end)
        local hidden=panel:GetPropertyChangedSignal('Visible'):Connect(function()
            if panel.Visible then return end
            for _,state in pairs(states) do state.input=nil;state.hover=false;state.update() end
        end)
        D.gui.Destroying:Connect(function()
            release:Disconnect();added:Disconnect();hidden:Disconnect()
            for _,state in pairs(states) do
                state.alive=false;if state.tween then state.tween:Cancel() end
            end
            table.clear(states)
        end)
    end

    do
        local Tweens=game:GetService('TweenService')
        local hovered,moving,scheduled=false,false,false
        local lastMovement=0
        local tween
        local function paint()
            if tween then tween:Cancel() end
            local highlighted=hovered or moving
            tween=Tweens:Create(list,TweenInfo.new(0.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{
                ScrollBarThickness=highlighted and 9 or 6,
                ScrollBarImageColor3=highlighted and Color3.fromRGB(140,205,255) or Color3.fromRGB(150,132,190),
                ScrollBarImageTransparency=highlighted and 0 or 0.18
            })
            tween:Play()
        end
        local function idle()
            if not active or not list.Parent then scheduled=false;return end
            if os.clock()-lastMovement<0.22 then task.delay(0.12,idle);return end
            scheduled=false;moving=false;paint()
        end
        local enter=list.MouseEnter:Connect(function()
            if Input:GetLastInputType()==Enum.UserInputType.Touch then return end
            hovered=true;paint()
        end)
        local leave=list.MouseLeave:Connect(function() hovered=false;paint() end)
        local scrolled=list:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
            lastMovement=os.clock()
            if not moving then moving=true;paint() end
            if not scheduled then scheduled=true;task.delay(0.24,idle) end
        end)
        local hidden=panel:GetPropertyChangedSignal('Visible'):Connect(function()
            if not panel.Visible then hovered=false;moving=false;paint() end
        end)
        D.gui.Destroying:Connect(function()
            enter:Disconnect();leave:Disconnect();scrolled:Disconnect();hidden:Disconnect()
            if tween then tween:Cancel() end
        end)
        paint()
    end

    local function applyDesktopLayout()
        settingsButton.Position=UDim2.fromOffset(16,18)
        settingsButton.Size=UDim2.fromOffset(112,42)
        status.Position=UDim2.fromOffset(18,52)
        status.Size=UDim2.new(1,-250,0,28)
        status.TextSize=14
        status.TextXAlignment=Enum.TextXAlignment.Left
        refreshButton.Position=UDim2.new(1,-218,0,48)
        refreshButton.Size=UDim2.fromOffset(200,38)
        refreshButton.TextSize=16

        scope.Position=UDim2.new(0,14,1,-84)
        scope.Size=UDim2.fromOffset(260,54)
        myScope.Position=UDim2.new(0,284,1,-84)
        myScope.Size=UDim2.fromOffset(260,54)
        serversValueFrame.Position=UDim2.new(0,554,1,-84)
        serversValueFrame.Size=UDim2.fromOffset(270,54)
        serversValueInput.Position=UDim2.new(0.64,0,0,4)
        serversValueInput.Size=UDim2.new(0.36,-8,1,-8)
        serversValueLabel.TextSize=12
        minValueFrame.Position=UDim2.new(0,834,1,-84)
        minValueFrame.Size=UDim2.fromOffset(270,54)
        minValueInput.Position=UDim2.new(0.64,0,0,4)
        minValueInput.Size=UDim2.new(0.36,-8,1,-8)
        minValueLabel.TextSize=12
        autoJoinButton.Position=UDim2.new(0,1114,1,-84)
        autoJoinButton.Size=UDim2.new(1,-1128,0,54)
        autoJoinButton.TextSize=16

        -- Keep the left data column clear and reserve the right column for the portrait.
        list.Position=UDim2.fromOffset(14,100)
        list.Size=UDim2.new(0.68,-24,1,-206)
        list.ScrollBarThickness=8
        list.ScrollBarImageColor3=Theme.cyan
        list.BackgroundTransparency=1
    end

    fitFinder()
    applyDesktopLayout()
    panel.Visible=true
    local failed=Teleports.TeleportInitFailed:Connect(function(who,_,message)
        if who==D.player then
            joining=false;queryStatus='Join failed: '..tostring(message)
            if autoJoinEnabled and autoJoinCandidateIndex<=#autoJoinCandidates then
                autoJoinCandidateIndex+=1
                autoJoinRetryRequested=true
                queryStatus='Auto Join: teleport failed; trying the next candidate'
            end
        end
    end)
    D.gui.Destroying:Connect(function() active=false; failed:Disconnect();if localHighlight then localHighlight:Destroy() end end)
    task.spawn(function()
        local lastReport=-math.huge
        local lastReportAttempt=-math.huge
        local lastPeakSignature=nil
        while active do
            local ok,err=pcall(function()
                if networkBusy then return end
                if not config or os.clock()-configAt>60 then local success,message=loadConfig(); if not success then error(message) end end
                local peak=snapshot()
                local parts={}
                for i=1,math.min(10,#peak) do
                    local egg=peak[i]
                    parts[#parts+1]=table.concat({
                        tostring(egg.uid or ''),
                        tostring(egg.rate or ''),
                        tostring(egg.scale or ''),
                        tostring(egg.weight or ''),
                        tostring(egg.mutations or ''),
                        tostring(egg.traitsKnown),
                        tostring(egg.source or '')
                    },':')
                end
                local signature=table.concat(parts,';')
                local now=os.clock()
                local heartbeatDue=now-lastReport>=broadcastInterval
                local snapshotChanged=#parts>0 and signature~=lastPeakSignature
                local changeDue=snapshotChanged and now-lastReportAttempt>=0.1
                if heartbeatDue or changeDue then
                    lastReportAttempt=now
                    local success,message=report()
                    if success then lastPeakSignature=signature;lastReport=now end
                    reportStatus=message
                    if not success then warn('Tenshi broadcast: '..tostring(message)) end
                end
                if os.clock()-feedAt>=0.5 then local success,message=refresh(autoJoinEnabled); if not success then queryStatus='Finder: '..tostring(message) end end
            end)
            if not ok then reportStatus='BCAST: '..tostring(err);queryStatus=tostring(err);warn('Tenshi broadcast: '..tostring(err)) end
            task.wait(0.5)
        end
    end)
    task.spawn(function()
        while active do
            status.Text=joining and 'Joining server…' or (tostring(reportStatus)..'\n'..tostring(queryStatus))
            local cycle=cycleInfo()
            if cycle then
                local seconds=math.max(0,math.ceil(cycle.remaining))
                resetTimer.Text=cycle.running and string.format('RESET %02d:%02d',math.floor(seconds/60),seconds%60) or 'RESET PAUSED'
                resetTimer.TextColor3=cycle.running and seconds<=60 and Color3.fromRGB(255,85,85) or cycle.running and seconds<=150 and Color3.fromRGB(255,215,65) or Color3.fromRGB(230,245,255)
            else
                resetTimer.Text='RESET --:--'
                resetTimer.TextColor3=Color3.fromRGB(230,245,255)
            end
            sharingNotice.Visible=false
            local ok=pcall(render)
            if not ok then queryStatus='Unable to display finder feed' end
            task.wait(1)
        end
    end)
end


--============================================================================--
--  [6] SCAN LOOP - reads field eggs from the game modules once per second and
--      feeds both the UI renderer and the shared broadcast worker.
--============================================================================--
local function run()
    if not game:IsLoaded() then
        startupNotice.Text = "MARVIN • WAITING FOR ROBLOX TO FINISH LOADING"
        game.Loaded:Wait()
    end

    local EggState=module('Client.EggState')
    local Assets=module('Data.Assets')
    local States=module('Shared.Types.AreaEggs').States
    local mutations,eggRecords
    pcall(function() mutations=module('Shared.Modules.Mutations') end)
    pcall(function() eggRecords=module('Shared.Util.EggRecords') end)
    assert(type(EggState.ReadFieldEggs)=='function','ReadFieldEggs unavailable')
    assert(type(Assets.Directory)=='table' and States and States.Slot~=nil,'Game schema changed')
    local latestEntries={}
    local latestMetadata=nil
    local scanCycle
    pcall(function() scanCycle=module('Shared.Util.AreaEggCycle') end)
    local function parseValue(text)
        local amount,suffix=tostring(text):gsub(',',''):match('^%s*%$?%s*(%d+%.?%d*)%s*(%a*)%s*$')
        local powers={['']=1,k=1e3,m=1e6,b=1e9,t=1e12,qa=1e15,qi=1e18}
        local factor=suffix and powers[suffix:lower()]
        if not amount or not factor then return nil end
        local value=tonumber(amount)*factor
        return valid(value) and value or nil
    end
    local lastScan=0
    finderCreating = true
    createFinder({gui=gui,localPanel={Visible=false},player=player,make=make,label=label,entries=function() return os.clock()-lastScan<10 and latestEntries or {} end,metadata=function() return latestMetadata end,ready=function() return lastScan>0 and os.clock()-lastScan<10 end,parseValue=parseValue,money=money,stopFarm=function() end})
    if startupNotice and startupNotice.Parent then startupNotice:Destroy() end
    local notified={}
    while alive do
        local ok,err=pcall(function()
            local scanStartedClock=os.clock()
            local snapshot=EggState.ReadFieldEggs()
            assert(type(snapshot)=='table' and type(snapshot.Records)=='table','Field snapshot unavailable')
            local eggs,seen={},{}
            local fieldCount,missingIncome=0,0
            local fieldStates={}
            local scanAt=workspace:GetServerTimeNow()*1000
            local resetAt
            if scanCycle then pcall(function() if scanCycle.IsRunning() then resetAt=scanCycle.NextResetTime(scanAt/1000)*1000 end end) end
            for recordKey,record in pairs(snapshot.Records) do
                fieldStates[#fieldStates+1]={uid=tostring(record.Uid or recordKey),state=record.State}
                if record.State==States.Slot or record.State==States.Carried or record.State==States.Dropped or record.State==States.GuardCarried then
                    local asset=Assets.Directory[record.AssetCategory] or {}
                    local rarity=asset.Rarity or {}
                    local uid=record.Uid or recordKey
                    local model=modelFor(uid)
                    local scale=numberField(record,{'AssetScale'})
                    local weight
                    if eggRecords and type(eggRecords.WeightKg)=='function' then
                        local good,result=pcall(eggRecords.WeightKg,record)
                        if good and valid(result) then weight=result end
                    end
                    local rate=displayedRate(model)
                    local estimated=false
                    if not rate then
                        rate=computedRate(asset.EarningRate,scale,record.Mutations or {},mutations)
                        estimated=rate~=nil
                    end
                    fieldCount=fieldCount+1
                    seen[tostring(uid)]=true
                    local traits,traitsKnown=readTraitNames(record)
                    table.insert(eggs,{key='field:'..tostring(uid),uid=uid,state=record.State,traitsKnown=traitsKnown,category=record.AssetCategory,areaKey=record.AreaId,nestId=record.NestId,worldPos=typeof(record.BottomCFrame)=='CFrame' and record.BottomCFrame.Position or nil,area=tostring(record.AreaId)..' | Mut: '..(#traits>0 and table.concat(traits,', ') or traitsKnown and 'None' or 'UNKNOWN'),model=model,icon=asset.Icon,name=asset.DisplayName or record.AssetCategory or 'Unknown',rarity=rarity.DisplayName or rarity._id or 'Unknown',tier=tonumber(rarity.Rank) or 0,color=typeof(rarity.Color)=='Color3' and rarity.Color or Color3.new(1,1,1),scale=scale,weight=weight,rate=rate,estimated=estimated})
                end
            end
            -- One numeric value drives both display and ordering.
            for _,entry in ipairs(eggs) do
                entry.rate=entry.rate or entry.unmutatedRate
            end
            for _,entry in ipairs(eggs) do
                entry.mutationText=tostring(entry.area or ''):match('Mut:%s*(.*)') or ''
            end
            latestEntries=eggs
            latestMetadata={states=fieldStates,resetAt=resetAt,scanAt=scanAt,scanClock=scanStartedClock}
            lastScan=os.clock()
        end)
        if not ok then warn('NYX Finder scan:',err) end
        task.wait(1)
    end
end
 task.spawn(function()
    local attempt = 0
    while alive do
        attempt += 1
        local ok,err = pcall(run)
        if ok then return end

        warn('NYX Finder startup attempt '..tostring(attempt)..': '..tostring(err))
        if startupNotice and startupNotice.Parent then
            if finderCreating then
                startupNotice.Text = 'MARVIN STARTUP ERROR • '..tostring(err):sub(1, 140)
                break
            end
            startupNotice.Text = 'MARVIN • WAITING FOR GAME MODULES (RETRY '..tostring(attempt)..')'
        end
        task.wait(math.min(8, 1 + attempt))
    end
end)
end

--============================================================================--
--  [7] KEY GATE - glass key window. Validates against the Cloudflare endpoint,
--      caches accepted keys locally and rechecks them while the Finder runs.
--============================================================================--
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
if not game:IsLoaded() then
    game.Loaded:Wait()
end
local player = Players.LocalPlayer
local playerDeadline = os.clock() + 60
while not player and os.clock() < playerDeadline do
    task.wait(0.1)
    player = Players.LocalPlayer
end
if not player then return end
local VERIFY_URL = "https://unknown.unknownsystem.workers.dev/validate"


local function launchUnknown()
    local runtimeEnv = _G
    pcall(function()
        if type(getgenv) == "function" then runtimeEnv = getgenv() end
    end)
    local runningJob = "__UNKNOWN_RUNNING_JOB"
    if type(runtimeEnv) == "table" and runtimeEnv[runningJob] == game.JobId then return end
    if type(runtimeEnv) == "table" then runtimeEnv[runningJob] = game.JobId end

    local loadOk, loadError = pcall(startUnknown)
    if not loadOk then
        if type(runtimeEnv) == "table" then runtimeEnv[runningJob] = nil end
        warn("[UNKNOWN] Finder startup failed: " .. tostring(loadError))
    end
end

local function httpRequest(options)
    local req = request or http_request or (syn and syn.request)
    if type(req) == "function" then
        return req(options)
    end
    error("Your executor does not expose a supported HTTP request function.")
end

--== Key gate window: a centered glass card with a gradient border ==--
local Tweens = game:GetService("TweenService")

local gui = Instance.new("ScreenGui")
gui.Name = "UNKNOWN_KeySystem"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1100

local parent
pcall(function()
    if type(gethui) == "function" then parent = gethui() end
end)
if not parent then
    parent = player:WaitForChild("PlayerGui", 60)
end
assert(parent, "Key UI could not find a GUI parent")
gui.Parent = parent

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.fromOffset(356, 230)
frame.Position = UDim2.new(0.5, -178, 0.5, -115)
frame.BackgroundColor3 = Color3.fromRGB(12, 9, 24)
frame.BackgroundTransparency = 0.04
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(147, 92, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.18
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = frame

local strokeGradient = Instance.new("UIGradient")
strokeGradient.Rotation = 55
strokeGradient.Color = ColorSequence.new(Color3.fromRGB(147, 92, 255), Color3.fromRGB(56, 205, 255))
strokeGradient.Parent = stroke

local frameSheen = Instance.new("UIGradient")
frameSheen.Rotation = 95
frameSheen.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 138, 190))
frameSheen.Parent = frame

-- Soft purple ring hugging the outside edge of the card.
local edgeGlow = Instance.new("Frame")
edgeGlow.Name = "EdgeGlow"
edgeGlow.BackgroundTransparency = 1
edgeGlow.BorderSizePixel = 0
edgeGlow.Position = UDim2.fromOffset(-4, -4)
edgeGlow.Size = UDim2.new(1, 8, 1, 8)
edgeGlow.ZIndex = 0
edgeGlow.Active = false
edgeGlow.Parent = frame

local edgeGlowCorner = Instance.new("UICorner")
edgeGlowCorner.CornerRadius = UDim.new(0, 20)
edgeGlowCorner.Parent = edgeGlow

local edgeGlowStroke = Instance.new("UIStroke")
edgeGlowStroke.Color = Color3.fromRGB(147, 92, 255)
edgeGlowStroke.Thickness = 6
edgeGlowStroke.Transparency = 0.84
edgeGlowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
edgeGlowStroke.Parent = edgeGlow

-- Title + fading accent underline + centered subtitle.
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 34)
title.Position = UDim2.fromOffset(12, 14)
title.BackgroundTransparency = 1
title.Text = "MARVIN"
title.TextColor3 = Color3.fromRGB(246, 242, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Center
title.Parent = frame

local titleGradient = Instance.new("UIGradient")
titleGradient.Rotation = 0
titleGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 164, 255))
titleGradient.Parent = title

local underline = Instance.new("Frame")
underline.Name = "TitleUnderline"
underline.BorderSizePixel = 0
underline.BackgroundColor3 = Color3.fromRGB(147, 92, 255)
underline.Position = UDim2.new(0.5, -52, 0, 52)
underline.Size = UDim2.fromOffset(104, 2)
underline.Active = false
underline.Parent = frame

local underlineCorner = Instance.new("UICorner")
underlineCorner.CornerRadius = UDim.new(1, 0)
underlineCorner.Parent = underline

local underlineGradient = Instance.new("UIGradient")
underlineGradient.Rotation = 0
underlineGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.5, 0),
    NumberSequenceKeypoint.new(1, 1),
})
underlineGradient.Parent = underline

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -24, 0, 20)
subtitle.Position = UDim2.fromOffset(12, 60)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Enter your access key to continue"
subtitle.TextColor3 = Color3.fromRGB(172, 160, 202)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Center
subtitle.Parent = frame

-- Glass input field; the border lights up cyan while focused.
local keyBox = Instance.new("TextBox")
keyBox.Size = UDim2.new(1, -40, 0, 42)
keyBox.Position = UDim2.fromOffset(20, 92)
keyBox.BackgroundColor3 = Color3.fromRGB(24, 17, 44)
keyBox.BackgroundTransparency = 0.08
keyBox.BorderSizePixel = 0
keyBox.PlaceholderText = "TF-XXXX-XXXX"
keyBox.PlaceholderColor3 = Color3.fromRGB(126, 116, 152)
keyBox.Text = ""
keyBox.TextColor3 = Color3.fromRGB(246, 242, 255)
keyBox.Font = Enum.Font.GothamBold
keyBox.TextSize = 14
keyBox.ClearTextOnFocus = false
keyBox.Parent = frame

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 10)
boxCorner.Parent = keyBox

local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(147, 92, 255)
boxStroke.Thickness = 1
boxStroke.Transparency = 0.45
boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
boxStroke.Parent = keyBox

keyBox.Focused:Connect(function()
    boxStroke.Color = Color3.fromRGB(56, 205, 255)
    boxStroke.Transparency = 0.05
end)
keyBox.FocusLost:Connect(function()
    boxStroke.Color = Color3.fromRGB(147, 92, 255)
    boxStroke.Transparency = 0.45
end)

-- Gradient call-to-action with a subtle hover/press scale.
local verifyButton = Instance.new("TextButton")
verifyButton.Size = UDim2.new(1, -40, 0, 40)
verifyButton.Position = UDim2.fromOffset(20, 146)
verifyButton.BackgroundColor3 = Color3.fromRGB(120, 62, 220)
verifyButton.BorderSizePixel = 0
verifyButton.Text = "VERIFY KEY"
verifyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
verifyButton.Font = Enum.Font.GothamBold
verifyButton.TextSize = 14
verifyButton.AutoButtonColor = false
verifyButton.Parent = frame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 10)
buttonCorner.Parent = verifyButton

local buttonGradient = Instance.new("UIGradient")
buttonGradient.Rotation = 25
buttonGradient.Color = ColorSequence.new(Color3.fromRGB(168, 85, 247), Color3.fromRGB(124, 58, 237))
buttonGradient.Parent = verifyButton

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(213, 96, 255)
buttonStroke.Thickness = 1
buttonStroke.Transparency = 0.35
buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
buttonStroke.Parent = verifyButton

local buttonScale = Instance.new("UIScale")
buttonScale.Scale = 1
buttonScale.Parent = verifyButton

verifyButton.MouseEnter:Connect(function()
    Tweens:Create(buttonScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.03}):Play()
end)
verifyButton.MouseLeave:Connect(function()
    Tweens:Create(buttonScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
end)
verifyButton.MouseButton1Down:Connect(function()
    Tweens:Create(buttonScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.97}):Play()
end)
verifyButton.MouseButton1Up:Connect(function()
    Tweens:Create(buttonScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.03}):Play()
end)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -40, 0, 20)
status.Position = UDim2.fromOffset(20, 194)
status.BackgroundTransparency = 1
status.Text = "Waiting for key..."
status.TextColor3 = Color3.fromRGB(172, 160, 202)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Center
status.Parent = frame

-- Entrance: a short Back-eased pop.
local introScale = Instance.new("UIScale")
introScale.Scale = 0.92
introScale.Parent = frame
Tweens:Create(introScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

local busy = false

local function setStatus(message, color)
    status.Text = message
    status.TextColor3 = color or Color3.fromRGB(160, 160, 175)
end

local function verifyKey()
    if busy then return end

    local key = keyBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then
        setStatus("Please enter your key.", Color3.fromRGB(255, 190, 90))
        return
    end

    busy = true
    verifyButton.Text = "CHECKING..."
    setStatus("Checking key with server...")

    local ok, response = pcall(function()
        return httpRequest({
            Url = VERIFY_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode({ key = key })
        })
    end)

    if not ok or type(response) ~= "table" then
        setStatus("Connection failed. Try again.", Color3.fromRGB(255, 100, 100))
        verifyButton.Text = "VERIFY KEY"
        busy = false
        return
    end

    local body = response.Body or response.body or ""
    local decodedOk, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if not decodedOk or type(data) ~= "table" or data.valid ~= true then
        local reason = decodedOk and data.reason == "expired" and "Key expired." or "Invalid or revoked key."
        setStatus(reason, Color3.fromRGB(255, 100, 100))
        verifyButton.Text = "VERIFY KEY"
        busy = false
        return
    end

    -- Remember the key locally only after the server confirms it is valid.
    if type(writefile) == "function" then
        pcall(function() writefile("unknown_saved_access_key.txt", key) end)
    end

    setStatus("Key accepted. Loading UNKNOWN...", Color3.fromRGB(100, 220, 140))
    verifyButton.Text = "ACCEPTED"

    task.wait(0.35)
    gui:Destroy()

    launchUnknown()

    -- Revalidate the active key while UNKNOWN is running.
    -- Explicit invalid/expired responses close the Finder; transient network errors do not.
    task.spawn(function()
        while true do
            task.wait(60)
            local requestOk, checkResponse = pcall(function()
                return httpRequest({
                    Url = VERIFY_URL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode({ key = key })
                })
            end)
            if requestOk and type(checkResponse) == "table" then
                local checkBody = checkResponse.Body or checkResponse.body or ""
                local checkDecoded, checkData = pcall(function()
                    return HttpService:JSONDecode(checkBody)
                end)
                if checkDecoded and type(checkData) == "table" and checkData.valid ~= true then
                    local env = _G
                    pcall(function()
                        if type(getgenv) == "function" then env = getgenv() end
                    end)
                    if type(env) == "table" and type(env.__UNKNOWN_STOP_ACTIVE) == "function" then
                        pcall(env.__UNKNOWN_STOP_ACTIVE)
                    end
                    if type(delfile) == "function" then
                        pcall(function() delfile("unknown_saved_access_key.txt") end)
                    end
                    break
                end
            end
        end
    end)
end

verifyButton.MouseButton1Click:Connect(verifyKey)

-- Reuse the saved key on the next execution, but always revalidate it online.
if type(readfile) == "function" then
    local savedKey
    pcall(function() savedKey = readfile("unknown_saved_access_key.txt") end)
    if type(savedKey) == "string" and savedKey:gsub("%s+", "") ~= "" then
        keyBox.Text = savedKey
        task.defer(verifyKey)
    end
end
