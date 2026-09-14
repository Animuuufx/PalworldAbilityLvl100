# HumanSkillFruits

Experimental Palworld UE4SS mod for teaching Pal active skills to **players and human NPCs** with Skill Fruits and exposing learned fruit skills through a player skill bar.

## Branch

`HumanSkillFruits`

## Current build

`v0.1.0-probe`

This is the first compatibility build for the current Palworld executable. It intentionally discovers the live fruit-use and player-skill functions before calling them. That avoids hard-coding an outdated `ProcessEvent` signature and crashing the game after a Palworld update.

## Target behavior

- Players can consume normal Skill Fruits.
- Captured/recruited human NPCs can consume normal Skill Fruits.
- Fruit-taught attacks are stored as learned active skills (`MasteredWaza`) instead of a mod-only fake list.
- Human NPCs can equip learned attacks in their normal `EquipWaza` slots.
- The player receives a skill bar built from learned fruit skills.
- Skill slots are usable from hotkeys and retain normal per-skill cooldown behavior once the current player-cast entry point is resolved.
- Duplicate fruit skills are rejected.
- Learning data should persist through the normal character/NPC save data rather than a separate save file.

## v0.1 probe controls

- `Alt + 1` through `Alt + 8`: select one of the player's learned fruit skills.
- `Alt + F8`: dump the player's `MasteredWaza`, `EquipWaza`, and current runtime skill/fruit/item function candidates to `UE4SS.log`.
- The build also displays a temporary on-screen `Skill Fruit Bar` generated from the player's learned `MasteredWaza` list.

## Install for testing

Copy the whole `HumanSkillFruits` folder into:

`Palworld\Pal\Binaries\Win64\ue4ss\Mods\HumanSkillFruits`

The existing `enabled.txt` enables it on UE4SS installs that support that convention. If the current UE4SS install uses `mods.txt`, add:

`HumanSkillFruits : 1`

Then fully restart Palworld.

## First compatibility test

1. Load a world and wait until the player can move.
2. Press `Alt + F8` once.
3. If the player already has any fruit-taught skills, the bar will list them.
4. Close the game and inspect `UE4SS.log` for lines beginning with `[HumanSkillFruits v0.1.0-probe]`.
5. The runtime probe reports the current executable's player/controller/character-parameter functions containing `Waza`, `Skill`, `Fruit`, `Attack`, or `Item`. Those names are used to wire the final safe cast and fruit-target hooks without guessing signatures.

## Why MasteredWaza + EquipWaza

Palworld's save format distinguishes learned/taught active moves from equipped active moves. Fruit-taught extras belong in `MasteredWaza`, while currently equipped active attacks are represented by `EquipWaza`. Using those game-owned lists is preferable to maintaining a parallel mod-only skill database because the skills remain part of the actual character data.

## Planned v0.2

- Patch the Skill Fruit target validation so Player and Human targets are accepted.
- Resolve Skill Fruit item -> `EPalWazaID` from the live item/master-data row.
- Add learned skill to the target's `MasteredWaza` using the game's own function/path where available.
- Auto-fill an empty `EquipWaza` slot for human NPCs.
- Consume exactly one fruit only after learning succeeds.
- Wire player skill-bar slots to the current executable's Waza action/cast path.
- Track cooldowns and reject casts while the selected skill is cooling down.

## Safety choice in v0.1

The probe does **not** invoke guessed Waza functions. Calling a reflected Unreal function with the wrong parameter layout can corrupt memory or crash Palworld even when wrapped in Lua `pcall`. The first live log gives the correct candidates for this game build, after which the cast/consume path can be bound precisely.
