WorkSuitability100 v1.3.1 - INVENTORY CRASH FIX + NATIVE SPEED SCALING
Target: Palworld Steam v1.0.2.101103
EXE SHA256: 8b5286b96550e83fb79a2ec7ede7bf881ec86f52f017e8276ceb1dc1b39d52f0

PATCH-ONLY UPDATE
Replace:
  WorkSuitability100\Scripts\main.lua
  WorkSuitability100\Native\WorkSuitability100.dll
  WorkSuitability100\Native\WorkSuitability100.cpp
Keep your existing enabled.txt.

IMPORTANT
v1.3's UE4SS GetCraftSpeed* hooks were removed completely. They could re-enter
Palworld's reflected craft-speed calls while the inventory/Pal UI queried work
stats, causing a crash when TAB opened the inventory.

v1.3.1 hooks the native rank -> work-speed lookup instead. The exact Palworld
1.0.2.101103 function clamps ranks beyond the work-speed table to its final
(level-10) entry. v1.3.1 calls that original lookup safely and extends the
returned level-10 value when the real rank is above 10.

Scaling above level 10:
  Lv 10  = 1.0x level-10 speed
  Lv 11  = 1.5x
  Lv 20  = 6.0x
  Lv 50  = 21.0x
  Lv 75  = 33.5x
  Lv 100 = 46.0x

The existing rank cap + handbook patches remain:
  rank ceiling = 100
  handbook eligibility ceiling = 100
  handbook application ceiling = 100

EXPECTED LOG
  [WorkSuitability100 v1.3.1] Loaded through Lua package.loadlib.
  [WorkSuitability100 v1.3.1] PATCHED: work suitability rank ceiling = 100.
  [WorkSuitability100 v1.3.1] PATCHED: handbook eligibility ceiling = 100.
  [WorkSuitability100 v1.3.1] PATCHED: handbook application ceiling = 100.
  [WorkSuitability100 v1.3.1] PATCHED: native work-speed scaling enabled through rank 100.
  [WorkSuitability100 v1.3.1] Inventory-safe: no UE4SS craft-speed UFunction hooks are installed.

TEST ORDER
1. Fully close Palworld.
2. Replace the three files above.
3. Start Palworld and press TAB several times before loading a save.
4. Load the save and open Inventory/Party/Pal Stats several times.
5. Test Handiwork 100 on the Gold Coin Assembly Line.
6. Test Lumbering 75 on Logging Site II / Hardwood Site.
7. If anything crashes, send the new crash dump plus work_suitability_100.log.
