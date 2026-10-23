-- Painted copy of a recorded line. Green is throttle, red is brake, purple is
-- handbrake, and a blue circle marks a clutch kick. Rebuilt only when the run
-- or the appearance settings change.
--
-- Each point is dropped onto the physics surface with a short downward ray,
-- and track paint is told not to cast one of its own. Track paint's cast is
-- long enough to hit the first surface in the column. On Brooklyn Park that
-- surface is the bridge deck, so the line jumped onto the bridge while the
-- recorded car stayed on the road underneath.
local Playback = require('playback')
local M = {}

-- Starts just above the recorded car and reaches a couple of metres down.
-- A deck you can drive under is above the roof, so the ray never enters it.
-- From up on that deck the ray ends before the road underneath.
local RAY_LIFT = 0.4
local RAY_REACH = 2.5
local origin, hit, down

local function trackCast(x, y, z, reach)
  if not physics or not physics.raycastTrack then return -1 end
  if not origin then origin, hit, down = vec3(), vec3(), vec3(0, -1, 0) end
  origin:set(x, y, z)
  local distance = physics.raycastTrack(origin, down, reach, hit)
  if not distance or distance < 0 then return -1 end
  return distance, hit.y
end

-- `cast` stands in for the physics ray in tests. A miss keeps the recorded point.
function M.project(x, y, z, cast)
  local distance, surfaceY = (cast or trackCast)(x, y + RAY_LIFT, z, RAY_REACH)
  if not distance or distance < 0 or surfaceY == nil then return x, y, z end
  return x, surfaceY, z
end

function M.new()
  local paint = ac.TrackPaint()
  paint.bulgeFactor = 0.4
  paint.ageFactor = 0
  paint.castStep = math.huge
  paint.alignShapes = false
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
  local placed = {}
  for index = 1, count do
    local x, y, z = Playback.xyz(samples, index)
    local px, py, pz = M.project(x, y, z)
    placed[index] = vec3(px, py, pz)
  end
  state.paint:circle(placed[1], radius or 4, 0.18, rgbm(0.95, 0.95, 0.95, alpha), 28)
  local previousClutch = Playback.field(samples, 1, 14)
  for index = 2, count do
    local gas = Playback.field(samples, index, 11)
    local brake = Playback.field(samples, index, 12)
    local handbrake = Playback.field(samples, index, 13)
    local clutch = Playback.field(samples, index, 14)
    state.paint:line(placed[index - 1], placed[index], color(gas, brake, handbrake, alpha), handbrake > 0.35 and 0.55 or 0.32)
    if clutch > 0.65 and previousClutch < 0.35 then
      state.paint:circle(placed[index], 0.55, 0.14, rgbm(0.35, 0.65, 1, alpha), 12)
    end
    previousClutch = clutch
  end
end

return M
