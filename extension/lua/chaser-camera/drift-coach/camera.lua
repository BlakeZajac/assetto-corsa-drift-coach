-- Drift Coach. Distances are metres, angles inside the script are radians.
-- Sits above and behind the direction of travel, with slow smoothing, so a
-- drift reads as the car's angle against its line.
local cfg = ac.INIConfig.scriptSettings():mapSection('SETTINGS', {
  DISTANCE = 7,
  HEIGHT = 9,
  FOV = 60,
  LOOK_AHEAD = 2,
  TRAVEL_FOLLOW = 1,
  SMOOTHING = 1,
  HORIZON_LOCK = 0.98
})

local pi = math.pi
local tau = 2 * pi

local function clamp(v, low, high)
  return math.max(low, math.min(high, v))
end

local function number(v, fallback)
  if type(v) ~= 'number' or v ~= v or v == math.huge or v == -math.huge then
    return fallback
  end
  return v
end

local function wrap(angle)
  return (angle + pi) % tau - pi
end

local function smoothAngle(value, target, blend)
  return wrap(value + wrap(target - value) * blend)
end

local function smoothstep(low, high, value)
  local t = clamp((value - low) / (high - low), 0, 1)
  return t * t * (3 - 2 * t)
end

local distance = clamp(number(cfg.DISTANCE, 7), 4, 16)
local height = clamp(number(cfg.HEIGHT, 9), 4, 18)
local fov = clamp(number(cfg.FOV, 60), 40, 100)
local lookAhead = clamp(number(cfg.LOOK_AHEAD, 2), 0, 8)
local travelFollow = clamp(number(cfg.TRAVEL_FOLLOW, 1), 0, 1)
local smoothing = clamp(number(cfg.SMOOTHING, 1), 0.35, 2.5)
local yawTime = 0.45 * smoothing
local moveTime = 0.35 * smoothing
local horizonLock = clamp(number(cfg.HORIZON_LOCK, 0.98), 0, 1)

local function newState()
  return { generation = -1, position = vec3() }
end

local states = { newState(), newState() }
local generation = 0
local activeIndex

local function reset()
  generation = generation + 1
end

ac.onReplay(reset)
ac.onCarJumped(-1, function(index)
  if car and car.index == index then reset() end
end)

function script.onCarChanged()
  reset()
end

local cameraPosition = vec3()
local cameraDirection = vec3()
local cameraUp = vec3()

function script.update(dt, cameraIndex)
  if not car then return end

  local index = cameraIndex == 2 and 2 or 1
  local state = states[index]
  local clock = number(sim.time, 0)
  local step = number(sim.dt, number(dt, 0))
  local replay = sim.isReplayActive
  local replayRate = number(sim.replayPlaybackRate, 1)
  if sim.isPaused or (replay and replayRate == 0) then step = 0 end
  step = math.abs(step)
  local replayDirection = replayRate < 0 and -1 or 1

  local origin = car.transform.position
  local vx, vz = car.velocity.x, car.velocity.z
  local speed = math.sqrt(vx * vx + vz * vz)
  local lx, lz = car.look.x, car.look.z
  local horizontalLength = math.sqrt(lx * lx + lz * lz)
  local heading = state.heading or 0
  if horizontalLength > 0.001 then
    lx, lz = lx / horizontalLength, lz / horizontalLength
    heading = math.atan2(lx, lz)
  else
    lx, lz = math.sin(heading), math.cos(heading)
  end

  -- Follow velocity only while moving forwards. Reversing and spins keep the
  -- camera behind the nose instead of flipping 180 degrees.
  local forward = vx * lx + vz * lz
  local motion = smoothstep(2, 8, speed) * smoothstep(0, 0.35, forward / math.max(speed, 0.001))
  local travelYaw = heading
  if speed > 0.5 then
    travelYaw = smoothAngle(heading, math.atan2(vx, vz), motion * travelFollow)
  end
  local manual = clamp(number(ac.getDesiredLookDirection(), 0), -1, 1)
  local targetYaw = wrap(travelYaw + manual * pi * 0.75)

  local resetState = activeIndex ~= index or state.generation ~= generation or state.carIndex ~= car.index
    or state.replay ~= replay or state.replayDirection ~= replayDirection or step > 0.25
  if state.lastClock then
    local dx = origin.x - state.carX
    local dy = origin.y - state.carY
    local dz = origin.z - state.carZ
    local jumpDistance = 12 + speed * math.min(step, 0.25) * 3
    resetState = resetState or clock < state.lastClock or clock - state.lastClock > 500
      or dx * dx + dy * dy + dz * dz > jumpDistance * jumpDistance
  end

  local radius = distance + (index == 2 and 2 or 0)
  local camH = height + (index == 2 and 1.5 or 0)
  if resetState or not state.ready then
    state.yaw = targetYaw
  elseif step > 0 then
    state.yaw = smoothAngle(state.yaw, targetYaw, 1 - math.exp(-step / yawTime))
  end

  local slope = clamp(car.look.y, -0.45, 0.45) * radius * 0.25
  local tx = origin.x - math.sin(state.yaw) * radius
  local ty = origin.y + camH + slope
  local tz = origin.z - math.cos(state.yaw) * radius
  if resetState or not state.ready then
    state.position:set(tx, ty, tz)
    state.ready = true
  elseif step > 0 then
    local blend = 1 - math.exp(-step / moveTime)
    state.position:set(
      state.position.x + (tx - state.position.x) * blend,
      state.position.y + (ty - state.position.y) * blend,
      state.position.z + (tz - state.position.z) * blend)
  end
  cameraPosition:set(state.position)

  local ax = origin.x + math.sin(state.yaw) * lookAhead
  local ay = origin.y + 0.7
  local az = origin.z + math.cos(state.yaw) * lookAhead
  local dx = ax - cameraPosition.x
  local dy = ay - cameraPosition.y
  local dz = az - cameraPosition.z
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if length < 0.001 then
    dx, dy, dz, length = math.sin(state.yaw), 0, math.cos(state.yaw), 1
  end
  dx, dy, dz = dx / length, dy / length, dz / length
  cameraDirection:set(dx, dy, dz)

  local mix = 1 - horizonLock
  local ux = car.up.x * mix
  local uy = car.up.y * mix + horizonLock
  local uz = car.up.z * mix
  local projection = ux * dx + uy * dy + uz * dz
  ux, uy, uz = ux - projection * dx, uy - projection * dy, uz - projection * dz
  local upLength = math.sqrt(ux * ux + uy * uy + uz * uz)
  if upLength < 0.001 then
    ux, uy, uz = -dy * dx, 1 - dy * dy, -dy * dz
    upLength = math.sqrt(ux * ux + uy * uy + uz * uz)
    if upLength < 0.001 then
      ux, uy, uz = 1 - dx * dx, -dx * dy, -dx * dz
      upLength = math.sqrt(ux * ux + uy * uy + uz * uz)
    end
  end
  cameraUp:set(ux / upLength, uy / upLength, uz / upLength)

  ac.Camera.position = cameraPosition
  ac.Camera.direction = cameraDirection
  ac.Camera.up = cameraUp
  ac.Camera.fov = fov

  state.generation, state.carIndex = generation, car.index
  state.replay, state.replayDirection = replay, replayDirection
  state.heading, state.lastClock = heading, clock
  state.carX, state.carY, state.carZ = origin.x, origin.y, origin.z
  activeIndex = index
end
