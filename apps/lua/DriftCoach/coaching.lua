-- References describe a demonstration, never a correction for a different car state.
local P = require('playback')
local M = {}
M.WAITING, M.MATCHED, M.LINE, M.SPEED, M.DIRECTION, M.GEAR, M.FINISHED, M.REPLAY = 1, 2, 3, 4, 5, 6, 7, 8

local function average(run, index, field)
  local span = math.max(1, math.floor(0.08 / run.dt))
  local sum, weight = 0, 0
  for i = math.max(1, index - span), math.min(P.count(run.samples), index + span) do
    local w = span + 1 - math.abs(i - index)
    sum, weight = sum + P.field(run.samples, i, field) * w, weight + w
  end
  return sum / math.max(1, weight)
end

local function trend(run, index, field)
  local n = P.count(run.samples)
  local span = math.max(1, math.floor(0.2 / run.dt))
  local change = average(run, math.min(n, index + span), field) - average(run, math.max(1, index - span), field)
  return change > 0.1 and 1 or change < -0.1 and -1 or 0
end

-- Look ahead in demonstration time. Require a change to persist for 0.1 s so
-- a single noisy pedal sample does not become an instruction.
function M.upcoming(run, index)
  local n, samples = P.count(run.samples), run.samples
  local hold = math.max(1, math.floor(0.1 / run.dt))
  local gas, brake = P.field(samples, index, 11), P.field(samples, index, 12)
  for i = index + 1, math.min(n - hold, index + math.floor(1.5 / run.dt)) do
    local code
    if brake < 0.08 and P.field(samples, i, 12) >= 0.15 then code = 1
    elseif gas >= 0.3 and P.field(samples, i, 11) <= gas - 0.25 then code = 2
    elseif gas < 0.1 and P.field(samples, i, 11) >= 0.3 then code = 3 end
    if code then
      local sustained = true
      for j = i, i + hold do
        if (code == 1 and P.field(samples, j, 12) < 0.15)
          or (code == 2 and P.field(samples, j, 11) > gas - 0.25)
          or (code == 3 and P.field(samples, j, 11) < 0.3) then sustained = false break end
      end
      if sustained then return code, (i - index) * run.dt end
    end
  end
  return 0, 0
end

function M.evaluate(run, index, distance, car, waiting, finished, replay, previous)
  if not index then return nil end
  local s = run.samples
  local out = {
    status = M.MATCHED, gas = average(run, index, 11), brake = average(run, index, 12),
    handbrake = P.field(s, index, 13), clutch = P.field(s, index, 14), steer = P.field(s, index, 15),
    speed = P.field(s, index, 10) * 3.6, gear = P.field(s, index, 16), slip = P.field(s, index, 17),
    distance = distance or math.huge, time = (index - 1) * run.dt,
    gasTrend = trend(run, index, 11), brakeTrend = trend(run, index, 12),
  }
  local v, look = car.velocity, car.look
  local speed = math.sqrt(v.x * v.x + v.z * v.z) * 3.6
  out.speedDelta = speed - out.speed
  local dot = look.x * P.field(s, index, 4) + look.z * P.field(s, index, 6)
  local length = math.sqrt((look.x * look.x + look.z * look.z)
    * (P.field(s, index, 4)^2 + P.field(s, index, 6)^2))
  out.headingDelta = math.deg(math.acos(math.max(-1, math.min(1, dot / math.max(1e-6, length)))))
  local from, to = math.max(1, index-3), math.min(P.count(s), index+3)
  local ax, _, az = P.xyz(s, from)
  local bx, _, bz = P.xyz(s, to)
  local tx, tz = bx-ax, bz-az
  local travelLength = math.sqrt((tx*tx+tz*tz)*(v.x*v.x+v.z*v.z))
  local wrongTravel = travelLength > 0.1 and (tx*v.x+tz*v.z)/travelLength < math.cos(math.rad(50))
  -- A slightly tighter return threshold stops warnings flickering at the edge.
  local previousStatus = previous and previous.status
  local lineLimit = previousStatus == M.LINE and 3 or 4
  local headingLimit = previousStatus == M.DIRECTION and 28 or 35
  local speedLimit = previousStatus == M.SPEED and math.max(10,out.speed*0.2) or math.max(12,out.speed*0.25)
  if replay then out.status = M.REPLAY
  elseif waiting then out.status = M.WAITING
  elseif finished then out.status = M.FINISHED
  elseif out.distance > lineLimit then out.status = M.LINE
  elseif out.headingDelta > headingLimit or wrongTravel then out.status = M.DIRECTION
  elseif math.abs(out.speedDelta) > speedLimit then out.status = M.SPEED
  elseif car.gear ~= out.gear then out.status = M.GEAR end
  out.comparable = out.status == M.MATCHED
  if out.comparable then out.cue, out.cueIn = M.upcoming(run, index)
  else out.cue, out.cueIn = 0, 0 end
  return out
end

function M.statusText(code)
  return ({'Approach the start circle', 'Reference inputs', 'Away from demonstration: line',
    'Away from demonstration: speed', 'Away from demonstration: direction',
    'Away from demonstration: gear', 'Section complete', 'Replay: reference paused'})[code] or 'Reference unavailable'
end

return M
