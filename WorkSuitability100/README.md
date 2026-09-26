# WorkSuitability100 v4.1 — crash-safe native speed build

This build allows Pal Work Suitability ranks above 10 while avoiding the live Unreal container edits that caused the new-world crash in v4.0.

## What caused the crash

v4.0 resized Palworld-owned `CraftSpeeds` and special-work `TArray` values and then wrote modified rows back into `WorkSuitabilityDefineDataMap` while a world was loading.

That can invalidate a UE4SS/native wrapper while Palworld is still constructing its game settings. The result is a native access violation such as:

`EXCEPTION_ACCESS_VIOLATION writing address 0x0000000000001438`

Lua `pcall` cannot catch a native access violation, so delaying or wrapping those writes was not enough. v4.1 removes that approach completely.

## v4.1 behavior

- Lua only loads the native DLL.
- Lua performs **no** `PalGameSetting`, `TArray`, or `TMap` mutation.
- The existing validated rank-cap patch still raises suitability handling from 10 to 100.
- The DLL hooks the exact native `GetCraftSpeedByWorkSuitability` routine for the supplied Palworld executable.
- It reads the Pal's live `GetWorkSuitabilityRankWithCharacterRank` value.
- Ranks 1–10 keep vanilla speed.
- Ranks 11–100 scale the **real work-speed value returned to the facility**, not only the displayed rank.
- Because the hook sits in the shared suitability work-speed path, suitability-driven facilities such as workstations, furnaces and watering production use the higher value without needing per-building hard-coded names.
- Before installing, the DLL verifies the exact machine-code prologue at the target RVA. A changed Palworld executable causes the speed hook to be skipped instead of patching an unknown address.

## Scaling above rank 10

v4.1 keeps the scaling rule used by the previous attempt:

`factor = 1 + ((rank - 10) * 4.95)`

The DLL multiplies Palworld's own returned rank-10 work-speed value by that factor.

## Target build

- Palworld executable SHA-256: `44b6295e70aa37b83d1c42ce1dcf865a7ffadcd300298b0e49a02bad8eb83443`
- Executable size: `161802312`
- Craft-speed RVA: `0x2F79D30`
- Live rank getter RVA: `0x2F80390`

## Install

Delete/replace the **entire old `WorkSuitability100` folder** in your UE4SS `Mods` directory with the v4.1 folder, then fully restart Palworld.

Do not mix the v4.0 `Scripts/main.lua` with this DLL.

## Verify

After launching, open:

`Mods/WorkSuitability100/Native/WorkSuitability100.log`

A correct install should contain:

`SPEED HOOK installed speedRVA=0x2F79D30 rankRVA=0x2F80390`

`Native >10 work-speed scaling enabled.`

`Compatibility initialization successful (rank cap + real speed scaling).`

When a Pal with rank 11+ performs suitability work, the first few calls also log:

`SPEED suitability=... rank=... vanilla=... scaled=...`

That line proves the actual work-speed number is being changed.
