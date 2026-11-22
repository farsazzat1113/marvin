-- Performance harness (deterministic simulation). Metrics use the mock scheduler's
-- simulated time, NOT wall-clock or real Roblox numbers. Bounds are enforced only
-- when the composition sets PERF_ENFORCE=true (run.py); baseline capture runs without it.
local enforce = PERF_ENFORCE == true
local missingSleeps = 0
local coldReadyS, coldValidate, hopReadyS, hopValidateAtReady, hopValidateBy2s, hopSlowReadyS = 0, 0, 0, 0, 0, -1
local missingLateSleeps, missingRequireCalls = 0, 0
local function metric(suite, values)
    local parts = {}
    for key, value in pairs(values) do parts[#parts + 1] = key .. '=' .. tostring(value) end
    table.sort(parts)
    print('METRIC ' .. suite .. ' ' .. table.concat(parts, ' '))
end
local function boot(options)
    options = options or {}
    if options.autoSteal == nil then options.autoSteal = false end
    if options.keyDelay == nil then options.keyDelay = 0.02 end
    if options.width == nil then options.width = 1280 end
    if options.height == nil then options.height = 1000 end
    reset(options); executeScript(); Scheduler.advance(0.1)
    return state.playerGui:FindFirstChild('UNKNOWN', true)
end
local function resetCounters()
    state.requests = {}; state.metrics.instances = 0; state.metrics.propWrites = {}; Scheduler.sleeps = 0
end
local function countRequests(substring)
    local n = 0
    for _, r in ipairs(state.requests) do if r.url:find(substring, 1, true) then n += 1 end end
    return n
end
local function headRequests()
    local n = 0
    for _, r in ipairs(state.requests) do
        if r.url:find('/v1/eggs', 1, true) and (tonumber(r.url:match('&offset=(%d+)')) or 0) == 0 then n += 1 end
    end
    return n
end
local function pageRequests()
    local n = 0
    for _, r in ipairs(state.requests) do
        if r.url:find('/v1/eggs', 1, true) and (tonumber(r.url:match('&offset=(%d+)')) or 0) > 0 then n += 1 end
    end
    return n
end
local function textWrites()
    local n = 0
    for bucket, count in pairs(state.metrics.propWrites) do
        if bucket == 'TextLabel.Text' or bucket == 'TextButton.Text' then n += count end
    end
    return n
end
local function attrWrites()
    return (state.metrics.propWrites['ScreenGui.Attribute']) or 0
end
local function named(name)
    local obj = state.playerGui:FindFirstChild(name, true); expect(obj ~= nil, 'Missing UI object ' .. name); return obj
end
local function cardTitles()
    local seen = {}
    for _, obj in ipairs(named('EggFeed'):GetChildren()) do
        if obj.Name == 'EggCard' then
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA('TextLabel') and child.Position.Y.Offset == 12 then seen[child.Text] = true end
            end
        end
    end
    return seen
end
local function hideWindow() named('MinimizeButton').Activated:Fire(); Scheduler.advance(0.4) end
local function showWindow() named('UNKNOWNLauncher').Activated:Fire(); Scheduler.advance(0.4) end

-- S1 COLD: first launch (no hop ticket) — gate, auto-submit saved key, then startup.
do
    local options = {cold = true, myServer = false, autoSteal = false, keyDelay = 0.02, width = 1280, height = 1000}
    reset(options); executeScript()
    local t0 = Scheduler.now
    while Scheduler.now - t0 < 20 do
        if state.playerGui:FindFirstChild('ObsidianPanel', true) then break end
        Scheduler.advance(0.02)
    end
    local coldReady = Scheduler.now - t0
    metric('cold_first_launch', {readyS = coldReady, validate = countRequests('/validate'), instances = state.metrics.instances, sleeps = Scheduler.sleeps})
    coldReadyS = coldReady; coldValidate = countRequests('/validate')
end

-- S2 HOP: validated hop resume — immediate startup, background revalidation.
do
    local options = {myServer = false, autoSteal = false, keyDelay = 0.02, width = 1280, height = 1000, remote = true}
    reset(options); executeScript()
    local t0 = Scheduler.now
    while Scheduler.now - t0 < 20 do
        if state.playerGui:FindFirstChild('ObsidianPanel', true) then break end
        Scheduler.advance(0.02)
    end
    local hopReady = Scheduler.now - t0
    local validateAtReady = countRequests('/validate')
    Scheduler.advance(2)
    metric('hop_resume', {readyS = hopReady, validateAtReady = validateAtReady, validateBy2s = countRequests('/validate'),
        instances = state.metrics.instances, sleeps = Scheduler.sleeps})
    hopReadyS = hopReady; hopValidateAtReady = validateAtReady; hopValidateBy2s = countRequests('/validate')
end
-- S2b: same hop with a SLOW validation service must start just as fast (non-blocking proof).
do
    local options = {myServer = false, autoSteal = false, keyDelay = 2, width = 1280, height = 1000, remote = true}
    reset(options); executeScript()
    local t0 = Scheduler.now
    while Scheduler.now - t0 < 20 do
        if state.playerGui:FindFirstChild('ObsidianPanel', true) then break end
        Scheduler.advance(0.02)
    end
    hopSlowReadyS = Scheduler.now - t0
    metric('hop_resume_slow_validate', {readyS = hopSlowReadyS, keyDelay = 2})
end

-- S3/S4/S5: steady-state 60s request/text-writes, ALL SERVERS scope, constant feed.
local function steady(suite, options, hidden)
    options.myServer = false
    if not options.noRemote then options.remote = true end
    boot(options)
    if hidden then hideWindow(); Scheduler.advance(1) end
    resetCounters(); Scheduler.advance(60)
    local m = {eggsAll = countRequests('/v1/eggs'), head = headRequests(), pages = pageRequests(),
        report = countRequests('/v1/report'), config = countRequests('Config.json'), experimental = countRequests('Experimental'),
        texts = textWrites(), sleeps = Scheduler.sleeps}
    metric(suite, m)
    return m
end
local visibleOff = steady('visible_autojoin_off', {}, false)
local visibleOn = steady('visible_autojoin_on', {autoJoin = true, remote = nil, noRemote = true}, false)
local hiddenOff = steady('hidden_autojoin_off', {repeatPage = true}, true)
local hiddenJoinPages = steady('hidden_autojoin_on_pages', {autoJoin = true, repeatPage = true}, true)
local visiblePages = steady('visible_manual_pages', {repeatPage = true}, false)

-- S6 hide/show restores an immediate head refresh (measured freshness on show).
boot({myServer = false, remote = true})
hideWindow(); Scheduler.advance(5); resetCounters()
showWindow(); Scheduler.advance(1)
local showWakeHead = headRequests()
metric('show_wake', {headWithin1s = showWakeHead})

-- S7 feed churn: changed server data must appear promptly (suppression never hides updates).
boot({myServer = false, remote = true})
Scheduler.advance(3)
resetCounters()
state.options.feedItems = {{placeId = 42, jobId = 'fresh-job', uid = 'fresh-egg', name = 'Fresh Nova', rate = 90e9,
    rank = 10, rarity = 'Divine', expiresAt = (1794355200 + 200) * 1000, key = 'fresh-key', source = 'field'}}
local freshAt, t3 = -1, 0
while t3 < 5 do
    for title in pairs(cardTitles()) do
        if title:find('Fresh Nova', 1, true) then freshAt = t3 break end
    end
    if freshAt >= 0 then break end
    Scheduler.advance(0.05); t3 += 0.05
end
local churnFresh = freshAt
metric('feed_churn_visible', {freshS = freshAt})
-- And stable feed churn: 10s of identical responses.
state.options.feedItems = nil
resetCounters(); Scheduler.advance(10)
local stableTexts = textWrites()
metric('stable_feed_10s', {texts = stableTexts, sleeps = Scheduler.sleeps, head = headRequests()})

-- S8 missing optional module: warm retry loops must stay bounded (no 10 Hz spin forever).
do
    local options = {myServer = false}
    reset(options)
    local assets = game:GetService('ReplicatedStorage'):FindFirstChild('Assets', true)
    expect(assets ~= nil, 'mock Assets module not found for missing-module scenario')
    assets.Module = nil
    expect(select(2, pcall(function() return require(assets) end)) ~= nil, 'breaking the Assets module did not break require')
    Scheduler.sleeps = 0
    local ok, err = pcall(function()
        executeScript(); Scheduler.advance(20)
        local atTwenty = Scheduler.sleeps
        Scheduler.advance(10)
        missingLateSleeps = Scheduler.sleeps - atTwenty
    end)
    local requireCalls = (Scheduler.requireCalls or {}).Assets or 0
    missingRequireCalls = requireCalls
    missingSleeps = Scheduler.sleeps
    metric('missing_module_30s', {ok = tostring(ok), sleeps = Scheduler.sleeps, late10s = missingLateSleeps,
        assetsRequires = requireCalls})
end

if enforce then
    test('hidden manual mode polls far less than visible and pages stay automation-complete', function()
        -- Bounds calibrated above measurements; see PERF.md for the method.
        expect(hiddenOff.head <= 45, 'hidden manual head polls not reduced: ' .. tostring(hiddenOff.head))
        expect(hiddenOff.pages == 0, 'hidden manual pagination should pause: ' .. tostring(hiddenOff.pages))
        expect(hiddenJoinPages.pages >= 1, 'Auto Join must keep discovering pages while hidden')
        expect(visiblePages.pages >= 1, 'visible pagination sanity')
    end)
    test('show wake refreshes immediately and churn stays fresh', function()
        expect(showWakeHead >= 1, 'no head request within 1s of showing the window')
        expect(churnFresh >= 0 and churnFresh <= 1.5, 'changed feed took too long to render')
    end)
    test('stable feed does not repaint text every 0.2s tick', function()
        expect(stableTexts <= 300, 'stable feed still churns text: ' .. tostring(stableTexts))
    end)
    test('startup never blocks on key validation and revalidates hop sessions in background', function()
        expect(coldReadyS >= 0 and coldReadyS <= 2, 'cold first launch too slow: ' .. tostring(coldReadyS))
        expect(coldValidate == 1, 'cold launch must validate exactly once before starting')
        expect(hopReadyS >= 0 and hopReadyS <= 0.5, 'validated-hop resume too slow: ' .. tostring(hopReadyS))
        expect(hopSlowReadyS >= 0 and hopSlowReadyS <= 0.5, 'hop resume blocked on slow key validation: ' .. tostring(hopSlowReadyS))
        expect(hopValidateBy2s >= 1, 'hop session never revalidated in background')
    end)
    test('missing modules back off instead of spinning at a fixed rate', function()
        expect(missingRequireCalls > 1 and missingRequireCalls <= 30, 'missing module retry count out of bounds: ' .. tostring(missingRequireCalls))
    end)
    print('5 perf-bound groups passed')
else
    print('PERF BASELINE MODE (bounds not enforced)')
end
