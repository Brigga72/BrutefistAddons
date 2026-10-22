-- DoesItDie nameplates: the damage marker (and optionally the kill icon) on every enemy nameplate that has your
-- DoTs on it, using the per-mob tracking in DoesItDie.lua (ns.dotBreakdownForUnit). Same secret-value trick as
-- the target frame: StatusBars are fed the mob's hidden health and do the comparing.
--
-- Widgets are created per Blizzard nameplate frame (which WoW recycles between mobs) and parented to it, so
-- they move, scale and hide with the plate. With EllesmereUI's nameplates they go on its own plate frame instead,
-- and with Platynator's they anchor to its health bar (see findHealthBar). They're lighter than the target marker: fill, per-DoT segments and a thin outline in the
-- Marker tab's style; no glow, shine, spark or animation.
--
-- Also the probe (/did plates): what the addon can reach on nameplates, logged, with a test bar on each.

local ADDON_NAME, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_PLATES = 40
local UPDATE_INTERVAL = 0.1
local MAX_SEGMENTS = 4
local OUTLINE_THICKNESS = 1
local ICON_BAR_LENGTH = 10000 -- see the kill icon notes in DoesItDie.lua
local FALLBACK_LEVEL = 200    -- frame level when the plate's own level can't be read
local TEST_SECONDS = 8
local TEST_BAR_WIDTH, TEST_BAR_HEIGHT = 90, 6

ns.lists.nameplateModes = {
    { id = "off",        label = "Off" },
    { id = "marker",     label = "Marker only" },
    { id = "markerIcon", label = "Marker and kill icon" },
}
ns.lists.nameplateIconPositions = {
    { id = "right", label = "Right of the health bar" },
    { id = "left",  label = "Left of the health bar" },
    { id = "above", label = "Above the health bar" },
}

local testBars = {}
local hideTestBarsAt = 0

local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

-- "secret", "nil", "error: ...", or the value.
local function describe(ok, value)
    if not ok then return "error: " .. tostring(value) end
    if value == nil then return "nil" end
    if isSecret(value) then return "secret" end
    return tostring(value)
end

local function call(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    return describe(pcall(fn, ...))
end

-- Platynator hides Blizzard's UnitFrame and draws its own display frames (40 per style, preallocated),
-- parented to "NamePlate<i>" or, when that doesn't exist yet at creation (as in Forever), to UIParent. The
-- active one for a unit is shown with .unit = the nameplate unit token; its .widgets list holds the health
-- widget (details.kind == "health") with the real StatusBar in .statusBar. Displays are found by scanning
-- UIParent's and the plate's children, cached, and rescanned (throttled) when a unit has none.
local platyDisplays = {}
local platyLastScan = -math.huge
local PLATY_RESCAN_INTERVAL = 2

local function isPlatyDisplay(frame)
    return type(frame.widgets) == "table" and type(frame.Install) == "function" and type(frame.SetUnit) == "function"
end

local function scanPlatyDisplays(plate)
    for _, parent in ipairs({ UIParent, plate }) do
        for _, child in ipairs({ parent:GetChildren() }) do
            if not platyDisplays[child] and isPlatyDisplay(child) then platyDisplays[child] = true end
        end
    end
end

local function platyBarFor(unit)
    for display in pairs(platyDisplays) do
        if display.unit == unit and display:IsShown() and type(display.widgets) == "table" then
            for _, widget in ipairs(display.widgets) do
                if type(widget.details) == "table" and widget.details.kind == "health" and widget.statusBar then
                    return widget.statusBar
                end
            end
        end
    end
end

local function findPlatynatorBar(plate, unit)
    if not (Platynator and unit) then return nil end
    local bar = platyBarFor(unit)
    if bar then return bar end
    local now = GetTime()
    if now - platyLastScan < PLATY_RESCAN_INTERVAL then return nil end
    platyLastScan = now
    scanPlatyDisplays(plate)
    return platyBarFor(unit)
end

-- False only when the bar is known to be hidden or fully transparent, e.g. a plate addon took over and parked or
-- faded out Blizzard's: the marker would otherwise draw over nothing.
local function barShown(bar)
    local ok, visible = pcall(bar.IsVisible, bar)
    if ok and not isSecret(visible) and visible == false then return false end
    local okAlpha, alpha = pcall(bar.GetEffectiveAlpha, bar)
    if okAlpha and type(alpha) == "number" and not isSecret(alpha) and alpha <= 0 then return false end
    return true
end

local function isStatusBar(value)
    if type(value) ~= "table" or type(value.GetObjectType) ~= "function" then return false end
    local ok, kind = pcall(value.GetObjectType, value)
    return ok and kind == "StatusBar"
end

local function forbidden(frame)
    local ok, result = pcall(function() return frame.IsForbidden and frame:IsForbidden() end)
    return not ok or result == true
end

-- The Advanced tab's "Nameplate health bar": keys from the Blizzard nameplate, e.g. "unitFrame.healthBar".
local function resolveFromPlate(plate, path)
    local current = plate
    for key in string.gmatch(path, "[^%.]+") do
        local ok, value = pcall(function() return current[key] end)
        if not ok or type(value) ~= "table" then return nil end
        current = value
    end
    if current ~= plate and isStatusBar(current) then return current end
end

-- Automatic search for a nameplate addon's health bar (Plater, KUI, ...): they hang their own frames on Blizzard's
-- nameplate and keep the bar in a field named like "health" (healthBar, health, HealthBar). Breadth-first through
-- the plate's frames (not Blizzard's UnitFrame), the first shown StatusBar under such a key wins. Returns the bar
-- and where it was found ("unitFrame.healthBar"). Reading every field of a frame is slow, so each plate's result
-- is kept (searchCache) and only searched again, at most once a second, when it's gone or hidden.
local SEARCH_DEPTH = 4
local SEARCH_INTERVAL = 1
local searchCache = {} -- plate -> { bar, path, at }

-- Whether `frame` sits inside `plate` (fields can point anywhere: a frame's back-reference to UIParent would
-- otherwise lead the search to some other "health" bar).
local function isUnder(frame, plate)
    local current = frame
    for _ = 1, 12 do
        local ok, parent = pcall(current.GetParent, current)
        if not ok or parent == nil then return false end
        if parent == plate then return true end
        current = parent
    end
    return false
end

-- A plain Lua table (an addon's own bookkeeping, like Threat Plates' TPFrame.visual), as opposed to a frame.
local MAX_TABLE_ENTRIES = 200 -- bigger plain tables are settings or caches, not where a plate keeps its bar
local function isFrame(value)
    local ok, kind = pcall(function() return value:GetObjectType() end)
    return ok and type(kind) == "string"
end

-- The string-keyed table fields of `container`, sorted (the same answer every time). Nil if it can't be read, or
-- for a plain table that's too big.
local function tableFields(container, plain)
    local ok, fields = pcall(function()
        local found, count = {}, 0
        for key, value in pairs(container) do
            count = count + 1
            if plain and count > MAX_TABLE_ENTRIES then return nil end
            if type(key) == "string" and type(value) == "table" then table.insert(found, { key, value }) end
        end
        return found
    end)
    if not ok or not fields then return nil end
    table.sort(fields, function(a, b) return a[1] < b[1] end)
    return fields
end

-- Each field is checked under its own pcall: plate addons build frames with frameworks whose objects may error
-- when read (an __index that throws), and one such field mustn't stop the whole search.
local function searchHealthBar(plate)
    local blizzardBar = plate.UnitFrame and plate.UnitFrame.healthBar
    local queue = { { node = plate, path = "", depth = 0, plain = false } }
    local seen = { [plate] = true }
    local head = 1
    while queue[head] do
        local item = queue[head]
        head = head + 1
        local fields = tableFields(item.node, item.plain)
        if fields then
            -- A shown StatusBar under a "health" key, inside the plate, is the answer.
            for _, field in ipairs(fields) do
                local key, value = field[1], field[2]
                local ok, found = pcall(function()
                    return key:lower():find("health", 1, true) and value ~= blizzardBar and isStatusBar(value)
                        and not forbidden(value) and isUnder(value, plate) and barShown(value)
                end)
                if ok and found then return value, item.path .. key end
            end
            -- Else go one level deeper: frames inside the plate (not Blizzard's UnitFrame), and plain tables.
            if item.depth < SEARCH_DEPTH then
                for _, field in ipairs(fields) do
                    local key, value = field[1], field[2]
                    if not seen[value] and value ~= plate.UnitFrame then
                        seen[value] = true
                        local frame = isFrame(value)
                        local ok, visit = pcall(function()
                            if frame then return not isStatusBar(value) and not forbidden(value) and isUnder(value, plate) end
                            return true
                        end)
                        if ok and visit then
                            table.insert(queue, { node = value, path = item.path .. key .. ".", depth = item.depth + 1,
                                plain = not frame })
                        end
                    end
                end
            end
        end
    end
end

local function autoHealthBar(plate)
    local cached = searchCache[plate]
    local now = GetTime()
    if cached and cached.bar and barShown(cached.bar) then return cached.bar, cached.path end
    if cached and now - cached.at < SEARCH_INTERVAL then return nil end
    local ok, bar, path = pcall(searchHealthBar, plate)
    if not ok then bar, path = nil, nil end
    searchCache[plate] = { bar = bar, path = path, at = now }
    return bar, path
end

-- The health bar a nameplate shows, the frame our widgets go on, the path the bar was found under, and whether
-- it's a plate addon's bar (drawn in a strata of its own, which ours must match). In order:
--   * the Advanced tab's path from the plate, when set and shown
--   * EllesmereUI: it parks Blizzard's bar on a hidden frame and shows its own plate, a pooled frame parented to
--     the Blizzard plate while in use, listed by unit in its addon table, with the bar at .health. Our widgets go
--     on that frame so they fade, scale and hide with it.
--   * Platynator: its displays aren't tied to one plate (they're reassigned between units, and may hang off
--     UIParent), so our widgets stay on Blizzard's plate and only anchor to its bar.
--   * Blizzard's own bar, while it's shown
--   * the automatic search (searchHealthBar), for other plate addons
--   * Blizzard's bar, hidden: only the kill icon is drawn, beside the plate (iconOnly)
local function findHealthBar(plate, unit)
    local db = ns.db
    local custom = db and strtrim(db.customPlateHealthBar or "") or ""
    if custom ~= "" then
        local bar = resolveFromPlate(plate, custom)
        if bar and barShown(bar) then return bar, plate, "custom " .. custom, true end
    end
    local eui = EllesmereNameplates_NS
    local euiPlate = type(eui) == "table" and type(eui.plates) == "table" and eui.plates[unit]
    if type(euiPlate) == "table" and euiPlate.nameplate == plate and euiPlate.health then
        return euiPlate.health, euiPlate, "EllesmereUI plate.health", true
    end
    local ok, platyBar = pcall(findPlatynatorBar, plate, unit)
    if ok and platyBar then return platyBar, plate, "Platynator health widget", true end

    local unitFrame = plate.UnitFrame
    local blizzard, blizzardPath
    if unitFrame then
        local container = unitFrame.HealthBarsContainer
        if unitFrame.healthBar then
            blizzard, blizzardPath = unitFrame.healthBar, "UnitFrame.healthBar"
        elseif container and container.healthBar then
            blizzard, blizzardPath = container.healthBar, "UnitFrame.HealthBarsContainer.healthBar"
        elseif unitFrame.HealthBar then
            blizzard, blizzardPath = unitFrame.HealthBar, "UnitFrame.HealthBar"
        end
    end
    if blizzard and barShown(blizzard) then return blizzard, plate, blizzardPath, false end
    local found, path = autoHealthBar(plate)
    if found then return found, plate, "auto " .. path, true end
    -- Nothing found and Blizzard's bar hidden: a plate addon we can't read. A marker on the hidden bar would float
    -- over nothing, but the kill icon beside the plate still says "this one dies" (as before v0.7.0): icon only.
    if blizzard then return blizzard, plate, blizzardPath .. " (hidden: kill icon only)", false, true end
    return nil, nil, unitFrame and "no health bar found" or "no UnitFrame"
end

-- What the last drawn nameplate's marker was on, for the options window.
local lastBarPath

function ns.plateBarStatus()
    if not lastBarPath then return "|cff888888none drawn yet|r" end
    if lastBarPath:find("^custom ") then return "|cff66ff66" .. lastBarPath:sub(8) .. "|r" end
    if lastBarPath:find("^auto ") then return "found: " .. lastBarPath:sub(6) end
    return lastBarPath
end

---------------------------------------------------------------------------
-- Nameplate display
---------------------------------------------------------------------------

local widgetsByHost = {} -- frame the widgets are parented to (Blizzard's or EllesmereUI's plate) -> our widgets

local function hideWidgets(w)
    w.marker:Hide()
    w.iconWindow:Hide()
end

local function coverSpan(texture, span)
    texture:SetPoint("TOPLEFT", span, "TOPLEFT")
    texture:SetPoint("BOTTOMRIGHT", span, "BOTTOMRIGHT")
end

local function invisibleBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    return bar
end

-- Anchors the widgets to a health bar and layers them above it. Its level/strata can be secret in Forever;
-- then use a fixed level. matchStrata: a plate addon's bar (EllesmereUI, Platynator), drawn in a strata of its
-- own (EllesmereUI flattens its plate's children into one render layer; frames that set a strata are drawn
-- apart from it, ordered by level; Platynator's bars are MEDIUM, above the plate's WORLD). Set before the
-- levels: a strata change resets them.
local function attachWidgets(w, healthBar, matchStrata)
    w.healthBar = healthBar
    w.signature = nil -- the icon position is anchored to the bar in applyStyle
    w.marker:ClearAllPoints()
    w.marker:SetAllPoints(healthBar)

    local strataOf = matchStrata and healthBar or w.host
    local okStrata, strata = pcall(strataOf.GetFrameStrata, strataOf)
    if (matchStrata or w.strataSet) and okStrata and type(strata) == "string" and not isSecret(strata) then
        w.marker:SetFrameStrata(strata)
        w.iconWindow:SetFrameStrata(strata)
        w.iconBar:SetFrameStrata(strata)
        w.strataSet = true
    end
    local ok, level = pcall(healthBar.GetFrameLevel, healthBar)
    if not ok or isSecret(level) or type(level) ~= "number" then level = FALLBACK_LEVEL end
    -- The icon sits well above: plate decorations beside the bar (the level badge) must not cover it.
    w.marker:SetFrameLevel(level + 5)
    w.iconWindow:SetFrameLevel(level + 20)
    w.iconBar:SetFrameLevel(level + 21)
end

-- pooledHost: host is a plate addon's own pooled frame (EllesmereUI), not Blizzard's nameplate.
local function createWidgets(host, healthBar, pooledHost, matchStrata)
    local w = { host = host }

    -- Marker: filled from the bar's left edge to the remaining DoT damage, on the mob's (secret) health scale.
    w.marker = invisibleBar(host)
    w.span = w.marker:GetStatusBarTexture()
    w.fill = w.marker:CreateTexture(nil, "ARTWORK")
    coverSpan(w.fill, w.span)

    -- Per-DoT segments: running-total bars, each segment between the previous bar's fill end and its own.
    w.segments = {}
    for i = 1, MAX_SEGMENTS do
        local bar = invisibleBar(w.marker)
        bar:SetAllPoints(w.marker)
        local fillEnd = bar:GetStatusBarTexture()
        local texture = w.marker:CreateTexture(nil, "ARTWORK", nil, 1)
        if i == 1 then
            texture:SetPoint("TOPLEFT", w.marker, "TOPLEFT")
        else
            texture:SetPoint("TOPLEFT", w.segments[i - 1].fillEnd, "TOPRIGHT")
        end
        texture:SetPoint("BOTTOMRIGHT", fillEnd, "BOTTOMRIGHT")
        w.segments[i] = { bar = bar, fillEnd = fillEnd, texture = texture }
    end

    w.edges = {}
    for _, points in ipairs({ { true, "TOPLEFT", "TOPRIGHT" }, { true, "BOTTOMLEFT", "BOTTOMRIGHT" },
        { false, "TOPLEFT", "BOTTOMLEFT" }, { false, "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local edge = w.marker:CreateTexture(nil, "OVERLAY")
        edge:SetPoint(points[2], w.span, points[2])
        edge:SetPoint(points[3], w.span, points[3])
        if points[1] then edge:SetHeight(OUTLINE_THICKNESS) else edge:SetWidth(OUTLINE_THICKNESS) end
        table.insert(w.edges, { texture = edge, horizontal = points[1] })
    end

    -- Kill icon: a clipped window; the icon rides the end of a very long bar with max = current health and
    -- value = remaining damage, so it only slides into the window when damage >= health.
    w.iconWindow = CreateFrame("Frame", nil, host)
    w.iconWindow:SetClipsChildren(true)
    w.iconBar = invisibleBar(w.iconWindow)
    w.iconBar:SetPoint("RIGHT", w.iconWindow, "RIGHT")
    w.icon = w.iconBar:CreateTexture(nil, "OVERLAY")
    w.icon:SetPoint("RIGHT", w.iconBar:GetStatusBarTexture(), "RIGHT")

    -- The plate is pooled: a recycled one must not show the last mob's marker before our next update.
    if pooledHost then host:HookScript("OnHide", function() hideWidgets(w) end) end

    attachWidgets(w, healthBar, matchStrata)
    widgetsByHost[host] = w
    return w
end

-- Nameplates have their own look (plate* settings), separate from the target marker: enemy plates are red.
local STYLE_KEYS = {
    "plateFillTexture", "plateFillColor", "plateFillOpacity", "plateDotColors", "plateOutlineStyle",
    "plateDashLength", "plateOutlineThickness", "plateOutlineColor", "plateOutlineOpacity", "plateIcon",
    "nameplateIconSize", "nameplateIconPosition", "plateIconOffsetX", "plateIconOffsetY",
}

-- Pushes the look settings onto one plate's widgets when any of them changed since the last time.
local function applyStyle(w, db)
    local parts = {}
    for i, key in ipairs(STYLE_KEYS) do parts[i] = tostring(db[key]) end
    local signature = table.concat(parts, "|")
    if signature == w.signature then return end
    w.signature = signature

    local lists = ns.lists
    local style = ns.findById(lists.fills, db.plateFillTexture)
    local path = (style.path and not style.gradient) and style.path or nil
    local wrap = style.tiled and "REPEAT" or nil
    w.fill:SetShown(path ~= nil and db.plateDotColors == "single")
    if path then
        w.fill:SetTexture(path, wrap, wrap)
        w.fill:SetHorizTile(style.tiled or false)
        w.fill:SetVertTile(style.tiled or false)
        w.fill:SetVertexColor(ns.colorOf(db.plateFillColor, db.plateFillOpacity))
    end
    for _, segment in ipairs(w.segments) do
        segment.texture:SetTexture(path or WHITE, wrap, wrap)
        segment.texture:SetHorizTile(style.tiled or false)
        segment.texture:SetVertTile(style.tiled or false)
    end

    local r, g, b, a = ns.colorOf(db.plateOutlineColor, db.plateOutlineOpacity)
    for _, edge in ipairs(w.edges) do
        if db.plateOutlineStyle == "dashed" then
            local file = (edge.horizontal and "DashH" or "DashV") .. db.plateDashLength
            edge.texture:SetTexture(ns.textureDir .. file, "REPEAT", "REPEAT")
            edge.texture:SetHorizTile(edge.horizontal)
            edge.texture:SetVertTile(not edge.horizontal)
        else
            edge.texture:SetTexture(WHITE)
            edge.texture:SetHorizTile(false)
            edge.texture:SetVertTile(false)
        end
        if edge.horizontal then
            edge.texture:SetHeight(db.plateOutlineThickness)
        else
            edge.texture:SetWidth(db.plateOutlineThickness)
        end
        edge.texture:SetVertexColor(r, g, b, a)
        edge.texture:SetShown(db.plateOutlineStyle ~= "none")
    end

    local size = db.nameplateIconSize
    w.iconWindow:SetSize(size, size)
    w.iconBar:SetSize(ICON_BAR_LENGTH, size)
    w.icon:SetSize(size, size)
    w.icon:SetTexture(ns.findById(lists.icons, db.plateIcon).path)
    w.iconWindow:ClearAllPoints()
    local x, y = db.plateIconOffsetX, db.plateIconOffsetY
    if db.nameplateIconPosition == "left" then
        w.iconWindow:SetPoint("RIGHT", w.healthBar, "LEFT", -4 + x, y)
    elseif db.nameplateIconPosition == "above" then
        w.iconWindow:SetPoint("BOTTOM", w.healthBar, "TOP", x, 4 + y)
    else
        w.iconWindow:SetPoint("LEFT", w.healthBar, "RIGHT", 4 + x, y)
    end
end

-- Draws one plate's widgets. maxHealth and health may be secret (real plates) or plain (the options preview):
-- they only ever go into StatusBar min/max, never into Lua math. Returns false if drawing failed.
local function drawPlate(w, entries, total, maxHealth, health, db)
    applyStyle(w, db)
    local perDot = db.plateDotColors ~= "single"
    local count = perDot and math.min(#entries, MAX_SEGMENTS) or 0
    local ok = pcall(function()
        w.marker:SetMinMaxValues(0, maxHealth)
        w.marker:SetValue(total)
        local running = 0
        for i, segment in ipairs(w.segments) do
            local entry = entries[i]
            if i <= count then
                running = running + entry.damage
                -- The last segment also covers any DoTs beyond MAX_SEGMENTS.
                if i == count then running = total end
                local color = ns.dotColor(entry, db.plateDotColors)
                segment.texture:SetVertexColor(color[1], color[2], color[3], db.plateFillOpacity / 100)
            end
            segment.bar:SetMinMaxValues(0, maxHealth)
            segment.bar:SetValue(i <= count and running or total)
            segment.texture:SetShown(i <= count)
        end
        w.iconBar:SetMinMaxValues(0, health)
        w.iconBar:SetValue(total)
    end)
    if not ok then
        hideWidgets(w)
        return false
    end
    w.marker:SetShown(db.showMarkers)
    w.iconWindow:SetShown(db.nameplateMode == "markerIcon")
    return true
end

-- Widgets are made once per host and re-anchored when the host's bar changes (Blizzard swaps the bar under a
-- plate; Platynator reassigns its displays between units): frames can't be freed, so making new ones would leak.
local function widgetsFor(host, healthBar, pooledHost, matchStrata)
    local w = widgetsByHost[host]
    if not w then
        w = createWidgets(host, healthBar, pooledHost, matchStrata)
    elseif w.healthBar ~= healthBar then
        attachWidgets(w, healthBar, matchStrata)
    end
    return w
end

-- Hosts drawn this update; refreshPlates hides the widgets of every other one, except pinned hosts: those
-- another file draws on with these widgets (Focus.lua), which shows and hides them itself.
local seenHosts = {}
local pinnedHosts = {}

-- A dead mob keeps its plate for a moment, and its DoTs stay tracked until they expire.
local function unitIsDead(unit)
    local ok, dead = pcall(UnitIsDead, unit)
    return ok and not isSecret(dead) and dead
end

local function updatePlate(unit, plate, db)
    local entries, total = ns.dotBreakdownForUnit(unit)
    if total <= 0 or unitIsDead(unit) then return end
    local healthBar, host, path, addonBar, iconOnly = findHealthBar(plate, unit)
    if not healthBar or (not iconOnly and not barShown(healthBar)) then return end
    seenHosts[host] = true
    lastBarPath = path
    local w = widgetsFor(host, healthBar, host ~= plate, addonBar)
    if drawPlate(w, entries, total, UnitHealthMax(unit), UnitHealth(unit), db) and iconOnly then w.marker:Hide() end
end

-- The options window's mock nameplate: { plate, healthBar } plus its preview state ({ health, dots } in % of
-- max health), or nil. Drawn by the same code as real plates, with plain numbers.
local previewPlate, previewState

function ns.setPlatePreview(host, state)
    local old = previewPlate
    previewPlate, previewState = host, state
    if old and not host then
        local w = widgetsByHost[old.plate]
        if w then hideWidgets(w) end
    end
end

local function updatePreviewPlate(db)
    local entries, total = {}, 0
    for _, dot in ipairs(previewState.dots) do
        if dot.damage > 0 then
            table.insert(entries, dot)
            total = total + dot.damage
        end
    end
    local w = widgetsFor(previewPlate.plate, previewPlate.healthBar)
    if total <= 0 or db.nameplateMode == "off" then return hideWidgets(w) end
    drawPlate(w, entries, total, 100, math.max(previewState.health, 0.01), db)
end

local function refreshPlates()
    local db = ns.db
    wipe(seenHosts)
    if db and previewPlate and previewState then
        seenHosts[previewPlate.plate] = true
        updatePreviewPlate(db)
    end
    if db and db.nameplateMode ~= "off" and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        for i = 1, MAX_PLATES do
            local unit = "nameplate" .. i
            if UnitExists(unit) then
                local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
                local forbidden = ok and plate and plate.IsForbidden and plate:IsForbidden()
                if ok and plate and not forbidden then
                    updatePlate(unit, plate, db)
                end
            end
        end
    end
    for host, w in pairs(widgetsByHost) do
        if not seenHosts[host] and not pinnedHosts[host] then hideWidgets(w) end
    end
end

-- The same marker and kill icon on another health bar (Focus.lua). Widgets live on `host`, made once and
-- re-anchored when the bar changes; draw takes the breakdown, max health and health (secret or plain).
ns.barMarker = {
    pin = function(host) pinnedHosts[host] = true end,
    widgetsFor = widgetsFor,
    draw = drawPlate,
    hide = hideWidgets,
    -- Puts the widgets in `strata`, just above `level` (a frame's top layer, when its bar's own isn't enough).
    layer = function(w, strata, level)
        w.marker:SetFrameStrata(strata)
        w.iconWindow:SetFrameStrata(strata)
        w.iconBar:SetFrameStrata(strata)
        w.strataSet = true
        w.marker:SetFrameLevel(level + 5)
        w.iconWindow:SetFrameLevel(level + 20)
        w.iconBar:SetFrameLevel(level + 21)
    end,
}

local driver = CreateFrame("Frame")
local sinceUpdate = 0
local reportedError = false
driver:SetScript("OnUpdate", function(_, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < UPDATE_INTERVAL then return end
    sinceUpdate = 0
    local ok, err = pcall(refreshPlates)
    if not ok and not reportedError and ns.trace then
        reportedError = true
        ns.trace("ERROR in nameplate update: " .. tostring(err))
        ns.print("Nameplate display error (logged): " .. tostring(err))
    end
end)

local function testBar(i)
    if not testBars[i] then
        local bar = CreateFrame("StatusBar", nil, UIParent)
        bar:SetSize(TEST_BAR_WIDTH, TEST_BAR_HEIGHT)
        bar:SetStatusBarTexture(WHITE)
        bar:SetStatusBarColor(1, 0, 1, 1)
        bar:SetFrameStrata("HIGH")
        local back = bar:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:SetColorTexture(0, 0, 0, 0.8)
        bar:Hide()
        testBars[i] = bar
    end
    return testBars[i]
end

local hider = CreateFrame("Frame")
hider:Hide()
hider:SetScript("OnUpdate", function(self)
    if GetTime() < hideTestBarsAt then return end
    for _, bar in ipairs(testBars) do bar:Hide() end
    self:Hide()
end)

-- Checks one nameplate unit; returns a log line and whether the test bar could be shown.
local function probePlate(unit, index)
    local parts = { unit }
    table.insert(parts, "guid=" .. call(UnitGUID, unit))
    -- What DoTs on it are tracked under: its GUID, "plate:nameplateN" (secret GUID, e.g. instances) or nil.
    table.insert(parts, "key=" .. tostring(ns.tracking and ns.tracking.unitKey(unit)))
    table.insert(parts, "attackable=" .. call(UnitCanAttack, "player", unit))
    table.insert(parts, "health=" .. call(UnitHealth, unit))
    table.insert(parts, "max=" .. call(UnitHealthMax, unit))

    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        table.insert(parts, "plate API missing")
        return table.concat(parts, " "), false
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok then
        table.insert(parts, "plate: error " .. tostring(plate))
        return table.concat(parts, " "), false
    end
    if not plate then
        table.insert(parts, "plate: nil")
        return table.concat(parts, " "), false
    end
    local forbidden = plate.IsForbidden and plate:IsForbidden()
    table.insert(parts, "forbidden=" .. tostring(forbidden))
    if forbidden then return table.concat(parts, " "), false end

    local healthBar, host, path = findHealthBar(plate, unit)
    table.insert(parts, "healthBar=" .. path)
    if healthBar then
        table.insert(parts, "barForbidden=" .. tostring(healthBar.IsForbidden and healthBar:IsForbidden() or false))
        table.insert(parts, "barShown=" .. tostring(barShown(healthBar)))
        table.insert(parts, "barStrata=" .. call(healthBar.GetFrameStrata, healthBar))
        table.insert(parts, "barRect=" .. call(healthBar.GetRect, healthBar))
        table.insert(parts, "barScale=" .. call(healthBar.GetEffectiveScale, healthBar))
    end
    -- Platynator: which display frames we know of, and which unit each shows.
    if Platynator then
        pcall(scanPlatyDisplays, plate)
        local known, units = 0, {}
        for display in pairs(platyDisplays) do
            known = known + 1
            if display.unit then table.insert(units, tostring(display.unit) .. (display:IsShown() and "" or "(hidden)")) end
        end
        table.insert(parts, "platyDisplays=" .. known .. " units=" .. table.concat(units, ","))
        local childCount = select("#", plate:GetChildren())
        table.insert(parts, "plateChildren=" .. childCount)
    end
    local w = host and widgetsByHost[host]
    if w then
        table.insert(parts, "markerRect=" .. call(w.marker.GetRect, w.marker))
        table.insert(parts, "markerOnBar=" .. tostring(w.healthBar == healthBar))
    end

    local bar = testBar(index)
    bar:ClearAllPoints()
    local anchorOK, anchorErr = pcall(bar.SetPoint, bar, "BOTTOM", plate, "TOP", 0, 2)
    table.insert(parts, "anchorPlate=" .. (anchorOK and "ok" or ("error " .. tostring(anchorErr))))
    if healthBar then
        local probeAnchor = testBar(MAX_PLATES + 1)
        probeAnchor:ClearAllPoints()
        local ok2, err2 = pcall(probeAnchor.SetPoint, probeAnchor, "TOPLEFT", healthBar, "TOPLEFT")
        table.insert(parts, "anchorHealthBar=" .. (ok2 and "ok" or ("error " .. tostring(err2))))
        probeAnchor:ClearAllPoints()
        probeAnchor:Hide()
    end
    local feedOK, feedErr = pcall(function()
        bar:SetMinMaxValues(0, UnitHealthMax(unit))
        bar:SetValue(UnitHealth(unit))
    end)
    table.insert(parts, "feedHealth=" .. (feedOK and "ok" or ("error " .. tostring(feedErr))))

    local shown = anchorOK and feedOK
    if shown then bar:Show() end
    return table.concat(parts, " "), shown
end

function ns.probeNameplates()
    local inInstance, instanceType = IsInInstance()
    ns.trace(string.format("PLATES probe: C_NamePlate=%s GetNamePlateForUnit=%s instance=%s (%s) inCombat=%s",
        tostring(C_NamePlate ~= nil), tostring(C_NamePlate ~= nil and C_NamePlate.GetNamePlateForUnit ~= nil),
        tostring(inInstance), tostring(instanceType), call(UnitAffectingCombat, "player")))
    for _, bar in ipairs(testBars) do bar:Hide() end

    local found, shown = 0, 0
    for i = 1, MAX_PLATES do
        local unit = "nameplate" .. i
        if UnitExists(unit) then
            found = found + 1
            local line, ok = probePlate(unit, found)
            ns.trace("PLATES " .. line)
            if ok then shown = shown + 1 end
        end
    end

    hideTestBarsAt = GetTime() + TEST_SECONDS
    hider:Show()
    ns.trace(string.format("PLATES probe done: %d nameplates, %d test bars shown", found, shown))
    ns.print(string.format("Nameplate probe: %d nameplates found, %d magenta test bars shown for %d seconds. "
        .. "Results are in the log (/reload to save it).", found, shown, TEST_SECONDS))
end
