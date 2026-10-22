local _, G = ...
G.version = "0.6.1"
G.history = {}
G.defaults = {strengthAP = 2, intellectBonus = 0.04, intellectAP = 1, intellectSP = 0.3,
    apWeight = 1, spellWeight = 0.3, agilityWeight = 1, meleeShare = 0.85, flurryHaste = 0.25,
    apPerDPS = 14, spellBase = 100, spellCoefficient = 0.4,
    windfuryChance=0.20, windfuryAP=104, windfuryICD=0,
    stormstrikeInterval=8, weaponNormalization=3.3}
function G:Secret(v)
    if type(issecretvalue) == "function" then
        local ok, s = pcall(issecretvalue, v)
        if not ok or s then return true end
    end
    if type(canaccessvalue) == "function" then
        local ok, access = pcall(canaccessvalue, v)
        if not ok or not access then return true end
    end
    return false
end
function G:Number(v)
    if self:Secret(v) or type(v) ~= "number" then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
function G:Text(v)
    if self:Secret(v) then return "<restricted>" end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    return "<" .. t .. ">"
end
function G:Table(v)
    if self:Secret(v) or type(v) ~= "table" then return false end
    if type(issecrettable) == "function" then
        local ok, s = pcall(issecrettable, v)
        if not ok or s then return false end
    end
    return true
end
function G:Print(v) DEFAULT_CHAT_FRAME:AddMessage("|cffffcf77Gear Advisor:|r " .. v) end
function G:Log(v)
    for _, previous in ipairs(self.history) do
        if previous == v then
            self.duplicates = (self.duplicates or 0) + 1
            return
        end
    end
    self.history[#self.history+1] = v
    if #self.history > 40 then table.remove(self.history, 1) end
end
function G:Score(s)
    local p = self:Profile()
    local intellect = (s.int or 0) * (1 + p.intellectBonus)
    local ap = (s.ap or 0) + (s.str or 0) * p.strengthAP + intellect * p.intellectAP
    local sp = (s.sp or 0) + intellect * p.intellectSP
    return ap * p.apWeight + sp * p.spellWeight + (s.agi or 0) * p.agilityWeight, ap, sp
end
function G:Delta(a, b)
    local sa, aa, pa = self:Score(a)
    local sb, ab, pb = self:Score(b)
    return sa - sb, aa - ab, pa - pb
end
