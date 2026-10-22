local _, B = ...
local H = {}
B:AddModule("HUD", H)
function H:Place()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", B.db.x, B.db.y)
    self.frame:SetScale(B.db.scale)
    self.frame:SetShown(B.db.visible)
    self.frame:EnableMouse(false)
    self.moveHandle:EnableMouse(not B.db.locked)
    self.grip:SetShown(not B.db.locked)
    self.editButton:SetText(B.db.locked and "EDIT" or "DONE")
end
function H:Scale(value)
    B.db.scale = math.max(0.5, math.min(2, value))
    self:Place()
end
function H:SavePosition()
    local cx, cy = self.frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local ratio = self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    B.db.x, B.db.y = cx * ratio - ux, cy * ratio - uy
    self:Place()
end
function H:Init()
    local f = CreateFrame("Frame", "BrutefistCompanionHUD", UIParent)
    self.frame = f
    f:SetSize(320, 88)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\BrutefistCompanion\\Media\\RoundedPanel.tga")
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -9); title:SetText("MAIN HAND")
    title:SetTextColor(1, 0.82, 0.45)
    title:SetShadowOffset(1, -1)
    self.bar = CreateFrame("StatusBar", nil, f)
    self.bar:SetPoint("TOPLEFT", 12, -29); self.bar:SetSize(296, 20)
    self.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    self.bar:SetStatusBarColor(0.38, 0.56, 0.66)
    self.bar:SetMinMaxValues(0, 1)
    local track = self.bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0.09, 0.075, 0.05, 1)
    self.time = self.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.time:SetPoint("CENTER")
    self.time:SetTextColor(1, 0.94, 0.78)
    self.time:SetShadowOffset(1, -1)
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.status:SetPoint("TOPLEFT", 12, -59)
    -- Only dedicated edit controls catch the mouse; combat HUD content stays click-through.
    self.editButton = CreateFrame("Button", nil, f)
    self.editButton:SetSize(44, 20); self.editButton:SetPoint("TOPRIGHT", -7, -4)
    self.editButton:SetNormalFontObject("GameFontNormalSmall")
    self.editButton:SetHighlightFontObject("GameFontHighlightSmall")
    self.editButton:SetScript("OnClick", function()
        if InCombatLockdown() then B:Print("Adjust the HUD after combat."); return end
        B.db.locked = not B.db.locked
        H:Place()
        if not B.db.locked then B:Print("Drag the header to move; drag the bottom-right grip to resize. Click DONE to lock.") end
    end)
    self.moveHandle = CreateFrame("Frame", nil, f)
    self.moveHandle:SetPoint("TOPLEFT"); self.moveHandle:SetPoint("TOPRIGHT", -55, 0)
    self.moveHandle:SetHeight(26); self.moveHandle:RegisterForDrag("LeftButton")
    self.moveHandle:EnableMouseWheel(true)
    self.moveHandle:SetScript("OnDragStart", function()
        if not B.db.locked and not InCombatLockdown() then f:StartMoving() end
    end)
    self.moveHandle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing(); H:SavePosition()
    end)
    self.moveHandle:SetScript("OnMouseWheel", function(_, delta)
        if not B.db.locked and not InCombatLockdown() then H:Scale(B.db.scale + delta * 0.05) end
    end)
    self.grip = CreateFrame("Button", nil, f)
    self.grip:SetSize(20, 20); self.grip:SetPoint("BOTTOMRIGHT", -2, 2)
    self.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    self.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    self.grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or B.db.locked or InCombatLockdown() then return end
        local x, y = GetCursorPosition()
        H.resize = {x = x, y = y, scale = B.db.scale}
    end)
    self.grip:SetScript("OnMouseUp", function() H.resize = nil end)
    self.grip:SetScript("OnHide", function() H.resize = nil end)
    self.grip:SetScript("OnUpdate", function()
        if not H.resize then return end
        if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then H.resize = nil; return end
        local x, y = GetCursorPosition()
        local change = ((x - H.resize.x) - (y - H.resize.y)) / UIParent:GetEffectiveScale()
        H:Scale(H.resize.scale + change / (320 + 88))
    end)
    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.03 then return end
        elapsed = 0
        local left, duration, status = B.modules.Swing:Sample(GetTime())
        if B.demoUntil and GetTime() < B.demoUntil then
            duration = 3.6; left = duration - ((GetTime() - B.demoStart) % duration)
            status = "DEMO ONLY, simulated 3.6 second swing"
        else B.demoUntil = nil end
        H.bar:SetValue(left and left / duration or 0)
        H.time:SetText(left and string.format("%.1fs / %.2fs", left, duration) or "Awaiting swing")
        local demo = B.demoUntil ~= nil
        local soon = left and left > 0 and left <= B.db.warning and (demo or InCombatLockdown())
        if soon then
            H.bar:SetStatusBarColor(1, 0.65, 0.1)
            H.status:SetText(demo and "DEMO: SWING SOON, hold hard casts" or "SWING SOON: hold hard casts")
            H.status:SetTextColor(1, 0.75, 0.2)
        else
            H.bar:SetStatusBarColor(0.38, 0.56, 0.66)
            H.status:SetText(status)
            H.status:SetTextColor(0.72, 0.67, 0.56)
        end
    end)
    self:Place()
end
