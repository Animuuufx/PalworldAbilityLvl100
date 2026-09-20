# WorkSuitability100 v4.1

Runtime UE4SS mod for Palworld that raises Pal Work Suitability rank handling from the normal level-10 ceiling to level 100 and makes ranks above 10 affect real work throughput.

## Install

Copy the `WorkSuitability100` folder into the UE4SS `Mods` directory. Keep `enabled.txt`, `Scripts/main.lua`, and `Native/WorkSuitability100.dll` together.

The native DLL removes the rank-10 cap. The Lua runtime layer handles work-speed scaling.

## v4.1 runtime scaling

v4.1 no longer depends on extending Palworld's rank-10 `TArray` tables to rank 100.

It hooks the live work-speed functions instead:

- `GetCraftSpeedByWorkSuitability`
- `GetCraftSpeed_withBuff_WorkSuitability`
- `GetCraftSpeed`
- `GetCraftSpeed_withBuff`
- `GetMiningDamageRate`
- `GetDeforestDamageRate`
- `GetCollectionDropNumRate`

It also hooks `PalWorkProgressMultiType:AddProgressForWorkType` as a fallback for newer multi-suitability production stations. The fallback reads the workers actually assigned to that work object, checks the matching suitability rank, and only multiplies the progress amount when the normal craft-speed path did not already apply the turbo scaling.

This specifically covers newer production paths such as Advanced Workshop, Ancient Workbench, and Ancient Furnace without blindly multiplying nested speed calls several times.

## Speed curve

- Rank 10: 1x
- Rank 20: about 10x
- Rank 30: about 100x
- Rank 100: about 100,000x

Rank 100 is intended to feel effectively instant for Handiwork, Kindling, Watering, Planting, Electricity, Medicine Production, Cooling, and other craft/progress-based work.

Mining and Lumbering also scale their actual resource damage. Gathering scales work speed and has a separately capped yield multiplier so rank 100 does not attempt to spawn absurd loose-item counts.

## Target build

The native DLL in this branch targets the Palworld executable stored through Git LFS in this repository:

- EXE SHA256: `44b6295e70aa37b83d1c42ce1dcf865a7ffadcd300298b0e49a02bad8eb83443`
- EXE size: `161802312`

## Logs

Native rank-cap log:

`WorkSuitability100/Native/WorkSuitability100.log`

UE4SS console/log entries from v4.1 include hook registration plus one-time messages when each suitability/rank scaling path is actually used.
