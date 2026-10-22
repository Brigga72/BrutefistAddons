local _, G = ...
function G:WeaponData(item)
    if item.equip ~= "INVTYPE_2HWEAPON" then return nil end
    local speed,lo,hi=self:Number(item.speed),self:Number(item.min),self:Number(item.max)
    if not speed or speed<=0 or not lo or not hi or lo<0 or hi<lo then return nil end
    return {speed=speed,hit=(lo+hi)/2,dps=(lo+hi)/2/speed}
end
function G:WeaponDamage(data,ap,crit)
    local p=self:Profile()
    local flurry=self:FlurryFactor(crit)
    local critical=1+math.max(0,math.min(1,crit))
    local swingRate=flurry/data.speed
    local auto=(data.dps+ap/p.apPerDPS)*flurry*critical
    -- Normalization affects AP only, not the weapon's base damage roll.
    local strike=(data.hit+ap/p.apPerDPS*p.weaponNormalization)*critical
    local storm=strike/p.stormstrikeInterval
    -- Renewal approximation for a configurable ICD. No recursive procs or
    -- Stormstrike-triggered procs are assumed; hit/armor are held fixed.
    local procRate=p.windfuryChance*swingRate/(1+p.windfuryChance*swingRate*p.windfuryICD)
    local procHit=data.hit+(ap+p.windfuryAP)/p.apPerDPS*data.speed
    local wind=procRate*2*procHit*critical
    return auto+storm+wind,{auto=auto,stormstrike=storm,windfury=wind,hit=data.hit+ap/p.apPerDPS*data.speed}
end
function G:WeaponCompare(item,old,context)
    local a,b=self:WeaponData(item),self:WeaponData(old)
    if not a or not b then return nil,"Two-handed weapon damage/speed unavailable" end
    if context.weaponLink~=old.link then return nil,"Equipped weapon changed; hover again" end
    local _,ap,sp=self:Delta(item.stats,old.stats)
    local m=context.calibration.measures
    local mc=((item.stats.agi or 0)-(old.stats.agi or 0))*m.meleeCritPerAgility/100
    local sc=((item.stats.int or 0)-(old.stats.int or 0))*m.spellCritPerItemIntellect/100
    if context.ap+ap<0 then return nil,"Invalid weapon AP baseline" end
    local before,components=self:WeaponDamage(b,context.ap,context.meleeCrit)
    local after,nextComponents=self:WeaponDamage(a,context.ap+ap,context.meleeCrit+mc)
    local p=self:Profile()
    local spellBefore=(p.spellBase+p.spellCoefficient*context.spellDamage)*(1+0.5*math.max(0,math.min(1,context.spellCrit)))
    local spellAfter=(p.spellBase+p.spellCoefficient*(context.spellDamage+sp))*(1+0.5*math.max(0,math.min(1,context.spellCrit+sc)))
    if before<=0 or after<=0 or spellBefore<=0 or spellAfter<=0 then return nil,"Invalid weapon damage baseline" end
    local change=100*(p.meleeShare*after/before+(1-p.meleeShare)*spellAfter/spellBefore-1)
    local oldFlurry=self:FlurryFactor(context.meleeCrit)
    local newFlurry=self:FlurryFactor(context.meleeCrit+mc)
    return {weapon=true,change=change,index=100+change,melee=100*(after/before-1),spell=100*(spellAfter/spellBefore-1),
        flurry=100*(newFlurry/oldFlurry-1),hitDelta=nextComponents.hit-components.hit,before=components,after=nextComponents}
end
