-- Sample buffer for a recorded run. Samples are a flat list, 17 numbers each:
-- position xyz, look xyz, up xyz, speed (m/s), gas, brake, handbrake, clutch,
-- steer (degrees), gear, slip (degrees). Time is implicit at INTERVAL seconds.
local M = {}
M.INTERVAL = 1 / 30
M.STRIDE = 17
local MAX_SAMPLES = 30 * 60 * 6

function M.jumpDistance(speed, dt)
  return 12 + (speed or 0) * math.min(dt or 0, 0.25) * 3
end

function M.new()
  return { recording = false, current = {}, best = {}, acc = 0, note = nil }
end

local function keepLongest(state)
  if #state.current > #state.best then state.best = state.current end
  state.current = {}
  state.acc = 0
end

function M.start(state)
  state.recording = true
  state.current, state.best = {}, {}
  state.acc = 0
  state.note = nil
end

-- Stops recording and returns the longest continuous segment. Pauses and
-- replays leave a gap instead of a sample. A teleport starts a new segment
-- and the shorter piece is dropped, so a reset is not part of the saved run.
function M.stop(state)
  state.recording = false
  keepLongest(state)
  local saved = state.best
  state.best, state.current = {}, {}
  state.acc = 0
  return saved
end

function M.liveSamples(state)
  return math.floor(#state.current / M.STRIDE)
end

function M.observe(state, sample, dt, flags)
  if not state.recording then return end
  flags = flags or {}
  if flags.paused or flags.replay then
    state.acc = 0
    return
  end
  if flags.jump or (dt or 0) > 0.25 then
    keepLongest(state)
    state.note = 'Reset trimmed. The longest continuous piece is the one that will be saved.'
    return
  end
  state.acc = state.acc + math.max(0, dt or 0)
  local guard = 0
  while state.acc >= M.INTERVAL and guard < 4 do
    guard = guard + 1
    state.acc = state.acc - M.INTERVAL
    if #state.current / M.STRIDE >= MAX_SAMPLES then
      state.recording = false
      state.note = 'Stopped at 6 minutes'
      return
    end
    if not sample then return end
    for i = 1, M.STRIDE do
      state.current[#state.current + 1] = sample[i] or 0
    end
  end
end

return M
