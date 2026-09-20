# WorkSuitabilityUnlock v1.0

Standalone UE4SS Lua mod for Palworld.

## Goal

Allows Applied Work Suitability Handbooks to be used on Pals that do not naturally have the corresponding work suitability.

## Current suitability IDs

v1.0 updates the handbook mapping for the current Palworld enum, which includes Oil Extraction at ID 9:

- 1 Kindling (`EmitFlame`)
- 2 Watering
- 3 Planting (`Seeding`)
- 4 Generating Electricity
- 5 Handiwork
- 6 Gathering (`Collection`)
- 7 Lumbering (`Deforest`)
- 8 Mining
- 9 Oil Extraction
- 10 Medicine Production
- 11 Cooling
- 12 Transporting
- 13 Farming/Ranching (`MonsterFarm`)

Older builds of this mod used the pre-Oil-Extraction numbering, which could target the wrong suitability for Medicine, Cooling, Transporting, and Farming/Ranching.

## Supported handbooks

- `WorkSuitability_AddTicket_EmitFlame`
- `WorkSuitability_AddTicket_Watering`
- `WorkSuitability_AddTicket_Seeding`
- `WorkSuitability_AddTicket_GenerateElectricity`
- `WorkSuitability_AddTicket_Handcraft`
- `WorkSuitability_AddTicket_Collection`
- `WorkSuitability_AddTicket_Deforest`
- `WorkSuitability_AddTicket_Mining`
- `WorkSuitability_AddTicket_OilExtraction`
- `WorkSuitability_AddTicket_ProductMedicine`
- `WorkSuitability_AddTicket_Cool`
- `WorkSuitability_AddTicket_Transport`
- `WorkSuitability_AddTicket_MonsterFarm`

## Install

Copy the `WorkSuitabilityUnlock` folder into the UE4SS `Mods` directory. Keep `enabled.txt` and `Scripts/main.lua` in place.

This mod is independent from `WorkSuitability100`, but the two can be installed together: WorkSuitabilityUnlock allows missing suitability types to be added, while WorkSuitability100 removes the rank-10 ceiling and scales work throughput above rank 10.
