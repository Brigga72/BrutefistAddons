"""Run from repository root with Python + lupa installed (Lua 5.1 preferred)."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

for toc in Path('addons/BrutefistDeathReview').glob('*.toc'):
    for line in toc.read_text(encoding='utf-8-sig').splitlines():
        if line.strip() and not line.startswith('#'):
            assert (toc.parent / line.strip()).is_file(), (toc, line)

for path in Path('addons/BrutefistDeathReview').glob('*.lua'):
    LuaRuntime().execute('assert(loadstring(...))', path.read_text(encoding='utf-8-sig'))
for test in ('tests-death-review/test.lua', 'tests-death-review/test-era.lua', 'tests-death-review/test-analysis.lua', 'tests-professions/test.lua'):
    LuaRuntime().execute(Path(test).read_text(encoding='utf-8-sig'))
