-- DoesItDie execute range: the probe (/did exec) for showing when the target is below a health percentage
-- (Execute and Hammer of Wrath: 20%). Target health is secret, so two ways are tested side by side:
--
--  A. Geometry, like the kill icon: a very long invisible StatusBar with max = max health and value = health.
--     A clipping frame covers only its empty part (from the fill's end to the bar's end), and the icon sits at
--     the threshold's position on the bar, inside that frame, so it's visible only when the fill ends before
--     it: health < threshold. Works if a frame anchored to a secret-sized texture still clips correctly.
--  B. Midnight's UnitHealthPercent with a step color curve (opaque below the threshold, transparent above),
--     applied to the icon's color. Only if Forever has these APIs; the probe logs what exists.
--  C. Not execute: a test of the kill icon done with a curve instead of the clipped-StatusBar trick. A step
--     curve in raw health (opaque up to the remaining DoT damage, transparent above) is evaluated with the
--     secret UnitHealth("target") and the result goes to SetAlpha (float curve) or, failing that, to
--     SetVertexColor (color curve). Should light up exactly when the real kill icon on the portrait does.
--
-- The icons show above the target frame until /did exec is typed again. Compare A and B with the target's
-- health as it drops past the threshold, and C with the real kill icon.

local ADDON_NAME, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICON = "Interface\\Icons\\INV_Sword_48"
local BAR_LENGTH = 50000 -- icon A slides in over ICON_SIZE / BAR_LENGTH (~0.05%) of health at the threshold
local ICON_SIZE = 24
local UPDATE_INTERVAL = 0.1
local DEFAULT_THRESHOLD = 20

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

local function keysOf(t)
    if type(t) ~= "table" then return type(t) end
    local keys = {}
    for k in pairs(t) do table.insert(keys, tostring(k)) end
    table.sort(keys)
    return "{" .. table.concat(keys, ",") .. "}"
end

local function rectOf(region)
    local ok, left, bottom, width, height = pcall(region.GetRect, region)
    if not ok then return "error" end
    if left == nil then return "no rect" end
    if isSecret(left) or isSecret(width) then return "secret" end
    return string.format("%.0f,%.0f %.0fx%.0f", left, bottom, width, height)
end

---------------------------------------------------------------------------
-- Probe widgets
---------------------------------------------------------------------------

local holder = CreateFrame("Frame", "DoesItDieExecuteProbe", UIParent)
holder:SetSize(ICON_SIZE * 3 + 32, ICON_SIZE + 14)
holder:SetFrameStrata("HIGH")
holder:Hide()

-- Hidden without a target; the holder keeps running the update.
local content = CreateFrame("Frame", nil, holder)
content:SetAllPoints()

local function slot(point, label)
    local frame = CreateFrame("Frame", nil, content)
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetPoint(point, content, point, 0, 7)
    local back = frame:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.35) -- shows where the icon would be
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOP", frame, "BOTTOM", 0, -1)
    text:SetText(label)
    return frame
end

-- A: geometry. The bar's threshold point is placed at the slot's right edge (see setThreshold).
local slotA = slot("LEFT", "A")
local bar = CreateFrame("StatusBar", nil, content)
bar:SetStatusBarTexture(WHITE)
bar:SetStatusBarColor(0, 0, 0, 0)
bar:SetSize(BAR_LENGTH, ICON_SIZE)
local emptyPart = CreateFrame("Frame", nil, bar)
emptyPart:SetClipsChildren(true)
emptyPart:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
emptyPart:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
local iconA = emptyPart:CreateTexture(nil, "OVERLAY")
iconA:SetTexture(ICON)
iconA:SetAllPoints(slotA)

-- B: health percent through a color curve.
local slotB = slot("RIGHT", "B")
local iconB = slotB:CreateTexture(nil, "OVERLAY")
iconB:SetTexture(ICON)
iconB:SetAllPoints()

-- C: kill icon through a curve on raw health.
local slotC = slot("CENTER", "C")
local iconC = slotC:CreateTexture(nil, "OVERLAY")
iconC:SetTexture(ICON)
iconC:SetAllPoints()

local active = false
local threshold = DEFAULT_THRESHOLD
local curve -- nil if the curve APIs are missing
local reportedA, reportedB -- first error of each method, logged once per probe

local function setThreshold(percent)
    threshold = percent
    bar:ClearAllPoints()
    bar:SetPoint("LEFT", slotA, "RIGHT", -BAR_LENGTH * percent / 100, 0)
end

-- UnitHealthPercent may be 0-1 or 0-100; the player's own percent (if readable) tells which.
local function percentScale()
    local ok, p = pcall(UnitHealthPercent, "player")
    if ok and type(p) == "number" and not isSecret(p) and p > 1.001 then return 100 end
    return 1
end

local function buildCurve()
    if type(UnitHealthPercent) ~= "function" then return nil, "UnitHealthPercent missing" end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then
        return nil, "curve API missing"
    end
    local at = threshold / 100 * percentScale()
    local ok, result = pcall(function()
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, CreateColor(1, 1, 1, 1))
        c:AddPoint(at, CreateColor(1, 1, 1, 0))
        return c
    end)
    if not ok then return nil, "error: " .. tostring(result) end
    return result, "threshold point at " .. at
end

-- Alpha the curve gives at x (plain numbers, so readable), to check the step direction.
local function curveAlphaAt(x)
    return describe(pcall(function()
        local color = curve:Evaluate(x)
        return type(color) == "table" and color.a or color
    end))
end

local function updateA()
    local ok, err = pcall(function()
        bar:SetMinMaxValues(0, UnitHealthMax("target"))
        bar:SetValue(UnitHealth("target"))
    end)
    if not ok and not reportedA then
        reportedA = true
        ns.trace("EXEC A feed error: " .. tostring(err))
    end
end

local function updateB()
    if not curve then
        iconB:Hide()
        return
    end
    local ok, err = pcall(function()
        local color = UnitHealthPercent("target", false, curve)
        iconB:SetVertexColor(color:GetRGBA())
    end)
    iconB:SetShown(ok)
    if not ok and not reportedB then
        reportedB = true
        ns.trace("EXEC B error: " .. tostring(err))
    end
end

-- C state: the curve is rebuilt only when the (rounded) remaining damage changes. killMode is "alpha" (float
-- curve into SetAlpha), "color" (color curve into SetVertexColor) or nil once both have failed.
local killCurve, killDamage, killMode
local killReported = {} -- trace lines already logged this probe, so each finding is logged once

local function traceOnce(key, line)
    if killReported[key] then return end
    killReported[key] = true
    ns.trace("EXEC C " .. line)
end

-- Step curve: the kill value up to the damage, the "survives" value above it. Health is whole numbers, so the
-- step sits half a point past the damage (health == damage dies).
local function buildKillCurve(mode, damage)
    return pcall(function()
        if mode == "alpha" then
            local c = C_CurveUtil.CreateCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, 1)
            c:AddPoint(damage + 0.5, 0)
            return c
        end
        local c = C_CurveUtil.CreateColorCurve()
        c:SetType(Enum.LuaCurveType.Step)
        c:AddPoint(0, CreateColor(1, 1, 1, 1))
        c:AddPoint(damage + 0.5, CreateColor(1, 1, 1, 0))
        return c
    end)
end

-- Evaluates the curve with the target's health and applies it. Errors propagate to the caller's pcall.
local function applyKill(mode, c)
    local health = UnitHealth("target")
    local value = c:Evaluate(health)
    traceOnce("eval-" .. mode, string.format("%s: Evaluate(health secret=%s) -> %s (%s)", mode,
        tostring(isSecret(health)), isSecret(value) and "secret" or tostring(value), type(value)))
    if mode == "alpha" then
        iconC:SetAlpha(value)
    else
        iconC:SetVertexColor(value:GetRGBA())
    end
    traceOnce("apply-" .. mode, mode .. ": applied without error")
end

local function updateC()
    if not killMode then
        iconC:Hide()
        return
    end
    local _, total = ns.dotBreakdownForUnit("target")
    local damage = math.floor((total or 0) + 0.5)
    if damage <= 0 then
        iconC:Hide()
        killDamage = nil
        return
    end
    if damage ~= killDamage then
        local ok, result = buildKillCurve(killMode, damage)
        if not ok then
            traceOnce("build-" .. killMode, killMode .. " curve error: " .. tostring(result))
            killMode = killMode == "alpha" and "color" or nil
            killDamage = nil
            return
        end
        killCurve, killDamage = result, damage
        traceOnce("built-" .. killMode, string.format("%s curve built, step at %.1f; plain check: alpha at "
            .. "%d=%s, at %d=%s", killMode, damage + 0.5, damage, describe(pcall(killCurve.Evaluate, killCurve,
            damage)), damage + 1, describe(pcall(killCurve.Evaluate, killCurve, damage + 1))))
    end
    iconC:Show()
    local ok, err = pcall(applyKill, killMode, killCurve)
    if not ok then
        traceOnce("error-" .. killMode, killMode .. " error: " .. tostring(err))
        iconC:SetAlpha(1)
        iconC:SetVertexColor(1, 1, 1, 1)
        killMode = killMode == "alpha" and "color" or nil
        killDamage = nil
    end
end

local sinceUpdate = 0
holder:SetScript("OnUpdate", function(self, elapsed)
    sinceUpdate = sinceUpdate + elapsed
    if sinceUpdate < UPDATE_INTERVAL then return end
    sinceUpdate = 0
    if not UnitExists("target") then
        content:Hide()
        return
    end
    content:Show()
    updateA()
    updateB()
    updateC()
end)

local function traceGeometry()
    ns.trace("EXEC geometry: holder " .. rectOf(holder) .. " | slot A " .. rectOf(slotA) .. " | bar " .. rectOf(bar)
        .. " | fill " .. rectOf(bar:GetStatusBarTexture()) .. " | empty part " .. rectOf(emptyPart)
        .. " | icon A visible=" .. tostring(iconA:IsVisible()) .. " | icon B visible=" .. tostring(iconB:IsVisible())
        .. " | icon C visible=" .. tostring(iconC:IsVisible()))
end

local function start(percent)
    setThreshold(percent)
    reportedA, reportedB = false, false
    holder:ClearAllPoints()
    if not (TargetFrame and pcall(holder.SetPoint, holder, "BOTTOM", TargetFrame, "TOP", 0, 4)) then
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end

    ns.trace(string.format("EXEC probe at %d%%: UnitHealthPercent=%s UnitHealthMissing=%s C_CurveUtil=%s "
        .. "LuaCurveType=%s CurveConstants=%s inCombat=%s", percent, type(UnitHealthPercent),
        type(UnitHealthMissing), keysOf(C_CurveUtil), keysOf(Enum and Enum.LuaCurveType), keysOf(CurveConstants),
        call(UnitAffectingCombat, "player")))
    ns.trace("EXEC percents: target=" .. call(UnitHealthPercent, "target") .. " player="
        .. call(UnitHealthPercent, "player") .. " target missing=" .. call(UnitHealthMissing, "target"))
    local note
    curve, note = buildCurve()
    ns.trace("EXEC curve: " .. note)
    if curve then
        ns.trace(string.format("EXEC curve alpha at 0.1=%s 0.5=%s 10=%s 50=%s",
            curveAlphaAt(0.1), curveAlphaAt(0.5), curveAlphaAt(10), curveAlphaAt(50)))
    end

    wipe(killReported)
    killCurve, killDamage = nil, nil
    if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
        killMode = "alpha"
    elseif C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType then
        killMode = "color"
    else
        killMode = nil
    end
    ns.trace("EXEC C kill curve mode: " .. tostring(killMode))

    active = true
    holder:Show()
    C_Timer.After(0.5, traceGeometry)
    ns.print(string.format("Execute probe on at %d%%. Above the target frame, icons A (geometry) and B (health "
        .. "percent) should appear only while the target is below %d%%; C (middle, kill icon via curve) only "
        .. "while the real kill icon shows. /did exec to stop, /reload to save the log.", percent, percent))
end

-- /did exec [percent]: starts the probe, changes its threshold, or (with no percent) stops it.
function ns.toggleExecuteProbe(percent)
    if active and not percent then
        active = false
        holder:Hide()
        ns.trace("EXEC probe off")
        ns.print("Execute probe off.")
        return
    end
    start(math.max(1, math.min(99, percent or threshold)))
end
