# Brutefist Death Review 0.2.0

Supports an Era test installation using the Vanilla manifest for interface 11509. The regular manifest targets Forever interface 16001. Both clients use the same Lua recorder. Era results validate that client only; Forever must be tested separately. Use `Update Era Death Review.cmd` to install/update only this diagnostic addon in Classic Era.

This stage adds a readable fight/death review and conservative potion observations. It records the player's combat events, health, movement speed and a fixed list of common healing potion IDs. It does not automate actions. Class defensive spell cooldowns, control effects, aura restrictions and escape-route analysis are not implemented yet.

`/bdeath report` shows incoming damage, healing, failed casts, low-health points and potential potion windows. A window requires at least 1.5 seconds of consecutive observations (no more than one second apart) while alive, in combat and at/below 35% health, with a potion carried, its cooldown clear, enabled state 1 and usability true. Missing observations close the window. These are potential opportunities, not confirmed mistakes; being stunned or otherwise prevented from acting is not checked. Short cooldowns of up to three seconds are reported as temporary lockouts, possibly global cooldowns, without asserting their cause. Both short and long active cooldowns are excluded from availability windows, even when the usability API returns true.

On death, the report identifies the last incoming hit within two seconds, explicitly as the last recorded hit rather than a guaranteed cause. If no such hit exists, the cause remains unknown. Only events in the retained recording are analyzed. Death capture is still pending an in-game test; do not deliberately die to test it.

1. Install through Update Addons and /reload (restart if the client does not discover the new addon).
2. Carry a common healing potion: Minor, Lesser, Healing, Greater, Superior, Major, Super or Runic Healing Potion. Forever-specific variants are not yet catalogued.
3. Outside combat, type `/bdeath start`.
4. Fight an ordinary enemy. Use a healing potion while injured if appropriate. Do not deliberately die.
5. Soon after combat, type `/bdeath stop`, then `/bdeath report`.
6. Ctrl+A, Ctrl+C in the report window and paste the text into the development chat. `/bdeath diagnostics` opens the raw API report if needed.

Recording retains the latest 30 seconds, capped at 800 rows. A high event rate can shorten that window. Stop promptly after the fight so the relevant events remain. Death automatically freezes the recording. Recording starts only by command and is off after reload. `/bdeath previous` retrieves the last saved review after reload (or the raw report from a pre-0.2 recording). Raw diagnostics contain character/attacker names and GUIDs; the review includes names. Review reports before sharing. Only the latest review and its raw report are retained in SavedVariables. Upgrading does not convert earlier saved raw reports into structured reviews.

Registered events are not assumed functional. API results are counted separately in and out of combat. Missing, rejected or restricted data is reported without attempting to bypass restrictions. A readable result does not prove potion usability or survival. Nil results remain unknown. API absence, no event delivery and payload restrictions may prevent detailed reconstruction.

The movable copy window opens outside combat. Gameplay behavior, secret-value handling and event delivery require the beta test above; mocked regression tests cannot establish client capabilities.
