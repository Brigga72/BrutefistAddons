local _, B = ...
local L = {state = "unavailable", detail = "Not sampled", icon = 136051, snapshots = {}}
B:AddModule("Shield", L)
local ranks = {[324]=true, [325]=true, [905]=true, [945]=true, [8134]=true, [10431]=true, [10432]=true}
local function readableTable(value)
    if B:IsSecret(value) or type(value) ~= "table" then return false end
    if type(issecrettable) == "function" then
        local ok, restricted = pcall(issecrettable, value)
        if not ok or restricted then return false end
    end
    return true
end
function L:Read()
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then
        return "unavailable", "Aura API absent"
    end
    local unknown = false
    for index = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if not ok then return "unavailable", "Aura API call failed" end
        if B:IsSecret(aura) then return "unavailable", "Aura result restricted" end
        if aura == nil then
            if unknown then return "unavailable", "Some aura identities unavailable" end
            return "missing", "Complete readable aura scan"
        end
        if not readableTable(aura) then unknown = true
        else
            local id = B:Number(aura.spellId)
            local name
            if not B:IsSecret(aura.name) and type(aura.name) == "string" then name = aura.name end
            if (id and ranks[id]) or (name and self.localizedName and name == self.localizedName) then
                local charges = B:Number(aura.applications)
                if charges and (charges < 1 or charges ~= math.floor(charges)) then charges = nil end
                return "active", charges and "Readable shield and charges" or "Shield active, charges unavailable",
                    id, charges, B:Number(aura.icon)
            end
            -- A readable different ID is enough to exclude this aura.
            if not id and not (name and self.localizedName) then unknown = true end
        end
    end
    return "unavailable", "Aura scan limit reached"
end
function L:Refresh()
    self.state, self.detail, self.id, self.charges, self.icon = self:Read()
    self.icon = self.icon or 136051
    local signature = self.state .. "|" .. self.detail .. "|id=" .. B:Plain(self.id) .. "|charges=" .. B:Plain(self.charges)
    if signature ~= self.lastSignature then
        self.lastSignature = signature
        self.snapshots[#self.snapshots+1] = "SHIELD " .. signature
        if #self.snapshots > 12 then table.remove(self.snapshots, 1) end
        local d = B.modules.Diagnostics
        if d and d.recording then d:Log("SHIELD " .. signature) end
    end
end
function L:Update(dt)
    self.elapsed = (self.elapsed or 0) + dt
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    local ok = pcall(self.Refresh, self)
    if not ok then
        self.state, self.detail, self.id, self.charges, self.icon = "unavailable", "Shield read failed", nil, nil, 136051
    end
end
function L:Display()
    if self.state == "missing" then
        if InCombatLockdown() then return "Lightning Shield: not detected", 0.65, 0.65, 0.65 end
        return "Missing Lightning Shield", 1, 0.65, 0.15
    end
    if self.state ~= "active" then return "Lightning Shield: unavailable", 0.65, 0.65, 0.65 end
    if self.charges then return "Lightning Shield  " .. self.charges .. " charges", 0.4, 0.85, 0.65 end
    return "Lightning Shield  charges unavailable", 0.4, 0.85, 0.65
end
function L:Init()
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, 324)
        if ok and not B:IsSecret(name) and type(name) == "string" then self.localizedName = name end
    end
    B:On("UNIT_AURA", function(unit)
        if not B:IsSecret(unit) and unit == "player" then self.elapsed = 0.5 end
    end)
    B:On("PLAYER_ENTERING_WORLD", function() self.elapsed = 0.5 end)
    self:Update(0.5)
    self.frame = CreateFrame("Frame")
    self.frame:SetScript("OnUpdate", function(_, dt) self:Update(dt) end)
end
