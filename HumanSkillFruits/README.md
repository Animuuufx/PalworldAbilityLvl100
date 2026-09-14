# HumanSkillFruits

Experimental Palworld UE4SS mod for teaching Pal active skills to **players and human NPCs** with Skill Fruits and exposing learned fruit skills through a player skill bar.

## Branch

`HumanSkillFruits`

## Current build

`v0.1.1-safe`

This is a stability baseline after the original v0.1.0 runtime probe crashed while entering a world on the current Palworld/UE4SS build.

## Crash fix in v0.1.1

Removed all automatic world-entry behavior:

- no `LoopAsync` polling
- no `FindFirstOf`/player lookup during world entry
- no reflected `ForEachFunction` class scan
- no `MasteredWaza` or `EquipWaza` array access during loading
- no `StaticFindObject` / `PrintString` calls during loading
- no automatic skill-bar rendering during loading
- no guessed `ProcessEvent` or Waza calls

The only active feature in this build is a safe Lua hotkey test. `Alt + F8` writes a log line and does not touch any Unreal object.

## Test this build first

Copy/replace the whole `HumanSkillFruits` folder in:

`Palworld\Pal\Binaries\Win64\ue4ss\Mods\HumanSkillFruits`

Fully restart Palworld and enter the same world that crashed previously.

If the world loads normally, press `Alt + F8`. `UE4SS.log` should contain:

`[HumanSkillFruits v0.1.1-safe] Alt+F8 hotkey received. No Unreal objects were accessed.`

If it still crashes before entering the world, send the end of `UE4SS.log` from that run because that would indicate the crash is outside the removed runtime probe.

## Target behavior

The finished mod will provide:

- Players can consume normal Skill Fruits.
- Captured/recruited human NPCs can consume normal Skill Fruits.
- Fruit-taught attacks are stored as learned active skills (`MasteredWaza`).
- Human NPCs can equip learned attacks through their normal skill data.
- The player gets a usable skill bar for learned fruit skills.
- Skill-bar abilities retain normal cooldowns.
- Duplicate learned skills are rejected.
- One fruit is consumed only after learning succeeds.
- Learned skills persist with the character/NPC.

## Development approach after stability test

The unsafe broad runtime reflection scan will not be restored. Function hooks and save-data access will be added back one subsystem at a time against known current-build Palworld functions so any compatibility problem can be isolated immediately.
