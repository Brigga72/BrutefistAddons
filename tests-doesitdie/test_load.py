"""Smoke test: loads the whole addon (every file in the .toc) in Lua with a fake WoW environment, then drives it
like a player: ADDON_LOADED, /did, every tab, every preset, checkboxes, sliders, dropdowns, Simulate fight,
closing the window. Fails on any Lua error and checks a few results.

    pip install lupa
    python tools/test_load.py

The fake frames accept any method (unknown ones do nothing) and record what matters: scripts, text, values,
shown state. It catches runtime mistakes (nil calls, typos, wrong arguments to our own functions), not
visual ones.
"""
import os
import sys

import locale  # noqa: E402
locale.setlocale(locale.LC_CTYPE, "C")  # as in WoW: Lua's %d and %s follow the C library's locale
from lupa.lua51 import LuaRuntime  # WoW runs Lua 5.1

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "addons", "DoesItDie")

FAKE_WOW = r"""
now = 1000
chat = {}
frames = {}
tickers = {}

local methods = {}
local function mock(kind, parent)
    local o = { kind = kind, parent = parent, scripts = {}, shown = true, width = 100, height = 20, children = {} }
    if parent and type(parent) == "table" and parent.children then table.insert(parent.children, o) end
    table.insert(frames, o)
    -- Unknown methods (CamelCase, like WoW's) do nothing; unknown fields are nil like a real table.
    return setmetatable(o, { __index = function(t, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:match("^%u") then return function() end end
    end })
end
FakeMock = mock

function methods.SetScript(self, name, fn) self.scripts[name] = fn end
function methods.GetScript(self, name) return self.scripts[name] end
function methods.HookScript(self, name, fn) self.scripts[name] = fn end
function methods.Show(self)
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods.Hide(self)
    local was = self.shown
    self.shown = false
    if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function methods.IsShown(self) return self.shown end
function methods.GetObjectType(self) return self.kind end
function methods.IsVisible(self)
    if not self.shown then return false end
    local parent = self.parent
    if type(parent) == "table" and parent.shown ~= nil then return methods.IsVisible(parent) end
    return true
end
function methods.SetText(self, t) self.text = t end
function methods.GetText(self) return self.text end
function methods.SetSize(self, w, h) self.width, self.height = w, h end
function methods.SetWidth(self, w) self.width = w end
function methods.SetHeight(self, h) self.height = h end
function methods.GetWidth(self) return self.width end
function methods.GetHeight(self) return self.height end
function methods.GetStringWidth(self) return #(self.text or "") * 6 end
function methods.GetFont(self) return "Fonts\\FRIZQT__.TTF", 12, "" end
function methods.SetFrameStrata(self, v) self.strata = v end
function methods.GetFrameStrata(self) return self.strata or "MEDIUM" end
function methods.SetFrameLevel(self, v) self.level = v end
function methods.GetFrameLevel(self) return self.level or 5 end
function methods.GetChildren(self) return end
function methods.SetClipsChildren(self, v) self.clips = v end
function methods.IsMouseOver(self) return false end
function methods.GetStatusBarTexture(self) self._tex = self._tex or mock("tex", self); return self._tex end
function methods.GetThumbTexture(self) self._thumb = self._thumb or mock("thumb", self); return self._thumb end
function methods.CreateTexture(self) return mock("texture", self) end
function methods.CreateMaskTexture(self) return mock("mask", self) end
function methods.CreateFontString(self) return mock("fontstring", self) end
function methods.CreateAnimationGroup(self) return mock("animgroup", self) end
function methods.CreateAnimation(self) return mock("anim", self) end
function methods.SetChecked(self, v) self.checked = v end
function methods.GetChecked(self) return self.checked end
function methods.SetMinMaxValues(self, a, b) self.min, self.max = a, b end
function methods.GetMinMaxValues(self) return self.min, self.max end
function methods.SetValue(self, v)
    if self.min and type(v) == "number" then v = math.max(self.min, math.min(self.max, v)) end
    self.value = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end
end
function methods.GetValue(self) return self.value or 0 end
function methods.RegisterEvent(self, e) self.events = self.events or {}; self.events[e] = true end
function methods.RegisterUnitEvent(self, e) self.events = self.events or {}; self.events[e] = true end
function methods.GetDebugName(self) return self.name or "mock" end
function methods.GetName(self) return self.name end
function methods.GetParent(self) return self.parent end
function methods.SetAllPoints(self, target) self.allPoints = target end

function CreateFrame(kind, name, parent, template)
    local f = mock(kind, parent)
    f.name, f.template = name, template
    if kind ~= "Frame" or name then f.shown = true end
    if name then _G[name] = f end
    return f
end
UIParent = mock("UIParent")
GameTooltip = mock("GameTooltip")
GameFontNormalSmall = mock("font")
DEFAULT_CHAT_FRAME = mock("chat")
function DEFAULT_CHAT_FRAME.AddMessage(self, msg) table.insert(chat, msg) end
SlashCmdList = {}
UISpecialFrames = {}
Settings = {
    RegisterCanvasLayoutCategory = function() return mock("category") end,
    RegisterAddOnCategory = function() end,
}
C_Timer = {
    After = function(t, fn) end,
    NewTicker = function(t, fn)
        local ticker = { fn = fn, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        table.insert(tickers, ticker)
        return ticker
    end,
}
local SPELLS = {
    [172] = { "Corruption", "Corrupts the target, causing 40 Shadow damage over 12 sec." },
    [348] = { "Immolate", "Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec." },
}
C_Spell = {
    GetSpellName = function(id) return SPELLS[id] and SPELLS[id][1] or "Spell" end,
    GetSpellDescription = function(id) return SPELLS[id] and SPELLS[id][2] or "" end,
}
Enum = { PowerType = { ComboPoints = 4 } }
function GetTime() return now end
targetGuid = nil -- set later: the target and nameplate1 are then the same mob
function UnitExists(unit) return unit == "nameplate1" or (unit == "target" and targetGuid ~= nil) end
function UnitCanAttack() return true end
function IsInInstance() return false, "none" end
local plate = mock("Frame")
FakePlate = plate
plate.UnitFrame = mock("Frame", plate)
plate.UnitFrame.healthBar = mock("StatusBar", plate.UnitFrame)
C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "nameplate1" then return plate end end }
function UnitGUID(unit) if unit == "target" or unit == "nameplate1" then return targetGuid end end
function UnitIsDead() return false end
combat = false
function UnitAffectingCombat() return combat end
function InCombatLockdown() return combat end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function hooksecurefunc() end
function HideUIPanel() end
function CreateColor(...) return { ... } end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strlower(s) return string.lower(s) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function date() return "12:00:00" end
unpack = unpack or table.unpack
"""

HELPERS = r"""
local H = {}
function H.load(path, src, ns)
    local fn, err = (loadstring or load)(src, "@" .. path)
    if not fn then error(err) end
    fn("DoesItDie", ns)
end
function H.fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
function H.update(elapsed)
    now = now + elapsed
    for _, f in ipairs(frames) do
        if f.scripts.OnUpdate then f.scripts.OnUpdate(f, elapsed) end
    end
end
-- The same in reverse order: WoW doesn't promise an order between frames' OnUpdate scripts.
function H.updateReversed(elapsed)
    now = now + elapsed
    for i = #frames, 1, -1 do
        local f = frames[i]
        if f.scripts.OnUpdate then f.scripts.OnUpdate(f, elapsed) end
    end
end
-- The clickable owner of a visible text (buttons with SetText, or a button whose child font string has it).
function H.clickText(text)
    for _, f in ipairs(frames) do
        if f.text == text then
            local target = f.scripts.OnClick and f or f.parent
            if target and target.scripts and target.scripts.OnClick then
                target.scripts.OnClick(target)
                return true
            end
        end
    end
    error("nothing clickable with text: " .. text)
end
-- The row whose label is `text`: returns its first child widget of the given kind.
function H.rowWidget(text, kind)
    for _, f in ipairs(frames) do
        if f.kind == "fontstring" and f.text == text and f.parent then
            for _, child in ipairs(f.parent.children) do
                if child.kind == kind then return child end
            end
        end
    end
    error("no " .. kind .. " in row " .. text)
end
function H.shownMenuEntries()
    local out = {}
    for _, f in ipairs(frames) do
        if f.kind == "Button" and f.swatch and f.shown and f.scripts.OnClick then table.insert(out, f) end
    end
    return out
end
function H.runTickers(times)
    for _ = 1, times do
        for _, t in ipairs(tickers) do if not t.cancelled then now = now + 0.5; t.fn() end end
    end
end
return H
"""

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(FAKE_WOW)
H = lua.execute(HELPERS)
G = lua.globals()
failures = 0


def check(label, actual, expected):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {label:<60} {actual}" + ("" if ok else f"   (expected {expected})"))


def step(label, fn):
    global failures
    try:
        fn()
        print(f"PASS  {label}")
    except Exception as e:  # a Lua error surfaces here
        failures += 1
        print(f"FAIL  {label}\n      {e}")


ns = lua.table()
toc = open(os.path.join(ADDON, "DoesItDie.toc"), encoding="utf-8").read().splitlines()
files = [line.strip() for line in toc if line.strip().endswith(".lua")]
for name in files:
    step(f"load {name}", lambda name=name: H.load(name, open(os.path.join(ADDON, name), encoding="utf-8").read(), ns))

ns.locale.collectStrings = True  # every text the window asks T for (see --dump-strings)
step("ADDON_LOADED", lambda: H.fire("ADDON_LOADED", "DoesItDie"))
check("defaults applied", G.DoesItDieDB.skullIcon, "cross")
# The window's own text: a test language with one translation, chosen as the window language.
ns.locale.register(lua.eval('{ tag = "xxXX", label = "Test", strings = { ["Live preview"] = "Vorschau (test)" } }'))
G.DoesItDieDB.uiLanguage = "xxXX"
check("a language with translations is offered", [e.id for e in ns.locale.windowLanguages().values()],
      ["auto", "enUS", "deDE", "xxXX"])
step("run the display loop with no target", lambda: H.update(0.2))
step("/did opens the window", lambda: G.SlashCmdList.DOESITDIE(""))
check("window shown", G.DoesItDieOptions.shown, True)
check("translated text shown in the window language", lua.eval("""function(frames)
    for _, f in ipairs(frames) do if f.text == "Vorschau (test)" then return true end end
    return false
end""")(lua.globals().frames), True)
check("untranslated text stays English", ns.locale.T("Simulate fight"), "Simulate fight")
step("display loop with the window's preview", lambda: H.update(0.2))

for tab in ("Kill icon", "Marker", "Effects", "Text", "Nameplates", "Focus", "Advanced"):
    step(f"open tab {tab}", lambda tab=tab: H.clickText(tab))


def copy_marker_look():
    H.clickText("Nameplates")
    G.DoesItDieDB.fillColor = "gold"
    H.clickText("Copy from Marker tab")


step("Nameplates: Copy from Marker tab", copy_marker_look)
check("  plate fill color copied from the marker", G.DoesItDieDB.plateFillColor, "gold")

for preset in ("Minimal", "Classic", "Debug", "Juicy"):
    step(f"apply preset {preset}", lambda p=preset: H.clickText(p))
    step(f"  display loop after {preset}", lambda: H.update(0.2))
check("Juicy preset set the fill", G.DoesItDieDB.fillTexture, "stripes")


def toggle_glow():
    box = H.rowWidget("Glow", "CheckButton")
    box.checked = False
    box.scripts.OnClick(box)


step("untick Glow", toggle_glow)
check("  glow setting off", G.DoesItDieDB.showGlow, False)


def set_slider(label, value):
    def run():
        H.rowWidget(label, "Slider").SetValue(H.rowWidget(label, "Slider"), value)
    return run


step("drag Size slider to 40", set_slider("Size", 40))
check("  icon size saved", G.DoesItDieDB.skullSize, 40)
step("drag Target health to 30", set_slider("Target health", 30))
step("drag DoT damage to 50", set_slider("DoT damage", 50))
step("display loop with a lethal preview", lambda: H.update(1.2))
check("  marker frame shown", G.DoesItDieRemaining.shown, True)
check("  marker filled to the DoT damage", round(G.DoesItDieRemaining.value or -1), 50)
check("  kill icon frame shown", G.DoesItDieSkull.shown, True)
check("  marker layered above the window's strata", G.DoesItDieRemaining.strata, "FULLSCREEN")


same = lua.eval("function(a, b) return rawequal(a, b) end")


def preview_plate_markers():
    # The mock nameplate is the window's only frame whose child StatusBar is sized 140x10.
    for f in G.frames.values():
        if f.kind == "Frame" and f.width == 140 and f.height == 26:
            return [c for c in f.children.values() if c.kind == "StatusBar" and c.width != 140]
    return []


markers_on_preview_plate = preview_plate_markers()
check("  preview nameplate got a marker", len(markers_on_preview_plate) >= 1, True)
check("  preview nameplate marker filled to the DoT damage",
      round(markers_on_preview_plate[0].value) if markers_on_preview_plate else None, 50)
preview_focus_bar = G.DoesItDieOptions.focusHealthBar
preview_focus_markers = [f for f in G.frames.values() if f.kind == "StatusBar" and f.allPoints is not None
                         and same(f.allPoints, preview_focus_bar)]
check("  preview focus frame got a marker", len(preview_focus_markers), 1)
check("  preview focus marker filled to the DoT damage",
      round(preview_focus_markers[0].value) if preview_focus_markers else None, 50)
check("  preview focus marker shown", preview_focus_markers[0].shown if preview_focus_markers else None, True)


def preview_focus_icon_window():
    mock_focus = preview_focus_bar.parent
    return next((c for c in mock_focus.children.values() if c.kind == "Frame" and c.clips), None)


G.DoesItDieDB.focusIconSize, G.DoesItDieDB.nameplateIconSize = 40, 18
step("focus kill icon size 40, nameplates' 18", lambda: H.update(0.2))
check("  the focus uses its own look", preview_focus_icon_window().width if preview_focus_icon_window() else None, 40)
step("Copy from Nameplates tab", lambda: (H.clickText("Focus"), H.clickText("Copy from Nameplates tab"),
                                          H.update(0.2)))
check("  copied the nameplates' icon size", G.DoesItDieDB.focusIconSize, 18)
check("  and their fill", G.DoesItDieDB.focusFillTexture, G.DoesItDieDB.plateFillTexture)
check("  but not their show mode", G.DoesItDieDB.focusMode, "markerIcon")
check("  preview follows", preview_focus_icon_window().width if preview_focus_icon_window() else None, 18)


def pick_outline_none():
    H.clickText("Marker")
    button = H.rowWidget("Outline", "Button")
    button.scripts.OnClick(button)
    entries = H.shownMenuEntries()
    for entry in entries.values():
        if entry.text and "None" in entry.text.text:
            entry.scripts.OnClick(entry)
            return
    raise AssertionError("no None entry in the outline menu")


step("pick Outline: None from the dropdown", pick_outline_none)
check("  outline style saved", G.DoesItDieDB.outlineStyle, "none")
step("display loop without outline", lambda: H.update(0.2))

step("Reset this tab (Marker)", lambda: H.clickText("Reset this tab"))
check("  outline back to default", G.DoesItDieDB.outlineStyle, "dashed")

def enter_combat():
    G.combat = True
    H.fire("PLAYER_REGEN_DISABLED")
    H.update(1.2)


def leave_combat():
    G.combat = False
    H.fire("PLAYER_REGEN_ENABLED")
    H.update(1.2)


step("enter combat with the window open", enter_combat)
check("  display back on the target frame (not the window's strata)", G.DoesItDieRemaining.strata != "FULLSCREEN", True)
check("  log says the preview stepped aside",
      any("PREVIEW off" in line for line in list(G.DoesItDieDB.log.values())[-5:]), True)
step("leave combat", leave_combat)
check("  preview has the display again", G.DoesItDieRemaining.strata, "FULLSCREEN")

step("start Simulate fight", lambda: H.clickText("Simulate fight"))
step("run the simulated fight", lambda: (H.runTickers(25), H.update(0.2)))
step("Flash button", lambda: H.clickText("Flash"))
step("Reset learned tick sizes", lambda: H.clickText("Reset"))
step("close the window", lambda: G.DoesItDieOptions.Hide(G.DoesItDieOptions))
check("window hidden", G.DoesItDieOptions.shown, False)
step("display loop back on the (absent) target", lambda: H.update(0.2))
def chat_text():
    return "\n".join(str(line) for line in G.chat.values())


step("/did help", lambda: G.SlashCmdList.DOESITDIE("help"))
step("/did skull", lambda: (G.SlashCmdList.DOESITDIE("skull"), H.update(0.2)))
step("/did line (markers off)", lambda: G.SlashCmdList.DOESITDIE("line"))
check("  markers off", G.DoesItDieDB.showMarkers, False)
step("/did line (markers on)", lambda: G.SlashCmdList.DOESITDIE("line"))
check("  markers on; no target frame in this fake UI, so it says so",
      chat_text().splitlines()[-1].endswith("health bar markers unavailable."), True)
step("/did debug twice", lambda: (G.SlashCmdList.DOESITDIE("debug"), G.SlashCmdList.DOESITDIE("debug")))
step("/did plates", lambda: G.SlashCmdList.DOESITDIE("plates"))
plate_lines = [line for line in G.DoesItDieDB.log.values() if "PLATES" in line]
check("  probe logged the fake nameplate", any("nameplate1" in line and "healthBar=UnitFrame.healthBar" in line
                                                and "anchorPlate=ok" in line for line in plate_lines), True)
check("  probe summary", plate_lines[-1].split("PLATES ")[1], "probe done: 1 nameplates, 1 test bars shown")
step("test bars hide after 8 seconds", lambda: H.update(9))


def exec_log():
    return [line for line in G.DoesItDieDB.log.values() if "EXEC" in line]


def execute_bar():
    return next((f for f in G.frames.values() if f.kind == "StatusBar" and f.width == 50000), None)


G.targetGuid = "Creature-0-1-2-3-3099-000001"
step("/did exec (no curve API)", lambda: (G.SlashCmdList.DOESITDIE("exec"), H.update(0.2)))
check("  probe logged the missing curve API", any("curve: UnitHealthPercent missing" in l for l in exec_log()), True)
check("  geometry bar fed the target's health", execute_bar().value if execute_bar() else None, 100)
lua.execute("""
    function UnitHealthPercent(unit, usePredicted, curve)
        if curve then return curve:Evaluate(0.5) end
        return 1
    end
    Enum.LuaCurveType = { Linear = 0, Step = 1 }
    C_CurveUtil = { CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType() end
        function c:AddPoint(x, color) table.insert(self.points, { x = x, color = color }) end
        function c:Evaluate(x)
            local found = self.points[1].color
            for _, p in ipairs(self.points) do if x >= p.x then found = p.color end end
            return { a = found[4], GetRGBA = function() return unpack(found) end }
        end
        return c
    end, CreateCurve = function()
        local c = { points = {} }
        function c:SetType() end
        function c:AddPoint(x, y) table.insert(self.points, { x = x, y = y }) end
        function c:Evaluate(x)
            local found = self.points[1].y
            for _, p in ipairs(self.points) do if x >= p.x then found = p.y end end
            return found
        end
        return c
    end }
""")
step("/did exec 35 (with a fake curve API)", lambda: (G.SlashCmdList.DOESITDIE("exec 35"), H.update(0.2)))
check("  curve built at 0.35", any("threshold point at 0.35" in l for l in exec_log()), True)
check("  no B errors", any("EXEC B error" in l for l in exec_log()), False)
step("/did exec stops it", lambda: G.SlashCmdList.DOESITDIE("exec"))
check("  probe off", G.DoesItDieExecuteProbe.shown, False)
G.targetGuid = None


def plate_children(kind):
    return [c for c in G.FakePlate.children.values() if c.kind == kind]


def dot_the_mob():
    G.targetGuid = "Creature-0-1-2-3-3099-000001"
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 172)
    H.update(0.2)


step("cast Corruption on the mob behind nameplate1", dot_the_mob)
markers = plate_children("StatusBar")
check("  nameplate got a marker", len(markers), 1)
check("  marker filled to Corruption's 40", markers[0].value if markers else None, 40)
check("  marker shown", markers[0].shown if markers else None, True)
icon_windows = [f for f in plate_children("Frame") if f.clips]  # the clipped kill icon window
check("  kill icon window shown", icon_windows[0].shown if icon_windows else None, True)


def fire_and_update(event, *args):
    def run():
        H.fire(event, "player", *args)
        H.update(0.2)
    return run


step("start casting Immolate (cast time) on it", fire_and_update("UNIT_SPELLCAST_START", "cast-2", 348))
check("  nameplate marker counts it while casting: 40 + 20", markers[0].value if markers else None, 60)
step("the cast is interrupted", fire_and_update("UNIT_SPELLCAST_INTERRUPTED", "cast-2", 348))
check("  back to Corruption alone", markers[0].value if markers else None, 40)


def set_estimate(on):
    def run():
        H.clickText("Advanced")
        box = H.rowWidget("Estimate during casting", "CheckButton")
        box.checked = on
        box.scripts.OnClick(box)
    return run


step("untick Estimate during casting", set_estimate(False))
check("  setting off", G.DoesItDieDB.estimateDuringCast, False)
step("start casting Immolate with it off", fire_and_update("UNIT_SPELLCAST_START", "cast-3", 348))
check("  nothing added while casting", markers[0].value if markers else None, 40)
step("  and interrupted", fire_and_update("UNIT_SPELLCAST_INTERRUPTED", "cast-3", 348))
step("tick it again", set_estimate(True))
check("  setting on", G.DoesItDieDB.estimateDuringCast, True)
step("cast Immolate again", fire_and_update("UNIT_SPELLCAST_START", "cast-4", 348))
step("  it lands (SUCCEEDED, then STOP)", lambda: (H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-4", 348),
                                                   H.fire("UNIT_SPELLCAST_STOP", "player", "cast-4", 348),
                                                   H.update(1.0)))
check("  counted once: 40 + 20", markers[0].value if markers else None, 60)


def plates_off():
    G.DoesItDieDB.nameplateMode = "off"
    H.update(0.2)


step("switch nameplates off", plates_off)
check("  marker hidden", markers[0].shown if markers else None, False)
check("  kill icon hidden", icon_windows[0].shown if icon_windows else None, False)

step("/did exec with Corruption on the target (kill icon curve, C)",
     lambda: (G.SlashCmdList.DOESITDIE("exec"), H.update(0.2)))
check("  C uses the float curve", any("kill curve mode: alpha" in l for l in exec_log()), True)
check("  C curve stepped past Corruption's 40", any("step at 40.5; plain check: alpha at 40=1, at 41=0" in l
                                                   for l in exec_log()), True)
check("  C applied without error", any("alpha: applied without error" in l for l in exec_log()), True)
check("  no C errors", any("EXEC C" in l and "error:" in l for l in exec_log()), False)
step("/did exec stops it again", lambda: G.SlashCmdList.DOESITDIE("exec"))

# Custom target frame (Advanced tab), as for a unit frame addon that replaces Blizzard's target frame.
lua.execute("""
    local custom = CreateFrame("Frame", "MyTargetFrame", UIParent)
    custom.Health = CreateFrame("StatusBar", nil, custom)
""")
custom_bar = G.MyTargetFrame.Health
check("frame path of an unnamed child found by its key", ns.framePath(custom_bar), "MyTargetFrame.Health")
check("  and resolves back to it", same(ns.resolveFramePath("MyTargetFrame.Health"), custom_bar), True)
check("  a missing path resolves to nothing", ns.resolveFramePath("NoSuchFrame.Health"), None)


def type_frame_path(label, text):
    def run():
        box = H.rowWidget(label, "EditBox")
        box.SetText(box, text)
        box.scripts.OnEditFocusLost(box)
    return run


step("type a custom health bar path", type_frame_path("Target health bar", "MyTargetFrame.Health"))
check("  saved", G.DoesItDieDB.customHealthBar, "MyTargetFrame.Health")
step("display loop on the custom frame", lambda: H.update(0.2))
check("  marker laid over the custom health bar", same(G.DoesItDieRemaining.allPoints, custom_bar), True)
check("  status shows it in use", "MyTargetFrame.Health" in ns.attachStatus()[0], True)
check("  marker still showing Corruption", G.DoesItDieRemaining.shown, True)


def hide_custom_frame():
    G.MyTargetFrame.Hide(G.MyTargetFrame)
    H.update(0.2)


step("custom target frame hidden", hide_custom_frame)
check("  marker hidden with it", G.DoesItDieRemaining.shown, False)
G.MyTargetFrame.Show(G.MyTargetFrame)
step("type a path that doesn't exist", type_frame_path("Target health bar", "Gone.Health"))
check("  status says not found", "not found" in ns.attachStatus()[0], True)
step("clear it", type_frame_path("Target health bar", ""))
check("  back to Blizzard's", ns.attachStatus()[0], "Blizzard's target frame")
step("Pick button starts pick mode", lambda: H.clickText("Pick"))
step("  a right-click cancels it", lambda: H.fire("GLOBAL_MOUSE_DOWN", "RightButton"))

# In-game, IsMouseOver on Blizzard's target frame textures returned a secret boolean and every pick update errored
# (Frames.lua:96, 57 times). Secret values here are a sentinel that issecretvalue recognizes.
lua.execute("""
    SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
    function issecretvalue(v) return v == SECRET end
    local frame, bar = MyTargetFrame, MyTargetFrame.Health
    function frame:GetChildren() return bar end
    function frame:GetRect() return 0, 0, 200, 40 end
    function frame:IsMouseOver() return SECRET end
    function bar:GetObjectType() return "StatusBar" end
    function bar:GetRect() return 10, 10, 150, 12 end
    function bar:IsMouseOver() return SECRET end
    function bar:GetEffectiveScale() return 1 end
    function frame:GetEffectiveScale() return 1 end
    function GetCursorPosition() return 50, 15 end
    function GetMouseFoci() return { frame } end
""")


def pick_with_secret_mouseover():
    H.clickText("Pick")  # the health bar row's
    H.update(0.1)
    H.fire("GLOBAL_MOUSE_DOWN", "LeftButton")


step("Pick over a bar whose IsMouseOver is secret: no error", pick_with_secret_mouseover)
check("  falls back to the rectangle and picks the bar", G.DoesItDieDB.customHealthBar, "MyTargetFrame.Health")
check("  no pick error logged", any("ERROR in frame pick" in l for l in G.DoesItDieDB.log.values()), False)
lua.execute("issecretvalue = nil")

# EllesmereUI's nameplates: it parks Blizzard's health bar on a hidden frame and shows its own plate frame (pooled,
# parented to the Blizzard plate while in use, listed by unit in EllesmereNameplates_NS.plates, bar at .health).
lua.execute("""
    local parking = CreateFrame("Frame")
    parking:Hide()
    FakePlate.UnitFrame.healthBar.parent = parking
    local eui = CreateFrame("Frame", nil, FakePlate)
    eui.health = CreateFrame("StatusBar", nil, eui)
    eui.health:SetFrameStrata("MEDIUM")
    eui.nameplate, eui.unit = FakePlate, "nameplate1"
    FakeEllesmerePlate = eui
    EllesmereNameplates_NS = { plates = { nameplate1 = eui } }
""")
eui = G.FakeEllesmerePlate


def plates_on_with_ellesmere():
    G.DoesItDieDB.nameplateMode = "markerIcon"
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 172)
    H.update(0.2)


step("EllesmereUI's plate on nameplate1, Corruption recast", plates_on_with_ellesmere)
eui_markers = [c for c in eui.children.values() if c.kind == "StatusBar" and same(c.allPoints, eui.health)]
check("  marker laid over EllesmereUI's health bar", len(eui_markers), 1)
check("  filled to Corruption's 40 + the Immolate cast earlier", eui_markers[0].value if eui_markers else None, 60)
check("  shown", eui_markers[0].shown if eui_markers else None, True)
check("  in the bar's strata", eui_markers[0].strata if eui_markers else None, "MEDIUM")
check("  nothing drawn on Blizzard's parked bar", markers[0].shown if markers else None, False)

step("EllesmereUI releases its plate to the pool", lambda: eui.Hide(eui))
check("  marker hidden at once", eui_markers[0].shown if eui_markers else None, False)
step("  the plate comes back for another mob", lambda: eui.Show(eui))
check("  no stale marker before the next update", eui_markers[0].shown if eui_markers else None, False)
step("  next update", lambda: H.update(0.2))
check("  marker back for this mob's DoTs", eui_markers[0].shown if eui_markers else None, True)

lua.execute("function UnitIsDead(unit) return unit == 'nameplate1' end")
step("the mob dies with Corruption still on it (its plate lingers)", lambda: H.update(0.2))
check("  no marker on the corpse", eui_markers[0].shown if eui_markers else None, False)
lua.execute("function UnitIsDead() return false end")
step("  (alive again for the next checks)", lambda: H.update(0.2))

step("/did plates with EllesmereUI's plate", lambda: G.SlashCmdList.DOESITDIE("plates"))
plate_lines = [line for line in G.DoesItDieDB.log.values() if "PLATES" in line]
check("  probe reports its health bar", any("healthBar=EllesmereUI plate.health" in line and "barShown=true" in line
                                            and "barStrata=MEDIUM" in line for line in plate_lines), True)

lua.execute("""
    EllesmereNameplates_NS = nil
    FakePlate.UnitFrame.healthBar.parent = FakePlate.UnitFrame
""")
step("without EllesmereUI's plates", lambda: H.update(0.2))
check("  marker back on Blizzard's bar", markers[0].shown if markers else None, True)
check("  EllesmereUI plate's marker hidden", eui_markers[0].shown if eui_markers else None, False)

# EllesmereUI's unit frames: its target frame is used without a setting. The frame only exists while EllesmereUI
# draws the target frame itself.
lua.execute("""
    local frame = CreateFrame("Frame", "EllesmereUIUnitFrames_Target", UIParent)
    frame.Health = CreateFrame("StatusBar", nil, frame)
    -- The portrait sits on a backdrop, which EllesmereUI hides when portraits are off.
    local backdrop = CreateFrame("Frame", nil, frame)
    frame.Portrait = backdrop:CreateTexture()
    frame.Portrait.name = "EllesmereUIPortrait"
""")
eui_target_bar = G.EllesmereUIUnitFrames_Target.Health


def last_attach():
    return [line for line in G.DoesItDieDB.log.values() if "ATTACH" in line][-1]



def type_and_update(text):
    def run():
        type_frame_path("Target health bar", text)()
        H.update(0.2)
    return run


step("EllesmereUI's target frame appears", lambda: (H.fire("PLAYER_TARGET_CHANGED"), H.update(0.2)))
check("  a typed path still wins", same(G.DoesItDieRemaining.allPoints, custom_bar), True)
step("clear the path", type_and_update(""))
check("  marker laid over EllesmereUI's health bar", same(G.DoesItDieRemaining.allPoints, eui_target_bar), True)
check("  status names it", ns.attachStatus()[0], "EllesmereUI's target frame")
check("  kill icon on its portrait", ns.attachStatus()[1], "EllesmereUI's portrait")
check("    and attached there", "ATTACH portrait: EllesmereUIPortrait" in last_attach(), True)


def portraits_off():
    lua.execute("EllesmereUIUnitFrames_Target.Portrait:GetParent():Hide()")
    H.fire("PLAYER_TARGET_CHANGED")
    H.update(0.2)


step("EllesmereUI's portraits turned off", portraits_off)
check("  kill icon on its health bar", ns.attachStatus()[1], "the health bar")
check("    and attached there", "ATTACH portrait: not found" in last_attach(), True)
step("type a path that doesn't exist", type_and_update("Gone.Health"))
check("  falls back to EllesmereUI's, not Blizzard's", same(G.DoesItDieRemaining.allPoints, eui_target_bar), True)
check("  status says so", "using EllesmereUI's target frame" in ns.attachStatus()[0], True)
lua.execute("EllesmereUIUnitFrames_Target = nil")
step("clear it, with EllesmereUI's target frame off", type_and_update(""))
check("  back to Blizzard's", ns.attachStatus()[0], "Blizzard's target frame")


# Learned tick sizes viewer (Advanced > View, /did ticks).
def learn_some_ticks():
    ticks = ns.db.ticks
    lua.execute("wipe(DoesItDieDB.ticks)")
    ticks[172] = 12       # Corruption: tooltip 40 over 12s = 10 per tick
    ticks[348] = 4.4      # Immolate: tooltip 20 over 15s = 4 per tick
    ticks["1079x3"] = 22  # a 3-point finisher the client has no description for here


step("learn three tick sizes", learn_some_ticks)
step("/did ticks opens the viewer", lambda: G.SlashCmdList.DOESITDIE("ticks"))
viewer = G.DoesItDieLearnedTicks
check("  shown", viewer.shown if viewer else None, True)
rows = viewer.rows


def cells(i):
    row = rows[i]
    return [row.name.text, row.cells.combo.text, row.cells.learned.text, row.cells.tooltip.text,
            row.cells.bonus.text, row.cells.total.text]


check("  Corruption: 12 learned, tooltip 10, +20%, 48 in all", cells(1), ["Corruption", "", "12", "10", "+20%", "48"])
check("  Immolate: decimals kept", cells(2), ["Immolate", "", "4.4", "4", "+10%", "22"])
check("  finisher: its combo points, no tooltip numbers", cells(3), ["Spell", 3, "22", "-", "-", "-"])
check("  no fourth row", rows[4].shown, False)
def viewer_count():
    for child in viewer.children.values():
        if child.kind == "fontstring" and "learned tick size" in str(child.text or ""):
            return child.text


check("  count", viewer_count(), "3 learned tick sizes")
step("hover a row (spell tooltip plus learned numbers)", lambda: rows[1].scripts.OnEnter(rows[1]))
lua.execute('linked = nil; function IsShiftKeyDown() return true end; '
            'function ChatEdit_InsertLink(l) linked = l; return true end; '
            'C_Spell.GetSpellLink = function(id) return "[link " .. id .. "]" end')
step("shift-click Corruption", lambda: rows[1].scripts.OnClick(rows[1]))
check("  linked in chat", G.linked, "[link 172]")


def forget_first_row():
    for child in rows[1].children.values():
        if child.kind == "Button":
            child.scripts.OnClick(child)
            return
    raise AssertionError("no forget button")


step("forget Corruption's tick size", forget_first_row)
check("  gone from the saved data", ns.db.ticks[172], None)
check("  Immolate moves up", rows[1].name.text, "Immolate")
step("Forget all", lambda: H.clickText("Forget all"))
check("  saved data empty", len(list(ns.db.ticks.keys())), 0)
check("  no rows", rows[1].shown, False)
step("/did ticks again closes it", lambda: G.SlashCmdList.DOESITDIE("ticks"))
check("  hidden", viewer.shown, False)
step("Advanced tab's View button opens it", lambda: H.clickText("View"))
check("  shown", viewer.shown, True)


# Focus frame (Focus.lua): a focus mob ("FocusMob") with Blizzard's focus frame, a [@focus] Corruption on it.
lua.execute("""
    focusGuid = "Creature-0-1-2-3-3099-0000F0"
    local unitExists, unitGUID = UnitExists, UnitGUID
    function UnitExists(unit) if unit == "focus" then return focusGuid ~= nil end return unitExists(unit) end
    function UnitGUID(unit) if unit == "focus" then return focusGuid end return unitGUID(unit) end
    function UnitName(unit) if unit == "focus" and focusGuid then return "FocusMob" end end
    local focus = CreateFrame("Frame", "FocusFrame", UIParent)
    focus.TargetFrameContent = CreateFrame("Frame", nil, focus)
    focus.TargetFrameContent.TargetFrameContentMain = CreateFrame("Frame", nil, focus.TargetFrameContent)
    local main = focus.TargetFrameContent.TargetFrameContentMain
    main.HealthBarsContainer = CreateFrame("Frame", nil, main)
    main.HealthBarsContainer.HealthBar = CreateFrame("StatusBar", nil, main.HealthBarsContainer)
    BlizzardFocusBar = main.HealthBarsContainer.HealthBar
    -- Like Blizzard's: art layered far above the health bar (the target frame's top was MEDIUM/1001 in game).
    focus:SetFrameStrata("MEDIUM")
    focus:SetFrameLevel(1001)
""")


def markers_on(bar):
    return [f for f in G.frames.values() if f.kind == "StatusBar" and f.allPoints is not None and same(f.allPoints, bar)]


def focus_cast():
    H.fire("UNIT_SPELLCAST_SENT", "player", "FocusMob", "cast-f1", 172)
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-f1", 172)
    H.update(0.2)


G.DoesItDieDB.nameplateMode = "markerIcon"
step("[@focus] Corruption on the focus", focus_cast)
focus_markers = markers_on(G.BlizzardFocusBar)
check("  marker on Blizzard's focus health bar", len(focus_markers), 1)
check("  filled to Corruption's 40", focus_markers[0].value if focus_markers else None, 40)
check("  shown", focus_markers[0].shown if focus_markers else None, True)
check("  status names it", ns.focusStatus(), "Blizzard's focus frame")
check("  layered above the focus frame's top (MEDIUM/1001)",
      (focus_markers[0].strata, focus_markers[0].level) if focus_markers else None, ("MEDIUM", 1006))
step("another update (the nameplate refresh must leave it alone)", lambda: H.update(0.2))
check("  still shown", focus_markers[0].shown if focus_markers else None, True)
step("  and with the updates in the other order", lambda: H.updateReversed(0.2))
check("  still shown", focus_markers[0].shown if focus_markers else None, True)
lua.execute("focusGuid = nil")
step("focus cleared", lambda: H.update(0.2))
check("  hidden", focus_markers[0].shown if focus_markers else None, False)
lua.execute('focusGuid = "Creature-0-1-2-3-3099-0000F0"')
G.DoesItDieDB.focusMode = "off"
step("focus back, Show on focus frame off", lambda: H.update(0.2))
check("  hidden", focus_markers[0].shown if focus_markers else None, False)
G.DoesItDieDB.focusMode = "markerIcon"
lua.execute("""
    local eui = CreateFrame("Frame", "EllesmereUIUnitFrames_Focus", UIParent)
    eui.Health = CreateFrame("StatusBar", nil, eui)
""")
step("EllesmereUI's focus frame appears", lambda: H.update(0.2))
eui_focus = markers_on(G.EllesmereUIUnitFrames_Focus.Health)
check("  marker moves to its health bar", len(eui_focus), 1)
check("  status names it", ns.focusStatus(), "EllesmereUI's focus frame")
check("  Advanced tab has the focus rows", all(H.rowWidget(label, kind) is not None for label, kind in
      (("Show on focus frame", "Button"), ("Focus health bar", "EditBox"))), True)


# Instances (PR #8): creature GUIDs are secret; the target's nameplate token stands in for its GUID.
lua.execute("""
    savedUnitGUID, savedGetPlate = UnitGUID, C_NamePlate.GetNamePlateForUnit
    function issecretvalue(v) return v == SECRET end
    FakePlate.namePlateUnitToken = "nameplate1"
    plateUp = true
    function UnitGUID(unit) if unit == "target" or unit == "nameplate1" then return SECRET end end
    C_NamePlate.GetNamePlateForUnit = function(unit)
        if plateUp and (unit == "nameplate1" or unit == "target") then return FakePlate end
    end
    targetGuid = SECRET
""")


def dungeon_cast(guid):
    def run():
        H.fire("PLAYER_TARGET_CHANGED")
        H.fire("UNIT_SPELLCAST_SENT", "player", "", guid, 172)
        H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 172)
        H.update(0.2)
    return run


def dot_total(unit):
    return ns.dotBreakdownForUnit(unit)[1]


step("in a dungeon: Corruption on the target (secret GUID, nameplate up)", dungeon_cast("cast-d1"))
check("  tracked on the target", dot_total("target"), 40)
check("  and on its nameplate: the same mob", dot_total("nameplate1"), 40)
check("  logged why", any("tracking each mob by its nameplate" in l for l in G.DoesItDieDB.log.values()), True)
step("its nameplate goes away", lambda: (H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"), H.update(0.2)))
check("  its DoTs are dropped (the token will be another mob's)", dot_total("nameplate1"), 0)
check("  logged", any("PLATE nameplate1 removed" in l for l in G.DoesItDieDB.log.values()), True)
lua.execute("plateUp = false")
step("no nameplate at all: Corruption on the target", dungeon_cast("cast-d2"))
check("  tracked on the target only (the old fallback)", dot_total("target"), 40)
lua.execute("""
    UnitGUID, C_NamePlate.GetNamePlateForUnit = savedUnitGUID, savedGetPlate
    targetGuid = nil
    issecretvalue = nil
""")


# Other nameplate addons (Plater, ...): Blizzard's plate bar hidden, the addon's own frame on the plate with its bar
# under a "health" key, found by the automatic search; then the Advanced tab's path for one it would miss.
lua.execute("""
    EllesmereNameplates_NS, Platynator = nil, nil
    targetGuid = "Creature-0-1-2-3-3099-0000A1"
    FakePlate.UnitFrame:Hide()
    FakePlate.unitFrame = CreateFrame("Frame", nil, FakePlate)
    FakePlate.unitFrame.PlateFrame = FakePlate -- (a back-reference, as Plater keeps)
    FakePlate.unitFrame.healthBar = CreateFrame("StatusBar", nil, FakePlate.unitFrame)
    PlaterBar = FakePlate.unitFrame.healthBar
    -- A reference to a frame outside the plate, with its own health bar, under a key that's searched first.
    local outside = CreateFrame("Frame", nil, UIParent)
    outside.healthBar = CreateFrame("StatusBar", nil, outside)
    FakePlate.aaaElsewhere = outside
""")


def plate_cast():
    H.fire("PLAYER_TARGET_CHANGED")
    H.fire("UNIT_SPELLCAST_SENT", "player", "", "cast-p1", 172)
    H.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-p1", 172)
    H.update(0.2)


G.DoesItDieDB.nameplateMode = "markerIcon"
step("Plater-like plate: Corruption on its mob", plate_cast)
plater_markers = markers_on(G.PlaterBar)
check("  marker found Plater's bar on its own", len(plater_markers), 1)
check("  filled to Corruption's 40", plater_markers[0].value if plater_markers else None, 40)
check("  shown", plater_markers[0].shown if plater_markers else None, True)
check("  status says where", ns.plateBarStatus(), "found: unitFrame.healthBar")
step("/did plates with it", lambda: G.SlashCmdList.DOESITDIE("plates"))
check("  probe names the bar", any("healthBar=auto unitFrame.healthBar" in l
                                   for l in G.DoesItDieDB.log.values()), True)
lua.execute("""
    FakePlate.mine = CreateFrame("Frame", nil, FakePlate)
    FakePlate.mine.bar = CreateFrame("StatusBar", nil, FakePlate.mine)
    MineBar = FakePlate.mine.bar
""")
G.DoesItDieDB.customPlateHealthBar = "mine.bar"
step("Advanced: Nameplate health bar = mine.bar", lambda: H.update(0.2))
mine_markers = markers_on(G.MineBar)
check("  marker on that bar", len(mine_markers), 1)
check("  status shows the path", "mine.bar" in ns.plateBarStatus(), True)
G.DoesItDieDB.customPlateHealthBar = "nothing.here"
step("  a path that doesn't exist: back to the automatic search", lambda: H.update(0.2))
check("  on Plater's bar again", ns.plateBarStatus(), "found: unitFrame.healthBar")
G.DoesItDieDB.customPlateHealthBar = ""

# A field that errors when read (frameworks' objects with a throwing __index), searched before Plater's frame: it
# used to abort the whole search, so Plater's bar was never found (CurseForge, tuwzz).
lua.execute("""
    FakePlate.aaaBomb = setmetatable({}, { __index = function() error("framework object: no such key") end })
""")


def fresh_search():
    # a different plate frame each time would be cleaner; waiting out the per-plate cache does the same
    H.update(1.5)


def search_again():
    # The cache keeps a shown bar: hide it for one update so the next search really runs.
    lua.execute("PlaterBar:Hide()")
    H.update(0.2)
    lua.execute("PlaterBar:Show()")
    H.update(1.5)


step("a field that errors when read sits before Plater's frame", search_again)
check("  Plater's bar still found and drawn on", any(m.shown for m in markers_on(G.PlaterBar)), True)


def isolated_search():
    # The real searchHealthBar on its own, on a plate with a throwing field sorted before a Plater-like frame.
    # (The fake environment above doesn't reproduce the abort; v0.8.1's search fails this, the current one passes.)
    import re
    source = open(os.path.join(ADDON, "Nameplates.lua"), encoding="utf-8").read()
    code = source[source.index("local function isStatusBar"):source.index("local function autoHealthBar")]
    code = re.sub(r"^local SEARCH_(DEPTH|INTERVAL) = \d+\n", "", code, flags=re.M)
    return LuaRuntime().execute("""
        local function isSecret() return false end
        local SEARCH_DEPTH, SEARCH_INTERVAL = 4, 1
        local function frame(kind, parent)
            local f = { kind = kind, parent = parent, shown = true }
            function f.GetObjectType(self) return self.kind end
            function f.GetParent(self) return self.parent end
            function f.IsVisible(self) return self.shown end
            function f.GetEffectiveAlpha() return 1 end
            function f.IsForbidden() return false end
            return f
        end
        local function barShown(bar) return bar:IsVisible() end
    """ + code + """
        local plate = frame("Frame", nil)
        plate.UnitFrame = frame("Frame", plate)
        plate.aaaBomb = setmetatable({}, { __index = function() error("framework object: no such key") end })
        plate.unitFrame = frame("Frame", plate)
        plate.unitFrame.healthBar = frame("StatusBar", plate.unitFrame)
        local ok, _, path = pcall(searchHealthBar, plate)
        return ok and path or "search aborted"
    """)


check("  the search itself, run in isolation, gets past the throwing field", isolated_search(), "unitFrame.healthBar")

# Threat Plates keeps its bar in a plain table: TPFrame.visual.healthbar.
lua.execute("""
    PlaterBar:Hide(); FakePlate.unitFrame = nil
    FakePlate.TPFrame = CreateFrame("Frame", nil, FakePlate)
    FakePlate.TPFrame.visual = {}
    FakePlate.TPFrame.visual.healthbar = CreateFrame("StatusBar", nil, FakePlate.TPFrame)
    ThreatBar = FakePlate.TPFrame.visual.healthbar
""")
step("Threat Plates-like plate", fresh_search)
check("  its bar found through the plain table", ns.plateBarStatus(), "found: TPFrame.visual.healthbar")
check("  marker on it", len(markers_on(G.ThreatBar)), 1)

# Nothing readable and Blizzard's bar hidden: the kill icon alone, beside the plate (as before v0.7.0).
lua.execute("ThreatBar:Hide(); FakePlate.TPFrame, FakePlate.aaaBomb = nil, nil")
step("a plate addon we can't read", fresh_search)
check("  status says so", "kill icon only" in ns.plateBarStatus(), True)
blizzard_markers = markers_on(G.FakePlate.UnitFrame.healthBar)
check("  no marker over the hidden bar", any(m.shown for m in blizzard_markers), False)
icon_windows = [c for c in G.FakePlate.children.values() if c.kind == "Frame" and c.clips]
check("  but the kill icon shows", any(w.shown for w in icon_windows), True)

lua.execute("""
    FakePlate.UnitFrame:Show()
    FakePlate.unitFrame, FakePlate.mine, FakePlate.TPFrame, FakePlate.aaaBomb = nil, nil, nil, nil
    targetGuid = nil
""")


def lua_quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


# --dump-strings FILE: every text the window and messages above asked T for (Locale.lua), as a table to paste
# into a language file's STRINGS and fill in.
if "--dump-strings" in sys.argv:
    import re
    path = sys.argv[sys.argv.index("--dump-strings") + 1]
    seen = {k for k in ns.locale.seenStrings.keys() if isinstance(k, str)}
    # Plus every literal T("...") in the source: text only shown in states the run above didn't reach.
    for name in files:
        source = open(os.path.join(ADDON, name), encoding="utf-8").read()
        for literal in re.findall(r'\bT\("((?:[^"\\]|\\.)*)"\)', source):
            seen.add(literal.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\"))
    keys = sorted(seen)
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("local STRINGS = {\n")
        for key in keys:
            out.write(f"    [{lua_quote(key)}] = \"\",\n")
        out.write("}\n")
    print(f"\n{len(keys)} strings written to {path}")

print(f"\n{'all passed' if not failures else str(failures) + ' FAILED'}")
if __name__ == "__main__": sys.exit(1 if failures else 0)
