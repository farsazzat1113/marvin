-- Policy is extracted from UNKNOWN.lua by run.py, not a reimplementation.
test('finite bounds reject NaN, infinity and strings',function()
    expect(not Policy.finite(0/0));expect(not Policy.finite(math.huge));expect(not Policy.finite('24'))
    near(Policy.number(0/0,24,16,32),24);near(Policy.number(100,24,16,32),32)
    near(Policy.backoff(1,2,24),2);near(Policy.backoff(2,2,24),4);near(Policy.backoff(99,2,24),24)
end)
test('remote candidate policy excludes stale, same-server, taken and low-rarity reports',function()
    local egg={placeId=42,jobId='elsewhere',uid='a',rate=2e9,rank=10,expiresAt=2000}
    expect(Policy.remoteEligible(egg,1000,'here',1e9,6))
    for key,value in pairs({jobId='here',expiresAt=999,full=true,unavailable=true,takenConfirmed=true,rank=3,rate=0/0,placeId=-1,source='event'})do
        local bad=table.clone(egg);bad[key]=value;expect(not Policy.remoteEligible(bad,1000,'here',1e9,6),key)
    end
    near(Policy.joinDeadline(egg,{expiresAt=1500}),1500);near(Policy.joinDeadline(egg,{}),2000)
end)
test('webhook validation accepts only real Discord webhook endpoints',function()
    local valid='https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwx'
    expect(Policy.webhook('  '..valid..'?wait=true  ')==valid)
    for _,bad in ipairs({'http://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwx',
        valid:gsub('discord.com','discord.com.evil.example'),valid..'/../../secret',valid..'?redirect=http://localhost',
        'https://discord.com@evil.example/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwx',
        'https://discord.com/api/webhooks/1/short','https://127.0.0.1/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwx'})do
        expect(not Policy.webhook(bad),bad)
    end
end)
test('fast key resume is recent, key-bound and destination-bound',function()
    local session={version=1,key='key',verifiedAt=990,hopAt=999,fromJob='old',placeId=42,jobId='new'}
    expect(Policy.resume(session,'key',42,'new',1000))
    for key,value in pairs({key='wrong',verifiedAt=879,hopAt=954,fromJob='new',placeId=43,jobId='other',expiresAt=999})do
        local bad=table.clone(session);bad[key]=value;expect(not Policy.resume(bad,'key',42,'new',1000),key)
    end
    expect(not Policy.resume(nil,'key',42,'new',1000));expect(not Policy.resume(session,'different',42,'new',1000))
end)
test('slab collision catches rotated thin traps, boundary contact and degenerate segments',function()
    local frame=CFrame.new(5,0,0)*CFrame.Angles(0,math.pi/4,0)
    local size=Vector3.new(0.2,1,8);local padding=Vector3.new(2.1,4,2.1)
    expect(Policy.segmentHitsBox(Vector3.new(0,0,0),Vector3.new(10,0,0),frame,size,padding))
    expect(not Policy.segmentHitsBox(Vector3.new(0,0,20),Vector3.new(10,0,20),frame,size,padding))
    expect(Policy.segmentHitsBox(frame.Position,frame.Position,frame,size,padding))
    expect(not Policy.segmentHitsBox(Vector3.new(100,0,0),Vector3.new(100,0,0),frame,size,padding))
    expect(not Policy.segmentHitsBox(Vector3.new(0,20,0),Vector3.new(10,20,0),frame,size,padding))
    expect(Policy.segmentHitsBox(Vector3.new(-3,0,0),Vector3.new(3,0,0),CFrame.new(),Vector3.new(2,1,2),Vector3.new(2,1,2)))
end)
test('custom values parse raw, fractional, scientific and suffix inputs without fixed B limits',function()
    for raw,value in pairs({['2500000']=2500000,['2.5M']=2.5e6,['  $1.25b  ']=1.25e9,['.5K']=500,
        ['75B']=75e9,['2T']=2e12,['1.5Qa']=1.5e15,['3Qi']=3e18,['1e20']=1e20,['0']=0})do
        near(Policy.parseValue(raw),value,math.max(1e-6,value*1e-15))
    end
    for _,bad in ipairs({'','NaN','inf','-1','1e999','1e-999','0x10','1+2','1,000','2BB','2e','1/0','2 B X'})do
        expect(Policy.parseValue(bad)==nil,'Accepted invalid custom value: '..bad)
    end
    for _,value in ipairs({0,0.1,1234567890.123,1e20,75e9})do
        expect(Policy.parseValue(Policy.formatValue(value))==value,'Exact value formatting lost precision')
    end
end)
test('exact mode never broadens to a minimum and rejects unknown or non-finite rates',function()
    expect(Policy.valueMatches(2e9,2e9,'exact'))
    expect(not Policy.valueMatches(2e9+1,2e9,'exact'));expect(not Policy.valueMatches(2e9-1,2e9,'exact'))
    expect(Policy.valueMatches(3e9,2e9,'atLeast'));expect(not Policy.valueMatches(1e9,2e9,'atLeast'))
    expect(not Policy.valueMatches(nil,0,'exact'));expect(not Policy.valueMatches(0/0,0,'exact'))
    expect(not Policy.valueMatches(math.huge,0,'atLeast'));expect(not Policy.valueMatches(1,1,'unknown'))
    expect(not Policy.localEligible({uid='a',pickable=true,tier=10},0,0,'exact'))
    expect(Policy.localEligible({uid='a',pickable=true,tier=10},0,0))
    local egg={placeId=42,jobId='elsewhere',uid='a',rate=2e9,rank=10,expiresAt=2000}
    expect(Policy.remoteEligible(egg,1000,'here',2e9,6,'exact'))
    expect(not Policy.remoteEligible(egg,1000,'here',1e9,6,'exact'))
end)
print(tostring(passed)..' policy groups passed')
