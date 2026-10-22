local _, G = ...
local function read(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if not ok then return nil end
    return G:Number(value)
end
local function clamp(value) return math.max(0,math.min(1,value)) end
function G:FlurryFactor(crit)
    -- Simplified independent-swing model: buff present if any of the last three swings crit.
    local q=1-(1-clamp(crit))^3
    local haste=self:Profile().flurryHaste
    return 1/((1-q)+q/(1+haste)),q
end
function G:QuestingContext(calibration)
    if InCombatLockdown() then return nil,"Outside-combat comparison only" end
    if not calibration or not calibration.measures.meleeCritPerAgility or not calibration.measures.spellCritPerItemIntellect then
        return nil,"Calibrate both Agility and Intellect first"
    end
    if type(UnitAttackPower)~="function" then return nil,"AP API absent" end
    local ok,base,pos,neg=pcall(UnitAttackPower,"player")
    base,pos,neg=self:Number(base),self:Number(pos),self:Number(neg)
    if not ok or not base or not pos or not neg then return nil,"AP unavailable" end
    local meleeCrit=read(GetCritChance)
    local spellCrit=read(GetSpellCritChance,4)
    local spellDamage=read(GetSpellBonusDamage,4)
    if not meleeCrit or not spellCrit or not spellDamage then return nil,"Crit/spell stats unavailable" end
    local worked,link=pcall(GetInventoryItemLink,"player",16)
    if not worked or self:Secret(link) or type(link)~="string" then return nil,"Equipped weapon unavailable" end
    local weapon,err=self:Read(link)
    if not weapon then return nil,err end
    if weapon.equip~="INVTYPE_2HWEAPON" then return nil,"Model requires an equipped two-hander" end
    local dps=weapon.stats.dps
    if not dps and weapon.min and weapon.max and weapon.speed and weapon.speed>0 then dps=(weapon.min+weapon.max)/2/weapon.speed end
    if not dps or dps<=0 then return nil,"Weapon DPS unavailable" end
    return {ap=base+pos+neg,meleeCrit=meleeCrit/100,spellCrit=spellCrit/100,
        spellDamage=spellDamage,weaponDPS=dps,weaponName=weapon.name,weaponLink=link,calibration=calibration}
end
function G:QuestingCompare(item,old,context)
    if item.equip=="INVTYPE_2HWEAPON" then return self:WeaponCompare(item,old,context) end
    if self:Weapon(item) or item.equip=="INVTYPE_TRINKET" or item.equip=="INVTYPE_SHIELD" or item.equip=="INVTYPE_HOLDABLE" then
        return nil,"Armor/rings only; weapon kept fixed"
    end
    local _,apDelta,spDelta=self:Delta(item.stats,old.stats)
    local m=context.calibration.measures
    local mcDelta=((item.stats.agi or 0)-(old.stats.agi or 0))*m.meleeCritPerAgility/100
    local scDelta=((item.stats.int or 0)-(old.stats.int or 0))*m.spellCritPerItemIntellect/100
    local beforeFlurry,beforeQ=self:FlurryFactor(context.meleeCrit)
    local afterFlurry,afterQ=self:FlurryFactor(context.meleeCrit+mcDelta)
    local p=self:Profile()
    local physical=context.weaponDPS+context.ap/p.apPerDPS
    local nextPhysical=context.weaponDPS+(context.ap+apDelta)/p.apPerDPS
    local meleeBase=physical*(1+clamp(context.meleeCrit))*beforeFlurry
    local meleeNew=nextPhysical*(1+clamp(context.meleeCrit+mcDelta))*afterFlurry
    local spellBase=(p.spellBase+p.spellCoefficient*context.spellDamage)*(1+0.5*clamp(context.spellCrit))
    local spellNew=(p.spellBase+p.spellCoefficient*(context.spellDamage+spDelta))*(1+0.5*clamp(context.spellCrit+scDelta))
    if meleeBase<=0 or spellBase<=0 or nextPhysical<=0 or spellNew<=0 then return nil,"Invalid model baseline" end
    local melee=meleeNew/meleeBase
    local spell=spellNew/spellBase
    local index=100*(p.meleeShare*melee+(1-p.meleeShare)*spell)
    return {index=index,change=index-100,melee=100*(melee-1),spell=100*(spell-1),
        flurry=100*(afterFlurry/beforeFlurry-1),oldUptime=100*beforeQ,newUptime=100*afterQ,
        meleeCritDelta=mcDelta*100,spellCritDelta=scDelta*100}
end
function G:QuestingReport()
    local calibration=self:CurrentCalibration()
    local context,err=self:QuestingContext(calibration)
    local lines={"--- Typical questing model ---","Proxy only; not a measured damage percentage.",
        string.format("Assumed mix: %.0f%% melee proxy / %.0f%% Nature spell proxy",100*self.db.meleeShare,100*(1-self.db.meleeShare)),
        string.format("Assumptions: AP/DPS %.2f; Flurry haste %.2f; base spell %.2f; coefficient %.2f",self.db.apPerDPS,self.db.flurryHaste,self.db.spellBase,self.db.spellCoefficient)}
    if context then
        lines[#lines+1]=string.format("Baseline: %s, weapon DPS %.4f, AP %.2f, melee crit %.6f%%, Nature crit %.6f%%, spell damage %.2f",
            context.weaponName,context.weaponDPS,context.ap,context.meleeCrit*100,context.spellCrit*100,context.spellDamage)
    else lines[#lines+1]="Unavailable: "..err end
    return lines
end
