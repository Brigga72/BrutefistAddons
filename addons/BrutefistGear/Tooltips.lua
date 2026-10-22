local _, G = ...
function G:Append(tip)
    if not self.db or (tip ~= GameTooltip and tip ~= ItemRefTooltip) then return end
    local ok, _, link = pcall(tip.GetItem, tip)
    if not ok or self:Secret(link) or type(link) ~= "string" then return end
    local item, errorText = self:Read(link)
    if not item then
        self:Log(errorText); tip:AddLine("Gear Advisor: item data unavailable, hover again.",0.8,0.7,0.5,true); return
    end
    local slots = self.slots[item.equip]
    if not slots then return end
    if self:Weapon(item) then self.lastProbeLink=link end
    self:RefreshProfile()
    local calibration
    if not InCombatLockdown() then calibration = self:CurrentCalibration() end
    local context, modelError = self:QuestingContext(calibration)
    tip:AddLine(" ")
    for _, slot in ipairs(slots) do
        local success, worn = pcall(GetInventoryItemLink,"player",slot)
        if not success or self:Secret(worn) then
            tip:AddLine("CANNOT ASSESS: equipped item unavailable",1,0.8,0.4,true)
        elseif worn == nil then
            tip:AddLine("EMPTY SLOT: check whether you can use this item",1,0.8,0.4,true)
        else
            local old, err = self:Read(worn)
            if not old then tip:AddLine("CANNOT ASSESS: equipped item data pending",1,0.8,0.4,true)
            else
                local model, reason
                if context then model, reason = self:QuestingCompare(item,old,context) end
                local verdict, explanation, kind = self:Verdict(item,old,model,reason or modelError)
                if #slots>1 then tip:AddLine("Compared with "..old.name,0.8,0.8,0.7,true) end
                local r,g,b=1,0.8,0.4
                if kind=="yes" then r,g,b=0.4,0.95,0.55 elseif kind=="no" then r,g,b=1,0.45,0.35 end
                tip:AddLine(verdict,r,g,b,true)
                tip:AddLine(explanation,0.85,0.85,0.75,true)
                if model and model.weapon then
                    local warning=self:SkillWarning(item,old)
                    if warning then tip:AddLine(warning,1,0.8,0.4,true);self:Log(warning) end
                end
                local delta,ap,sp=self:Delta(item.stats,old.stats)
                self:Log(item.name.." vs "..old.name..": "..verdict)
                self:Log(string.format("Stats: score %+.4f, AP %+.4f, SP %+.4f, Armor %+.0f, Stamina %+.0f, Intellect %+.0f",delta,ap,sp,
                    (item.stats.armor or 0)-(old.stats.armor or 0),(item.stats.sta or 0)-(old.stats.sta or 0),(item.stats.int or 0)-(old.stats.int or 0)))
                if model then
                    self:Log(string.format("Questing: %s vs %s: index %+.4f, melee %+.4f%%, spell %+.4f%%, Flurry factor %+.4f%%",item.name,old.name,model.change,model.melee,model.spell,model.flurry))
                    if model.weapon then
                        self:Log(string.format("Weapon components (old -> new): auto %.4f -> %.4f; Stormstrike %.4f -> %.4f; Windfury %.4f -> %.4f; hit delta %+.4f",
                            model.before.auto,model.after.auto,model.before.stormstrike,model.after.stormstrike,model.before.windfury,model.after.windfury,model.hitDelta))
                    end
                else self:Log("Questing unavailable: "..(reason or modelError or "Unknown")) end
                if self:Weapon(item) then self:Log(self:WeaponLine(item,old)) end
                for _,key in ipairs(item.unmodeled) do self:Log("Candidate unsupported: "..key) end
                for _,key in ipairs(old.unmodeled) do self:Log("Equipped unsupported: "..key) end
            end
        end
    end
end
function G:Hook()
    if not TooltipDataProcessor or type(TooltipDataProcessor.AddTooltipPostCall) ~= "function" or not Enum or not Enum.TooltipDataType then
        self.hookStatus="Modern tooltip hook unavailable"; return
    end
    local ok = pcall(TooltipDataProcessor.AddTooltipPostCall,Enum.TooltipDataType.Item,function(tip)
        if G.busy then return end
        G.busy=true
        local worked, err = pcall(G.Append,G,tip)
        G.busy=false
        if not worked then G:Log("Tooltip error: " .. G:Text(err)) end
    end)
    self.hookStatus=ok and "Registered" or "Registration failed"
end
