-- Horizontal modules; graph and tyres also have independent movable windows.
local T = require('telemetry')
local V = {}
local white, muted = rgbm(.94,.96,.98,1), rgbm(.65,.71,.77,1)
local colors = {rgbm(.25,.9,.68,1),rgbm(1,.35,.35,1),rgbm(.47,.65,1,1),rgbm(.93,.65,1,1),white,rgbm(1,.76,.32,1)}
local ghostColors = {rgbm(.25,.9,.68,.5),rgbm(1,.35,.35,.5),rgbm(.47,.65,1,.5),rgbm(.93,.65,1,.5)}
local labels = {'THR','BRK','CLU','H.B','FFB','BOOST'}
local function fmt(v, pattern)
  v = T.number(v, nil)
  return v and string.format(pattern or '%.0f', v) or '--'
end
local function geometry(prefs, mode, coachVisible)
  local modules = {}
  local function add(id, w) modules[#modules+1] = {id=id, width=w} end
  if mode == 'graph' then
    if prefs.graph then add('graph',400) end
  elseif mode == 'tyres' then
    if prefs.tyres then add('tyres',440) end
  else
    if coachVisible then add('coach',400) end
    if prefs.driving ~= false then add('driving',230) end
    if prefs.steering ~= false then add('steering',90) end
    if prefs.inputs ~= false then add('inputs',260) end
    if prefs.drift then add('drift',240) end
  end
  local total = 0
  for _,m in ipairs(modules) do total = total + m.width + 8 end
  total = math.max(200,total-8)
  return modules, total
end
function V.size(prefs, mode, coachVisible)
  local _, total = geometry(prefs, mode, coachVisible)
  return total, 92
end
function V.draw(car, state, prefs, width, replay, mode)
  local modules, total = geometry(prefs, mode, state.coach ~= nil)
  -- The content cursor includes CSP window chrome when free placement is used.
  -- Fit both axes so a saved window size cannot clip text or meters.
  local origin = ui.getCursor()
  local available = ui.availableSpace()
  local scale = math.max(.01, math.min(available.x/total, available.y/92))
  local offset = 0
  local function point(x,y) return vec2(origin.x+(offset+x)*scale,origin.y+y*scale) end
  local function rect(x,y,w,h,c) ui.drawRectFilled(point(x,y),point(x+w,y+h),c,4*scale) end
  local function text(s,x,y,size,c) ui.dwriteDrawText(s,size*scale,point(x,y),c or white) end
  local function centeredText(s,center,y,size,c)
    local measured = ui.measureDWriteText(s,size*scale)
    text(s,center-measured.x/(2*scale),y,size,c)
  end
  local function line(x,y,xx,yy,c) ui.drawLine(point(x,y),point(xx,yy),c,1.3*scale) end
  if not car then text('Waiting for a car',8,20,18); return end
  for _,m in ipairs(modules) do
    rect(0,0,m.width,92,rgbm(.035,.047,.065,prefs.backgroundOpacity or .18))
    if m.id == 'coach' then
      local c = state.coach
      local comparable = c.status == 2
      local status = ({'Approach start', 'Reference inputs', 'Away from demo: line', 'Away from demo: speed',
        'Away from demo: direction', 'Away from demo: gear', 'Section complete', 'Replay: reference paused'})[c.status]
      text(status or 'Reference unavailable',10,4,11,comparable and white or colors[6])
      local factor = prefs.mph and .621371 or 1
      text('Demo '..fmt(c.speed*factor)..' G'..fmt(c.gear)..' / You '..fmt(T.number(car.speedKmh,0)*factor)..' G'..fmt(car.gear)
        ..(prefs.mph and ' mph' or ' km/h'),10,20,10,muted)
      text('DEMO',220,20,10,white); text('LEARNER',300,20,10,white)
      for i,channel in ipairs({'gas','brake'}) do
        local y = 36 + (i-1)*20
        text(i==1 and 'THROTTLE' or 'BRAKE',10,y,10,colors[i])
        rect(97,y+3,110,7,rgbm(.2,.24,.28,.5))
        local live = T.clamp(car[channel],0,1)
        rect(97,y+3,110*live,7,colors[i])
        if comparable then
          local mark = 97+110*T.clamp(c[channel],0,1)
          rect(mark-2,y,4,13,white)
        end
        text(fmt(c[channel]*100)..'%',220,y,13,comparable and white or muted)
        text(fmt(live*100)..'%',300,y,13,colors[i])
        if comparable then
          local trend = c[channel..'Trend'] or 0
          text(trend>0 and 'UP' or trend<0 and 'DOWN' or 'HOLD',365,y,9,white)
        end
      end
      local cue = ({'Brake ahead', 'Throttle release ahead', 'Throttle application ahead'})[c.cue]
      text(comparable and cue and ('Demo: '..cue..' / '..fmt(c.cueIn,'%.1fs'))
        or comparable and 'White marker = demo / filled bar = learner'
        or 'Reference only. Respond to your own car.',10,78,10,muted)
    elseif m.id == 'driving' then
      local rpm,limit = T.number(car.rpm,0),T.number(car.rpmLimiter,0)
      for i=1,24 do
        rect(10+(i-1)*8.8,7,7,3,limit>0 and rpm/limit>=i/24 and (rpm>limit*.95 and colors[2] or colors[1]) or muted)
      end
      text(car.gear == -1 and 'R' or car.gear == 0 and 'N' or fmt(car.gear),10,15,48)
      text(fmt(T.number(car.speedKmh,0)*(prefs.mph and .621371 or 1)),65,16,42)
      text(prefs.mph and 'MPH' or 'KM/H',68,66,10,muted)
      text(fmt(car.rpm),155,27,20)
      text('RPM / '..fmt(car.fuel,'%.1f')..' L',150,58,10,muted)
    elseif m.id == 'steering' then
      local a=math.rad(T.number(car.steer,0))
      ui.drawCircle(point(45,35),24*scale,muted,40,2*scale)
      line(45-math.cos(a)*21,35-math.sin(a)*21,45+math.cos(a)*21,35+math.sin(a)*21,white)
      text(fmt(car.steer)..' deg',20,68,12,muted)
      if state.ghost then
        local g=math.rad(T.number(state.ghost[5],0))
        line(45-math.cos(g)*21,35-math.sin(g)*21,45+math.cos(g)*21,35+math.sin(g)*21,rgbm(.45,.9,1,1))
      end
    elseif m.id == 'inputs' then
      local values={car.gas,car.brake,T.clutch(car,prefs.invertClutch),car.handbrake,math.abs(T.number(car.ffbFinal,0)),car.turboBoost}
      local n=0
      for i=1,6 do
        if prefs['trace'..i] then
          local x=10+n*40; n=n+1
          local available=not(i>=5 and car.physicsAvailable==false)
          local value=T.clamp(values[i],0,1)
          centeredText(labels[i],x+11,10,9,muted)
          rect(x+6,27,10,34,rgbm(.2,.24,.28,.5))
          if available then rect(x+6,61-value*34,10,value*34,colors[i]) end
          if available and state.ghost and i <= 4 then
            local mark=T.clamp(state.ghost[i],0,1)
            rect(x+2,60-mark*34,18,2,rgbm(1,1,1,.95))
          end
          centeredText(available and fmt(value*100) or '--',x+11,69,11,colors[i])
        end
      end
    elseif m.id == 'drift' then
      text(fmt(math.abs(state.angle or 0))..' deg',10,10,27,state.active and colors[1] or white)
      text(fmt(state.run.seconds,'%.1fs')..' / '..state.run.transitions..' turns',125,18,13)
      text(replay and 'REPLAY' or state.active and 'DRIFTING' or 'SLIP ANGLE',10,43,10,muted)
      text('BEST '..fmt(state.trackBest and state.trackBest.seconds,'%.1fs'),125,44,10,colors[1])
      text(state.last and ('LAST '..fmt(state.last.seconds,'%.1fs')..' / '..fmt(state.last.peak)..' deg peak') or 'Ready for your next run',10,69,11,muted)
    elseif m.id == 'graph' then
      for j=0,2 do line(10,12+j*25,390,12+j*25,rgbm(.3,.35,.4,.35)) end
      for n=2,state.count do
        local prev=state.history[(state.head-state.count+n-2)%160+1]
        local curr=state.history[(state.head-state.count+n-1)%160+1]
        for channel=1,6 do
          if prefs['trace'..channel] and not(channel>=5 and car.physicsAvailable==false) then
            line(10+(n-2)*380/159,62-prev[channel]*50,10+(n-1)*380/159,62-curr[channel]*50,colors[channel])
          end
          if channel<=4 and prefs['trace'..channel] and prev[channel+6] and curr[channel+6] then
            line(10+(n-2)*380/159,62-prev[channel+6]*50,10+(n-1)*380/159,62-curr[channel+6]*50,ghostColors[channel])
          end
        end
      end
      local ghostTrace=false
      if state.count>1 then
        local newest=state.history[(state.head-1)%160+1]
        ghostTrace=newest and newest[7]~=nil
      end
      text(ghostTrace and 'INPUT HISTORY / GHOST / 8 SECONDS' or 'INPUT HISTORY / 8 SECONDS',10,73,10,muted)
    elseif m.id == 'tyres' then
      for i=0,3 do
        local w=car.wheels and car.wheels[i]; local x=10+i*108
        text(({'FL','FR','RL','RR'})[i+1],x,10,11,muted)
        local ok=w and car.physicsAvailable~=false
        text(ok and fmt(w.tyreCoreTemperature)..' C' or '--',x,29,19)
        text(ok and fmt(w.tyrePressure,'%.1f')..' PSI' or '--',x,54,12)
        text(ok and 'I '..fmt(w.tyreInsideTemperature)..' M '..fmt(w.tyreMiddleTemperature)..' O '..fmt(w.tyreOutsideTemperature) or '',x,75,8,muted)
      end
    end
    offset=offset+m.width+8
  end
  ui.setCursor(origin); ui.dummy(vec2(total*scale,92*scale))
end
return V
