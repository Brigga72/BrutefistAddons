local _,G=...
local function call(fn,...)
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn,...)
    if ok and not G:Secret(value) then return value end
end
function G:Profile()
    local p={}
    for k in pairs(self.defaults) do p[k]=self.db[k] end
    for k,v in pairs(self.runtimeProfile or {}) do p[k]=v end
    return p
end
function G:RefreshProfile(force)
    if not self.db or InCombatLockdown() then return end
    local now=self:Number(call(GetTime))
    if not force and now and self.profileTime and now-self.profileTime<2 then return end
    self.profileTime=now
    local p,notes,overrides={},{},{}
    for k in pairs(self.defaults) do p[k]=self.db[k] end
    local function spell(id)
        local info=call(C_Spell and C_Spell.GetSpellInfo,id)
        if not self:Table(info) or self:Secret(info.name) or type(info.name)~="string" then return end
        local description=call(C_Spell and C_Spell.GetSpellDescription,id)
        if type(description)~="string" then return end
        return info.name,description
    end
    local recognized={}
    local ok,err=pcall(function()
        local configID=self:Number(call(C_ClassTalents and C_ClassTalents.GetActiveConfigID))
        local config=configID and call(C_Traits and C_Traits.GetConfigInfo,configID)
        if not self:Table(config) or not self:Table(config.treeIDs) then error("Talent definitions unavailable") end
        for _,tree in ipairs(config.treeIDs) do
            tree=self:Number(tree);if not tree then error("Restricted talent tree") end
            local nodes=call(C_Traits.GetTreeNodes,tree)
            if not self:Table(nodes) or #nodes>1000 then error("Talent nodes unavailable") end
            for _,node in ipairs(nodes) do
                node=self:Number(node);if not node then error("Restricted talent node") end
                local info=call(C_Traits.GetNodeInfo,configID,node)
                if not self:Table(info) then error("Talent node unavailable") end
                local rank=self:Number(info.activeRank)
                if not rank then error("Talent rank unavailable") end
                if rank>0 then
                    if not self:Table(info.activeEntry) then error("Selected entry unavailable") end
                    local entryID=self:Number(info.activeEntry.entryID)
                    local entry=entryID and call(C_Traits.GetEntryInfo,configID,entryID)
                    local definitionID=self:Table(entry) and self:Number(entry.definitionID)
                    local definition=definitionID and call(C_Traits.GetDefinitionInfo,definitionID)
                    local id=self:Table(definition) and self:Number(definition.spellID)
                    local name,desc
                    if id then name,desc=spell(id) end
                    if name and desc then
                        local value
                        -- Passive spell descriptions can expose maximum-rank or
                        -- placeholder effects. Use selected-rank mappings for
                        -- these two talents, verified against this client's ranks.
                        if name=="Ancestral Knowledge" then if rank>=1 and rank<=5 and rank%1==0 then value=rank*2;recognized.intellectBonus=value/100 end
                        elseif name=="Mental Dexterity" then value=tonumber(desc:match("(%d+)%% of your [Ii]ntellect"));if value then recognized.intellectAP=value/100 end
                        elseif name=="Mental Quickness" then value=tonumber(desc:match("(%d+)%% of your [Ii]ntellect"));if value then recognized.intellectSP=value/100 end
                        elseif name=="Flurry" then if rank>=1 and rank<=5 and rank%1==0 then value=rank*5;recognized.flurryHaste=value/100 end end
                        if value then notes[#notes+1]="Automatic talent: "..name..", selected rank "..rank..", coefficient "..value.."%" end
                    end
                end
            end
        end
    end)
    if ok then for k,v in pairs(recognized) do if v>=0 and v<=1 then p[k]=v;overrides[k]=v end end
    else notes[#notes+1]="Talent automation fallback: "..self:Text(err) end
    local knownID
    for _,id in ipairs({8232,8235,10486,16362}) do
        local known=call(IsPlayerSpell,id)
        if known==true then knownID=id end
    end
    if knownID then
        local name=spell(knownID)
        -- Use rendered tooltip text for Windfury, not raw spell descriptions,
        -- which may omit the player's talent modifiers.
        local tooltip=call(C_TooltipInfo and C_TooltipInfo.GetSpellByID,knownID)
        local bonus,chance
        if self:Table(tooltip) and self:Table(tooltip.lines) then
            for _,line in ipairs(tooltip.lines) do
                if self:Table(line) and not self:Secret(line.leftText) and type(line.leftText)=="string" then
                    local text=line.leftText
                    bonus=bonus or tonumber(text:match("with (%d+) extra melee attack power"))
                    chance=chance or tonumber(text:match("(%d+)%% chance"))
                end
            end
        end
        if name=="Windfury Weapon" and bonus and bonus<=2000 and chance and chance<=100 then
            p.windfuryAP=bonus;p.windfuryChance=chance/100;overrides.windfuryAP=bonus;overrides.windfuryChance=chance/100
            notes[#notes+1]="Automatic Windfury: spell "..knownID..", tooltip AP "..bonus..", chance "..chance.."%. Verify talent modifiers are included."
        else notes[#notes+1]="Windfury rank found; description unreadable/unrecognized. Manual AP retained." end
    else notes[#notes+1]="Windfury rank API unavailable/unreadable. Manual AP retained." end
    local u=self.usage
    if u and u.casts>=5 and u.seconds>=60 then
        p.stormstrikeInterval=math.max(1,u.seconds/u.casts);overrides.stormstrikeInterval=p.stormstrikeInterval
        notes[#notes+1]=string.format("Observed Stormstrike: %.2fs per cast across %.1fs combat, %d casts (session).",p.stormstrikeInterval,u.seconds,u.casts)
    else notes[#notes+1]="Stormstrike: manual interval until 5 casts and 60 seconds of completed combat are recorded." end
    for _,k in ipairs({"intellectBonus","intellectAP","intellectSP","flurryHaste"}) do
        if not recognized[k] or not ok then notes[#notes+1]="Manual talent fallback: "..k.."="..p[k] end
    end
    self.runtimeProfile=overrides;self.adaptiveNotes=notes
end
function G:AdaptiveReport()
    self:RefreshProfile(true)
    local lines={"--- Automatic profile / usage ---"}
    for _,line in ipairs(self.adaptiveNotes or {"Unavailable"}) do lines[#lines+1]=line end
    lines[#lines+1]="Crit calibration remains level/talent specific; automation does not invent new measured rates."
    lines[#lines+1]="Confidence describes model separation, not measured accuracy. Hit, armor and item procs remain unmodeled."
    local events={}
    for event in pairs(self.adaptiveEvents) do events[#events+1]=event end
    table.sort(events)
    for _,event in ipairs(events) do lines[#lines+1]="Adaptive event "..event..": "..tostring(self.adaptiveEvents[event]) end
    return lines
end
function G:UsageEvent(event,unit,castID,spellID)
    local now=self:Number(call(GetTime));if not now then return end
    self.usage=self.usage or {seconds=0,casts=0}
    local u=self.usage
    if event=="PLAYER_REGEN_DISABLED" then self.combatStart=now;self.combatCasts=0;self.lastStormCast=nil
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        if self:Secret(unit) or unit~="player" or not self.combatStart then return end
        spellID=self:Number(spellID)
        if spellID==17364 and not self:Secret(castID) and type(castID)=="string" and castID~=self.lastStormCast then
            self.lastStormCast=castID;self.combatCasts=(self.combatCasts or 0)+1
        end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if self.combatStart then
            local elapsed=now-self.combatStart
            if elapsed>0 and elapsed<1800 then u.seconds=u.seconds+elapsed;u.casts=u.casts+(self.combatCasts or 0) end
        end
        self.combatStart=nil;self.profileTime=nil
    elseif event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_LEAVING_WORLD" then self.combatStart=nil;self.profileTime=nil
    else
        self.profileTime=nil;self.usage={seconds=0,casts=0}
    end
end
local f=CreateFrame("Frame")
G.adaptiveEvents={}
for _,event in ipairs({"PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","UNIT_SPELLCAST_SUCCEEDED","PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LEVEL_UP","TRAIT_CONFIG_UPDATED","SPELLS_CHANGED"}) do
    G.adaptiveEvents[event]=pcall(f.RegisterEvent,f,event)
end
f:SetScript("OnEvent",function(_,event,...) G:UsageEvent(event,...) end)
