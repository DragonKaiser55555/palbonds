# PalBonds

A Palworld mod concept: earn a wild Pal's trust by petting and feeding it
before you ever throw a Palsphere. Enough trust and it joins you on its own;
mistreat it and it runs off for good.

Full design, subsystem breakdown, and the phased build plan live in
[`DESIGN.md`](./DESIGN.md) — read that first. This README is just setup.

## Status

**Working mod, ~82% complete.** This section was badly out of date for a
long time (it still described the project as "design phase, the scripts are
stubs" well after the mod was real and playable) — corrected 2026-09-06.

What actually works in-game today, all confirmed in live play:

- Pet (F9), Feed (F10) and Play (F8) on **wild** Pals, using the game's own
  real animations
- A per-individual personality roll (7 tiers) that changes a wild Pal's real
  AI disposition, with an on-screen label
- A trust/bonding bar per Pal, scaled by the level gap between it and you
- Kinship Peaches grant real bonding progress (250 lesser / 500 full against
  a 500-point bar)
- Crossing 20% of the bar wins the Pal over; crossing 100% captures it into
  your party with **no Palsphere**, after a happy-reaction celebration
- Damaging a bonding Pal costs trust; hitting it yourself is treated as
  betrayal and resets it

Known incomplete, and where the remaining work is:

- A wild Pal does **not** follow you during the bonding phase yet — every
  mechanism tried so far needs real ownership, which a still-wild Pal
  doesn't have. This is the largest open question, and combat-assist is
  blocked behind it.
- No capture VFX (the Pal turns happy, then vanishes — the "becomes light
  and travels into the player" effect is still missing)
- Real food-item feeding for wild Pals is shelved (the game's ownership gate
  is a raw C++ vtable call, unreachable from Lua)

The ordered, authoritative list of what's left lives at the top of
[`CLAUDE.md`](./CLAUDE.md), not here.

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

## Local install

Copy `mod/PalBonds/` into your game's UE4SS `Mods/` folder. Note the real
path includes `ue4ss/` — corrected 2026-09-06 to match the actual install:

```
<Palworld install>/Pal/Binaries/Win64/ue4ss/Mods/PalBonds/
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

Read the "⚠️ EMPEZAR ACÁ" section at the top of [`CLAUDE.md`](./CLAUDE.md).
It is the authoritative ordered list of what's left and is kept current.
DESIGN.md §8's research questions are all answered, and DESIGN.md §12
carries a staleness warning — trust `CLAUDE.md` over both.

[`docs/phase1-research.md`](./docs/phase1-research.md) is the FModel setup
guide, still live because FModel is the method for the one remaining
research question (the join VFX).
