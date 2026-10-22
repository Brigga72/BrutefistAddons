"""Port-specific regression: old target frames, legacy spell APIs, legacy settings."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
import test_load as base

assert not base.failures
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(base.FAKE_WOW)
lua.execute(r'''
local modern = C_Spell
function GetSpellInfo(id) return modern.GetSpellName(id) end
function GetSpellDescription(id) return modern.GetSpellDescription(id) end
C_Spell = nil
Settings = nil
local categoryCount = 0
function InterfaceOptions_AddCategory(panel)
    assert(panel.name == "DoesItDie")
    categoryCount = categoryCount + 1
end
function EraCategoryCount() return categoryCount end
TargetFrame = CreateFrame("Frame", "TargetFrame", UIParent)
-- The permissive upstream mock otherwise invents functions for missing uppercase fields.
TargetFrame.TargetFrameContent = false
TargetFrame.TargetFrameContainer = false
TargetFramePortrait = CreateFrame("Texture", "TargetFramePortrait", TargetFrame)
TargetFrameHealthBar = CreateFrame("StatusBar", "TargetFrameHealthBar", TargetFrame)
TargetFrameHealthBar:SetMinMaxValues(0, 100)
TargetFrameHealthBar:SetValue(100)
targetGuid = "era-mob"
''')
helpers = lua.execute(base.HELPERS)
namespace = lua.table()
addon = Path(__file__).resolve().parents[1] / 'addons' / 'DoesItDie'
toc = (addon / 'DoesItDie.toc').read_text(encoding='utf-8-sig')
assert '## Interface: 11509' in toc
for filename in toc.splitlines():
    filename = filename.strip()
    if filename.endswith('.lua'):
        helpers.load(filename, (addon / filename).read_text(encoding='utf-8-sig'), namespace)
helpers.fire('ADDON_LOADED', 'DoesItDie')
assert lua.globals().EraCategoryCount() == 1
helpers.fire('UNIT_SPELLCAST_SUCCEEDED', 'player', 'era-cast', 172)
total, count, _ = namespace.tracking.targetRemainingDamage()
assert count == 1 and total == 40, (total, count)
lua.globals().now = 1003
helpers.fire('UNIT_COMBAT', 'target', 'WOUND', '', 10, 32)
namespace.refresh()
helpers.update(0.1)
total, count, _ = namespace.tracking.targetRemainingDamage()
assert count == 1 and total == 30, (total, count)
assert not any('failed' in str(msg).lower() or 'error' in str(msg).lower() for msg in lua.globals().chat.values())
print('PASS: Era legacy spell APIs, target frame, options registration, Corruption cast and tick')
