-- Translucent copy of the recorded car. Wheels stay straight; the recorded
-- steer angle is shown by Drift HUD instead. A debug box stands in until the
-- model loads, and remains if the KN5 cannot be found.
local M = {}

local function existing(root, name)
  if type(name) ~= 'string' or name == '' then return nil end
  if io.fileExists(name) then return name end
  local path = root .. '/' .. name
  if io.fileExists(path) then return path end
  return nil
end

function M.findModel(carId)
  if not carId or carId == '' then return nil, nil end
  local root = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carId
  local main, lod
  local ok, lods = pcall(ac.INIConfig.load, root .. '/data/lods.ini')
  if ok and lods then
    main = existing(root, lods:get('LOD_0', 'FILE', ''))
    lod = existing(root, lods:get('LOD_1', 'FILE', ''))
  end
  if not main then
    local files = io.scanDir(root, '*.kn5') or {}
    for i = 1, #files do
      local name = tostring(files[i])
      if not name:lower():find('collider', 1, true) then
        if name:find('^%a:') or name:sub(1, 1) == '/' or name:sub(1, 1) == '\\' then main = name
        else main = root .. '/' .. name end
        break
      end
    end
  end
  return main, lod
end

function M.new()
  return {
    token = 0, carId = nil, error = nil, model = nil, root = nil,
    position = vec3(), look = vec3(), up = vec3(), tip = vec3(), fallback = false, shown = false,
  }
end

local function ghostify(node)
  local unique, err = pcall(function() node:ensureUniqueMaterials() end)
  if not unique then return err end
  pcall(function() node:setShadows(false) end)
  pcall(function() node:setTransparent(true) end)
  pcall(function() node:setBlendMode(render.BlendMode.AlphaBlend) end)
  pcall(function() node:excludeFromCubemap(true) end)
  pcall(function() node:applyShaderReplacements('BLEND_MODE = ALPHA_BLEND\nCAST_SHADOWS = 0\n') end)
  pcall(function() node:setMaterialProperty('alpha', 0.45) end)
  return nil
end

function M.clear(state)
  state.token = state.token + 1
  state.carId, state.model, state.error, state.shown = nil, nil, nil, false
  if state.root then pcall(function() state.root:dispose() end) end
  state.root = nil
end

function M.useCar(state, carId)
  local loading = state.root and not state.error and not state.model
  if state.carId == carId and (state.model or loading or (state.error and state.error ~= 'Car scene is not available yet')) then return end
  M.clear(state)
  state.carId = carId
  local main, lod = M.findModel(carId)
  if not main then
    state.error = 'No visual model found for ' .. tostring(carId)
    return
  end
  local cars = ac.findNodes('carsRoot:yes')
  if not cars or cars:empty() then
    state.error = 'Car scene is not available yet'
    return
  end
  state.root = cars:createBoundingSphereNode('driftCoach.ghost', 8)
  if not state.root then
    state.error = 'Could not create the ghost node'
    return
  end
  state.root:setVirtualCarFlag(true)
  state.root:setVisible(false)
  state.token = state.token + 1
  local token = state.token
  local function loaded(err, node)
    if token ~= state.token then
      if node then node:dispose() end
      return
    end
    if err or not node then
      state.error = err or 'Could not load the car model'
      return
    end
    local materialError = ghostify(node)
    state.model = node
    state.error = materialError and 'Model loaded, transparency skipped' or nil
  end
  if lod then state.root:loadKN5LODAsync(lod, main, loaded)
  else state.root:loadKN5Async(main, loaded) end
end

local function basis(state, pose)
  local lx, ly, lz = pose[4], pose[5], pose[6]
  local mag = math.sqrt(lx * lx + ly * ly + lz * lz)
  if mag < 1e-4 then lx, ly, lz, mag = 0, 0, 1, 1 end
  lx, ly, lz = lx / mag, ly / mag, lz / mag
  local ux, uy, uz = pose[7], pose[8], pose[9]
  local project = ux * lx + uy * ly + uz * lz
  ux, uy, uz = ux - project * lx, uy - project * ly, uz - project * lz
  mag = math.sqrt(ux * ux + uy * uy + uz * uz)
  if mag < 1e-4 then ux, uy, uz, mag = 0, 1, 0, 1 end
  state.look:set(lx, ly, lz)
  state.up:set(ux / mag, uy / mag, uz / mag)
end

-- Returns true when the caller should draw the debug-box stand-in.
function M.place(state, pose, visible)
  state.fallback = false
  if not visible or not pose then
    if state.shown and state.root then state.root:setVisible(false) end
    state.shown = false
    return false
  end
  state.position:set(pose[1], pose[2], pose[3])
  basis(state, pose)
  if state.root and state.model then
    state.root:setPosition(state.position)
    state.root:setOrientation(state.look, state.up)
    if not state.shown then state.root:setVisible(true, true) end
    state.shown = true
    return false
  end
  state.fallback = true
  return true
end

function M.drawFallback(state)
  if not state.fallback then return end
  state.tip:set(state.position.x + state.look.x * 3, state.position.y + state.look.y * 3, state.position.z + state.look.z * 3)
  render.debugBox(state.position, vec3(1.8, 1.2, 4.2), rgbm(0.45, 0.82, 1, 0.35))
  render.debugArrow(state.position, state.tip, 0.45, rgbm(0.45, 0.9, 1, 1))
end

return M
