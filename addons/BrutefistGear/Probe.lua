local _, G = ...
-- Explicit outside-combat diagnostics only. No automatic scoring changes.
function G:Probe()
    local lines={"--- Calibration API probe ---"}
    if InCombatLockdown() then lines[#lines+1]="Blocked during combat";return lines end
    local function read(label,fn,index,...)
        if type(fn)~="function" then lines[#lines+1]=label..": API absent";return nil end
        local result={pcall(fn,...)}
        if not result[1] then lines[#lines+1]=label..": call failed";return nil end
        local value=result[index+1]
        local n=G:Number(value)
        lines[#lines+1]=label..": "..(n and string.format("%.6f",n) or G:Text(value))
        return n
    end
    read("Level",UnitLevel,1,"player")
    for index,name in ipairs({"Strength","Agility","Stamina","Intellect","Spirit"}) do
        read(name.." (effective)",UnitStat,2,"player",index)
    end
    if type(UnitAttackPower)=="function" then
        local ok,base,pos,neg=pcall(UnitAttackPower,"player")
        base,pos,neg=G:Number(base),G:Number(pos),G:Number(neg)
        lines[#lines+1]="Attack power (total): "..(ok and base and pos and neg and string.format("%.6f",base+pos+neg) or "unavailable")
    else lines[#lines+1]="Attack power (total): API absent" end
    read("Melee crit (percentage points)",GetCritChance,1)
    local schools={[2]="Holy",[3]="Fire",[4]="Nature",[5]="Frost",[6]="Shadow",[7]="Arcane"}
    for school=2,7 do
        read(schools[school].." spell crit (percentage points)",GetSpellCritChance,1,school)
        read(schools[school].." spell damage",GetSpellBonusDamage,1,school)
    end
    read("Spell healing",GetSpellBonusHealing,1)
    local config=read("Active talent config ID",C_ClassTalents and C_ClassTalents.GetActiveConfigID,1)
    lines[#lines+1]="Trait config reader available: "..tostring(C_Traits and type(C_Traits.GetConfigInfo)=="function" or false)
    lines[#lines+1]="Aura scan available: "..tostring(C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex)=="function" or false)
    lines[#lines+1]="Probe only: no calibration coefficients changed."
    return lines
end
