WorkSuitability100 v1.2 - Handbook Ceiling Patch
Target: Palworld Steam v1.0.2.101103
EXE SHA256: 8b5286b96550e83fb79a2ec7ede7bf881ec86f52f017e8276ceb1dc1b39d52f0

PATCH-ONLY UPDATE from v1.1.
Keep your existing WorkSuitability100/enabled.txt.

Replace:
  WorkSuitability100/Scripts/main.lua
  WorkSuitability100/Native/WorkSuitability100.dll
  WorkSuitability100/Native/WorkSuitability100.cpp

v1.2 adds two exact native handbook patches:
  1) CanUseTargetWorkSuitabilityRankUp: current rank must be < 100.
  2) Actual handbook application: next rank must be <= 100.

The existing v1.1 rank calculation/map ceiling patches remain active.
No internal Palworld functions are called by the DLL.

Expected log:
  [WorkSuitability100 v1.2] Loaded through Lua package.loadlib.
  [WorkSuitability100 v1.2] PATCHED: work suitability rank ceiling = 100.
  [WorkSuitability100 v1.2] PATCHED: handbook eligibility ceiling = 100.
  [WorkSuitability100 v1.2] PATCHED: handbook application ceiling = 100.
  [WorkSuitability100 v1.2] Safe mode: no internal Palworld function calls are used.
