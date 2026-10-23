-- Painted copy of a recorded line. Green is throttle, red is brake, purple is
-- handbrake, and a blue circle marks a clutch kick. Rebuilt only when the run
-- or the appearance settings change.
local Playback = require('playback')
local M = {}

function M.new()
  local paint = ac.TrackPaint()
  paint.bulgeFactor = 0.4
  paint.ageFactor = 0
  paint.castStep = 1
  return { paint = paint, key = '' }
end

local function color(gas, brake, handbrake, alpha)
  if handbrake > 0.35 then return rgbm(0.78, 0.32, 1, alpha) end
  local total = gas + brake
  if total < 0.08 then return rgbm(0.75, 0.78, 0.82, alpha * 0.65) end
  local throttle = gas / total
  local braking = brake / total
  return rgbm(0.95 * braking + 0.1 * throttle, 0.82 * throttle + 0.08 * braking, 0.18, alpha)
end

function M.sync(state, run, show, opacity, radius)
  local count = run and Playback.count(run.samples) or 0
  local key = string.format('%s:%d:%.2f:%.2f:%s', run and run.id or '', count, opacity or 0, radius or 0, show and '1' or '0')
  if key == state.key then return end
  state.key = key
  state.paint:reset()
  if not show or not run or count < 2 then return end
  local alpha = math.max(0.15, math.min(1, opacity or 0.9))
  local samples = run.samples
  local sx, sy, sz = Playback.xyz(samples, 1)
  state.paint:circle(vec3(sx, sy, sz), radius or 4, 0.18, rgbm(0.95, 0.95, 0.95, alpha), 28)
  local previousClutch = Playback.field(samples, 1, 14)
  for index = 2, count do
    local ax, ay, az = Playback.xyz(samples, index - 1)
    local bx, by, bz = Playback.xyz(samples, index)
    local gas = Playback.field(samples, index, 11)
    local brake = Playback.field(samples, index, 12)
    local handbrake = Playback.field(samples, index, 13)
    local clutch = Playback.field(samples, index, 14)
    state.paint:line(vec3(ax, ay, az), vec3(bx, by, bz), color(gas, brake, handbrake, alpha), handbrake > 0.35 and 0.55 or 0.32)
    if clutch > 0.65 and previousClutch < 0.35 then
      state.paint:circle(vec3(bx, by, bz), 0.55, 0.14, rgbm(0.35, 0.65, 1, alpha), 12)
    end
    previousClutch = clutch
  end
end

return M
