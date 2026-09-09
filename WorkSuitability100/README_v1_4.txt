WorkSuitability100 v1.4 - Palworld v1.0.3.101238 retarget

Exact target EXE:
Palworld-Win64-Shipping.exe
SHA256: fe3c15064524bae1947852467c4f92bc22469acc033a3d3c8031eab4324e41e8
SizeOfImage: 0x09FAD000

PATCH-ONLY UPDATE
Replace only:
  WorkSuitability100\Scripts\main.lua
  WorkSuitability100\Native\WorkSuitability100.dll
  WorkSuitability100\Native\WorkSuitability100.cpp

KEEP:
  WorkSuitability100\enabled.txt

Retargeted native sites for v1.0.3.101238:
  suitability-rank map max             RVA 0x02E6F3CA
  scalar rank max                      RVA 0x02F7481A
  handbook eligibility max             RVA 0x032B26D3
  handbook application max             RVA 0x02F7C21C
  common rank->work-speed lookup       RVA 0x02F11560

Expected log:
  WorkSuitability100\work_suitability_100.log

Expected key lines:
  [WorkSuitability100 v1.4] PATCHED: work suitability rank ceiling = 100.
  [WorkSuitability100 v1.4] PATCHED: handbook eligibility ceiling = 100.
  [WorkSuitability100 v1.4] PATCHED: handbook application ceiling = 100.
  [WorkSuitability100 v1.4] PATCHED: native work-speed scaling enabled through rank 100.
