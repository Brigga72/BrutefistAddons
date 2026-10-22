local D={}
local now,combat=10,false
local secret={}
function GetTime() return now end
function InCombatLockdown() return combat end
function issecretvalue(v) return rawequal(v,secret) end
function canaccessvalue(v) return not rawequal(v,secret) end
function GetBuildInfo() return '1.60.1','test','date',16001 end
function CreateFrame()
 return {RegisterEvent=function(_,event) if event=='COMBAT_LOG_EVENT_UNFILTERED' and reject then error('unsupported') end end,SetScript=function() end}
end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
function UnitHealth() return combat and 120 or 400 end
function UnitHealthMax() return 500 end
function GetUnitSpeed() return 0 end
function UnitGUID() return 'player-guid' end
local potionCount=2
C_Item={GetItemCount=function(id,includeBank) assert(includeBank==false);return id==118 and potionCount or 0 end,IsUsableItem=function() return true,false end}
C_Container={GetItemCooldown=function() return 0,0,1 end}
SlashCmdList={}
assert(loadfile('addons/BrutefistDeathReview/Recorder.lua'))('BrutefistDeathReview',D)
assert(loadfile('addons/BrutefistDeathReview/UI.lua'))('BrutefistDeathReview',D)
D:Event('ADDON_LOADED','AnotherAddon');assert(not D.ready)
D:Event('ADDON_LOADED','BrutefistDeathReview');assert(D.ready)
assert(not D.recording)
reject=true;D:Register('COMBAT_LOG_EVENT_UNFILTERED');assert(D.capabilities.COMBAT_LOG_EVENT_UNFILTERED=='registration rejected');reject=false
D:Start();assert(D.recording)
assert(D:Report():find('id=118 bags=2'))
assert(D:Report():find('ItemCount %[outside%]'))
combat=true;D:Event('PLAYER_REGEN_DISABLED');D:Event('UNIT_HEALTH','player')
assert(D:Report():find('ItemCount %[combat%]'))
C_CombatLog={GetCurrentEventInfo=function() return now,'SWING_DAMAGE',false,'enemy-guid','Enemy',0,0,'player-guid','Player',0,0,25 end}
D:Event('COMBAT_LOG_EVENT_UNFILTERED');assert(D:Report():find('SWING_DAMAGE'))
local before=D.count
C_CombatLog.GetCurrentEventInfo=function() return now,'SWING_DAMAGE',false,'enemy',nil,0,0,'other',nil,0,0,25 end
D:Event('COMBAT_LOG_EVENT_UNFILTERED');assert(D.count==before)
C_CombatLog.GetCurrentEventInfo=function() return now,secret end
D:Event('COMBAT_LOG_EVENT_UNFILTERED');assert(D:Report():find('restricted=1'))
UnitHealth=function() return secret end
D:Sample('restricted health');assert(D:Report():find('hp=nil/500'))
assert(D:Num(secret)==nil and D:Plain(secret)=='<restricted>')
assert(D:Num(0)==0 and D:Num(0/0)==nil)
assert(D:Call('Missing',nil)==nil)
assert(D:Call('Broken',function() error('test') end)==nil)
local a,b,c=D:Call('Nil-preserving',function() return 1,nil,3 end);assert(a==1 and b==nil and c==3)
-- A missing modern reader may use legacy event arguments without shifting nils.
C_CombatLog=nil
D:CombatEvent(now,'SPELL_HEAL',false,'player-guid',nil,0,0,'player-guid',nil,0,0,331,'Healing Wave',8,55)
assert(D:Report():find('SPELL_HEAL'))
-- Cooldown evidence is captured before death, not inferred afterwards.
now=12;potionCount=1
C_Container.GetItemCooldown=function() return 12,120,1 end
D:Sample('after potion');assert(D:Report():find('cooldownStart=12 duration=120'))
for i=1,900 do D:Add('TEST',tostring(i)) end
assert(D.count==800 and #D.rows==800)
local lines=D:Timeline();assert(lines[#lines]:find('900'))
now=50;assert(#D:Timeline()==0)
D:Add('MARK','death window');D:Event('PLAYER_DEAD')
assert(not D.recording and BrutefistDeathReviewDB.lastReport:find('PLAYER_DEAD'))
local saved=BrutefistDeathReviewDB.lastReport
now=100;assert(D:Report():find('death window'))
D:Event('UNIT_HEALTH','player');assert(BrutefistDeathReviewDB.lastReport==saved)
D:Start();assert(D.recording and D.count<800 and not D.snapshot)
assert(BrutefistDeathReviewDB.lastReport==saved)
D:Event('PLAYER_LOGOUT');assert(not D.recording and BrutefistDeathReviewDB.lastReport:find('Logout'))
print('PASS: recorder filtering, missing/restricted APIs, cooldown history, nil payloads, bounds, death freeze and report persistence')
