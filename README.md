# PalBonds

A Palworld mod concept: earn a wild Pal's trust by petting and feeding it
before you ever throw a Palsphere. Enough trust and it joins you on its own;
mistreat it and it runs off for good.

Full design, subsystem breakdown, and the phased build plan live in
[`DESIGN.md`](./DESIGN.md) — read that first. This README is just setup.

## Status

Design phase. The `mod/PalBonds/Scripts/*.lua` files are stubs with
`TODO`s, not working code yet — real logic goes in once the hook points in
[`docs/hook-points.md`](./docs/hook-points.md) are confirmed against the
actual game files (Phase 0/1 in DESIGN.md).

## What you need installed

1. **Palworld**, obviously, with a save you're okay experimenting on.
   Singleplayer or a self-hosted server only — see the ban-risk note below.
2. **UE4SS** (the experimental Palworld build) — the Lua scripting host this
   mod runs on. Install it into your Palworld installation per the
   [Palworld Modding Docs UE4SS guide](https://pwmodding.wiki/docs/category/ue4ss).
3. **FModel** — for inspecting the game's assets/data tables while we track
   down real class and function names. Not needed at runtime, only for
   research.
4. Optionally **PalSchema**, if any subsystem turns out to be a plain data
   value we'd rather patch as JSON than hook in Lua (see DESIGN.md §4).

## Local install (once there's real code)

Copy `mod/PalBonds/` into your game's UE4SS `Mods/` folder so it looks like:

```
<Palworld install>/Pal/Binaries/Win64/Mods/PalBonds/
├── enabled.txt
└── Scripts/
    └── main.lua (+ the rest)
```

Then launch the game — `main.lua` should print a startup line to the UE4SS
console confirming it loaded. Everything past that point is whatever the
current phase in DESIGN.md has implemented.

## Ban-risk / scope note

Modding is safe in singleplayer and on a server you control. Official
Pocketpair servers and most community servers can flag or ban modified
clients. This project is scoped to singleplayer/self-host; see DESIGN.md §7
for the full list of caveats (patch fragility, chunk-streaming edge cases,
multiplayer replication being out of scope for now).

## Next step

Phase 0 is done — UE4SS is installed and the PalBonds stub is confirmed
loading cleanly in the game log. **Right now:** follow
[`docs/phase1-research.md`](./docs/phase1-research.md) to install FModel
and start answering DESIGN.md §8's open research questions, logging
findings in [`docs/hook-points.md`](./docs/hook-points.md). Once question
1–2 have real answers, Phase 1 (personality reassignment) is the first
piece worth actually coding.
