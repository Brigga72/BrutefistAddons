"""Simulates DoesItDie's DoT tracking (extracted from the addon) through scripted fights, with game APIs stubbed.

    pip install lupa
    python tools/test_tracking.py

Covers cast outcomes (dodge/parry/miss vs. auto-attacks), recasts, first-tick waiting and combo point counting.
Each scenario prints what the marker would count, and PASS/FAIL against the expectation.
"""
import os
import sys

import locale  # noqa: E402
locale.setlocale(locale.LC_CTYPE, "C")  # as in WoW: Lua's %d and %s follow the C library's locale
from lupa.lua51 import LuaRuntime  # WoW runs Lua 5.1

# An optional argument tests another copy of DoesItDie.lua (e.g. an older version, to see a test fail).
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "addons", "DoesItDie", "DoesItDie.lua")
src = open(SRC, encoding="utf-8").read()
# The files before DoesItDie.lua in the .toc (Locale.lua and the languages) put ns.locale on the namespace the
# chunks below use.
TOC = [line.strip() for line in open(os.path.join(os.path.dirname(SRC), "DoesItDie.toc"), encoding="utf-8")]
LOCALE_PRELUDE = "local ns = {}\n" + "".join(
    ";(function(...)\n" + open(os.path.join(os.path.dirname(SRC), name), encoding="utf-8").read()
    + "\nend)(\"DoesItDie\", ns)\n"
    for name in TOC[:TOC.index("DoesItDie.lua")] if name.endswith(".lua"))


def chunk(start_marker, end_marker):
    start = src.index(start_marker)
    return src[start:src.index(end_marker, start)]


HARNESS = LOCALE_PRELUDE + """
now = 100
log = {}
db = { ticks = {}, waitFirstTick = "off", estimateDuringCast = true }
local dotsByTarget = {}
local function isSecret(v) return false end
local function trace(msg) table.insert(log, string.format("%.2f %s", now, msg)) end
function GetTime() return now end
-- The target and the mobs behind visible nameplates (unit -> mob key).
local targetKey, plates = "mob", {}
local function unitKey(unit) if unit == "target" then return targetKey end return plates[unit] end
function UnitExists(unit) return unitKey(unit) ~= nil end
-- A unit's name is its mob key, unless given one (two mobs with the same name).
local names = {}
function UnitName(unit) return names[unit] or unitKey(unit) end
-- Whether the player can attack a unit (nil: the client can't say).
local attackable = {}
function UnitCanAttack(_, unit) return attackable[unit] end
-- Combo points: the API's reading (nil while secret), and Blizzard's display (ComboFrame, set by api.comboDisplay).
local comboReading
function GetComboPoints() return comboReading end
local castCount = 0
local SPELLS = {
    [1] = { "Corruption", "Corrupts the target, causing 40 Shadow damage over 12 sec." },
    [2] = { "Rake", "Rake the target for 19 damage and an additional 39 damage over 9 sec.  Awards 1 combo point." },
    [3] = { "Claw", "Claw the enemy, causing 27 additional damage.  Awards 1 combo point." },
    [4] = { "Rip", "Finishing move that causes damage over time. 1 point : 42 damage over 12 sec. 2 points: 71 damage over 12 sec. 5 points: 138 damage over 12 sec." },
    [5] = { "Rend", "Wounds the target causing them to bleed for 45 damage over 9 sec." },
    [6] = { "Bane of Agony", "Afflicts the target with agony, causing 72 Shadow damage over 24 sec.  This damage is dealt slowly at first, and builds up as the Bane reaches its full duration." },
    [7] = { "Serpent Sting", "Stings the target, causing 10 Nature damage over 15 sec.  Only one Sting per Hunter can be active on any one target." },
    -- Cast-time DoTs (Estimate during casting).
    [8] = { "Immolate", "Burns the enemy for 11 Fire damage and then an additional 20 Fire damage over 15 sec." },
    [9] = { "Shadow Bolt", "Sends a shadowy bolt at the enemy, causing 13 Shadow damage." },
    -- A German client (Classic Era deDE wording): names and descriptions both German.
    [10] = { "Krallenhieb", "Attackiert das Ziel mit Krallen, fügt 19 Punkt(e) Schaden sowie 39 Punkt(e) zusätzlichen Schaden im Verlauf von 9 Sek. zu. Gewährt 1 Combopunkt." },
    [11] = { "Zerfetzen", "Finishing-Move, der Schaden im Lauf der Zeit verursacht. Der Schaden erhöht sich pro Combopunkt sowie durch Eure Angriffskraft:\\n   1 Punkt: 42 Schaden im Verlauf von 12 Sek.\\n   2 Punkte: 66 Schaden im Verlauf von 12 Sek.\\n   5 Punkte: 138 Schaden im Verlauf von 12 Sek." },
    [12] = { "Fluch der Pein", "Verflucht das Ziel mit Pein und fügt 24 Sek. lang 72 Punkt(e) Schattenschaden zu. Zuerst wird der Schaden langsam zugefügt und nimmt dann zu, bis der Fluch seine Gesamtdauer erreicht hat." },
    [13] = { "Feuerregen", "Lässt einen feurigen Regen niedergehen, der 8 Sek. lang Feinde im Wirkungsbereich mit 168 Punkt(en) Feuerschaden verbrennt." },
    [14] = { "Immolation Trap", "Place a Fire trap that will burn the first enemy to approach for 690 Fire damage over 15 sec. Trap will exist for 1 min. Only one Fire trap can be active at a time." },
    [16] = { "Shadow Word: Pain", "A word of darkness that causes 40 Shadow damage over 12 sec." },
    [15] = { "Explosive Trap", "Place a Fire trap that explodes when an enemy approaches, causing 201 to 257 Fire damage and 330 additional Fire damage over 20 sec to all within 10 yards. Trap will exist for 1 min. Only one Fire trap can be active at a time." },
}
local function spellNameAndDescription(id) return SPELLS[id][1], SPELLS[id][2] end
""" + chunk("local UPDATE_INTERVAL", "-- User options") + chunk(
    "local function schoolFromWords", "---------------------------------------------------------------------------\n-- Settings") + """
local api = {}
function api.reset(waitMode, estimateDuringCast)
    for k in pairs(dotsByTarget) do dotsByTarget[k] = nil end
    for k in pairs(db.ticks) do db.ticks[k] = nil end
    db.waitFirstTick = waitMode or "off"
    lastBuilder, lastDotCast, lastOutcome, armedTrap = nil, nil, nil, nil
    for k in pairs(sentTargets) do sentTargets[k] = nil end
    db.estimateDuringCast = estimateDuringCast ~= false
    if dropCastInProgress then dropCastInProgress("reset") end
    resetComboCount()
    targetKey, plates, names, attackable, comboReading = "mob", {}, {}, {}, nil
    ComboFrame = nil
    log = {}
end
function api.learn(spellID, perTick) db.ticks[spellID] = perTick end
function api.learned(spellID) return db.ticks[spellID] end
-- Pressing the button (UNIT_SPELLCAST_SENT, which names the cast's target) and the server confirming it
-- (UNIT_SPELLCAST_SUCCEEDED).
function api.send(spellID, guid, targetName)
    if not guid then castCount = castCount + 1; guid = "cast-" .. castCount end
    onCastSent(spellID, guid, targetName); return guid
end
function api.succeed(spellID, guid)
    if onCastSucceeded then onCastSucceeded(guid, spellID) end
    return onPlayerCast(spellID, guid)
end
function api.cast(spellID) return api.succeed(spellID, api.send(spellID)) end
-- A cast with a cast time, event by event as the addon's handler runs them (SENT comes before START). The
-- handlers are looked up by name, so without the feature these do nothing (and the checks fail instead of erroring).
function api.start(spellID, guid, targetName)
    api.send(spellID, guid, targetName)
    if onCastStart then onCastStart(guid, spellID) end
end
function api.name(unit, name) names[unit] = name end
function api.ended(event, spellID, guid) if onCastEnded then onCastEnded(event, guid, spellID) end end
function api.targetChanged() if dropCastInProgress then dropCastInProgress("target changed") end end
function api.target(key) targetKey = key; resetComboCount() end
function api.plate(unit, key) plates[unit] = key end
-- Hits and avoids on the target, or on another unit (e.g. a nameplate).
function api.hit(amount, school, flag, unit) return onUnitCombat(unit or "target", "WOUND", flag or "", amount, school or 1) end
function api.avoid(action, school, unit) onUnitCombat(unit or "target", action, "", 0, school or 1) end
function api.advance(seconds) now = now + seconds; housekeep(now) end
function api.marker() local damage, count = targetRemainingDamage(); return damage .. " dmg from " .. count .. " DoT(s)" end
function api.markerOn(key) local total = 0; for _, e in ipairs(dotBreakdown(key)) do total = total + e.damage end; return math.floor(total + 0.5) .. " dmg" end
function api.counted() return countedPoints end
-- Any UNIT_COMBAT event (ABSORB, ...).
function api.raw(unit, action, amount, school) return onUnitCombat(unit, action, "", amount, school) end
function api.canAttack(unit, value) attackable[unit] = value end
function api.comboAPI(points) comboReading = points end
-- Blizzard's combo point display showing `lit` of 5 points (nil: hidden).
function api.comboDisplay(lit)
    ComboFrame = { IsShown = function() return lit ~= nil end }
    for i = 1, 5 do
        _G["ComboPoint" .. i] = { IsShown = function() return true end,
            Highlight = { GetAlpha = function() return (lit and i <= lit) and 1 or 0 end } }
    end
end
function api.readCombo() local points = readComboPoints(); return points end
function api.cacheCombo(points) lastComboPoints, lastComboAt = points, now end
function api.comboForCast() local points, source = comboPointsForCast(); return tostring(points) .. " " .. source end
function api.provisional()
    for _, entry in ipairs(dotBreakdown("mob")) do if entry.provisional then return true end end
    return false
end
function api.log() return table.concat(log, "\\n") end
return api
"""

sim = LuaRuntime(unpack_returned_tuples=True).execute(HARNESS)
failures = 0


def check(label, actual, expected):
    global failures
    ok = str(actual) == str(expected)
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'}  {label:<64} {actual}" + ("" if ok else f"   (expected {expected})"))


# Corruption: 4 ticks of 10, learned so it shows straight away.
sim.reset(); sim.learn(1, 10); sim.cast(1)
check("Corruption lands: shown immediately", sim.marker(), "40 dmg from 1 DoT(s)")
sim.advance(3); sim.hit(10, 32)
check("  after first tick", sim.marker(), "30 dmg from 1 DoT(s)")

sim.reset(); sim.learn(1, 10); sim.cast(1); sim.advance(0.1); sim.avoid("RESIST", 32)
check("Corruption resisted: dropped", sim.marker(), "0 dmg from 0 DoT(s)")
check("  log says dropped", "right after Corruption; dropped" in sim.log(), True)
sim.advance(2.9); sim.hit(10, 32)
check("  a same-school hit at tick time doesn't bring it back", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(2, 13); sim.cast(2); sim.advance(0.05); sim.hit(19, 1); sim.advance(0.25); sim.avoid("DODGE")
check("Rake hit, then an auto-attack dodged: still shown", sim.marker(), "39 dmg from 1 DoT(s)")
check("  Rake's combo point still counted", sim.counted(), 1)

sim.reset(); sim.learn(2, 13); sim.cast(2); sim.advance(0.05); sim.avoid("PARRY")
check("Rake parried: dropped", sim.marker(), "0 dmg from 0 DoT(s)")
check("  combo point taken back", sim.counted(), 0)

sim.reset(); sim.learn(1, 10); sim.avoid("MISS", 32); sim.advance(0.1); sim.cast(1)
check("Miss arrives just BEFORE the cast event: dropped", sim.marker(), "0 dmg from 0 DoT(s)")

# Player feedback (CurseForge): a bleed on a mob immune to bleeds still showed its full size. Rake's direct part
# hits and only the bleed is IMMUNE; the hit used to settle the cast, so the IMMUNE after it was ignored.
sim.reset(); sim.learn(2, 13); sim.cast(2); sim.advance(0.05); sim.hit(19, 1); sim.advance(0.05); sim.avoid("IMMUNE")
check("Rake hit, then its bleed IMMUNE: dropped", sim.marker(), "0 dmg from 0 DoT(s)")
check("  log says why", "IMMUNE after Rake's direct hit" in sim.log(), True)
check("  combo point still counted (the direct part landed)", sim.counted(), 1)
sim.advance(1.0); sim.hit(13, 1); sim.advance(3.0); sim.hit(13, 1)
check("  white hits at tick times don't bring it back", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(2, 13); sim.avoid("IMMUNE"); sim.advance(0.02); sim.hit(19, 1); sim.advance(0.05); sim.cast(2)
check("Same, both results just BEFORE the cast event: dropped", sim.marker(), "0 dmg from 0 DoT(s)")
check("  combo point still counted", sim.counted(), 1)

sim.reset(); sim.learn(2, 13); sim.cast(2); sim.advance(0.05); sim.hit(19, 1); sim.advance(1.0); sim.avoid("IMMUNE")
check("Rake hit, an IMMUNE a second later (something else): still shown", sim.marker(), "39 dmg from 1 DoT(s)")

sim.reset(); sim.learn(2, 13); sim.cast(2); sim.advance(0.05); sim.hit(19, 1); sim.advance(0.05)
sim.avoid("DODGE"); sim.advance(0.05); sim.avoid("IMMUNE")
check("Rake hit, an auto-attack dodged, then the bleed IMMUNE: dropped", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.cast(8); sim.advance(0.05); sim.hit(11, 4); sim.advance(0.05); sim.avoid("IMMUNE", 1)
check("Immolate hit, then a Physical IMMUNE (the pet's): waits for its first tick", sim.marker(), "0 dmg from 0 DoT(s)")
sim.advance(2.9); sim.hit(4, 4)
check("  its first tick shows it", sim.marker(), "16 dmg from 1 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.cast(8); sim.advance(0.05); sim.hit(11, 4); sim.advance(0.05); sim.avoid("IMMUNE", 4)
check("Immolate hit, then a Fire IMMUNE: dropped", sim.marker(), "0 dmg from 0 DoT(s)")

# Replay of log 123506.4: first Corruption of the session (nothing learned). At its first tick a Shadow Bolt
# (26) and the real tick (10) land in the same instant, bolt first. Previously 26 was learned as the tick size.
sim.reset(); sim.cast(1); sim.advance(3.0); sim.hit(26, 32); sim.hit(10, 32)
check("Replay: Shadow Bolt + tick in the same instant: the 10 is the tick", sim.marker(), "30 dmg from 1 DoT(s)")
check("  log shows the swap", "SWAP Corruption tick: 26 was another hit, 10 is the tick" in sim.log(), True)
sim.reset(); sim.learn(1, 10); sim.cast(1); sim.advance(3.0); sim.hit(10, 32); sim.hit(26, 32)
check("  tick first, bolt second: no swap", sim.marker(), "30 dmg from 1 DoT(s)")

# Replay of the rest of that log: Corruption had learned 29 (from Shadow Bolts), so every real tick of 10-11
# was rejected and each cast was dropped as "never ticked". Two on-rhythm ticks now relearn it.
sim.reset(); sim.learn(1, 29); sim.cast(1)
sim.advance(3.0); sim.hit(11, 32)
check("Replay: learned 29, first real tick (11) still rejected", sim.marker(), "116 dmg from 1 DoT(s)")
sim.advance(3.0); sim.hit(10, 32)
check("  second on-rhythm tick (10): relearned, not dropped", sim.marker(), "21 dmg from 1 DoT(s)")
check("  and the saved tick size is fixed", sim.learned(1), 10.5)
sim.advance(3.0); sim.hit(11, 32)
check("  next tick matches normally", sim.marker(), "11 dmg from 1 DoT(s)")

sim.reset(); sim.learn(1, 10); sim.cast(1)
sim.advance(1.0); sim.hit(26, 32); sim.advance(1.0); sim.hit(27, 32)
check("Two off-rhythm Shadow Bolts don't trigger a relearn", sim.learned(1), 10)

# Replay of log 166015.8: Bane of Agony, 72 over 24s, back-loaded ticks 3,3,3,3,6,6,6,6,9,9,9,9 every 2s.
# Previously it learned 3, estimated half the damage, rejected the 6s, relearned, and dropped the 9s.
sim.reset(); sim.cast(6)
check("Replay: Bane of Agony estimate at cast is the full 72", sim.marker(), "72 dmg from 1 DoT(s)")
remaining = []
for amount in (3, 3, 3, 3, 6, 6, 6, 6, 9, 9, 9, 9):
    sim.advance(2.0); sim.hit(amount, 32)
    remaining.append(sim.marker().split()[0])
check("  remaining after each tick follows the ramp", remaining,
      ["69", "66", "63", "60", "54", "48", "42", "36", "27", "18", "9", "0"])
log = sim.log()
check("  all 12 ticks matched", log.count("TICK Bane of Agony"), 12)
check("  no relearn or unmatched hits", ("RELEARN" in log) or ("not matched" in log), False)
check("  learned the average tick (6)", float(sim.learned(6)), 6.0)
sim.advance(3.0); sim.cast(6)
check("  next cast starts from the learned average: 72", sim.marker(), "72 dmg from 1 DoT(s)")

# The same ramp on a German client: "Fluch der Pein" must get Agony's 2s ticks and shape from the name tables.
sim.reset(); sim.cast(12)
check("German: Fluch der Pein estimate at cast is the full 72", sim.marker(), "72 dmg from 1 DoT(s)")
for amount in (3, 3, 3, 3, 6, 6, 6, 6, 9, 9, 9, 9):
    sim.advance(2.0); sim.hit(amount, 32)
log = sim.log()
check("  all 12 ticks matched", log.count("TICK Fluch der Pein"), 12)
check("  no relearn or unmatched hits", ("RELEARN" in log) or ("not matched" in log), False)

# German builders count combo points ("Gewährt 1 Combopunkt"), and the German finisher reads its point table.
sim.reset(); sim.cast(10); sim.advance(0.05); sim.hit(19, 1)
sim.advance(1); sim.cast(10); sim.advance(0.05); sim.hit(19, 1)
check("German: two Krallenhieb, 2 combo points", sim.counted(), 2)
sim.advance(1); sim.cast(11)
check("  Zerfetzen uses the counted 2 points: 66 over 12s, every 2s",
      "2 combo points (counted): 66 dmg over 12s, school 1, tick every 2s" in sim.log(), True)

sim.reset(); sim.cast(13)
check("German: Feuerregen (Rain of Fire) is ignored", sim.marker(), "0 dmg from 0 DoT(s)")

# Replay of the in-game miss (log 99223.7): 2-point Rip missed, white hits of 20-22 kept landing near tick
# times. Previously a white hit at +2.6s "proved" the Rip and brought it back.
sim.reset(); sim.learn("4x2", 15.2)
sim.cast(3); sim.advance(0.05); sim.hit(20, 1); sim.advance(1); sim.cast(3); sim.advance(0.05); sim.hit(20, 1)
sim.advance(1); sim.cast(4); sim.avoid("MISS")
for t, amount in ((0.8, 20), (1.8, 20), (1.0, 21), (0.9, 22), (1.8, 20)):
    sim.advance(t); sim.hit(amount, 1)
check("Replay: missed Rip stays gone through white hits", sim.marker(), "0 dmg from 0 DoT(s)")

# Replay of a landed 3-point Rip (log 99200.3): ticks 21,21,20,20 every ~2s, with white hits of the SAME size
# in between. All four ticks must be matched and no white hit.
sim.reset()
for _ in range(3):
    sim.cast(3); sim.advance(0.05); sim.hit(20, 1); sim.advance(1)
start = 0.0
sim.cast(4)
events = [(0.9, 21), (1.3, 20), (1.9, 21), (2.5, 21), (3.5, 20), (3.9, 21), (4.3, 22), (5.5, 22), (6.0, 20),
          (6.8, 46), (8.0, 20)]
for at, amount in events:
    sim.advance(at - start); start = at; sim.hit(amount, 1)
lines = sim.log().split("\n")
cast_at = float(next(line for line in lines if "CAST Rip" in line).split()[0])
ticks = [round(float(line.split()[0]) - cast_at, 1) for line in lines if "TICK Rip" in line]
check("Replay: landed 3-point Rip matches exactly its 4 ticks", len(ticks), 4)
check("  and they're the right ones (seconds after the cast)", ticks, [1.9, 3.9, 6.0, 8.0])

# Rend (3 ticks of 15 every 3s) with white hits of ~20 and white crits of ~40 in between.
sim.reset(); sim.learn(5, 15); sim.cast(5)
sim.advance(2.95); sim.hit(20, 1)
check("Rend: white hit (20) at tick time isn't a tick (learned 15)", sim.marker(), "45 dmg from 1 DoT(s)")
sim.advance(0.05); sim.hit(15, 1)
check("  the real tick (15) is", sim.marker(), "30 dmg from 1 DoT(s)")
sim.advance(0.15); sim.hit(15, 1)
check("  a second 15 right after the tick isn't another tick", sim.marker(), "30 dmg from 1 DoT(s)")
sim.advance(0.85); sim.hit(15, 1)
check("  a 15 off the 3s rhythm (+1s) isn't a tick", sim.marker(), "30 dmg from 1 DoT(s)")
sim.advance(1.95); sim.hit(41, 1, "CRITICAL")
check("  white crit (41) at tick time isn't a tick crit", sim.marker(), "30 dmg from 1 DoT(s)")
sim.advance(0.05); sim.hit(30, 1, "CRITICAL")
check("  tick crit (30 = 2x15) is", sim.marker(), "15 dmg from 1 DoT(s)")
check("  and doesn't raise the expected tick size", "expecting 15.0 for this tick" in sim.log().split("\n")[-1], True)

sim.reset(); sim.learn(1, 10); sim.avoid("MISS"); sim.advance(1.0); sim.cast(1)
check("Old miss (1s before cast): ignored, shown", sim.marker(), "40 dmg from 1 DoT(s)")

sim.reset(); sim.learn(1, 10); sim.cast(1); sim.advance(3); sim.hit(10, 32); sim.advance(1)
sim.cast(1); sim.advance(0.1); sim.avoid("RESIST", 32)
check("Corruption ticking, recast resisted: earlier one kept", sim.marker(), "30 dmg from 1 DoT(s)")

sim.reset(); sim.cast(3); sim.advance(0.05); sim.hit(27, 1); sim.advance(1); sim.cast(3); sim.advance(0.05); sim.avoid("DODGE")
sim.advance(1); sim.cast(3); sim.advance(0.05); sim.hit(27, 1)
check("Claw hit, Claw dodged, Claw hit: 2 combo points", sim.counted(), 2)
sim.advance(1); sim.cast(4)
check("  Rip uses the counted 2 points", "2 combo points (counted)" in sim.log(), True)

sim.reset("unsure"); sim.cast(1)
check("'When unsure', never seen tick: waits", sim.marker(), "0 dmg from 0 DoT(s)")
sim.advance(3); sim.hit(10, 32)
check("  first tick: shown with the real tick size", sim.marker(), "30 dmg from 1 DoT(s)")

# Replay of log 253548.7: Serpent Sting (10 over 15s, first cast of the session) with the arrow's travel time:
# the first tick came 3.7s after the cast, not 3s, with Arcane Shot and auto shots around it. Previously the
# late tick went unmatched and the sting was dropped as "never ticked" at +6.5s.
sim.reset(); sim.cast(7)
sim.advance(2.2); sim.hit(28, 64); sim.hit(15, 1)
sim.advance(1.5); sim.hit(4, 8)
check("Replay: Serpent Sting's first tick 3.7s after the cast is matched", "TICK Serpent Sting 4" in sim.log(), True)
sim.advance(0.5); sim.hit(13, 1); sim.advance(2.1); sim.hit(14, 1)
check("  not dropped as never ticked", "DROP" in sim.log(), False)
remaining = []
for amount in (3, 3, 3, 4):  # at 6.7, 9.7, 12.7, 15.7s
    sim.advance(3.0 if remaining else 0.4)
    sim.hit(amount, 8)
    remaining.append(sim.marker().split()[0])
check("  the other four ticks keep the landing's rhythm", sim.log().count("TICK Serpent Sting"), 5)
check("  and count down to zero", remaining[-1], "0")
sim.advance(1.0)
check("  expires after the fifth tick", "EXPIRE Serpent Sting" in sim.log(), True)

sim.reset(); sim.learn(7, 3); sim.cast(7); sim.advance(3.7)
check("Serpent Sting in flight: no tick lost before the first one lands", sim.marker(), "15 dmg from 1 DoT(s)")
sim.advance(3.5); sim.advance(3.0)
check("  never ticks at all: still dropped", "DROP Serpent Sting" in sim.log(), True)

sim.reset(); sim.learn(1, 10); sim.cast(1); sim.advance(3.8); sim.hit(10, 32)
check("Corruption (no travel): a tick 0.8s late still doesn't count", "TICK Corruption" in sim.log(), False)

# Focus casts (issue #12): UNIT_SPELLCAST_SENT names the cast's target, so a /cast [@focus] macro's DoT goes on
# the focus when that name is the focus's and not the target's.
sim.reset(); sim.target("A"); sim.plate("focus", "B"); sim.succeed(6, sim.send(6, None, "B"))
check("[@focus] Agony: on the focus", sim.markerOn("B"), "72 dmg")
check("  not on the target", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset(); sim.target("A"); sim.plate("focus", "B"); sim.succeed(6, sim.send(6, None, "A"))
check("Agony cast at the target, with a focus: on the target", sim.marker(), "72 dmg from 1 DoT(s)")
sim.reset(); sim.target("A"); sim.plate("focus", "B"); sim.name("target", "Boar"); sim.name("focus", "Boar")
sim.succeed(6, sim.send(6, None, "Boar"))
check("Same-named target and focus: on the target, as before", sim.marker(), "72 dmg from 1 DoT(s)")
sim.reset(); sim.target("A"); sim.name("focus", "B"); sim.succeed(6, sim.send(6, None, "B"))
check("Focus whose GUID is secret: skipped, not put on the target", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset(); sim.learn(8, 4); sim.target("A"); sim.plate("focus", "B"); sim.start(8, "cast-1", "B")
check("[@focus] Immolate while casting: estimated on the focus", sim.markerOn("B"), "20 dmg")
check("  not on the target", sim.marker(), "0 dmg from 0 DoT(s)")
sim.succeed(8, "cast-1")
check("  lands on the focus", sim.markerOn("B"), "20 dmg")

# Player feedback: tab-dotting. An instant DoT's cast event comes a round trip after the button press; a player
# who tabs straight away has a new target by then.
sim.reset(); sim.target("A"); guid = sim.send(6); sim.target("B"); sim.succeed(6, guid)
check("Agony sent on A, tabbed to B before the cast event: on A", sim.markerOn("A"), "72 dmg")
check("  and not on B", sim.marker(), "0 dmg from 0 DoT(s)")
check("  log names the mob", "on A, the target when sent" in sim.log(), True)

# Player feedback: "it forgets previous targets" when chain pulling. Ticks on a mob that's neither the target
# nor on a visible nameplate never reach the addon; that isn't proof the DoT didn't land.
sim.reset(); sim.learn(1, 10); sim.target("A"); sim.cast(1); sim.advance(0.5); sim.target("B"); sim.advance(9)
check("Corruption on A, tabbed away, A's ticks unseen: still tracked", sim.markerOn("A"), "10 dmg")
check("  not dropped as never ticked", "DROP" in sim.log(), False)
sim.target("A")
check("  back on A: shown", sim.marker(), "10 dmg from 1 DoT(s)")
sim.advance(3)
check("  and expires on time", sim.markerOn("A"), "0 dmg")

sim.reset(); sim.learn(1, 10); sim.target("A"); sim.cast(1); sim.target("B"); sim.plate("nameplate1", "A"); sim.advance(7)
check("Same, but A's nameplate is up and no tick came: dropped", "DROP Corruption" in sim.log(), True)

sim.reset(); sim.learn(1, 10); sim.target("A"); sim.cast(1); sim.target("B"); sim.plate("nameplate1", "A")
sim.advance(3); sim.hit(10, 32, "", "nameplate1")
check("Ticks on A's nameplate still count after tabbing away", sim.markerOn("A"), "30 dmg")

# Player feedback: Agony sometimes not recognized. The pet's (or a groupmate's) melee avoids right after the cast
# were taken as the spell's outcome.
sim.reset(); sim.learn(6, 6); sim.cast(6); sim.advance(0.1); sim.avoid("DODGE")
check("Agony, pet's melee dodged right after: ignored", sim.marker(), "72 dmg from 1 DoT(s)")
sim.advance(0.1); sim.avoid("RESIST", 32)
check("  the spell's own resist right after still drops it", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(6, 6); sim.cast(6); sim.advance(0.05); sim.hit(30, 1); sim.advance(0.1); sim.avoid("RESIST", 32)
check("Agony, pet's melee hit, then the spell's resist: dropped", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(6, 6); sim.cast(6); sim.advance(0.1); sim.avoid("MISS", 1)
check("Agony, a Physical miss right after: waits for its first tick", sim.marker(), "0 dmg from 0 DoT(s)")
sim.advance(1.9)
check("  first tick shows it (and flashes)", sim.hit(3, 32), "mob")
check("  with the ramp's remaining damage", sim.marker(), "69 dmg from 1 DoT(s)")

sim.reset(); sim.learn(6, 6); sim.cast(6); sim.advance(0.1); sim.avoid("MISS", 1); sim.advance(5)
check("  it never ticks: dropped", "DROP Bane of Agony" in sim.log(), True)

sim.reset(); sim.learn(6, 6); sim.plate("nameplate2", "other"); sim.cast(6); sim.advance(0.1)
sim.avoid("RESIST", 32, "nameplate2")
check("A resist on another mob doesn't touch the target's Agony", sim.marker(), "72 dmg from 1 DoT(s)")

sim.reset(); sim.learn(5, 15); sim.cast(5); sim.advance(0.05); sim.avoid("PARRY")
check("Rend (Physical) parried: still dropped straight away", sim.marker(), "0 dmg from 0 DoT(s)")

# Estimate during casting: Immolate (cast time; 20 Fire over 15s = 5 ticks of 4, learned) shows from the start
# of its cast, and the cast's own result takes over.
sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1")
check("Casting Immolate: shown while casting", sim.marker(), "20 dmg from 1 DoT(s)")
check("  as a provisional entry", sim.provisional(), True)
sim.advance(2.5)
check("  still the full estimate late in the cast", sim.marker(), "20 dmg from 1 DoT(s)")
sim.succeed(8, "cast-1")
check("  cast lands: replaced, not added", sim.marker(), "20 dmg from 1 DoT(s)")
check("  by the landed DoT (no provisional entry left)", sim.provisional(), False)
sim.ended("UNIT_SPELLCAST_STOP", 8, "cast-1"); sim.advance(1.0)
check("  STOP after the success doesn't remove it", sim.marker(), "20 dmg from 1 DoT(s)")
sim.advance(2.0); sim.hit(4, 4)
check("  first tick counts as usual", sim.marker(), "16 dmg from 1 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1"); sim.advance(1.0)
sim.ended("UNIT_SPELLCAST_STOP", 8, "cast-1"); sim.succeed(8, "cast-1")
check("Casting Immolate, STOP just before SUCCEEDED: one DoT", sim.marker(), "20 dmg from 1 DoT(s)")
sim.advance(1.0)
check("  still there after the STOP grace", sim.marker(), "20 dmg from 1 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1"); sim.advance(1.0)
sim.ended("UNIT_SPELLCAST_INTERRUPTED", 8, "cast-1")
check("Casting Immolate, interrupted: gone", sim.marker(), "0 dmg from 0 DoT(s)")
sim.advance(3.0); sim.hit(4, 4)
check("  and a Fire hit later doesn't bring it back", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1"); sim.advance(1.0)
sim.ended("UNIT_SPELLCAST_FAILED", 8, "cast-1")
check("Casting Immolate, failed: gone", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1"); sim.advance(0.5)
sim.ended("UNIT_SPELLCAST_FAILED", 8, "cast-2")
check("Casting Immolate, another press of it fails: still shown", sim.marker(), "20 dmg from 1 DoT(s)")
sim.ended("UNIT_SPELLCAST_STOP", 8, "cast-1")
check("  STOP without a success: kept briefly", sim.marker(), "20 dmg from 1 DoT(s)")
sim.advance(0.6)
check("  then gone", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1"); sim.advance(0.5); sim.targetChanged()
check("Casting Immolate, target changed: gone", sim.marker(), "0 dmg from 0 DoT(s)")

# Refreshing an Immolate that is ticking: the cast stands in for it, and an interrupted refresh leaves the old
# one exactly as it was, including a tick that landed during the cast.
sim.reset(); sim.learn(8, 4); sim.start(8, "cast-1"); sim.succeed(8, "cast-1")
sim.advance(3.0); sim.hit(4, 4); sim.advance(1.0)
check("Immolate ticking", sim.marker(), "16 dmg from 1 DoT(s)")
sim.start(8, "cast-2")
check("  refresh being cast: replaces it, not added", sim.marker(), "20 dmg from 1 DoT(s)")
sim.advance(2.0); sim.hit(4, 4)
check("  old one's tick during the cast", "TICK Immolate 4" in sim.log().split("\n")[-1], True)
sim.ended("UNIT_SPELLCAST_INTERRUPTED", 8, "cast-2")
check("  refresh interrupted: the old one is back, with its tick", sim.marker(), "12 dmg from 1 DoT(s)")
sim.start(8, "cast-3"); sim.advance(1.5); sim.succeed(8, "cast-3")
check("  refresh cast again and landed: one fresh DoT", sim.marker(), "20 dmg from 1 DoT(s)")

sim.reset(); sim.learn(8, 4); sim.cast(1); sim.start(8, "cast-1")
check("Corruption up, casting Immolate: both count", sim.marker(), "60 dmg from 2 DoT(s)")

sim.reset(); sim.start(9, "cast-1")
check("Casting Shadow Bolt (no DoT): nothing shown", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset("always"); sim.learn(8, 4); sim.start(8, "cast-1")
check("'Always' wait for first tick: not shown while casting either", sim.marker(), "0 dmg from 0 DoT(s)")


# Option off: the same casts give exactly what they give without the cast events at all.
def play(with_cast_events, estimate):
    sim.reset("off", estimate); sim.learn(8, 4)
    seen = []
    for guid, interrupt in (("cast-1", False), ("cast-2", True), ("cast-3", False)):
        if with_cast_events:
            sim.start(8, guid)
        seen.append(sim.marker())
        sim.advance(1.5)
        if with_cast_events and interrupt:
            sim.ended("UNIT_SPELLCAST_INTERRUPTED", 8, guid)
        elif with_cast_events:
            sim.succeed(8, guid); sim.ended("UNIT_SPELLCAST_STOP", 8, guid)
        elif not interrupt:
            sim.cast(8)
        seen.append(sim.marker())
        sim.advance(1.5); sim.hit(4, 4)
        seen.append(sim.marker())
    return seen, [line.split(" ", 1)[1] for line in sim.log().split("\n") if line]


check("Option off: casts with START/STOP events same as without", play(True, False), play(False, False))
check("  (and on, they differ)", play(True, True) != play(False, True), True)

# Player feedback: Immolation Trap wasn't tracked. Placing it only arms it; the DoT starts on whichever mob takes
# its first tick (138 = 690 / 5 ticks every 3s), which comes one interval after the trap springs.
sim.reset(); sim.cast(14)
check("Immolation Trap placed: nothing shown yet", sim.marker(), "0 dmg from 0 DoT(s)")
sim.advance(8)
check("  first tick on the target: shown (and flashes)", sim.hit(140, 4), "mob")
check("  with 4 ticks left at the observed size", sim.marker(), "560 dmg from 1 DoT(s)")
for amount in (138, 139, 140, 138):
    sim.advance(3); sim.hit(amount, 4)
check("  the other 4 ticks matched", sim.log().count("TICK Immolation Trap"), 4)
check("  and it counts down to zero", sim.marker().split()[0], "0")
sim.advance(3); sim.hit(139, 4)
check("  a used trap doesn't spring again", sim.log().count("sprung"), 1)

sim.reset(); sim.plate("nameplate1", "B"); sim.cast(14); sim.advance(10); sim.hit(138, 4, "", "nameplate1")
check("Trap sprung on another mob (seen on its nameplate): on that mob", sim.markerOn("B"), "552 dmg")
check("  not on the target", sim.marker(), "0 dmg from 0 DoT(s)")

sim.reset(); sim.cast(14); sim.advance(1); sim.hit(138, 4)
check("A Fire hit sooner than one tick after placing isn't the trap", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset(); sim.cast(14); sim.advance(5); sim.hit(900, 4); sim.hit(20, 4); sim.hit(138, 1)
check("Fire hits far off the trap's size, or other schools, aren't it", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset(); sim.cast(14); sim.advance(62); sim.hit(138, 4)
check("A trap sprung at the end of its minute still counts", sim.marker(), "552 dmg from 1 DoT(s)")
sim.reset(); sim.cast(14); sim.advance(70); sim.hit(138, 4)
check("  but not a hit after that", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset(); sim.cast(14); sim.advance(2); sim.cast(15); sim.advance(5); sim.hit(138, 4)
check("Explosive Trap placed after it replaces the armed trap", sim.marker(), "0 dmg from 0 DoT(s)")
sim.reset(); sim.learn(14, 200); sim.cast(14); sim.advance(5); sim.hit(138, 4)
check("With a learned size, a hit far off it isn't the trap", sim.marker(), "0 dmg from 0 DoT(s)")
sim.advance(1); sim.hit(205, 4)
check("  one close to it is", sim.marker(), "820 dmg from 1 DoT(s)")

# PR #14 (Ironship). Two DoTs of one school ticking for the same amount in the same instant: two hits from one
# token, not a copy. Previously the second was dropped as a duplicate and its DoT as "never ticked".
def ticks(name):
    return sim.log().count("TICK " + name)


sim.reset(); sim.learn(1, 10); sim.learn(16, 10); sim.cast(1); sim.cast(16)
for _ in range(2):
    sim.advance(3); sim.hit(10, 32); sim.hit(10, 32)
check("Corruption + SW:Pain ticking 10 at once: both ticks counted", (ticks("Corruption"), ticks("Shadow Word: Pain")),
      (2, 2))
sim.advance(3.5)
check("  neither dropped", "DROP" in sim.log(), False)
sim.reset(); sim.learn(1, 10); sim.learn(16, 10); sim.plate("nameplate1", "mob"); sim.cast(1); sim.cast(16)
sim.advance(3)
sim.hit(10, 32); sim.hit(10, 32, "", "nameplate1"); sim.hit(10, 32); sim.hit(10, 32, "", "nameplate1")
check("  each also seen on its nameplate (interleaved): one tick each", (ticks("Corruption"),
      ticks("Shadow Word: Pain")), (1, 1))
sim.reset(); sim.learn(1, 10); sim.plate("nameplate1", "mob"); sim.cast(1)
sim.advance(3); sim.hit(10, 32); sim.hit(10, 32, "", "nameplate1")
check("One DoT's tick seen on target and nameplate: counted once", sim.marker(), "30 dmg from 1 DoT(s)")

# A fully absorbed tick (ABSORB, 0) still proves the DoT is on; previously it was dropped as never ticked.
sim.reset(); sim.learn(1, 10); sim.cast(1)
for _ in range(3):
    sim.advance(3); sim.raw("target", "ABSORB", 0, 32)
check("Corruption's ticks absorbed by a shield: still tracked", sim.marker(), "10 dmg from 1 DoT(s)")
check("  the 0s don't teach a tick size", sim.learned(1), 10)
sim.reset(); sim.learn(1, 10); sim.learn(16, 10); sim.cast(1); sim.cast(16)
sim.advance(3); sim.raw("target", "ABSORB", 0, 32)
check("  an absorbed tick two DoTs could own: ignored", (ticks("Corruption"), ticks("Shadow Word: Pain")), (0, 0))

# Same-slot swap judged by the size learned before the cast, not the tooltip's (which leaves out attack power).
sim.reset(); sim.learn(2, 26); sim.cast(2); sim.advance(0.05); sim.hit(19, 1)
sim.advance(2.95); sim.hit(20, 1); sim.advance(0.1); sim.hit(26, 1)
check("Rake (learned 26, tooltip 13): a white 20 just before its 26 tick: swapped", "SWAP Rake" in sim.log(), True)
check("  learned size stays 26", sim.learned(2), 26)

# Combo points: a cached reading belongs to the target it was built on.
sim.reset(); sim.target("A"); sim.cacheCombo(5); sim.advance(1); sim.target("B")
check("5 points cached on A, finisher on B: points unknown (errs low)", sim.comboForCast(), "nil unknown")
# Blizzard's combo point display: only when the API has no number, never raising a readable one.
sim.reset(); sim.comboAPI(None); sim.comboDisplay(3)
check("API secret, display shows 3: 3", sim.readCombo(), 3)
sim.reset(); sim.comboAPI(2); sim.comboDisplay(5)
check("API reads 2, display shows 5: the API's 2", sim.readCombo(), 2)
sim.reset(); sim.comboAPI(None)
check("API secret, no display: unknown", sim.readCombo(), None)

# Soft targets: a friendly hard target never takes a cast; a cast named for the soft enemy goes on it.
sim.reset(); sim.target("friend"); sim.canAttack("target", False); sim.plate("softenemy", "B")
sim.succeed(1, sim.send(1, None, "B"))
check("Friendly target, DoT cast at soft enemy B: on B", (sim.markerOn("B"), sim.markerOn("friend")),
      ("40 dmg", "0 dmg"))
sim.reset(); sim.target("A"); sim.canAttack("target", True); sim.plate("softenemy", "B")
sim.succeed(1, sim.send(1, None, "B"))
check("Enemy target A, DoT cast at soft enemy B (mouseover): on B", (sim.markerOn("B"), sim.markerOn("A")),
      ("40 dmg", "0 dmg"))
sim.reset(); sim.target("A"); sim.canAttack("target", True); sim.plate("softenemy", "B")
sim.succeed(1, sim.send(1, None, "A"))
check("  cast at A itself: on A", (sim.markerOn("A"), sim.markerOn("B")), ("40 dmg", "0 dmg"))

print(f"\n{'all passed' if not failures else str(failures) + ' FAILED'}")
if failures:
    print("\nlog of last scenario:\n" + sim.log())
