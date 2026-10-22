local _, B = ...
local I = {state = "unavailable", detail = "Not sampled", icon = 134400, snapshots = {}}
B:AddModule("Imbue", I)
local function tableReadable(value)
    if B:IsSecret(value) or type(value) ~= "table" then return false end
    if type(issecrettable) == "function" then
        local ok, restricted = pcall(issecrettable, value)
        if not ok or restricted then return false end
    end
    return true
end
function I:ReadModern()
    if not C_Item or type(C_Item.GetWeaponEnchantInfo) ~= "function" then return nil, "Modern API absent" end
    local slot = Enum and Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0
    local ok, entries = pcall(C_Item.GetWeaponEnchantInfo, slot)
    if not ok then return nil, "Modern API call failed" end
    if not tableReadable(entries) then return nil, "Modern data unavailable" end
    local imbueType = Enum and Enum.ItemEnchantType and Enum.ItemEnchantType.Imbue or 3
    local unknown = false
    for _, entry in ipairs(entries) do
        if not tableReadable(entry) then unknown = true
        else
            local kind = B:Number(entry.enchantType)
            if not kind then unknown = true
            elseif kind == imbueType then
                if B:IsSecret(entry.hasEnchant) or type(entry.hasEnchant) ~= "boolean" then
                    unknown = true
                elseif entry.hasEnchant then
                    return {state = "active", id = B:Number(entry.enchantID), icon = B:Number(entry.enchantIconID),
                        rawTime = B:Number(entry.timeLeft)}, "Modern imbue entry"
                end
            end
        end
    end
    if unknown then return nil, "Modern fields unavailable" end
    return {state = "missing"}, "Modern API: no active imbue"
end
function I:ReadLegacy()
    if type(GetWeaponEnchantInfo) ~= "function" then return nil, "Legacy API absent" end
    local ok, has, remaining, charges, id = pcall(GetWeaponEnchantInfo)
    if not ok then return nil, "Legacy API call failed" end
    if B:IsSecret(has) or type(has) ~= "boolean" then return nil, "Legacy fields unavailable" end
    if not has then return {state = "missing"}, "Legacy API: no temporary enchant" end
    local ms = B:Number(remaining)
    return {state = "active", id = B:Number(id), seconds = ms and ms > 0 and ms / 1000 or nil},
        "Legacy temporary enchant (type unverified)"
end
function I:Refresh()
    local modern, modernDetail = self:ReadModern()
    local legacy, legacyDetail = self:ReadLegacy()
    self.modernDetail, self.legacyDetail = modernDetail, legacyDetail
    self.rawModernTime = modern and modern.rawTime or nil
    self.legacySeconds = legacy and legacy.seconds or nil
    local value, detail = modern, modernDetail
    -- An unavailable modern result must not become a false 'missing' claim.
    if not value and modernDetail == "Modern API absent" then value, detail = legacy, legacyDetail end
    self.state, self.detail = value and value.state or "unavailable", detail
    self.id, self.icon, self.expires = value and value.id or nil, value and value.icon or 134400, nil
    if value and value.state == "active" then
        local seconds = value.seconds
        -- Build 70338 live capture: Windfury 283 refreshes to 3600000, confirmed 60 minutes.
        if modern and modern.rawTime and modern.rawTime > 0 then
            seconds = modern.rawTime / 1000
        end
        -- Legacy timing is only a fallback for the same enchant.
        if not seconds and modern and legacy and legacy.state == "active" and modern.id and legacy.id == modern.id then
            seconds = legacy.seconds
        end
        if seconds then self.expires = GetTime() + seconds end
    end
    local signature = self.state .. "|" .. (self.id or "unknown") .. "|" .. self.detail
    if signature ~= self.lastSignature then
        self.lastSignature = signature
        local text = "IMBUE " .. signature .. " modernTimeRaw=" .. B:Plain(self.rawModernTime)
            .. " legacySeconds=" .. B:Plain(self.legacySeconds)
        self.snapshots[#self.snapshots+1] = text
        if #self.snapshots > 12 then table.remove(self.snapshots, 1) end
        local d = B.modules.Diagnostics
        if d and d.recording then d:Log(text) end
    end
end
function I:Update(dt)
    self.elapsed = (self.elapsed or 0) + dt
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    local ok = pcall(self.Refresh, self)
    if not ok then
        self.state, self.detail, self.expires, self.id, self.icon = "unavailable", "Imbue read failed", nil, nil, 134400
    end
end
function I:Display()
    if self.state == "missing" then
        if InCombatLockdown() then return "Weapon imbue: none detected", 0.65, 0.65, 0.65 end
        return "Missing weapon imbue", 1, 0.65, 0.15
    end
    if self.state ~= "active" then return "Weapon imbue: unavailable", 0.65, 0.65, 0.65 end
    local label = self.detail:find("Legacy") and "Weapon enchant active" or "Weapon imbue active"
    if self.id == 283 and self.detail == "Modern imbue entry" then label = "Windfury Weapon" end
    if self.expires then
        local seconds = math.max(0, math.ceil(self.expires - GetTime()))
        if seconds == 0 then return label .. " (refreshing)", 0.4, 0.85, 0.65 end
        label = label .. string.format("  %d:%02d", math.floor(seconds/60), seconds%60)
    end
    return label, 0.4, 0.85, 0.65
end
function I:Init()
    B:On("UNIT_INVENTORY_CHANGED", function(unit)
        if not B:IsSecret(unit) and unit == "player" then self.elapsed = 0.5 end
    end)
    B:On("PLAYER_ENTERING_WORLD", function() self.elapsed = 0.5 end)
    self:Update(0.5)
    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnUpdate", function(_, dt) self:Update(dt) end)
end
