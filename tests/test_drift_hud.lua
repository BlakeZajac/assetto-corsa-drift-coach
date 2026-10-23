package.path = 'apps/lua/DriftHUD/?.lua;' .. package.path
local T = require('telemetry')
local total = 0
local function test(label, fn)
  fn(); total = total + 1; print('PASS ' .. label)
end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. ' ~= ' .. tostring(b)) end
local function car(angle)
  return {index = 0, velocity = {x = math.sin(math.rad(angle)) * 20, z = math.cos(math.rad(angle)) * 20},
    look = {x = 0, z = 1}, speedKmh = 72, gas = 0.8, brake = 0.1, clutch = 0.3,
    handbrake = 0.2, ffbFinal = -1.2, turboBoost = 0.5, steer = 180, rpm = 6200,
    rpmLimiter = 7500, gear = 3, fuel = 23.5, physicsAvailable = true, wheels = {}}
end
local function advance(s, c, seconds, replay)
  for _ = 1, math.floor(seconds * 100 + 0.5) do T.update(s, c, 0.01, false, replay) end
end
test('signed slip angle follows velocity relative to heading', function()
  near(T.angle(car(35)), 35); near(T.angle(car(-40)), -40)
  local c = car(30); c.look = {x = 1, z = 0}; near(T.angle(c), -60)
end)
test('stationary and reverse cannot score', function()
  for _, angle in ipairs({0, 120, 180}) do
    local s, c = T.new(), car(angle)
    if angle == 0 then c.velocity = {x = 0, z = 0} end
    advance(s, c, 2); assert(s.run.seconds == 0 and not s.last)
  end
end)
test('short straight links transitions without adding drift time', function()
  local s = T.new(); advance(s, car(30), 1.5); advance(s, car(0), 0.4)
  advance(s, car(-30), 1); near(s.run.seconds, 2.5); assert(s.run.transitions == 1)
  advance(s, car(0), 0.8); near(s.last.seconds, 2.5); assert(s.run.seconds == 0)
end)
test('spin ends a run and preserves its summary', function()
  local s = T.new(); advance(s, car(35), 2); advance(s, car(100), 0.1)
  near(s.last.seconds, 2); near(s.last.peak, 35); assert(s.run.seconds == 0)
end)
test('pauses and replay never contribute to timings', function()
  local s, c = T.new(), car(30); advance(s, c, 1)
  T.update(s, c, 10, true, false); near(s.run.seconds, 1)
  advance(s, c, 3, true); assert(s.run.seconds == 0 and not s.last and not s.active)
end)
test('pit and low speed exclude scoring', function()
  for _, field in ipairs({'isInPit', 'isInPitlane'}) do
    local s, c = T.new(), car(35); c[field] = true; advance(s, c, 2); assert(not s.last and s.run.seconds == 0)
  end
  local s, c = T.new(), car(35); c.speedKmh = 15; advance(s, c, 2); assert(s.run.seconds == 0)
end)
test('input history is bounded and frame rate independent', function()
  for _, dt in ipairs({0.01, 0.1, 0.2}) do
    local s = T.new(); for _ = 1, math.floor(10 / dt) do T.update(s, car(0), dt, false, false) end
    assert(s.count == 160 and #s.history == 160)
    assert(s.history[s.head][5] == 1)
  end
end)
test('best run is retained after a shorter run', function()
  local s = T.new(); advance(s, car(30), 3); advance(s, car(0), 1)
  advance(s, car(30), 1.5); advance(s, car(0), 1)
  near(s.best.seconds, 3); near(s.last.seconds, 1.5)
end)
test('discontinuities discard unfinished runs and history', function()
  local s = T.new(); advance(s, car(30), 2); T.update(s, car(30), 1, false, false)
  assert(s.run.seconds == 0 and not s.last and s.count == 0 and not s.active)
end)
test('invalid measurements do not poison state', function()
  local c, s = car(30), T.new(); c.velocity.x, c.gas = 0/0, math.huge
  advance(s, c, 1); assert(s.angle == s.angle and s.history[s.head][1] == 0)
end)
test('clutch polarity is shared by bars and history', function()
  local c, s = car(0), T.new(); c.clutch = 1
  T.update(s, c, 0.1, false, false, true)
  assert(T.clutch(c, true) == 0 and s.history[s.head][3] == 0)
  c.clutch = 0; T.update(s, c, 0.1, false, false, true)
  assert(T.clutch(c, true) == 1 and s.history[s.head][3] == 1)
end)

-- Rendering doubles catch bad draw arguments and exercise both settings modes.
local draws = 0
vec2 = function(x, y) return {x = x, y = y} end
rgbm = function(r, g, b, a) return {r = r, g = g, b = b, mult = a} end
ui = {}
ui.getCursor = function() return vec2(8, 26) end
ui.availableSpace = function() return vec2(824, 76) end
ui.measureDWriteText = function(text, size) return vec2(#text * size * 0.5, size) end
for _, name in ipairs({'drawRectFilled', 'drawLine', 'drawCircle', 'dwriteDrawText', 'setCursor', 'dummy'}) do
  ui[name] = function(...) draws = draws + 1 end
end
local View = require('view')
test('view renders full history, missing physics and no-car states', function()
  local s, c = T.new(), car(30); advance(s, c, 10)
  local p = {opacity = .94, graph = true, tyres = true, drift = true}
  for i = 1, 6 do p['trace' .. i] = true end
  View.draw(c, s, p, 840, false)
  View.draw(c, s, p, 420, false, 'graph')
  View.draw(c, s, p, 460, false, 'tyres'); assert(draws > 100)
  c.physicsAvailable = false; View.draw(c, s, p, 610, true)
  View.draw(nil, s, p, 840, false)
  p.graph, p.tyres, p.drift, p.mph = false, false, false, true
  View.draw(c, s, p, 1200, false)
  p.driving, p.steering, p.inputs = false, false, false
  View.draw(c, s, p, 420, false)
  View.draw(c, s, p, 420, false, 'graph')
  View.draw(c, s, p, 460, false, 'tyres')
end)
test('entry point handles focus changes, jump callbacks and settings', function()
  local sim = {focusedCar = 0, isReplayActive = false, replayCurrentFrame = 0}
  local c = car(30)
  local callbacks, stores = {}, {}
  ac = {storage = function(p, key) stores[key] = stores[key] or p; return stores[key] end, getSim = function() return sim end,
    StructItem = {key = function(k) return k end, boolean = function() return false end,
      int32 = function() return 0 end, float = function() return 0 end},
    connect = function(layout) return layout end,
    getTrackID = function() return 'brooklyn' end, getTrackLayout = function() return '' end,
    getCarID = function() return 'test-car' end,
    getCar = function() return c end, onSessionStart = function(fn) callbacks.session = fn end,
    onCarJumped = function(_, fn) callbacks.jump = fn end}
  script = {}
  ui.windowWidth = function() return 840 end
  ui.checkbox = function() return false end
  ui.slider = function(_, v) return v end
  ui.button = function() return false end
  ui.text, ui.textWrapped, ui.separator = function() end, function() end, function() end
  dofile('apps/lua/DriftHUD/DriftHUD.lua')
  script.update(0.02); script.windowMain(); script.windowSettings()
  for _ = 1, 100 do script.update(.02) end
  c.velocity = {x = 0, z = 0}; script.update(.02)
  local saved = require('history').new(stores['driftHUD.history.'].json)
  assert(#saved.recent == 1 and saved.recent[1].track == 'brooklyn')
  script.windowHistory()
  -- Loading the actual entry point again simulates a fresh app instance.
  dofile('apps/lua/DriftHUD/DriftHUD.lua'); script.update(.02); script.windowHistory()
  c.velocity = car(30).velocity
  callbacks.jump(0); script.update(0.02); callbacks.session(); script.update(0.02)
  sim.isReplayActive = true; script.update(0.02)
  sim.replayCurrentFrame = 100; script.update(0.02)
  c.index, sim.focusedCar = 1, 1; script.update(0.02)
  sim.isReplayActive = false
  for _ = 1, 100 do script.update(.02) end
  c.velocity = {x = 0, z = 0}; script.update(.02)
  assert(#require('history').new(stores['driftHUD.history.'].json).recent == 1)
  sim.focusedCar = -1; script.update(0.02); script.windowMain()
end)
test('coach panel labels both pedals and suppresses markers for mismatched states', function()
  local s, c = T.new(), car(30)
  s.coach = {status=2, gas=.6, brake=.2, speed=72, gear=3, cue=1, cueIn=.8, gasTrend=0, brakeTrend=1}
  local labels = {}
  ui.dwriteDrawText = function(label) labels[label] = true end
  local p = {driving=false, steering=false, inputs=false, drift=false}
  local base = View.size(p)
  local width = View.size(p, nil, true)
  assert(width == 400 and width > base)
  View.draw(c,s,p,width,false)
  assert(labels['DEMO'] and labels['LEARNER'] and labels['60%'] and labels['20%'])
  assert(labels['Demo: Brake ahead / 0.8s'])
  labels = {}; s.coach.status = 4
  View.draw(c,s,p,width,false)
  assert(labels['Away from demo: speed'] and not labels['Demo: Brake ahead / 0.8s'])
end)
print(total .. ' Drift HUD checks passed')
