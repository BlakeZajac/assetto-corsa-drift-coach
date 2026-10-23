package.path = 'apps/lua/DriftCoach/?.lua;' .. package.path
local P, C = require('playback'), require('coaching')
local L = require('lesson')
local R, Runs, Visuals = require('recorder'), require('runs'), require('visuals')
local count = 0
local function test(name, fn) fn(); count=count+1; print('PASS '..name) end
local function near(a,b) assert(math.abs(a-b)<1e-5, tostring(a)..' ~= '..tostring(b)) end
local function run()
  local out = {samples={},dt=1/30}
  for i=1,180 do
    local sample = {0,0,(i-1)*2/3, 0,0,1, 0,1,0, 20, .6,0,0,0,180,3,30}
    for _,v in ipairs(sample) do out.samples[#out.samples+1]=v end
  end
  return out
end
local function car() return {velocity={x=0,z=20},look={x=0,z=1},gear=3} end
local function set(r,i,k,v) r.samples[(i-1)*P.STRIDE+k]=v end
test('pedal references retain strength and simultaneous braking',function()
  local r=run()
  for i=1,180 do set(r,i,12,.2) end
  local ref=C.evaluate(r,60,0,car(),false,false,false)
  assert(ref.comparable); near(ref.gas,.6); near(ref.brake,.2); near(ref.speed,72); assert(ref.gear==3)
end)
test('unlike driving states cannot publish actionable references',function()
  local r,c=run(),car()
  assert(C.evaluate(r,60,5,c,false,false,false).status==C.LINE)
  c.velocity.z=10; assert(C.evaluate(r,60,0,c,false,false,false).status==C.SPEED)
  c=car(); c.look={x=1,z=0}; assert(C.evaluate(r,60,0,c,false,false,false).status==C.DIRECTION)
  c=car(); c.gear=2; assert(C.evaluate(r,60,0,c,false,false,false).status==C.GEAR)
  assert(C.evaluate(r,60,0,car(),true,false,false).status==C.WAITING)
  assert(C.evaluate(r,60,0,car(),false,true,false).status==C.FINISHED)
  assert(C.evaluate(r,60,0,car(),false,false,true).status==C.REPLAY)
end)
test('advance notices require a sustained recorded change and stop on mismatch',function()
  local r=run()
  set(r,70,12,.3); assert(C.upcoming(r,60)==0)
  for i=80,100 do set(r,i,12,.3) end
  local code,seconds=C.upcoming(r,60); assert(code==1); near(seconds,20/30)
  local ref=C.evaluate(r,60,0,car(),false,false,false); assert(ref.cue==1)
  ref=C.evaluate(r,60,8,car(),false,false,false); assert(ref.cue==0 and not ref.comparable)
end)
test('spatially matched reference does not depend on ghost playback time',function()
  local r=run()
  for i=90,180 do set(r,i,11,.2) end
  local p=P.newPlayer(); p.started=true; p.time=4
  local index=P.advance(p,r.samples,r.dt,0,0,20,20,4,.01)
  assert(index < 40)
  local ref=C.evaluate(r,index,0,car(),false,false,false); near(ref.gas,.6)
end)
test('practice sections preserve the original and use their own start',function()
  local r=run(); r.id='demo'; r.skin='red'
  local section=L.section(r,1,3)
  assert(section and P.count(section.samples)==61 and section.skin=='red')
  near(P.field(section.samples,1,3),20); near(P.duration(section.samples,section.dt),2)
  set(section,1,11,0); near(P.field(r.samples,31,11),.6)
  assert(not L.section(r,3,2)); assert(not L.section(r,1,1.3))
end)
test('first sustained difference is retained without diagnosing a cause',function()
  local r,c=run(),car(); local a=L.new()
  c.velocity.z=10
  local ref=C.evaluate(r,1,0,c,false,false,false)
  L.observe(a,ref,c,.1,1,180,true); assert(not a.first)
  L.observe(a,ref,c,.1,2,180,true); assert(not a.first)
  L.observe(a,ref,c,.1,3,180,true); assert(a.first.text:find('slower'))
  c.velocity.z=20; c.gear=2; ref=C.evaluate(r,80,0,c,false,false,false)
  L.observe(a,ref,c,.2,80,180,true); assert(a.first.text:find('slower'))
  L.observe(a,ref,c,.1,179,180,true); assert(a.done and L.summary(a):find('First difference'))
end)
test('a paused or backwards start cannot release the ghost',function()
  local r=run(); local p=P.newPlayer()
  P.advance(p,r.samples,r.dt,0,0,0,20,4,0,0,20); assert(not p.started)
  P.advance(p,r.samples,r.dt,0,0,0,20,4,.02,0,-20); assert(not p.started)
  P.advance(p,r.samples,r.dt,0,0,0,20,4,.02,0,20); assert(p.started)
end)
test('reverse travel cannot match even with the same heading speed and gear',function()
  local c=car(); c.velocity.z=-20
  assert(C.evaluate(run(),40,0,c,false,false,false).status==C.DIRECTION)
end)
test('new run files round trip visuals skin and precise sample timing',function()
  local r=run(); r.name='Demo'; r.track='brooklyn'; r.car='350z'; r.layout=''; r.skin='red'; r.visuals={}
  for i=1,180*P.VISUAL_STRIDE do r.visuals[i]=i/10 end
  local decoded,err=Runs.decode(Runs.encode(r)); assert(decoded,err)
  assert(decoded.skin=='red' and #decoded.visuals==#r.visuals and #decoded.samples==#r.samples)
  near(decoded.visuals[200],r.visuals[200]); near(decoded.dt,r.dt)
  local section=L.section(decoded,1,3)
  assert(#section.visuals==61*P.VISUAL_STRIDE)
  near(section.visuals[1],decoded.visuals[30*P.VISUAL_STRIDE+1])
end)
test('legacy runs load without inventing skin or wheel motion',function()
  local r=run()
  local lines={'DRIFTCOACH 1','Demo','brooklyn','','350z','1','0.03333','180'}
  for i=1,180 do
    local row={}; for k=1,17 do row[k]=tostring(P.field(r.samples,i,k)) end
    lines[#lines+1]=table.concat(row,' ')
  end
  local decoded,err=Runs.decode(table.concat(lines,'\n')); assert(decoded,err)
  assert(decoded.skin=='' and not decoded.visuals and P.count(decoded.samples)==180)
  local again=Runs.decode(Runs.encode(decoded)); assert(again and not again.visuals)
end)
test('corrupt intervals counts and nonfinite samples are rejected',function()
  local text=Runs.encode(run())
  assert(not Runs.decode(text:gsub('0.0333333333','0')))
  assert(not Runs.decode(text:gsub('0.0333333333','nan')))
  assert(not Runs.decode(text:gsub('\n180\n','\n99999999\n',1)))
  assert(not Runs.decode(text:sub(1,-8)))
end)
test('recording resamples positions and visuals across slow frames',function()
  local r=R.new(); R.start(r)
  for i=1,40 do
    local s={}; for k=1,17 do s[k]=0 end; s[1]=i*.1; s[16]=3
    local v={}; for k=1,P.VISUAL_STRIDE do v[k]=i*.1 end
    R.observe(r,s,.1,{},v)
  end
  local samples,visuals=R.stop(r)
  assert(P.count(samples)>=119 and P.count(samples)<=120)
  for i=5,P.count(samples) do
    near(P.field(samples,i,1)-P.field(samples,i-1,1),1/30)
    near(visuals[(i-1)*P.VISUAL_STRIDE+1],P.field(samples,i,1))
  end
end)
test('resets preserve the same longest segment for telemetry and visuals',function()
  local r=R.new(); R.start(r)
  local s,v={},{}; for k=1,17 do s[k]=1 end; for k=1,49 do v[k]=2 end
  for i=1,60 do R.observe(r,s,1/30,{},v) end
  R.observe(r,s,.02,{jump=true},v)
  for i=1,20 do R.observe(r,s,1/30,{},v) end
  local samples,visuals=R.stop(r)
  assert(P.count(samples)==60 and #visuals==60*49)
end)
test('wheel phase interpolation preserves multiple revolutions',function()
  local values={}
  for i=1,2 do for k=1,49 do values[#values+1]=(k==19 and (i-1)*8 or 0) end end
  near(P.visualPose(values,1/60,1/30)[19],4)
end)
test('warning hysteresis avoids flicker and varying speed still yields a summary',function()
  local r,c=run(),car()
  local previous=C.evaluate(r,40,4.1,c,false,false,false)
  assert(previous.status==C.LINE)
  assert(C.evaluate(r,40,3.5,c,false,false,false,previous).status==C.LINE)
  assert(C.evaluate(r,40,2.9,c,false,false,false,previous).comparable)
  local a=L.new()
  for i=1,10 do
    c.velocity.z=9+i*.1
    local ref=C.evaluate(r,40+i,0,c,false,false,false)
    L.observe(a,ref,c,1/30,40+i,180,true)
  end
  assert(a.first and a.first.text:find('slower'))
end)
print(count..' Drift Coach checks passed')
