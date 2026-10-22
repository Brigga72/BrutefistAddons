# Brutefist Death Review diagnostics 0.1.0

This is the API investigation stage, not the completed death analysis addon. It records the player's combat events, health, movement speed and a fixed list of common healing potion IDs. It does not issue advice or automate actions. No spell cooldown or aura analysis is implemented yet.

1. Install through Update Addons and /reload (restart if the client does not discover the new addon).
2. Carry a common healing potion: Minor, Lesser, Healing, Greater, Superior, Major, Super or Runic Healing Potion. Forever-specific variants are not yet catalogued.
3. Outside combat, type `/bdeath start`.
4. Fight an ordinary enemy. Use a healing potion while injured if appropriate. Do not deliberately die.
5. Soon after combat, type `/bdeath stop`, then `/bdeath report`.
6. Ctrl+A, Ctrl+C in the report window and paste the text into the development chat.

Recording retains the latest 30 seconds, capped at 800 rows. A high event rate can shorten that window. Stop promptly after the fight so the relevant events remain. Death automatically freezes the recording. Recording starts only by command and is off after reload. `/bdeath previous` retrieves the last saved report after reload. The report contains character/attacker names and GUIDs from combat; review it before sharing. Only the latest saved report is retained in SavedVariables.

Registered events are not assumed functional. API results are counted separately in and out of combat. Missing, rejected or restricted data is reported without attempting to bypass restrictions. A readable result does not prove potion usability or survival. Nil results remain unknown. API absence, no event delivery and payload restrictions may prevent detailed reconstruction.

The movable copy window opens outside combat. Gameplay behavior, secret-value handling and event delivery require the beta test above; mocked regression tests cannot establish client capabilities.
