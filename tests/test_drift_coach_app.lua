-- Exercise the actual app entry points with an in-memory Documents folder.
package.path = 'apps/lua/DriftCoach/?.lua;apps/lua/DriftHUD/?.lua;' .. package.path
local total=0
local function test(name,fn) fn(); total=total+1; print('PASS '..name) end
local function vec(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
vec2,vec3=vec,vec
rgbm=function(...) return {...} end
local saved,stores,blocks,schemas,buttons,sliders,checks,texts={},{},{},{},{},{},{},{}
local sim={focusedCar=0,isPaused=false,isInMainMenu=false,isReplayActive=false}
local car={index=0,gas=.6,brake=0,handbrake=0,clutch=1,steer=120,gear=3,
  velocity=vec(0,0,20),look=vec(0,0,1),up=vec(0,1,0),transform={position=vec()},
  isConnected=true,speedKmh=72,rpm=5000,rpmLimiter=7500,fuel=20,physicsAvailable=true}
local track,carID='brooklyn','350z'
ac={FolderID={ACDocuments=1},
  StructItem={key=function(k) return k end,boolean=function() return 'bool' end,
    int32=function() return 'int' end,float=function() return 'float' end},
  storage=function(defaults,key) stores[key]=stores[key] or defaults; return stores[key] end,
  getSim=function() return sim end,getCar=function() return car end,getFolder=function() return '/documents' end,
  getTrackID=function() return track end,getTrackLayout=function() return '' end,getCarID=function() return carID end,
  getCarSkinID=function() return 'red_paint' end,onCarJumped=function(_,callback) ac.jump=callback end,
  onSessionStart=function(callback) ac.session=callback end,
  ControlButton=function() return {pressed=function() return false end,control=function() end} end,
  TrackPaint=function() return {reset=function() end,circle=function() end,line=function() end} end}
ac.connect=function(layout)
  local key=layout[1]
  if schemas[key] then
    for name,kind in pairs(layout) do assert(schemas[key][name]==kind,'shared schema mismatch: '..name) end
    for name,kind in pairs(schemas[key]) do assert(layout[name]==kind,'missing shared field: '..name) end
  else
    schemas[key]=layout; blocks[key]={}
    for name,kind in pairs(layout) do if name~=1 then blocks[key][name]=kind=='bool' and false or 0 end end
  end
  return blocks[key]
end
io.load=function(path,default) return saved[path] or default end
io.save=function(path,data) saved[path]=data; return true end
io.createDir=function() end
io.deleteFile=function(path) saved[path]=nil end
stringify=setmetatable({tryParse=function(text,default)
  if not text or text=='' then return default end
  local ok,value=pcall(JSON.parse,text); return ok and value or default
end},{__call=function(_,data) return JSON.stringify(data) end})
ui={}
for _,name in ipairs({'separator','sameLine','pushID','popID','setCursor','dummy','drawRectFilled','drawLine','drawCircle'}) do ui[name]=function() end end
ui.text=function(s) texts[#texts+1]=s end
ui.textWrapped=ui.text
ui.dwriteDrawText=function(s) texts[#texts+1]=s end
ui.measureDWriteText=function(s,size) return vec(#s*size*.5,size) end
ui.getCursor=function() return vec() end
ui.availableSpace=function() return vec(2400,92) end
ui.windowWidth=function() return 2400 end
ui.inputText=function(_,value) return value end
ui.slider=function(label,value) return sliders[label] or value end
ui.checkbox=function(label) local value=checks[label]; checks[label]=nil; return value end
ui.button=function(label) local value=buttons[label]; buttons[label]=nil; return value or false end
local ghostPlacements=0
package.loaded.ghost={new=function() return {} end,useCar=function() end,clear=function() end,
  place=function(_,_,visible) if visible then ghostPlacements=ghostPlacements+1 end end,drawFallback=function() end}
local function saw(text)
  for _,line in ipairs(texts) do if line:find(text,1,true) then return true end end
  return false
end
script={}; dofile('apps/lua/DriftCoach/DriftCoach.lua'); local coach=script
local P=require('playback')
test('record save and reload preserve the driven run and recorded skin',function()
  buttons.Record=true; coach.windowMain()
  for i=1,120 do car.transform.position.z=(i-1)*2/3; coach.update(1/30) end
  buttons['Stop and save']=true; coach.windowMain()
  local found
  for path,data in pairs(saved) do
    if path:match('%.run$') then found=require('runs').decode(data) end
  end
  assert(found and found.skin=='red_paint' and P.count(found.samples)==120)
  assert(#found.visuals==120*49)
end)
test('selected section publishes start context and starts when driven forwards',function()
  sliders.Start,sliders.End=1,3
  buttons['Practise section']=true; coach.windowMain(); sliders={}
  car.transform.position.z=20; coach.update(1/30)
  assert(blocks['driftCoach.context.v1'].available and blocks['driftCoach.context.v1'].status==2)
  assert(blocks['driftCoach.v1'].active and math.abs(blocks['driftCoach.v1'].gas-.6)<1e-5)
  assert(ghostPlacements>0)
end)
test('context mismatch pauses references and produces one reviewable observation',function()
  car.velocity.z=8; car.speedKmh=28.8
  for _=1,20 do coach.update(1/30) end
  assert(not blocks['driftCoach.v1'].active and blocks['driftCoach.context.v1'].status==4)
  texts={}; coach.windowMain(); assert(saw('slower than the demonstration'))
  car.velocity.z=20; car.speedKmh=72
end)
test('the learner can finish after the timed ghost and rearm by returning',function()
  -- Stay near the start until the two-second ghost has finished.
  for _=1,80 do coach.update(1/30) end
  assert(blocks['driftCoach.context.v1'].status==2)
  for i=32,91 do car.transform.position.z=(i-1)*2/3; coach.update(1/30) end
  assert(blocks['driftCoach.context.v1'].status==7)
  car.transform.position.z=20; coach.update(1/30)
  assert(blocks['driftCoach.context.v1'].status==2)
  texts={}; coach.windowMain(); assert(saw('Previous attempt:'))
end)
test('the actual HUD reads the same schemas and renders the comparison',function()
  coach.update(1/30)
  script={}; dofile('apps/lua/DriftHUD/DriftHUD.lua'); local hud=script
  hud.update(1/30); texts={}; hud.windowMain()
  assert(saw('DEMO') and saw('LEARNER') and saw('60%'))
  -- A stopped/closed Coach must not leave stale percentages on the HUD.
  for _=1,30 do hud.update(1/30) end
  texts={}; hud.windowMain(); assert(not saw('LEARNER'))
end)
test('hiding learning guides clears reference channels',function()
  checks['Show learning guides']=true; coach.windowMain(); coach.update(1/30)
  assert(not blocks['driftCoach.v1'].active and not blocks['driftCoach.context.v1'].available)
  checks['Show learning guides']=true; coach.windowMain()
end)
test('other tracks and cars cannot receive a stale teaching reference',function()
  track='other_track'; coach.update(1/30); assert(not blocks['driftCoach.context.v1'].available)
  track='brooklyn'; carID='other_car'; coach.update(1/30); assert(not blocks['driftCoach.context.v1'].available)
  carID='350z'
end)
test('replay pauses matching and cannot launch a waiting ghost',function()
  sim.isReplayActive=true; car.transform.position.z=20; coach.update(1/30)
  assert(blocks['driftCoach.context.v1'].status==8 and not blocks['driftCoach.v1'].active)
  sim.isReplayActive=false; sim.isPaused=true; coach.update(1/30)
  assert(blocks['driftCoach.context.v1'].status==1 and not blocks['driftCoach.v1'].active)
  sim.isPaused=false
end)
test('destroy clears all published references',function()
  coach.destroy(); assert(not blocks['driftCoach.v1'].active and not blocks['driftCoach.context.v1'].available)
end)
print(total..' Coach / HUD integration checks passed')
