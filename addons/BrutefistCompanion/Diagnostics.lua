local _, B = ...
local D = {lines = {}, recording = false, total = 0}
B:AddModule("Diagnostics", D)
function D:Log(text)
    self.total = self.total + 1
    table.insert(self.lines, string.format("%.3f %s", GetTime(), text))
    if #self.lines > 200 then table.remove(self.lines, 1) end
end
function D:Capture(event, ...)
    if not self.recording then return end
    local fields = {event}
    for i = 1, select("#", ...) do fields[#fields + 1] = B:Plain(select(i, ...)) end
    self:Log(table.concat(fields, " | "))
end
function D:Report()
    local version, build, date, interface = GetBuildInfo()
    local lines = {"Brutefist Companion " .. B.version,
        "Client: " .. B:Plain(version) .. " build " .. B:Plain(build) .. " interface " .. B:Plain(interface),
        "Secret guard: " .. tostring(type(issecretvalue) == "function"),
        "Access guard: " .. tostring(type(canaccessvalue) == "function"),
        "Main-hand accepted: " .. B.modules.Swing.count .. " rejected payloads: " .. B.modules.Swing.rejected,
        "Status: " .. B.modules.Swing.state,
        "Recording: " .. tostring(self.recording) .. "; retained " .. #self.lines .. "/200; total " .. self.total}
    local keys = {}
    for event in pairs(B.capabilities) do keys[#keys+1] = event end
    table.sort(keys)
    for _, event in ipairs(keys) do lines[#lines+1] = event .. " registration: " .. tostring(B.capabilities[event]) end
    if type(UnitAttackSpeed) == "function" then
        local ok, speed = pcall(UnitAttackSpeed, "player")
        lines[#lines+1] = "UnitAttackSpeed (diagnostic only): " .. (ok and B:Plain(speed) or "call failed")
    end
    lines[#lines+1] = string.format("Swing warning threshold: %.2f seconds", B.db.warning)
    lines[#lines+1] = "--- Event history ---"
    for _, line in ipairs(self.lines) do lines[#lines+1] = line end
    return table.concat(lines, "\n")
end
function D:Show()
    if InCombatLockdown() then B:Print("Open diagnostics after combat."); return end
    if not self.window then
        local f = CreateFrame("Frame", nil, UIParent)
        self.window = f
        f:SetSize(650, 420); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.02, 0.02, 0.03, 0.98)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 16, -16); title:SetText("Diagnostics: Ctrl+A, Ctrl+C to copy")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT")
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -45); scroll:SetPoint("BOTTOMRIGHT", -35, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(595); edit:SetHeight(340)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit); self.edit = edit
    end
    self.edit:SetText(self:Report()); self.window:Show(); self.edit:SetFocus(); self.edit:HighlightText()
end
function D:Init()
    for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_SWING_RANGE_UPDATE", "UNIT_ATTACK_SPEED", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED"}) do
        B:On(event, function() end)
    end
    B:On("PLAYER_REGEN_DISABLED", function() B.demoUntil = nil end)
end
