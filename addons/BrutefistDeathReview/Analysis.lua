local _,D=...
-- Analysis uses structured observations, never parses localized combat text.
function D:ReviewRows()
    if self.frozenRows then return self.frozenRows end
    local rows,now={},self:Now()
    for i=0,self.count-1 do
        local row=self.rows[(self.head+i-1)%self.maxEvents+1]
        if now-row.t<=self.limit then rows[#rows+1]=row end
    end
    return rows
end
function D:PotionState(p,t)
    if not p or not p.count then return 'unknown' end
    if p.count<=0 then return 'none carried' end
    if p.start==nil or p.duration==nil or p.enabled==nil then return 'unknown' end
    if p.enabled~=1 then return 'disabled' end
    if p.duration>0 and p.start+p.duration>t then
        return p.duration<=3 and 'short lockout' or 'cooldown'
    end
    if p.usable==nil then return 'unknown' end
    return p.usable and 'observed ready' or 'unusable'
end
function D:Analyze(rows)
    local result={timeline={},windows={},damage=0,healing=0,healthSamples=0,shortLocks=0}
    local open,previous={},nil
    local reference=self.stoppedAt or self:Now()
    local function add(t,text) result.timeline[#result.timeline+1]=string.format('%6.1fs  %s',t-reference,text) end
    local function finish(id)
        local window=open[id]
        if window and window.last-window.first>=1.5 then result.windows[#result.windows+1]=window end
        open[id]=nil
    end
    for _,row in ipairs(rows) do
        local data=row.data
        if row.kind=='STATE' and data then
            local health=data.hp and data.maximum and data.maximum>0 and data.hp/data.maximum or nil
            if health then
                result.healthSamples=result.healthSamples+1
                if not result.lowest or health<result.lowest then result.lowest=health end
                local low=health<=0.35 and data.hp>0
                if low and (not previous or not previous.low) then add(row.t,string.format('Low health: %d/%d (%.0f%%).',data.hp,data.maximum,health*100)) end
                previous={low=low}
            else previous=nil end
            local eligible={}
            for id,potion in pairs(data.potions or {}) do
                local status=self:PotionState(potion,row.t)
                if status=='short lockout' then result.shortLocks=result.shortLocks+1 end
                if health and health<=0.35 and data.hp>0 and data.combat and status=='observed ready' then
                    eligible[id]=true
                    if open[id] and row.t-open[id].last>1 then finish(id) end
                    if not open[id] then open[id]={id=id,first=row.t,last=row.t,hp=data.hp,maximum=data.maximum} end
                    open[id].last=row.t
                end
            end
            for id in pairs(open) do if not eligible[id] then finish(id) end end
        elseif row.kind=='COMBAT' and data then
            if data.incoming and data.amount then
                result.damage=result.damage+data.amount
                result.lastHit={t=row.t,data=data}
                add(row.t,string.format('%s: %s hit you for %d%s.',data.source,data.spell,data.amount,(data.overkill and data.overkill>0) and ' (overkill '..data.overkill..')' or ''))
            elseif data.incoming and data.heal then
                local effective=data.overheal and math.max(0,data.heal-data.overheal) or nil
                result.healing=result.healing+(effective or 0)
                add(row.t,string.format('%s healed you with %s: %d%s.',data.source,data.spell,data.heal,effective and ' ('..effective..' effective)' or ' (effective amount unknown)'))
            elseif data.outgoing and data.failure then
                add(row.t,'Failed '..data.spell..': '..data.failure..'.')
            end
        elseif row.kind=='MARK' then add(row.t,row.text) end
    end
    for id in pairs(open) do finish(id) end
    table.sort(result.windows,function(a,b) if a.first==b.first then return a.id<b.id end;return a.first<b.first end)
    return result
end
function D:Review()
    local rows=self:ReviewRows()
    if #rows==0 then return 'Brutefist Death Review '..self.version..'\nNo recording yet. /bdeath start before a short fight; /bdeath stop afterwards.' end
    local r=self:Analyze(rows)
    local version,build,_,interface=self:Call('GetBuildInfo',GetBuildInfo)
    local lines={'Brutefist Death Review '..self.version,
        'Client '..self:Plain(version)..' / build '..self:Plain(build)..' / interface '..self:Plain(interface),
        self.deathAt and 'DEATH CAPTURED' or (self.recording and 'LIVE RECORDING - stop after the fight to save it.' or 'FIGHT REVIEW - no player death recorded.'),
        string.format('Retained %.1f seconds, %d rows. Older events may be absent.',rows[#rows].t-rows[1].t,#rows),
        string.format('Recorded incoming damage: %d. Known effective healing: %d.',r.damage,r.healing)}
    if r.lowest then lines[#lines+1]=string.format('Lowest sampled health: %.0f%%.',r.lowest*100) else lines[#lines+1]='Health history unavailable; no health-based suggestions.' end
    if self.deathAt then
        local hit=r.lastHit
        if hit and self.deathAt-hit.t<=2 then
            lines[#lines+1]=string.format('Last recorded hit before death: %s / %s / %d damage (%.2fs earlier).',hit.data.source,hit.data.spell,hit.data.amount,self.deathAt-hit.t)
        else lines[#lines+1]='No recent incoming hit recorded; cause of death is unknown.' end
    end
    lines[#lines+1]='\nPOTION REVIEW'
    lines[#lines+1]='Potential windows: carried potion + cooldown clear + usability true, while alive, in combat and at/below 35% health.'
    local reference=self.stoppedAt or self:Now()
    for i,window in ipairs(r.windows) do
        if i<=8 then lines[#lines+1]=string.format('Item %d: observed ready from %.1fs to %.1fs (%.1fs), starting at %d/%d health.',window.id,window.first-reference,window.last-reference,window.last-window.first,window.hp,window.maximum) end
    end
    if #r.windows==0 then lines[#lines+1]='No sustained potential potion window established in the retained data.' end
    if r.shortLocks>0 then lines[#lines+1]='Short item lockouts observed; these intervals were excluded. They may reflect a global cooldown or another temporary lockout; the source was not verified.' end
    lines[#lines+1]='These are observed opportunities, not confirmed mistakes. Stuns, control effects and exact reaction time are not checked. A later potion use can follow a listed window.'
    lines[#lines+1]='\nTIMELINE (times relative to death or recording stop)'
    for i,line in ipairs(r.timeline) do if i<=160 then lines[#lines+1]=line end end
    if #r.timeline>160 then lines[#lines+1]='Timeline display truncated; /bdeath diagnostics contains the raw snapshot.' end
    lines[#lines+1]='\nMovement speed was recorded, but safe escape routes and whether retreat would succeed cannot be established. No run-sooner verdict is issued.'
    lines[#lines+1]='Read /bdeath diagnostics for API failures/restrictions. Missing samples are not treated as available potions.'
    return table.concat(lines,'\n')
end
