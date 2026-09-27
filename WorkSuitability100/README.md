# WorkSuitability100 v4.2 — crash-safe lookup redirect

v4.2 removes the v4.1 whole-function native detour that still crashed while a new Palworld world was starting.

## What changed from v4.1

v4.1 correctly removed all Lua TArray/TMap mutations, but it still replaced the entry of
`GetCraftSpeedByWorkSuitability` with a hand-built trampoline.

The September 26 crash log confirms v4.1 loads successfully and reaches `MainWorld_5`, then
the process stops during world initialization. That makes the whole-function native detour the
remaining unsafe path.

v4.2 does **not** detour that function.

The supported executable contains this native sequence inside
`GetCraftSpeedByWorkSuitability`:

- rank is already in `r8d`
- suitability type is already in `dl`
- game settings object is already in `rcx`
- one direct call at RVA `0x2F79F05` goes to the rank→craft-speed lookup at RVA `0x2F16210`

Palworld's own lookup safely clamps an out-of-range rank to the final existing
`CraftSpeeds` entry. The relevant native logic compares the requested rank with the
array count and substitutes `count - 1` when the rank is too high.

v4.2 redirects **only that single validated CALL instruction** to a small near stub.
The stub jumps to the DLL wrapper, which:

1. leaves ranks 1–10 completely vanilla;
2. asks Palworld's original lookup for rank 10 when the real rank is 11–100;
3. multiplies that real rank-10 speed by the configured higher-rank factor;
4. returns the scaled integer to the untouched Palworld function.

There is:

- no Lua game-setting mutation;
- no TArray/TMap resize;
- no call back into a Pal object;
- no replacement of a Palworld function prologue;
- no copied/trampolined game instructions.

## Scaling

`factor = 1 + ((rank - 10) * 4.95)`

## Target executable

- SHA-256: `44b6295e70aa37b83d1c42ce1dcf865a7ffadcd300298b0e49a02bad8eb83443`
- size: `161802312`
- craft-speed lookup call RVA: `0x2F79F05`
- original rank→speed lookup RVA: `0x2F16210`

## Install

Delete the entire old `UE4SS/Mods/WorkSuitability100` folder first, then copy this v4.2
folder in fresh and fully restart Palworld.

## Expected native log

`WorkSuitability100/Native/WorkSuitability100.log` should include:

`SPEED REDIRECT installed callRVA=0x2F79F05 lookupRVA=0x2F16210`

`Native >10 work-speed scaling enabled through direct lookup redirect.`

`Compatibility initialization successful (rank cap + crash-safe lookup scaling).`

When rank 11+ work is actually evaluated, the first calls log:

`SPEED suitability=... rank=... vanilla10=... scaled=...`
