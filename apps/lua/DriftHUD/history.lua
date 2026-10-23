local T = require('telemetry')
local H = {}
-- Validate persisted JSON before allowing writes. A newer schema or corrupt
-- record must not cause this version to overwrite the user's saved history.
local function validRun(r)
  return type(r) == 'table' and type(r.track) == 'string' and #r.track <= 256
    and type(r.layout) == 'string' and #r.layout <= 256 and type(r.car) == 'string' and #r.car <= 256
    and T.number(r.seconds, 0) >= 1 and r.seconds <= 86400
    and T.number(r.peak, -1) >= 0 and r.peak <= 80.01
    and T.number(r.transitions, -1) >= 0 and r.transitions <= 100000 and r.transitions % 1 == 0
    and T.number(r.when, -1) >= 0
end
function H.same(a, b, car)
  return a.track == b.track and a.layout == b.layout and (not car or a.car == b.car)
end
function H.new(raw)
  local h = {recent = {}, best = {}}
  if not raw or raw == '' then return h end
  local ok, data = pcall(JSON.parse, raw)
  if not ok or type(data) ~= 'table' or data.version ~= 1 or type(data.recent) ~= 'table'
    or type(data.best) ~= 'table' or #data.recent > 500 or #data.best > 500 then
    h.error = 'Practice history could not be read. Existing data has been kept.'; return h
  end
  for _, list in ipairs({data.recent, data.best}) do
    for _, run in ipairs(list) do
      if not validRun(run) then h.error = 'Practice history contains an invalid run. Existing data has been kept.'; return h end
    end
  end
  h.recent, h.best = data.recent, data.best
  return h
end
function H.add(h, context, run, when)
  if h.error then return nil end
  local r = {track = context.track, layout = context.layout, car = context.car, when = when,
    seconds = run.seconds, transitions = run.transitions, peak = run.peak}
  if not validRun(r) then return nil end
  table.insert(h.recent, 1, r)
  if #h.recent > 500 then table.remove(h.recent) end
  -- Bests are retained independently of the 500-run rolling history.
  local found
  for i, best in ipairs(h.best) do
    if H.same(best, context, true) then
      found = true
      if r.seconds > best.seconds then table.remove(h.best, i); table.insert(h.best, 1, r) end
      break
    end
  end
  if not found then table.insert(h.best, 1, r) end
  if #h.best > 500 then table.remove(h.best) end
  return r
end
function H.bestFor(h, context)
  for _, run in ipairs(h.best) do if H.same(run, context, true) then return run end end
end
function H.encode(h) return JSON.stringify({version = 1, recent = h.recent, best = h.best}) end
return H
