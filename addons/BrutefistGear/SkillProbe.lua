local _, G = ...
-- Read-only capability probe. No skill headers are expanded or collapsed.
function G:SkillProbe()
    local lines={"--- Weapon skill / usability API probe ---"}
    if InCombatLockdown() then lines[#lines+1]="Blocked during combat";return lines end
    local function scan(label,countFn,infoFn)
        lines[#lines+1]=label.." count API: "..tostring(type(countFn)=="function").."; reader API: "..tostring(type(infoFn)=="function")
        if type(countFn)~="function" or type(infoFn)~="function" then return end
        local ok,count=pcall(countFn);count=ok and G:Number(count) or nil
        if not count or count<0 or count%1~=0 then lines[#lines+1]=label..": count unavailable";return end
        lines[#lines+1]=label.." visible rows: "..count
        for i=1,math.min(count,200) do
            local r={pcall(infoFn,i)}
            if not r[1] then lines[#lines+1]=label.." row "..i..": call failed"
            elseif G:Table(r[2]) then
                local fields={}
                for k,v in pairs(r[2]) do
                    if not G:Secret(k) and type(k)=="string" then
                        local t=type(v)
                        if G:Secret(v) or t=="string" or t=="number" or t=="boolean" then fields[#fields+1]=k.."="..G:Text(v) end
                    end
                    if #fields>=24 then break end
                end
                table.sort(fields);lines[#lines+1]=label.." row "..i..": "..table.concat(fields,", ")
            else
                lines[#lines+1]=label.." row "..i..": name="..G:Text(r[2])..", header="..G:Text(r[3])..", expanded="..G:Text(r[4])
                    ..", rank="..G:Text(r[5])..", temporary="..G:Text(r[6])..", modifier="..G:Text(r[7])..", max="..G:Text(r[8])
            end
        end
        if count>200 then lines[#lines+1]=label..": truncated after 200 rows" end
    end
    scan("Legacy skills",GetNumSkillLines,GetSkillLineInfo)
    scan("Modern skills",C_SkillInfo and C_SkillInfo.GetNumSkillLines,C_SkillInfo and C_SkillInfo.GetSkillLineInfo)
    local function item(label,link)
        if G:Secret(link) or type(link)~="string" then lines[#lines+1]=label..": no readable item link";return end
        local fn=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        if type(fn)=="function" then
            local ok,id,kind,sub,loc,_,class,subclass=pcall(fn,link)
            lines[#lines+1]=label.." type: "..(ok and ("id="..G:Text(id)..", type="..G:Text(kind)..", subtype="..G:Text(sub)..", equip="..G:Text(loc)..", class="..G:Text(class)..", subclass="..G:Text(subclass)) or "call failed")
        else lines[#lines+1]=label.." type: API absent" end
        for _,api in ipairs({{"C_Item.IsUsableItem",C_Item and C_Item.IsUsableItem},{"IsUsableItem",IsUsableItem}}) do
            if type(api[2])=="function" then
                local ok,usable,mana=pcall(api[2],link)
                lines[#lines+1]=label.." "..api[1]..": "..(ok and ("usable="..G:Text(usable)..", insufficientMana="..G:Text(mana)) or "call failed")
            else lines[#lines+1]=label.." "..api[1]..": API absent" end
        end
    end
    for _,slot in ipairs({16,17}) do
        local ok,link=false,nil
        if type(GetInventoryItemLink)=="function" then ok,link=pcall(GetInventoryItemLink,"player",slot) end
        if ok then item(slot==16 and "Main hand" or "Off hand",link)
        else item(slot==16 and "Main hand" or "Off hand",nil) end
    end
    item("Last hovered item",self.lastProbeLink)
    lines[#lines+1]="Collapsed skill headers may hide rows. Expand your weapon skills in the Skills panel and rerun if needed."
    lines[#lines+1]="Probe only: no scoring/settings changed. Usable=false is raw API output, not yet an equip verdict."
    return lines
end
