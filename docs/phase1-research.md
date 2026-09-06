# FModel Setup — asset/Blueprint research

Rewritten 2026-09-06. This file used to be "Phase 1 — research kickoff",
with a list of six open questions to go answer in FModel. **All six of
those questions are answered** — see `docs/hook-points.md` for each. What
survives from that file, and the only reason this one still exists, is the
FModel setup itself, because FModel is still the stated method for the one
remaining research question this project has.

`docs/phase0-install.md` (the UE4SS setup guide) was deleted in the same
pass — UE4SS has been installed and working for months, and the install
path is documented in `README.md`.

## What FModel is still needed for

**The join VFX.** When a Pal joins you — a real vanilla cage rescue, or a
capture — it plays a visual effect of the Pal turning into light and
travelling into the player. PalBonds does not reproduce that: today the Pal
plays its happy reaction and then simply vanishes, which is the jarring
part.

Important, so nobody burns a session re-testing it: the one strong
candidate this project ever had, **`ABP_ReturnPalEffect_C`, is ruled out.**
A dedicated test run (`hook-points.md`, Hundred-and-ninety-third pass —
one real sphere capture, one real sphere-less capture, one real cage
rescue, same session) showed it fires only when switching active Otomo,
never on any of the three join events. It structurally looks exactly right
(`UNiagaraSystem` fields, `LerpStartPos`/`Progress`/`CurveForLerp`,
`StartLocation`→`ForPlayer`) which is precisely why it fooled this project
for months. Do not reuse it.

What's needed is the **real** class behind the vanilla effect. Two
approaches, both already proven to work in this project:

1. **FModel** — read the Blueprint graph of whatever the cage-unlock path
   calls. `UBP_ActionUnlockCagePalLock_C` is confirmed real and confirmed
   to fire at the moment the cage door opens, so it is the best-known entry
   point into that path.
2. **repak / strings against the game pak** — search for VFX-adjacent names
   near the capture-success and cage-unlock code paths. This is how the
   eleven real `AIResponsePreset` classes were found, so the technique is
   known-good here.

## Prerequisites (manual installs)

Same standing rule as UE4SS: executables and runtimes get installed by
hand, everything after that is automated.

1. **.NET 10 Desktop Runtime** (FModel's prerequisite):
   https://dotnet.microsoft.com/download/dotnet/10.0/runtime — "Desktop
   Apps" runtime, Windows x64.
2. **FModel**: https://fmodel.app/download → `FModel.zip`. **Extract it to
   a real folder before running it** — FModel's own docs warn that running
   it from inside the zip causes permission errors.

## Configuration (once)

1. **Game Directory**: `C:\Program Files (x86)\Steam\steamapps\common\Palworld`
   (the folder containing `Engine` and `Pal` — not the `Pal` folder itself)
2. **Detected Game / UE Version**: `GAME_UE5_1`
3. Settings → General → enable **"Local Mapping File"**, then point
   **Mapping File Path** at:
   `C:\Users\Dragon\Proyectos\32-PalBonds\research\Mappings.usmap`

   Note the path: this used to live under a nested `palbonds-mod/research/`
   folder, which was removed when the duplicate mirror was consolidated.
   The mappings file itself is kept deliberately — without it, Palworld's
   data tables open empty in FModel.
4. No AES key should be needed for Palworld's paks. If FModel asks for one
   and refuses to open without it, say so and we'll track one down.

Right-clicking an asset exports it as JSON, which is the easiest thing to
hand over — much better than describing what's on screen. Screenshots work
too.
