local _, G = ...
local function call(fn,...)
    if type(fn)~="function" then error("Required calibration API absent",0) end
    local ok,a,b,c,d=pcall(fn,...)
    if not ok then error("Calibration API call failed",0) end
    return a,b,c,d
end
local function number(v)
    local n=G:Number(v);if n==nil then error("Calibration value unavailable/restricted",0) end
    return n
end
function G:TalentFingerprint()
    local id=number(call(C_ClassTalents and C_ClassTalents.GetActiveConfigID))
    local config=call(C_Traits and C_Traits.GetConfigInfo,id)
    if not self:Table(config) or not self:Table(config.treeIDs) or #config.treeIDs==0 then error("Talent trees unavailable",0) end
    local parts={"config="..id}
    for _,tree in ipairs(config.treeIDs) do
        tree=number(tree)
        local nodes=call(C_Traits.GetTreeNodes,tree)
        if not self:Table(nodes) or #nodes==0 or #nodes>1000 then error("Talent nodes unavailable",0) end
        for _,node in ipairs(nodes) do
            node=number(node)
            local info=call(C_Traits.GetNodeInfo,id,node)
            if not self:Table(info) then error("Talent node unavailable",0) end
            local rank=number(info.activeRank)
            local entry=0
            if rank>0 then
                if not self:Table(info.activeEntry) then error("Selected talent entry unavailable",0) end
                entry=number(info.activeEntry.entryID)
            end
            parts[#parts+1]=tree..":"..node..":"..rank..":"..entry
        end
    end
    table.sort(parts);return table.concat(parts,";")
end
function G:AuraFingerprint()
    local parts={}
    for i=1,255 do
        local aura=call(C_UnitAuras and C_UnitAuras.GetAuraDataByIndex,"player",i,"HELPFUL")
        if self:Secret(aura) then error("Aura result restricted",0) end
        if aura==nil then table.sort(parts);return table.concat(parts,";") end
        if not self:Table(aura) then error("Aura table unavailable",0) end
        parts[#parts+1]=number(aura.spellId)..":"..number(aura.applications)
    end
    error("Aura scan exceeded limit",0)
end
function G:CharacterKey()
    local name=call(UnitName,"player")
    local realm=call(GetRealmName)
    if self:Secret(name) or self:Secret(realm) or type(name)~="string" or type(realm)~="string" then error("Character identity unavailable",0) end
    return name.."@"..realm
end
function G:Snapshot()
    if InCombatLockdown() then error("Take calibration readings outside combat",0) end
    local s={level=number(call(UnitLevel,"player")),character=self:CharacterKey(),stats={},gear={},spellCrit={},spellDamage={},profile={}}
    for k in pairs(self.defaults) do s.profile[k]=self:Profile()[k] end
    for index,key in ipairs({"str","agi","sta","int","spi"}) do
        local _,effective=call(UnitStat,"player",index);s.stats[key]=number(effective)
    end
    local base,pos,neg=call(UnitAttackPower,"player");s.ap=number(base)+number(pos)+number(neg)
    s.meleeCrit=number(call(GetCritChance))
    for school=2,7 do
        s.spellCrit[school]=number(call(GetSpellCritChance,school))
        s.spellDamage[school]=number(call(GetSpellBonusDamage,school))
    end
    s.talents=self:TalentFingerprint();s.auras=self:AuraFingerprint()
    for slot=1,19 do
        local link=call(GetInventoryItemLink,"player",slot)
        if self:Secret(link) then error("Equipment link restricted",0) end
        if link~=nil then
            if type(link)~="string" then error("Equipment link unavailable",0) end
            local item,err=self:Read(link)
            if not item then error(err,0) end
            s.gear[slot]=item
        end
    end
    return s
end
function G:Baseline()
    self:RefreshProfile(true)
    local ok,s=pcall(self.Snapshot,self)
    if not ok then self.baseline=nil;self:Print("Baseline failed: "..self:Text(s));return end
    self.baseline=s
    self:Print("Baseline saved for level "..s.level..". Swap ONE armor item, wait two seconds, then /bgear calibrate.")
end
function G:Analyze(a,b)
    if a.character~=b.character or a.level~=b.level then error("Character or level changed; take a new baseline",0) end
    if a.talents~=b.talents then error("Talents changed; take a new baseline",0) end
    if a.auras~=b.auras then error("Buffs changed; restore buffs or take a new baseline",0) end
    for k in pairs(self.defaults) do if a.profile[k]~=b.profile[k] then error("Advisor profile changed",0) end end
    local changed={}
    for slot=1,19 do
        local x,y=a.gear[slot],b.gear[slot]
        if (x and x.link or "")~=(y and y.link or "") then changed[#changed+1]=slot end
    end
    if #changed~=1 then error("Change exactly ONE equipment slot",0) end
    local slot=changed[1]
    if slot>=13 and slot<=14 or slot>=16 or slot==4 then error("Use ordinary armor or a ring; weapons/trinkets are excluded",0) end
    local old,new=a.gear[slot],b.gear[slot]
    if not old or not new then error("Both readings need an equipped item in the changed slot",0) end
    if #old.unmodeled>0 or #new.unmodeled>0 or old.effects or new.effects or not old.tooltipReadable or not new.tooltipReadable then
        error("Use plain stat items without Equip/Use/procs or unsupported stats",0)
    end
    local delta={}
    for _,key in ipairs({"str","agi","int","sp","ap","sta","spi"}) do delta[key]=(new.stats[key] or 0)-(old.stats[key] or 0) end
    local result={level=a.level,character=a.character,talents=a.talents,from=old.name,to=new.name,measures={},notes={}}
    local agi=b.stats.agi-a.stats.agi
    if math.abs(agi)>=4 and delta.agi~=0 then
        local rate=(b.meleeCrit-a.meleeCrit)/agi
        if rate>0 and rate<1 then result.measures.meleeCritPerAgility=rate end
    end
    if math.abs(delta.int)>=5 then
        local rate=(b.spellCrit[4]-a.spellCrit[4])/delta.int
        -- Direct spell-crit items were excluded as unsupported stats/effects above.
        if rate>0 and rate<1 then result.measures.spellCritPerItemIntellect=rate end
        local observed=(b.spellDamage[4]-a.spellDamage[4]-delta.sp)/delta.int
        result.notes[#result.notes+1]=string.format("Observed spell damage/item Intellect: %.6f (rounded sheet totals; talent coefficient unchanged)",observed)
    end
    -- AP changes from simultaneous Strength and Intellect cannot identify both conversion rates.
    result.notes[#result.notes+1]=string.format("Observed changes: AP %+.0f, melee crit %+.6f pp, Nature spell crit %+.6f pp, Nature spell damage %+.0f",
        b.ap-a.ap,b.meleeCrit-a.meleeCrit,b.spellCrit[4]-a.spellCrit[4],b.spellDamage[4]-a.spellDamage[4])
    if not next(result.measures) then error("Stat differences too small: use at least 4 Agility or 5 item Intellect",0) end
    return result
end
function G:Calibrate()
    self:RefreshProfile(true)
    if not self.baseline then self:Print("Run /bgear baseline before swapping gear.");return end
    local ok,result=pcall(function() return self:Analyze(self.baseline,self:Snapshot()) end)
    if not ok then self:Print("Calibration rejected: "..self:Text(result));self:Log("Calibration rejected: "..self:Text(result));return end
    self.db.calibrations=self.db.calibrations or {}
    local key=result.character..":"..result.level
    local previous=self.db.calibrations[key]
    if previous and previous.talents==result.talents then
        for k,v in pairs(previous.measures) do if result.measures[k]==nil then result.measures[k]=v end end
    end
    self.db.calibrations[key]=result
    self.baseline=nil
    self:Print("Calibration saved for level "..result.level..". Measured crit conversions appear in item comparisons; damage weights are unchanged.")
    for k,v in pairs(result.measures) do self:Print(string.format("%s = %.6f percentage points per stat",k,v)) end
    for _,note in ipairs(result.notes) do self:Log(note) end
end
function G:CurrentCalibration()
    local ok,level,key,talents=pcall(function()
        return number(call(UnitLevel,"player")),self:CharacterKey(),self:TalentFingerprint()
    end)
    if not ok then return nil,"Calibration context unavailable" end
    local record=self.db.calibrations and self.db.calibrations[key..":"..level]
    if not record then return nil,"No calibration at current level" end
    if record.talents~=talents then return nil,"Talents changed; recalibrate" end
    return record,"Current level/talents match"
end
function G:CalibrationReport()
    local record,status=self:CurrentCalibration()
    local lines={"--- Calibration ---",status,"Baseline pending: "..tostring(self.baseline~=nil)}
    if record then
        lines[#lines+1]=record.from.." -> "..record.to
        for k,v in pairs(record.measures) do lines[#lines+1]=k.."="..string.format("%.6f",v) end
        for _,note in ipairs(record.notes) do lines[#lines+1]=note end
    end
    return lines
end

local watcher=CreateFrame("Frame")
local registered=pcall(watcher.RegisterEvent,watcher,"PLAYER_LEVEL_UP")
if registered then
    watcher:SetScript("OnEvent",function()
        G.baseline=nil
        if G.db and G.db.calibrations then G:Print("Level changed. Use /bgear baseline and /bgear calibrate to refresh measured crit conversions.") end
    end)
end
