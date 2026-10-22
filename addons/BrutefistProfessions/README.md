# Brutefist Profession Planner 0.2.0

Install the BrutefistProfessions folder in Interface/AddOns, then reload. This addon is independent of Gear Advisor and the Combat Companion. Visit the bank once, then hover Leatherworking materials. `/bprof` reports status.

Tooltips show current skill, next milestone (75/150/225/300), current bag quantity, bank quantity from your last bank visit, estimated requirements and remaining quantity. Bank data is per character and realm. Unknown bank data is explicitly labeled, never treated as zero. Counts use the client item-count API and need in-game verification for Forever's bank behavior. Bags refresh on hover; bank snapshots refresh while the bank is open.

Initial route: Leatherworking, default hide-based path, through 225. Source: https://www.wow-professions.com/forever/leatherworking-leveling-guide . The guide describes a fast/cheap route, not a mathematically proven fastest route. It currently has no verified plan from 225 to 300, which is marked unavailable. Cooking is supported through selected recipe bands. Fishing and separate Skinning progression are not implemented; gathered leather and cooking fish are counted normally.

Craft estimates are prorated upward when partway through a recipe's skill range. Yellow recipe outcomes are uncertain, so these are planning estimates, not exact requirements. Intermediate outputs from future planned steps are credited once against later inputs. Already owned intermediates are counted as stock; missing intermediate stock is shown as needed, not automatically expanded into substitute recipes. Do not sell cured hides/belts that later steps require. Route recipe-output assumptions and partial-skill estimates need validation against the Forever crafting UI. Trainer availability and character-level gates still apply.

Uses guarded C_SkillInfo, C_Item.GetItemCount and modern tooltip hooks. It never automates crafting or purchasing. Bank counts are snapshots, not guaranteed current while the bank is closed; other storage and alts are excluded. Missing/restricted APIs fail visibly. The tooltip is outside-combat only.


## Cooking

Source: https://www.wow-professions.com/forever/cooking-leveling-guide . Defaults use a mixed ingredient route: boar, clams, ribs, eggs, raptor, yellowtail and salmon. These are choices within the guide, not a guarantee of the fastest route for your inventory. `/bprof cooking` lists the supported choices for each band. `/bprof cooking 50 fish` switches the 50-100 band to Longjaw Mud Snapper; `/bprof cooking 100 fish` and `/bprof cooking 130 fish` choose Catfish through 150. Only the selected recipe counts toward requirements. Alternative ingredients show a selection hint, never an additive required total. Recipe ownership, vendors and training quests are not detected.

Cooking tooltips use your current Cooking skill and the same 75/150/225/300 milestones. Counts prorate partial bands and round up. The guide explicitly labels 225-300 untested in Forever, so tooltips warn about it. Requirements for the Artisan unlock quest and campfire equipment are excluded from crafting-material totals. Not every alternative on the site is included, faction-limited crab-claw and other special alternatives are omitted. Fishing skill itself has no material requirement calculation.
