package.path = 'apps/lua/DriftCoach/?.lua;' .. package.path
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS '..name) end
local function near(a,b) assert(math.abs(a-b)<1e-5,tostring(a)..' ~= '..tostring(b)) end
local function v(x,y,z)
  return {x=x or 0,y=y or 0,z=z or 0,set=function(self,a,b,c)
    self.x,self.y,self.z=type(a)=='table' and a.x or a,type(a)=='table' and a.y or b,type(a)=='table' and a.z or c
  end}
end
vec3=v
rgbm=function(...) return {...} end
render={BlendMode={AlphaBlend=1},debugBox=function() end,debugArrow=function() end}
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b) return v(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
local function norm(a) local n=math.sqrt(dot(a,a)); return v(a.x/n,a.y/n,a.z/n) end
local Matrix={}; Matrix.__index=Matrix
local function matrix(p,l,u)
  l=norm(l); local s=norm(cross(u,l)); u=cross(l,s)
  return setmetatable({position=v(p.x,p.y,p.z),look=l,up=u,side=s},Matrix)
end
function Matrix:transformVector(a)
  return v(a.x*self.side.x+a.y*self.up.x+a.z*self.look.x,
    a.x*self.side.y+a.y*self.up.y+a.z*self.look.y,a.x*self.side.z+a.y*self.up.z+a.z*self.look.z)
end
function Matrix:mul(other)
  local p=other:transformVector(self.position)
  p.x,p.y,p.z=p.x+other.position.x,p.y+other.position.y,p.z+other.position.z
  return matrix(p,other:transformVector(self.look),other:transformVector(self.up))
end
function Matrix:inverse()
  return matrix(v(-dot(self.position,self.side),-dot(self.position,self.up),-dot(self.position,self.look)),
    v(self.side.z,self.up.z,self.look.z),v(self.side.y,self.up.y,self.look.y))
end
function Matrix:set(m)
  self.position,self.side,self.look,self.up=m.position,m.side,m.look,m.up
end
mat4x4={look=matrix,rotation=function(angle,axis)
  assert(axis.x==1); return matrix(v(),v(0,-math.sin(angle),math.cos(angle)),v(0,math.cos(angle),math.sin(angle)))
end}
local identity=function() return matrix(v(),v(0,0,1),v(0,1,0)) end
local Node={}; Node.__index=Node
local function node(parent) return setmetatable({parent=parent,transform=identity(),children={}},Node) end
function Node:empty() return self.missing==true end
function Node:getParent() return self.parent end
function Node:getTransformationRaw() return self.transform end
function Node:getWorldTransformationRaw() return self.parent and self.transform:mul(self.parent:getWorldTransformationRaw()) or self.transform end
function Node:setPosition(p) self.transform.position=v(p.x,p.y,p.z) end
function Node:setOrientation(l,u) self.transform=matrix(self.transform.position,l,u) end
function Node:setVisible(value) self.visible=value end
function Node:dispose() self.disposed=true end
function Node:ensureUniqueMaterials() self.unique=true end
function Node:applySkin(path) assert(self.unique); self.skin=path end
function Node:findNodes(name) return self.children[name] or setmetatable({missing=true},Node) end
for _,method in ipairs({'setVirtualCarFlag','setShadows','setTransparent','setBlendMode','excludeFromCubemap','applyShaderReplacements','setMaterialProperty'}) do
  Node[method]=function() end
end
local scene=node(); scene.transform.position=v(100,0,30)
local loads={}
function Node:createBoundingSphereNode() return node(self) end
function Node:loadKN5Async(path,callback)
  local model=node(self)
  for _,name in ipairs({'LF','RF','LR','RR'}) do
    local suspension=node(model); model.children['SUSP_'..name]=suspension
    model.children['WHEEL_'..name]=node(suspension)
  end
  loads[#loads+1]={callback=callback,model=model,path=path}
end
local lods={get=function(_,section,_,fallback) return section=='LOD_0' and 'z_main.kn5' or fallback end}
ac={FolderID={ContentCars=1},getFolder=function() return '/cars' end,
  getCarID=function() return '350z' end,INIConfig={load=function() return nil end,carData=function() return lods end},
  findNodes=function() return scene end}
io.fileExists=function(path) return path=='/cars/350z/z_main.kn5' end
io.dirExists=function() return true end
io.scanDir=function() return {'wrong_lod.kn5','z_main.kn5'} end
local G,V=require('ghost'),require('visuals')
local function pose(x,lx,lz)
  return {x,0,0,lx,0,lz,0,1,0,20,.6,0,0,0,180,3,30}
end
local function visual()
  local out={10,1,20, .6,0,.8, 0,1,0}
  for i=1,4 do
    for _,value in ipairs({10+i,0,20, -.6,0,.8, 0,1,0, .7}) do out[#out+1]=value end
  end
  return out
end
test('packed car data selects the full model and applies the recorded skin',function()
  local s=G.new(); G.useCar(s,'350z','red',0)
  local load=loads[#loads]; assert(load.path=='/cars/350z/z_main.kn5')
  load.callback(nil,load.model)
  assert(s.model.skin=='/cars/350z/skins/red' and #s.wheels==4)
  local before=#loads; G.useCar(s,'350z','red',0); assert(#loads==before)
end)
test('body yaw and countersteer survive parent transforms and wheel spin',function()
  local s=G.new(); G.useCar(s,'350z','red',0); local load=loads[#loads]; load.callback(nil,load.model)
  local p=pose(0,0,1); p.visual=visual()
  assert(not G.place(s,p,true))
  local body=s.root:getWorldTransformationRaw()
  near(body.position.x,10); near(body.position.y,1); near(body.position.z,20)
  near(body.look.x,.6); near(body.look.z,.8)
  local suspension=s.wheels[1].suspension:getWorldTransformationRaw()
  near(suspension.position.x,11); near(suspension.look.x,-.6)
  local wheel=s.wheels[1].wheel:getWorldTransformationRaw()
  near(wheel.position.x,11); near(wheel.look.y,-math.sin(.7)); near(wheel.look.x,-.6*math.cos(.7))
  assert(s.root.visible and scene.transform.position.x==100)
end)
test('changing skin reloads and ignores a late callback for the old model',function()
  local s=G.new(); G.useCar(s,'350z','red',0); local old=loads[#loads]
  G.useCar(s,'350z','blue',0); local new=loads[#loads]
  old.callback(nil,old.model); assert(old.model.disposed and not s.model)
  new.callback(nil,new.model); assert(s.model.skin=='/cars/350z/skins/blue')
end)
test('legacy pose still preserves yaw and unavailable models use the fallback',function()
  local s=G.new(); assert(G.place(s,pose(5,.6,.8),true)); assert(s.fallback)
  G.useCar(s,'350z','red',0); local load=loads[#loads]; load.callback(nil,load.model)
  G.place(s,pose(5,.6,.8),true); near(s.root:getTransformationRaw().look.x,.6)
  G.place(s,nil,false); assert(not s.root.visible)
end)
test('capture retains actual body and wheel orientation and unwraps wheel phase',function()
  local state=V.new()
  local base=identity()
  local function sample(phase)
    local c={bodyTransform=matrix(v(1,2,3),v(.6,0,.8),v(0,1,0)),wheels={}}
    for i=0,3 do c.wheels[i]={transform=base,transformWheel=mat4x4.rotation(phase,v(1,0,0)),angularSpeed=80} end
    return c
  end
  local a=V.capture(state,sample(0),.1); local b=V.capture(state,sample(8),.1)
  near(a[4],.6); near(b[19],8); assert(#b==49)
end)
print(count..' ghost checks passed')
