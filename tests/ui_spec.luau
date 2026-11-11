-- Actual-source UI/input regression tests. These simulate signals and geometry,
-- not Roblox rendering, hit testing, device drivers or live executor behavior.
local function named(name)
    local obj=state.playerGui:FindFirstChild(name,true);expect(obj~=nil,'Missing UI object '..name);return obj
end
local function boot(options)
    options=options or {}
    if options.tracked==nil then options.tracked=false end
    if options.autoSteal==nil then options.autoSteal=false end
    if options.keyDelay==nil then options.keyDelay=20 end
    if options.width==nil then options.width=1280 end
    if options.height==nil then options.height=1000 end
    if options.touch==nil then options.touch=false end
    reset(options);executeScript();Scheduler.advance(0.1)
    return named('UNKNOWN'),named('ObsidianPanel'),named('DragHeader')
end
local function listeners(sig)
    local n=0;for _,entry in ipairs(sig.listeners)do if entry.connection.Connected then n+=1 end end;return n
end
local function beginDrag(panel,header,kind)
    local p=panel.AbsolutePosition
    local input=state.input(kind or 'MouseButton1',p.X+42,p.Y+28)
    header.InputBegan:Fire(input)
    return input
end
local function move(input,x,y)
    if input.UserInputType==Enum.UserInputType.Touch then input.Position=Vector3.new(x,y,0);state.services.UserInputService.InputChanged:Fire(input)
    else state.services.UserInputService.InputChanged:Fire(state.input('MouseMovement',x,y)) end
end
local function inside(obj,container)
    local p,s,c,cs=obj.AbsolutePosition,obj.AbsoluteSize,container.AbsolutePosition,container.AbsoluteSize
    expect(p.X>=c.X-0.01 and p.Y>=c.Y-0.01 and p.X+s.X<=c.X+cs.X+0.01 and p.Y+s.Y<=c.Y+cs.Y+0.01,obj.Name..' is outside '..container.Name)
end
local function overlap(a,b)
    local ap,as,bp,bs=a.AbsolutePosition,a.AbsoluteSize,b.AbsolutePosition,b.AbsoluteSize
    return ap.X<bp.X+bs.X-0.01 and ap.X+as.X>bp.X+0.01 and ap.Y<bp.Y+bs.Y-0.01 and ap.Y+as.Y>bp.Y+0.01
end
local function cards()
    local result={};for _,obj in ipairs(named('EggFeed'):GetChildren())do if obj.Name=='EggCard'then result[#result+1]=obj end end
    table.sort(result,function(a,b)return a.LayoutOrder<b.LayoutOrder end);return result
end
local function title(card)
    for _,obj in ipairs(card:GetChildren())do if obj:IsA('TextLabel')and obj.Position.Y.Offset==12 then return obj.Text end end
end
local function settingWrites()
    local n=0;for _,entry in ipairs(state.writes)do if entry.path=='tenshi_beta_ui.json'then n+=1 end end;return n
end

test('first launch centers the scaled whole window inside the safe area',function()
    for _,spec in ipairs({{1366,1000,100,false},{1600,1200,150,false},{390,844,150,true},{844,320,150,true}})do
        local gui,panel=boot({width=spec[1],height=spec[2],sizePercent=spec[3],touch=spec[4],insetX=19,insetY=36})
        near(panel.AnchorPoint.X,0);near(panel.AnchorPoint.Y,0)
        near(panel.AbsolutePosition.X,19+(spec[1]-panel.AbsoluteSize.X)/2)
        near(panel.AbsolutePosition.Y,36+(spec[2]-panel.AbsoluteSize.Y)/2)
        expect(gui:GetAttribute('UnknownWindowDragging')==false);inside(panel,gui)
    end
end)
test('mouse press has no jump; movement uses screen delta, not scaled delta',function()
    local gui,panel,header=boot({width=1600,height=1200,sizePercent=150,insetX=21,insetY=43})
    local p=panel.AbsolutePosition;local input=beginDrag(panel,header)
    expect(gui:GetAttribute('UnknownWindowDragging'));near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y)
    move(input,input.Position.X+73,input.Position.Y+21)
    near(panel.AbsolutePosition.X,p.X+73);near(panel.AbsolutePosition.Y,p.Y+21)
    state.services.UserInputService.InputEnded:Fire(input)
    expect(gui:GetAttribute('UnknownWindowDragging')==false)
    move(input,1500,1100);near(panel.AbsolutePosition.X,p.X+73);near(panel.AbsolutePosition.Y,p.Y+21)
end)
test('touch tracks only the captured finger and ends immediately on its own state',function()
    local gui,panel,header=boot({width=1000,height=1000,touch=true})
    local p=panel.AbsolutePosition;local input=beginDrag(panel,header,'Touch');local second=state.input('Touch',1,1)
    state.services.UserInputService.InputChanged:Fire(second);state.services.UserInputService.InputEnded:Fire(second)
    near(panel.AbsolutePosition.X,p.X);expect(gui:GetAttribute('UnknownWindowDragging'))
    move(input,input.Position.X+47,input.Position.Y+32)
    near(panel.AbsolutePosition.X,p.X+47);near(panel.AbsolutePosition.Y,p.Y+32)
    input.UserInputState=Enum.UserInputState.End
    expect(gui:GetAttribute('UnknownWindowDragging')==false)
    move(input,999,999);near(panel.AbsolutePosition.X,p.X+47)
    expect(listeners(input:GetPropertyChangedSignal('UserInputState'))==0)
end)
test('clamps all four edges without changing the pointer offset or anchor',function()
    local gui,panel,header=boot();local input=beginDrag(panel,header)
    move(input,-1e6,-1e6);near(panel.Position.X.Offset,12);near(panel.Position.Y.Offset,12);inside(panel,gui)
    move(input,1e6,1e6);near(panel.Position.X.Offset,gui.AbsoluteSize.X-panel.AbsoluteSize.X-12)
    near(panel.Position.Y.Offset,gui.AbsoluteSize.Y-panel.AbsoluteSize.Y-12);inside(panel,gui)
    state.services.UserInputService.InputEnded:Fire(input)
    local before=panel.AbsolutePosition;local again=beginDrag(panel,header)
    near(panel.AbsolutePosition.X,before.X);near(panel.AbsolutePosition.Y,before.Y)
    move(again,again.Position.X-7,again.Position.Y-9)
    near(panel.AbsolutePosition.X,before.X-7);near(panel.AbsolutePosition.Y,before.Y-9)
end)
test('right click, keyboard, body input and a second drag never replace capture',function()
    local gui,panel,header=boot();local p=panel.AbsolutePosition
    for _,kind in ipairs({'MouseButton2','Keyboard','Gamepad1'})do header.InputBegan:Fire(state.input(kind,20,20)) end
    panel.InputBegan:Fire(state.input('MouseButton1',20,20));expect(not gui:GetAttribute('UnknownWindowDragging'))
    local input=beginDrag(panel,header)
    header.InputBegan:Fire(state.input('Touch',2,2));move(input,input.Position.X+12,input.Position.Y+13)
    near(panel.AbsolutePosition.X,p.X+12);near(panel.AbsolutePosition.Y,p.Y+13)
end)
test('release by global mouse-up, cancellation, focus loss and hiding all stop capture',function()
    local gui,panel,header=boot();local input=beginDrag(panel,header)
    state.services.UserInputService.InputEnded:Fire(state.input('MouseButton1',0,0));expect(not gui:GetAttribute('UnknownWindowDragging'))
    input=beginDrag(panel,header,'Touch');input.UserInputState=Enum.UserInputState.Cancel;expect(not gui:GetAttribute('UnknownWindowDragging'))
    input=beginDrag(panel,header);state.services.UserInputService.WindowFocusReleased:Fire();expect(not gui:GetAttribute('UnknownWindowDragging'))
    input=beginDrag(panel,header);named('MinimizeButton').Activated:Fire();expect(not gui:GetAttribute('UnknownWindowDragging'))
    local p=panel.AbsolutePosition;move(input,900,900);near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y)
end)
test('drag saves once on release, restores persisted pixels and rejects invalid coordinates',function()
    local _,panel,header=boot();local n=settingWrites();local input=beginDrag(panel,header)
    move(input,input.Position.X+64,input.Position.Y+30);expect(settingWrites()==n,'Wrote settings during pointer movement')
    local x,y=panel.Position.X.Offset,panel.Position.Y.Offset
    state.services.UserInputService.InputEnded:Fire(input);expect(settingWrites()==n+1)
    local settings=state.http:JSONDecode(state.files['tenshi_beta_ui.json']);near(settings.windowPosition.x,x);near(settings.windowPosition.y,y)
    _G.__UNKNOWN_STOP_ACTIVE();state.options.keyDelay=0.02;executeScript();Scheduler.advance(0.2)
    panel=named('ObsidianPanel');near(panel.Position.X.Offset,x);near(panel.Position.Y.Offset,y)
    local gui
    gui,panel=boot({windowPosition={x=1e300,y=-1e300}});inside(panel,gui);near(panel.Position.Y.Offset,12)
    gui,panel=boot({windowPosition={x='invalid',y=0}});near(panel.Position.X.Offset,(gui.AbsoluteSize.X-panel.AbsoluteSize.X)/2)
end)
test('refreshes, scans, settings, scope, animations and hide/show preserve placement and size',function()
    local gui,panel,header=boot();local input=beginDrag(panel,header)
    move(input,input.Position.X+61,input.Position.Y+29);state.services.UserInputService.InputEnded:Fire(input)
    local x,y,w,h=panel.Position.X.Offset,panel.Position.Y.Offset,panel.AbsoluteSize.X,panel.AbsoluteSize.Y
    local writes=0;panel:GetPropertyChangedSignal('Position'):Connect(function()writes+=1 end)
    named('Refresh').Activated:Fire();named('AllServers').Activated:Fire();named('MyServer').Activated:Fire()
    named('SettingsButton').Activated:Fire();named('reducedMotionToggle').Activated:Fire();named('SettingsClose').Activated:Fire()
    Scheduler.advance(1.5);named('MinimizeButton').Activated:Fire();Scheduler.advance(0.3);named('UNKNOWNLauncher').Activated:Fire();Scheduler.advance(0.3)
    near(panel.Position.X.Offset,x);near(panel.Position.Y.Offset,y);near(panel.AbsoluteSize.X,w);near(panel.AbsoluteSize.Y,h)
    expect(writes==0,'A non-layout refresh wrote the window position');inside(panel,gui)
end)
test('viewport changes clamp only when needed, retain interior pixels and invalidate an old gesture',function()
    local gui,panel,header=boot({windowPosition={x=120,y=55}})
    state.resize(1500,1100);near(panel.Position.X.Offset,120);near(panel.Position.Y.Offset,55)
    local input=beginDrag(panel,header);state.resize(600,500)
    expect(not gui:GetAttribute('UnknownWindowDragging'));inside(panel,gui)
    local p=panel.AbsolutePosition;move(input,1000,1000);near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y)
    state.resize(600,500);near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y)
end)
test('title drag overlays do not intersect buttons and every button retains an action',function()
    local gui,panel,header=boot()
    for _,name in ipairs({'MinimizeButton','Refresh'})do expect(not overlap(header,named(name)),name..' is covered by drag overlay') end
    for _,obj in ipairs(gui:GetDescendants())do
        if obj:IsA('GuiButton')then
            expect(listeners(obj.Activated)>0,'Decorative or disconnected button '..obj.Name)
            local input=state.input('Touch',0,0);obj.InputBegan:Fire(input)
            expect(not gui:GetAttribute('UnknownWindowDragging'),'Button began a window drag: '..obj.Name)
            state.services.UserInputService.InputEnded:Fire(input)
        end
    end
    named('SettingsButton').Activated:Fire();local sheetHeader=named('SettingsDragHeader')
    local p=panel.AbsolutePosition;local input=beginDrag(panel,sheetHeader,'Touch')
    move(input,input.Position.X+20,input.Position.Y+12);near(panel.AbsolutePosition.X,p.X+20)
    state.services.UserInputService.InputEnded:Fire(input);expect(named('SettingsSheet').Visible)
    named('SettingsClose').Activated:Fire();expect(not named('SettingsSheet').Visible)
end)
test('portrait, landscape and oversized desktop settings keep readable nonoverlapping actions',function()
    for _,spec in ipairs({{320,640,true,100},{390,844,true,150},{844,390,true,100},{844,320,true,100},{1280,320,false,150},{600,390,false,150},{1920,1080,false,150},{1280,720,false,70}})do
        local gui,panel,header=boot({width=spec[1],height=spec[2],touch=spec[3],sizePercent=spec[4]})
        inside(panel,gui);expect(named('EggFeed').AbsoluteSize.Y>=40,'Feed collapsed for '..spec[1]..'x'..spec[2])
        local controls={'AutoStealMain','AutoJoinMain','SettingsButton','AllServers','MyServer','Refresh','MinimizeButton'}
        for _,name in ipairs(controls)do local b=named(name);inside(b,panel);expect(b.AbsoluteSize.Y>=(spec[3] and 44 or 36),name..' has a short hit target') end
        expect(not overlap(named('AutoStealMain'),named('AutoJoinMain')));expect(not overlap(named('AllServers'),named('MyServer')))
        expect(not overlap(named('EggFeed'),named('ThumbDock')));expect(not overlap(header,named('Refresh')))
        local card=cards()[1];expect(card~=nil)
        expect(not overlap(card:FindFirstChild('FindEggButton'),card:FindFirstChild('EggActionButton')))
        inside(card:FindFirstChild('FindEggButton'),card);inside(card:FindFirstChild('EggActionButton'),card)
    end
end)
test('desktop size controls retain top-left placement and mobile ignores shrink preferences',function()
    local _,panel=boot({width=1600,height=1200,windowPosition={x=90,y=22}})
    named('IncreaseSize').Activated:Fire();near(panel.Position.X.Offset,90);near(panel.Position.Y.Offset,22)
    expect(panel.AbsoluteSize.X>402)
    named('DecreaseSize').Activated:Fire();near(panel.AbsoluteSize.X,402)
    local _,mobile=boot({width=390,height=844,touch=true,sizePercent=70});local w=mobile.AbsoluteSize.X
    named('IncreaseSize').Activated:Fire();near(mobile.AbsoluteSize.X,w)
end)
test('the original launcher can be dragged without accidental reopen and remembers its location',function()
    local gui,panel=boot();named('MinimizeButton').Activated:Fire();Scheduler.advance(0.3)
    local launcher=named('UNKNOWNLauncher');local p=launcher.AbsolutePosition
    local input=state.input('Touch',p.X+20,p.Y+20);launcher.InputBegan:Fire(input)
    move(input,input.Position.X-90,input.Position.Y-30);state.services.UserInputService.InputEnded:Fire(input)
    launcher.Activated:Fire();expect(launcher.Visible and not panel.Visible,'Drag was interpreted as a launcher click')
    local settings=state.http:JSONDecode(state.files['tenshi_beta_ui.json']);near(settings.launcherPosition.x,launcher.Position.X.Offset)
    inside(launcher,gui);Scheduler.advance(0.5);launcher.Activated:Fire();expect(panel.Visible and not launcher.Visible)
end)
test('space animation is bounded, background-only, reduced-motion aware and paused when hidden',function()
    local gui,panel=boot();local backdrop=named('SpaceBackdrop');local cloud=backdrop:FindFirstChild('NebulaCloud')
    local counts={NebulaCloud=0,SpaceStar=0,SpaceParticle=0};for _,obj in ipairs(backdrop:GetChildren())do if counts[obj.Name]then counts[obj.Name]+=1 end end
    expect(counts.NebulaCloud==3 and counts.SpaceStar==22 and counts.SpaceParticle==6)
    local budget=#backdrop:GetDescendants();local ticks=0;cloud:GetPropertyChangedSignal('Position'):Connect(function()ticks+=1 end)
    local p=panel.AbsolutePosition;Scheduler.advance(1,1/120);expect(ticks>=16 and ticks<=21,'Unexpected background frame budget: '..ticks)
    near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y);expect(#backdrop:GetDescendants()==budget)
    named('reducedMotionToggle').Activated:Fire();Scheduler.advance(0.1);local still=ticks
    Scheduler.advance(0.5);expect(ticks==still,'Reduced motion still animates the nebula')
    named('reducedMotionToggle').Activated:Fire();Scheduler.advance(0.15);expect(ticks>still)
    named('MinimizeButton').Activated:Fire();Scheduler.advance(0.3);still=ticks;Scheduler.advance(0.5);expect(ticks==still)
    for _,tween in ipairs(state.tweens)do expect(not (tween.object==panel and tween.properties.Position),'Animated the root window') end
    expect(next(Scheduler.bindings)==nil,'Decorations added a render binding')
end)
test('all global UI signals and active per-input listeners disconnect on destruction',function()
    local gui,panel,header=boot();local input=beginDrag(panel,header,'Touch')
    local Input,Run=state.services.UserInputService,state.services.RunService
    expect(listeners(Input.InputChanged)==1 and listeners(Input.WindowFocusReleased)==1)
    executeScript();Scheduler.advance(0.1);expect(listeners(Input.InputChanged)==1,'Reinjection duplicated the input listener')
    gui:Destroy();expect(listeners(Input.InputChanged)==0 and listeners(Input.InputEnded)==0 and listeners(Input.WindowFocusReleased)==0)
    expect(listeners(input:GetPropertyChangedSignal('UserInputState'))==0);expect(listeners(Run.Heartbeat)==0)
    local p=panel.Position;move(input,400,400);expect(panel.Position==p)
    Scheduler.advance(1);expect(next(Scheduler.bindings)==nil)
end)
test('UI failures after panel ownership leave no input, perk or heartbeat owners',function()
    reset({tracked=false,autoSteal=false,speedBoost=true,infiniteJump=true,keyDelay=20})
    local original=Instance.new
    Instance.new=function(class)if class=='UIGradient'then error('Injected gradient construction failure')end;return original(class)end
    executeScript();Instance.new=original;Scheduler.advance(0.1)
    expect(state.playerGui:FindFirstChild('UNKNOWN')==nil);near(state.humanoid.WalkSpeed,16)
    expect(listeners(state.services.UserInputService.InputChanged)==0 and listeners(state.services.RunService.Heartbeat)==0)
    state.services.UserInputService.JumpRequest:Fire();expect(state.jumps==0)
end)
test('F respects focused text and processed input; hover/press effects never move the root',function()
    local gui,panel=boot();local Input=state.services.UserInputService
    local key=state.input('Keyboard',0,0);key.KeyCode=Enum.KeyCode.F
    state.focused=named('targetValueInput');Input.InputBegan:Fire(key,false);expect(panel.Visible)
    state.focused=nil;Input.InputBegan:Fire(key,true);expect(panel.Visible)
    local button=named('Refresh');local p=panel.Position;button.MouseEnter:Fire();button.MouseLeave:Fire();Scheduler.advance(0.3);expect(panel.Position==p)
    Input.InputBegan:Fire(key,false);Scheduler.advance(0.3);expect(not panel.Visible)
    Input.InputBegan:Fire(key,false);Scheduler.advance(0.3);expect(panel.Visible);expect(panel.Position==p)
end)
test('restored Discord account uses each sourced opener and a visible copy/manual fallback',function()
    local url='https://discord.com/users/1078459357185970268'
    for _,mode in ipairs({'openurl','open_url','syn','browser','clipboard','toclipboard','manual'})do
        boot({browser=mode=='browser'})
        local function accept(value)state.opened=value end
        if mode=='openurl'then openurl=accept
        elseif mode=='open_url'then openurl=function()error('Unavailable opener')end;open_url=accept
        elseif mode=='syn'then syn={open_url=accept}
        elseif mode=='clipboard'then setclipboard=function(value)state.copied=value end
        elseif mode=='toclipboard'then toclipboard=function(value)state.copied=value end end
        named('DiscordAccountButton').Activated:Fire();Scheduler.advance(0.01)
        if mode=='clipboard'or mode=='toclipboard'then expect(state.copied==url and state.notification~=nil)
        elseif mode=='manual'then expect(state.notification~=nil)
        else expect(state.opened==url,'Wrong Discord opener '..mode)end
        expect(named('DiscordProfileLink').Text==url and named('DiscordProfileLink').TextEditable==false)
        syn=nil
    end
end)
test('restored rarity callback cycles original ranks, saves them and invalidates the feed query',function()
    boot();local button=named('MinRarityButton')
    for _,rank in ipairs({6,7,8,9,10,0})do
        button.Activated:Fire();Scheduler.advance(0.1)
        expect(state.http:JSONDecode(state.files['tenshi_beta_ui.json']).minRank==rank)
        local last
        for _,req in ipairs(state.requests)do if req.url:find('/v1/eggs',1,true)then last=req.url end end
        expect(tonumber(last:match('&minRank=([^&]+)'))==rank,'Rarity query did not update')
    end
    reset({tracked=false,autoSteal=true,minRank=6,keyDelay=20})
    state.modules['Data.Assets'].Directory.TestEgg.Rarity.Rank=3;executeScript();Scheduler.advance(2)
    expect(#state.carryCalls==0 and #cards()==0,'Saved rarity did not filter local candidates')
end)
test('Top 4 is a live income-sorted view and switching back preserves the complete list',function()
    reset({tracked=false,autoSteal=false,topFourOnly=true,keyDelay=20})
    for i=2,7 do
        local kind='Type'..i;state.modules['Data.Assets'].Directory[kind]={DisplayName=kind,EarningRate=i*1e9,Rarity={DisplayName='Divine',Rank=10}}
        state.records['egg-'..i]={Uid='egg-'..i,AssetCategory=kind,AssetScale=1,Mutations={},BottomCFrame=CFrame.new(i*5,0,0),State='Slot'}
    end
    executeScript();Scheduler.advance(0.2);expect(#cards()==4)
    for i,card in ipairs(cards())do expect(title(card)=='Type'..(8-i)..' Egg','Incorrect Top 4 order')end
    named('topFourOnlyToggle').Activated:Fire();Scheduler.advance(0.1);expect(#cards()==7,'Top 4 erased the backing list')
    expect(state.http:JSONDecode(state.files['tenshi_beta_ui.json']).topFourOnly==false)
end)
test('Top 4 does not prune Auto Join candidates or the retained top-five cache',function()
    local items={}
    for i=1,5 do items[i]={placeId=42,jobId='job-'..i,uid='uid-'..i,key='key-'..i,name='Remote'..i,rarity='Divine',rank=10,
        rate=(10-i)*1e9,expiresAt=(1794355200+200)*1000,source='field',full=i<=4}end
    local previous
    for _,topOnly in ipairs({false,true})do
        reset({tracked=false,autoSteal=false,autoJoin=true,topFourOnly=topOnly,myServer=false,feedItems=items,keyDelay=20})
        state.settings.showUnavailable=true;state.files['tenshi_beta_ui.json']=state.http:JSONEncode(state.settings)
        executeScript();Scheduler.advance(0.5)
        if topOnly then expect(#cards()==4)end
        expect(#state.teleports==1 and state.teleports[1].job=='job-5','Top 4 restricted automatic selection')
        Scheduler.advance(1.1) -- preserve the existing one-second cache-write throttle
        local bytes=state.files['tenshi_beta_top5_cycle_v2.json'];local cache=state.http:JSONDecode(bytes)
        for i=1,5 do expect(cache.items['key-'..i]~=nil,'Lost a retained candidate')end
        -- Legacy retention can keep a prior local sighting beyond five entries.
        if previous then expect(previous==bytes,'Presentation changed retained cache data')end;previous=bytes
    end
end)
test('income detection still prefers model text and retains the original scale/mutation formula',function()
    reset({tracked=false,autoSteal=false,keyDelay=20})
    local model=state.world:FindFirstChild('AreaEggSlotsClient'):FindFirstChild('egg-1')
    local label=Instance.new('TextLabel');label.Text='$7.50B/s';label.Parent=model
    executeScript();Scheduler.advance(0.2)
    local found=false;for _,obj in ipairs(cards()[1]:GetChildren())do if obj:IsA('TextLabel')and obj.Text=='$7.50B/s'then found=true end end;expect(found)
    reset({tracked=false,autoSteal=false,keyDelay=20,localRate=100})
    state.records['egg-1'].AssetScale=6;state.records['egg-1'].Mutations={Gold=true};state.modules['Shared.Modules.Mutations'].EarningsFor=function()return 3 end
    executeScript();Scheduler.advance(0.2)
    local snapshot
    for _,req in ipairs(state.requests)do if req.url:find('/v1/report',1,true)then snapshot=state.http:JSONDecode(req.body);break end end
    expect(snapshot and #snapshot.eggs==1);near(snapshot.eggs[1].rate,100*(6/5)^1.2*19.637875755794113*3,1e-6)
    expect(snapshot.eggs[1].mutations=='Gold')
end)
test('VERIFY KEY button and Enter submit the unchanged online gate and clean its visuals',function()
    for _,enter in ipairs({false,true})do
        reset({cold=true,tracked=false,autoSteal=false,keyDelay=0.05});state.files['unknown_saved_access_key.txt']=nil
        executeScript();Scheduler.advance(0.01);local gate=named('UNKNOWN_KeySystem');local Run=state.services.RunService
        expect(listeners(Run.Heartbeat)==1);local input=named('AccessKeyInput');input.Text=' TEST-KEY '
        if enter then input.FocusLost:Fire(true)else named('VerifyKeyButton').Activated:Fire()end
        Scheduler.advance(0.2);expect(gate.Parent==nil and named('UNKNOWN')~=nil)
        local n=0;for _,req in ipairs(state.requests)do if req.url:find('/validate',1,true)then n+=1;expect(state.http:JSONDecode(req.body).key=='TEST-KEY')end end;expect(n==1)
        for _,entry in ipairs(gate._signals['property:AbsoluteSize'].listeners)do expect(not entry.connection.Connected)end
        for _,tween in ipairs(state.tweens)do if tween.object.Name=='AccessCard'then expect(tween.cancelled)end end
    end
end)
test('empty, invalid and double-clicked keys cannot launch Finder or duplicate verification',function()
    reset({cold=true,tracked=false,autoSteal=false,keyDelay=0.4,invalidKey=true});state.files['unknown_saved_access_key.txt']=nil
    executeScript();Scheduler.advance(0.01);local button=named('VerifyKeyButton')
    button.Activated:Fire();expect(#state.requests==0,'Empty key was submitted')
    named('AccessKeyInput').Text='BAD-KEY';button.Activated:Fire();button.Activated:Fire()
    expect(#state.requests==1);Scheduler.advance(0.5);expect(state.playerGui:FindFirstChild('UNKNOWN')==nil);expect(button.Text=='VERIFY KEY')
    expect(state.files['unknown_saved_access_key.txt']==nil)
end)
test('remaining size, speed and settings callbacks are real and preserve user configuration',function()
    boot();named('IncreaseSpeed').Activated:Fire();local s=state.http:JSONDecode(state.files['tenshi_beta_ui.json']);expect(s.boostSpeed==26)
    named('DecreaseSpeed').Activated:Fire();named('speedBoostToggle').Activated:Fire();near(state.humanoid.WalkSpeed,24)
    named('infiniteJumpToggle').Activated:Fire();state.services.UserInputService.JumpRequest:Fire();expect(state.jumps==1)
    named('showUnavailableToggle').Activated:Fire();named('webhookEnabledToggle').Activated:Fire()
    named('AutoExecuteToggle').Activated:Fire();expect(named('UNKNOWN'):GetAttribute('UnknownAutoExecuteStatus')=='disabled')
    s=state.http:JSONDecode(state.files['tenshi_beta_ui.json']);expect(s.showUnavailable and s.webhookEnabled and s.infiniteJump and not s.autoExecute)
end)

test('destroying only the main window tears down its host and all background owners',function()
    local gui,panel,header=boot();local input=beginDrag(panel,header,'Touch')
    panel:Destroy();expect(listeners(state.services.UserInputService.InputChanged)==0)
    expect(listeners(input:GetPropertyChangedSignal('UserInputState'))==0)
    Scheduler.advance(0.1);expect(gui.Parent==nil and listeners(state.services.RunService.Heartbeat)==0)
    expect(_G.__UNKNOWN_STOP_ACTIVE==nil and _G.__UNKNOWN_RUNNING_JOB==nil)
end)
test('focus loss releases pressed button scale without moving the window',function()
    local _,panel=boot();local button=named('Refresh');local p=panel.Position
    button.InputBegan:Fire(state.input('MouseButton1',0,0));Scheduler.advance(0.12)
    expect(button:FindFirstChildOfClass('UIScale').Scale<1)
    state.services.UserInputService.WindowFocusReleased:Fire();Scheduler.advance(0.2)
    near(button:FindFirstChildOfClass('UIScale').Scale,1);expect(panel.Position==p)
end)

test('returning the pointer exactly to its starting offset restores the window, including after a clamp',function()
    for _,kind in ipairs({'MouseButton1','Touch'})do
        local _,panel,header=boot();local p=panel.AbsolutePosition;local input=beginDrag(panel,header,kind)
        local x,y=input.Position.X,input.Position.Y
        move(input,x+70,y+33);move(input,x,y);near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y)
        move(input,-1e6,-1e6);move(input,x,y);near(panel.AbsolutePosition.X,p.X);near(panel.AbsolutePosition.Y,p.Y)
        state.services.UserInputService.InputEnded:Fire(input)
    end
end)

print(tostring(passed)..' UI/input groups passed')
