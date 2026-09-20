# PalBonds crash testing guide (test build 2)

This document is written for an AI assistant helping a player test PalBonds
test build `v1.1.6-test2`. It explains what the build logs, four test runs that
narrow the cause down between them, and what to report. A player can follow it
too, but it is deliberately detailed.

Context: on Linux/Proton the game dies with
`EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000000`, every frame of
the crash stack inside the UE4SS module, no Lua error, and the mod's log simply
stops mid-run. Two crashes so far have **identical 64-frame stacks**, reached
from different places in the mod: once about ten seconds after a Pal joined the
player, once seconds after a third pet with no Pal joining at all. So one place
inside UE4SS is being reached from several of the mod's jobs, most likely a
read on a game object the game has already freed — something Windows tolerates
and Wine does not.

## What this build adds

Every repeating job in the mod writes one `[TRACE]` line **before** it runs.
The log is flushed to disk line by line, so when the game dies, the **last
`[TRACE]` line in the file names the job that was running.** That is the one
thing the previous logs could not tell us.

The lines you will see:

| Line | What it means |
|---|---|
| `[TRACE] personality-scan start` / `end` | The periodic pass over nearby wild Pals. An `end` should always follow a `start`. |
| `[TRACE] sensor-index rebuild (FindAllOf PalAISensorComponent)` | A full scan of the game's object list, at most once every 30 s. The single heaviest thing the mod does. |
| `[TRACE] preset build <name>` / `preset write <name>` | Creating and writing a Pal's AI behaviour preset. |
| `[TRACE] interrupt and re-sense <id>` | Cancelling a Pal's current action and making it look around again. |
| `[TRACE] companion preset write <id>` | Giving a bonded Pal its companion behaviour. |
| `[TRACE] nameplate scan start` / `end` | Looking for health bars on screen to attach the trust bar and tag to. |
| `[TRACE] build trust bar` | Building the trust bar UI for one Pal. |
| `[TRACE] follower tick (trust)` / `(combat)` | The two per-second jobs that look after bonded Pals. |

Two warnings:

- **The game may feel heavier than usual.** This build writes a lot to disk,
  several lines per second. That is expected and only happens in this build;
  it is not the bug and will not be in a release.
- **Save each run's log before starting the next one.** The mod opens
  `palbonds-live.log` fresh at every game launch, so launching again
  **overwrites the previous run's log**. After each run, copy the file
  somewhere else and name it after the run (`run-A.log`, `run-B.log`, ...).
  Every run's log is worth keeping, including the ones that did not crash:
  a clean run is what proves a whole group of jobs innocent.
- **The log grows quickly**, a few MB in a few minutes, which is another
  reason to keep one file per run rather than one long session.

## Where the files are

- `Palworld/Pal/Binaries/Win64/palbonds-live.log` — the mod's log, already on
  in this build.
- `Palworld/Pal/Binaries/Win64/ue4ss/UE4SS.log` — UE4SS's own log. Useful, but
  it is **not** flushed line by line, so its tail is always behind; the mod's
  log is the accurate one for the moment of the crash.
- The crash folder written by the game, containing `CrashContext.runtime-xml`
  (GitHub rejects that extension, so it needs zipping).

## The four runs

Run them in this order and stop as soon as one crashes; that run is the
informative one. Each is about five minutes. **Only PalBonds should be
installed**, as in the last test.

### Run A — stand still, touch nothing

Load your world, then stand somewhere with wild Pals in view and do nothing at
all for five minutes: no petting, no feeding, no fighting. Walking around is
fine; interacting is not.

- **If it crashes:** the cause is one of the mod's background jobs, with no
  interaction needed. The last `[TRACE]` line names it. This is the most
  valuable result of the four.
- **If it does not:** the background jobs alone are not enough, and the cause
  needs an interaction. Continue to run B.

### Run B — pet one Pal, but stop before it warms to you

Pick one wild Pal. Pet it **twice only**, then leave it alone and stay nearby
for five minutes. Two pets keep it below the point where the Pal starts
following you (that happens at 20% of its trust bar, and most Pals need three
or four interactions to get there). If the mod shows a "Friendly" tag over the
Pal, it went past that point: note it and treat the run as run C instead.

- **If it crashes:** interacting is enough on its own, without any following.
- **If it does not:** continue to run C.

### Run C — let one Pal reach the "Friendly" stage

Same as B, but keep petting or feeding the same Pal until its tag changes to
**Friendly** and it follows you for a few seconds before wandering off. Then
stop interacting and stay nearby for five minutes.

This is the step we most suspect. When that short follow ends, the mod swaps
the Pal's AI action several times, writes it a new behaviour preset and makes
it look around again: a lot of engine objects created and discarded at once.

- **If it crashes:** the crash belongs to that sequence, and the last `[TRACE]`
  line says which part.
- **If it does not:** continue to run D.

### Run D — bond a Pal all the way

Keep going with one Pal until it joins your party, then keep playing nearby for
five minutes. This is what the first crash report did.

## What to report per run

1. Which run (A, B, C or D), and whether the game crashed.
2. That run's saved log (`run-A.log` and so on) — please send the clean runs
   too, not only the crash.
3. The crash file, zipped, if it crashed.
4. From the log, the part worth calling out explicitly:
   - the **last `[TRACE]` line** in the file;
   - whether any job **started without its matching `end`** (`personality-scan
     start` with no `personality-scan end`, or `nameplate scan start` alone);
   - the last 20 lines.

If a run does not crash, that is a real result and worth reporting: it rules a
whole group out. Please say how long you played.

## For the assistant reading the log

- The mod's log is flushed per line, so its final line is accurate to the
  moment of death. UE4SS.log is buffered and will look like it stopped earlier;
  that is normal and not evidence of anything.
- Absence of a log line is **not** evidence that its code did not run. Some log
  tags are filtered out of the file on purpose (a release-noise cleanup), so
  code can run and print nothing.
- `PCallStackHash` in these crash files is the SHA-1 of an empty string
  (`DA39A3EE…`), i.e. the field is unused. Two dumps sharing it means nothing;
  compare the `PCallStack` frame lists instead.
- The useful comparison across runs is: which job was last, and whether the
  same job is last every time.
