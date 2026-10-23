-- Plain Lua checks for recording, matching and the run file. Not loaded by CSP.
local Recorder = require('recorder')
local Playback = require('playback')
local Runs = require('runs')

local failures = 0
local function check(name, ok)
  if not ok then
    failures = failures + 1
    io.stderr:write('FAIL ' .. name .. '\n')
  end
end

local function fill(x, gas)
  local sample = { x, 0, 0, 0, 0, 1, 0, 1, 0, 10, gas or 0, 0, 0, 0, 0, 1, 0 }
  return sample
end

local state = Recorder.new()
Recorder.start(state)
for i = 1, 10 do Recorder.observe(state, fill(i), 1 / 30, {}) end
Recorder.observe(state, fill(100), 1 / 30, { jump = true })
for i = 1, 4 do Recorder.observe(state, fill(100 + i), 1 / 30, {}) end
local kept = Recorder.stop(state)
check('jump keeps the longer piece', Playback.count(kept) == 10)
check('kept piece starts at the first sample', kept[1] == 1)

state = Recorder.new()
Recorder.start(state)
Recorder.observe(state, fill(1), 1 / 30, { paused = true })
Recorder.observe(state, fill(2), 0.4, {})
check('pause and a long frame add nothing', Recorder.liveSamples(state) == 0)

local samples = {}
for i = 1, 149 do
  local row = fill(i, i % 2)
  for k = 1, 17 do samples[#samples + 1] = row[k] end
end
local crossing = fill(12, 1)
for k = 1, 17 do samples[#samples + 1] = crossing[k] end
local index, distance = Playback.nearest(samples, 10, 12, 0, 0)
check('crossing stays outside the match window', index == 12)
check('match distance is on the local line', distance < 0.01)

index, distance = Playback.nearest(samples, 10, 12, 0, 40)
check('a far point leaves the local window', distance > 12)

local pose = Playback.pose(samples, Playback.INTERVAL * 0.5, Playback.INTERVAL, {})
check('halfway pose is between the first two samples', math.abs(pose[1] - 1.5) < 0.001)
check('pose keeps look normalised', math.abs(pose[6] - 1) < 0.001)

local run = {
  name = 'Lesson', track = 'brooklyn', layout = '', car = '350z',
  when = 100, dt = Playback.INTERVAL, samples = samples,
}
local decoded, err = Runs.decode(Runs.encode(run))
check('decode error ' .. tostring(err), decoded ~= nil)
check('round trip count', decoded and Playback.count(decoded.samples) == 150)
check('round trip name', decoded and decoded.name == 'Lesson')
check('round trip throttle', decoded and math.abs(decoded.samples[11] - samples[11]) < 0.001)

local player = Playback.newPlayer()
local _, _, ghost, waiting = Playback.advance(player, samples, Playback.INTERVAL, 1, 0, 0, 0, 4, 0.1)
check('standing in the circle does not start the ghost', waiting and ghost[1] == 1)
_, _, ghost, waiting = Playback.advance(player, samples, Playback.INTERVAL, 1, 0, 0, 3, 4, 0.1)
check('driving through the circle starts the ghost', not waiting)

if failures > 0 then
  io.stderr:write(failures .. ' failed\n')
  os.exit(1)
end
io.write('drift coach checks passed\n')
