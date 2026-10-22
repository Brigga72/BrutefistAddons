-- DoesItDie custom frames: lets the marker and kill icon attach to another addon's target frame (unit frame
-- replacements) instead of Blizzard's, which those addons hide. Advanced options, off by default; known
-- replacements (EllesmereUI's) are used without a setting.
--
-- A setting holds a frame path: a global frame name, optionally followed by keys, e.g. "MyTargetFrame.Health".
-- The options' "Pick" button fills one in from the frame under the mouse. The marker only needs the health
-- bar's rectangle (it's laid over it, filling left to right on the same max-health scale), so any bar that fills
-- left to right and whose frame is exactly the fill area works.

local _, ns = ...

-- Blizzard's own frames answer some queries with secret values (IsMouseOver on the target frame's textures,
-- in and out of combat): anything read from a frame we don't own is checked before use.
local function isSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r or false
end

-- A plain value from region:method(), or nil if it errors or is secret.
local function plain(region, method)
    local fn = region[method]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, region)
    if not ok or isSecret(value) then return nil end
    return value
end

-- Frame path -> the frame (or texture), or nil if it doesn't exist (yet: some addons build frames late).
function ns.resolveFramePath(path)
    if type(path) ~= "string" then return nil end
    path = strtrim(path)
    if path == "" then return nil end
    local ok, object = pcall(function()
        local object
        for part in path:gmatch("[^%.]+") do
            if object == nil then
                object = _G[part]
            elseif type(object) == "table" then
                object = object[part]
            else
                return nil
            end
        end
        return object
    end)
    if ok and type(object) == "table" and type(object.GetObjectType) == "function"
        and type(object.GetWidth) == "function" then
        return object
    end
end

-- The key under which `parent` holds `region`, if it's a plain identifier.
local function keyInParent(region, parent)
    local key = plain(region, "GetParentKey")
    if type(key) == "string" and parent[key] == region then return key end
    for k, v in pairs(parent) do
        if v == region and type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
    end
end

-- A path that finds `region` again after a reload, or nil if it has no named ancestor to start from.
function ns.framePath(region)
    local parts, current = {}, region
    for _ = 1, 12 do
        local name = plain(current, "GetName")
        if type(name) == "string" and not name:find(".", 1, true) and _G[name] == current then
            table.insert(parts, 1, name)
            return table.concat(parts, ".")
        end
        local parent = plain(current, "GetParent")
        if not parent then return nil end
        local key = keyInParent(current, parent)
        if not key then return nil end
        table.insert(parts, 1, key)
        current = parent
    end
end

-- The top-level frame `region` belongs to (its ancestor just below UIParent), for layering.
function ns.frameRoot(region)
    local current = region
    for _ = 1, 20 do
        local parent = plain(current, "GetParent")
        if not parent or parent == UIParent then return current end
        current = parent
    end
    return current
end

-- Replacement target frames used without a setting: the frame's global name, its health bar and portrait keys,
-- and whose it is. Each only exists while its addon draws its own target frame (EllesmereUI creates its frame
-- only when its target frame is enabled).
local KNOWN_TARGET_FRAMES = {
    { frame = "EllesmereUIUnitFrames_Target", bar = "Health", portrait = "Portrait", owner = "EllesmereUI's" },
}

-- The same for the focus frame (Focus.lua): only its health bar is needed. EllesmereUI's path verified in-game by
-- a user (issue #12).
local KNOWN_FOCUS_FRAMES = {
    { frame = "EllesmereUIUnitFrames_Focus", bar = "Health", owner = "EllesmereUI's" },
}

-- A known replacement focus frame that's there: its health bar and whose it is, else nil.
function ns.knownFocusFrame()
    for _, known in ipairs(KNOWN_FOCUS_FRAMES) do
        local bar = ns.resolveFramePath(known.frame .. "." .. known.bar)
        if bar then return bar, known.owner end
    end
end

-- Whether `region` and its ancestors below `root` are shown. The root itself is left out: a target frame hides
-- while there's no target.
local function shownBelow(region, root)
    local current = region
    for _ = 1, 20 do
        if current == nil or current == root then return true end
        if plain(current, "IsShown") == false then return false end
        current = plain(current, "GetParent")
    end
    return true
end

-- A known replacement target frame that's there: its health bar, its portrait if it's shown (EllesmereUI
-- hides its portrait when portraits are off), and whose it is ("EllesmereUI's"). Nil if none is there.
function ns.knownTargetFrame()
    for _, known in ipairs(KNOWN_TARGET_FRAMES) do
        local root = ns.resolveFramePath(known.frame)
        local bar = root and ns.resolveFramePath(known.frame .. "." .. known.bar)
        if bar then
            local portrait = ns.resolveFramePath(known.frame .. "." .. known.portrait)
            if portrait and not shownBelow(portrait, root) then portrait = nil end
            return bar, portrait, known.owner
        end
    end
end

---------------------------------------------------------------------------
-- Pick mode
---------------------------------------------------------------------------

-- Health bars usually don't take the mouse themselves (the unit button around them does), so the mouse focus
-- only says which frame the cursor is on. Pick searches that frame's whole top-level frame for what's under
-- the cursor and takes the smallest match: a StatusBar for "bar", any frame or texture for "anchor".

local MIN_ANCHOR_SIZE = 12
local picker -- { kind, onPick, candidate }
local pickFrame, highlight, pickLabel

local function mouseFocus()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    end
    if GetMouseFocus then return GetMouseFocus() end
end

-- The region's rectangle in its own coordinates, or nil if it has none or any part of it is secret.
local function plainRect(region)
    local ok, left, bottom, width, height = pcall(region.GetRect, region)
    if not ok or type(left) ~= "number" then return nil end
    for _, v in ipairs({ left, bottom, width, height }) do
        if isSecret(v) or type(v) ~= "number" then return nil end
    end
    return left, bottom, width, height
end

-- Width and height of a visible region under the cursor, else nil. IsMouseOver is secret on some of Blizzard's
-- frames; then the cursor is checked against the rectangle, if that's readable.
local function areaUnderMouse(region)
    if plain(region, "IsVisible") ~= true then return nil end
    local left, bottom, width, height = plainRect(region)
    if not left then return nil end
    local over = plain(region, "IsMouseOver")
    if over == nil then
        local scale = plain(region, "GetEffectiveScale")
        if type(scale) ~= "number" or scale <= 0 then return nil end
        local x, y = GetCursorPosition()
        x, y = x / scale, y / scale
        over = x >= left and x <= left + width and y >= bottom and y <= bottom + height
    end
    if not over then return nil end
    return width, height
end

local function findCandidate(kind)
    local focus = mouseFocus()
    if not focus or focus == WorldFrame or focus == pickFrame then return nil end
    local root = ns.frameRoot(focus)
    local best, bestArea
    local function consider(region, isBar)
        if kind == "bar" and not isBar then return end
        local width, height = areaUnderMouse(region)
        if not width then return end
        if kind == "anchor" and (width < MIN_ANCHOR_SIZE or height < MIN_ANCHOR_SIZE) then return end
        local area = width * height
        if not bestArea or area < bestArea then best, bestArea = region, area end
    end
    local function visit(frame, depth)
        consider(frame, plain(frame, "GetObjectType") == "StatusBar")
        if kind == "anchor" then
            for _, region in ipairs({ frame:GetRegions() }) do
                if plain(region, "GetObjectType") == "Texture" then consider(region, false) end
            end
        end
        if depth < 8 then
            for _, child in ipairs({ frame:GetChildren() }) do visit(child, depth + 1) end
        end
    end
    visit(root, 0)
    return best
end

local function stopPicking()
    picker = nil
    if pickFrame then pickFrame:Hide() end
end
ns.stopFramePick = stopPicking

local function describe(region)
    local path = ns.framePath(region)
    return path, path or "(this frame has no name to save)"
end

local function createPickFrame()
    pickFrame = CreateFrame("Frame", nil, UIParent)
    pickFrame:SetFrameStrata("TOOLTIP")
    pickFrame:Hide()

    highlight = CreateFrame("Frame", nil, pickFrame)
    highlight:SetFrameStrata("TOOLTIP")
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = highlight:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0.2, 1, 0.3, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetHeight(2)
            edge:SetPoint(side .. "LEFT")
            edge:SetPoint(side .. "RIGHT")
        else
            edge:SetWidth(2)
            edge:SetPoint("TOP" .. side)
            edge:SetPoint("BOTTOM" .. side)
        end
    end
    local fill = highlight:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetColorTexture(0.2, 1, 0.3, 0.15)

    pickLabel = pickFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pickLabel:SetPoint("TOP", UIParent, "TOP", 0, -120)

    local function update()
        local candidate = findCandidate(picker.kind)
        picker.candidate = candidate
        highlight:ClearAllPoints()
        if candidate then
            highlight:SetAllPoints(candidate)
            highlight:Show()
        else
            highlight:Hide()
        end
        local what = picker.kind == "bar" and "the target's health bar" or "where the kill icon should go"
        local text = candidate and select(2, describe(candidate)) or "nothing under the mouse"
        pickLabel:SetText("DoesItDie: click " .. what .. " (right-click to cancel)\n|cff33ff4d" .. text .. "|r")
    end

    -- Runs 20 times a second over frames we don't own: an error stops picking (reported once) instead of
    -- repeating.
    local sinceCheck = 0
    pickFrame:SetScript("OnUpdate", function(_, elapsed)
        sinceCheck = sinceCheck + elapsed
        if not picker or sinceCheck < 0.05 then return end
        sinceCheck = 0
        local ok, err = pcall(update)
        if not ok then
            stopPicking()
            ns.trace("ERROR in frame pick: " .. tostring(err))
            ns.print("Frame pick stopped after an error (logged). You can still type a frame name.")
        end
    end)

    -- The click that picks. (GLOBAL_MOUSE_DOWN may not exist on every client; the options explain typing a path.)
    pcall(pickFrame.RegisterEvent, pickFrame, "GLOBAL_MOUSE_DOWN")
    pickFrame:SetScript("OnEvent", function(_, _, button)
        if not picker then return end
        local current = picker
        stopPicking()
        if button == "RightButton" then
            ns.print("Frame pick cancelled.")
            return
        end
        if not current.candidate then
            ns.print("Nothing to pick there.")
            return
        end
        local path = ns.framePath(current.candidate)
        if not path then
            ns.print("That frame has no name to save, so it can't be found again after a reload. Try the frame "
                .. "around it, or type a path.")
            return
        end
        current.onPick(path)
    end)
end

-- kind: "bar" or "anchor". onPick(path) runs when a saveable frame is clicked. (The Pick button's own click
-- can't count: its mouse-down came before this.)
function ns.startFramePick(kind, onPick)
    if not pickFrame then createPickFrame() end
    picker = { kind = kind, onPick = onPick }
    pickFrame:Show()
end
