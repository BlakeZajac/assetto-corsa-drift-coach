local T = require('telemetry')
local View = require('view')
local History = require('history')
local Layout = require('layout')
local historyStore = ac.storage({json = ''}, 'driftHUD.history.')
local history = History.new(historyStore.json)
local context, onlyCar = nil, true
local state = T.new()
-- Same layout as Drift Coach's shared block. Pedal values are the recorded
-- inputs at the student's position on the line.
local coach = ac.connect({
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
-- Keep this layout identical to Drift Coach's additive context channel.
local coachContext = ac.connect({
  ac.StructItem.key('driftCoach.context.v1'),
  available = ac.StructItem.boolean(), beat = ac.StructItem.int32(), status = ac.StructItem.int32(),
  gas = ac.StructItem.float(), brake = ac.StructItem.float(), speed = ac.StructItem.float(),
  gear = ac.StructItem.int32(), cue = ac.StructItem.int32(), cueIn = ac.StructItem.float(),
  gasTrend = ac.StructItem.int32(), brakeTrend = ac.StructItem.int32(),
}, true)
local coachBeat, coachSeen = -1, 0
local contextBeat, contextSeen = -1, 1
local prefs = ac.storage({ mph = false, invertClutch = true, backgroundOpacity = 0.18,
  dockBottom = true, driving = true, steering = true, inputs = true, graph = true, tyres = true, drift = true,
  coachGhost = true, coachPanel = true,
  trace1 = true, trace2 = true, trace3 = true, trace4 = true, trace5 = true, trace6 = true }, 'driftHUD.')
prefs.backgroundOpacity = T.clamp(prefs.backgroundOpacity, 0, 1)
local car, identity, replayFrame, replayMode
local function reset() state = T.new(); identity, replayFrame, replayMode = nil, nil, nil end
ac.onSessionStart(reset)
ac.onCarJumped(-1, function(index) if car and car.index == index then reset() end end)

function script.update(dt)
  local sim = ac.getSim()
  car = sim.focusedCar >= 0 and ac.getCar(sim.focusedCar) or nil
  if not car or car.isConnected == false then reset(); car = nil; Layout.update(prefs, false); return end
  local id = car.index
  local isReplay = sim.isReplayActive
  if identity ~= id or replayMode ~= isReplay
      or (isReplay and replayFrame and math.abs(sim.replayCurrentFrame - replayFrame) > 5) then
    reset()
  end
  if not identity then
    context = {track = ac.getTrackID(), layout = ac.getTrackLayout() or '', car = ac.getCarID(id)}
    state.trackBest = History.bestFor(history, context)
  end
  identity, replayMode, replayFrame = id, isReplay, sim.replayCurrentFrame
  local previous = state.last
  coachSeen = coachSeen + (dt or 0)
  if coach.beat ~= coachBeat then coachBeat, coachSeen = coach.beat, 0 end
  contextSeen = contextSeen + (dt or 0)
  if coachContext.beat ~= contextBeat then contextBeat, contextSeen = coachContext.beat, 0 end
  local coachLive = prefs.coachGhost ~= false and coach.active and coachSeen < 0.5 and not isReplay
  T.update(state, car, dt, sim.isPaused or sim.isInMainMenu, isReplay, prefs.invertClutch,
    coachLive and { gas = coach.gas, brake = coach.brake, handbrake = coach.handbrake, clutch = coach.clutch, steer = coach.steer } or nil)
  state.coach = nil
  if prefs.coachPanel ~= false and coachContext.available and contextSeen < 0.5 then
    state.coach = {status = coachContext.status, gas = coachContext.gas, brake = coachContext.brake,
      speed = coachContext.speed, gear = coachContext.gear, cue = coachContext.cue, cueIn = coachContext.cueIn,
      gasTrend = coachContext.gasTrend, brakeTrend = coachContext.brakeTrend}
    if isReplay then state.coach.status, state.coach.cue = 8, 0 end
  end
  Layout.update(prefs, state.coach ~= nil)
  -- Only player driving contributes records. Spectating stays a telemetry view.
  if state.last and state.last ~= previous and not isReplay and id == 0 then
    if History.add(history, context, state.last, os.time()) then
      historyStore.json = History.encode(history)
      state.trackBest = History.bestFor(history, context)
    end
  end
end

function script.windowMain()
  View.draw(car, state, prefs, ui.windowWidth(), ac.getSim().isReplayActive)
end

function script.windowSettings()
  local function toggle(label, key)
    if ui.checkbox(label, prefs[key]) then prefs[key] = not prefs[key] end
  end
  toggle('Speed in MPH', 'mph')
  toggle('Invert clutch telemetry', 'invertClutch')
  toggle('Dock panels at bottom centre', 'dockBottom')
  toggle('Speed, gear, RPM and fuel', 'driving')
  toggle('Steering indicator', 'steering')
  toggle('Input meters', 'inputs')
  local oldTyres, oldGraph = prefs.tyres, prefs.graph
  toggle('Tyres (separate window)', 'tyres')
  toggle('Input history (separate window)', 'graph')
  if oldTyres ~= prefs.tyres then ac.setWindowOpen('tyres', prefs.tyres) end
  if oldGraph ~= prefs.graph then ac.setWindowOpen('inputs', prefs.graph) end
  toggle('Drift angle and practice runs', 'drift')
  toggle('Show coach ghost inputs', 'coachGhost')
  toggle('Show demo / learner coaching panel', 'coachPanel')
  ui.textWrapped('Coach marks are the recorded pedals and steering from Drift Coach. They show on the meters, the steering wheel and the input history while a teaching run is active.')
  prefs.backgroundOpacity = ui.slider('Background opacity', prefs.backgroundOpacity, 0, 1, '%.2f')
  ui.textWrapped('Panels open together and dock Inputs / Info / Tyres at the bottom. Close a panel to recenter the others. Disable docking for free placement. Channels below control input meters and history.')
  ui.separator()
  ui.text('History channels')
  for i, label in ipairs({'Throttle', 'Brake', 'Clutch', 'Handbrake', 'FFB', 'Boost'}) do
    toggle(label .. '##trace', 'trace' .. i)
  end
  ui.separator()
  ui.textWrapped('Completed player runs are saved by track, layout and car. Pauses, spectating and replays do not add records. Short straight sections link turns but add no drift time. Resets clear the current run and input graph. Saved records remain in Practice history.')
  ui.textWrapped('Check that the clutch meter reads zero with your foot off the pedal. Toggle clutch inversion if needed. Tyre values are measurements, not recommended temperatures or pressures. Boost and FFB meters saturate at 100%.')
  if ui.button('Clear practice runs and input history') then reset() end
end

function script.windowInputs()
  View.draw(car, state, prefs, ui.windowWidth(), ac.getSim().isReplayActive, 'graph')
end

function script.windowTyres()
  View.draw(car, state, prefs, ui.windowWidth(), ac.getSim().isReplayActive, 'tyres')
end

function script.windowHistory()
  ui.text('Practice history')
  if history.error then ui.textWrapped(history.error); return end
  if not context then ui.text('Load a track to compare runs.'); return end
  ui.text(context.track .. (context.layout ~= '' and ' / ' .. context.layout or ''))
  if ui.checkbox('Only this car', onlyCar) then onlyCar = not onlyCar end
  ui.textWrapped('Best means longest recorded drift time. Conditions and assists can differ. This is a practice log, not a competitive score.')
  ui.separator()
  for _, best in ipairs(history.best) do
    if History.same(best, context, onlyCar) then
      ui.text(string.format('Best / %s / %.1fs / %d transitions / %.0f deg peak', best.car, best.seconds, best.transitions, best.peak))
    end
  end
  ui.separator()
  local count = 0
  for _, run in ipairs(history.recent) do
    if History.same(run, context, onlyCar) then
      local best = History.bestFor(history, run)
      ui.text(string.format('%s / %s / %.1fs / %s / %d turns / %.0f deg',
        os.date('%d %b %H:%M', run.when), run.car, run.seconds,
        best and string.format('%+.1fs to best', run.seconds - best.seconds) or 'best unavailable', run.transitions, run.peak))
      count = count + 1
      if count >= 30 then break end
    end
  end
  if count == 0 then ui.text('No completed runs recorded here yet.'); end
  ui.textWrapped('Keeps the latest 500 runs and bests for up to 500 track/layout/car combinations. Runs shorter than one second are omitted.')
end
