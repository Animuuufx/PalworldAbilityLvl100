# WorkSuitabilityUnlock v0.3

Standalone UE4SS Lua mod for Palworld.

## Goal

Allows Applied Work Suitability Handbooks to be used on Pals that do not naturally have the corresponding work suitability.

Supported handbooks:

- `WorkSuitability_AddTicket_EmitFlame` — Kindling
- `WorkSuitability_AddTicket_Watering` — Watering
- `WorkSuitability_AddTicket_Seeding` — Planting
- `WorkSuitability_AddTicket_GenerateElectricity` — Generating Electricity
- `WorkSuitability_AddTicket_Handcraft` — Handiwork
- `WorkSuitability_AddTicket_Collection` — Gathering
- `WorkSuitability_AddTicket_Deforest` — Lumbering
- `WorkSuitability_AddTicket_Mining` — Mining
- `WorkSuitability_AddTicket_ProductMedicine` — Medicine Production
- `WorkSuitability_AddTicket_Cool` — Cooling
- `WorkSuitability_AddTicket_Transport` — Transporting
- `WorkSuitability_AddTicket_MonsterFarm` — Farming/Ranching

## v0.3

The previous versions attempted to seed `WorkSuitability_*` reflected properties directly. That was incorrect for the handbook system.

Palworld exposes the actual persistent add-rank mutation as `UPalIndividualCharacterParameter::SetWorkSuitabilityAddRank(EPalWorkSuitability, int32)`. The save parameter also contains `GotWorkSuitabilityAddRankList`. v0.3 therefore leaves the native mutation completely intact and removes only the handbook eligibility gate, while logging the real rank-mutation function when it is reached.

## Install

Copy the `WorkSuitabilityUnlock` folder into the UE4SS `Mods` directory. Keep `enabled.txt` and `Scripts/main.lua` in place.

This mod is independent from `WorkSuitability100` and does not modify its files.

## Test

Use an Applied Kindling Handbook on a Pal that has no Kindling.

Expected log entries include:

`[WorkSuitabilityUnlock v0.3] Handbook eligibility override: EmitFlame`

and, if the native transaction reaches the mutation stage:

`[WorkSuitabilityUnlock v0.3] SetWorkSuitabilityAddRank called: ...`
