# DoesItDie - Era test port 0.8.2-era.1

Unofficial Classic Era 1.15.9 test port of DoesItDie by Joe Greive, based on upstream commit cce4a306abb45456899782c025a729f93832402d retrieved October 22, 2026.

Source: https://github.com/swirllyman/DoesItDie
Author's releases: https://www.curseforge.com/wow/addons/does-it-die

The original MIT license and copyright are included in LICENSE. This is a community adaptation, not an official release or endorsement. The upstream addon folder name and saved variable DoesItDieDB are retained; do not install another DoesItDie build alongside it. The CurseForge project ID was removed so this test copy does not advertise itself as the author's released package.

Changes: Era interface manifest (11509), an older-client spell-name fallback, and legacy options-category registration. The upstream target-frame compatibility, options window, locale parsers, artwork, tick-learning and DoT prediction engine are retained. No Forever-only spells are hard-coded into a new Era spell table; the parser reads this client's tooltips. The source also contains support for spells unavailable in Era, which simply cannot be cast there.

This first port deliberately retains the author's UNIT_COMBAT matching engine. Estimates can confuse similar ticks or hits from other attackers, do not model future healing, and are not a guarantee of death. It does not yet use Era's combat log for exact per-caster attribution or aura-removal tracking. Test solo first. Learned sizes can be stale after gear/talent changes; `/did reset` clears them.

## In-game acceptance

1. Reload (or restart if needed), target an ordinary enemy, and type `/did`.
2. Use the live preview / simulation to verify the marker and icon. `/did skull` tests icon placement.
3. On a Warlock, cast Corruption alone and let it tick without wanding or pet attacks. Compare the displayed remaining damage with the remaining ticks. Repeat with Immolate, then Curse of Agony. Do not deliberately put the character at risk.
4. Check refreshing a DoT, changing targets and its expiry. The marker should update and disappear when nothing is expected to tick.
5. If using ElvUI or another target frame, use the original Advanced frame picker to choose its health bar and icon anchor. Automatic attachment to every replacement frame is not guaranteed.
6. If anything fails, `/did debug` enables the author's tracking log; report the error and class/spell/rank.

The package passed the author's mocked load/UI, display, tracking and a port-specific legacy-API scenario. Actual Era rendering and prediction still need the in-game checks above. It is Era-only in this repository; keep the author's released Forever build for Forever.
