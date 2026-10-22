"""Run from repository root with Python + lupa installed (Lua 5.1 preferred)."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

for path in Path('addons/BrutefistDeathReview').glob('*.lua'):
    LuaRuntime().execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))
for test in ('tests-death-review/test.lua', 'tests-death-review/test-era.lua', 'tests-professions/test.lua'):
    LuaRuntime().execute(Path(test).read_text(encoding='utf-8-sig'))
