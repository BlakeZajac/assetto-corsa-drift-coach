-- Body and wheel transforms come from the app SDK, not an estimated steering
-- ratio. Store world-space poses; ghost.lua converts them to each node's parent.
local M = { STRIDE = 49 }
local TWO_PI = 2 * math.pi

function M.new() return {phase = {}} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function appendPose(out, transform)
  if transform then
    local p,l,u=transform.position,transform.look,transform.up
    for _,v in ipairs({p.x,p.y,p.z,l.x,l.y,l.z,u.x,u.y,u.z}) do out[#out+1]=v end
  else for _=1,9 do out[#out+1]=0 end end
end

function M.capture(state, car, dt)
  local out = {}
  appendPose(out, car.bodyTransform)
  for i=0,3 do
    local w = car.wheels and car.wheels[i]
    appendPose(out, w and w.transform)
    local phase = state.phase[i] or 0
    if w and w.transformWheel and w.transform then
      local raw = math.atan2(dot(w.transformWheel.up,w.transform.look),dot(w.transformWheel.up,w.transform.up))
      local predicted = state.phase[i] and phase + (w.angularSpeed or 0)*dt or raw
      phase = raw + TWO_PI * math.floor((predicted-raw)/TWO_PI+0.5)
    end
    state.phase[i] = phase
    out[#out+1] = phase
  end
  return out
end

return M
