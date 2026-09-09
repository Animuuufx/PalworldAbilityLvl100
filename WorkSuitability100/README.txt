WorkSuitability100 v1.1
=======================
Target: Palworld Steam v1.0.2.101103
Target EXE SHA256: 8b5286b96550e83fb79a2ec7ede7bf881ec86f52f017e8276ceb1dc1b39d52f0

PURPOSE
Raises Palworld's work-suitability rank ceiling from 10 to 100.

IMPORTANT - v1.0 CRASH FIX
v1.0 called an internal Palworld function with the wrong native signature and could
crash the game during startup. v1.1 removes that call completely.

v1.1 patches only the two exact instructions in this Palworld build which read the
maximum work-suitability rank. They are changed to load 100 directly. No internal
Palworld getter is invoked by this mod.

INSTALL / UPDATE
1. Fully close Palworld.
2. Replace the OLD WorkSuitability100 folder with this one:
   Palworld\Pal\Binaries\Win64\ue4ss\Mods\WorkSuitability100
3. Start Palworld.
4. Check:
   ue4ss\Mods\WorkSuitability100\work_suitability_100.log

Expected:
[WorkSuitability100 v1.1] Loaded through Lua package.loadlib.
[WorkSuitability100 v1.1] PATCHED: work suitability rank ceiling = 100.
[WorkSuitability100 v1.1] Safe mode: no internal Palworld function calls are used.

NOTE
This changes the engine-level ceiling. A handbook/item may have its own separate
"already at max" validation at level 10; if so, that validation needs its own patch.
