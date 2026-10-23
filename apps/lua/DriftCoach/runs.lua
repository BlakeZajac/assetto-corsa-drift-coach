-- Run files live in the player's Documents folder, grouped by track, layout
-- and car. They are not part of the game install or this repository.
local Playback = require('playback')
local M = {}

function M.folderFor(track, layout, car)
  local function safe(value)
    local text = tostring(value or 'none'):gsub('[^%w%._%-]+', '_')
    if text == '' then text = 'none' end
    return text:sub(1, 48)
  end
  return string.format('%s/drift-coach/%s/%s/%s', ac.getFolder(ac.FolderID.ACDocuments),
    safe(track), safe(layout), safe(car))
end

function M.ensure(folder)
  local built = ''
  local rooted = folder:sub(1, 1) == '/' or folder:sub(1, 1) == '\\'
  for part in tostring(folder):gmatch('[^/\\]+') do
    if built == '' then
      built = (rooted and '/' or '') .. part
    else
      built = built .. '/' .. part
    end
    io.createDir(built)
  end
end

local function clean(value)
  return tostring(value or ''):gsub('[\r\n]', ' ')
end

function M.encode(run)
  local lines = {
    'DRIFTCOACH 1',
    clean(run.name),
    clean(run.track),
    clean(run.layout),
    clean(run.car),
    tostring(math.floor(run.when or 0)),
    string.format('%.5f', run.dt or Playback.INTERVAL),
    tostring(Playback.count(run.samples)),
  }
  local stride = Playback.STRIDE
  for base = 1, #run.samples, stride do
    local row = {}
    for k = 0, stride - 1 do
      row[k + 1] = string.format('%.4f', run.samples[base + k] or 0)
    end
    lines[#lines + 1] = table.concat(row, ' ')
  end
  return table.concat(lines, '\n')
end

function M.decode(text)
  if type(text) ~= 'string' or text == '' then return nil, 'empty run' end
  local lines = {}
  local startAt = 1
  while startAt <= #text + 1 do
    local newline = text:find('\n', startAt, true)
    if not newline then
      lines[#lines + 1] = text:sub(startAt):gsub('\r$', '')
      break
    end
    lines[#lines + 1] = text:sub(startAt, newline - 1):gsub('\r$', '')
    startAt = newline + 1
  end
  if lines[1] ~= 'DRIFTCOACH 1' then return nil, 'unrecognised run file' end
  local count = tonumber(lines[8])
  if not count or count < 2 then return nil, 'run is too short' end
  local samples = {}
  local rows = 0
  for i = 9, #lines do
    rows = rows + 1
    local fields = 0
    for word in lines[i]:gmatch('%S+') do
      fields = fields + 1
      samples[#samples + 1] = tonumber(word) or 0
    end
    if fields ~= Playback.STRIDE then return nil, 'damaged run sample' end
  end
  if rows ~= count then return nil, 'run file was cut short' end
  return {
    name = lines[2], track = lines[3], layout = lines[4], car = lines[5],
    when = tonumber(lines[6]) or 0, dt = tonumber(lines[7]) or Playback.INTERVAL,
    samples = samples,
  }
end

function M.loadIndex(folder)
  local parsed = stringify.tryParse(io.load(folder .. '/index.txt', '') or '', {})
  if type(parsed) ~= 'table' or type(parsed.runs) ~= 'table' then return { runs = {} } end
  return parsed
end

function M.writeIndex(folder, index)
  M.ensure(folder)
  return io.save(folder .. '/index.txt', stringify(index, true), true)
end

function M.save(track, layout, car, run)
  local folder = M.folderFor(track, layout, car)
  M.ensure(folder)
  run.track, run.layout, run.car = track, layout or '', car
  run.dt = run.dt or Playback.INTERVAL
  local id = string.format('%d-%04d', math.floor(run.when or os.time()), math.random(0, 9999))
  local file = id .. '.run'
  if not io.save(folder .. '/' .. file, M.encode(run), true) then return nil, 'Could not save the run' end
  local index = M.loadIndex(folder)
  index.runs[#index.runs + 1] = {
    id = id, name = run.name, file = file,
    seconds = Playback.duration(run.samples, run.dt),
    when = run.when, track = run.track, layout = run.layout, car = run.car,
  }
  while #index.runs > 100 do
    local old = table.remove(index.runs, 1)
    if old and old.file then io.deleteFile(folder .. '/' .. old.file) end
  end
  M.writeIndex(folder, index)
  return id
end

function M.load(track, layout, car, id)
  local folder = M.folderFor(track, layout, car)
  local index = M.loadIndex(folder)
  local entry
  for i = 1, #index.runs do
    if index.runs[i].id == id then entry = index.runs[i] break end
  end
  if not entry then return nil, 'Run is not in the list' end
  local run, err = M.decode(io.load(folder .. '/' .. entry.file, '') or '')
  if not run then return nil, err end
  run.id = entry.id
  run.name = entry.name or run.name
  return run
end

function M.rename(track, layout, car, id, name)
  local folder = M.folderFor(track, layout, car)
  local index = M.loadIndex(folder)
  for i = 1, #index.runs do
    if index.runs[i].id == id then
      index.runs[i].name = clean(name)
      if M.writeIndex(folder, index) then return index.runs[i].name end
      return nil, 'Could not rename the run'
    end
  end
  return nil, 'Run is not in the list'
end

function M.delete(track, layout, car, id)
  local folder = M.folderFor(track, layout, car)
  local index = M.loadIndex(folder)
  for i = 1, #index.runs do
    if index.runs[i].id == id then
      io.deleteFile(folder .. '/' .. (index.runs[i].file or ''))
      table.remove(index.runs, i)
      M.writeIndex(folder, index)
      return true
    end
  end
  return false
end

return M
