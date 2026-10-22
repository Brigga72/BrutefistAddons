local _, G = ...
G.slots = {INVTYPE_HEAD={1},INVTYPE_NECK={2},INVTYPE_SHOULDER={3},INVTYPE_BODY={4},
    INVTYPE_CHEST={5},INVTYPE_ROBE={5},INVTYPE_WAIST={6},INVTYPE_LEGS={7},INVTYPE_FEET={8},
    INVTYPE_WRIST={9},INVTYPE_HAND={10},INVTYPE_FINGER={11,12},INVTYPE_TRINKET={13,14},
    INVTYPE_CLOAK={15},INVTYPE_2HWEAPON={16},INVTYPE_WEAPON={16},INVTYPE_WEAPONMAINHAND={16},
    INVTYPE_SHIELD={17},INVTYPE_WEAPONOFFHAND={17},INVTYPE_HOLDABLE={17},INVTYPE_RANGED={18},INVTYPE_RANGEDRIGHT={18}}
local keys = {ITEM_MOD_STRENGTH_SHORT="str",ITEM_MOD_AGILITY_SHORT="agi",ITEM_MOD_INTELLECT_SHORT="int",
    ITEM_MOD_STAMINA_SHORT="sta",ITEM_MOD_SPIRIT_SHORT="spi",ITEM_MOD_ATTACK_POWER_SHORT="ap",
    ITEM_MOD_SPELL_POWER_SHORT="sp",ITEM_MOD_SPELL_DAMAGE_DONE_SHORT="sp",RESISTANCE0_NAME="armor",ITEM_MOD_DAMAGE_PER_SECOND_SHORT="dps"}
local function tooltipText(line, key)
    if G:Secret(line[key]) or type(line[key]) ~= "string" then return nil end
    return line[key]
end
-- Recognize only unconditional, all-school spell bonuses already supplied
-- by GetItemStats. Tooltip text validates the effect; it never adds it twice.
local function modeledEquip(text, stats)
    local amount = text:match("^Equip: Increases damage and healing done by magical spells and effects by up to (%d+)%.?$")
        or text:match("^Equip: Increases damage done by magical spells and effects by up to (%d+)%.?$")
    return amount ~= nil and stats.sp == tonumber(amount)
end
function G:Read(link)
    if self:Secret(link) or type(link) ~= "string" then return nil, "Item link unavailable" end
    if not C_Item or type(C_Item.GetItemInfo) ~= "function" or type(C_Item.GetItemStats) ~= "function" then
        return nil, "Required item API absent"
    end
    local ok, name, _, _, _, requiredLevel, _, _, _, equip = pcall(C_Item.GetItemInfo, link)
    if not ok or self:Secret(name) or type(name) ~= "string" then
        if C_Item.RequestLoadItemDataByID then
            local id = tonumber(link:match("item:(%d+)"))
            if id then pcall(C_Item.RequestLoadItemDataByID,id) end
        end
        return nil, "Item data pending; hover again"
    end
    if self:Secret(equip) or type(equip) ~= "string" then return nil, "Equip slot unavailable" end
    local success, raw = pcall(C_Item.GetItemStats, link)
    if not success or not self:Table(raw) then return nil, "Item stats unavailable" end
    local item = {name=name, link=link, equip=equip, level=self:Number(requiredLevel), stats={}, unmodeled={}, effects=false}
    for key, value in pairs(raw) do
        if self:Secret(key) then return nil, "Stat keys restricted" end
        local n = self:Number(value)
        if n == nil then return nil, "Stat values unavailable" end
        if keys[key] then item.stats[keys[key]] = (item.stats[keys[key]] or 0) + n
        elseif n ~= 0 then item.unmodeled[#item.unmodeled+1] = self:Text(key) .. "=" .. n end
    end
    if C_TooltipInfo and type(C_TooltipInfo.GetHyperlink) == "function" then
        local worked, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if worked and self:Table(data) and self:Table(data.lines) then
            for _, line in ipairs(data.lines) do
                if self:Table(line) then
                    local left, right = tooltipText(line,"leftText"), tooltipText(line,"rightText")
                    if left then
                        if (left:match("^Equip:") and not modeledEquip(left,item.stats)) or left:match("^Use:") or left:match("^Set:") or left:match("^Chance on hit:") then item.effects=true end
                        local lo, hi = left:match("(%d+)%s*%-%s*(%d+)%s+Damage")
                        if lo then item.min, item.max = tonumber(lo), tonumber(hi) end
                    end
                    local speedText = right or left
                    local speed = speedText and speedText:match("Speed%s+(%d+%.?%d*)")
                    if speed then item.speed = tonumber(speed) end
                end
            end
            item.tooltipReadable=true
        end
    end
    return item
end
function G:Weapon(item)
    return item.equip:find("WEAPON") or item.equip:find("RANGED")
end
function G:WeaponLine(a, b)
    local av = a.min and a.max and (a.min+a.max)/2 or nil
    local bv = b.min and b.max and (b.min+b.max)/2 or nil
    local ad = a.stats.dps or (av and a.speed and a.speed > 0 and av/a.speed or nil)
    local bd = b.stats.dps or (bv and b.speed and b.speed > 0 and bv/b.speed or nil)
    local parts = {}
    if ad and bd then
        parts[#parts+1] = string.format("DPS %+.2f (%.2f vs %.2f)", ad-bd, ad, bd)
    end
    if av and bv then parts[#parts+1] = string.format("average hit %+.1f",av-bv) end
    if a.speed and b.speed then parts[#parts+1] = string.format("speed %+.2fs",a.speed-b.speed) end
    if #parts==0 then return "Weapon damage/speed unavailable; use native comparison." end
    if not av or not bv or not a.speed or not b.speed then parts[#parts+1]="hit/speed data incomplete" end
    return "Weapon: " .. table.concat(parts," | ")
end
