package.path = 'apps/lua/DriftHUD/?.lua;' .. package.path
vec2 = function(x, y) return {x=x, y=y} end
rgbm = function(r, g, b, a) return {r=r, g=g, b=b, mult=a} end
local View = require('view')
local titles = {'Drift HUD Inputs', 'Drift HUD', 'Drift HUD Tyres'}
local modes = {'graph', false, 'tyres'}
local count = 0
local function near(a,b) assert(math.abs(a-b)<0.001, a..' ~= '..b) end

local function scenario(screen, hidden, compact, dock, coach)
  local windows, accessors = {}, {}
  for i,title in ipairs(titles) do
    windows[i] = {name='window-'..i, title=title, visible=i~=hidden, collapsed=false}
    accessors[windows[i].name] = {
      valid=function() return true end,
      resize=function(self,size) self.size=size end,
      move=function(self,pos) self.position=pos end
    }
  end
  ac = {
    getAppWindows=function() return windows end,
    accessAppWindow=function(name) return accessors[name] end,
    getSim=function() return {windowSize=screen} end,
    setWindowOpen=function() end
  }
  local prefs = {dockBottom=dock, graph=true, tyres=true, drift=true,
    driving=true, steering=not compact, inputs=not compact}
  local layout = dofile('apps/lua/DriftHUD/layout.lua')
  layout.update(prefs,coach)
  local first, last
  for i,window in ipairs(windows) do
    local a=accessors[window.name]
    if window.visible and dock then
      assert(a.size and a.position)
      near(a.position.y+a.size.y, screen.y)
      local width,height=View.size(prefs,modes[i] or nil,coach)
      near(a.size.x/a.size.y, width/height)
      if not first then first=a end
      last=a
    else
      assert(not a.size and not a.position)
    end
  end
  if dock then
    near(first.position.x,screen.x-(last.position.x+last.size.x))
    -- Hiding another window must invalidate the cached layout.
    windows[1].visible=false
    layout.update(prefs,coach)
    near(accessors['window-2'].position.y+accessors['window-2'].size.y,screen.y)
    if coach then
      local before=accessors['window-2'].size.x
      layout.update(prefs,false)
      assert(accessors['window-2'].size.x < before)
    end
  end
end
for _,screen in ipairs({vec2(3440,1440), vec2(1920,1080), vec2(1280,720)}) do
  for _,hidden in ipairs({0,1,3}) do
    for _,compact in ipairs({false,true}) do
      for _,coach in ipairs({false,true}) do
        scenario(screen,hidden,compact,true,coach)
        count=count+1
      end
    end
  end
end
scenario(vec2(1920,1080),0,false,false)
print((count+1)..' HUD docking checks passed')
