# Phase 0 — Toolchain Setup

Status: DONE. Confirmed via the UE4SS log: `[PalBonds] mod loading...` and
all five module stub messages appear cleanly. Next: `phase1-research.md`.

## Why this one step is manual

Everything else in this project — the design doc, the mod's own Lua code,
verifying logs, deploying files — gets automated. Fetching and placing the
UE4SS binary itself is the one exception: it's a third-party DLL that loads
directly into Palworld's process the moment the game launches, and that
specific class of action (downloading/placing a compiled third-party binary
that gets loaded into a running process) is something handled manually
rather than automated, regardless of permission granted. It's open-source,
actively maintained, and the de-facto standard for this modding scene —
this isn't a trust concern about UE4SS specifically, just where the line
sits for that category of action. It's a two-minute step.

## Steps

1. Download **`UE4SS-Palworld.zip`** from the Palworld-specific fork:
   https://github.com/Okaetsu/RE-UE4SS/releases/download/experimental-palworld/UE4SS-Palworld.zip
   (tag `experimental-palworld` on `Okaetsu/RE-UE4SS` — this build has the
   memory-layout fix Palworld 1.0 needs; the generic upstream UE4SS release
   will crash without it). It's a few MB.

2. Extract it. You should get a `dwmapi.dll` file and a `ue4ss` folder.

3. Move both directly into:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Palworld\Pal\Binaries\Win64\
   ```

4. Launch Palworld once, let it reach the main menu, then close it. That
   first launch generates UE4SS's internal folder structure and log file —
   this is what we check next.

## After you've done this

Say so, and the next steps happen automatically:

1. Read-only check of `Pal\Binaries\Win64\ue4ss\` (folder structure + log
   file) to confirm UE4SS loaded without errors, and to confirm the real
   path to its `Mods` folder.
2. Copy `mod/PalBonds/` (our own authored code, not a third-party binary)
   from this project into that real `Mods` folder.
3. Ask you to launch the game once more, then read the UE4SS log to confirm
   the `[PalBonds]` startup messages appear — that's the Phase 0 acceptance
   test from `DESIGN.md` passing.
4. Move on to `DESIGN.md` §8's open research questions (needs FModel —
   same manual-install note will apply there, link to follow when we reach
   it).
