-- Records a driven line and plays it back as a ghost, a painted path and the
-- pedal values Drift HUD reads from the shared block below. Keep that block
-- identical to the one in Drift HUD.
local Recorder = require('recorder')
local Playback = require('playback')
local Runs = require('runs')
local Paint = require('paint')
local Ghost = require('ghost')

local shared = ac.connect({
  ac.StructItem.key('driftCoach.v1'),
  active = ac.StructItem.boolean(),
  beat = ac.StructItem.int32(),
  gas = ac.StructItem.float(),
  brake = ac.StructItem.float(),
  handbrake = ac.StructItem.float(),
  clutch = ac.StructItem.float(),
  steer = ac.StructItem.float(),
  slip = ac.StructItem.float(),
  delta = ac.StructItem.float(),
  angleDelta = ac.StructItem.float(),
}, true)

local prefs = ac.storage({
  line = true, ghost = true, opacity = 0.9, radius = 4, teaching = '', teachingKey = '', recordName = 'Teaching run',
}, 'driftCoach.')
local recordButton = ac.ControlButton('driftCoach/Record')
local resetButton = ac.ControlButton('driftCoach/Reset ghost')
local recorder = Recorder.new()
local player = Playback.newPlayer()
local paint = Paint.new()
local ghost = Ghost.new()
local active, message, status, indexKey, index, renameDraft, pendingDelete, bootedKey
local anchorX, anchorY, anchorZ

local function clamp(value, low, high)
  value = type(value) == 'number' and value == value and math.abs(value) ~= math.huge and value or low
  return math.max(low, math.min(high, value))
end

local function slipOf(car)
  local velocity, look = car.velocity, car.look
  if not velocity or not look then return 0 end
  local forward = velocity.x * look.x + velocity.z * look.z
  local lateral = velocity.x * look.z - velocity.z * look.x
  if forward <= 0.1 then return 0 end
  return math.deg(math.atan(lateral / forward))
end

local function contextOf(car)
  if not car or car.isConnected == false then return nil end
  return { track = ac.getTrackID(), layout = ac.getTrackLayout() or '', car = ac.getCarID(car.index) }
end

local function keyOf(context)
  return context.track .. '|' .. context.layout .. '|' .. context.car
end

local function runsFor(context)
  local key = keyOf(context)
  if key ~= indexKey then
    indexKey = key
    index = Runs.loadIndex(Runs.folderFor(context.track, context.layout, context.car))
  end
  return index
end

local function publish(match)
  shared.beat = shared.beat + 1
  if shared.beat > 2000000000 then shared.beat = 1 end
  shared.active = match ~= nil
  shared.gas = match and match.gas or 0
  shared.brake = match and match.brake or 0
  shared.handbrake = match and match.handbrake or 0
  shared.clutch = match and match.clutch or 0
  shared.steer = match and match.steer or 0
  shared.slip = match and match.slip or 0
  shared.delta = match and match.delta or 0
  shared.angleDelta = match and match.angleDelta or 0
end

local function openRun(context, id)
  local run, err = Runs.load(context.track, context.layout, context.car, id)
  if not run then message = err return end
  active = run
  renameDraft = run.name
  Playback.resetPlayer(player)
  Ghost.useCar(ghost, run.car)
  status = nil
end

local function finishRecording(context)
  local samples = Recorder.stop(recorder)
  anchorX = nil
  if not context then
    message = 'The session ended before the run could be saved.'
    return
  end
  if Playback.count(samples) < 30 then
    message = 'That run was shorter than a second, so it was not saved.'
    return
  end
  local name = prefs.recordName ~= '' and prefs.recordName or 'Teaching run'
  local id, err = Runs.save(context.track, context.layout, context.car, {
    name = name, when = os.time(), dt = Recorder.INTERVAL, samples = samples,
  })
  if not id then message = err return end
  indexKey = nil
  prefs.teaching, prefs.teachingKey = id, keyOf(context)
  openRun(context, id)
  message = 'Saved ' .. name .. '.'
end

local function toggleRecord(context)
  if recorder.recording then finishRecording(context) return end
  if not context then message = 'Start a driving session before recording.' return end
  Recorder.start(recorder)
  anchorX = nil
  message = nil
end

function script.update(dt)
  local sim = ac.getSim()
  dt = type(dt) == 'number' and dt > 0 and dt or 0
  if recordButton:pressed() then toggleRecord(contextOf(ac.getCar(0))) end
  if resetButton:pressed() then Playback.resetPlayer(player) end

  local playerCar = ac.getCar(0)
  local context = contextOf(playerCar)
  local wasRecording = recorder.recording
  if recorder.recording then
    if not context then
      Recorder.observe(recorder, nil, dt, { paused = true })
    else
      local pos, look, up = playerCar.transform.position, playerCar.look, playerCar.up
      local vx, vz = playerCar.velocity.x, playerCar.velocity.z
      local speed = math.sqrt(vx * vx + vz * vz)
      local jump = false
      if anchorX then
        local limit = Recorder.jumpDistance(speed, dt)
        local dx, dy, dz = pos.x - anchorX, pos.y - anchorY, pos.z - anchorZ
        jump = dx * dx + dy * dy + dz * dz > limit * limit
      end
      Recorder.observe(recorder, {
        pos.x, pos.y, pos.z, look.x, look.y, look.z, up.x, up.y, up.z, speed,
        clamp(playerCar.gas, 0, 1), clamp(playerCar.brake, 0, 1), clamp(playerCar.handbrake, 0, 1),
        clamp(playerCar.clutch, 0, 1), playerCar.steer or 0, playerCar.gear or 0, slipOf(playerCar),
      }, dt, { paused = sim.isPaused or sim.isInMainMenu, replay = sim.isReplayActive, jump = jump })
      anchorX, anchorY, anchorZ = pos.x, pos.y, pos.z
    end
    status = recorder.note
    if wasRecording and not recorder.recording then finishRecording(context) end
  end

  if context and prefs.teaching ~= '' and prefs.teachingKey == keyOf(context) and bootedKey ~= prefs.teachingKey then
    bootedKey = prefs.teachingKey
    if not active or active.id ~= prefs.teaching then openRun(context, prefs.teaching) end
  end

  local follow = sim.focusedCar >= 0 and ac.getCar(sim.focusedCar) or playerCar
  local match
  if active and follow and follow.transform and follow.isConnected ~= false then
    local pos = follow.transform.position
    local vx, vz = follow.velocity.x, follow.velocity.z
    local speed = math.sqrt(vx * vx + vz * vz)
    local step = (sim.isPaused or sim.isReplayActive) and 0 or math.min(dt, 0.25)
    local index, distance, pose, waiting = Playback.advance(player, active.samples, active.dt,
      pos.x, pos.y, pos.z, speed, clamp(prefs.radius, 2, 12), step)
    if pose and prefs.ghost ~= false then
      if Ghost.place(ghost, pose, true) then Ghost.drawFallback(ghost) end
    else
      Ghost.place(ghost, nil, false)
    end
    if index and distance and distance <= 12 then
      local recorded = Playback.field(active.samples, index, 17)
      match = {
        gas = Playback.field(active.samples, index, 11),
        brake = Playback.field(active.samples, index, 12),
        handbrake = Playback.field(active.samples, index, 13),
        clutch = Playback.field(active.samples, index, 14),
        steer = Playback.field(active.samples, index, 15),
        slip = recorded,
        delta = player.started and (player.time - (index - 1) * active.dt) or 0,
        angleDelta = slipOf(follow) - recorded,
        waiting = waiting,
        distance = distance,
        ended = pose and pose.ended,
      }
    end
    player._waiting = waiting
    player._ended = pose and pose.ended
    player._distance = distance
  else
    Ghost.place(ghost, nil, false)
    player._waiting, player._ended, player._distance = false, false, nil
  end
  if active then Ghost.useCar(ghost, active.car) end
  Paint.sync(paint, prefs.line ~= false and active or nil, prefs.line ~= false, clamp(prefs.opacity, 0.15, 1), clamp(prefs.radius, 2, 12))
  publish(match)
  player._match = match
end

function script.destroy()
  publish(nil)
  Ghost.clear(ghost)
end

local function sameCar(entry, context)
  return entry.track == context.track and entry.layout == context.layout and entry.car == context.car
end

function script.windowMain()
  local context = contextOf(ac.getCar(0))
  if message then ui.textWrapped(message) end
  if recorder.recording then
    ui.text(string.format('Recording  %.0f s', Recorder.liveSamples(recorder) / 30))
    if status then ui.textWrapped(status) end
    if ui.button('Stop and save') then toggleRecord(context) end
  else
    prefs.recordName = ui.inputText('Recording name', prefs.recordName or 'Teaching run')
    if ui.button('Record') then toggleRecord(context) end
  end
  ui.sameLine()
  if ui.button('Reset ghost') then Playback.resetPlayer(player) end
  ui.separator()
  if ui.checkbox('Painted line', prefs.line ~= false) then prefs.line = not (prefs.line ~= false) end
  ui.sameLine()
  if ui.checkbox('Ghost car', prefs.ghost ~= false) then prefs.ghost = not (prefs.ghost ~= false) end
  if not active then
    ui.textWrapped('Record a clean run, then have your friend drive through the white start circle. The ghost follows your timing. The painted line and Drift HUD show what you did at their position.')
  else
    ui.text(active.name .. string.format('  /  %.0f s', Playback.duration(active.samples, active.dt)))
    if player._waiting then ui.text('Drive through the start circle to release the ghost.')
    elseif player._match then ui.text(Playback.gapText(player._match.delta))
    elseif player._distance then ui.text(string.format('%.0f m off the recorded line', player._distance)) end
    if player._match then
      ui.text(string.format('Reference slip %.0f deg  /  difference %+.0f deg', player._match.slip, player._match.angleDelta))
    end
    if player._ended then ui.text('Ghost reached the end of the run.') end
    if ghost.error then ui.textWrapped(ghost.error) end
    renameDraft = ui.inputText('Saved name', renameDraft or active.name)
    if ui.button('Rename') and context then
      local renamed, err = Runs.rename(context.track, context.layout, context.car, active.id, renameDraft)
      if renamed then active.name = renamed indexKey = nil else message = err end
    end
  end
  ui.separator()
  ui.text('Saved runs')
  if not context then ui.text('Load a track to see runs for this car.') return end
  local runs = runsFor(context)
  local shown = 0
  for i = #runs.runs, 1, -1 do
    local entry = runs.runs[i]
    if sameCar(entry, context) then
      shown = shown + 1
      ui.pushID(entry.id)
      local label = string.format('%s  /  %.0f s', entry.name or 'Run', entry.seconds or 0)
      if active and active.id == entry.id then label = label .. '  (teaching)' end
      ui.text(label)
      if ui.button('Use') then
        prefs.teaching, prefs.teachingKey = entry.id, keyOf(context)
        openRun(context, entry.id)
      end
      ui.sameLine()
      if pendingDelete == entry.id then
        if ui.button('Confirm delete') then
          Runs.delete(context.track, context.layout, context.car, entry.id)
          if active and active.id == entry.id then active = nil Ghost.clear(ghost) Playback.resetPlayer(player) end
          if prefs.teaching == entry.id then prefs.teaching = '' end
          pendingDelete, indexKey = nil, nil
        end
      elseif ui.button('Delete') then pendingDelete = entry.id end
      ui.popID()
      if shown >= 30 then break end
    end
  end
  if shown == 0 then ui.text('No runs for this track and car yet.') end
end

function script.windowSettings()
  if ui.checkbox('Painted line', prefs.line ~= false) then prefs.line = not (prefs.line ~= false) end
  if ui.checkbox('Ghost car', prefs.ghost ~= false) then prefs.ghost = not (prefs.ghost ~= false) end
  prefs.opacity = ui.slider('Line opacity', clamp(prefs.opacity, 0.15, 1), 0.15, 1, '%.2f')
  prefs.radius = ui.slider('Start circle radius', clamp(prefs.radius, 2, 12), 2, 12, '%.1f m')
  ui.separator()
  ui.text('Record')
  recordButton:control(vec2(220, 24))
  ui.text('Reset ghost')
  resetButton:control(vec2(220, 24))
  ui.separator()
  ui.textWrapped('Chase cameras are chosen in CSP settings. Drift Passenger, Drift Coach and Drift Wheel are separate scripts. This window does not switch them.')
  ui.textWrapped('Green paint is throttle, red is brake, purple is handbrake and a blue circle is a clutch kick. Drift HUD can draw the recorded pedals on top of the live meters. The ghost body does not steer its wheels.')
end

ac.onCarJumped(0, function()
  Playback.resetPlayer(player)
end)
