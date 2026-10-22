# Brutefist Profession Planner 0.1.0

Install the BrutefistProfessions folder in Interface/AddOns, then reload. This addon is independent of Gear Advisor and the Combat Companion. Visit the bank once, then hover Leatherworking materials. `/bprof` reports status.

Tooltips show current skill, next milestone (75/150/225/300), current bag quantity, bank quantity from your last bank visit, estimated requirements and remaining quantity. Bank data is per character and realm. Unknown bank data is explicitly labeled, never treated as zero. Counts use the client item-count API and need in-game verification for Forever's bank behavior. Bags refresh on hover; bank snapshots refresh while the bank is open.

Initial route: Leatherworking, default hide-based path, through 225. Source: https://www.wow-professions.com/forever/leatherworking-leveling-guide . The guide describes a fast/cheap route, not a mathematically proven fastest route. It currently has no verified plan from 225 to 300, which is marked unavailable. Cooking, Fishing and separate Skinning progression are not implemented in this first version; gathered leather is counted normally.

Craft estimates are prorated upward when partway through a recipe's skill range. Yellow recipe outcomes are uncertain, so these are planning estimates, not exact requirements. Intermediate outputs from future planned steps are credited once against later inputs. Already owned intermediates are counted as stock; missing intermediate stock is shown as needed, not automatically expanded into substitute recipes. Do not sell cured hides/belts that later steps require. Route recipe-output assumptions and partial-skill estimates need validation against the Forever crafting UI. Trainer availability and character-level gates still apply.

Uses guarded C_SkillInfo, C_Item.GetItemCount and modern tooltip hooks. It never automates crafting or purchasing. Bank counts are snapshots, not guaranteed current while the bank is closed; other storage and alts are excluded. Missing/restricted APIs fail visibly. The tooltip is outside-combat only.
