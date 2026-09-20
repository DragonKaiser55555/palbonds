# PalBonds

A Palworld mod: earn a wild Pal's trust instead of throwing a sphere at it.

Pet it, feed it, play with it. Every wild Pal has its own personality, shown
in a tag over its head, and reacts to you differently. Warm one up enough and
it starts following you, fights at your side, and eventually joins your party
on its own — no sphere, no fight. Mistreat it, or leave it behind, and it's
gone for good.

Nothing new is authored: no models, textures, or animations. Everything reuses
behavior the game already has.

![PalBonds](images/palbonds-thumbnail.jpg)

## Built with AI assistance

The design, the Lua code, and most of the documentation in this repo —
including the reverse-engineering notes in
[`docs/hook-points.md`](./docs/hook-points.md) — were built with AI
assistance. If that's something you'd rather not run on your
machine, that's entirely your call — this section exists so you can make it
before installing, not after.

## Features

- **Pet, Feed, and Play** on wild Pals through the game's own radial menu (and
  F8 for Play), the same interactions you already use on your own Pals.
- **Seven personalities** — Normal, Curious, Timid, Aloof, Grumpy, Hostile,
  Feral — rolled per individual, shown as a tag under the Pal's health bar
  alongside a trust meter.
- **Following and combat assist.** A bonded Pal stays behind you, holds still
  when you're aiming at it, joins your fights, and defends itself if
  something goes after it while you're busy elsewhere.
- **Feed scales with rarity.** Better food earns more trust. Kinship Peaches,
  found rather than crafted, are worth the most.
- **Level and rank aware.** The trust bar scales with the level gap between
  you and the Pal; alphas need twice the usual trust before they'll join.
  Befriending a boss also counts as defeating it, with the game's own
  first-time rewards.
- **Forgiveness, once.** The first time a Pal's trust reaches 20% it forgives
  you: it stops attacking, follows you for a moment, then goes back to its own
  business as a Friendly Pal.
- **Consequences.** Hit a bonded Pal and it loses half its trust; do it again
  and it's over between you. Hit one that isn't bonded yet and its trust drops
  to zero. Wander too far and leave a bonded Pal behind, and it gives up on
  you too.
- **Sphere-less joining** — a real celebration, a join effect, and a
  friendship head start for the Pal that just chose you.
- **Your language.** Tags and messages follow the game's language, in every
  language Palworld offers, with the right grammatical gender for female Pals.
- **Settings file.** Trust amounts, the join bonus, how often each personality
  appears, whether the tags start shown, the keys and the language can all be
  changed (see [Settings](#settings)).

## Get it

- **Steam Workshop:** [PalBonds - The Befriending Mod](https://steamcommunity.com/sharedfiles/filedetails/?id=3797816321)
  — installs its own UE4SS dependency for you.
- **Nexus Mods / manual install:** grab the latest `PalBonds-vX.Y.Z.zip` under
  [`release/`](./release), or build it yourself from [`mod/PalBonds/`](./mod/PalBonds).

## Requirements

- **Palworld**
- **UE4SS** (the experimental Palworld build) — installed automatically if you
  use the Steam Workshop version; otherwise grab it from
  [Nexus Mods](https://www.nexusmods.com/palworld/mods/2237) or the
  [Palworld Modding Docs](https://pwmodding.wiki/docs/category/ue4ss) first.

Use only **one** UE4SS install (manual or Workshop) at a time — running both
together crashes the game.

## Manual install

Drop the whole `PalBonds` folder into your UE4SS `Mods/` directory:

```
Pal/Binaries/Win64/ue4ss/Mods/PalBonds/        <- manual UE4SS install
Mods/NativeMods/UE4SS/Mods/PalBonds/           <- Steam Workshop UE4SS install
```

```
PalBonds/
├── enabled.txt
└── Scripts/
    └── main.lua (+ the rest)
```

Launch the game — UE4SS's console should print a line confirming PalBonds
loaded.

## Controls

| Key | Action |
|---|---|
| `4` | Radial menu — Pet and Feed a wild Pal you're looking at |
| `F8` | Play with the wild Pal you're looking at |
| `F9` | Show / hide personality tags |
| `F10` | Pause / resume passive friendship gain for followers |

Get close and look directly at the Pal for any of these. `F8`, `F9` and `F10`
can be changed in the settings file.

## Settings

The first time the game starts with PalBonds, it creates
`PalBonds_settings.lua` in UE4SS's `shared` folder:

```
Pal/Binaries/Win64/ue4ss/Mods/shared/PalBonds_settings.lua     <- manual UE4SS install
Mods/NativeMods/UE4SS/Mods/shared/PalBonds_settings.lua        <- Steam Workshop UE4SS install
```

It covers the trust each interaction gives (per food rarity, Kinship Peaches
included), how fast followers warm up on their own, the friendship a Pal gets
when it joins you, how often each personality appears, whether the personality
tags start shown or hidden (`ShowPersonalityTags`), the three keys, and the
language. Close the game, edit the file in any text editor, save, and start the
game again. Every setting is explained in the file. A value the mod can't use
falls back to its default and is reported in the UE4SS console; delete the file
and a fresh one with every default is written on the next launch.

A setting added by a later version is appended to the file you already have,
with your own values untouched — the file is read back and checked before
anything is written, and left alone if that check fails.

An in-game settings screen is planned for a future update.

## Known issues

- **A bonded wild Pal (50%+ friendship bar) may despawn if it moves too far
  from its spawn location.** This is Palworld's own wild-Pal lifecycle: the
  game unloads the spawn area you left and clears the Pals that belonged to
  it, and a bonded Pal is still a wild Pal until you catch her. It is not
  something a mod can currently veto — UE4SS's Lua `RegisterHook` has no
  cancel, so the despawn call can be observed but not blocked. If you want to
  keep a companion permanently, complete the bond; otherwise bonding again in
  a new area costs nothing but food. The full investigation, including the
  approaches that did *not* work, is in [`CLAUDE.md`](./CLAUDE.md). Since
  v1.1.5 the mod at least tells you when it happens, with the same "gave up
  on you" message as leaving a Pal behind.
- **Crash when loading another world — found and fixed in v1.1.4.** Loading a
  world after quitting one could crash the game (`EXCEPTION_ACCESS_VIOLATION`)
  if you had used Play (F8) in that session. Keypresses reach a UE4SS mod on
  UE4SS's own thread, not the game's, and Play was starting animations from
  there, which quietly corrupted the game's state until the next world load.
  v1.1.4 hands every keybind to the game thread first. Pet and Feed were never
  affected, because they arrive through the game's own menu. v1.1.3 fixed a
  real but smaller world-change problem (a stale reference to your character);
  v1.1.4 also lets go of everything the moment you confirm a quit. The hunt,
  including the wrong turns, is written up in [`CLAUDE.md`](./CLAUDE.md).
- **Microstutters — found and fixed in v1.1.2.** A player reported noticeable
  microstutters with the mod active, and measurement confirmed them: the mod
  was searching the game's entire object list on timers and during the radial
  menu, several times a second, at 40–100ms per search. v1.1.2 replaces those
  searches with references the mod already has. Standing still, frame pacing
  with the mod is now close to the game without it (1% low 33 fps vs 36 fps
  with the mod off, down from 13–16 fps before), and bonding and fighting
  stutter a fraction as often. A few rare safety-net checks remain on purpose.
  If you still see stutters, a comment on either store page with your specs
  helps.

## Scope

Singleplayer and self-hosted worlds only. Mods are not permitted on official
Pocketpair servers, and using one there risks a ban.

## For developers

This repo is also a record of getting a UE4SS Lua mod to do things Palworld
was never built to expose — real AI disposition swaps, a working follow
action, sphere-less capture, combat assist through the Hate system, and more.
If you're building your own Palworld mod, [`docs/hook-points.md`](./docs/hook-points.md)
is a pass-by-pass log of what was tried, what worked, what didn't, and the
exact class and function names involved. [`DESIGN.md`](./DESIGN.md) has the
original subsystem breakdown; [`CLAUDE.md`](./CLAUDE.md) tracks current state,
known issues, and what's next.

`tools/harness/` is an offline test harness (fengari, a Lua VM in JS) that
runs the mod's real source against stubbed UE4SS globals — useful for
catching load-time and logic bugs without a full game launch.

## License

MIT — see [`LICENSE`](./LICENSE). Fork it, learn from it, build on it.

Unofficial fan mod. Palworld belongs to Pocketpair, Inc.
