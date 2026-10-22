local secret={}
function issecretvalue(v) return rawequal(v,secret) end
function canaccessvalue(v) return not issecretvalue(v) end
function InCombatLockdown() return false end
local frame={}
function CreateFrame() return {RegisterEvent=function() end,SetScript=function(_,_,cb) frame.cb=cb end} end
SlashCmdList={};DEFAULT_CHAT_FRAME={AddMessage=function() end}
function UnitName() return 'Brigga' end
function GetRealmName() return 'Test' end
local callback
TooltipDataProcessor={AddTooltipPostCall=function(_,fn) callback=fn end};Enum={TooltipDataType={Item=0}}
local rank=134
C_SkillInfo={GetNumSkillLines=function() return 1 end,GetSkillLineInfo=function() return {skillID=165,rank=rank,maxRank=225} end}
local bags={[2319]=23,[2321]=6,[4235]=4,[4289]=2}
local bank={[2319]=30,[2321]=0,[4235]=0,[4289]=0}
C_Item={GetItemCount=function(id,includeBank) return (bags[id] or 0)+(includeBank and (bank[id] or 0) or 0) end}
local P={};assert(loadfile('addons/BrutefistProfessions/Cooking.lua'))('BrutefistProfessions',P);assert(loadfile('addons/BrutefistProfessions/Planner.lua'))('BrutefistProfessions',P)
frame.cb(nil,'ADDON_LOADED','BrutefistProfessions')
assert(P:Target(74)==75 and P:Target(75)==150 and P:Target(150)==225 and P:Target(225)==300)
local need=assert(P:Plan(134,150));assert(need[4235]==12 and need[4289]==36 and need[2319]==196 and need[2321]==56)
local whole=assert(P:Plan(75,150))
assert(whole[4231]==24 and whole[4233]==0 and whole[4246]==0) -- Already past producing light hides; later intermediate outputs consumed once.
assert(P:Plan(225,300)==nil)
local tip={lines={},GetItem=function() return 'Medium Leather','item:2319' end,AddLine=function(self,text) self.lines[#self.lines+1]=text end};GameTooltip=tip
callback(tip);assert(table.concat(tip.lines,'\n'):find('Bank: unknown'))
frame.cb(nil,'BANKFRAME_OPENED');assert(P.saved.bank[2319]==30)
frame.cb(nil,'BANKFRAME_CLOSED');tip.lines={};callback(tip)
local text=table.concat(tip.lines,'\n');assert(text:find('Bags: 23') and text:find('Bank: 30') and text:find('Still need: 143'))
bags[2319]=50;tip.lines={};callback(tip);assert(table.concat(tip.lines,'\n'):find('Still need: 116'))
assert(P:Num(secret)==nil and P:Num(0)==0)
C_SkillInfo.GetNumSkillLines=function() return secret end;assert(P:Skill()==nil)
function InCombatLockdown() return true end;assert(P:Skill()==nil)
print('PASS: milestones, partial estimates, intermediate credits, unverified route gate, bank freshness, live bags and restricted/combat guards')
function InCombatLockdown() return false end
C_SkillInfo.GetNumSkillLines=function() return 2 end
C_SkillInfo.GetSkillLineInfo=function(i) return {skillID=i==1 and 165 or 185,rank=i==1 and 134 or 21,maxRank=75} end
assert(P:Skill(185)==21)
local cooking=P:CookingPlan(100,150)
assert(cooking[2677]==35 and cooking[3685]==20 and not cooking[6308])
P:CookingCommand('cooking 100 fish');P:CookingCommand('cooking 130 fish')
cooking=P:CookingPlan(100,150);assert(cooking[6308]==55 and not cooking[2677] and not cooking[3685])
cooking=P:CookingPlan(130,150);assert(cooking[6308]==25)
cooking=P:CookingPlan(225,300);assert(cooking[4603]==65 and cooking[13760]==35)
local choices=P.saved.cookingChoices[100];P:CookingCommand('cooking 100 invalid');assert(P.saved.cookingChoices[100]==choices)
bags[769]=10;bank[769]=5;frame.cb(nil,'BANKFRAME_OPENED');frame.cb(nil,'BANKFRAME_CLOSED')
tip.GetItem=function() return 'Boar Meat','item:769' end;tip.lines={};callback(tip)
local cookingText=table.concat(tip.lines,'\n')
assert(cookingText:find('Cooking 21') and cookingText:find('Estimated need: 33') and cookingText:find('Still need: 18'))
assert(not cookingText:find('Leatherworking'))
tip.GetItem=function() return 'Raw Brilliant Smallfish','item:6291' end;tip.lines={};callback(tip)
assert(table.concat(tip.lines,'\n'):find('Alternative ingredient'))
assert(not table.concat(tip.lines,'\n'):find('Still need:'))
print('PASS: Cooking skill, selectable alternatives, single route totals, shared fish bands, untested 300 route, invalid choices and live tooltip counts')
