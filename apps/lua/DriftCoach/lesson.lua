local P = require('playback')
local C = require('coaching')
local M = {}

-- A practice section is a view of a saved run. Never overwrite its samples.
function M.section(run, fromSeconds, toSeconds)
  local n = P.count(run.samples)
  local first = math.max(1, math.min(n, math.floor(fromSeconds / run.dt + 0.5) + 1))
  local last = math.max(first, math.min(n, math.floor(toSeconds / run.dt + 0.5) + 1))
  if last - first < math.ceil(1 / run.dt) then return nil, 'Choose a section at least one second long.' end
  local out = {id = tostring(run.id)..':'..first..':'..last, name = run.name,
    track = run.track, layout = run.layout, car = run.car, skin = run.skin, dt = run.dt,
    samples = {}, sourceStart = (first - 1) * run.dt, visuals = run.visuals and {} or nil}
  for i = (first-1)*P.STRIDE+1, last*P.STRIDE do out.samples[#out.samples+1] = run.samples[i] end
  if out.visuals then
    for i = (first-1)*P.VISUAL_STRIDE+1, last*P.VISUAL_STRIDE do out.visuals[#out.visuals+1] = run.visuals[i] end
  end
  return out
end

function M.new() return {started = false, done = false, elapsed = 0, pending = nil, pendingTime = 0} end

local function difference(ref, car)
  if ref.status == C.LINE then return 'Your line moved away from the demonstration.', 'line' end
  if ref.status == C.DIRECTION then return 'Your car pointed a different way from the demonstration.', 'direction' end
  if ref.status == C.SPEED then
    return string.format('You were %.0f km/h %s than the demonstration.', math.abs(ref.speedDelta), ref.speedDelta < 0 and 'slower' or 'faster'),
      ref.speedDelta < 0 and 'slow' or 'fast'
  end
  if ref.status == C.GEAR then return string.format('You used gear %d; the demonstration used gear %d.', car.gear, ref.gear), 'gear' end
  if ref.comparable then
    if math.abs((car.brake or 0) - ref.brake) > 0.2 then return 'Your brake input differed from the demonstration.', 'brake' end
    if math.abs((car.gas or 0) - ref.gas) > 0.25 then return 'Your throttle input differed from the demonstration.', 'gas' end
  end
end

-- Report the first sustained observation, without claiming it caused a spin.
function M.observe(state, ref, car, dt, progress, total, started)
  if state.done or not started or not ref or dt <= 0 then return end
  state.started, state.elapsed = true, state.elapsed + dt
  if not state.first then
    local note, key = difference(ref, car)
    if key ~= state.pending then
      state.pending, state.pendingText, state.pendingTime, state.pendingAt = key, note, 0, ref.time
    end
    if note then
      state.pendingTime = state.pendingTime + dt
      if state.pendingTime >= 0.25 then
        state.first = {text = state.pendingText, time = state.pendingAt}
      end
    end
  end
  if progress >= total - 1 and ref.distance <= 4 then state.done = true end
end

function M.summary(state, stopped)
  if state.first then return string.format('First difference at %.1fs: %s', state.first.time, state.first.text) end
  if state.done then return 'Section complete. No large sustained difference detected. Try once with the guides hidden.' end
  if state.started then
    return stopped and 'Attempt stopped before the finish. No large sustained difference detected.'
      or 'Attempt in progress. Return to the start or reset the ghost to try again.'
  end
  return 'Drive through the start circle to begin an attempt.'
end

return M
