# Brutefist Gear Advisor v0.6.1

Standalone experimental item-tooltip comparisons for Brigga Brutefist, level 30, two-handed Enhancement damage. This addon is independent of Brutefist Combat Companion. Keep your existing swing timer installed.

## v0.6.1 talent-reader correction

The in-game report exposed incorrect raw passive descriptions: Ancestral Knowledge selected rank 2 described the maximum 10%, and Flurry selected rank 5 described 1%. These two coefficients now use selected rank mappings, 2% Intellect per Ancestral Knowledge rank and 5% haste per Flurry rank, within ranks 1 through 5. Regression tests deliberately use the misleading description text. Windfury, Mental Dexterity and Mental Quickness were correctly read in the supplied report.

## v0.6.0 adaptive profile, usage and skill warnings

Automatic talent coefficients are read from selected trait definitions and recognized English spell descriptions for Ancestral Knowledge, Mental Dexterity, Mental Quickness and Flurry. Only readable, recognized values override the saved manual profile; missing definitions or unfamiliar/localized text retain manual settings and are listed in diagnostics. Other talents are not automatically modeled. Existing character-sheet crit already contains static crit talents. Crit calibration still requires fresh controlled readings after a level or talent change.

Windfury searches known ranks 8232/8235/10486/16362 using IsPlayerSpell. It reads rendered C_TooltipInfo.GetSpellByID text, including the bonus AP and proc chance. Raw spell descriptions are not used for AP because they may omit talent modifiers. If unavailable, your saved manual AP (such as 64) remains intact. Automatic values are session overlays, not destructive changes to saved manual settings.

Stormstrike usage observes player spell 17364 during complete combat sessions, rejects duplicate cast GUIDs and non-player events, and measures total combat time per cast, including combat without Stormstrike. After at least 5 casts and 60 completed combat seconds, weapon comparisons use that average interval. Samples are session-only, reset on level/talent/spell changes, and exclude incomplete world transitions or sessions over 30 minutes. This reflects pauses and resets in aggregate, not a rotation simulation. Armor comparison math is unchanged.

Weapon warnings read current skill/max/modifiers on each hover. They report lower skill separately from the potential damage verdict; no unverified hit penalty is applied. Missing skill rows do not imply untrained proficiency. IsUsableItem is not an equip check. Diagnostics retain the last hovered weapon, not food. Confidence wording describes the modeled difference: under 0.5 index points is too close for weapons, 0.5 to under 3 is small, 3 or more is clear in the model. These thresholds do not imply statistical confidence or measured DPS accuracy.

Test: reload, hover a weapon, run `/bgear diag` and review Automatic profile / usage. Fight normally with Stormstrike, leave combat, then hover again. No new screenshots are required.

## v0.5.1 weapon-skill probe

Outside combat, hover a candidate weapon and run `/bgear diag`. Copy the Weapon skill / usability API probe section. It reports legacy and modern skill-reader availability and readable rows, equipped weapon types and raw usability results, plus the last hovered item. It never changes skill-panel headers or scoring. If rows are hidden, expand the weapon skill header in your Skills panel and rerun. Missing, failed and restricted API results are labeled.

## v0.5.0 two-handed weapons

Compares two-handed weapons using base damage/speed, talent-derived AP and spell damage, calibrated crit, simplified Flurry, Stormstrike and Windfury. One-handed/offhand comparisons and unknown item procs remain unsupported. Similar results say TOO CLOSE TO CALL. Native tooltip still determines proficiency, weapon skill and unique restrictions. Armor comparison math is unchanged.

Weapon model defaults are manual assumptions: Windfury 20% chance, two additional attacks, 104 bonus AP (Wowhead Forever rank-1 display), no internal cooldown, no recursive or Stormstrike-triggered procs. Forever databases disagree on the rank-1 AP bonus (46 vs 104); use `/bgear set windfuryAP NUMBER` to match your in-game tooltip, including any talent modifier. `/bgear set windfuryICD NUMBER` allows a verified cooldown. No hidden cooldown is claimed as verified. Stormstrike is modeled once every 8 seconds with the base weapon roll plus AP using an assumed 3.3-second two-handed normalization. Its spell bonus is held common between weapons, and cooldown resets, mana downtime, armor, misses and proc interactions are omitted. Change `stormstrikeInterval` to your typical usage interval. These are estimates, not simulated DPS.

Sources: https://www.wowhead.com/forever/spell=8232/windfury-weapon and https://www.wowhead.com/forever/spell=17364/stormstrike. Stormstrike's data lists Normalized Weapon Damage. No flat slow-weapon bonus is added.

## v0.4.1 flat spell-damage items

Unconditional all-school spell damage/healing Equip bonuses are recognized when their amount matches the spell-power stat supplied by the item API. They count once, alongside Intellect-derived spell damage. Short explanations now include net spell damage. Procs, school-specific bonuses, healing-only bonuses and unmatched effect text remain unsupported.

## v0.4.0 simple verdicts
Normal tooltips now show a verdict and one explanation. Scores, model percentages, crit conversions, and Flurry calculations are hidden in /bgear diag. No math is removed from the internal model.

For supported armor/rings: model index gains of at least 0.5 favor the candidate; losses of at least 0.5 favor the equipped item. Within that window, a candidate with no losses in Armor, Stamina or Intellect and at least one gain is favored for questing survival/mana. The reverse favors the equipped item. Mixed survival/mana tradeoffs say TOO CLOSE TO CALL. This is a questing decision heuristic, not proof of an actual DPS gain.

Unknown stats/effects, unsupported weapons/trinkets, unavailable model data, or missing calibration produce CANNOT ASSESS or CALIBRATION NEEDED instead of a false yes/no. Items above your level say cannot equip yet. Other proficiency/unique-equipped restrictions still need the native tooltip. Rings get a separate verdict for each equipped ring.

Reasons use approximate rounded AP changes and item Armor/Stamina/Intellect differences. HP/mana point conversions are not guessed. Intellect is treated as a mana tradeoff and Stamina/Armor as survival tradeoffs without assigning hidden damage weights to them.

Update, /reload, then hover Archer's Gloves with Brawler's equipped. Expected: YES, upgrade for questing, similar estimated damage and better survival/mana, with about 1 AP lost and 4 Stamina, 10 Armor, 7 Intellect gained. Your saved calibration remains intact.

## v0.3.1 survival tradeoffs
Item comparisons now show Armor, Stamina, and Spirit deltas separately from damage. Questing index differences strictly below 0.5 points in magnitude are neutral-colored and labeled Similar modeled damage: compare survival benefits. The 0.5-point threshold is a presentation heuristic, not a statistical confidence interval. These stats do not change the damage model.

## v0.3.0 typical questing model
Armor and ring comparisons now show a questing index change, separate melee/spell proxy changes, and an estimated Flurry speed-factor contribution. Your current two-handed weapon stays fixed. Existing calibration remains saved and is reused when level/talents match. Both measured crit rates must exist. If data is unavailable or you compare weapons/trinkets, the old score is explicitly labeled fallback.

### Test this update
1. Replace BrutefistGear and /reload. Your v0.2.0 calibration should still appear in /bgear diag.
2. With either calibrated glove equipped, hover the other pair. Look for questing index, melee proxy, spell proxy, and Flurry lines.
3. Send the tooltip or copy the Typical questing model section and recent Questing comparison line from /bgear diag.
4. No new calibration swap is needed unless your level/talents changed.

### Model assumptions and formulas
This is an exploratory index, NOT an accurate full rotation simulation or predicted DPS gain. There is no verified automatic stat-to-DPS calibration yet.

Baseline index = 100. Candidate index = 100 * [meleeShare * candidateMelee/baselineMelee + (1-meleeShare) * candidateSpell/baselineSpell]. Default meleeShare = 0.85, an adjustable assumption for typical questing. An index gain of +1 point means a 1-percent relative change in this proxy under the assumptions, NOT necessarily 1-percent actual damage.

Melee proxy = [fixed weapon base DPS + effective AP/apPerDPS] * [1 + meleeCritFraction] * estimatedFlurrySpeedFactor. Default apPerDPS=14 is an unverified Classic-style AP scaling assumption for Forever. Candidate AP uses the existing configured Strength/Intellect conversions. Melee crit uses your measured Agility conversion, not the old arbitrary Agility score weight. The current sheet crit already includes talents such as Thundering Strikes; its flat bonus is not added again. Melee crit multiplier assumes the 100-percent extra damage shown in your tooltip.

The simplified Flurry model assumes independent melee-swing crits, with q = 1-(1-c)^3 as the fraction of swings made while Flurry is active. The average speed factor is 1/[(1-q)+q/(1+flurryHaste)], default flurryHaste=0.25 from your talent tooltip. The tooltip's Flurry line is already INCLUDED in the melee proxy, not an additional bonus to add. The estimate ignores missed/glancing attacks, special-attack triggers, Windfury charge consumption, exact proc/refresh rules, finite fights and target changes. q is a modeled fraction of swings, not measured time uptime.

Nature spell proxy = [spellBase + spellCoefficient * Nature spell damage] * [1 + 0.5 * Nature spellCritFraction]. Defaults spellBase=100 and spellCoefficient=0.4 are synthetic placeholders for an occasional spell, NOT values read from your shock rank. This model includes only relative spell-damage and calibrated Intellect-to-Nature-crit effects, not mana limits, cooldowns, spell hit/resist, shock choice, or spell-specific multipliers. The 50-percent additional spell crit effect is from your character-sheet tooltip.

Windfury and Stormstrike are not explicitly simulated. The auto-attack proxy stands in for the melee portion of a questing profile; their actual contributions can respond differently to stats. Armor, stamina, recovery, hit, sockets, special effects and set bonuses remain outside this damage index. Unsupported effects are still flagged. A positive proxy index alone is not a guaranteed upgrade.

Current stats are read outside combat. The model requires an equipped two-hander and both valid calibrated rates. It does not read restricted data or change combat actions. Flurry rank, talent coefficients, and model assumptions remain manually configured; a new talent fingerprint invalidates the old measured crit rates.

Additional /bgear set keys:
- meleeShare 0.85 (range 0 through 1)
- flurryHaste 0.25 (range 0 through 1, use 0 to disable)
- apPerDPS 14 (positive, up to 100)
- spellBase 100 (positive, up to 100)
- spellCoefficient 0.4 (0 through 100)

The old apWeight, spellWeight, and agilityWeight apply only to the fallback stat score. They do not influence the questing index.

Local tests verify equal items give zero index change, increasing AP/crit/spell power increases the relevant proxy, Flurry contributions are included only once, boundary probabilities, unsupported weapon types, restricted/missing data, settings ranges and actual tooltip rendering. Live-client model output still needs verification.

## v0.2.0 controlled calibration
This version adds /bgear baseline and /bgear calibrate. No screenshots are needed for the readings.

### Your first test
1. Equip Brawler's Leather Gloves. Stay outside combat, let temporary stat buffs expire, and keep the same buffs for both readings.
2. Run /bgear baseline. It must confirm that the baseline was saved.
3. Equip Archer's Gloves of the Eagle, changing no other gear or talents. Wait two seconds for the character sheet to settle.
4. Run /bgear calibrate. It should print and save the measured crit conversions.
5. Run /bgear diag and copy the Calibration section if there is an error or to verify the first saved result.

Baseline stores current stats, all equipped item links/stats, selected talent node ranks/entries, active helpful aura IDs and application counts, character identity, level, and Advisor coefficients. Baseline is session-only. Both commands require readable data outside combat. Aura durations are excluded so a naturally counting-down buff does not invalidate a test, but buff additions/removals and stack changes do. The talent check covers the active config returned by the client; other talent systems not represented in its trees are not assumed to be covered.

Calibration rejects a changed character/level, talents, buffs, manual score profile, multiple changed slots, weapons/trinkets, an empty changed slot, unsupported stats, or Equip/Use/proc effects. Use plain-stat armor or rings. Weapon imbues are not a separate calibration fingerprint; keep the same weapon/imbue during the test. Set-bonus changes without readable aura changes may not be detected, so do not use set-bonus-changing swaps.

At least 4 observed Agility difference measures melee crit percentage points per effective Agility. At least 5 item Intellect difference measures Nature spell crit percentage points per item Intellect, including the current talent multiplier. They are empirical local estimates, not universal formulas. Intellect and Agility can change together because these two crit measurements are separate. The measured crit contributions appear separately in item comparisons. They do NOT alter the weighted stat score or estimate Flurry uptime.

AP and Nature spell-damage differences are recorded. A mixed Strength/Intellect swap cannot isolate both AP coefficients, and rounded spell-damage changes do not justify replacing the confirmed 30-percent talent coefficient. Those score coefficients stay unchanged. Automatic calibration estimates stat-to-crit conversion, not stat-to-DPS weights.

Results persist per character, level, and active talent fingerprint. Complementary results at the same level/talents are retained. A level-up notification asks you to repeat the swap; comparisons use no saved rates from another level or talent fingerprint. If aura/talent data is unavailable, calibration fails explicitly, rather than ignoring its guards.

## v0.1.2 calibration API probe
Run /bgear probe outside combat, then copy the Calibration API probe section. It reads effective primary stats, total AP, melee crit, spell crit and damage by school, healing, and talent/aura reader availability. Missing, failed, and restricted API fields are explicit. The probe changes no score weights or talent coefficients. This is the first client-validation step before implementing baseline/item-swap calibration.

## v0.1.1 changes
Recognizes ITEM_MOD_DAMAGE_PER_SECOND_SHORT as base weapon DPS. It is used in the separate weapon line, not included in the stat score. DPS remains visible even if tooltip damage/speed parsing is incomplete. Identical diagnostic lines are suppressed while retained in the bounded history; diagnostics report the number suppressed. Tooltip comparisons still refresh normally.

## Install and first test
1. Copy the BrutefistGear folder into the Forever client's Interface/AddOns folder. The .toc must be directly inside BrutefistGear.
2. Enable Brutefist Gear Advisor on the character selection AddOns screen and log in. If you install a newly named addon while the game is open, restart the client if /reload does not discover it.
3. Hover an equippable armor item in your bags or an item link. It should add a gold comparison section against your equipped item.
4. Try an Intellect item. Send a screenshot of the comparison and /bgear diag, which opens a copyable report outside combat. Ctrl+A then Ctrl+C. Escape closes it.
5. Compare a ring to check both ring slots. Hover a two-handed weapon to check separate base DPS, average-hit, and speed differences.
6. If item information is pending, hover again after it has loaded.

## Confirmed talent profile
These are manually configured from your supplied tooltips and description:
- Ancestral Knowledge 2/5: +4% Intellect.
- Mental Dexterity: AP equal to 100% of Intellect.
- Mental Quickness 2/2: spell damage/healing up to 30% of Intellect. The starter model uses 0.3 as the coefficient; exact rounding is not simulated.

For an item's stats, effective Intellect = item Intellect * 1.04. Effective AP includes direct AP, Strength contribution, and effective Intellect. Spell damage includes direct spell damage and effective Intellect * 0.3. Baseline character-sheet totals are not multiplied again.

Example: +10 item Intellect contributes approximately +10.4 AP and +3.12 spell damage. The score separately weights those contributions; it does not add a second independent Intellect weight.

The profile does NOT read or automatically update your talent tree yet. Reconfigure the coefficients when talents change. Other Intellect/Strength buffs, rounding, and multiplicative interactions are not modeled.

## Starter score, not measured DPS
Default score = effective AP * 1 + effective spell damage * 0.3 + Agility * 1.

Strength -> 2 AP is a conventional starter assumption, NOT verified for Forever from the screenshots. AP weight 1, spell-damage weight 0.3, and Agility weight 1 are adjustable placeholders, NOT derived from your build or performance. Agility weight includes no explicit level-based crit conversion. Stamina, Spirit, armor, and recovery do not influence the damage score and are secondary tradeoffs.

Positive/negative score lines mean higher/lower weighted modeled stats. They are not predicted damage percentages, guaranteed upgrades, or automatic equip recommendations. The tooltip labels the score experimental. Check usability, armor proficiency, unique-equipped constraints, socket/enchant effects, and the full native tooltip before replacing an item.

Thundering Strikes 5/5 (+5% crit) and Flurry 5/5 (+25% speed for three swings after a melee crit) are recorded context, but NOT modeled in v0.1. Crit/hit rating, crit percentage, Flurry uptime, attack-speed effects, weapon skill, and special damage schools need validated conversion data. Unsupported nonzero stat keys are flagged and appear in diagnostics. Equip/Use/proc/set effects are conservatively flagged when an English tooltip scan identifies them. The scan is not an exhaustive effect parser and does not claim completeness on other locales.

## Weapon comparisons
Weapons get separate base DPS, average base hit, speed differences, and a stat score. The weapon fields are parsed from standard English tooltip damage and Speed text, with a native-comparison fallback when parsing is unavailable. Positive speed difference means a slower weapon, not automatically better. The stat score EXCLUDES weapon damage, Windfury, Stormstrike, Flurry, and proc modeling. Weapon recommendations remain incomplete.

## Settings
/bgear lists commands and coefficients.
/bgear diag opens diagnostics.
/bgear reset restores starter defaults.
/bgear set KEY VALUE changes a coefficient and saves it; hover again to refresh.

Examples:
- /bgear set intellectAP 1
- /bgear set intellectBonus 0.04
- /bgear set intellectSP 0.3
- /bgear set strengthAP 2
- /bgear set apWeight 1
- /bgear set spellWeight 0.3
- /bgear set agilityWeight 1

Keys are case-sensitive; values must be finite numbers from 0 through 100. These are coefficient values, so 0.04 means 4%, not 4.

## API boundaries
Uses C_Item.GetItemInfo, C_Item.GetItemStats, C_TooltipInfo.GetHyperlink when available, GetInventoryItemLink, and the modern TooltipDataProcessor hook. No combat log, target combat analysis, automated equip, or protected actions. Secret values/tables are guarded before comparison, indexing, or formatting. Restricted/unavailable item stats stop a comparison instead of becoming zero. Missing modern tooltip hooks are reported; no legacy hook is guessed.

Current tooltip integration targets the normal GameTooltip and ItemRefTooltip only. Third-party tooltip surfaces may need support later. Diagnostics retain the last 40 comparison/error lines in memory, not persistent history.

## Validation
Local mocked Lua tests passed for startup, configured Intellect conversions, armor scoring, dual ring slots, weapon metrics, unsupported stat keys, restricted values, pending item data, recursive tooltip processing, settings, and diagnostic history limits. Forever 1.60.1 build 70338 item APIs and actual in-game tooltip formatting still need your first diagnostic capture.

Primary API references:
https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua
https://github.com/kemayo/wow-appearancetooltip/blob/master/addon.lua

No code from those projects is included.
