# WorkSuitability100 v2.0

Runtime mod for Palworld that raises Pal Work Suitability rank handling from the normal level-10 ceiling to level 100.

## Install

Copy the `WorkSuitability100` folder into the same UE4SS Mods/Scripts location used by the other Lua-loaded Palworld mods on the installation. The included `Scripts/main.lua` loads the native DLL automatically.

## What is different in v2.0

The old releases relied on fixed byte signatures and blind searches for the literal `10`. v2.0 instead discovers the current executable's Unreal native registrations at runtime, resolves lazy native implementation pointers without executing the registration thunk, follows bounded direct-call paths, and changes only validated rank-cap immediates in the relevant Work Suitability functions.

The DLL logs every applied patch with its RVA and original/new byte. It refuses to report successful initialization when it cannot establish a relevant rank-cap transition.

## Target build

The repository currently tracks the Palworld executable through Git LFS. The build workflow verifies the exact LFS object before compiling the DLL.

## Log

The runtime log is written beside `WorkSuitability100.dll` as `WorkSuitability100.log`.
