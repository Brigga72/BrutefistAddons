local _,P=...
P.version='0.1.0'
-- Data adapter: guide's default hide route; estimated crafts, not skill guarantees.
-- Item IDs keep the route independent of translated material names.
P.steps={
 {1,30,33,{[2934]=3},2318}, {30,55,27,{[783]=1,[4289]=1},4231},
 {55,75,21,{[2318]=3,[2320]=2}}, {75,80,8,{[2318]=4},2319},
 {80,90,10,{[4232]=1,[4289]=1},4233}, {90,100,19,{[2318]=6,[2320]=2},4246},
 {100,115,24,{[2318]=10,[4231]=1,[2321]=1}},
 {115,125,10,{[4246]=1,[4233]=1,[2321]=2,[4340]=1}},
 {125,130,7,{[2319]=5},4234}, {130,140,20,{[4235]=1,[4289]=3},4236},
 {140,155,20,{[2319]=14,[2321]=4}}, {155,165,10,{[4234]=8,[4236]=1,[2321]=2}},
 {165,175,10,{[4234]=4,[4236]=1,[4291]=1}}, {175,195,26,{[4234]=4,[4236]=1,[4291]=1}},
 {195,210,21,{[4304]=5,[4291]=2}}, {210,225,15,{[4304]=14,[4291]=4}}}
P.materials={}
for _,s in ipairs(P.steps) do for id in pairs(s[4]) do P.materials[id]=true end end
function P:Secret(v)
 for _,fn in ipairs({issecretvalue,canaccessvalue}) do
  if type(fn)=='function' then local ok,r=pcall(fn,v);if not ok or (fn==issecretvalue and r) or (fn==canaccessvalue and not r) then return true end end
 end
 return false
end
function P:Num(v)
 if self:Secret(v) or type(v)~='number' or v~=v or v==math.huge or v==-math.huge then return end
 return v
end
function P:Table(v)
 if self:Secret(v) or type(v)~='table' then return false end
 if type(issecrettable)=='function' then local ok,r=pcall(issecrettable,v);if not ok or r then return false end end
 return true
end
function P:Skill()
 if InCombatLockdown() then return nil,'Check outside combat' end
 if not C_SkillInfo or type(C_SkillInfo.GetNumSkillLines)~='function' or type(C_SkillInfo.GetSkillLineInfo)~='function' then return nil,'Skill API unavailable' end
 local ok,n=pcall(C_SkillInfo.GetNumSkillLines);n=ok and self:Num(n)
 if not n or n<0 or n>200 or n%1~=0 then return nil,'Skill count unavailable' end
 for i=1,n do
  local worked,row=pcall(C_SkillInfo.GetSkillLineInfo,i)
  if worked and self:Table(row) and self:Num(row.skillID)==165 then
   local rank,max=self:Num(row.rank),self:Num(row.maxRank)
   if rank and max then return rank,max end
  end
 end
 return nil,'Leatherworking unavailable; expand Skills panel'
end
function P:Target(skill)
 for _,n in ipairs({75,150,225,300}) do if skill<n then return n end end
end
function P:Plan(skill,target)
 if not target then return nil,'Maximum milestone reached' end
 if target>225 then return nil,'225-300 route not verified by the guide yet' end
 local need,produced={},{}
 for _,s in ipairs(self.steps) do
  local start,finish=math.max(skill,s[1]),math.min(target,s[2])
  if finish>start then
   local crafts=math.ceil(s[3]*(finish-start)/(s[2]-s[1]))
   for id,quantity in pairs(s[4]) do
    local amount=crafts*quantity
    local available=math.min(amount,produced[id] or 0)
    produced[id]=(produced[id] or 0)-available
    need[id]=(need[id] or 0)+amount-available
   end
   if s[5] then produced[s[5]]=(produced[s[5]] or 0)+crafts end
  end
 end
 return need
end
function P:Bag(id,bank)
 local fn=C_Item and C_Item.GetItemCount
 if type(fn)~='function' then return end
 local ok,n=pcall(fn,id,bank,false,false)
 return ok and self:Num(n) or nil
end
function P:BankSnapshot()
 if not self.bankOpen or InCombatLockdown() or not self.saved then return end
 for id in pairs(self.materials) do
  local bags,total=self:Bag(id,false),self:Bag(id,true)
  if bags and total and total>=bags then self.saved.bank[id]=total-bags end
 end
 self.saved.bankSeen=true
end
function P:Owned(id)
 local bags=self:Bag(id,false)
 local bank=self.saved and self.saved.bank[id]
 if self.bankOpen then self:BankSnapshot();bank=self.saved and self.saved.bank[id] end
 return bags,bank
end
function P:Append(tip)
 if tip~=GameTooltip and tip~=ItemRefTooltip or not self.saved or InCombatLockdown() then return end
 local ok,_,link=pcall(tip.GetItem,tip)
 if not ok or self:Secret(link) or type(link)~='string' then return end
 local id=tonumber(link:match('item:(%d+)'))
 if not id or not self.materials[id] then return end
 local skill,err=self:Skill()
 if not skill then tip:AddLine('Profession Planner: '..err,1,0.8,0.4,true);return end
 local target=self:Target(skill)
 local need,reason=self:Plan(skill,target)
 local bags,bank=self:Owned(id)
 tip:AddLine(' ')
 tip:AddLine('Leatherworking '..skill..' -> '..(target or 300),1,0.82,0.35,true)
 tip:AddLine('Bags: '..(bags or 'unavailable')..' | Bank: '..(bank or 'unknown')..(bank~=nil and not self.bankOpen and ' (last visit)' or ''),0.85,0.85,0.75,true)
 if not need then tip:AddLine(reason,1,0.8,0.4,true);return end
 local required=need[id] or 0
 if required==0 then tip:AddLine('Not required for the next milestone on this route.',0.7,0.8,0.7,true)
 elseif bags and bank~=nil then
  local remaining=math.max(0,required-bags-bank)
  tip:AddLine('Estimated need: '..required..' | Still need: '..remaining,remaining==0 and 0.4 or 1,0.9,0.5,true)
 else tip:AddLine('Estimated need: '..required..'; visit bank for a complete remaining count.',1,0.8,0.4,true) end
 tip:AddLine('Guide estimate; yellow recipes may need extra crafts.',0.65,0.65,0.65,true)
 if id==4231 or id==4233 or id==4236 or id==4246 then tip:AddLine('Keep this intermediate material for later steps.',1,0.8,0.4,true) end
end
function P:Init()
 BrutefistProfessionsDB=BrutefistProfessionsDB or {characters={}}
 BrutefistProfessionsDB.characters=BrutefistProfessionsDB.characters or {}
 local ok,name=pcall(UnitName,'player');local worked,realm=pcall(GetRealmName)
 if not ok or not worked or self:Secret(name) or self:Secret(realm) or type(name)~='string' or type(realm)~='string' then return end
 local key=name..'@'..realm
 BrutefistProfessionsDB.characters[key]=BrutefistProfessionsDB.characters[key] or {bank={}}
 self.saved=BrutefistProfessionsDB.characters[key]
 if TooltipDataProcessor and Enum and Enum.TooltipDataType then
  pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Item,function(tip)
   if P.busy then return end
   P.busy=true;local success,err=pcall(P.Append,P,tip);P.busy=false
   if not success then P.lastError=P:Secret(err) and '<restricted>' or tostring(err) end
  end)
 end
end
local f=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','BANKFRAME_OPENED','BANKFRAME_CLOSED','BAG_UPDATE_DELAYED','PLAYERBANKSLOTS_CHANGED'}) do pcall(f.RegisterEvent,f,event) end
f:SetScript('OnEvent',function(_,event,name)
 if event=='ADDON_LOADED' and name=='BrutefistProfessions' then P:Init()
 elseif event=='BANKFRAME_OPENED' then P.bankOpen=true;P:BankSnapshot()
 elseif event=='BANKFRAME_CLOSED' then P.bankOpen=false
 else P:BankSnapshot() end
end)
SLASH_BRUTEFISTPROFESSIONS1='/bprof'
SlashCmdList.BRUTEFISTPROFESSIONS=function()
 local skill,err=P:Skill()
 DEFAULT_CHAT_FRAME:AddMessage('Profession Planner '..P.version..': '..(skill and ('Leatherworking '..skill..', next milestone '..(P:Target(skill) or 'complete')) or err))
 DEFAULT_CHAT_FRAME:AddMessage('Route: guide default hides, verified guide coverage through 225. Visit bank once, then hover a material. Cooking/Fishing routes pending. '..(P.lastError or ''))
end
