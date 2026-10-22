local _, D = ...
D.version = '0.2.0'
D.limit, D.maxEvents = 30, 800
D.potions = {118,858,929,1710,3928,13446,22829,33447}
D.rows, D.head, D.count = {}, 1, 0
D.capabilities, D.stats, D.ready, D.saved = {}, {}, false, nil
local unpackValues = unpack or table.unpack
local function pack(...) return {n=select('#',...),...} end

function D:Readable(v)
    if type(issecretvalue)=='function' then
        local ok, restricted = pcall(issecretvalue,v)
        if not ok or restricted then return false end
    end
    if type(canaccessvalue)=='function' then
        local ok, accessible = pcall(canaccessvalue,v)
        if not ok or not accessible then return false end
    end
    return true
end
function D:Plain(v)
    if not self:Readable(v) then return '<restricted>' end
    local t=type(v)
    if t=='string' then return v:gsub('[\r\n|]',' '):sub(1,100) end
    if t=='number' or t=='boolean' or t=='nil' then return tostring(v) end
    return '<'..t..'>'
end
function D:Num(v)
    if not self:Readable(v) or type(v)~='number' then return nil end
    if v~=v or v==math.huge or v==-math.huge then return nil end
    return v
end
function D:Now() return self:Num(GetTime()) or 0 end
function D:Context()
    local ok, value=pcall(InCombatLockdown)
    if ok and self:Readable(value) then return value and 'combat' or 'outside' end
    return 'unknown'
end
function D:Note(key,status)
    key=key..' ['..self:Context()..']'
    self.stats[key]=self.stats[key] or {}
    self.stats[key][status]=(self.stats[key][status] or 0)+1
end
function D:Call(key,fn,...)
    if type(fn)~='function' then self:Note(key,'missing'); return nil end
    local result=pack(pcall(fn,...))
    if not result[1] then self:Note(key,'call failed'); return nil end
    for i=2,result.n do
        if not self:Readable(result[i]) then self:Note(key,'restricted'); return nil end
    end
    self:Note(key,'readable return')
    return unpackValues(result,2,result.n)
end
function D:Add(kind,text,data)
    local row={t=self:Now(),kind=kind,text=text,data=data}
    if self.count < self.maxEvents then
        self.rows[(self.head+self.count-1)%self.maxEvents+1]=row
        self.count=self.count+1
    else
        self.rows[self.head]=row
        self.head=self.head%self.maxEvents+1
    end
end
function D:Timeline()
    local lines, now={},self:Now()
    for i=0,self.count-1 do
        local row=self.rows[(self.head+i-1)%self.maxEvents+1]
        if now-row.t<=self.limit then
            lines[#lines+1]=string.format('%.2fs %s %s',row.t-now,row.kind,row.text)
        end
    end
    return lines
end
function D:Print(text) DEFAULT_CHAT_FRAME:AddMessage('Brutefist Death Review: '..text) end
function D:Sample(reason)
    local hp=self:Call('UnitHealth',UnitHealth,'player')
    local maximum=self:Call('UnitHealthMax',UnitHealthMax,'player')
    local speed=self:Call('GetUnitSpeed',GetUnitSpeed,'player')
    local state={hp=self:Num(hp),maximum=self:Num(maximum),speed=self:Num(speed),combat=self:Context()=='combat',potions={}}
    self:Add('STATE',reason..' hp='..self:Plain(hp)..'/'..self:Plain(maximum)..' speed='..self:Plain(speed),state)
    for _,id in ipairs(self.potions) do
        local count=self:Call('ItemCount',C_Item and C_Item.GetItemCount or GetItemCount,id,false)
        count=self:Num(count)
        state.potions[id]={count=count}
        if count and count>0 then
            local fn=C_Container and C_Container.GetItemCooldown or GetItemCooldown
            local start,duration,enabled=self:Call('ItemCooldown',fn,id)
            local usable,noMana=self:Call('ItemUsable',C_Item and C_Item.IsUsableItem or IsUsableItem,id)
            local potion=state.potions[id]
            potion.start,potion.duration,potion.enabled=self:Num(start),self:Num(duration),self:Num(enabled)
            if type(usable)=='boolean' and self:Readable(usable) then potion.usable=usable end
            self:Add('POTION',string.format('id=%d bags=%d cooldownStart=%s duration=%s enabled=%s usable=%s noMana=%s',id,count,self:Plain(start),self:Plain(duration),self:Plain(enabled),self:Plain(usable),self:Plain(noMana)))
        end
    end
end
function D:CombatEvent(...)
    local fn=C_CombatLog and C_CombatLog.GetCurrentEventInfo or CombatLogGetCurrentEventInfo
    local payload
    if type(fn)=='function' then
        payload=pack(self:Call('CombatLog payload',fn))
    else
        payload=pack(...)
        self:Note('CombatLog payload',payload.n>0 and 'legacy event received' or 'no reader')
    end
    local subevent=payload[2]
    if not self:Readable(subevent) or type(subevent)~='string' then return end
    local guid=self:Call('UnitGUID',UnitGUID,'player')
    if not self:Readable(guid) or type(guid)~='string' then return end
    local source,destination=payload[4],payload[8]
    if not self:Readable(source) or not self:Readable(destination) then return end
    if source~=guid and destination~=guid then return end
    local parts={}
    for i=1,math.min(payload.n,25) do parts[#parts+1]=i..'='..self:Plain(payload[i]) end
    local data={event=subevent,source=self:Plain(payload[5]),target=self:Plain(payload[9]),incoming=destination==guid,outgoing=source==guid}
    if subevent=='SWING_DAMAGE' then
        data.spell='Melee';data.amount=self:Num(payload[12]);data.overkill=self:Num(payload[13])
    elseif subevent=='ENVIRONMENTAL_DAMAGE' then
        data.spell=self:Plain(payload[12]);data.amount=self:Num(payload[13]);data.overkill=self:Num(payload[14])
    else
        data.spell=self:Plain(payload[13]);data.spellID=self:Num(payload[12])
        if subevent=='SPELL_DAMAGE' or subevent=='SPELL_PERIODIC_DAMAGE' or subevent=='RANGE_DAMAGE' or subevent=='DAMAGE_SHIELD' or subevent=='DAMAGE_SPLIT' then
            data.amount=self:Num(payload[15]);data.overkill=self:Num(payload[16])
        elseif subevent=='SPELL_HEAL' or subevent=='SPELL_PERIODIC_HEAL' then
            data.heal=self:Num(payload[15]);data.overheal=self:Num(payload[16])
        elseif subevent=='SPELL_CAST_FAILED' then data.failure=self:Plain(payload[15]) end
    end
    self:Add('COMBAT',table.concat(parts,' '),data)
end
function D:Report()
    local version,build,_,interface=self:Call('GetBuildInfo',GetBuildInfo)
    local lines={'Brutefist Death Review diagnostics '..self.version,
        'Client='..self:Plain(version)..' build='..self:Plain(build)..' interface='..self:Plain(interface),
        'DIAGNOSTIC ONLY: no cause-of-death or missed-opportunity conclusions.',
        'Rolling window: 30 seconds / 800 events. Recording pauses on death or /bdeath stop.',
        'Checks cover a fixed list of common healing potions, not every consumable.',
        'Readable returns establish access only, not correctness or usability in every situation.',
        'Recording='..tostring(self.recording)..' capturedEvents='..self.count,
        '--- Event registration ---'}
    local keys={};for k in pairs(self.capabilities) do keys[#keys+1]=k end;table.sort(keys)
    for _,k in ipairs(keys) do lines[#lines+1]=k..': '..self.capabilities[k] end
    lines[#lines+1]='--- Observed API results (combat vs outside) ---'
    keys={};for k in pairs(self.stats) do keys[#keys+1]=k end;table.sort(keys)
    for _,k in ipairs(keys) do
        local parts={};for status,n in pairs(self.stats[k]) do parts[#parts+1]=status..'='..n end;table.sort(parts)
        lines[#lines+1]=k..': '..table.concat(parts,', ')
    end
    lines[#lines+1]='--- Last recording snapshot ---'
    for _,line in ipairs(self.snapshot or self:Timeline()) do lines[#lines+1]=line end
    lines[#lines+1]='--- End report ---'
    return table.concat(lines,'\n')
end
function D:Save()
    if self.saved then
        self.saved.lastReport=self:Report()
        if self.Review then self.saved.lastReview=self:Review() end
    end
end
function D:Start()
    self.rows,self.head,self.count,self.stats,self.snapshot,self.frozenRows,self.stoppedAt,self.deathAt={},1,0,{},nil,nil,nil,nil
    self.recording=true
    self:Add('MARK','Recording started')
    self:Sample('start')
    self:Print('Recording. Fight normally, use a healing potion when needed, then /bdeath stop and /bdeath report.')
end
function D:Stop(reason)
    if not self.recording then return end
    self:Add('MARK',reason or 'Stopped')
    self.stoppedAt=self:Now()
    self.frozenRows=self:ReviewRows()
    self.recording=false
    self.snapshot=self:Timeline()
    self:Save()
end
D.frame=CreateFrame('Frame')
function D:Register(event)
    local ok=pcall(self.frame.RegisterEvent,self.frame,event)
    self.capabilities[event]=ok and 'registered (delivery not yet proven)' or 'registration rejected'
end
function D:Event(event,...)
    if event=='ADDON_LOADED' then
        local name=...
        if not self:Readable(name) or name~='BrutefistDeathReview' then return end
        BrutefistDeathReviewDB=type(BrutefistDeathReviewDB)=='table' and BrutefistDeathReviewDB or {}
        self.saved=BrutefistDeathReviewDB;self.ready=true
        self:Print('Loaded. /bdeath start records a test; /bdeath report opens the report.')
        return
    end
    if not self.ready then return end
    if event=='PLAYER_LOGOUT' then
        if self.recording then self:Stop('Logout') end
        return
    end
    if not self.recording then return end
    self.capabilities[event]='event received'
    if event=='COMBAT_LOG_EVENT_UNFILTERED' then self:CombatEvent(...)
    elseif event=='PLAYER_DEAD' then self.deathAt=self:Now();self:Stop('PLAYER_DEAD - frozen automatically');self:Print('Death review saved. /bdeath report after combat.')
    elseif event=='UNIT_HEALTH' or event=='UNIT_MAXHEALTH' or event:find('^UNIT_SPELLCAST') then
        local unit=...
        if self:Readable(unit) and unit=='player' then
            if event:find('^UNIT_SPELLCAST') then
                local parts={};for i=1,select('#',...) do parts[#parts+1]=self:Plain(select(i,...)) end
                self:Add(event,table.concat(parts,' '))
            else self:Sample(event) end
        end
    else self:Add('EVENT',event);self:Sample(event) end
end
D.frame:SetScript('OnEvent',function(_,event,...)
    local ok=pcall(D.Event,D,event,...)
    if not ok then D:Note('Recorder','handler failed') end
end)
local elapsed=0
D.frame:SetScript('OnUpdate',function(_,dt)
    elapsed=elapsed+dt
    if elapsed<0.5 then return end
    elapsed=0
    if D.ready and D.recording then
        local ok=pcall(D.Sample,D,'periodic')
        if not ok then D:Note('Recorder','sample failed') end
    end
end)
for _,event in ipairs({'ADDON_LOADED','PLAYER_LOGOUT','PLAYER_DEAD','PLAYER_REGEN_DISABLED','PLAYER_REGEN_ENABLED','UNIT_HEALTH','UNIT_MAXHEALTH','BAG_UPDATE_DELAYED','BAG_UPDATE_COOLDOWN','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED','COMBAT_LOG_EVENT_UNFILTERED'}) do D:Register(event) end
