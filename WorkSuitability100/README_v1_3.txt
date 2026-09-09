WorkSuitability100 v1.3 - REAL SPEED SCALING PATCH
Target: Palworld Steam v1.0.2.101103

PATCH-ONLY UPDATE
=================
Replace ONLY:
  WorkSuitability100\Scripts\main.lua

Keep your existing v1.2 files:
  WorkSuitability100\Native\WorkSuitability100.dll
  WorkSuitability100\enabled.txt

WHAT v1.3 ADDS
==============
v1.2 already allows suitability ranks and handbooks through level 100.
v1.3 extends the ACTUAL work/craft speed beyond rank 10.

The game still returns a level-10-capped work speed for higher ranks, so v1.3
uses that capped vanilla result as the baseline and scales it using the Pal's
real suitability rank.

Default curve above rank 10:
  multiplier = 1 + ((rank - 10) * 0.50)

Examples:
  Lv.10  = 1.0x level-10 speed
  Lv.11  = 1.5x
  Lv.20  = 6.0x
  Lv.50  = 21.0x
  Lv.75  = 33.5x
  Lv.100 = 46.0x

The curve is intentionally strong so very high suitability levels are visibly
meaningful on slow facilities such as the Gold Coin Assembly Line and Logging
Site II / Hardwood Site.

CONFIGURATION
=============
At the top of Scripts\main.lua:
  EXTRA_MULTIPLIER_PER_RANK = 0.50

Lower it for gentler scaling or raise it for even faster high-rank work.

TEST
====
1. Fully close and restart Palworld.
2. Put the Handiwork 100 Pal on the Gold Coin Assembly Line.
3. Put the Lumbering 75 Pal on Logging Site II / Hardwood Site.
4. Check UE4SS.log or:
     WorkSuitability100\work_suitability_speed.log

Expected lines include:
  [WorkSuitability100 v1.3] Hook installed: ...GetCraftSpeedByWorkSuitability
  [WorkSuitability100 v1.3] READY - suitability ranks above 10 now scale actual work speed ...
  [WorkSuitability100 v1.3] SPEED SCALE: ... rank=100 ... multiplier=46.00x ...

If no SPEED SCALE line appears while the Pal is actively working, send the
work_suitability_speed.log / UE4SS log. That means the facility uses another
work-speed path and it can be traced without changing the rank system again.
