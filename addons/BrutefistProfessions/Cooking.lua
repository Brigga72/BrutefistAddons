local _,P=...
-- Guide bands: choose ONE recipe per band. Estimated crafts, not guaranteed points.
P.cooking={
 {1,50,'boar', {boar={55,{[769]=1}},wolf={55,{[2672]=1}},egg={55,{[6889]=1,[2678]=1}},fish={55,{[6291]=1}},mackerel={55,{[6303]=1}}}},
 {50,100,'clam',{clam={55,{[5503]=1,[159]=1}},coyote={55,{[2673]=1}},fish={55,{[6289]=1}},albacore={55,{[6361]=1}}}},
 {100,130,'ribs',{ribs={35,{[2677]=1,[2678]=1}},crab={40,{[2674]=1,[2678]=1}},fish={30,{[6308]=1}}}},
 {130,150,'egg',{egg={20,{[3685]=1,[2692]=1}},clam={25,{[5504]=1,[2692]=1}},lion={25,{[3731]=1,[2692]=1}},fish={25,{[6308]=1}}}},
 {150,175,'egg',{egg={25,{[3685]=1,[2692]=1}},lion={25,{[3731]=1,[2692]=1}}}},
 {175,225,'raptor',{raptor={50,{[12184]=1,[2692]=1}},fish={50,{[6362]=1}},turtle={50,{[3712]=1,[3713]=1}}}},
 {225,275,'yellowtail',{yellowtail={65,{[4603]=1}},redgill={65,{[13758]=1}},egg={65,{[12207]=1,[3713]=2}},wolf={65,{[12208]=1,[3713]=1}},clam={65,{[7974]=2,[2692]=1,[1179]=1}}}},
 {275,300,'salmon',{salmon={35,{[13760]=1}},nightfin={35,{[13759]=1,[159]=1}}}}}
P.cookingMat={}
for _,s in ipairs(P.cooking) do for _,r in pairs(s[4]) do for id in pairs(r[2]) do P.cookingMat[id]=true end end end
function P:CookingPlan(skill,target)
 local need,alternatives={},{}
 for _,s in ipairs(self.cooking) do
  local start,finish=math.max(skill,s[1]),math.min(target,s[2])
  if finish>start then
   local key=self.saved.cookingChoices and self.saved.cookingChoices[s[1]] or s[3]
   local recipe=s[4][key] or s[4][s[3]]
   local count=math.ceil(recipe[1]*(finish-start)/(s[2]-s[1]))
   for id,q in pairs(recipe[2]) do need[id]=(need[id] or 0)+count*q end
   for choice,r in pairs(s[4]) do
    if choice~=key then for id in pairs(r[2]) do alternatives[id]='/bprof cooking '..s[1]..' '..choice end end
   end
  end
 end
 return need,alternatives
end
function P:AppendCooking(tip,id)
 local skill,err=self:Skill(185)
 if not skill then tip:AddLine('Cooking Planner: '..err,1,0.8,0.4,true);return end
 local target=self:Target(skill)
 if not target then return end
 local need,alternatives=self:CookingPlan(skill,target)
 local bags,bank=self:Owned(id)
 tip:AddLine(' ');tip:AddLine('Cooking '..skill..' -> '..target,1,0.82,0.35,true)
 tip:AddLine('Bags: '..(bags or 'unavailable')..' | Bank: '..(bank or 'unknown')..(bank~=nil and not self.bankOpen and ' (last visit)' or ''),0.85,0.85,0.75,true)
 local required=need[id] or 0
 if required>0 then
  local text='Estimated need: '..required
  if bags and bank~=nil then text=text..' | Still need: '..math.max(0,required-bags-bank)
  else text=text..'; visit bank for a complete count.' end
  tip:AddLine(text,0.8,0.95,0.6,true)
 elseif alternatives[id] then
  tip:AddLine('Alternative ingredient, not required by your selected route.',1,0.8,0.4,true)
  tip:AddLine('Choose it with '..alternatives[id],0.85,0.85,0.75,true)
 else tip:AddLine('Not required for the next Cooking milestone on this route.',0.7,0.8,0.7,true) end
 tip:AddLine('Estimate; recipe must be learned. /bprof cooking lists choices.',0.65,0.65,0.65,true)
 if target==300 then tip:AddLine('225-300: untested Forever route in the source guide.',1,0.6,0.3,true) end
end
function P:CookingCommand(input)
 if not self.saved then return end
 local start,key=input:match('^cooking%s+(%d+)%s+(%S+)$')
 start=tonumber(start)
 if start and key then
  for _,s in ipairs(self.cooking) do
   if s[1]==start and s[4][key] then
    self.saved.cookingChoices=self.saved.cookingChoices or {};self.saved.cookingChoices[start]=key
    DEFAULT_CHAT_FRAME:AddMessage('Cooking '..start..'-'..s[2]..': '..key..' selected. Hover again.');return
   end
  end
  DEFAULT_CHAT_FRAME:AddMessage('Unknown Cooking choice. /bprof cooking lists choices.');return
 end
 DEFAULT_CHAT_FRAME:AddMessage('Select one recipe per range: /bprof cooking START CHOICE. Recipe ownership is not checked yet.')
 for _,s in ipairs(self.cooking) do
  local keys={};for key in pairs(s[4]) do keys[#keys+1]=key end;table.sort(keys)
  local chosen=self.saved.cookingChoices and self.saved.cookingChoices[s[1]] or s[3]
  DEFAULT_CHAT_FRAME:AddMessage(s[1]..'-'..s[2]..' ['..chosen..']: '..table.concat(keys,', '))
 end
end
