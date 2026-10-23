-- Telemetry sampling and practice-run detection, independent of rendering.
local M = {}
function M.number(v, fallback)
  if type(v) ~= 'number' or v ~= v or math.abs(v) == math.huge then return fallback end
  return v
end
function M.clamp(v, low, high) return math.max(low, math.min(high, M.number(v, low))) end
function M.clutch(car, invert)
  local value = M.clamp(car.clutch, 0, 1)
  return invert and 1 - value or value
end
function M.new()
  return { history = {}, head = 0, count = 0, sampleTime = 0,
    run = { seconds = 0, transitions = 0, peak = 0 }, gap = 0, side = 0 }
end

-- Horizontal velocity versus horizontal car heading, independent of steering
-- lock. Reverse and stationary motion do not qualify as a practice drift.
function M.angle(car)
  local v, look = car.velocity, car.look
  if not v or not look then return 0, false end
  local x, z = M.number(v.x, 0), M.number(v.z, 0)
  local lx, lz = M.number(look.x, 0), M.number(look.z, 0)
  local forward = x * lx + z * lz
  local lateral = x * lz - z * lx
  if forward <= 0.1 or lx * lx + lz * lz < 0.1 then return 0, false end
  return math.deg(math.atan(lateral / forward)), true
end

function M.finish(s)
  if s.run.seconds >= 1 then
    s.last = s.run
    if not s.best or s.run.seconds > s.best.seconds then s.best = s.run end
  end
  s.run = { seconds = 0, transitions = 0, peak = 0 }
  s.gap, s.side = 0, 0
end

function M.update(s, car, dt, paused, replay, invertClutch, ghost)
  -- `ghost` is the recorded pedal sample for this spot, or nil. Clutch is raw
  -- (1 = pedal down) and is inverted with the live clutch so the marks agree.
  s.ghost = nil
  if ghost then
    local clutch = M.clamp(ghost.clutch, 0, 1)
    s.ghost = {
      M.clamp(ghost.gas, 0, 1), M.clamp(ghost.brake, 0, 1),
      invertClutch and 1 - clutch or clutch, M.clamp(ghost.handbrake, 0, 1),
      M.number(ghost.steer, 0),
    }
  end
  if paused then return end
  dt = M.number(dt, 0)
  if dt <= 0 or dt > 0.25 then
    s.run = { seconds = 0, transitions = 0, peak = 0 }
    s.gap, s.side, s.history, s.count, s.head, s.sampleTime = 0, 0, {}, 0, 0, 0
    s.active = false
    return
  end
  s.angle, s.forward = M.angle(car)
  -- Sample at 20 Hz into a 160-entry ring (eight seconds). The renderer reads
  -- from head-count to head, so wrapping does not reorder the graph.
  s.sampleTime = s.sampleTime + dt
  while s.sampleTime >= 0.05 do
    s.sampleTime = s.sampleTime - 0.05
    s.head = s.head % 160 + 1
    local p = s.history[s.head] or {}
    p[1], p[2], p[3] = M.clamp(car.gas, 0, 1), M.clamp(car.brake, 0, 1), M.clutch(car, invertClutch)
    p[4], p[5], p[6] = M.clamp(car.handbrake, 0, 1), M.clamp(math.abs(M.number(car.ffbFinal, 0)), 0, 1), M.clamp(car.turboBoost, 0, 1)
    -- Channels 7..10 are the coach ghost, sampled on the same tick so the
    -- graph's right edge is "now" for both traces. Absent when no ghost is active.
    if s.ghost then p[7], p[8], p[9], p[10] = s.ghost[1], s.ghost[2], s.ghost[3], s.ghost[4]
    else p[7], p[8], p[9], p[10] = nil, nil, nil, nil end
    s.history[s.head], s.count = p, math.min(160, s.count + 1)
  end
  -- Replays remain telemetry viewers. They never contribute to live records.
  if replay then
    s.run, s.gap, s.side = { seconds = 0, transitions = 0, peak = 0 }, 0, 0
    s.active = false
    return
  end
  local a = math.abs(s.angle)
  -- Practice timing counts forward slides at >=20 km/h and 12..80 degrees.
  -- These thresholds are deliberately separate from the displayed slip angle.
  local valid = s.forward and M.number(car.speedKmh, 0) >= 20 and a >= 12 and a <= 80
    and car.isConnected ~= false and not car.isInPit and not car.isInPitlane
  s.active = valid
  if valid then
    local side = s.angle > 0 and 1 or -1
    if s.side ~= 0 and side ~= s.side then s.run.transitions = s.run.transitions + 1 end
    s.side, s.gap = side, 0
    s.run.seconds = s.run.seconds + dt
    s.run.peak = math.max(s.run.peak, a)
  elseif a > 85 or not s.forward or car.isInPit or car.isInPitlane then
    M.finish(s)
  elseif s.run.seconds > 0 then
    -- A short straight section can link a transition. Its time is not scored.
    s.gap = s.gap + dt
    if s.gap > 0.7 then M.finish(s) end
  end
end
return M
