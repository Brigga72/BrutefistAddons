local D={version='test',maxEvents=800,limit=30,rows={},head=1,count=0}
local clock=20
function GetTime() return clock end
function InCombatLockdown() return false end
function GetBuildInfo() return '1.15.9','70003','date',11509 end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
assert(loadfile('addons/BrutefistDeathReview/Recorder.lua'))('BrutefistDeathReview',D)
assert(loadfile('addons/BrutefistDeathReview/Analysis.lua'))('BrutefistDeathReview',D)
local function state(t,hp,start,duration,usable,combat,count)
 return {t=t,kind='STATE',data={hp=hp,maximum=363,combat=combat~=false,potions={[858]={count=count or 2,start=start,duration=duration,enabled=1,usable=usable}}}}
end
local function ready(t) return state(t,100,0,0,true) end
local rows={state(1,107,0.5,1.8,true),state(1.5,107,0.5,1.8,true),ready(3),ready(3.5),ready(4),ready(4.5),ready(5),state(5.5,250,5.5,120,true),state(6,250,5.5,120,true)}
local result=D:Analyze(rows)
assert(result.shortLocks==2 and #result.windows==1)
assert(result.windows[1].first==3 and result.windows[1].last==5)
-- The API usable flag alone cannot make an on-cooldown potion available.
assert(#D:Analyze({state(1,100,1,120,true),state(2,100,1,120,true),state(3,100,1,120,true)}).windows==0)
assert(#D:Analyze({state(1,100,nil,nil,true),state(2,100,nil,nil,true),state(3,100,nil,nil,true)}).windows==0)
assert(#D:Analyze({state(1,100,0,0,false),state(2,100,0,0,false),state(3,100,0,0,false)}).windows==0)
assert(#D:Analyze({state(1,100,0,0,true,false),state(2,100,0,0,true,false),state(3,100,0,0,true,false)}).windows==0)
assert(#D:Analyze({state(1,100,0,0,true,true,0),state(2,100,0,0,true,true,0),state(3,100,0,0,true,true,0)}).windows==0)
assert(#D:Analyze({ready(1),ready(1.5),ready(5),ready(5.5)}).windows==0)
assert(#D:Analyze({ready(1),state(1.5,nil,0,0,true),ready(2),ready(2.5)}).windows==0)
assert(#D:Analyze({state(1,0,0,0,true),state(1.5,0,0,0,true),state(2.5,0,0,0,true)}).windows==0)
-- Use a structured equivalent of the observed 100 -> 250 health potion heal.
rows[#rows+1]={t=5.5,kind='COMBAT',data={incoming=true,outgoing=true,event='SPELL_HEAL',source='Player',spell='Healing Potion',heal=150,overheal=0}}
rows[#rows+1]={t=6,kind='COMBAT',data={outgoing=true,event='SPELL_CAST_FAILED',spell='Healing Potion',failure='Item is not ready yet'}}
rows[#rows+1]={t=7,kind='COMBAT',data={incoming=true,event='SWING_DAMAGE',source='Enemy',spell='Melee',amount=27,overkill=-1}}
D.frozenRows=rows;D.stoppedAt=8
local review=D:Review()
assert(review:find('150 effective') and review:find('Item is not ready yet'))
assert(review:find('FIGHT REVIEW') and not review:find('DEATH CAPTURED'))
assert(review:find('Short item lockouts observed') and review:find('source was not verified'))
assert(review:find('not confirmed mistakes'))
D.deathAt=8;review=D:Review();assert(review:find('DEATH CAPTURED') and review:find('Last recorded hit before death'))
D.deathAt=15;review=D:Review();assert(review:find('cause of death is unknown'))
-- Parse actual recorded payload layouts into the structured model.
function UnitGUID() return 'player' end
local payload
C_CombatLog={GetCurrentEventInfo=function() return unpack(payload,1,payload.n) end}
payload={clock,'ENVIRONMENTAL_DAMAGE',false,nil,nil,0,0,'player','Player',0,0,'Falling',55,-1};payload.n=14
D:CombatEvent();local parsed=D.rows[1].data;assert(parsed.amount==55 and parsed.spell=='Falling' and parsed.incoming)
payload={clock,'SWING_DAMAGE',false,'enemy','Enemy',0,0,'player','Player',0,0,27,-1};payload.n=13
D:CombatEvent();parsed=D.rows[2].data;assert(parsed.amount==27 and parsed.spell=='Melee')
payload={clock,'SPELL_HEAL',false,'player','Player',0,0,'player','Player',0,0,440,'Healing Potion',1,150,0};payload.n=16
D:CombatEvent();parsed=D.rows[3].data;assert(parsed.heal==150 and parsed.overheal==0)
print('PASS: timeline, payload normalization, potion windows, gaps, death evidence and temporary lockout exclusions')
