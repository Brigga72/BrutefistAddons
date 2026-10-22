local _, G = ...
local function difference(item,old,key) return (item.stats[key] or 0)-(old.stats[key] or 0) end
local function rounded(value)
    if value>=0 then return math.floor(value+0.5) end
    return math.ceil(value-0.5)
end
function G:ShortTradeoffs(item,old)
    local parts={}
    local _,ap,sp=self:Delta(item.stats,old.stats)
    if math.abs(ap)>=0.5 then
        parts[#parts+1]=(ap>0 and "gains about " or "loses about ")..math.abs(rounded(ap)).." AP"
    end
    if math.abs(sp)>=0.5 then
        parts[#parts+1]=(sp>0 and "gains about " or "loses about ")..math.abs(rounded(sp)).." spell damage"
    end
    for _,entry in ipairs({{"sta","Stamina"},{"armor","Armor"},{"int","Intellect"}}) do
        local value=difference(item,old,entry[1])
        if value~=0 then parts[#parts+1]=(value>0 and "gains " or "loses ")..math.abs(value).." "..entry[2] end
    end
    return #parts>0 and table.concat(parts,", ") or "no important modeled stat difference"
end
function G:Verdict(item,old,model,reason)
    if item.level and type(UnitLevel)=="function" then
        local ok,level=pcall(UnitLevel,"player");level=ok and self:Number(level) or nil
        if level and item.level>level then return "NO, cannot equip yet","Requires a higher level.","no" end
    end
    if (self:Weapon(item) and item.equip~="INVTYPE_2HWEAPON") or item.equip=="INVTYPE_TRINKET" or item.equip=="INVTYPE_SHIELD" or item.equip=="INVTYPE_HOLDABLE" then
        return "CANNOT ASSESS","This item needs a weapon or special-effect comparison.","unknown"
    end
    if #item.unmodeled>0 or #old.unmodeled>0 or item.effects or old.effects or not item.tooltipReadable or not old.tooltipReadable then
        return "CANNOT ASSESS","Some stats or effects are not modeled. Check the native tooltip.","unknown"
    end
    if not model then
        if reason and reason:find("Calibrate") then return "CALIBRATION NEEDED","Run /bgear baseline and /bgear calibrate first.","unknown" end
        return "CANNOT ASSESS","Comparison data is unavailable; check /bgear diag.","unknown"
    end
    local tradeoffs=self:ShortTradeoffs(item,old)
    if model.weapon then
        local hits=math.abs(model.hitDelta)<0.5 and "similar individual hits" or (model.hitDelta>0 and "harder individual hits" or "softer individual hits")
        local confidence=math.abs(model.change)<3 and "Small estimated difference" or "Clear difference in the model"
        if model.change>=0.5 then return "YES, upgrade for questing",confidence..": higher damage, "..hits.."; "..tradeoffs..".","yes" end
        if model.change<=-0.5 then return "NO, keep your equipped weapon",confidence..": lower damage, "..hits.."; "..tradeoffs..".","no" end
        return "TOO CLOSE TO CALL","Similar estimated damage, "..hits.."; "..tradeoffs..".","unknown"
    end
    if model.change>=0.5 then
        return "YES, upgrade for questing",(model.change<3 and "Small estimated advantage; " or "Clear damage advantage in the model; ")..tradeoffs..".","yes"
    elseif model.change<=-0.5 then
        return "NO, keep your equipped item",(model.change>-3 and "Small estimated disadvantage; " or "Clear damage disadvantage in the model; ")..tradeoffs..".","no"
    end
    local sta,armor,int=difference(item,old,"sta"),difference(item,old,"armor"),difference(item,old,"int")
    if sta>=0 and armor>=0 and int>=0 and (sta>0 or armor>0 or int>0) then
        return "YES, upgrade for questing","Similar estimated damage, better survival or mana; "..tradeoffs..".","yes"
    elseif sta<=0 and armor<=0 and int<=0 and (sta<0 or armor<0 or int<0) then
        return "NO, keep your equipped item","Similar estimated damage, less survival or mana; "..tradeoffs..".","no"
    end
    return "TOO CLOSE TO CALL","Similar estimated damage; "..tradeoffs..".","unknown"
end
