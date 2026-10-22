Adapted from the original DoesItDie tests by Joe Greive, MIT licensed. The addon and its MIT LICENSE are in ../addons/DoesItDie. Test file paths were changed for this repository; test_load.py allows import by the new Era-specific scenario. The mock accepts unknown frame methods, so these tests do not establish visual correctness or actual Era API availability.

Run with Python and lupa==2.8:

    python tests-doesitdie/test_tracking.py
    python tests-doesitdie/test_display.py
    python tests-doesitdie/test_era.py

test_era.py also runs the original complete load/options suite. It then creates a new mocked session with no C_Spell, no Settings service, and the legacy target frame globals, and tests an actual Corruption cast/tick through the loaded addon.
