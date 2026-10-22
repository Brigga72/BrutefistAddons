-- Era compatibility test: legacy globals, no secret-value helpers or C_* APIs.
local D={}
function GetTime() return 20 end
function InCombatLockdown() return false end
function GetBuildInfo() return '1.15.9','70003','test',11509 end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function() end} end
DEFAULT_CHAT_FRAME={AddMessage=function() end}
SlashCmdList={}
function UnitHealth() return 200 end
function UnitHealthMax() return 400 end
function GetUnitSpeed() return 0 end
function UnitGUID() return 'era-player' end
function GetItemCount(id,bank) assert(bank==false);return id==858 and 3 or 0 end
function GetItemCooldown() return 10,120,1 end
function IsUsableItem() return true,false end
function CombatLogGetCurrentEventInfo() return 20,'SWING_DAMAGE',false,'enemy',nil,0,0,'era-player',nil,0,0,12 end
assert(loadfile('addons/BrutefistDeathReview/Recorder.lua'))('BrutefistDeathReview',D)
assert(loadfile('addons/BrutefistDeathReview/UI.lua'))('BrutefistDeathReview',D)
D:Event('ADDON_LOADED','BrutefistDeathReview');D:Start()
D:Event('COMBAT_LOG_EVENT_UNFILTERED');D:Stop('Era test')
local report=D:Report()
assert(report:find('1.15.9') and report:find('11509'))
assert(report:find('id=858 bags=3') and report:find('cooldownStart=10 duration=120'))
assert(report:find('SWING_DAMAGE'))
assert(D:Plain(5)=='5' and D:Num(0)==0)
print('PASS: Era legacy globals, no secret helpers, potion cooldowns and combat payload')
