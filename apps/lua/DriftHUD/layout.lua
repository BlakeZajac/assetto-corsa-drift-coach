-- Dock the three independent HUD windows in UI-scaled screen coordinates.
local M = {}
local View = require('view')
local started, lastLayout
local panels = {
  {id='inputs', title='Drift HUD Inputs', mode='graph'},
  {id='main', title='Drift HUD'},
  {id='tyres', title='Drift HUD Tyres', mode='tyres'}
}
function M.update(prefs, coachVisible)
  if not ac.getAppWindows or not ac.accessAppWindow then return end
  if not started then
    started = true
    ac.setWindowOpen('main', true)
    ac.setWindowOpen('inputs', prefs.graph)
    ac.setWindowOpen('tyres', prefs.tyres)
  end
  if not prefs.dockBottom then lastLayout=nil; return end
  local screen=ac.getSim().windowSize
  if not screen or screen.x<=0 or screen.y<=0 then return end
  local windows=ac.getAppWindows()
  local visible,total={},0
  local key=string.format('%g:%g',screen.x,screen.y)
  for _,panel in ipairs(panels) do
    for _,window in ipairs(windows) do
      if window.title==panel.title and window.visible and not window.collapsed then
        local width=View.size(prefs,panel.mode,coachVisible)
        visible[#visible+1]={name=window.name,width=width}
        total=total+width
        key=key..':'..window.name..':'..width
        break
      end
    end
  end
  if key==lastLayout then return end
  lastLayout=key
  local gap=8
  local factor=math.min(1,(screen.x-32)/math.max(1,total+gap*math.max(0,#visible-1)))
  local height=92*factor
  local x=(screen.x-(total+gap*math.max(0,#visible-1))*factor)/2
  for _,panel in ipairs(visible) do
    local window=ac.accessAppWindow(panel.name)
    if window and window:valid() then
      window:resize(vec2(panel.width*factor,height))
      window:move(vec2(x,math.max(0,screen.y-height)))
    end
    x=x+(panel.width+gap)*factor
  end
end
return M
