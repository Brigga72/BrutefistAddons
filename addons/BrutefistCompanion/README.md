# Brutefist Combat Companion v0.4.2

Standalone main-hand swing HUD for Brigga Brutefist in WoW Forever. No dependencies. Weapon imbue and Lightning Shield modules have been removed.

## v0.4.2 appearance
The HUD header now reads MAIN HAND. A bundled alpha texture gives the window rounded corners, a dark textured background, and layered bronze edging. Gold header text and ivory timer text give the HUD a Classic WoW inspired appearance. Copy the Media folder with the rest of the addon. Timer behavior and edit controls are unchanged.

## Install or update
Close the game. Replace the existing BrutefistCompanion folder in your Forever client's Interface/AddOns folder with the folder in this ZIP. Confirm the .toc is directly inside that folder. Enable the addon and log in. For an in-session update, /reload after replacing the files. Position, scale, and visibility settings persist.

TOC targets interface 16001. Live diagnostics confirmed native swing events on client 1.60.1 build 70338. Future client changes may require revalidation.

## Swing cue
The blue bar drains toward the next estimated main-hand swing. During combat, the final 0.3 seconds turn amber and show SWING SOON: hold hard casts. This is a cue to let an approaching swing happen before starting a hard cast. It does not apply to every instant ability and does not promise that casting after a swing leaves subsequent swings unaffected.

The cue is suppressed when timing is unavailable, during a player hard cast, after a player attack-speed event, outside combat, or after the estimate reaches zero. It resumes from a readable native main-hand PLAYER_SWING event. The bar never invents repeating swings. The demo shows a clearly labeled simulated cue outside combat.

This is an estimate from event receipt time, not detection of a guaranteed imminent hit. Movement, range, delayed events, parry haste, and spell interactions can affect it. No automated targeting or casting, no combat-log dependency, and no attempts to reveal restricted data.

## Move and resize
Click EDIT outside combat. Drag the header to move. Drag the bottom-right grip to scale the entire HUD, or scroll the mouse wheel over the header in edit mode. Click DONE to lock. Scale ranges from 50 to 200 percent. Settings persist through reload. Adjustments are blocked during combat.

## Commands
- /bcc warning 0.3: set warning window in seconds, range 0.05 through 1. Default 0.3.
- /bcc unlock or /bcc lock: edit mode.
- /bcc scale 1.2: scale 0.5 through 2.
- /bcc show or /bcc hide: visibility.
- /bcc reset: default position, scale, and visibility.
- /bcc demo: 15 seconds of simulated timing and amber cue.
- /bcc record on or /bcc record off: bounded event history, off initially.
- /bcc clear: clear history.
- /bcc diag: copyable diagnostic report outside combat, Ctrl+A then Ctrl+C. Escape closes it.

## Test one change at a time
1. Confirm version 0.4.2 in /bcc diag and that the two removed tracker rows are gone.
2. Run /bcc demo to see the amber cue. Verify EDIT, dragging, resizing, and DONE.
3. Auto-attack a safe enemy. Watch for the amber final window, then a return to blue when the next native swing arrives.
4. Start a hard cast and confirm the cue clears. Activate an attack-speed buff and confirm the estimate waits for the next native event.
5. If the cue feels too late, try /bcc warning 0.4. If too distracting, try /bcc warning 0.2.

Local mocked Lua tests passed for loading, restricted/invalid values, countdowns, speed/cast/death resets, bounded diagnostics, edit/resize controls, coordinate saving, warning appearance and clearing, combat gating, threshold validation, and removal of tracker dependencies. Actual visual timing still needs in-game testing.

## Modular files
Core.lua: safe event registration, guarded values, module registry.
Swing.lua: native main-hand countdown state.
HUD.lua: compact renderer, amber cue, move/resize controls.
Diagnostics.lua: bounded event capture and copyable report.
Bootstrap.lua: saved settings and commands.

API research references:
https://github.com/Thunderz96/forever-addon-kit
https://github.com/m33shoq/M33kAuras/blob/main/M33kAuras/GenericTrigger.lua

No source code from those projects is bundled.
