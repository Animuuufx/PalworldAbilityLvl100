# WorkSuitabilityUnlock v0.1

Standalone UE4SS Lua mod for Palworld.

## Goal

Allows Applied Work Suitability Handbooks to pass the game's normal `CanUseTargetWorkSuitabilityRankUp` eligibility check even when the target Pal does not already have that suitability.

Supported handbook item families:

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

## Install

Copy the `WorkSuitabilityUnlock` folder into the same UE4SS Mods location used by the other Lua mods. Keep `enabled.txt` and `Scripts/main.lua` in place.

This mod is independent from `WorkSuitability100` and does not modify its files.

## v0.1 testing target

The first implementation overrides the native handbook eligibility function and then lets Palworld's normal handbook transaction execute. This is intentionally minimal so the game's own persistence and rank-up code remains responsible for saving the new suitability.

Test with a Pal that has **no Kindling** (or another supported suitability), then use the matching Applied Handbook. If the handbook is accepted but the new suitability is not created, the next patch will target the native mutation/storage path directly.

## Log

Look for lines beginning with:

`[WorkSuitabilityUnlock v0.1]`

A successful handbook attempt should log the handbook code, target parameter, and item full name.
