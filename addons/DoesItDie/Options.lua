-- DoesItDie options window (/did).
--
-- Left: a live preview. The addon's real marker and kill icon are attached to a mock target frame here (see
-- ns.setDisplayHost in DoesItDie.lua) and fed plain numbers from the preview sliders, so the preview runs the
-- same drawing code as combat. Right: tabbed settings. Top: presets.
--
-- Controls are built from basic widgets (CheckButton, Slider, Button) rather than Blizzard templates, so they
-- don't depend on templates behaving the same in Forever. Settings are written straight to ns.db.

local ADDON_NAME, ns = ...
local T = ns.locale.T -- the window's text in the window language (Locale.lua)

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- Tall enough for the longest tabs (Nameplates, Focus: 15 rows); wide enough for the seven tab names in a row.
local WINDOW_WIDTH, WINDOW_HEIGHT = 800, 548
local HEADER_HEIGHT = 52 -- title bar: title, presets, close button
local PREVIEW_WIDTH = 290
local ROW_HEIGHT = 26
local SETTINGS_LAYOUT = { label = 170, control = 200 }
local PREVIEW_LAYOUT = { label = 92, control = 140 }
local DISABLED_ALPHA = 0.35
local SIMULATION_STEP = 0.5 -- seconds

-- Presets only set appearance; accuracy and troubleshooting settings are left alone.
local PRESETS = {
    { id = "minimal", label = "Minimal", values = {
        showSkull = true, skullIcon = "cross", skullSize = 40, skullPulse = false,
        showMarkers = true, fillTexture = "flat", fillColor = "purple", fillOpacity = 35, dotColors = "single",
        outlineStyle = "solid", outlineThickness = 1, outlineColor = "purple", outlineOpacity = 100,
        smoothMotion = true, flashOnApply = false, pulseOutline = false,
        showSpark = false, showGlow = false, showShine = false, scrollStripes = false, showLabel = false,
    } },
    { id = "classic", label = "Classic", values = {
        showSkull = true, skullIcon = "skull", skullSize = 48, skullPulse = true,
        showMarkers = true, fillTexture = "smooth", fillColor = "red", fillOpacity = 60, dotColors = "single",
        outlineStyle = "dashed", dashLength = 4, outlineThickness = 2, outlineColor = "gold", outlineOpacity = 100,
        smoothMotion = true, flashOnApply = true, pulseOutline = false,
        showSpark = true, showGlow = false, showShine = false, scrollStripes = false, showLabel = false,
    } },
    { id = "juicy", label = "Juicy", values = {
        showSkull = true, skullIcon = "shades", skullSize = 64, skullPulse = true,
        showMarkers = true, fillTexture = "stripes", fillColor = "red", fillOpacity = 100, dotColors = "each",
        segmentDividers = true, outlineStyle = "dashed", dashLength = 4, outlineThickness = 1, outlineColor = "red",
        outlineOpacity = 85, smoothMotion = true, flashOnApply = true, pulseOutline = true,
        showSpark = true, showGlow = true, glowSize = 7, showShine = true, shineInterval = 3, scrollStripes = true,
        showLabel = false,
    } },
    { id = "debug", label = "Debug", values = {
        showSkull = true, skullIcon = "cross", skullPulse = false,
        showMarkers = true, fillTexture = "flat", fillOpacity = 60, dotColors = "school", segmentDividers = true,
        outlineStyle = "solid", outlineThickness = 1, outlineColor = "white", outlineOpacity = 100,
        smoothMotion = false, flashOnApply = true, pulseOutline = false,
        showSpark = false, showGlow = false, showShine = false, scrollStripes = false,
        showLabel = true, labelPosition = "left", labelSize = 10, labelColor = "white",
    } },
}

local window
local controls = {} -- every settings/preview row, refreshed after each change
local tabs, activeTab = {}, nil
local menu -- shared dropdown list
local simulation

-- Preview numbers, in % of the mock target's max health.
local preview = {
    health = 60,
    dots = {
        { name = "Corruption", school = 32, damage = 27, tick = 4 },
        { name = "Immolate", school = 4, damage = 18, tick = 5 },
    },
}

local function db() return ns.db end

local function findEntry(list, id)
    for _, entry in ipairs(list) do
        if entry.id == id then return entry end
    end
end

local function setBackdrop(frame, shade, alpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(shade, shade, shade, alpha or 1)
    frame:SetBackdropBorderColor(0.28, 0.28, 0.3, 1)
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------

local function previewTotal()
    local total = 0
    for _, dot in ipairs(preview.dots) do total = total + dot.damage end
    return total
end

-- Splits a total over the two sample DoTs (60/40).
local function setPreviewDamage(total)
    preview.dots[1].damage = total * 0.6
    preview.dots[2].damage = total * 0.4
end

local function refreshControls()
    for _, control in ipairs(controls) do control:Refresh() end
end

local function inCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

-- The preview only takes over the display out of combat: in combat the real target comes first, even with the
-- window open (settings changes still apply to it live).
local function syncDisplayHost()
    if not window or not window:IsShown() then return end
    local paused = inCombat() and true or false
    window.combatNote:SetShown(paused)
    window.mock:SetAlpha(paused and 0.3 or 1)
    window.mockPlate:SetAlpha(paused and 0.3 or 1)
    window.mockFocus:SetAlpha(paused and 0.3 or 1)
    window.simulateButton:SetEnabled(not paused)
    window.flashButton:SetEnabled(not paused)
    if paused ~= window.previewPaused then
        window.previewPaused = paused
        if paused and simulation then
            simulation:Cancel()
            simulation = nil
            window.simulateButton:SetText(T("Simulate fight"))
        end
        ns.setDisplayHost((not paused) and window.host or nil)
        ns.setPlatePreview((not paused) and window.plateHost or nil, preview)
        ns.setFocusPreview((not paused) and window.focusHost or nil, preview)
    end
end

local function updatePreview()
    if not window then return end
    window.healthBar:SetValue(preview.health)
    window.plateHealthBar:SetValue(preview.health)
    window.focusHealthBar:SetValue(preview.health)
    local total = previewTotal()
    if total <= 0 then
        window.status:SetText(T("No DoTs on the target"))
    elseif total >= preview.health then
        window.status:SetText("|cff66ff66" .. T("DoTs finish it: the kill icon shows") .. "|r")
    else
        window.status:SetText(string.format(T("Survives by %d%% of its health"), math.floor(preview.health - total + 0.5)))
    end
    ns.refresh()
end

local function stopSimulation()
    if simulation then
        simulation:Cancel()
        simulation = nil
    end
    if window then window.simulateButton:SetText(T("Simulate fight")) end
end

-- A scripted fight: a DoT lands, ticks, a second DoT lands and makes it lethal, ticks until the target dies.
local function startSimulation()
    stopSimulation()
    preview.health = 80
    setPreviewDamage(0)
    local step = 0
    simulation = C_Timer.NewTicker(SIMULATION_STEP, function()
        step = step + 1
        if step == 1 then
            preview.dots[1].damage = 32
            ns.playFlash()
        elseif step == 5 then
            preview.dots[2].damage = 50
            ns.playFlash()
        else
            local dealt = 0
            for _, dot in ipairs(preview.dots) do
                local tick = math.min(dot.damage, dot.tick)
                dot.damage = dot.damage - tick
                dealt = dealt + tick
            end
            preview.health = math.max(0, preview.health - dealt)
        end
        updatePreview()
        refreshControls()
        if preview.health <= 0 or (step > 5 and previewTotal() <= 0) then stopSimulation() end
    end)
    window.simulateButton:SetText(T("Stop"))
    updatePreview()
    refreshControls()
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function changed()
    ns.reattach() -- refreshes; re-attaches only if a custom frame setting changed what to attach to
    refreshControls()
end

local function makeRow(parent, labelText, opts)
    local layout = opts.layout or SETTINGS_LAYOUT
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(layout.label + layout.control + 50, ROW_HEIGHT)
    row.layout = layout
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetWidth(layout.label - 8)
    row.label:SetJustifyH("LEFT")
    labelText = T(labelText)
    local tooltip = opts.tooltip and T(opts.tooltip)
    row.label:SetText(labelText)
    row.enabledIf = opts.enabledIf
    if tooltip then
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    function row:ApplyEnabled(widget)
        local enabled = not self.enabledIf or self.enabledIf(db())
        self:SetAlpha(enabled and 1 or DISABLED_ALPHA)
        widget:EnableMouse(enabled)
        if widget.EnableMouseWheel then widget:EnableMouseWheel(enabled) end
    end
    table.insert(controls, row)
    return row
end

local function checkbox(parent, key, labelText, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local box = CreateFrame("CheckButton", nil, row)
    box:SetSize(24, 24)
    box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box:SetScript("OnClick", function(self)
        db()[key] = self:GetChecked() and true or false
        changed()
    end)
    function row:Refresh()
        box:SetChecked(db()[key] and true or false)
        self:ApplyEnabled(box)
    end
    return row
end

-- get/set work on any value (settings or preview numbers).
local function sliderRow(parent, labelText, min, max, step, get, set, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(row.layout.control - 44, 18)
    slider:SetPoint("LEFT", row, "LEFT", row.layout.label + 2, 0)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0.3, 0.3, 0.32, 1)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(18, 24)
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    local suffix = opts.suffix or ""
    local updating = false
    slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        value = math.floor(value / step + 0.5) * step
        valueText:SetText(value .. suffix)
        set(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * step) end)
    function row:Refresh()
        updating = true
        local value = get()
        slider:SetValue(value)
        valueText:SetText(math.floor(value / step + 0.5) * step .. suffix)
        updating = false
        self:ApplyEnabled(slider)
    end
    return row
end

local function slider(parent, key, labelText, min, max, step, opts)
    return sliderRow(parent, labelText, min, max, step,
        function() return db()[key] end,
        function(value)
            db()[key] = value
            changed()
        end, opts)
end

local function closeMenu()
    if menu then menu:Hide() end
end

-- Shared dropdown list under `owner`; entries may carry an rgb swatch.
local function openMenu(owner, list, current, pick)
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:EnableMouse(true)
        setBackdrop(menu, 0.08, 0.98)
        menu.buttons = {}
        -- Close on a click anywhere else (event may not exist on every client; clicking the owner toggles too).
        pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
        menu:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
        end)
    end
    if menu:IsShown() and menu.owner == owner then return menu:Hide() end
    menu.owner = owner
    for i, entry in ipairs(list) do
        local button = menu.buttons[i]
        if not button then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(20)
            local highlight = button:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.1)
            button.swatch = button:CreateTexture(nil, "ARTWORK")
            button.swatch:SetSize(12, 12)
            button.swatch:SetPoint("LEFT", 8, 0)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetJustifyH("LEFT")
            menu.buttons[i] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (i - 1) * 20)
        button:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
        button.swatch:SetShown(entry.rgb ~= nil)
        if entry.rgb then button.swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
        button.text:ClearAllPoints()
        button.text:SetPoint("LEFT", entry.rgb and 26 or 8, 0)
        button.text:SetText(entry.id == current and ("|cffffd100" .. T(entry.label) .. "|r") or T(entry.label))
        button:SetScript("OnClick", function()
            menu:Hide()
            pick(entry.id)
        end)
        button:Show()
    end
    for i = #list + 1, #menu.buttons do menu.buttons[i]:Hide() end
    menu:SetSize(owner:GetWidth(), #list * 20 + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

local function choice(parent, key, labelText, list, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    for _, entry in ipairs(list) do T(entry.label) end -- (so --dump-strings lists every entry)
    local button = CreateFrame("Button", nil, row, "BackdropTemplate")
    button:SetSize(row.layout.control, 22)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    setBackdrop(button, 0.13)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    local swatch = button:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(12, 12)
    swatch:SetPoint("LEFT", 8, 0)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetPoint("RIGHT", -20, 0)
    local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    button:SetScript("OnClick", function(self)
        openMenu(self, list, db()[key], function(id)
            db()[key] = id
            changed()
            if opts.onChange then opts.onChange(id) end
        end)
    end)
    function row:Refresh()
        local entry = findEntry(list, db()[key])
        text:SetText(entry and T(entry.label) or tostring(db()[key]))
        swatch:SetShown(entry ~= nil and entry.rgb ~= nil)
        if entry and entry.rgb then swatch:SetColorTexture(entry.rgb[1], entry.rgb[2], entry.rgb[3], 1) end
        text:ClearAllPoints()
        text:SetPoint("LEFT", (entry and entry.rgb) and 26 or 8, 0)
        text:SetPoint("RIGHT", -20, 0)
        self:ApplyEnabled(button)
    end
    return row
end

local function pushButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(T(text))
    button:SetScript("OnClick", onClick)
    return button
end

-- A frame path setting (Frames.lua): a text box (saved on Enter or leaving it) and a Pick button that takes the
-- next click on screen.
local function frameRow(parent, key, labelText, kind, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    box:SetSize(row.layout.control - (opts.noPick and 0 or 58), 22)
    box:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    setBackdrop(box, 0.13)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    box:SetAutoFocus(false)
    local function save(value)
        db()[key] = strtrim(value or "")
        changed()
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(db()[key])
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        if strtrim(self:GetText() or "") ~= db()[key] then save(self:GetText()) end
    end)
    local pick = (not opts.noPick) and pushButton(row, "Pick", 52, function()
        ns.print(kind == "bar"
            and T("Click your target's health bar (you may need to move this window). Right-click cancels.")
            or T("Click where the kill icon should go (you may need to move this window). Right-click cancels."))
        ns.startFramePick(kind, function(path)
            box:SetText(path)
            save(path)
            ns.print(string.format(T("Picked %s."), path))
        end)
    end)
    if pick then pick:SetPoint("LEFT", box, "RIGHT", 6, 0) end
    function row:Refresh()
        if not box:HasFocus() then box:SetText(db()[key] or "") end
        self:ApplyEnabled(box)
    end
    return row
end

-- A line of text in the settings column, from getText().
local function infoRow(parent, labelText, getText, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    text:SetWidth(row.layout.control + 40)
    text:SetJustifyH("LEFT")
    function row:Refresh() text:SetText(getText()) end
    return row
end

local function actionRow(parent, labelText, buttonText, onClick, opts)
    opts = opts or {}
    local row = makeRow(parent, labelText, opts)
    local button = pushButton(row, buttonText, 90, onClick)
    button:SetPoint("LEFT", row, "LEFT", row.layout.label, 0)
    row.button = button
    function row:Refresh() self:ApplyEnabled(button) end
    return row
end

---------------------------------------------------------------------------
-- Learned tick sizes viewer (Advanced tab > View): one row per learned tick size, with the spell's icon, name
-- and rank (hover for its tooltip, shift-click to link it), what its description predicts per tick, and the
-- difference: the spell power or attack power the description leaves out.
---------------------------------------------------------------------------

local TICKS_ROW_HEIGHT, TICKS_VISIBLE_ROWS = 32, 11
-- Column x positions and widths in a row; numbers are right-aligned in theirs.
local TICKS_COLUMNS = {
    spell = { 44, 212 }, combo = { 258, 48 }, learned = { 310, 66 }, tooltip = { 380, 66 }, bonus = { 450, 58 },
    total = { 512, 70 },
}
local SPELL_LINK_COLOR = { 0.44, 0.84, 1 }
local tickViewer

local function formatTick(value)
    if not value then return "-" end
    if value == math.floor(value) then return string.format("%d", value) end
    return string.format("%.1f", value)
end

local function spellCall(fnName, spellID)
    local fn = C_Spell and C_Spell[fnName]
    if not fn then return nil end
    local ok, value = pcall(fn, spellID)
    if ok and (type(value) == "string" or type(value) == "number") then return value end
end

local function spellLink(spellID)
    local link = spellCall("GetSpellLink", spellID)
    if not link and GetSpellLink then
        local ok, value = pcall(GetSpellLink, spellID)
        link = ok and value or nil
    end
    return link
end

local function showTickTooltip(row)
    local entry = row.entry
    if not entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local shown = GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, entry.spellID)
    if not shown then GameTooltip:SetText(entry.name or (T("Spell") .. " " .. entry.spellID), 1, 1, 1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("DoesItDie", 1, 0.82, 0)
    if entry.comboPoints then
        GameTooltip:AddDoubleLine(T("Combo points"), entry.comboPoints, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(T("Learned per tick"), formatTick(entry.perTick), 0.8, 0.8, 0.8, 1, 1, 1)
    if entry.tooltipPerTick then
        GameTooltip:AddDoubleLine(T("Tooltip per tick"), formatTick(entry.tooltipPerTick), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(T("Ticks"), string.format(T("%d, every %gs (%gs)"), entry.ticks, entry.interval,
            entry.duration), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(T("Full duration"), formatTick(entry.perTick * entry.ticks), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(T("Learned from this spell's ticks on your targets; used instead of the tooltip's number, "
        .. "which leaves out spell power and attack power."), 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine(T("Shift-click to link it in chat."), 0.5, 0.8, 1)
    GameTooltip:Show()
end

local function createTickRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(TICKS_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, index % 2 == 0 and 0.035 or 0)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    -- The spell's school color, as on the marker with "Color by school".
    row.school = row:CreateTexture(nil, "ARTWORK")
    row.school:SetSize(3, TICKS_ROW_HEIGHT - 8)
    row.school:SetPoint("LEFT", 2, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 12, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", TICKS_COLUMNS.spell[1], -3)
    row.name:SetWidth(TICKS_COLUMNS.spell[2])
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.rank:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.rank:SetWidth(TICKS_COLUMNS.spell[2])
    row.rank:SetJustifyH("LEFT")
    row.cells = {}
    for _, column in ipairs({ "combo", "learned", "tooltip", "bonus", "total" }) do
        local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cell:SetPoint("LEFT", row, "LEFT", TICKS_COLUMNS[column][1], 0)
        cell:SetWidth(TICKS_COLUMNS[column][2])
        cell:SetJustifyH(column == "combo" and "CENTER" or "RIGHT")
        row.cells[column] = cell
    end

    local forget = CreateFrame("Button", nil, row)
    forget:SetSize(20, 20)
    forget:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    forget.text = forget:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    forget.text:SetPoint("CENTER")
    forget.text:SetText("x")
    forget.text:SetTextColor(0.6, 0.6, 0.6)
    local forgetHighlight = forget:CreateTexture(nil, "HIGHLIGHT")
    forgetHighlight:SetAllPoints()
    forgetHighlight:SetColorTexture(1, 0.3, 0.3, 0.25)
    forget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("Forget this tick size"), 1, 1, 1)
        GameTooltip:AddLine(T("The next cast starts from the tooltip again and learns it anew."), nil, nil, nil, true)
        GameTooltip:Show()
    end)
    forget:SetScript("OnLeave", function() GameTooltip:Hide() end)
    forget:SetScript("OnClick", function()
        if not row.entry then return end
        ns.forgetLearnedTick(row.entry.key)
        tickViewer:Refresh()
    end)

    row:SetScript("OnEnter", showTickTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if not (self.entry and IsShiftKeyDown and IsShiftKeyDown()) then return end
        local link = spellLink(self.entry.spellID)
        if link and not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then
            ChatFrame_OpenChat(link)
        end
    end)
    return row
end

local function fillTickRow(row, entry)
    row.entry = entry
    local color = entry.color or { 0.5, 0.5, 0.5 }
    row.school:SetColorTexture(color[1], color[2], color[3], 1)
    row.icon:SetTexture(spellCall("GetSpellTexture", entry.spellID) or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(entry.name or (T("Spell") .. " " .. entry.spellID))
    row.name:SetTextColor(SPELL_LINK_COLOR[1], SPELL_LINK_COLOR[2], SPELL_LINK_COLOR[3])
    local rank = spellCall("GetSpellSubtext", entry.spellID)
    row.rank:SetText(rank and rank ~= "" and rank or ("ID " .. entry.spellID))
    row.cells.combo:SetText(entry.comboPoints or "")
    row.cells.learned:SetText(formatTick(entry.perTick))
    row.cells.tooltip:SetText(entry.tooltipPerTick and formatTick(entry.tooltipPerTick) or "-")
    local bonus = entry.tooltipPerTick and entry.tooltipPerTick > 0
        and math.floor((entry.perTick / entry.tooltipPerTick - 1) * 100 + 0.5)
    if bonus then
        row.cells.bonus:SetText(string.format("%+d%%", bonus))
        if bonus > 0 then
            row.cells.bonus:SetTextColor(0.4, 1, 0.4)
        elseif bonus < 0 then
            row.cells.bonus:SetTextColor(1, 0.45, 0.45)
        else
            row.cells.bonus:SetTextColor(0.7, 0.7, 0.7)
        end
    else
        row.cells.bonus:SetText("-")
        row.cells.bonus:SetTextColor(0.7, 0.7, 0.7)
    end
    row.cells.total:SetText(entry.ticks and formatTick(entry.perTick * entry.ticks) or "-")
    row:Show()
end

local function createTickViewer()
    local width = TICKS_COLUMNS.total[1] + TICKS_COLUMNS.total[2] + 56
    local viewer = CreateFrame("Frame", "DoesItDieLearnedTicks", UIParent, "BackdropTemplate")
    viewer:Hide()
    viewer:SetSize(width, 112 + TICKS_VISIBLE_ROWS * TICKS_ROW_HEIGHT + 44)
    viewer:SetFrameStrata("DIALOG")
    viewer:SetToplevel(true)
    viewer:SetClampedToScreen(true)
    viewer:EnableMouse(true)
    viewer:SetMovable(true)
    viewer:RegisterForDrag("LeftButton")
    viewer:SetScript("OnDragStart", viewer.StartMoving)
    viewer:SetScript("OnDragStop", viewer.StopMovingOrSizing)
    setBackdrop(viewer, 0.06, 0.97)
    table.insert(UISpecialFrames, "DoesItDieLearnedTicks") -- Escape closes it

    local title = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(T("Learned tick sizes"))
    local close = CreateFrame("Button", nil, viewer, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -10)
    local intro = viewer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetWidth(width - 32)
    intro:SetJustifyH("LEFT")
    intro:SetText(T("What each DoT really ticks for, learned from your casts and used instead of its tooltip. "
        .. "Tooltips leave out spell power and attack power: Bonus is how much more yours do. "
        .. "Hover a spell for details, shift-click to link it."))

    local list = CreateFrame("Frame", nil, viewer, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 10, -100)
    list:SetPoint("TOPRIGHT", -10, -100)
    list:SetHeight(TICKS_VISIBLE_ROWS * TICKS_ROW_HEIGHT + 2)
    setBackdrop(list, 0.09)
    list:EnableMouseWheel(true)

    local headers = { spell = "Spell", combo = "Combo", learned = "Per tick", tooltip = "Tooltip", bonus = "Bonus",
        total = "Total" }
    for column, text in pairs(headers) do
        local header = viewer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("BOTTOMLEFT", list, "TOPLEFT", TICKS_COLUMNS[column][1], 4)
        header:SetWidth(TICKS_COLUMNS[column][2])
        header:SetJustifyH(column == "spell" and "LEFT" or column == "combo" and "CENTER" or "RIGHT")
        header:SetText(T(text))
    end

    viewer.rows = {}
    for i = 1, TICKS_VISIBLE_ROWS do
        viewer.rows[i] = createTickRow(list, i)
        viewer.rows[i]:SetPoint("TOPLEFT", list, "TOPLEFT", 1, -1 - (i - 1) * TICKS_ROW_HEIGHT)
        viewer.rows[i]:SetPoint("RIGHT", list, "RIGHT", -1, 0)
    end
    local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetWidth(width - 80)
    empty:SetText(T("Nothing learned yet. Tick sizes are learned as your DoTs tick on your targets."))

    local count = viewer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    count:SetPoint("BOTTOMLEFT", 16, 18)
    local forgetAll = pushButton(viewer, "Forget all", 100, function()
        ns.resetLearnedTicks()
        viewer:Refresh()
    end)
    forgetAll:SetPoint("BOTTOMRIGHT", -12, 12)

    viewer.offset = 0
    function viewer:Refresh()
        local entries = ns.learnedTickList()
        local maxOffset = math.max(0, #entries - TICKS_VISIBLE_ROWS)
        self.offset = math.max(0, math.min(self.offset, maxOffset))
        for i, row in ipairs(self.rows) do
            local entry = entries[self.offset + i]
            if entry then fillTickRow(row, entry) else row.entry = nil; row:Hide() end
        end
        empty:SetShown(#entries == 0)
        local scrolled = maxOffset > 0 and ("  " .. string.format(T("(%d-%d shown; scroll for more)"),
            self.offset + 1, math.min(#entries, self.offset + TICKS_VISIBLE_ROWS))) or ""
        local counted = #entries == 1 and T("1 learned tick size")
            or string.format(T("%d learned tick sizes"), #entries)
        count:SetText(counted .. scrolled)
        forgetAll:SetEnabled(#entries > 0)
    end
    list:SetScript("OnMouseWheel", function(_, delta)
        viewer.offset = viewer.offset - delta
        viewer:Refresh()
    end)
    -- New ticks are learned while it's open (in combat): keep it current.
    local sinceRefresh = 0
    viewer:SetScript("OnUpdate", function(self, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh < 1 then return end
        sinceRefresh = 0
        self:Refresh()
    end)
    viewer:SetScript("OnShow", function(self)
        sinceRefresh = 0
        self:Refresh()
    end)
    return viewer
end

local function toggleTickViewer()
    if not ns.db then return end
    if not tickViewer then tickViewer = createTickViewer() end
    if tickViewer:IsShown() then return tickViewer:Hide() end
    tickViewer:ClearAllPoints()
    if window and window:IsShown() then
        tickViewer:SetPoint("CENTER", window, "CENTER", 0, 0)
    else
        tickViewer:SetPoint("CENTER")
    end
    tickViewer:Show()
end
ns.toggleTickViewer = toggleTickViewer

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function selectTab(tab)
    closeMenu()
    activeTab = tab
    for _, other in ipairs(tabs) do
        local selected = other == tab
        other.content:SetShown(selected)
        other.button.text:SetTextColor(selected and 1 or 0.6, selected and 0.82 or 0.6, selected and 0 or 0.6)
        other.button.underline:SetShown(selected)
        if other.footer then other.footer:SetShown(selected) end
    end
end

-- A tab whose methods add rows top to bottom and remember the setting keys, for "Reset this tab".
local function addTab(name)
    local area = window.settingsArea
    local tab = { keys = {}, y = 0 }
    tab.content = CreateFrame("Frame", nil, area)
    tab.content:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -40)
    tab.content:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 40)
    tab.content:Hide()

    local button = CreateFrame("Button", nil, area)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetText(T(name))
    -- Tight padding: seven tabs have to fit the settings area's width.
    button:SetSize(button.text:GetStringWidth() + 12, 26)
    button.text:SetPoint("CENTER")
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetColorTexture(1, 0.82, 0, 1)
    button.underline:SetHeight(2)
    button.underline:SetPoint("BOTTOMLEFT", 3, 0)
    button.underline:SetPoint("BOTTOMRIGHT", -3, 0)
    local previous = tabs[#tabs]
    if previous then
        button:SetPoint("LEFT", previous.button, "RIGHT", 2, 0)
    else
        button:SetPoint("TOPLEFT", area, "TOPLEFT", 8, -8)
    end
    button:SetScript("OnClick", function() selectTab(tab) end)
    tab.button = button

    local function place(row, key)
        row:SetPoint("TOPLEFT", tab.content, "TOPLEFT", 0, -tab.y)
        tab.y = tab.y + ROW_HEIGHT
        if key then table.insert(tab.keys, key) end
        return row
    end
    function tab:checkbox(key, ...) return place(checkbox(self.content, key, ...), key) end
    function tab:slider(key, ...) return place(slider(self.content, key, ...), key) end
    function tab:choice(key, ...) return place(choice(self.content, key, ...), key) end
    function tab:action(...) return place(actionRow(self.content, ...)) end
    function tab:frame(key, ...) return place(frameRow(self.content, key, ...), key) end
    function tab:info(...) return place(infoRow(self.content, ...)) end
    function tab:gap() self.y = self.y + 8 end

    table.insert(tabs, tab)
    return tab
end

local function resetTab(tab)
    for _, key in ipairs(tab.keys) do db()[key] = ns.DEFAULTS[key] end
    changed()
end

local function applyPreset(preset)
    for key, value in pairs(preset.values) do db()[key] = value end
    changed()
    ns.print(preset.label .. " preset applied.")
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function isDashed(settings) return settings.outlineStyle == "dashed" end
local function hasOutline(settings) return settings.outlineStyle ~= "none" end
local function singleColor(settings) return settings.dotColors == "single" end
local function perDot(settings) return settings.dotColors ~= "single" end
local function showsLabel(settings) return settings.showLabel end

local function buildTabs()
    local lists = ns.lists

    local icon = addTab("Kill icon")
    icon:checkbox("showSkull", "Show icon on portrait",
        { tooltip = "Shows an icon over the target's portrait when your DoTs on it will kill it." })
    icon:choice("skullIcon", "Icon", lists.icons)
    icon:slider("skullSize", "Size", 20, 128, 2)
    icon:checkbox("skullPulse", "Pulse", { tooltip = "Gently pulses the icon while it's showing." })
    -- Wide ranges: with a custom target frame (Advanced) the icon may be centered on a long health bar.
    icon:slider("skullOffsetX", "Horizontal offset", -150, 150, 1,
        { tooltip = "Pixels right (+) or left (-) of the portrait's center (or the custom spot's, see Advanced)." })
    icon:slider("skullOffsetY", "Vertical offset", -150, 150, 1,
        { tooltip = "Pixels up (+) or down (-) from the portrait's center (or the custom spot's, see Advanced)." })

    local marker = addTab("Marker")
    marker:checkbox("showMarkers", "Show damage marker", { tooltip = "Marks the damage your DoTs still have to "
        .. "deal on the target's health bar. If the health ends inside it, the target dies." })
    marker:choice("dotColors", "DoT colors", lists.dotColors, { tooltip = "One color, or one segment per DoT "
        .. "colored by spell school or with a different color each." })
    marker:choice("fillTexture", "Fill style", lists.fills)
    marker:choice("fillColor", "Fill color", lists.colors, { enabledIf = singleColor,
        tooltip = "Used when DoT colors is set to one color." })
    marker:slider("fillOpacity", "Fill opacity", 0, 100, 5, { suffix = "%" })
    marker:checkbox("segmentDividers", "Dividers between DoTs", { enabledIf = perDot })
    marker:gap()
    marker:choice("outlineStyle", "Outline", lists.outlines)
    marker:choice("dashLength", "Dash length", lists.dashLengths, { enabledIf = isDashed })
    marker:slider("outlineThickness", "Outline thickness", 1, 8, 1, { enabledIf = hasOutline })
    marker:choice("outlineColor", "Outline color", lists.colors, { enabledIf = hasOutline })
    marker:slider("outlineOpacity", "Outline opacity", 10, 100, 5, { suffix = "%", enabledIf = hasOutline })

    local effects = addTab("Effects")
    effects:checkbox("smoothMotion", "Smooth motion",
        { tooltip = "The marker grows in when it appears and glides to new values instead of jumping." })
    effects:checkbox("flashOnApply", "Flash on new DoT")
    effects:checkbox("showSpark", "Spark", { tooltip = "A bright flare on the marker's edge when a DoT lands." })
    effects:checkbox("pulseOutline", "Pulse outline", { enabledIf = hasOutline })
    effects:gap()
    effects:checkbox("showGlow", "Glow", { enabledIf = hasOutline, tooltip = "Soft halo in the outline color." })
    effects:slider("glowSize", "Glow size", 2, 16, 1,
        { enabledIf = function(s) return hasOutline(s) and s.showGlow end })
    effects:checkbox("showShine", "Shine sweep")
    effects:slider("shineInterval", "Shine every", 2, 10, 1,
        { suffix = "s", enabledIf = function(s) return s.showShine end })
    effects:checkbox("scrollStripes", "Scroll stripes", { tooltip = "Animates the diagonal stripes fill.",
        enabledIf = function(s) return s.fillTexture == "stripes" and singleColor(s) end })

    local text = addTab("Text")
    text:checkbox("showLabel", "Show damage text",
        { tooltip = "Remaining DoT damage next to the health bar (a per-DoT breakdown with DoT colors)." })
    text:choice("labelPosition", "Position", lists.labelPositions, { enabledIf = showsLabel })
    text:slider("labelSize", "Size", 8, 20, 1, { enabledIf = showsLabel })
    text:choice("labelColor", "Color", lists.colors, { enabledIf = showsLabel })

    -- Nameplates have their own look: enemy plates are red, so the target marker's colors may not show on them.
    local platesOn = function(s) return s.nameplateMode ~= "off" end
    local plateIcon = function(s) return s.nameplateMode == "markerIcon" end
    local plateSingle = function(s) return platesOn(s) and s.plateDotColors == "single" end
    local plateOutline = function(s) return platesOn(s) and s.plateOutlineStyle ~= "none" end
    local plates = addTab("Nameplates")
    plates:choice("nameplateMode", "Show on nameplates", lists.nameplateModes, { tooltip = "Draws a marker "
        .. "(and optionally the kill icon) on every enemy nameplate with your DoTs on it, in its own look below." })
    plates:choice("plateIcon", "Kill icon", lists.icons, { enabledIf = plateIcon })
    plates:slider("nameplateIconSize", "Kill icon size", 12, 128, 1, { enabledIf = plateIcon })
    plates:choice("nameplateIconPosition", "Kill icon position", lists.nameplateIconPositions,
        { enabledIf = plateIcon })
    plates:slider("plateIconOffsetX", "Icon horizontal offset", -40, 40, 1,
        { enabledIf = plateIcon, tooltip = "Pixels right (+) or left (-) of the chosen position." })
    plates:slider("plateIconOffsetY", "Icon vertical offset", -40, 40, 1,
        { enabledIf = plateIcon, tooltip = "Pixels up (+) or down (-) from the chosen position." })
    plates:gap()
    plates:choice("plateDotColors", "DoT colors", lists.dotColors, { enabledIf = platesOn })
    plates:choice("plateFillTexture", "Fill style", lists.fills, { enabledIf = platesOn })
    plates:choice("plateFillColor", "Fill color", lists.colors, { enabledIf = plateSingle })
    plates:slider("plateFillOpacity", "Fill opacity", 0, 100, 5, { suffix = "%", enabledIf = platesOn })
    plates:choice("plateOutlineStyle", "Outline", lists.outlines, { enabledIf = platesOn })
    plates:choice("plateDashLength", "Dash length", lists.dashLengths,
        { enabledIf = function(s) return platesOn(s) and s.plateOutlineStyle == "dashed" end })
    plates:slider("plateOutlineThickness", "Outline thickness", 1, 3, 1, { enabledIf = plateOutline })
    plates:choice("plateOutlineColor", "Outline color", lists.colors, { enabledIf = plateOutline })
    plates:slider("plateOutlineOpacity", "Outline opacity", 10, 100, 5, { suffix = "%", enabledIf = plateOutline })
    plates.footer = pushButton(window.settingsArea, "Copy from Marker tab", 160, function()
        local db = ns.db
        db.plateFillTexture, db.plateFillColor, db.plateFillOpacity = db.fillTexture, db.fillColor, db.fillOpacity
        db.plateDotColors, db.plateIcon = db.dotColors, db.skullIcon
        db.plateOutlineStyle, db.plateDashLength = db.outlineStyle, db.dashLength
        db.plateOutlineThickness = math.min(db.outlineThickness, 3)
        db.plateOutlineColor, db.plateOutlineOpacity = db.outlineColor, db.outlineOpacity
        changed()
    end)
    plates.footer:SetPoint("BOTTOMLEFT", 10, 10)
    plates.footer:Hide()

    -- The focus frame (Focus.lua): its own look, like the nameplates'. Its frame path is on the Advanced tab.
    local focusOn = function(s) return s.focusMode ~= "off" end
    local focusIcon = function(s) return s.focusMode == "markerIcon" end
    local focusSingle = function(s) return focusOn(s) and s.focusDotColors == "single" end
    local focusOutline = function(s) return focusOn(s) and s.focusOutlineStyle ~= "none" end
    local focus = addTab("Focus")
    focus:choice("focusMode", "Show on focus frame", lists.nameplateModes, { tooltip = "Draws the marker (and "
        .. "optionally the kill icon) on your focus's health bar, for your DoTs on it, in its own look below. "
        .. "/cast [@focus] macros put the DoT on your focus. For another addon's focus frame, see the Advanced tab." })
    focus:choice("focusIcon", "Kill icon", lists.icons, { enabledIf = focusIcon })
    focus:slider("focusIconSize", "Kill icon size", 12, 128, 1, { enabledIf = focusIcon })
    focus:choice("focusIconPosition", "Kill icon position", lists.nameplateIconPositions, { enabledIf = focusIcon })
    focus:slider("focusIconOffsetX", "Icon horizontal offset", -40, 40, 1,
        { enabledIf = focusIcon, tooltip = "Pixels right (+) or left (-) of the chosen position." })
    focus:slider("focusIconOffsetY", "Icon vertical offset", -40, 40, 1,
        { enabledIf = focusIcon, tooltip = "Pixels up (+) or down (-) from the chosen position." })
    focus:gap()
    focus:choice("focusDotColors", "DoT colors", lists.dotColors, { enabledIf = focusOn })
    focus:choice("focusFillTexture", "Fill style", lists.fills, { enabledIf = focusOn })
    focus:choice("focusFillColor", "Fill color", lists.colors, { enabledIf = focusSingle })
    focus:slider("focusFillOpacity", "Fill opacity", 0, 100, 5, { suffix = "%", enabledIf = focusOn })
    focus:choice("focusOutlineStyle", "Outline", lists.outlines, { enabledIf = focusOn })
    focus:choice("focusDashLength", "Dash length", lists.dashLengths,
        { enabledIf = function(s) return focusOn(s) and s.focusOutlineStyle == "dashed" end })
    focus:slider("focusOutlineThickness", "Outline thickness", 1, 3, 1, { enabledIf = focusOutline })
    focus:choice("focusOutlineColor", "Outline color", lists.colors, { enabledIf = focusOutline })
    focus:slider("focusOutlineOpacity", "Outline opacity", 10, 100, 5, { suffix = "%", enabledIf = focusOutline })
    focus.footer = pushButton(window.settingsArea, "Copy from Nameplates tab", 180, function()
        local db = ns.db
        for plateKey, focusKey in pairs(ns.focusKeys) do
            if plateKey ~= "nameplateMode" then db[focusKey] = db[plateKey] end
        end
        changed()
    end)
    focus.footer:SetPoint("BOTTOMLEFT", 10, 10)
    focus.footer:Hide()

    local advanced = addTab("Advanced")
    advanced:choice("uiLanguage", "Window language", ns.locale.windowLanguages(), { tooltip = "The language of this "
        .. "window and the addon's messages. Auto follows your game client. Changes apply after /reload.",
        onChange = function() ns.print(T("The window language changes after a /reload.")) end })
    advanced:choice("waitFirstTick", "Wait for first tick", lists.waitModes, { tooltip = "Whether a new DoT "
        .. "counts before its first tick lands. \"When unsure\" waits for finishers with unknown combo points "
        .. "and spells the addon hasn't seen tick yet." })
    advanced:checkbox("estimateDuringCast", "Estimate during casting", { tooltip = "Shows a DoT with a cast time "
        .. "while you're still casting it. Once the cast lands the normal estimate takes over; an interrupted or "
        .. "failed cast removes it." })
    advanced:checkbox("debug", "Echo trace log to chat",
        { tooltip = "Prints each DoT cast, matched tick and estimate to chat." })
    local learned = advanced:action("Learned tick sizes", "View", toggleTickViewer, { tooltip = "What each of your "
        .. "DoTs really ticks for, learned from earlier casts, next to what its tooltip says. Reset forgets them all." })
    local resetLearned = pushButton(learned, "Reset", 90, function()
        ns.resetLearnedTicks()
        if tickViewer and tickViewer:IsShown() then tickViewer:Refresh() end
    end)
    resetLearned:SetPoint("LEFT", learned.button, "RIGHT", 6, 0)
    -- Custom target frame (Frames.lua), for unit frame addons that replace Blizzard's.
    advanced:gap()
    advanced:gap()
    advanced:frame("customHealthBar", "Target health bar", "bar", { tooltip = "For unit frame addons that replace "
        .. "Blizzard's target frame. Target something, click Pick, then click its health bar. Or type the frame's "
        .. "name (/fstack shows it). The bar must fill left to right. Leave empty for Blizzard's, or "
        .. "EllesmereUI's when it shows its own target frame." })
    advanced:frame("customIconAnchor", "Kill icon spot", "anchor", { tooltip = "Where the kill icon is centered "
        .. "(e.g. the custom frame's portrait). Empty: Blizzard's portrait, or EllesmereUI's when its target frame "
        .. "shows one; else the health bar in use. "
        .. "Fine-tune with the offsets on the Kill icon tab." })
    advanced:info("Health bar in use", function() return (ns.attachStatus()) end)
    advanced:info("Kill icon in use", function() return select(2, ns.attachStatus()) end)
    -- Custom focus frame (Focus.lua; its look is on the Focus tab).
    advanced:gap()
    advanced:frame("customFocusHealthBar", "Focus health bar", "bar", { tooltip = "For unit frame addons that "
        .. "replace Blizzard's focus frame. Focus something, click Pick, then click its health bar. Leave empty for "
        .. "Blizzard's, or EllesmereUI's when it shows its own focus frame.",
        enabledIf = function(settings) return settings.focusMode ~= "off" end })
    advanced:info("Focus bar in use", function() return ns.focusStatus and ns.focusStatus() or "" end)
    -- Nameplate addons' bars (Nameplates.lua): found automatically; this is for one the search misses.
    advanced:gap()
    advanced:frame("customPlateHealthBar", "Nameplate health bar", "bar", { noPick = true, tooltip = "Most "
        .. "nameplate addons' health bars are found automatically (Plater, EllesmereUI, Platynator, ...). If the "
        .. "marker doesn't show on yours, type the keys from Blizzard's nameplate to its bar, like "
        .. "unitFrame.healthBar. /did plates logs what each plate uses. Leave empty for automatic." })
    advanced:info("Nameplate bar in use", function() return ns.plateBarStatus and ns.plateBarStatus() or "" end)
end

local function buildPreview(pane)
    local title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(T("Live preview"))

    -- Mock target frame: name, health bar, round portrait.
    local mock = CreateFrame("Frame", nil, pane, "BackdropTemplate")
    mock:SetSize(PREVIEW_WIDTH - 24, 78)
    mock:SetPoint("TOP", pane, "TOP", 0, -40)
    setBackdrop(mock, 0.03)

    local portrait = mock:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(56, 56)
    portrait:SetPoint("RIGHT", mock, "RIGHT", -12, 0)
    portrait:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Boar")
    local mask = mock:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(portrait)
    portrait:AddMaskTexture(mask)

    local healthBar = CreateFrame("StatusBar", nil, mock)
    healthBar:SetSize(PREVIEW_WIDTH - 110, 18)
    healthBar:SetPoint("RIGHT", portrait, "LEFT", -10, -6)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(0.1, 0.8, 0.1)
    healthBar:SetMinMaxValues(0, 100)
    local healthBack = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBack:SetAllPoints()
    healthBack:SetColorTexture(0.25, 0.08, 0.08, 1)

    local name = mock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    name:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, 4)
    name:SetText(T("Mottled Boar"))

    window.healthBar = healthBar
    window.host = { healthBar = healthBar, portrait = portrait, layerFrame = window }
    window.mock = mock

    -- Shown over the mock frame while combat has the display back on the real target.
    window.combatNote = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.combatNote:SetPoint("CENTER", mock, "CENTER")
    window.combatNote:SetWidth(PREVIEW_WIDTH - 40)
    window.combatNote:SetText(T("In combat: the marker and kill icon are showing on your target. "
        .. "The preview resumes after combat."))
    window.combatNote:Hide()

    -- Preview controls (plain numbers, not settings).
    local health = sliderRow(pane, "Target health", 0, 100, 1,
        function() return preview.health end,
        function(value)
            stopSimulation()
            preview.health = value
            updatePreview()
        end, { layout = PREVIEW_LAYOUT, suffix = "%" })
    health:SetPoint("TOPLEFT", mock, "BOTTOMLEFT", -4, -14)
    local damage = sliderRow(pane, "DoT damage", 0, 100, 1,
        function() return math.floor(previewTotal() + 0.5) end,
        function(value)
            stopSimulation()
            setPreviewDamage(value)
            updatePreview()
        end, { layout = PREVIEW_LAYOUT, suffix = "%",
            tooltip = "Remaining damage of two sample DoTs, in % of the target's max health." })
    damage:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)

    window.simulateButton = pushButton(pane, "Simulate fight", 130, function()
        if simulation then stopSimulation() else startSimulation() end
    end)
    window.simulateButton:SetPoint("TOPLEFT", damage, "BOTTOMLEFT", 6, -10)
    window.flashButton = pushButton(pane, "Flash", 80, function() ns.playFlash() end)
    window.flashButton:SetPoint("LEFT", window.simulateButton, "RIGHT", 8, 0)

    window.status = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.status:SetPoint("TOPLEFT", window.simulateButton, "BOTTOMLEFT", 0, -14)
    window.status:SetWidth(PREVIEW_WIDTH - 30)
    window.status:SetJustifyH("LEFT")

    -- Mock enemy nameplate (red, like the real ones), drawn by the real nameplate code (Nameplates.lua).
    local plateLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    plateLabel:SetPoint("TOPLEFT", window.status, "BOTTOMLEFT", 0, -20)
    plateLabel:SetText(T("Nameplate"))
    local mockPlate = CreateFrame("Frame", nil, pane)
    mockPlate:SetSize(140, 26)
    mockPlate:SetPoint("TOPLEFT", plateLabel, "BOTTOMLEFT", 40, -6)
    local plateName = mockPlate:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    plateName:SetPoint("TOP", mockPlate, "TOP")
    plateName:SetText(T("Mottled Boar"))
    local plateBar = CreateFrame("StatusBar", nil, mockPlate)
    plateBar:SetSize(140, 10)
    plateBar:SetPoint("BOTTOM", mockPlate, "BOTTOM")
    plateBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    plateBar:SetStatusBarColor(0.85, 0.1, 0.1)
    plateBar:SetMinMaxValues(0, 100)
    local plateBack = plateBar:CreateTexture(nil, "BACKGROUND")
    plateBack:SetAllPoints()
    plateBack:SetColorTexture(0.1, 0.02, 0.02, 1)
    window.mockPlate = mockPlate
    window.plateHealthBar = plateBar
    window.plateHost = { plate = mockPlate, healthBar = plateBar }

    -- A small focus frame (Focus.lua draws on it), shaped like Blizzard's: bar on the left, portrait on the right.
    local focusLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    focusLabel:SetPoint("TOPLEFT", plateLabel, "BOTTOMLEFT", 0, -46)
    focusLabel:SetText(T("Focus"))
    local mockFocus = CreateFrame("Frame", nil, pane)
    mockFocus:SetSize(170, 36)
    mockFocus:SetPoint("TOPLEFT", focusLabel, "BOTTOMLEFT", 50, -4)
    local focusPortrait = mockFocus:CreateTexture(nil, "ARTWORK")
    focusPortrait:SetSize(32, 32)
    focusPortrait:SetPoint("RIGHT", mockFocus, "RIGHT", 0, 0)
    focusPortrait:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Boar")
    local focusMask = mockFocus:CreateMaskTexture()
    focusMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE")
    focusMask:SetAllPoints(focusPortrait)
    focusPortrait:AddMaskTexture(focusMask)
    local focusBar = CreateFrame("StatusBar", nil, mockFocus)
    focusBar:SetSize(130, 12)
    focusBar:SetPoint("RIGHT", focusPortrait, "LEFT", -6, -5)
    focusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    focusBar:SetStatusBarColor(0.1, 0.8, 0.1)
    focusBar:SetMinMaxValues(0, 100)
    local focusBack = focusBar:CreateTexture(nil, "BACKGROUND")
    focusBack:SetAllPoints()
    focusBack:SetColorTexture(0.25, 0.08, 0.08, 1)
    local focusName = mockFocus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    focusName:SetPoint("BOTTOMLEFT", focusBar, "TOPLEFT", 0, 3)
    focusName:SetText(T("Mottled Boar"))
    window.mockFocus = mockFocus
    window.focusHealthBar = focusBar
    window.focusHost = { frame = mockFocus, healthBar = focusBar }

    local hint = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 12)
    hint:SetWidth(PREVIEW_WIDTH - 24)
    hint:SetJustifyH("LEFT")
    hint:SetText(T("While this window is open, the marker and kill icon are drawn here instead of on your target."))
end

local function createWindow()
    window = CreateFrame("Frame", "DoesItDieOptions", UIParent, "BackdropTemplate")
    window:Hide() -- new frames start shown; ns.openOptions shows it (running OnShow)
    window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    setBackdrop(window, 0.06, 0.97)
    table.insert(UISpecialFrames, "DoesItDieOptions") -- Escape closes it

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -18)
    title:SetText("DoesItDie")

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -12)

    -- Presets, right-aligned in the title bar.
    local presetLabel = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    local previous
    for i = #PRESETS, 1, -1 do
        local preset = PRESETS[i]
        local button = pushButton(window, preset.label, 72, function() applyPreset(preset) end)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        else
            button:SetPoint("RIGHT", close, "LEFT", -8, 0)
        end
        previous = button
    end
    presetLabel:SetPoint("RIGHT", previous, "LEFT", -8, 0)
    presetLabel:SetText(T("Presets"))

    local pane = CreateFrame("Frame", nil, window, "BackdropTemplate")
    pane:SetPoint("TOPLEFT", 10, -HEADER_HEIGHT)
    pane:SetPoint("BOTTOMLEFT", 10, 10)
    pane:SetWidth(PREVIEW_WIDTH)
    setBackdrop(pane, 0.09)
    buildPreview(pane)

    local area = CreateFrame("Frame", nil, window, "BackdropTemplate")
    area:SetPoint("TOPLEFT", pane, "TOPRIGHT", 10, 0)
    area:SetPoint("BOTTOMRIGHT", -10, 10)
    setBackdrop(area, 0.09)
    window.settingsArea = area

    local divider = area:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.28, 0.28, 0.3, 1)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 8, -34)
    divider:SetPoint("TOPRIGHT", -8, -34)

    buildTabs()
    local reset = pushButton(area, "Reset this tab", 120, function() resetTab(activeTab) end)
    reset:SetPoint("BOTTOMRIGHT", -10, 10)

    window:SetScript("OnShow", function()
        ns.setPreviewState(preview)
        window.previewPaused = nil
        syncDisplayHost()
        refreshControls()
        updatePreview()
    end)
    window:SetScript("OnHide", function()
        stopSimulation()
        closeMenu()
        ns.setPreviewState(nil)
        ns.setDisplayHost(nil)
        ns.setPlatePreview(nil)
        ns.setFocusPreview(nil)
    end)
    -- Combat hands the display back to the real target, and after combat back to the preview.
    window:RegisterEvent("PLAYER_REGEN_DISABLED")
    window:RegisterEvent("PLAYER_REGEN_ENABLED")
    window:SetScript("OnEvent", function() syncDisplayHost() end)
    selectTab(tabs[1])
end

function ns.openOptions()
    if not ns.db then return end
    if not window then createWindow() end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
    end
end

-- Options > AddOns > DoesItDie: a short page with a button that opens the window.
function ns.registerOptions()
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("DoesItDie")
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetText(T("Settings have their own window with a live preview. You can also type /did."))
    local open = pushButton(panel, "Open DoesItDie options", 200, function()
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        if not (window and window:IsShown()) then ns.openOptions() end
    end)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "DoesItDie")
        Settings.RegisterAddOnCategory(category)
    elseif type(InterfaceOptions_AddCategory) == "function" then
        panel.name = "DoesItDie"
        InterfaceOptions_AddCategory(panel)
    end
end
