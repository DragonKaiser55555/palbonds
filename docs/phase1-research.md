# Phase 1 — FModel Setup & Research Kickoff

Status: waiting on manual FModel + .NET runtime install. Phase 0 is done —
the toolchain works end to end (UE4SS loads, PalBonds stub confirmed in
the log). This phase is about answering DESIGN.md §8's open questions.

## Manual installs (same reasoning as UE4SS in phase0-install.md)

Two things to install by hand — both are executables/runtimes, so same
rule as before: I don't fetch or place these myself, but everything after
they're installed is automated again.

1. **.NET 10 Desktop Runtime** (FModel's prerequisite):
   https://dotnet.microsoft.com/download/dotnet/10.0/runtime
   Get the "Desktop Apps" runtime for Windows x64.

2. **FModel**: https://fmodel.app/download → download `FModel.zip`,
   **extract it to a real folder first** (don't run it straight out of the
   zip — FModel's own docs warn this causes permission errors).

## Already done for you

The `.usmap` mappings file FModel needs to correctly read Palworld's data
(without it, data tables show up empty) is already sitting at:
`palbonds-mod/research/Mappings.usmap`
(pulled from the community-maintained `PalworldModding/UsefulFiles` repo —
this is just a data file, not executable, so no manual step needed here.)

## FModel configuration (do this once, after installing)

1. Open FModel. On first run / in Settings, set:
   - **Game Directory**: the root of the Palworld install —
     `C:\Program Files (x86)\Steam\steamapps\common\Palworld`
     (the folder containing `Engine` and `Pal`, not the `Pal` folder itself)
   - **Detected Game / UE Version**: `GAME_UE5_1`
2. Settings → General tab → enable **"Local Mapping File"**, then point
   **Mapping File Path** at:
   `C:\Users\Dragon\Proyectos\32-PalBonds\palbonds-mod\research\Mappings.usmap`
3. No AES key is needed for Palworld's paks as far as current community
   docs say — if FModel prompts for one and refuses to open without it,
   tell me and we'll track one down.

## What to actually search for (maps to DESIGN.md §8)

FModel's left panel is a searchable asset tree; the bottom-left has a
text search box that filters by name. Once it's open and configured,
here's where to point it at each open question — log whatever you find
(even partial/uncertain) into `docs/hook-points.md` and I'll help
interpret it:

- **Q1 (AI Controller / Behavior Tree / disposition source)** — search
  `AIController`, `BehaviorTree`, and `Personality` / `Disposition`.
  Palworld's own Pal-brain classes are likely under a `Pal`-prefixed
  Blueprint path (e.g. something like `PalAIController` or
  `PalIndividualCharacter*`) — search `Pal` + `AI` together too.
- **Q2 (pet/feed ownership gate)** — search `Pet`, `Feed`, `Stroke`, and
  `OwnerPlayer` / `IsOwned` — the gate is likely a boolean check inside
  whatever Blueprint handles the interact prompt.
- **Q3 (existing trust/friendship field)** — search `Trust`, `Friendship`,
  `Affection` inside Data Tables specifically (FModel's tree separates
  DataTable assets) — this is what the "Configurable Trust On Capture"
  mod precedent implies exists somewhere.
- **Q4 (sphere-less capture function)** — search `Capture`, `CatchPal`,
  `Sphere` — look for a UFunction that doesn't take a Palsphere item as
  a parameter, or one clearly meant for debug/cheat capture.
- **Q5 (stable per-instance identifier)** — search `GUID`, `InstanceId`,
  `SaveData` near Pal-related structs — save-persisted Pals almost
  certainly have some unique key already, since the game has to remember
  which specific Pal is which across saves.
- **Q6 (owned-Pal follow/assist branch)** — search `Follow`, `Assist`,
  inside `BehaviorTree` assets specifically tied to owned/party Pals as
  opposed to wild ones.

Right-clicking an asset in FModel lets you export its data as JSON —
that's the easiest way to hand me something concrete to read rather than
describing what you saw. Screenshots work too.

## After this phase

Once even a couple of these questions have real answers in
`docs/hook-points.md`, Phase 1 in `DESIGN.md` (personality reassignment)
becomes the first subsystem worth writing real hook code for, instead of
the current TODO stubs.
