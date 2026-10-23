-- Playback timing and spot matching. Samples use recorder.lua's 17-wide stride.
local M = {}
M.STRIDE = 17
M.VISUAL_STRIDE = require('visuals').STRIDE
M.INTERVAL = 1 / 30
local WINDOW_BACK = 8
local WINDOW_AHEAD = 45
local LOST = 12

function M.count(samples)
  if not samples then return 0 end
  return math.floor(#samples / M.STRIDE)
end

function M.visualPose(visuals, time, dt, out)
  if not visuals then return nil end
  local n=math.floor(#visuals/M.VISUAL_STRIDE)
  if n==0 then return nil end
  out=out or {}
  local frame=math.max(0, math.min(n-1,time/dt))
  local index=math.min(n,math.floor(frame)+1)
  local blend=frame-(index-1)
  for k=1,M.VISUAL_STRIDE do
    local a=visuals[(index-1)*M.VISUAL_STRIDE+k] or 0
    local b=visuals[math.min(n-1,index)*M.VISUAL_STRIDE+k] or a
    out[k]=a+(b-a)*blend
  end
  return out
end

function M.xyz(samples, index)
  local base = (index - 1) * M.STRIDE
  return samples[base + 1] or 0, samples[base + 2] or 0, samples[base + 3] or 0
end

function M.field(samples, index, field)
  return samples[(index - 1) * M.STRIDE + field] or 0
end

function M.duration(samples, dt)
  local n = M.count(samples)
  if n <= 1 then return 0 end
  return (n - 1) * (dt or M.INTERVAL)
end

local function scored(samples, cursor, x, y, z, n)
  local bestIndex, bestScore = 1, 1e18
  for i = 1, n do
    local px, py, pz = M.xyz(samples, i)
    local dx, dy, dz = px - x, py - y, pz - z
    local along = (i - cursor) / 30
    local score = dx * dx + dy * dy + dz * dz + along * along * 16
    if score < bestScore then bestScore, bestIndex = score, i end
  end
  local px, py, pz = M.xyz(samples, bestIndex)
  local dx, dy, dz = px - x, py - y, pz - z
  return bestIndex, dx * dx + dy * dy + dz * dz
end

-- Nearest recorded point in a short window ahead of the previous match.
-- The window stops a crossing of the same road, later in the run, from
-- stealing the match. If the car has left that window, a wider search still
-- prefers points near the previous match.
function M.nearest(samples, cursor, x, y, z)
  local n = M.count(samples)
  if n == 0 then return nil, nil end
  cursor = math.max(1, math.min(n, cursor or 1))
  local from = math.max(1, cursor - WINDOW_BACK)
  local to = math.min(n, cursor + WINDOW_AHEAD)
  local bestIndex, bestDistance = from, 1e18
  for i = from, to do
    local px, py, pz = M.xyz(samples, i)
    local dx, dy, dz = px - x, py - y, pz - z
    local distance = dx * dx + dy * dy + dz * dz
    if distance < bestDistance then bestDistance, bestIndex = distance, i end
  end
  if bestDistance > LOST * LOST then
    bestIndex, bestDistance = scored(samples, cursor, x, y, z, n)
  end
  return bestIndex, math.sqrt(bestDistance)
end

local function normalize(out, origin)
  local x, y, z = out[origin] or 0, out[origin + 1] or 0, out[origin + 2] or 0
  local mag = math.sqrt(x * x + y * y + z * z)
  if mag < 1e-4 then
    -- Look falls back to +Z. Up falls back to +Y.
    out[origin], out[origin + 1], out[origin + 2] = 0, origin == 7 and 1 or 0, origin == 4 and 1 or 0
    return
  end
  out[origin], out[origin + 1], out[origin + 2] = x / mag, y / mag, z / mag
end

function M.pose(samples, time, dt, out)
  local n = M.count(samples)
  if n == 0 then return nil end
  out = out or {}
  dt = (dt and dt > 0) and dt or M.INTERVAL
  local maxTime = (n - 1) * dt
  if time < 0 then time = 0 end
  local ended = time >= maxTime - 1e-4
  if time > maxTime then time = maxTime end
  local frame = time / dt
  local index = math.floor(frame) + 1
  if index < 1 then index = 1 end
  if index >= n then index = n - 1 end
  if n == 1 then index = 1 end
  local blend = frame - (index - 1)
  if blend < 0 then blend = 0 end
  if blend > 1 then blend = 1 end
  local base = (index - 1) * M.STRIDE
  for k = 1, M.STRIDE do
    local from = samples[base + k] or 0
    local to = samples[base + M.STRIDE + k]
    if to == nil or k == 16 then
      out[k] = (blend < 0.5 or to == nil) and from or to
    else
      out[k] = from + (to - from) * blend
    end
  end
  normalize(out, 4)
  normalize(out, 7)
  out.index = index
  out.ended = ended
  return out
end

function M.newPlayer()
  return { started = false, time = 0, cursor = 1, pose = {} }
end

function M.resetPlayer(player)
  player.started = false
  player.time = 0
  player.cursor = 1
  player._leftStart = false
  player._reference, player._match = nil, nil
  player._waiting, player._ended, player._distance = true, false, nil
end

-- `step` is the frame delta in seconds, or 0 while paused. The ghost waits
-- at the first sample until the car drives through the start circle.
function M.advance(player, samples, dt, x, y, z, speed, radius, step, vx, vz)
  local n = M.count(samples)
  if n == 0 then return nil, nil, nil, true end
  local sx, sy, sz = M.xyz(samples, 1)
  local dx, dy, dz = x - sx, y - sy, z - sz
  local forward = true
  if vx and vz then
    local tx, tz = 0, 0
    for i = 2, math.min(n, 31) do
      local px, _, pz = M.xyz(samples, i)
      tx, tz = px - sx, pz - sz
      if tx*tx+tz*tz > 1 then break end
    end
    forward = tx*vx+tz*vz > 0
  end
  if not player.started and (step or 0) > 0 and forward and dx * dx + dy * dy + dz * dz <= radius * radius and (speed or 0) >= 2 then
    player.started = true
    player.time = 0
    player.cursor = 1
  elseif player.started and step and step > 0 then
    local maxTime = M.duration(samples, dt)
    if player.time < maxTime then player.time = math.min(maxTime, player.time + step) end
  end
  local ghost = M.pose(samples, player.started and player.time or 0, dt, player.pose)
  local index, distance = M.nearest(samples, player.cursor, x, y, z)
  if index then player.cursor = index end
  return index, distance, ghost, not player.started
end

function M.gapText(delta)
  local amount = math.abs(delta or 0)
  if amount < 0.15 then return 'Level with the ghost' end
  if delta > 0 then return string.format('Ghost ahead %.1f s', amount) end
  return string.format('Ghost behind %.1f s', amount)
end

return M
