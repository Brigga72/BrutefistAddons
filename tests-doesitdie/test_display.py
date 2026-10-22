"""Loads DoesItDie's real display code (Display.lua) with mocked frames (they record what they're set to) and checks
the per-DoT segment logic: running totals, visibility, dividers, colors and the text breakdown.

    pip install lupa
    python tools/test_display.py
"""
import os
import sys

import locale  # noqa: E402
locale.setlocale(locale.LC_CTYPE, "C")  # as in WoW: Lua's %d and %s follow the C library's locale
from lupa.lua51 import LuaRuntime  # WoW runs Lua 5.1

src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "DoesItDie", "Display.lua"),
           encoding="utf-8").read()


def chunk(start, end):
    i = src.index(start)
    return src[i:src.index(end, i)]


MOCKS = """
-- Every frame/texture/animation is a mock that accepts any method; values set are recorded.
local function mock(kind)
    local o = { kind = kind, values = {}, shown = true }
    return setmetatable(o, { __index = function(t, k)
        if k == "GetStatusBarTexture" then
            return function(self) self._tex = self._tex or mock("tex"); return self._tex end
        elseif k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup"
            or k == "CreateAnimation" then
            return function() return mock(k) end
        elseif k == "SetValue" then return function(self, v) self.value = v end
        elseif k == "SetMinMaxValues" then return function(self, a, b) self.max = b end
        elseif k == "SetShown" then return function(self, v) self.shown = v and true or false end
        elseif k == "Show" then return function(self) self.shown = true end
        elseif k == "Hide" then return function(self) self.shown = false end
        elseif k == "IsShown" then return function(self) return self.shown end
        elseif k == "SetVertexColor" then return function(self, r, g, b, a) self.color = { r, g, b, a } end
        elseif k == "SetText" then return function(self, s) self.text = s end
        end
        return function() end
    end })
end
function CreateFrame(kind) return mock(kind) end
UIParent = mock("UIParent")
GameFontNormalSmall = mock("font")
function CreateColor(...) return { ... } end
db = { dotColors = "single", segmentDividers = true, fillOpacity = 50, smoothMotion = false, showMarkers = true,
       showLabel = true }
local ADDON_NAME = "DoesItDie"
local function isSecret() return false end
local function trace() end
"""

HARNESS = MOCKS + chunk(
    "---------------------------------------------------------------------------\n-- Display",
    "local function playFlash") + """
return {
    update = function(entries) return updateSegments(entries) end,
    set = function(value, scale, cumulative) setMarkerValue(value, scale, cumulative) end,
    text = function(entries) return breakdownText(entries) end,
    segment = function(i)
        local s = segments[i]
        local c = rawget(s.texture, "color")
        return rawget(s.bar, "value"), rawget(s.texture, "shown"), rawget(s.divider, "shown"),
            c and table.concat({ c[1], c[2], c[3], c[4] }, ",") or ""
    end,
    total = function() return remainingBar.value end,
    setMode = function(mode) db.dotColors = mode end,
}
"""

failures = 0


def check(label, actual, expected):
    global failures
    ok = actual == expected
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {label:<58} {actual}" + ("" if ok else f"   (expected {expected})"))


rt = LuaRuntime(unpack_returned_tuples=True)
t = rt.execute(HARNESS)
mk = lambda *items: rt.table_from([rt.table_from(i) for i in items])

t.setMode("school")
list3 = mk({"name": "Corruption", "school": 32, "damage": 60},
           {"name": "Immolate", "school": 4, "damage": 45},
           {"name": "Serpent Sting", "school": 8, "damage": 15})
cum = t.update(list3)
t.set(120, "mob", cum)
check("segment 1 running total", t.segment(1)[0], 60)
check("segment 2 running total", t.segment(2)[0], 105)
check("segment 3 running total", t.segment(3)[0], 120)
check("unused segment 4 sits at the total (zero width)", t.segment(4)[0], 120)
check("marker total", t.total(), 120)
check("segments 1-3 shown, 4 hidden", [t.segment(i)[1] for i in (1, 2, 3, 4)], [True, True, True, False])
check("dividers after 1 and 2 only", [t.segment(i)[2] for i in (1, 2, 3)], [True, True, False])
check("Corruption is Shadow purple at 50% opacity", t.segment(1)[3], "0.7,0.35,1,0.5")
check("Immolate is Fire orange", t.segment(2)[3], "1,0.55,0.15,0.5")
check("breakdown text", t.text(list3),
      "DoTs: |cffb359ffCorruption 60|r · |cffff8c26Immolate 45|r · |cff59ff59Serpent Sting 15|r")

t.setMode("each")
t.update(list3)
first = t.segment(1)[3]
swapped = mk({"name": "Immolate", "school": 4, "damage": 45}, {"name": "Corruption", "school": 32, "damage": 60})
t.update(swapped)
check("'each' mode: Corruption keeps its color when order changes", t.segment(2)[3], first)
check("'each' mode: two DoTs get different colors", t.segment(1)[3] != t.segment(2)[3], True)

many = mk(*[{"name": f"DoT{i}", "school": 32, "damage": 10} for i in range(10)])
cum = t.update(many)
check("10 DoTs: last of 8 segments covers the rest", cum[8], 100)

t.update(None)
check("single-color mode: segments hidden", [t.segment(i)[1] for i in (1, 2)], [False, False])

print(f"\n{'all passed' if not failures else str(failures) + ' FAILED'}")
sys.exit(1 if failures else 0)
