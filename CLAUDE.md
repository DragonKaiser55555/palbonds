# 32 — PalBonds (behaviour mod for Palworld)

**Progress: 98%**

| Category | Weight | Done | Contributes |
|---|---|---|---|
| Design and planning | 10% | 100% | 10% |
| Tooling (UE4SS + mod loading in game) | 15% | 100% | 15% |
| Hook research (the 6 open questions in DESIGN.md §8) | 15% | 100% | 15% |
| Per-individual personality system | 10% | 95% | 9.5% |
| Wild-Pal interaction (pet / feed / play) | 15% | 100% | 15% |
| Trust system | 15% | 100% | 15% |
| Following and combat assist | 10% | 95% | 9.5% |
| Threshold capture / flee | 5% | 100% | 5% |
| Polish and configuration | 5% | 85% | 4.25% |

Following stays at 95% for the open spawner-despawn defect. Polish counts the
README, both store descriptions, licence, screenshots, the Workshop upload, the
Nexus package and the Nexus publish as done (published on Steam, Nexus, and
announced in 2 Reddit posts, 2026-09-14; **v1.1.1 published to both stores
2026-09-15**; **v1.1.2 on GitHub, Nexus and the Steam Workshop 2026-09-15**;
**v1.1.3 on all three 2026-09-16**; **v1.1.4 on all three 2026-09-18**, GitHub
`8846dca`; **v1.1.5 on Nexus and the Workshop 2026-09-19**); only the settings screen is left. v1.1.4 (the Play crash fix and
20% forgiveness) moves no category. Recalculate whenever a category moves, and keep
the `Progreso:` line of this project's block in `../game proyects.txt` in sync.

**Microstutter note for the table:** the reported stutter WAS the mod's doing
(measured 2026-09-15) and is fixed in v1.1.2, so no category was moved; the
percentage stays as it was.

---

## Where we stand — read this first (2026-09-15, after the performance work)

**v1.1.2 = the microstutter fix, committed and pushed to GitHub as the new
stable version on Dragón's instruction** (*"lets update all of this to github
as the new stable version - we will have to upload it to nexus and the steam
workshop too, but one step at a time"*). **Then PUBLISHED to both stores the
same afternoon, all verified:**
- **Nexus:** Dragón uploaded `release/PalBonds-v1.1.2.zip` via the Update
  button. The page header reads 1.1.2 (last updated 15 Sep 3:13PM). There is
  one main file, "PalBonds V1.1.2", and the changelog is saved in Dragón's
  wording. That last point was confirmed from his screenshot: the Changelogs
  accordion never renders its entries in the logged-out in-app browser, so
  don't call it empty from there.
- **Steam Workshop:** the same item 3797816321, so no duplicate. The change note
  is dated 15 Sep, and `.workshop.json` now reads `last_published_version`
  1.1.2 with the change note.
- **The game's installed copy updated when Dragón re-ticked the items:**
  `Mods\NativeMods\UE4SS\Mods\PalBonds\` is md5-identical to the release (10
  scripts, profiler OFF), and ManagedMods records Version 1.1.2. The Workshop
  UE4SS loaded PalBonds cleanly (14 hooks, no Lua errors). Dragón's quick run
  on the published build: *"i think it did [feel smoother]"*.

- **What 1.1.2 is:** the two fix rounds in "Known open defects" #0 (PlayerRef,
  hook-fed nameplates and personality scan, sensor cache first, label/bar
  update gating, cache-only regular scan, death/world-exit player tracking,
  controller from the character) plus the dev profiler shipped OFF. Release
  trees and `release/PalBonds-v1.1.2.zip` verified md5-identical to `mod/`
  (10 scripts incl. the new `PlayerRef.lua` and `Profiler.lua` with
  `PROFILING = false`); Workshop `Info.json` Version 1.1.2.
- **Verified in game (runs D, E and an unrecorded run F):** no Lua errors, 14
  hooks, bonding/joining/fights/betrayal/death-respawn all normal. Standing
  still, 1% low 33 fps with the mod vs 36 fps with it off (13–16 before);
  bonding 13 stutters/min vs 91; fighting 19 vs 55. Dragón after run F: *"the
  game feels significantly better and less laggy"*.
- **LESSON — the frame recorder itself caused felt lag.** Run E (recorded,
  with PresentMon's live console stats on) felt laggier than run D (whose
  recording silently failed). Dragón's theory, then his unrecorded run F: *"it
  was the recording itself the one who caused lag, i suspected it because it
  felt constant, not when doing interactions"*. Use PresentMon for numbers,
  never judge FEEL during a recorded run, and keep `--no_console_stats`.
- **Dev install still has `PROFILING = true`** in its `Profiler.lua` (only that
  line differs from `mod/`). It adds a little overhead; set it false there when
  performance work is done.

**v1.1.1 (still what the stores serve)** is v1.1.0 plus exactly ONE confirmed
fix (owned Pals no longer roll a personality and no longer show a tag) — 2
files, 41 lines, nothing else. Everything from the despawn investigation was
reverted rather than shipped; see "KNOWN LIMITATION" below.

- **Nexus:** published 2026-09-14 11:56PM via the file row's **Update** button
  (not "Add file" — see "Publishing procedure" below). Mod version header
  reads 1.1.1, one file listed, 1.1.0 archived, changelog entry saved.
- **Steam Workshop:** published 2026-09-15 00:29 on the same item
  **3797816321** — no duplicate item. Change note: *"Owned Pals no longer roll
  a random personality or show a personality tag - that system is for wild Pals
  only."*
- **Known Issues** (the bonded-Pal despawn) is now stated on BOTH store pages,
  in Dragón's own wording, which is the accurate one — following starts at
  `FOLLOW_TRIGGER_RATIO = 0.5` (`Trust.lua:35`), so "50%+ friendship bar" is
  literal, and "complete the bond" is correct because filling the bar fires the
  sphere-less capture and an owned Pal is no longer spawner-owned.

**URGENT (2026-09-16): v1.1.2 — the SHIPPED version — crashes on a world
change.** Bond a Pal, quit to the menu, load a world →
`EXCEPTION_ACCESS_VIOLATION reading 0x338`. Dragón confirmed it with the
Workshop 1.1.2 copy (vanilla fine, 1.1.1 fine in two runs: pet-only and
feed-only). Cause, from the 1.1.1 log vs the dev log: 1.1.1's fast loop
re-searched for the player every ~4 s, the search came back empty on quit and
`[WORLD-RESET]` dropped every reference; 1.1.2's `PlayerRef.lua` kept returning
the old character (still passing UE4SS IsValid during teardown), so the reset
never ran. The harness reproduces this exactly (`worldchangetest.js`: section C
fails on 1.1.2, passes on 1.1.1).
**Fix (PlayerRef.lua only):** once a second, `UKismetSystemLibrary::IsValid` on
the kept player (engine check, no search); and while a Pal is following, a real
search every 4 s (1.1.1's cadence; never runs with no follower). Both log
`[PLAYER-LIFE]`. **HOTFIX BUILD, in Dragón's game folder for a live test:**
`git show f31b823:release/workshop/PalBonds/Scripts/*.lua` (the exact 1.1.2
release) + `mod/PalBonds/Scripts/PlayerRef.lua` from the working tree, with
`DEBUG_LOGGING` and `PROFILING` on. Today's dev scripts are parked in the game
folder as `ue4ss/Mods/PalBonds/Scripts.dev-2026-09-16`. If the live test holds,
this becomes a 1.1.3 hotfix (ship from 1.1.2 + PlayerRef, logging OFF) before
the boss/Friendly work; do not ship until Dragón confirms in game.
**CONFIRMED 2026-09-16:** several quit/reload runs, no crash; the reset fired
("5 follower(s)"). Cost: ~11 player searches/min at ~39 ms each while a Pal
follows — Dragón: "almost imperceptible... acceptable for now".
**Dragón's call: 1.1.3 = the crash fix PLUS the finished work.** The full dev
tree (`mod/PalBonds/Scripts`, DEBUG_LOGGING + PROFILING on) is in his game
folder as the release candidate. Candidate list given to him: (1) crash fix,
(2) boss tag + bar, (3) failed pets give nothing, (4) no double pay, (5) 3 s
abandon grace — all confirmed live; (6) x2 meter for gym/raid/predator bosses,
(7) humans show Normal and keep their AI, (8) self-defence reach 3000,
(9) 20% brief follow (cat confirmed; no passive gain during it, fixed
2026-09-16) — awaiting the RC run. NOT included: three-boss layout, the
despawn-while-following gap, and the spies (strip before shipping).
**Dragón narrowed it (2026-09-16): 1.1.3 = items 1–7.** Items 8 and 9 wait for
the next update ("once we polish it further"). They stay in the code behind
module switches, both `false` for 1.1.3: `Personality.FRIENDLY_BRIEF_FOLLOW`
(false = the exact 1.1.2 20% behaviour, `legacy_friendly_reset`, plus the
human-NPC guard) and `Combat.SELF_DEFENCE_EXTENDED_REACH` (false = 1800). The
harness tests both states (bosstest G = shipped; B/D switch them on). The dev
copy in his game folder is now the 1.1.3 candidate (`mod/` + DEBUG_LOGGING on,
PROFILING off). He confirmed humans show Normal in the previous run; the last
run checks the boss x2 meter, then GitHub/Nexus/Workshop — build the release
from `mod/` with logging OFF; the spies are diagnostics-gated and silent there.

**v1.1.3 BUILT (2026-09-16), items 1–7, after Dragón's final run** (sleeping
Pal refused, quit/reload with a fed follower fine, boss bars fine, gym Lyleen
bar 250 = x2 and a double pet refused, humans Normal; three bosses at once
still unchecked, too rare). `release/PalBonds/Scripts` and
`release/workshop/PalBonds/Scripts` are byte-identical to `mod/` (10 files,
logging/diagnostics/profiling all false, both held-back switches false),
`release/workshop/PalBonds/Info.json` Version 1.1.3,
`release/PalBonds-v1.1.3.zip` built (same layout as 1.1.2, LICENSE included;
the 1.1.2 zip removed) and the full harness run against the UNZIPPED package.
READMEs updated (bosses x2 wording; crash-fix known-issue entry). Next, one step
at a time as Dragón directs: Nexus (Update button), then Workshop, and GitHub
only when he asks. The dev copy in his game folder still has DEBUG_LOGGING on.
**Nexus 1.1.3 LIVE (2026-09-16 20:31):** header 1.1.3, one main file "PalBonds
V1.1.3" (267 KB), changelog entry in Dragón's one-line-per-change wording.
Workshop upload folder updated to 1.1.3 (10 scripts identical to release,
Info.json Version edited in place, `.workshop.json` untouched — note it still
says last_published_version 1.1.1, so the uploader does NOT write that back).
Local dev copy disabled again (dwmapi.dll / enabled.txt → *.MODS-DISABLED) for
his Workshop test.
**Workshop 1.1.3 PUBLISHED (2026-09-16, `.workshop.json` now says
last_published_version 1.1.3) — BUT the world-change crash STILL happens with
the Workshop install** (0x338 at 20:53:31). The game's copy
(`Mods/NativeMods/UE4SS/Mods/PalBonds/Scripts`) is byte-identical to the
release. Key difference from every successful fix test: the Workshop UE4SS is
a different build (`v3.0.1 Beta, Git SHA 2281fa31`) from the manual one
(`ba2efd55`). Both log "FCallbackGarbageCollector", so that is not it. The
crashed session's UE4SS.log was overwritten by his relaunch 20 s later and the
release writes no mod log. Next: DEBUG_LOGGING + SHOW_DIAGNOSTICS switched on
in the GAME'S Workshop copy (local only, not published) for a logged repro;
he must not relaunch before the logs are read.
**v1.1.3 on GitHub: commit `bd8e0ca` (pushed 2026-09-16). Workshop change note
live (16 SEP 20:46); Steam shows only "Fixed a crash that 1.1.2 introduced" for
the first line — the sentence after the period was dropped.**
**Logged repro (21:01–21:06): NO crash in several tries.** Three quits with a
follower (PinkCat, PlantSlime, and the boss WeaselDragon/Chillet following):
each time `[PLAYER-SPY] search (kept player became invalid)` → `[WORLD-RESET]
the player left the world`. So the fix works on the Workshop UE4SS too; the
20:53 crash is unexplained. Dragón: "im pretty sure all i did was just try to
bond with a boss and then quit and re-join a world", but repeating that didn't
crash; parked until it happens again.
**NEXT SESSION, FIRST TASK — suspect for that crash:** `Indicator.lua`'s
`bossEntries` / `pendingBossGauges` (new in 1.1.3) hold boss-bar widgets and
their `TargetCharacter`, and `Combat.ResetForNewWorld` does NOT clear them
(nor `trackedBars`, the old pass-285 note). The gauge canvas is GameInstance-
lived, so after a world change the 2 s tick can read a widget whose boss is
gone — `Trust.HasBondingState(actor)` / `get_friendship_ratio(actor)` on an
actor that UE4SS may still call valid (it did for the player). Fix: an
`Indicator.ResetForNewWorld()` called from `Combat.ResetForNewWorld`, plus
harness coverage; ship as 1.1.4 once tested. His game's Workshop copy is left
with DEBUG_LOGGING on (SHOW_DIAGNOSTICS off) so a repeat leaves a log.

**NEXT SESSION STARTS HERE (Dragón, 2026-09-15): the boss display update.**
Bosses show neither the trust bar nor the rolled personality tag, because
their HP bar is a different widget from the one Indicator.lua attaches to.
Full notes are in "Next steps" 0b. **2026-09-16: built and deployed to the
dev copy, awaiting its first test run** together with the 20% reset spies
("Next steps" 0c).

**The microstutter report (Workshop commenter *Goldaer*, against 1.1.0) is
RESOLVED in v1.1.2** — reproduced, profiled and fixed on 2026-09-15. The full
record (A/B baseline, profiler, both fix rounds, runs A–F with numbers, and the
remaining minor stalls) is under "Known open defects" #0. Worth telling Goldaer
on the Workshop page once 1.1.2 is published there.

- **GitHub:** `master` is the only branch. **The v1.1.2 commit (2026-09-15) is
  the stable code.** Earlier: `1d06a5a` was the 1.0 stable code, `b10e763` was
  v1.1.1.
- **Steam Workshop:** item **3797816321**, "PalBonds - The Befriending Mod",
  published at 1.1.0. https://steamcommunity.com/sharedfiles/filedetails/?id=3797816321
- **Nexus Mods:** published 2026-09-14. https://www.nexusmods.com/palworld/mods/5623
- **Reddit:** announced in 2 posts.
- **The mod now has real subscribers beyond Dragón.** Anything pushed to
  Steam/Nexus from here on reaches them too — see "Publishing safety" below
  before touching the uploader.
- **Confirmed in live play** (runs 37-39 and the raid-boss test): following,
  combat assist, self-defence, the churn and hit-lag fixes, feed by rarity, the
  alpha x2 bar, the F8 cheer stopping with the Pal, and bonding a raid boss
  without breaking anything.

### Publishing safety — read before touching anything Steam/Nexus-facing

Dragón, 2026-09-14, after seeing changes land in his local Workshop content
folder: *"the idea is that we dont upload things we havent checked yet... we
cant risk something breaking the game for others or causing more problems than
what it fix"*.

- `steamapps\workshop\content\1623730\3797816321\` is a **local folder** on
  Dragón's disk. It is both his subscription (what his game reads when he
  plays the Workshop copy) and the Palworld Mod Uploader's source folder. It
  is completely fine — expected, even — to keep deploying fixes there so
  Dragón can test them in a real session; that is how testing before
  publishing works in this project. **Editing files in it does not reach
  Steam's servers or any other subscriber.** Only running the Mod Uploader
  (which bumps `Version` in `Info.json` and pushes a new version) does that,
  and only that action affects the other subscribers who now exist.
- Never run, or suggest running, the Mod Uploader, `git push` to a shared
  remote treated as a release, or the Nexus upload flow unless Dragón
  explicitly asks for that specific step, separately from "deploy this fix so
  I can test it."
- **One step at a time.** When Dragón names a later step alongside the current
  one ("check the Nexus page, then we do the Steam Workshop"), that is him
  describing the order of work, not authorising the second half. Do the step he
  asked for, report, and stop — including the read-only prep for the next step,
  which from his side looks identical to starting it. He interrupted a turn
  over exactly this on 2026-09-15.

### Publishing procedure — both stores, as actually performed for 1.1.1

**Nexus (mod 5623).** Use the **Update** button on the existing file's row, NOT
"Add file". "Add file" creates an independent second entry and leaves the old
one live; Update links them, archives 1.1.0 (still downloadable under "File
archive"), and — the part that matters — tells everyone who downloaded the old
file, including Vortex and the Nexus app, that an update exists. Fields that
were used: category Main, display name `PalBonds V1.1.1`, file version `1.1.1`,
**tick "update mod version to match"** (this is what bumps the page header;
without it the page keeps advertising the old version), allow mod manager
download, set as primary, plus a changelog entry. The changelog is what Vortex
shows at the update prompt, so it is worth filling in.

**Steam Workshop (item 3797816321).** The uploader's source folder is
`steamapps\workshop\content\1623730\3797816321\`. Publishing means: replace EVERY
script from `release/workshop/PalBonds/Scripts/` (10 since v1.1.2, which added
`PlayerRef.lua` and `Profiler.lua` — copying only the old 8 would ship a build
that fails to load), bump `Version` in `Info.json`, leave `.workshop.json` **untouched**,
then Dragón runs the Palworld Mod Uploader.

- `.workshop.json` holds `publishedfileid` and is the only thing tying the
  local folder to the published item. Preserve it and the uploader updates
  3797816321; lose it and the uploader would publish a DUPLICATE mod page.
  After a successful publish the uploader writes `changenote` and
  `last_published_version` back into it — a cheap way to confirm the push
  landed.
- **Reload the uploader** before publishing if it was open while the files
  changed; it reads `Info.json` at scan time. The version it displays is the
  proof — if it still shows the old number it has stale data, and uploading
  then would push new scripts under the old version.
- Edit `Version` **in place** in the live `Info.json` rather than copying
  `release/workshop/PalBonds/Info.json` over it, so no other field or the file's
  line endings can drift.
- `Info.json`'s `MinRevision` is a floor, not a pin — a Palworld update does not
  require changing it.

**BUG UNDER INVESTIGATION (2026-09-15, found on the published v1.1.2): the
"abandoned" status never triggers.** Dragón bonded a Pal, then ran far away to
see the "left behind" toast, but the bond never broke.

- **His question:** could it be the player-check change made for the
  stutters (PlayerRef)?
- **Code facts:**
  - `EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS = false`, so punishment is not switched
    off.
  - Past `MAX_FOLLOW_DISTANCE` (3000) and not fighting for
    `DRIFT_GRACE_SECONDS` wipes friendship and calls
    `on_follower_lost_all_trust("too far from player")`, which gives the
    "abandoned" toast.
  - **`DRIFT_GRACE_SECONDS` is 3 as of 2026-09-15 (was 15).** Dragón asked
    when the window had appeared: he expected the pre-pass-323 rule, where
    crossing the leash ended the bond instantly unless the Pal was fighting.
    The history shows pass 323 (2026-09-12) added the 15s window after his
    complaint about losing Petallia right after a fight, and that he was only
    consulted on march-vs-warp, not on the window covering ordinary drift. He
    then set it to 3: *"ok, shorten that to 3 seconds"*. A Pal that is
    fighting is still fully protected, with no clock at all.
  - A scratch harness run of the REAL Trust tick with diagnostics on still
    breaks the bond correctly. The logic works offline, so the in-game cause
    is an input.
- **DIAGNOSED from the spy run (log archived at
  `perf-captures/bug-abandon-palbonds-live.log`, 19:20–19:23):**
  - **The player lookup is NOT the cause.** PlayerRef kept the same
    `BP_Player_Female_C` all run (safety-net searches only), and neither Pal
    was ever "fighting".
  - **Pal 1, Ribbuny Botan: abandonment WORKED.** Recalled past 1800, drift
    clock started at 3475, still 10340 units away at 15s. Then "losing all
    trust", `follow stopped: too far from player`, and the bond-lost message
    "Ribbuny Botan was left behind and gave up on you." Whether it appeared on
    screen still needs Dragón's confirmation.
  - **Pal 2, `BP_FlowerRabbit_C`: the bug.** Drift clock started at 4514
    (19:22:23). Its distance then jumped 6402 → 11082 → **261373** with "no
    controller", its last trace was a TRAINER-REASSERT to Destination (0,0), and
    its spy lines stopped at 10.6s of 15s. No break, no toast, and it was still
    counted as a follower at the world reset ("1 follower(s)").
  - **Cause:** the known spawner despawn (see "KNOWN LIMITATION" below)
    removed the actor mid-countdown. `tick_followers` only processes a
    follower inside `if stillValid then` (Trust.lua ~1167–1506) and has **no
    `else`**, so an invalid follower is skipped silently forever. Its State
    entry, and Combat's follower references, linger until the world reset.
- **Fix to decide with Dragón (it changes what the player sees):** when a
  following Pal goes invalid, end the bond cleanly and tell the player.
  Open questions:
  - which message when its drift clock was running (probably the "left
    behind" one);
  - which message when it despawned while following nearby, which the known
    limitation says also happens;
  - whether an invalid Pal's trust should be kept or wiped. Its identity and
    friendship survive the despawn.

  Also clean up Trust State and Combat's `FollowerActors`/`BondingState` for
  it. The spies stay until the fix is verified in game.
- **Spies added (in `mod/`, diagnostics-gated, REMOVE once this is answered):**
  - `[LEASH-SPY]` every 3s per follower, showing distance, pastLeash, fighting
    plus the reason and hate-target name, the drift clock, the player name and
    both positions.
  - `[LEASH-SPY] leash check SKIPPED` when there is no player position.
  - `[PLAYER-SPY]` on every PlayerRef search (with its reason), death,
    respawn and invalidation.
  - `Combat.IsBusyFighting` now also returns the reason and target; its first
    return value is unchanged.
  - All suites pass; the spy paths were checked offline with diagnostics on.

**UPDATE 2026-09-15, after the publish — back in DEV MODE with FULL LOGGING to
chase a bug Dragón found.** He described it only as "not terrible"; the details
were still to come, and he wants the fix ideally in tomorrow's update.

- **Workshop items:** Dragón unticked both in-game. Verified: no
  `ActiveModList` lines, so it is safe for the manual UE4SS to load alone.
- **Dev install re-enabled:** the `dwmapi.dll` and `enabled.txt` renames were
  reversed.
- **The dev copy is v1.1.2 except three switch lines:** `DEBUG_LOGGING = true`
  and `SHOW_DIAGNOSTICS = true` in its `Logger.lua`, and `PROFILING = true` in
  its `Profiler.lua`.
- **Logs:**
  - `Pal\Binaries\Win64\palbonds-live.log`, written in "w" mode, so it is
    overwritten on every launch. Read it before the next launch.
  - `Pal\Binaries\Win64\palbonds-profile.log`.
- **Before any future publish:** switch all three back to false. They are only
  ever changed in the live dev copy; `mod/` and `release/` stay false.

The Workshop-mode snapshot below is how the machine was right after the
publish, before this.

**Dragón's machine at 2026-09-15 15:26 — WORKSHOP MODE on the published v1.1.2:**
- **Both Workshop items are ticked in-game.** `PalModSettings.ini` lists
  `ActiveModList=UE4SSExperimentalPW` and `ActiveModList=PalBonds`.
- **The game's installed copy is v1.1.2.** `Mods\NativeMods\UE4SS\Mods\PalBonds\`
  is md5-identical to `release/workshop/PalBonds/Scripts/` (10 scripts,
  `PROFILING = false`). `Mods\ManagedMods\PalBonds\Info.json` reads Version
  1.1.2. The InstallManifest shows LastInstallTimeUtc 18:25:55 and tracks 11
  files.
  - Re-ticking the items after the upload DID recopy it this time. Before that
    the copy was still 1.1.1, with the two new files missing, so keep checking
    by hash after every publish.
  - The InstallManifest's `LastWorkshopUpdateTimeUtc` still shows the old
    03:29:50 value; the files are what count.
- **The Workshop UE4SS loaded it cleanly at 15:25:57:** 14 hooks, no Lua errors.
- **The uploader folder** `steamapps\workshop\content\1623730\3797816321\`
  holds the same 10 scripts and Version 1.1.2. Its `.workshop.json` reads
  `last_published_version` 1.1.2.
- **The dev install is DISABLED** (`dwmapi.dll.MODS-DISABLED`,
  `enabled.txt.MODS-DISABLED`); its local UE4SS.log is untouched since 15:04.
  - Its `Profiler.lua` still has `PROFILING = true`. Its other 9 scripts match
    v1.1.2.
  - To go back to dev mode, follow the order in the DEV MODE notes below:
    untick both items in-game first, then reverse the two renames.

The DEV MODE notes that follow describe how the machine was during the
performance work.

**Dragón's machine during the performance work, 2026-09-15 11:11 — DEV
MODE, Workshop mods switched off in-game but still subscribed:**
- **Switching between Workshop and dev no longer needs unsubscribing (found and
  verified 2026-09-15).** Palworld's own mod manager keeps its state in
  `Palworld\Mods\PalModSettings.ini` (`bGlobalEnableMod`, one `ActiveModList=`
  line per active mod). Dragón unticked BOTH Workshop items in-game (PalBonds
  and UE4SS Experimental), which emptied `ActiveModList`. The Workshop files
  stay on disk under `Mods\NativeMods\UE4SS\` and `Mods\ManagedMods\`, but the
  game **does not load them while unticked** — proven by
  `Mods\NativeMods\UE4SS\UE4SS.log` keeping its pre-toggle timestamp across
  later launches. With that confirmed, the two manual-install renames were
  reversed (`dwmapi.dll`, `ue4ss\Mods\PalBonds\enabled.txt` restored) and the
  manual stack loaded alone: one UE4SS (`Loading mods from:
  ...\Pal\Binaries\Win64\ue4ss\Mods`), PalBonds initialised, Dragón petted a
  wild Cattiva and it joined, no crash.
  - **To go back to Workshop mode:** close the game, rename `dwmapi.dll` →
    `dwmapi.dll.MODS-DISABLED` and `enabled.txt` → `enabled.txt.MODS-DISABLED`
    FIRST, then tick both items in-game. Never have the local `dwmapi.dll`
    active while the Workshop UE4SS is ticked — two UE4SS loaders crash the game.
  - **The safety check before re-enabling local:** launch once with local still
    disabled and confirm the Workshop `UE4SS.log` timestamp did not change.
  - **The game DOES detect the manual install.** It shows its "mods active"
    warning with only the local UE4SS running, even though the Workshop items
    are off. (An earlier assumption that it could not see a manual install was
    wrong.)
- **The two UE4SS builds differ.** Local/dev: `v3.0.1 Beta #0, Git SHA
  ba2efd55`, GUI console ON in its `UE4SS-settings.ini` — which is why Dragón
  sees a live log window in dev mode. Workshop (what subscribers run): `Git SHA
  2281fa31`, console OFF. **Matters for performance work:** a stutter measured
  on the dev build is not automatically what subscribers get.
- **The copy the game runs in dev mode is `Pal\Binaries\Win64\ue4ss\Mods\PalBonds\`,
  at 1.1.1** — md5-identical to `mod/` on all 8 scripts, `DEBUG_LOGGING` and
  `SHOW_DIAGNOSTICS` both `false` in its `Logger.lua`. The Workshop copy at
  `Mods\NativeMods\UE4SS\Mods\PalBonds\` is also 1.1.1 but dormant. Steam's
  re-download on resubscribe brought it current, which is NOT the usual
  behaviour (see the fourth-copy warning below): normally that copy is written
  once and never re-synced. **Always verify it by hash rather than assuming
  either way.**
- The pre-unsubscribe backup at
  `save-backups/workshop-3797816321-before-unsubscribe-2026-09-14/` is still
  the insurance copy if Steam ever refuses a resubscribe. It contains a
  `.workshop.json` with the real `publishedfileid`, which means the uploader
  folder can be rebuilt **by hand, without resubscribing at all** — worth
  remembering, because resubscribing is what forces the manual install off.
- **The live install now runs the clean v1.1.1 build**, byte-identical to
  `mod/` on all 8 scripts — every diagnostic and experiment from the despawn
  investigation was reverted, and `DEBUG_LOGGING` / `SHOW_DIAGNOSTICS` are
  back to `false` (the shipped configuration). To debug again, set them
  `true` in the live install's `Logger.lua` only; `palbonds-live.log` is
  written to `Pal\Binaries\Win64\palbonds-live.log` (opened in `"w"` mode, so
  it truncates fresh each launch), and **remember that `SHOW_DIAGNOSTICS` is
  a separate switch** — `DEBUG_LOGGING` alone leaves every suppressed tag
  invisible, which cost two test runs this session.
- **Historical, for when Dragón resubscribes to Workshop later for QA:**
  `steamapps\workshop\content\1623730\3797816321\` was both his subscription
  and the uploader's working folder — publishing still means replacing the 8
  scripts there, bumping `Version` in `Info.json`, and uploading with the
  Palworld Mod Uploader. **Found 2026-09-14, still true whenever Workshop is
  subscribed again:** the file the game actually runs while Workshop-
  subscribed is a FOURTH copy, not the Workshop content folder itself —
  Palworld's mod manager copies each subscribed mod once into
  `Palworld\Mods\NativeMods\UE4SS\Mods\<ModName>\` and does not keep it synced
  afterward (confirmed stale a full day after the source was fixed). Any
  future Workshop-based test needs that copy refreshed by hand too, and
  `palbonds-live.log` has always lived at `Pal\Binaries\Win64\palbonds-live.log`
  regardless of which Mods subfolder the script loaded from — never inside a
  Mods folder itself. The folders 3797815819 and 3797816106 next to the real
  item are leftover uploader templates, not real Workshop items — harmless.
- **Save backups (gitignored):** `save-backups/2026-09-12_before-raid-boss-test/`
  (SaveGames plus `SteamCloud_1623730`, every file MD5-verified),
  `save-backups/workshop-3797816321-published-1.0.0/`,
  `save-backups/recreated-workshop-folder-3797816321/`, and
  `save-backups/workshop-3797816321-before-unsubscribe-2026-09-14/`. To
  restore saves: close Palworld, replace the contents of
  `%LOCALAPPDATA%\Pal\Saved\SaveGames\` with the backup's (and
  `Steam\userdata\<account>\1623730\` with `SteamCloud_1623730`), then launch.
  The Global Palbox is the local `GlobalPalStorage.sav` and is included. Real
  Steam and world IDs are deliberately not written in this public file.

**Stable-build flags:** `DEBUG_LOGGING = false` in every tree (to debug, set it
`true` in the live install's `Logger.lua` only), `ACTION_CHANGE_PROBE = false`,
`SHOW_DIAGNOSTICS = false`, `QUIET_RETALIATION_DURING_PLAYER_FIGHT = true`,
`DISCOVER_BATTLE_DURING_PLAYER_FIGHT = true` (runs 35/36 inconclusive, left on).

**Store packaging facts:**
- Workshop Info.json: ModName "PalBonds - The Befriending Mod", PackageName
  PalBonds, Author DragonKaiser, Thumbnail thumbnail.jpg, Tags UE4SS + Gameplay,
  InstallRule Lua `./Scripts`, UE4SS dependency string `"UE4SSExperimentalPW"`.
  No enabled.txt in Workshop packages (Palworld's mod manager handles it).
- Nexus / manual: the `PalBonds/` folder with enabled.txt goes into
  `Pal/Binaries/Win64/ue4ss/Mods/` (manual UE4SS) or
  `Palworld/Mods/NativeMods/UE4SS/Mods/` (Workshop UE4SS).
- Thunderstore needs a different layout (manifest.json, 256x256 icon,
  mod/scripts, mod/enabled.txt, shimloader dependency). Not built.

## Species name mapping

Dragón refers to his own Pals by their in-game species name; the code and
every log line show the internal `CharacterID`/class name instead. Confirmed
mappings so far (from `docs/hook-points-archive.md`'s species-mapping
correction and repeated log cross-references) — **check here before ever
flagging a log's species name as a "mismatch" or "mix-up":**

| Dragón's name | Internal class / CharacterID |
|---|---|
| Petallia | `BP_FlowerDoll_C` (alpha/boss form: `BP_FlowerDoll_BOSS_C`) |
| Tanzee | `BP_Monkey_C` |
| Flopie | `BP_FlowerRabbit_C` |
| Daedream | `BP_DreamDemon_C` |

## What this mod is

Instead of only capturing Pals by force, the player walks up to a wild Pal and
pets, feeds and plays with it. A per-individual trust value rises with good
treatment and slowly while the Pal follows. Cross 20% and its personality turns
friendly; cross 50% and it follows and defends the player; fill the bar and it
joins the party on its own, with no sphere thrown. Hit it yourself, or leave it
too far behind, and you lose it.

Nothing new is authored — no models, textures or animations. Everything reuses
behaviour the game already has.

**Scope:** singleplayer / self-hosted only. Mods on official Pocketpair servers
risk a ban.

**Stack:** UE4SS (Okaetsu's experimental Palworld build, v3.0.1 Beta, Git SHA
`ba2efd55`) with all logic in Lua. The installed build's authoritative Lua API
is the `docs/lua-api/` folder of that exact commit — not memory, not a strings
grep of `UE4SS.dll` (both have produced wrong API names here; see "Retired
approaches").

---

## Current state

v1.1.0 is published (see "Where we stand"). v1.0.0 (commit `abe5ec8`) was the
earlier release; both crash fixes found after it (world change, pass 285;
death/respawn, commit `94adf54`) are in 1.1.0. Confirmed in live play:

- Pet, feed and play on wild Pals through the game's own radial menu, plus F8
  Play, with the player's cheer ending together with the Pal's animation
- Trust bar and personality tag drawn under the wild Pal's health gauge
- Seven personalities rolled per individual, with player-facing names
- Bonded Pals follow, stay *behind* the player, and hold still while aimed at
- Combat assist via the Hate system, and self-defence when a companion is
  attacked outside the player's fight
- Feed trust by food rarity (50 + 10..50); Kinship Peaches keep 250 / 500
- Level-scaled bonding bar; alpha (`BOSS_`) Pals need twice the trust
- Sphere-less joining, with a celebration animation, a join VFX, a named toast,
  and a flat +50000 friendship head start
- Betrayal (player hits the Pal) and bond loss by distance
- F9 personality tags on/off, F10 passive friendship gain on/off

### Owned-Pal tag fix, 2026-09-14 — CONFIRMED, and the only change in v1.1.1

Dragón noticed already-captured Pals were rolling a random personality tier
(and showing its tag) the first time they were summoned as the active Otomo
or placed to work at a base. Root cause: `Personality.GetOrInitState` creates
state for every `PalCharacter` the periodic scan finds via `FindAllOf` —
owned or wild — and only checked monster/NPC status before rolling, never
ownership. Enforcement already refused to ever *write* a rolled tier onto an
owned Pal's real AI (`try_enforce_personality_with_sensor`'s existing
`Capture.IsAlreadyOwned` check), but nothing stopped the roll itself from
being assigned and displayed for a Pal that was already the player's own.

**The fix, both halves:**
1. `Personality.GetOrInitState` checks `Capture.IsAlreadyOwned(palActor)`
   before rolling, in the same "checked before anything else" position as the
   existing monster/NPC exclusion — an owned Pal gets `rolledTier = "normal"`
   unconditionally, same treatment as NPCs/bosses/village NPCs.
2. `Indicator.lua`'s `personality_display_text` checks the same thing first,
   before even the broken-bond label, and returns an empty string for any
   owned Pal — **no tag at all**, per Dragón: *"owned pals should not show
   tags at all, they're already part of the player's roster so they dont need
   any tag."*

**Confirmed live.** Dragón summoned 22 base Pals + 1 Otomo (23 owned) plus
whatever wild Pals were nearby. The log's breakdown: 22 `normal (already
owned)`, 1 `normal (not a confirmed monster)` — together exactly his 23 owned
Pals, all excluded — plus 24 genuinely wild Pals rolling real variety and 11
more landing on `normal` by honest chance (the 35% weight). Then the display
half was confirmed separately: *"now it looks as it should."*

Minor known quirk, not urgent: one Otomo took the "not a confirmed monster"
branch rather than "already owned". Same visible result either way.

**Three process lessons from getting here, all of which cost real test runs:**
1. **A deploy that misses one copy looks exactly like a fix that doesn't
   work.** The first test showed no change because the build never reached
   the copy the game actually runs. See "Deploying a change".
2. **`SHOW_DIAGNOSTICS` is a separate switch from `DEBUG_LOGGING`**, and
   `[PERSONALITY-ROLL]` is in `SUPPRESSED_TAGS` — so the log looked empty
   while the code was running fine. Two more tests were spent concluding "it
   never ran" from a filtered log, against Dragón's direct in-game
   observation. **His direct observation was right; the log was blind.**
3. When a log can't distinguish two explanations (here: "excluded because
   owned" vs "rolled normal by chance"), **fix the log rather than guess** —
   adding the reason to the line is what actually settled it.


### Dev-vs-QA install — Dragón's call, 2026-09-14, adopted

Dragón, after two wasted test cycles in one session: *"felt like we were much
better before working entirely on local... working with the mod subscribed is
useful to check what the other players are seeing, but that should be QA, not
our DEV."* Correct, and now backed by concrete evidence from the same session:

- The Workshop-subscribed setup has (at least) two copies to keep in sync —
  the subscription/uploader folder AND the separate native-mods copy Palworld
  actually runs — versus one copy for a manual install. Missing the second
  one silently produced "the fix didn't work" instead of "the fix never ran,"
  costing a full test cycle before it was even noticed.
- `DEBUG_LOGGING = false` is correct for the stable/shipped build, but it also
  means `palbonds-live.log` — the fast, direct diagnostic this project has
  relied on since its first session — writes nothing at all. Confirming
  anything now requires reading UE4SS's own log instead
  (`Palworld\Mods\NativeMods\UE4SS\UE4SS.log`, or
  `Pal\Binaries\Win64\ue4ss\UE4SS.log` for a manual install), which mixes
  engine noise with mod output and has none of `Logger.lua`'s own filtering.
- A manual install lets `DEBUG_LOGGING` be flipped `true` in exactly one file,
  in Dragón's own dwmapi-toggled copy, with zero effect on what any subscriber
  sees — the same isolation the "Publishing safety" section above already
  established for local edits, just applied to the *manual* copy instead of
  the Workshop one.

**Going forward: active development uses the manual install; the Workshop
subscription is for periodic QA only** — confirming what real subscribers
experience on a build about to be published, not day-to-day iteration. To
switch back to manual for a dev session: re-enable
`Pal\Binaries\Win64\dwmapi.dll` and
`ue4ss\Mods\PalBonds\enabled.txt` (reverse the `.MODS-DISABLED` rename), and
make sure the Workshop-based UE4SS ("UE4SS Experimental", 3625223587) is not
also active at the same time — **never both**, the game crashes when two
UE4SS copies load. Exact toggle mechanics for disabling a subscribed Workshop
mod without unsubscribing are Dragón's own call/action in Palworld's in-game
mod list; not yet exercised this session.

### Cleanup pass, 2026-09-11

An external audit (a different AI, without this project's context) returned a
cleaned tree. It was verified rather than trusted, and the result is now
deployed to `mod/`, `release/PalBonds/` and the live game install:

- Shipping code went from 6,230 to 4,763 real code lines. All of it was dead
  research code; every functional hook survived (14 of them), and every
  hard-won fix survived byte-for-byte, including the pass-285 GameInstance
  outer fix.
- **It shipped two real defects, both fixed here.** `WORKER_MENU_OVERLAY_CLASS`
  was used but its declaration deleted — an undeclared Lua local reads as a nil
  global, so `Interaction.Init()` threw, and `Trust`/`Combat`/`Capture` never
  initialised at all (9 hooks instead of 57). And `update_territory_anchor` was
  called after its definition was deleted, throwing silently on every follow
  tick inside `safe_call`.
- Two genuine improvements were adopted from it: `[FOLLOW-RESTORE]` (detect via
  `HasAction` that the follow action is no longer installed and rebuild it —
  more precise than only rebuilding when the Lua object goes invalid), and
  moving `ApplyCompanionPreset` above the `GetHateSystem()` early return so
  preset restore no longer depends on the hate system being readable.

**Lesson worth keeping:** the break was invisible to reading and would have been
invisible in game (the mod loads, prints nothing alarming, and simply does
nothing). It was caught by *running* the code. See "Verifying a change" below.

---

## Where things live

```
32-PalBonds/
  CLAUDE.md            <- this file: current state, rules, next steps
  CLAUDE-archive.md    <- full narrative history (Continuación 1-180)
  DESIGN.md            <- the design: subsystems, phases, research questions
  README.md            <- repo readme (GitHub-facing)
  mod/PalBonds/        <- dev tree, mirrors what ships
  release/PalBonds/    <- release staging (same Scripts as mod/)
  release/README.txt   <- the readme that ships to players
  release/workshop-description.txt  <- Workshop description as saved (live page edited later by Dragón)
  release/nexus-description.txt     <- Nexus description (BBCode)
  release/PalBonds-v1.1.0.zip       <- Nexus / manual-install package
  release/workshop/PalBonds/        <- Workshop package mirror (Info.json, thumbnail.jpg, Scripts)
  save-backups/        <- real save data and Workshop folder backups (gitignored)
  images/              <- Steam Workshop screenshots
  docs/hook-points.md  <- technical pass-by-pass log (the real detail)
  docs/hook-points-archive.md
  stale/               <- archived, not part of the product (gitignored)
```

`mod/PalBonds/Scripts/` and `release/PalBonds/Scripts/` are kept identical, and
both are kept identical to the live game install. There are exactly 8 modules:
`main`, `Logger`, `Personality`, `Interaction`, `Trust`, `Combat`, `Capture`,
`Indicator`.

**Live game install:**
`C:\Program Files (x86)\Steam\steamapps\common\Palworld\Pal\Binaries\Win64\ue4ss\Mods\PalBonds\`

---

`tools/harness/` — the offline fengari test harness (see its own README, and
the section on it further down). Its `node_modules/` is gitignored; restore with
`npm install fengari`.

`stale/` — gitignored local archive: the five third-party reference mods, the
FModel mapping data, the pre-release dev-install backup, and retired research
modules. Nothing in it is part of the product, but the reference mods are worth
re-reading before building anything new (see the design rule about existing
implementations).

## Working procedures

### Deploying a change

Copy the changed `.lua` to **every** location listed under "Where we stand"'s
"Dragón's machine right now" note — dev tree, release staging, the manual live
install, the Workshop content folder, AND (2026-09-14 on) the Workshop native
mods copy (`Palworld\Mods\NativeMods\UE4SS\Mods\PalBonds\Scripts\`), which is
the one Dragón's actual play session runs while manual install stays disabled
— and confirm with `md5sum` that all of them match. A change that is only in
`mod/` has not been tested by anyone; a change that reaches everywhere except
the native-mods copy tests nothing either, and looks exactly like "the fix
didn't work" instead of "the fix never ran" — this already cost one full test
cycle.

### Verifying a change — do this before asking Dragón to test

There is no Lua interpreter on this machine, but `fengari` (a Lua 5.3 VM in
JavaScript) runs under Node and is enough to catch load-time breakage:

```bash
npm install fengari
node harness.js <path-to-Scripts> prelude.lua
```

`prelude.lua` stubs the UE4SS globals (`RegisterHook`, `FindFirstOf`,
`ExecuteInGameThreadWithDelay`, `UEHelpers`, …) as no-ops returning nil, then
the harness `dofile`s the real `main.lua`. What it proves:

- whether `main.lua` completes or aborts, and on which line
- how many hooks register — **the healthy number is 14**; a lower number means
  init died partway and everything after it never ran

It cannot prove gameplay behaviour, since every game call returns nil. It
catches exactly the class of bug that reading misses. The working copies live in
the session scratchpad; rebuild them if they are gone, it is worth it.

### Turning mods off (Dragón joins community servers)

Any active mod is a ban risk there. Rename, in
`Palworld\Pal\Binaries\Win64\`: `dwmapi.dll` → `dwmapi.dll.MODS-DISABLED`.
That single file is UE4SS's proxy DLL, so without it no Lua mod runs at all.
Reverse the rename to re-enable. Check separately that
`Pal/Content/Paks/LogicMods/` and `~mods/` are empty and that no other proxy DLL
(`xinput1_3`, `d3d11`, `version`, `winmm`, `dinput8`, `bink2w64`) is present.
Client-side cleanliness is verifiable; a third-party server's own policy is not.

---

## Decisions that are settled — do not re-litigate

- **Pet and Feed are radial-menu interactions, not keys.** F9/F10 as Pet/Feed
  were removed deliberately. Play keeps F8 only because it has no radial-menu
  equivalent yet.
- **Grumpy and Hostile stay separate personalities.** Dragón: *"while grumpy
  doesnt attack inmediately, it can attack if it sees another pal of its same
  species attacking, so kind of like they join - its an interesting
  personality"*. Do not merge them as a tidy-up.
- **No fallbacks that hide failure** while the project is in development. A
  failed read shows "unknown", never a plausible-looking default. This came from
  a real bug where a "friendly" fallback made most Pals look friendly.
- **Read everything you need from a Pal BEFORE `PalCaptureSuccess` runs.** The
  actor is torn down during capture and every component read fails afterwards.
  This bug has been introduced twice; resolve names and handles up front and
  pass them along as plain values.
- **`ActionComponent:ActionIsEmpty()` is not a reliable "is busy" signal.** It
  reports empty in the gaps between steps of a real multi-part interaction.
  Three separate attempts to detect "the animation finished" failed on it; the
  capture delay is now a fixed 5s on purpose.
- **A low-level Pal bonding in a single interaction is intended, not a bug.**
  Dragón, 2026-09-11: *"yes the level difference allowed to bond with just 1
  interaction thats on purpose to somewhat match high level catch on low level
  pals"* — it mirrors how trivially a high-level player captures a low-level
  Pal normally. A lv30 Pal against a lv61 player gets a 125-point bar, and one
  75-point feed clears 50% of it. Do not "fix" this.
- **Never propose removing a working feature to work around a bug.** Fix it, or
  ship with the limitation documented.
- **Feed trust scales with item rarity; Kinship Peaches are the exception.**
  Feed = 50 base (same as Pet and Play) + 10/20/30/40/50 for rarity 0-4
  (common..legendary), confirmed in run 38 (Carrot/Berries = 0, uncommon = 1).
  Kinship Peaches keep 250 (lesser) / 500 (full). Dragón, 2026-09-12: *"lets
  keep the kinship peaches special values, differently than other food, they
  cannot be cooked or made, only found out, so it makes sense that those peaches
  are special things"*.

## Two routes to "the right brain" — Dragón has ruled on both (2026-09-12)

Pass 325 found that `UPalOtomoHolderComponent::ActivatePalByHandle` spawns a Pal
as a real active Otomo, with `BP_MonsterAIController_Otomo_C`, using only the
game's own systems (proven by the Multi Party Pals Summons reference mod). That
gave two possible ways to stop fighting the wild AI:

**1. Capture the Pal earlier — REJECTED, do not propose again.** Summoning a
bonded Pal as an extra Otomo requires it to be in the party, so it would mean
capturing at the moment following starts instead of at full trust. Dragón's
ruling: *"i honestly dont like it, because it would shorten the bond with the
player we would be losing betrayal, passive friendship gain, the toasts, etc -
too many things just for one, so that consider it a no go."* The bonding phase
is the product; trading it for better pathing is the wrong trade.

**2. Possess the wild Pal with an Otomo controller — held in reserve.** Not
rejected, but explicitly not the current plan: *"lets leave it as a risky option
if what you're currently doing doesnt work and we have to try other things - if
your method works, then that settles it and we wont even need to try that."* So
this is only on the table if the action-pushing approach stops improving. Do not
open it while the current method is still gaining ground.

---

## Retired approaches — do not resurrect

Each of these was killed by evidence, not suspicion:

- **Territory / leash following** (`SetupLeash`) — an inner radius tight enough
  to hold followers also caged them, so they could not reach an attacker and
  stopped defending themselves. Also leaked leash actors.
- **The repeated Otomo composite** (`SetRootComposite` + `SetOtomoFollowAction`)
  — reported success every time and moved nobody.
- **`ABP_ReturnPalEffect_C` as the join VFX** — correlates only with switching
  active Otomo, never with a capture. The real VFX was found later.
- **`SelectedFeedingItem` called cold** — caused a crash that left the game
  running but unresponsive.
- **`OpenOtomoFeedInventory()` to open the picker directly** — needs a real
  deployed Otomo, so a new player could never feed, never bond, never get a
  first Pal.
- **Guessing UE4SS API names.** `RegisterInitGameStatePostHook` is real;
  `…PostCallback` is not. Four wrong names cost four test cycles. Read the api
  docs at the installed commit.
- **Subtracting hate to steer a target.** Run 25's `[HATE-VERIFY]` logged the
  player still most-hated *immediately after* `ChangeHate(-999999)`. Every fix
  built on it was a no-op: `clear_player_hate`, `PLAYER_OUTBID_HATE`,
  `Trust.ClearMutualHate`, `enforce_companion_truce`, `release_assist_hate` and
  the original hate-based recall. Adding hate still works and is what
  `[HATE-ASSIST]` uses.
- **`TargetActor` and `SetTargetAndNextAction` on the running combat action.**
  Both are declared on `UPalAIActionCombatBase`, and neither resolves on
  `BP_AIAction_CombatPal_C` in this build. `SetTargetAndNextAction` failed 29
  times out of 29 in run 27 with *"attempt to call a TrivialObject value"*, and
  `TargetActor` read as unreadable every time. Recorded once already in pass 217
  and repeated in pass 322 — **check `docs/hook-points.md` before reaching for
  this class again.** Use `UPalHate::FindMostHateTarget()` instead; it works.
- **UE4SS's async Lua** (`LoopAsync`) — a UE4SS collaborator states plainly it
  is unsafe. Dead fallbacks using it still exist in `Trust.lua` and
  `Indicator.lua`; see open defects.

---

## Combat assist and following — where they stand (runs 37-39, 2026-09-12)

**Working and confirmed live.** Dragón after run 37: *"the pals behaved
nicely"*; after run 38: *"it was a lot better this time, wasnt as laggy during
fights"*; run 39 and the raid-boss test: nothing broke.

What made the difference (details in `docs/hook-points.md`):
- **The recall-vs-assist loop.** Companions are not sent after an enemy further
  than `COMBAT_RECALL_DISTANCE` (1800) from the player, nor while their own
  recall is running. It had cost up to 68 follow rebuilds and 140 combat
  installs in one fight. `reachtest.js`.
- **Follow starvation.** The global follow-install limit is deleted; it lost
  five Pals in run 36. Per-Pal install caps are 60s rolling rates.
  `captest.js`.
- **Hit lag.** The damage hooks looked the player up with a full `FindAllOf`
  walk on every hit (41 walks per 30-hit burst). Now cached, at most 2.
  `hitcosttest.js`.
- **Self-defence.** `Combat.OnFollowerAttacked`: a companion hit outside a
  player fight fights back, only that Pal (Dragón's call).
  `selfdefencetest.js`.

Still true, not blockers:
- **Friendly fire.** With 4-6 companions, 5-20 companion-on-companion hits per
  fight; target discipline ends the duels. The runs 35/36 A/B on
  `DISCOVER_BATTLE_DURING_PLAYER_FIGHT` was inconclusive (two versus six
  companions), so both switches stay on. Any future A/B must use an in-session
  toggle rather than two separate runs, because spawns cannot be controlled.
- **Remaining hook cost.** Run 38 measured ~4.7 ms per damage event inside the
  two damage hooks, including one-off fight assignment. The measuring wrapper
  (`timed_hook` / `[HIT-COST]`) was removed for the stable build; bring it back
  from commit history if lag returns.
- The follow and combat actions still share priority slot 10, so some install
  churn per fight is inherent.

---

## The offline test harness — use it, it has paid for itself

`tools/harness/` holds a fengari-based harness that runs the **real mod source**
with the UE4SS globals stubbed. `tools/harness/README.md` has the full command
list. Short version:

```bash
cd tools/harness && npm install fengari
node syntaxcheck.js ../../mod/PalBonds/Scripts
node assisttest.js  ../../mod/PalBonds/Scripts prelude_323.lua
```

It cannot prove in-game behaviour. It has still caught bugs no test run could
have distinguished from "it didn't work again":

- a loop early-out that disabled the recall for exactly the Pal that needed it
- a recall measuring distance from the aim camera, so a failed camera read
  silently switched it off
- a call placed ~850 lines above its definition (a nil global, swallowed silently)
- the pass-331 damage gate that switched combat assist off completely

**The rule: a regression test must be run against the broken code too.** A test
that passes both before and after a fix proves nothing. Every bug-driven suite
in there was verified by reverting the fix in a throwaway copy and confirming the
test fails. Do the same for the next one.

## Never budget a retry from mod load

**Third instance, and it cost a Pal (run 29, 2026-09-12).** `FOLLOW_ACTION_MAX_TOTAL = 40`
counted follow-action installs from mod load and never reset. It ran out
mid-session; `followActionDisabled` latched true; from that second on, no Pal
could ever be given a follow action again. A Flopie then wandered off with
nothing installed to hold her and was lost while Dragón stood still watching.

It survived the earlier cleanup of this exact bug shape because it did not look
like a retry budget — it is a *leak guard*. **The rule covers both.** Any
counter that latches something off permanently, for any reason, is wrong unless
the thing it guards is genuinely unrecoverable. Leak guards should be rolling
rates (N per window, recovers when the window turns over), never lifetime
allowances. Check `FOLLOW_ACTION_MAX_PER_PAL`, `TRAINER_REASSERT_MAX_TOTAL` and
anything else shaped like them before adding another.


**Mod load happens on the title screen.** A Blueprint hook (`/Game/...`) cannot
be registered until that class is actually loaded, which does not happen until
the player is in a world — and that can be ten minutes later on a slow load.
A native hook (`/Script/...`) registers immediately and is never affected, which
is why personality enforcement keeps working while nameplates and the radial
menu quietly do not.

Any bounded retry anchored at mod load is therefore measuring the wrong thing.
This has now cost two separate test runs:

- **Nameplates/trust bars** (pass 297): a 30-round window. On 2026-09-11 the
  hook needed round **136**.
- **The radial menu** (pass 301): a 60-round, five-minute window. On the same
  day Dragón's world did not exist until 9.5 minutes in, so it gave up four and
  a half minutes before there was anything to hook, and he could not pet or feed
  anything for the whole session — *"i could no longer interact with the pals,
  no matter how close i got"*.

Both were invisible, because both logged under suppressed tags. Both now retry
at a slow cadence until they succeed, and report under the non-suppressed
`[TAGS]` / `[HOOKS]` prefixes.

**The lesson that generalises:** the first fix was applied to one instance
without checking for siblings, and the sibling broke a run a few days later. If
a bug class is found, grep for the rest of the class before calling it fixed —
`MAX_[A-Z_]*(ROUNDS|ATTEMPTS)` is the search that finds these.

## Lua errors do NOT appear in palbonds-live.log

A Lua runtime error is caught by UE4SS and printed to **its own console window**,
in red, as `Error: [Lua::call_function] lua_pcall returned LUA_ERRRUN => ...`.
It never reaches `palbonds-live.log`, because that file only contains what
`Logger.log` writes — and a function that threw never got to its log line.

This cost a real diagnosis on 2026-09-12: Dragón reported red lines, the mod log
was grepped for `error`/`FAILED`/`nil value`, nothing was found, and he was told
there were no errors. There was one, and it was serious — `close_combat_window`
calling `pal_has_own_fight` before its definition, killing the entire
combat-window close path. **When he reports red console lines, ask for the
console text; do not refute it from the mod log.**

## Diagnostics: the log filter hides more than you expect

`Logger.lua` has `SHOW_DIAGNOSTICS = false` and a `SUPPRESSED_TAGS` list, and
`Logger.log` **silently drops** any message matching it — everything starting
`[DIAG`, plus `[FOLLOW-DIAG]`, `[RADIAL-WATCH]`, `[TRAINER-REASSERT]`,
`[AIM-FREEZE]` and a couple of dozen more. Turning `DEBUG_LOGGING` on does
**not** bring these back; `SHOW_DIAGNOSTICS` is a separate switch.

This cost real time: the intermittent "personality tags missing" bug logged its
own cause on both the success and failure paths, and every one of those lines
was being thrown away before reaching the file, so a working session and a
broken one produced byte-identical logs. **When a log cannot explain something
it clearly should have logged, check this filter before theorising.** Anything
that must survive the filter needs a tag that is not on that list — the tag
bind-hook lines now use `[TAGS]` for exactly this reason.

## Known open defects

0. **Microstutters — FIXED in v1.1.2 (committed to GitHub 2026-09-15; stores
   still serve 1.1.1).** Kept here as the investigation record. Confirmed as
   the mod's doing on 2026-09-15. Reported by Workshop commenter *Goldaer* (2026-09-14, against
   1.1.0): the mod "appears to introduce a lot of microstutters that are
   really noticeable", visible on Steam's performance overlay. Dragón confirms
   he feels it too and had grown used to it.

   **Baseline measurement** (PresentMon, dev install 1.1.1, same spot, standing
   still, no followers, 2 minutes each; captures in `perf-captures/`, analysed
   with `node tools/perf/analyze-presentmon.js`):

   | | PalBonds ON (runA) | PalBonds OFF (runB, UE4SS still loaded) |
   |---|---|---|
   | avg fps | 68.1 | 70.2 |
   | 1% low | **16.2 fps** | 36.1 fps |
   | 0.1% low | **7.9 fps** | 32.2 fps |
   | worst frame | **139 ms** | 41.7 ms |
   | hitch events | 163 (81.6/min) | 87 (43.5/min) |
   | repeating stall series | **8.115s ~119ms (13/15 slots), 2.050s ~48ms (49/58), 3.065s ~48ms (26/39)** | **none** |

   The average barely moves, which is why it is easy to grow used to; the
   lows collapse. Every repeating series disappears with the mod off, and the
   remaining ~87 unpatterned hitches exist in both runs (the game's own). The
   stalls are CPU-side (CPU-busy equals frame time), i.e. game thread. Each
   period equals a mod timer's delay plus its own stall, because the mod's
   timers reschedule after their work: 8.115s = personality scan (8000ms) +
   ~119ms; 2.050s = nameplate sweep (`SCAN_INTERVAL_MS` 2000) + ~48ms; 3.065s =
   every second Trust tick (1500ms). The mapping is by period only — the
   profiler (Next steps #1) is what proves which code each stall is.

   **The 3.065s series is traced in code (Dragón asked why it runs with no
   followers).** `tick_followers` (`Trust.lua`, the 1.5s tick) calls
   `find_player()` on its first lines, BEFORE looping over `State` to see
   whether anything is following. `find_player` caches the player for
   `PLAYER_CACHE_SECONDS = 2.0`; a 2.0s cache on a ~1.53s tick expires on every
   second tick, so a full `FindAllOf("PalPlayerCharacter")` object-array walk
   runs every ~3.07s for the whole session, with or without a single bonded
   Pal. The cache was built for the per-hit damage path (run 37) and does its
   job there; the tick simply pays for it regardless. The same idle-cost shape
   applies to the 2s nameplate sweep and the 8s personality scan, which also
   run whether or not anything needs them.

   **Profiled run C (2026-09-15, 12:46–12:56, profiler ON, dev install).**
   Dragón's timeline, from F3 at 12:47:41: 2 min idle; walking; fast travel +
   mounted; feeding wild Pals via the radial menu; walking until they joined;
   several followers; a fight with followers; closing the game. Summarise
   with `node tools/perf/analyze-profile.js <palbonds-profile.log> --phase
   "HH:MM:SS label" ...`. Key results:
   - **The clock is trustworthy:** os.clock 611.5s vs wall 612s over the
     session. The 2026-09-07 "os.clock is CPU time" note in Combat.lua is
     WRONG for this build; os.clock is wall time at 1ms resolution.
   - **Nearly every stall is a world search** (`FindAllOf` / `FindFirstOf`).
     Hooks and loops are cheap: `SelectResponseBySenses` 0.03ms/call (8718
     calls in 2 min idle = 231ms total), Combat fast loop <1ms/pass,
     `update_trust_bars` 3–20ms, `try_enforce_personality` and per-Pal
     `GetFullName` ~0.
   - **A single search costs ~40ms idle and 55–100ms in play**, growing with
     what is loaded; timer runs containing several reached 246ms.
   - **Frozen time per minute from world searches alone:** idle ~2.9s (~5%),
     fight ~5.6s (~9%), **feeding via the radial menu ~7.9s (~13%)**.
   - **Biggest single offender in active play (Dragón's hunch was right):**
     the radial redirect hook `TryGetSpawnedOtomo` post-callback, 3.2–3.8s per
     minute while feeding / with several followers, driven by
     `FindFirstOf("PalPlayerCharacter")` at `Interaction.lua:2245`, called on
     EVERY hook fire while the 15s radial window is open (~4/s, ~50–60ms each).
     `WBP_PlayerRadialMenu_C:CloseMenu` also stalled up to 187ms.
   - **Steady sources, all session:** nameplate sweep
     `FindAllOf("WBP_PalNPCHPGauge_C")` ~29/min (1.2–1.9s/min); player lookups
     `FindAllOf("PalPlayerCharacter")` ~27/min (1.1–1.9s/min; Trust tick,
     personality scan, and during fights the `PalHate:DamageEvent` hook, one
     61ms); personality scan `FindAllOf("PalCharacter")` 7–13/min;
     `FindAllOf("PalAISensorComponent")` 7–10/min (40–75ms).
   - **Why the sensor index still rebuilds:** `GetOrInitState` →
     `GetPresetClassName` tries `GetComponentByClass` (broken for this
     component), then goes straight to `find_sensor_component_via_index`,
     a world-wide rebuild at most every 5s. It never checks
     `cachedSensorByPalId`, which the `SelectResponseBySenses` hook already
     fills for practically every wild Pal nearby.
   - **Fixes IMPLEMENTED 2026-09-15 (approved by Dragón: "sure go ahead...
     the idea is that we polish it as much as we can"), harness-tested, in
     the dev install, NOT yet measured in game (run D):**
     (a) **`Scripts/PlayerRef.lua`** (new) — the only player lookup. Keeps
     the reference, IsValid on every use, re-searches when invalid, plus a
     **10s safety-net re-search** even while valid (a dead character can
     linger as a valid object after respawn), and waits 2s after a search
     that found nobody. Replaces Trust `find_player`/`find_player_name`,
     Combat `find_player`, Capture's 4 and Interaction's 3 `FindFirstOf`
     player lookups (incl. the radial redirect), and the personality scan's.
     (b) **Nameplates from the hook** (Indicator.lua, "NAMEPLATES FROM THE
     HOOK"): BindFromHandle puts the gauge in `pendingGauges`, every 2s tick
     runs `install_trust_bar` on those with no search, Unbind/invalid drops
     them. The world sweep runs every tick until the hook registers, 5 more
     ticks after, then **every 15 ticks (~30s) as a safety net**.
     Discovered while doing this: the sweep was the ONLY thing that created
     tags; the hook only recorded the Pal handle.
     (c) **Personality scan from the sense hook**: the hook records
     `pawnByPalId` and refreshes `lastSeenAt` (its early return now stores
     the Pal id instead of `true`); `senseHookArmed` is set on registration.
     Armed scans iterate those Pals (skip enforced ones, drop invalid) with no
     search; **every 8th scan (~64s) is the full world search as a safety
     net**; unarmed, every scan is the world search as before.
     (d) **Sensor cache first**: `GetPresetClassName(palActor, palId)` checks
     `cachedSensorByPalId` before `GetComponentByClass`/the index;
     `cache_sensor_for_pal` now caches BEFORE `GetOrInitState` (it was after,
     so every new Pal's first sense rebuilt the index);
     `SENSOR_INDEX_REFRESH_SECONDS` 5 -> 30.
     Tests: `tools/harness/perffixtest.js` (30 checks, both directions — the
     search is gone in the common case AND every fallback still searches),
     verified to fail against two deliberate regressions (cache order
     reverted; palId ignored). `hitcosttest.js` updated to the 10s semantics
     plus an invalid-player re-search check. **Harness limit found:** fengari
     has 32-bit integers, so the real `GetStableId` (`% 0x100000000` mask)
     always returns nil there — tests replace it; no earlier test had ever
     exercised it. All 13 existing suites, harness3 (14 hooks, identical),
     profiletest, syntax and both static checkers pass.
     **RELEASE WARNING (extends the profiler one):** both release trees need
     `Profiler.lua` (switch OFF) AND `PlayerRef.lua`, or the mod fails to
     load. Run C's profile log is archived at
     `perf-captures/runC-palbonds-profile.log`.
     **Run C frame baseline** (whole capture incl. a fast-travel load):
     avg 45.6 fps, 1% low 6.2 fps, 79 hitch events/min.
   - **Run D (2026-09-15 13:35–13:45, first fix round, profiler ON).** Dragón:
     "it felt a lot smoother". No Lua errors, 14 hooks. The frame capture was
     NOT recorded (the in-game F3 never reached PresentMon; no CSV was ever
     created). Profile (`perf-captures/runD-palbonds-profile.log`), per
     minute over the session: radial redirect 37 ms/min (was 3.2–3.8 s);
     player searches 6.2/min (the 10s safety net); nameplate sweeps 3.7/min
     (was ~29); personality world scans 1.3/min (was 7–13); world-search
     freezing ~0.67 s/min total (was 2.9–7.9). Remaining, in order:
     `update_trust_bars` 244 ms/min (138 frames >=8ms, every label
     recomputed every 2s); sensor index still rebuilt ~1.7/min (Pals the
     safety scan found but the hook never reported retried it every scan);
     radial `CloseMenu` 108ms mean / 140 max with no search involved; player
     safety net ~6/min up to 102ms; tags showing "?" longer (tags now wait for
     the hook or the ~64s safety scan); F8 Play 150ms once (controller
     search).
   - **Second fix round IMPLEMENTED 2026-09-15 (Dragón: "go ahead... the
     specifics or the code related things, i will leave that up to you"),
     harness-tested, in the dev install, awaiting run E:**
     1. `update_trust_bars`: bar written only when its ratio changed; label
        Pal id resolved once per actor; label-only tags rebuild text only on
        personality/F9-visibility change or every `LABEL_REFRESH_SECONDS`
        (10s); tags with a bar (bonding) still every tick.
     2. `try_enforce_personality(palActor, palId, cacheOnly)`: the hook-fed
        scan passes `cacheOnly`, so a Pal without a hook-cached sensor never
        falls back to the world-wide index there (the safety scan still can).
     3. Profiler sections inside `closeRadialMenuActionWindow` (pet grant,
        feed dispatch) to name the 108ms in run E.
     4. `PlayerRef` death/world-exit (Dragón's idea): IsDead/IsDying checked
        at most once per second; after a death the body is still returned
        while the world is searched every 2s until a DIFFERENT or living
        character appears; `Combat.ResetForNewWorld` calls
        `PlayerRef.Invalidate()`; safety net 10s -> 60s.
     5. A tag still "?" creates that Pal's personality on the spot
        (`GetOrInitState`, retried at most every `LABEL_STATE_RETRY_SECONDS`
        = 10s per Pal).
     6. `find_player_controller` reads `player.Controller` first; the world
        search is only the fallback.
     Tests: `perffixtest.js` now 42 checks (death/respawn, world reset,
     cache-only scan for a never-sensed Pal added), each new one verified to
     fail against a deliberate regression (cacheOnly removed -> 7 index
     rebuilds; death check disabled -> 4 respawn failures).
     `hitcosttest.js` moved to the 60s safety net. All 13 existing suites,
     harness3 (14 hooks, identical), profiletest, syntax and both static
     checkers pass. **Not yet in-game verified — nothing committed** (Dragón:
     GitHub only once in-game testing confirms the changes work).
     **Untested by the harness (widgets too deep to stub):** fix 1's label
     gating and fix 5's on-the-spot personality creation — watch tags in run E.
   - **Run E (2026-09-15, F3 at 14:35:06, second fix round, profiler ON).**
     Dragón: "felt slightly laggier than the previous one" (run D, which has
     no frame capture). Timeline: 2 min idle; moving + F9 tags on/off; fast
     travel + mount; bonding; new Pal + fight; new Pal + betrayal; fast travel
     + bond + death; respawn (the bonded Pal waited at the respawn spot, then
     died fighting a hostile). No Lua errors, 14 hooks. Captures:
     `perf-captures/runE-fixes2-1.csv` (full session) and `-2.csv` (1.8s,
     from an extra F3 — confirms extra presses create new numbered files,
     never overwrite), profile `perf-captures/runE-palbonds-profile.log`.
     Frame comparison over matching windows (`analyze-presentmon.js --range`):
     | window | 1% low | p99 | hitches/min | mod timer series |
     |---|---|---|---|---|
     | idle A (mod on, pre-fix) | 16.2 | 41.6ms | 81.6 | 2.05s/3.07s/8.1s |
     | idle B (mod OFF) | 36.1 | 26.3ms | 43.5 | none |
     | idle C (pre-fix, profiled) | 13.4 | 54.7ms | 117 | 2.05s/8.1s |
     | **idle E** | **33.2** | **25.4ms** | **39.0** | none |
     | bonding C 240-300s | 4.1 | 110ms | 91 | several |
     | **bonding E 240-300s** | **13.3** | **39ms** | **13** | none |
     | fighting C 420-480s | 5.7 | 111ms | 55 | 2.1s/8.2s |
     | **fighting E 300-360s** | **13.9** | **48ms** | **19** | none |
     **Idle with the mod is now within noise of the mod turned off.** The
     median frame time in E's play windows was HIGHER than C's (bonding 24.5
     vs 21.0ms) — the game itself was working harder in those areas, which is
     the likeliest thing felt as "laggier"; the mod's stutter dropped.
     Profile checks: player searches once a minute in play; death noticed
     ~14:43:37, respawn searches every 2-3s stopped ~14:43:57 when the new
     character was found; searches every 3s after 14:44:24 = the game closing.
     **Remaining mod stalls, biggest first (next candidates):**
     1. The ~64s personality SAFETY scan: 115-155ms in ONE frame — its
        `FindAllOf("PalCharacter")` (60-80ms) plus a sensor-index rebuild
        (55-70ms) via `GetOrInitState` for Pals with no cached sensor.
     2. Each feed: `do_real_wild_feed_via_worker_menu` 100-146ms (the whole
        radial CloseMenu cost; now named by the profiler section).
     3. Fix 5 (on-the-spot personality for "?" tags) hit the index twice,
        60-80ms each.
     4. Nameplate safety sweep ~every 30s, up to 95ms; player safety search
        once a minute, 40-96ms.
   - PresentMon capture `perf-captures/runC-profiled-1.csv` was still locked
     by a running elevated PresentMon at the end of the session (the game
     exited but `--terminate_on_proc_exit` did not close it). Stopping it
     needs an elevated command, i.e. a UAC prompt for Dragón.
1. **Bonded Pals despawn when the player travels far from where they were
   bonded.** Investigated exhaustively on 2026-09-14 and then deliberately
   **PARKED as a known limitation** by Dragón. The mechanism is now fully
   understood and the dead ends are recorded — read
   "KNOWN LIMITATION: bonded wild Pals despawn when you travel far" below
   **before** touching this again, and do not re-run the experiments listed
   there as dead ends.
2. **Singleplayer only.** Not designed for co-op or dedicated servers; see
   "Multiplayer support" under Pending. Official servers do not allow mods.
3. **`LoopAsync` fallbacks still present** in `Trust.lua` and `Indicator.lua`,
   dead code that would only run in the emergency it is unsafe for.
4. **World-change references never cleared:** `Indicator.trackedBars` holds
   actors across a world change; `Interaction` writes `SpawnedOtomo` into a
   GameInstance-lived widget and never clears it, same for
   `pendingWildFeedTarget`.
5. **`FindFirstOf` exposure** (UE4SS issue #1328): `Capture.lua` still has 4
   and `Interaction.lua` 3 `FindFirstOf("PalPlayerCharacter")` calls. None is
   per hit.
6. **`find_targeted_pal` costs 42-47ms per scan** while the radial menu is open.
7. **No settings screen.** The F9 and F10 toggles are session-only.
8. **Friendly fire** is contained, not prevented (see the combat section).
9. **Hotkeys fire while typing in chat** — declined by Dragón 2026-09-14 as
   not worth fixing (see Pending).

---

## Pending, deliberately deferred

**New player reports (2026-09-19, after 1.1.5 shipped — not yet triaged by Dragón):**
- **CRASH AROUND THE JOIN, two independent reports.** Esaeon (Proton,
  GitHub issue #1, log saved at `docs/bug-reports/esaeon-issue1-palbonds-live.log`,
  1.1.4, DEBUG on, Pet/Feed only — no F8) ends EXACTLY at the join: join
  toast shown, StopFollowing, ForgetBonding at 19:15:17, then nothing. Not yet
  confirmed with him that the game crashed at that moment. His Nexus comment:
  also crashes "after a while of simply running around", most reliably after
  Pet/Feed; many other mods (PalSchema + 10 schema mods, LogicMods/~mods paks).
  Swordfish (Steam, no other mods): crashed "right when the trust bar went full"
  while spamming Pet on hostile Pals; rare. Lead, unverified: after a join the
  wild actor is destroyed, but only Trust (ForgetBonding) and Combat
  (StopFollowing) drop it; Indicator and Personality still hold references to
  it (a one-actor version of the world-change teardown fixed in 1.1.3/1.1.4).
  A stale reference touched after garbage collection could crash at a random
  later moment, which would also fit "while running around".
- **Feed on a charging Pal (Goldaer, Reindrix):** the Pal ran at him, hit him
  (damage), ran off without eating, and the PLAYER stayed stuck in the
  clapping/waiting animation (could move/jump inside it) until he fed again
  up close.
- **Boss joins don't count (Goldaer):** bonding with an overworld boss did not
  count it as defeated or captured (boss defeat record / Paldeck).
- **Alpha Mammorest falls through the floor after petting** — now a second
  report (Swordfish, twice, uneven terrain). Earlier judged base-game, but
  petting wild Pals only exists through our mod.
- **Feature request (Swordfish):** a way to release Pals back into the wild.
- **Icon (Meail):** use the meme image as the Workshop icon. Dragón's call.
- **DRAGÓN'S TRIAGE (2026-09-19):**
  - Crash: do NOT treat the two reports as one bug yet. Swordfish said it was
    rare and hasn't reported again (likely an older version). Esaeon may be a
    conflict with one of his many mods. Next step is information: ask Esaeon to
    confirm the timing and to run 1.1.5 with ONLY PalBonds active (rules out
    Proton vs mod conflict), with both logs. Asked on Nexus 2026-09-19.
    GitHub issue #1: answer (and close) only once it's fixed and finished,
    not before (Dragón).
  - Feed on an attacking Pal: his read is that the Pal's attack lands and
    staggers the player, interrupting the interaction but not the player's
    animation. Fix: stop the player's animation (or reject the interaction)
    when it fails, OR interrupt the Pal so the interaction takes priority. TO DO.
  - Boss joins must count as defeated/captured: find how the game records it.
    TO DO.
  - Mammorest under the floor: base-game limitation, NOT ours. Lifting the Pal
    would only cover uneven ground, not cliffs or walls. Reply as usual.
  - Releasing Pals: backlog, after the settings screen and multiplayer.
  - **Feed fix direction (Dragón, 2026-09-19):** release the player's
    animation when the interaction fails, and a failed feed should cost
    nothing ("stop the interaction entirely"). Finding: for wild Pals the
    GAME never takes the food; our RequestUseToCharacter post-hook takes it
    and grants the trust at the moment the food is PICKED, before the Pal
    walks over. So we can defer both until the Pal actually eats.
  - **Instrumentation for one combined test run (2026-09-19):**
    `Scripts/DevWatch.lua` (TEMPORARY, remove before any release, plus the
    call sites marked "DevWatch" in Interaction, Capture, main and
    `Logger.DebugEnabled`). [PAIR-WATCH] logs player / Pal AI / Pal action
    changes for 15 s after each Pet/Feed, plus the moment the food is taken.
    [BOSS-WATCH] hooks `APalNPCSpawnerBase:ProcessBossDefeatInfo_ServerInternal`
    (header-dump candidate for the boss-defeat record) and lists spawners near
    every joining Pal. [RECORD-WATCH] diffs the player's UPalPlayerRecordData
    (boss defeats, NormalBossDefeatFlag keys, capture counts) every 15 s and
    3 s after a join. 18 hooks with it. For the run, the game's settings file
    has **Pet = 20000** (instant join for the boss): SET IT BACK TO 50 after.
  - **Run 1 results (2026-09-19, 14:56-15:10):**
    - Feed sequence (7 feeds): player `BP_ActionPairStandby_FeedItem` (waiting
      pose) while Pal AI `BP_AIActionPairCall_FeedItem` walks over; food taken
      (RequestUseToCharacter) at ARRIVAL, when the player switches to
      `BP_ActionPairBehavior_FeedItem`; both end together ~5.5 s later. So an
      interrupted approach never costs food (my earlier "taken when picked"
      was wrong). A Lamball that rolled into Dragón and ragdolled left him in
      the waiting pose 6 s, then the game released him itself; no food taken.
      Dragón could NOT reproduce the stuck pose (tried hostile Pals, Reindrix,
      hitting them himself): rarer than thought.
    - Bosses: killing a Menasting fired
      `ProcessBossDefeatInfo_ServerInternal(boss, "sakura_red_B_BOSS")` and the
      record gained that NormalBossDefeatFlag (map: defeated). A PETTED Lyleen
      fired the SAME function during our capture ("sakura_purple_D_LilyQueen")
      but NO flag was written (map: undefeated); it did count as a capture
      (LilyQueen 5 -> 6). Difference: nobody attacked the Lyleen.
    - Dragón: the first defeat gives a key item; a befriended boss must not
      get it twice.
  - **Built after run 1 (tests pass, deployed):**
    - Stuck-pose watchdog (Interaction, `[PAIR-RELEASE]`): after every wild
      Pet/Feed, if the player is in a `BP_ActionPair*` pose and the Pal is out
      of its `AIActionPairCall` for 1.5 s (or gone), or waiting > 12 s /
      eating > 15 s, the pose is cancelled (CancelAction, as for Play's cheer).
      Nothing else is ever cancelled. Test: `pairwatchtest.js` A-H.
    - Boss credit (Capture, `[BOSS-CREDIT]`): for a `_BOSS/_GYM/_RAID` class,
      right before the capture the player is written in as the boss's last
      attacker (DamageReactionComponent.LastAttackerInstanceID from the
      player's IndividualHandle.ID, and LastDeadInfo.LastAttacker), so the
      game's own defeat function credits the player and handles first-time
      rewards itself. UNVERIFIED: run 2 decides. Test: `pairwatchtest.js` I.
  - **Run 2 results (2026-09-19, 15:27-15:34):** the boss credit RAN (both
    fields written and read back as the player) and ProcessBossDefeatInfo
    fired for the right spawner (Lyleen Noct, "sakura_purple_D_LilyQueen_Dark"),
    but still NO defeat flag: the last attacker is NOT the lever. Map:
    undefeated. A petted, already-beaten Mammorest gave no second reward (but
    nothing is written for bosses at all yet, so that proves nothing). Feeds and
    pets all played out normally, no [PAIR-RELEASE] (the watchdog never cut a
    normal one). Pet follows the same pattern: `BP_ActionPairStandby_Petting`
    -> `BP_ActionPairBehavior_Petting`, Pal AI `BP_AIActionPairCall_Petting`.
    The stuck pose still didn't happen.
  - Next: DevWatch now also hooks 9 record-writing candidates
    (PalPlayerRecordDataUtility SetRecordData_*, CaptureJudgeObject
    OnCaptureSuccess, the boss-reward client RPCs, OnDefeatCharacter delegate)
    to see who writes the flag on a REAL defeat or sphere capture. The
    BOSS-CREDIT code is kept for now but is disproven: delete it once the real
    lever is found.
  - **Run 3 (2026-09-19, 15:43-15:46):** Dragón confirmed a sphere-caught boss
    counts as defeated in the base game, then caught an undefeated Grintale
    (NaughtyCat, "81_1_grass_FBOSS_18"). ONLY ProcessBossDefeatInfo fired (none
    of the 7 hookable candidates; the two reward client RPCs couldn't be
    hooked), and the record gained the flag (defeats 8 -> 9). So that function
    decides alone, from the boss's state.
  - **Built after run 3 (tests pass, deployed):** the last-attacker write is
    DELETED (disproven). Replaced by a hate push: for a boss only, right before
    the capture, `Controller:GetHateSystem():ChangeHate(player, 1000)`, so the
    player is in the boss's UPalHate.HateMap the way any fight or sphere catch
    leaves them. Positive ChangeHate is proven in this build (combat assist);
    subtraction is not. `[BOSS-CREDIT]` logs the most-hated before/after.
    UNVERIFIED: run 4 decides.
  - **Run 4 (2026-09-19, 15:52-15:54): hate DISPROVEN too.** Petted an
    undefeated Grizzbolt-line alpha (GrassPanda_Electric,
    "81_1_grass_FBOSS_26"): the push worked (most hated nil -> the player) and
    ProcessBossDefeatInfo fired for the right spawner, still NO flag (captures
    +1, paldeck +1). The hate push is DELETED (Capture has no boss-credit code
    now; pairwatchtest section I removed with it).
  - Ruled out as the lever: last attacker (both fields), the hate table. Not
    visible from Lua: what ProcessBossDefeatInfo checks internally. Unhooked
    lead: `APalCharacter:OnCaptured(SelfCharacter, Attacker)` delegate (what a
    sphere catch broadcasts vs what PalCaptureSuccess broadcasts). Every
    experiment costs Dragón an UNDEFEATED alpha (they respawn only slowly), so
    ask before the next one. Dragón keeps one already-beaten alpha for the
    later "no second reward" check.
  - Dragón: "lets do more runs" (waiting for respawns is fine). Run 5 setup:
    DevWatch `[BOSS-STATE]` snapshot of the boss AT ProcessBossDefeatInfo (both
    cases) and "before our capture" (joins): battle mode, captured-processing,
    dead/dying/live, otomo flags, owner UId, HP, last attacker, dead type,
    most hated. Hooks on `PalCharacter:OnCaptured`, its delegate, and
    `OnDeadCharacter` log who the capture names as attacker. Protocol: one
    sphere catch AND one petted join of undefeated alphas, then diff.
  - **Run 5 (2026-09-19, 16:05-16:08):** sphere-caught Dumud (LazyCatfish,
    "81_1_grass_FBOSS_27", flag written) vs petted Nitewing (HawkBird,
    "81_1_grass_FBOSS_22", no flag). Boss state AT ProcessBossDefeatInfo was
    identical (no battle mode, not dead/dying, no owner yet, no last attacker)
    EXCEPT `IsCapturedProcessing` true (sphere) vs false (ours), and a most-hated
    target (sphere only; hate alone already disproven). OnCaptured and its
    delegate did not fire (native). ALSO: Dragón got stuck in the PET pose on
    the Nitewing: it accepted the pet mid-attack 6-7 m away, the game ended the
    player's pair action at +2.7 s (the Pal went back to attacking), but the
    POSE ANIMATION kept playing until he petted his own Pal. The watchdog only
    looks at the action, so it saw nothing. And the pet was PAID at 0.26 s
    (the Pal's pair call counts as accepting, not arriving): 20000 points, so the
    boss joined without ever being petted.
  - **Built after run 5 (tests pass, deployed):**
    - Boss: `Capture.MarkBossAsBeingCaptured`: for a boss only,
      `CharacterParameterComponent:SetIsCapturedProcessing(true)` (field write as
      fallback) right before the capture, as a sphere does. UNVERIFIED: run 6.
    - Pose: when a pair ends before the shared animation (failed), or the
      watchdog releases it, any montage still on the player is stopped
      (`Mesh:GetAnimInstance():GetCurrentActiveMontage()` + `Montage_Stop(0.25)`),
      logging its name. A pair that ended normally is never touched.
    - Pet pays only once the player is in `BP_ActionPairBehavior_*` (really
      petting); if the player's action is unreadable, the old rule applies.
      Tests: pairwatchtest I-L, bosstest C5.
  - **Run 6 (2026-09-19, 16:25-16:32):**
    - Boss (Foxparks Cryst, Kitsunebi_Ice, "81_1_grass_FBOSS_15"): at the
      defeat routine it had IsCapturedProcessing=true AND the player as most
      hated, i.e. both run-5 differences matched the sphere case, and STILL no
      flag. The boss's state is NOT the lever: the defeat record is written by
      the sphere's (and the kill's) own native code, which Lua can't reach or
      see. The captured-flag code is DELETED. Petted-but-unflagged bosses in
      Dragón's save: sakura_purple_D_LilyQueen, sakura_purple_D_LilyQueen_Dark,
      81_1_grass_FBOSS_26, 81_1_grass_FBOSS_22, 81_1_grass_FBOSS_15.
      Remaining route (needs Dragón's decision): write the record ourselves
      and handle the first-defeat reward ourselves.
    - Stuck pet, reproduced on a Nitewing: the release fired 2 s in and
      stopped `AM_Player_Female_Petting_Middle_Beckon` (the waiting wave, used
      by Pet AND Feed), but Dragón stayed stuck until he rolled. It also once
      stopped `AM_Player_Female_hit`. The pet check correctly refused to pay
      ("accepted the pet but never reached you").
  - **Built after run 6 (tests pass, deployed):** the release only touches a
    waiting pose (Petting/Feed/Beckon in the montage name), stops it with no
    blend, re-checks 0.4 s later, and if it is still playing and the player has
    no action, gives the player a fresh action the way a roll does (the Play
    cheer emote via ActionComponent:PlayAction, cancelled 0.15 s later), logging
    every step. pairwatchtest L-M.
  - **BOSS DEFEAT: STILL OPEN (Dragón, 2026-09-19).** First he said "ideally
    we would let the game itself mark them as defeated and give the items, if
    we do it ourselves, there are too many risks"; I wrongly recorded that as a
    known limitation and he corrected it: "i said 'ideally' not that we flag
    it as a known limitation, if we have to do it manually and give the item
    and mark it as defeated ourselves then we find how to - but IDEALLY we let
    the game itself do it - dont mark stuff as known limitations unless i
    state it myself". So: the game's route stays preferred; if it cannot be
    reached, write the record AND give the first-defeat rewards ourselves.
    What a first kill gives (Dragón, Elphidran, 2026-09-19): technology
    points, a "first boss kill" toast in the centre of the screen, and a
    bounty token. Boss instrumentation was removed from DevWatch (re-add what
    the next step needs); Pet restored to 50 in the game's settings file.
  - **Run 7 (2026-09-19, 17:09-17:14):** a Nitewing pet: the release stopped
    the pose and it was gone 0.4 s later (worked). A Nitewing FEED where the
    Pal HIT him: the top animation was `AM_Player_Female_hit`, left alone
    correctly, but the release then gave up and the waiting pose came back
    underneath: stuck until he rolled. Fixed: another animation on top is
    waited out (re-checked every 0.4 s, up to 6 checks), then the pose is
    stopped; a fresh action (cheer start+cancel) if the stop doesn't hold.
    pairwatchtest N. Dragón also petted an undefeated alpha (Petallia,
    VioletFairy, "81_1_forest_FBOSS_1"): captured, not defeated, as expected.
  - **Esaeon's crash, new evidence (2026-09-19, GitHub #1 comment + Nexus):**
    1.1.5, EVERY other mod disabled (his UE4SS.log: PalSchema disabled, only
    UE4SS's default Lua mods). Crash 5-15 s after a Lamball joined;
    CrashContext: EXCEPTION_ACCESS_VIOLATION reading 0x0, every frame in UE4SS
    (+ VCRUNTIME140 memcpy). palbonds-live.log's last line: [PRESET-SLOTS]
    Warlike, 10 s after the join ([ENFORCE] lines are filtered, so what ran
    after it is invisible). His UE4SS.log is in UTC ("local disabled due to
    wine") and not flushed per line, so its tail is stale. His Claude's
    analysis: apply_forced_preset never validated the sensor. Files saved in
    `docs/bug-reports/esaeon-0919-*`.
  - **Built for it (tests pass, deployed, NOT yet verified by Esaeon):**
    - Join cleanup: `Personality.ForgetJoinedPal(palId, actorKey)` (state,
      sensor caches, pawn, handled addresses, sensor index),
      `Indicator.ForgetJoinedPal(palId, actorAddr)` (tracked bars, boss
      entries, pending boss gauges; entries now store `actorAddr`), and
      `Interaction.ForgetJoinedPal(actorAddr)` (radial-menu targets, pending
      feed, the pose watchdog), all called by Capture after ForgetBonding with
      the id/address read BEFORE the capture. `[JOIN-CLEANUP]` logs the count.
      Before this, Personality kept the dead wild Pal up to 10 min.
    - Esaeon's suggestion: `sensor_alive(sensor)` checked at the top of
      apply_forced_preset, and right before BOTH `sensor.AIResponsePreset =
      fresh` writes (ApplyCompanionPreset too).
    - Test: `jointest.js` J1-J5 (22 suites now).
  - **Esaeon test build (Dragón's idea, 2026-09-19):** give him the fix early
    through GitHub instead of making him wait for 1.1.6, so a miss costs no
    release. Built locally, NOT pushed yet (ask first):
    `release/test-build/PalBonds-v1.1.6-test1.zip` = current `mod/` minus
    DevWatch.lua (its call sites are pcall-guarded no-ops), DEBUG_LOGGING ON so
    his log is written without edits, 1.1.5 README. 17 hooks, all suites pass
    against it. `[ENFORCE]` is no longer filtered from the log (it is what ran
    after his last visible line). Plan: commit to a branch (not master, which
    is the 1.1.5 stable), GitHub pre-release `v1.1.6-test1` with the zip.
  - Boss reward popup: `UPalNetworkPlayerComponent:ShowBossDefeatRewardUI_ToClient
    (FPalUIBossDefeatRewardDisplayData{TechnologyPoint, DefeatCharacterID},
    AfterTeleport, DelayTime)` and `ShowDefeatBossBonusExpReward_ToClient(int)`:
    run 3 hooked them on the wrong class (PalPlayerController), which is why
    they "could not hook". Client RPCs go through ProcessEvent, so hooked on
    the right class they should show what a real first kill hands out. The
    popup is the RESULT of the server writing the record, not its cause.
  - Dragón finished all 16 translated Workshop descriptions (Russian and
    Thai were rewritten shorter: Steam's character limit).
  - Icon: no (the meme isn't square).

**New player reports (Nexus posts, read 2026-09-18):**
- **Esae0n (18 Sep):** plays through **Proton** (Linux / Steam Deck
  compatibility layer). Taming works, but the game crashes *every time*
  immediately after a Pal joins. Possibly the keybind-thread bug fixed in pass
  333 — a join destroys the wild actor and builds the party one, a small
  version of the world-change teardown — but only if they used F8 Play. If
  they used only Pet/Feed, it is something else and Proton is a real suspect.
  Dragón was given a reply draft asking which interactions they used and for
  their UE4SS.log. Ask them to confirm once 1.1.4 is out.
- **Warframe666 (17 Sep):** the alpha **Mammorest** in the starting area
  sometimes **falls through the floor after being petted**. New, not
  investigated.
- Design feedback worth keeping (ralanost, Warframe666, 17 Sep): bonding feels
  like waiting on cooldowns; no indicator for when Pet/Feed is available again;
  ideas — favourite food, bonding through fighting together, no distance limit
  so you can bond while doing other things. Dragón has not ruled on any of it.

**1.1.4 RELEASED (2026-09-18) — Nexus, Steam Workshop (change note live,
`last_published_version` 1.1.4) and GitHub (`8846dca`).** Dragón smoke-tested
the exact release files locally AND the Workshop copy before uploading. Still
open from this release: the Proton player's reply (Dragón posted it), the
Nexus/Workshop description line about forgiveness — **Dragón: not needed**, "too
small of an addition and one that should've been there from earlier, since
that's what 'friendly' would make you think" — and the disabled-old-mechanisms
cleanup (next update).
- **Mod-compatibility questions (CS-Eden on Steam asked about "Random Sized Pals",
  2026-09-18):** Dragón does not test other mods. Answer from what we know
  overlaps. Aiming uses `GetScaledCapsuleRadius/HalfHeight`, so resized Pals are
  accounted for; the only foreseeable issue is the known small interaction
  area on very large Pals. Say "should work, untested, tell us", and never
  claim compatibility outright.
  - **Random Sized Pals (makkhan, Workshop 3789632682) — code read 2026-09-18,
    compatible.** It has one hook,
    `PalCharacterParameterComponent:OnInitializedCharacter`, and two frames
    later (game thread, `ExecuteInGameThreadAfterFrames`) it changes the
    MESH's `DefaultScale3D`/`RelativeScale3D` plus
    `static.MeshCapsuleHalfHeight/Radius`, keyed per individual ID. It skips
    bosses, and has no keybinds and no AI or trust changes. It does NOT resize
    the root collision capsule our aim reads, so an enlarged Pal keeps its normal
    interaction area inside a bigger model: aim at the middle of the body.
    PalBonds never hooks spawning (personalities roll when a Pal is first
    noticed) and writes the sensor's preset, which is a different component.
    Dragón subscribed only to let Claude read it; it is not enabled.
  - Side note for our own code: this UE4SS build has
    `ExecuteInGameThreadAfterFrames`.
- Dragón: "ship it without logs nor spies nor anything that's development
  related — just the fixes and the new things you added, no test codes nor
  functions that didn't work". So, removed from `mod/` itself (source =
  shipped): the Profiler (Profiler.lua, main.lua wiring and every
  `Prof.start/stop`), HookConfig.lua and every `hooks_enabled` gate, and the
  [WON-OVER-SPY], [LEASH-SPY] and [PLAYER-SPY] blocks (plus
  `Personality.DescribeFight`/`fight_snapshot`, which only served them).
  profiletest.js was deleted with the Profiler. `tools/dev-instruments/` keeps
  HookConfig.lua (it was never committed); the rest is in git at `bd8e0ca`.
- `release/PalBonds-v1.1.4.zip` (12 files: LICENSE, README.txt, enabled.txt,
  9 scripts) plus both release trees are byte-identical to `mod/`, with
  DEBUG_LOGGING false everywhere and no dev instrument, checked by grep.
  Info.json is 1.1.4. The 1.1.3 zip was deleted, as with previous releases.
- README.txt: forgiveness is described; "a BONDED Pal that loses all its trust
  flees for good" (it used to say any Pal); the rule for hits below 50%; and
  the bug-report log path fixed to `Palworld/Pal/Binaries/Win64/palbonds-live.log`
  (it wrongly said "the mod's folder").
- The game's dev copy now holds the EXACT release scripts (logging off) for the
  smoke run.
- **Nexus: LIVE** (2026-09-18, 4:01PM page time): version 1.1.4, file
  "PalBonds V1.1.4", 271 KB. Dragón's own changelog is five one-liners.
- **Workshop: files prepared** in both copies: the upload folder
  (`steamapps/workshop/content/1623730/3797816321/`, 9 scripts, Info.json 1.1.4
  bumped in place with its BOM kept, `.workshop.json` untouched) and the game's
  NativeMods copy. Both are byte-identical to `release/workshop`, and Profiler.lua
  is gone from both. The local dev install was disabled for Dragón's Workshop
  smoke test and is **ENABLED again (2026-09-18, after the release)**: Dragón
  unticked the Workshop mods (no `ActiveModList`), and `dwmapi.dll` and
  `enabled.txt` are back. Development mode (Dragón, 2026-09-18): DEBUG_LOGGING is
  **true** in both `mod/` and the game copy, otherwise identical to 1.1.4. Set it
  back to false before the next release. Next work: the own-points rework.
- **Workshop pre-upload test: VALID, confirmed 2026-09-18.** Dragón enabled the
  Workshop mods and played; the pals stopped attacking at 20%. Afterwards:
  - Both copies were still byte-identical to 1.1.4, and Steam did NOT revert the
    upload folder to the published 1.1.3.
  - The game's NativeMods copy had a NEW timestamp (16:32, the moment he
    enabled the mods), while the upload folder kept mine (16:25). **So Palworld's
    mod manager re-copies from the Workshop content folder when mods are
    enabled.** Editing the upload folder is therefore enough to test before
    uploading. This refines the 2026-09-14 note that the copy is "written once
    and never re-synced": it isn't re-synced while the mods stay enabled, but
    enabling them copies it again.
  - The UE4SS.log proves the 1.1.4 code ran: 17 hooks, including the ESC-menu
    quit hooks that only exist in 1.1.4, and no errors.
- Still to do: the Workshop upload (Dragón, via the Mod Uploader), then GitHub, and fix the
  README.md known-issues entry. Also ask whether the Nexus/Workshop
  descriptions should mention forgiveness.
- **Next update's cleanup, not done now to keep the verified build unchanged:**
  old disabled mechanisms still sit in the code behind false flags (e.g. the
  "real-Otomo-composite" and "move-order nudge" paths in Combat). Audit and
  delete them.

**1.1.4 TEST RUN (2026-09-18, 15:10–15:25): PASSED.** Dragón: "everything
played nicely, game didn't crash either — pals actually forgive and can attack
back if hit again". Log:
- 7 Pals crossed 20% (Chikipi ×3, Samurai dog, FlowerDoll, two DreamDemons;
  rolled escape/normal/friendly/warlike_anyway/notinterested). 6 were released
  after about 3.1 s "NO LONGER angry"; the 7th was hit during its calm-down.
- **The "follows ITSELF" loose end is closed:** in the 20 s after release, no
  Pal ever targeted the player (`hateTarget=none` on every tick). Their actions
  went from finishing the pet/feed, to `BP_AIAction_FriendlyLookat_C` (the
  game's own "looks at you" idle), to `BP_AIAction_WildLife_C` (normal
  wandering). None was stuck in a follow action.
- 2 unbonded hits, both handled as specified: one after forgiveness (a Chikipi
  rolled Curious, reverted to 'friendly' = its original), and one during the
  calm-down (DreamDemon: "follow stopped: hit by the player during its
  calm-down", reverted to warlike_anyway with its own preset back). No
  betrayal, no errors, nothing FAILED.
- The quit hooks and world reset worked on two consecutive quits.
- Cheer: logged "call ok"; visual confirmation still pending.

**1.1.4 BUILD STATUS (2026-09-18):** the forgiveness rules below are
implemented in `mod/` and deployed to the game's dev copy for Dragón's test run.
All 17 harness suites pass; bosstest R1–R4, U1–U5 and G cover the rules, and
they fail against 1.1.3.
- Personality: `FRIENDLY_BRIEF_FOLLOW` and `legacy_friendly_reset` are GONE —
  the calm-down is the behaviour. `MaybeBecomeFriendlyByBar` saves
  `state.preForgive` (disposition, rolledTier, presetClassName) before
  `become_friendly_wild` overwrites rolledTier; `Personality.RevertForgiveness`
  restores the tag and writes back the rolled tier's donor preset (or the
  species preset for a Normal roll), re-sensing without a cancel. It consumes
  preForgive, and the `becameFriendlyByBar` latch is never cleared, which is
  what makes it one forgiveness per Pal.
- Trust: `on_unbonded_pal_hit_by_player` — reached from `OnFollowerDamaged` for
  a PLAYER hit on a Pal that is not following, or is in its calm-down. It ends
  the calm-down (clearing the `briefFollow` token first, so the release never
  writes Friendly), empties the bar, and calls RevertForgiveness. It has a 1 s
  dedupe, because both damage hooks report every hit.
- `Personality.WON_OVER_SPY` (ships false; TRUE in the game copy only) turns on
  the post-release watch without the rest of the diagnostics. Use it to see
  what a Pal does after the "follows ITSELF" release.
- The HookConfig BISECT/EMOTE_ONLY switches are removed. The hook GROUPS stay,
  all true.
- The cheer now goes through `ActionComponent:PlayAction` (logged "call ok"
  live). **Dragón still has to confirm his character visibly cheers.**

**Dragón's rulings, 2026-09-18 — BONDING AND BETRAYAL (read before touching either):**
- **"Bonding is a status that starts or should start at 50% friendship."**
  Nothing before 50% is a bond. Any comment or note saying "the bond starts at
  the first pet" is WRONG. Claude invented it from a misread report, and the
  pass-246/251 comments in Trust.lua say it; correct them when that code is
  next touched.
- His Gumoss report ("I could hit a partially-bonded Gumoss over and over with
  no penalty") meant **the Gumoss never attacked him back**. It did not mean it
  should have been punished.
- **Below 50%:** hitting a Pal is an ordinary fight. It defends itself from the
  player normally. No betrayal and no scarred status, because there is no bond
  yet.
- **What the code actually does (checked 2026-09-18):** `Trust.OnFollowerDamaged`
  exits unless `st.isFollowing`, so below 50% the penalty never ran. The rule is
  broken in exactly one place: **the 20% brief follow**, which sets
  `isFollowing`. A hit during the calm-down costs half the bar, which at 20–49%
  empties it, so it is full betrayal and the Pal is scarred. The companion
  preset also stops the Pal defending itself during those seconds.
- 1.1.4 = the crash fix plus the POLISHED 20% brief follow, shipped together.
  Wider self-defence reach is NOT in 1.1.4 (too many variables).
- The Mammorest falling through the floor is the base game (Pals align to the
  player's facing axis on uneven terrain). Not ours.
- The Proton reply goes out after 1.1.4 ships. No Steam-vs-Nexus recommendation:
  untested, and a second UE4SS install next to the first crashes the game.
- Dragón: **ask about doubts, don't advance on interpretations.**
- **The 20% calm-down, his full spec (2026-09-18):**
  1. A hit during the calm-down: the Pal reacts however its species normally
     would (some fight, some flee, e.g. Lifmunk). No forced "fight back".
  2. **A player hit below 50% drops the bar to 0.** Player hits only: Pal-vs-Pal
     damage never costs trust (his earlier ruling, quoted in Trust.lua). No
     betrayal and no scarred status, because there is no bond. Costs nothing
     measurable: the hit detection already runs for betrayal.
  3. The calm-down happens for EVERY Pal crossing 20%, not only hostile ones.
  4. After forgiving, the Pal acts completely normally, including getting angry
     again if hit or if a Pal of its species pulls it in. "We just need to
     trigger that brief forgiveness."
  5. It still defends its own kind. Don't interfere with an unbonded Pal beyond
     the forgiveness moment itself.
  6. **One forgiveness per Pal.** After that it is the player's carelessness —
     "we can't let them abuse the poor pals".
  7. When the bar drops to 0, the Pal goes back to its ORIGINAL rolled
     personality: tag AND AI preset (confirmed 2026-09-18). A Hostile Pal
     reads Hostile again, which he agrees is correct because it will attack.
  8. **Crossing 20% a second time does nothing at all:** no calm-down, no
     Friendly switch; it keeps its original personality. Bonding at 50% still
     works. His reason: "most pals will probably not survive too many hits from
     the player, so if we continue making them forgive or act differently, the
     pals will end up dying without having a chance to defend themselves with
     our meddling."

**Dragón's rulings, 2026-09-17 (start of the post-1.1.3 session):**
- **The world-change crash is BACK, reproducible, and now fixed in `mod/`
  (pass 328) — awaiting Dragón's live run.** Recipe he confirmed twice:
  interact with a wild Pal, have NOTHING following you, quit to the title,
  load a world -> `EXCEPTION_ACCESS_VIOLATION 0x338`. His 16:52-16:57 log has
  no `[WORLD-RESET]` line at all, which is the whole bug in one line.
  - **Cause:** the fast loop's world-change check sat BELOW
    `if next(BondingState) == nil then return end`, so with nothing bonded the
    loop returned before it ever looked at the player. No reset ran, PlayerRef
    kept the old world's character, and Indicator/Personality/Interaction had
    never been reset by anything. The 20% brief follow makes this easy to hit:
    it puts a Pal on the follower list and then takes it off, so a run ends
    with the tables empty and plenty still cached.
  - **Fix:** `world_change_watch()` above that early-out, timed off `os.clock`
    (1 s while a world is up, 2 s latched at the title, 0.2 s right after a
    quit is asked for) because the loop itself runs at 100 ms with a follower
    and 1000 ms idle — a pass count would have meant 10 s in exactly the idle
    state the crash happens in. It goes straight to `PlayerRef.Get()`: asking
    Combat's own `lastKnownPlayerActor:IsValid()` first reintroduced the 1.1.2
    bug inside the fix (caught by harness section D on its first run, not in
    game). A latch (`worldResetLatched`) makes the reset run exactly once per
    world change, and both older reset branches now share it instead of being
    gated on holding followers.
  - `Indicator.ResetForNewWorld`, `Personality.ResetForNewWorld` and
    `Interaction.ResetForNewWorld` are new and called from
    `Combat.ResetForNewWorld` (each in its own `safe_call`). Interaction
    deliberately keeps `cachedWorkerMenuParameter` (pass 285) and Personality
    keeps `presetCDOCache`.
  - **The game's own quit event, found in the object dump:**
    `WBP_MenuESC_C:ConfirmReturnTitle` and `:OnReturn2Title`, hooked with
    RegisterHook (retries 30 rounds, 2 s apart, like the nameplate hooks).
    They drop NOTHING — semantics unknown, and dropping state when a confirm
    box merely opens would break a bond the player then keeps. They call
    `Combat.ExpectWorldChange`, which tightens the watch to 0.2 s and puts
    `PlayerRef` into per-call engine liveness checks for 20 s
    (`PlayerRef.ExpectWorldChange`).
  - Hook count is now **17** (was 15); profiletest, harness3's README line and
    worldchangetest sections D/E cover all of this. The new checks fail on
    `release/PalBonds/Scripts` (1.1.3) as they should.
  - If this holds live, it ships as **1.1.4** with both feature switches off.
- **Second live run (17:45-17:46): STILL CRASHED, and the log settled the
  question the polling fix could not.** Everything new worked — the quit hooks
  installed (round 21), both fired at 17:46:48, the earlier world change at
  17:45:20 reset all six modules — and then the log simply ENDS at the confirm.
  **No further loop pass is ever serviced once a quit is confirmed**, so
  detecting the world change afterwards is impossible by construction. (Run 5's
  "LEASH-SPY stopped, then the crash" was the same signal, read as a symptom
  instead of a cause.)
  - **Second fix (same pass):** release everything INSIDE the hook.
    `Combat.OnQuitConfirmed` (wired to `ConfirmReturnTitle`) tells PlayerRef
    the world is closing and runs the full reset there and then, on the game
    thread, while the world is still alive. `OnReturn2Title` still only
    tightens the watch, so if it is the earlier of the two nothing is dropped
    at a prompt the player may cancel.
  - `PlayerRef.SetWorldClosing/IsWorldClosing/ProbeForNewPlayer`: while closing,
    `Get()` returns nil — which every caller already handles, since that is
    what the title screen looks like — so the nameplate hook, the personality
    resolver and the trust recorder cannot refill the tables in the moment
    between the confirm and the world actually dying.
    `Combat.IsShuttingDown()` now also returns true while closing, which is
    what Indicator's sweep and Trust's tick already consult.
  - How a closing world ends is decided by `ProbeForNewPlayer`: a player at a
    DIFFERENT address = the new world is up; the SAME player still there after
    `WORLD_CLOSING_CANCEL_SECONDS` (10 s) = the quit was cancelled, logged as
    `the quit was CANCELLED`, and the mod resumes in that world (bonds from
    before the prompt are gone — the deliberate trade).
  - Harness sections F and G cover the in-hook release and both endings.
- **Third live run (17:54-17:55): STILL CRASHED — and the log caught the mod IN
  THE ACT.** The release ran correctly at the confirm (1 bonding record, 8
  nameplate bars, 21 personality records dropped), and then one more line was
  written after it:
  `[PalBonds/Personality] unrecognized AIResponsePreset 'PalAIResponsePreset'`.
  That value is the engine's own base class name, which is what a read off a
  half-destroyed object returns — so a HOOK was still doing work during
  teardown, after the loop had stopped. Releasing what we hold was never going
  to be enough: the game keeps calling the functions we hooked while it tears
  the world down, and this UE4SS build cannot unregister a hook.
  - **Third fix (pass 329): the world-closing gate.** Every hook callback in
    Indicator, Personality, Trust and Interaction now starts with
    `if world_is_closing() then return end` (a local helper per file, one
    function call, no reflection). The mod goes deliberately blind from the
    confirm until the next world's character exists. The two ESC-menu quit
    hooks are NOT gated, for obvious reasons.
  - `PlayerRef.IsWorldClosing` gives up waiting after `CLOSING_MAX_SECONDS`
    (60 s) and logs `giving up waiting`: if Combat's watch ever stopped being
    serviced, a permanently closed gate would look exactly like "the mod
    stopped working", which is worse than one frame of crash risk.
  - Harness section H: the busiest hook (`PalHate:DamageEvent`) does nothing
    during teardown, and the gate opens again after the timeout.
- **Fourth live run (18:06-18:08): STILL CRASHED, and the log is SILENT from
  the confirm to the crash.** The gate holds — our Lua provably does nothing
  during teardown — so what remains that is ours is the mere EXISTENCE of the
  hooks. UE4SS's own log registers 23 hooks (10 of them script hooks inside UI
  blueprint classes that load on demand and are destroyed with the world) and
  prints `[FCallbackGarbageCollector] Freed invalid callbacks!` after a world
  change. **Stop theorising and bisect.**
  - `Scripts/HookConfig.lua` (pass 330): hook GROUPS, all shipping `true`
    (`nameplate`, `boss`, `radial`, `workermenu`, `quit`, `senses`,
    `itemslot`, `otomo`, `damage`). A group that is off never registers, which
    is the only way to remove a hook in this build. 17 hooks with all on, 14
    with nameplate+boss off.
  - **Run A (in progress):** PalBonds disabled (`enabled.txt.MODS-DISABLED`)
    with UE4SS still loaded and its own built-in mods (BPModLoaderMod,
    BPML_GenericFunctions, Keybinds) active. Same recipe. If that crashes, the
    crash is UE4SS's, not ours — and it would explain why three real fixes
    changed nothing. Never tested before: the earlier vanilla control had no
    UE4SS at all.
  - Then: groups off in halves (the five UI script-hook groups first), then
    narrow to the group.
- **THE CAUSE, CONFIRMED (pass 333): keybind callbacks do not run on the game
  thread.** Dragón's final control settled it: *pet only* = clean, *feed only*
  = clean, *Play (F8)* = crash. Pet and Feed arrive through `RegisterHook`,
  which fires inside the game's own call stack (game thread). F8 arrives
  through `RegisterKeyBind`, which UE4SS services on **its own thread** — and
  from there the mod was starting animations, allocating action objects and
  queueing montages straight into the engine. Nothing fails at the time; engine
  state is corrupted quietly and the next world load reads freed memory
  (0x338). Hence: four correct world-change fixes changing nothing, the two
  clean v1.1.1 runs being the pet-only and feed-only ones, and "an action that
  fails to play is safe" (a refused call touches nothing).
  - UE4SS's own maintainer says the same about their async entry points
    (narknon, issue #1345, quoted in docs/hook-points.md): use the
    in-game-thread helpers. The mod did that everywhere EXCEPT its keybinds.
  - **Fix:** `run_on_game_thread(fn)` in Interaction.lua — `ExecuteInGameThread`
    first, `ExecuteInGameThreadWithDelay(1, ...)` as a fallback, and a logged
    direct call only if neither exists. **All three keybinds** (F8 Play, F9
    tags, F10 passive gain) now hop before doing anything; F9 touches live
    widgets and F10 shows a toast, so both count as engine work.
  - Harness: every prelude's `ExecuteInGameThread` now runs its callback and
    counts it; shiptest asserts each keybind hops exactly once. Those checks
    fail on the old code.
  - **CONFIRMED LIVE, 2026-09-17 evening.** Dragón's verification run: bonding,
    pet, feed, play, capture, several world reloads — no crash. This is 1.1.4.
  - **Release checklist for the next session (nothing done yet):**
    1. `mod/` is the fix; `release/PalBonds/Scripts` and
       `release/workshop/PalBonds/Scripts` are still 1.1.3 — rebuild both.
    2. Logger `DEBUG_LOGGING = false` in the release copies (the dev copy in
       the game folder keeps it true).
    3. `HookConfig.lua` is NEW — it must be in the zip, the Workshop folder and
       both release trees, with every group `true` and `EMOTE_ONLY = false`.
    4. Both held-back switches stay false (`FRIENDLY_BRIEF_FOLLOW`,
       `SELF_DEFENCE_EXTENDED_REACH`).
    5. Info.json Version 1.1.4, new zip, README/known-issues entry, changelog
       (one line per change, no promises — see the memory on his public text),
       then Nexus, then Workshop, then GitHub.
    6. The old 1.1.3 "crash fixed" known-issue entry in README.md needs
       correcting: that fix was real but it was not this crash.
  - Dragón on the player impact: not worried, because Play is already
    described as experimental on both store pages — but he wants it fixed so it
    can be used safely.
- **CORRECTION (pass 332, same evening): the `{}`-struct conclusion below was
  WRONG, and the log said so.** With every field of FActionDynamicParameter
  spelled out, UE4SS refused the call — `[push_classproperty] Error` — so the
  cheer never played. That run was clean for the same reason every clean run
  was clean: **no action was ever started.** Do not re-adopt the struct theory
  without a log line showing the emote actually playing.
  - Re-routing the cheer through `UPalActionComponent::PlayAction(pawn, cls)`
    (no struct at all) works — `[EMOTE] ... call ok` — and still crashes. That
    route is kept anyway: it is simpler, local, and has no parameter block.
  - **What IS established, from nine bisect runs:** reads, aiming and target
    resolution are safe; an action that PLAYS (on the player or on a Pal)
    poisons the next world load; an action that FAILS to play does not.
  - **The one hypothesis that fits everything, including the v1.1.1 runs:** the
    poison is an action **this mod starts directly**. Dragón's two clean 1.1.1
    runs were *pet only* and *feed only* — and the radial Pet/Feed path plays
    NOTHING itself (`grant_wild_interaction` is bookkeeping only; the GAME
    starts its own action there). Every crashing run today used F8 Play, which
    is where the mod's own `PlayActionByType` calls live.
  - **The mod's direct action plays, the complete list:** `do_play`'s
    `PlayActionByType(pal, PalRandomRest=77)` and its `Happy` follow-up
    (Interaction.lua ~765 and ~851), the player cheer (~1700), and Capture's
    join celebration `PlayActionByType(pal, 38)` (Capture.lua ~649).
  - **Next control (cheapest decisive run):** full mod, **no F8 at all** —
    radial Pet and Feed only — then quit and load. Clean = the rule holds, and
    the fix direction is to route Play through the game's own action start (the
    same substitution trick Pet already uses) instead of calling PlayActionByType.
  - **Player-facing consequence if it holds:** shipped 1.1.3 can crash for
    anyone who uses Play (F8) and then loads another world without restarting.
    Pet/Feed-only players are unaffected. Worth saying plainly in the 1.1.4
    notes once proven.
- **The (WRONG) conclusion of pass 331, kept for the record:** `{}` passed as a STRUCT.
  `play_player_emote` called
  `pc:ActionComponent_PlayAction_ToServer_ForPlayer(pawn, {}, cls, 0)` —
  copied verbatim from the Kick Keybind reference mod. That second argument is
  **`FActionDynamicParameter`, 0x100 bytes**: an actor pointer, a `TArray` of
  actors, an `FTransform`, two `FGuid`s and an `FPalNetArchive`. An empty Lua
  table leaves that memory as it was; the game copies the block into the action
  it creates and frees parts of it later. Nothing fails when the emote plays or
  when the world closes — it fails when the NEXT world loads into that memory.
  Hence four correct fixes to the quit path changing nothing.
  - **Dragón's bisect, one run each** (his own controls did the most work):
    UE4SS alone = clean; UI hooks off = crash; ALL hooks off = crash; no F8 =
    clean; F8 with no Pal nearby = clean; brief follow off = crash; trust grant
    off = crash; Pal animation only = crash; **player emote only, no Pal at
    all = crash**; same emote with every field spelled out = **CLEAN**
    (several loads, F8 spammed).
  - **Fix:** fill every field of the block, unconditionally. The switch used to
    prove it is gone. `Interaction.PlayPlayerEmote` is exported so the harness
    can fire the call directly; playstoptest asserts every field, and those
    checks fail on the old one-liner.
  - **Rule for this project from now on: an empty table is not an empty
    struct.** Any UFunction argument that is a struct gets every field spelled
    out. A grep found no other `{}` argument in the mod.
  - `Scripts/HookConfig.lua` stays (all groups true) — it turned a blind hunt
    into nine decisive runs, and it is the tool to reach for the next time
    something crashes only in game.
  - **Still to verify:** the full mod with the fix (the Pal-animation bisect run
    crashed too, and that call passes no struct — so either it shares the same
    poisoned memory or there is a second, smaller cause). If the full mod is
    clean, this ships as **1.1.4**.
  - **Answers for Dragón's questions, for the record:** the crash is inside
    the game's code but reached THROUGH our hooks (UE4SS frames sit mid-stack);
    and a "clean up on mod load" cannot help, because the mod loads once per
    game launch, nothing is persisted to disk, and the damage is done while the
    old world dies.
    **Watch for in the next log:** whether a CANCELLED line ever appears when
    Dragón confirms (it must not), and whether `ConfirmReturnTitle` fires on a
    cancelled prompt.
- **Bonded-Pal despawn:** stays a known issue.
- **Three-boss layout:** Dragón will test it himself with a spawn/cheat mod.
- **Own trust points (Dragón's idea, under discussion):** stop driving the bar
  from the game's `FriendshipPoint` and keep PalBonds' own points instead,
  granting the real trust only as the end-of-bond bonus. This would remove the
  game's own +10 after a pet from the bar, and would make per-interaction
  values fully ours to configure.
- **Settings screen wishlist (Dragón):**
  - language for toasts and tags (EN, ES, BR, JA, ...);
  - end-of-bond trust bonus, 0 to 200000 (max trust rank);
  - personality spawn weights (`PERSONALITY_TIERS`);
  - value per interaction;
  - rebindable Play / tags / passive-gain keys.
  - **Dragón's call:** the goal is an in-game menu, starting with a settings
    file first. Still open: where a user config survives Workshop updates.
    - **Candidate answer (from Random Sized Pals, 2026-09-18):** do NOT ship
      the config file. The mod writes a default `config.lua` beside `main.lua`
      on first run (write to `.tmp`, then rename) and `dofile`s it after that. A
      Workshop update replaces only shipped files, so an unshipped config
      survives. That is their claim and it is unverified here. Test it against
      the Workshop re-copy behaviour we found for 1.1.4 (the game re-copies the
      content folder when mods are enabled) before relying on it.
  - Own points: Dragón is interested; details later.
  - **DarnMenu 1.8.11 studied (2026-09-18).** Dragón put a copy in
    `32-PalBonds/DarnMenu 1.8.11 .../` to learn from, not as a dependency.
    Its licence: "free to use and modify".
    - **An in-game settings screen IS possible from pure Lua, with no pak and
      no Unreal editor.** This corrects what I said earlier. It uses
      `NotifyOnNewObject` on `WBP_MenuESC_C`, then after 50 ms (never inside
      the construction callback: AV writing 0x80) it constructs the game's own
      `WBP_MenuESC_Button_S_C` with `StaticConstructObject` under "Link
      Discord". Clicks come through a `RegisterHook` on that button class. The
      page is built from UMG CanvasPanel/ScrollBox/SizeBox.
    - Cost: ui.lua is 200 KB plus main.lua 176 KB, and full of crash lessons.
      Widget churn inside an open menu is their crash family, and a pre-build
      of about 100 widgets per ESC open caused 7 incidents before it was
      switched off.
    - **Config location: `Mods/shared/<name>_user.lua`, outside the mod
      folder,** because mod updates replace the folder. `Mods/shared` already
      exists in the Workshop UE4SS install (it is UE4SS's own library folder,
      with UEHelpers). Unverified: whether it survives a Workshop UE4SS
      update/re-copy. Test with a marker file in both `shared/` and our mod
      folder, across a Workshop enable.
    - Optional integration route: a mod writes
      `shared/DarnMenu_schema_<Name>.lua` and adds itself to
      `shared/DarnMenu_schema_index.lua`. With DarnMenu installed a page appears
      under ESC → Mod Options; without it nothing happens. Values apply at the
      next launch, or live via file polling.
    - Lessons that match ours: RegisterKeyBind runs off the game thread, so hop
      before touching UObjects (they crashed on it too; our 1.1.4 fix); gate
      work during map loads; write atomically (tmp → .bak → rename); "don't take
      the player's keys". `ExecuteWithDelay` (async) leaks a registry slot per
      fire, according to their reading of the UE4SS source. PalBonds uses only
      the game-thread `ExecuteInGameThreadWithDelay` plus the dead `LoopAsync`
      fallbacks.
- **1.1.5 CONTENT COMPLETE AND LIVE-TESTED (2026-09-18, end of day).**
  Dragón: "we will consider this the new most recent stable version". Pushed
  to GitHub. Tomorrow (09-19) is release packaging only, the usual steps:
  DEBUG_LOGGING back to false; README.txt, README.md and store text (the
  settings section drafted 2026-09-18 in chat: where the file is, how to edit
  it, "an in-game settings screen is planned for a future update"; the
  languages line; keys changeable); changelog; Info.json 1.1.5; zip; Nexus;
  Workshop pre-upload test, which also checks that PalBonds_settings.lua lands
  in and survives `Mods/NativeMods/UE4SS/Mods/shared/`; GitHub release notes.
  Dragón re-edits his 16 Workshop descriptions with the translated tag names
  (from docs/translations-review.md) and fixes "Tímid".
- **1.1.5 PACKAGED (2026-09-19, morning).** DEBUG_LOGGING false in `mod/`;
  all 21 suites pass, 17 hooks. `release/PalBonds-v1.1.5.zip` (14 files:
  LICENSE from the repo root, README.txt, enabled.txt, 11 scripts incl.
  Locale.lua and Settings.lua) verified byte-identical to `mod/`; the 1.1.4 zip
  deleted as usual. Both release trees and the game's manual-install copy are
  identical to `mod/`. `release/workshop/PalBonds/Info.json` is 1.1.5 (that copy
  has no BOM; the upload folder's does, so bump that one in place).
  README.txt: SETTINGS section, languages and settings bullets, keys
  changeable, the half-bar bonded hit, despawn message. README.md: the same
  plus a Settings section and a note on the despawn known issue.
  `nexus-description.txt`: Settings and Your language sections.
  The Workshop UE4SS has `Mods/NativeMods/UE4SS/Mods/shared/` (UEHelpers in
  it), so the settings path holds there; the Workshop test confirms it live.
  Order today: Nexus first, then the Workshop.
  - **Nexus: LIVE** (checked 2026-09-19): version 1.1.5, main file "PalBonds
    V1.1.5", 288 KB (= our zip), Dragón's changelog (8 one-liners) and short
    description. `release/nexus-description.txt` synced to the live page.
    Terminology in player text (Dragón): the game's UI calls its value
    "Trust", so where both appear (changelog) our bar is the "friendship bar";
    other texts keep "trust bar" as they are.
  - **Dev install DISABLED** for the Workshop test (`dwmapi.dll` and
    `ue4ss/Mods/PalBonds/enabled.txt` → `*.MODS-DISABLED`).
  - **Workshop upload folder prepared:** 11 scripts identical to
    `release/workshop`, Info.json 1.1.5 with its BOM kept, `.workshop.json`
    untouched. Next: Dragón ticks the Workshop mods and tests, then uploads.
  - **Workshop pre-upload test PASSED (2026-09-19, 12:26-12:30).** The
    NativeMods copy (re-copied 12:26) is identical to the release, 11 scripts.
    The settings file was CREATED in `Mods/NativeMods/UE4SS/Mods/shared/` on
    the first launch (12:26) and LOADED on the next one (UE4SS.log 12:29:
    "[SETTINGS] loaded .../NativeMods/UE4SS/Mods/shared/PalBonds_settings.lua"),
    17 hooks, no Lua errors. So the Workshop settings path is confirmed.
    Still unobserved: the file surviving a real Steam update of the item
    (it lives outside the PalBonds folder the update replaces).
  - **Workshop: LIVE** (checked 2026-09-19): updated 19 Sep @ 12:40pm, change
    note "Version 1.1.5" with the same 8 lines as Nexus, `.workshop.json`
    `last_published_version` 1.1.5, upload folder still identical to the
    release. English description has the Settings section (Steam route +
    `Mods/NativeMods/UE4SS/Mods/shared/`), the keys line, the language bullet
    and Known Issues; `release/workshop-description.txt` synced. Dragón still has
    to update the 16 translated descriptions. Dev install still DISABLED.
    Left: GitHub commit + release notes (ask first).
- **1.1.5 PLAN (Dragón, 2026-09-18): ship TOMORROW (09-19), not today, with the
  own-points rework plus the settings file ("either if we finish the settings
  file or not"). Two uploads a few hours apart made no sense, and the 1.1.4
  bugs it fixes are mild.**
- **SETTINGS FILE v1 — IMPLEMENTED 2026-09-18, awaiting a live run.**
  Dragón's scope: everything on the wishlist except language, as plain numbers
  ("percentages would destroy the purpose to have multipliers per level").
  - `Scripts/Settings.lua`, required first by Interaction, Trust, Capture,
    Personality and Indicator. It writes `PalBonds_settings.lua` on first
    launch into UE4SS's `Mods/shared/` (falling back to our mod folder if
    that isn't writable) via tmp + rename, and reads it once at launch.
    Changes apply on the next launch.
  - Keys: Pet, Play, FeedBase, FeedBonusCommon..Legendary, KinshipPeachLesser,
    KinshipPeach, PassivePerTick, JoinBonus (0–200000), ChanceNormal..Feral
    (weights 0–1000; if all are 0 the defaults apply), KeyPlay/KeyTags/
    KeyPassiveGain (validated against UE4SS's `Key` table, case-insensitive).
  - Rules: the file is loaded with an EMPTY environment (it can only return
    values). A bad value uses its default and is reported on the UE4SS
    console (`[PalBonds] [SETTINGS]`, via print, so it shows in a release
    build). An unparseable file is left untouched and all defaults apply.
    An existing file is NEVER rewritten; settings added later use their
    defaults. Unknown names are reported as typos.
  - Tests: `tools/harness/settingstest.js` (in-memory file system; A–G).
    pointstest's join check now reads the setting. `undefcheck.py` knows
    `loadfile`. 20 suites pass, 17 hooks.
  - Still to verify: that the file survives a Workshop update / re-copy in
    `shared/`. Plan: tomorrow's Workshop pre-upload test doubles as that check.
    README.txt/README.md/store text need a settings section at release.
  - **Language (asked 2026-09-18):** about 22 short strings (7 toasts, 4
    toggle toasts, 11 tags/labels). The code is small; the open parts are
    writing and checking the translations (Dragón has Steam description
    translations in ~10 languages to align terms with), whether non-English
    characters survive UE4SS's Lua-to-game text conversion (needs one live
    toast test), whether longer words fit the tag under the health bar, and
    whether to follow the game's language automatically.
    - **Dragón's Workshop description exists in 16 languages besides
      English** (2026-09-16/17): Simplified and Traditional Chinese, Japanese,
      Korean, Thai, Indonesian, German, Spanish (Spain), Spanish (Latin
      America), French, Italian, Polish, Portuguese (Brazil), Russian,
      Turkish, Vietnamese. To read one, add Steam's language parameter to the
      Workshop URL (`...?id=3797816321&l=spanish`; others: schinese,
      tchinese, japanese, koreana, thai, indonesian, german, latam, french,
      italian, polish, brazilian, russian, turkish, vietnamese) and read
      `.workshopItemDescription` in the browser. Verified with `spanish` on
      2026-09-18. Use these to keep the mod's terms matching the description.
    - Language work is AFTER 1.1.5.
  - Committed + pushed 2026-09-18 (`0a13eb9`, Dragón's go-ahead): the points
    rework, despawn changes and settings, with DEBUG_LOGGING still on in
    `mod/`. The DarnMenu reference folder is git-ignored (not ours to
    redistribute).
  - Settings live run 1: the file was created in `ue4ss/Mods/shared/` on
    first launch (console line OK). Fixed afterwards: the line printed twice
    in dev mode (Logger also prints) and showed `Scripts/../../shared`;
    `tidy_path` now cleans it. For run 2 the game's file has test values:
    Pet = 200, KeyPlay = "F7", and a deliberate typo `Petting = 5`. Delete
    the file after the run to restore the defaults.
  - **Settings live run 2: PASSED (2026-09-18).** UE4SS.log showed a clean
    "loaded .../ue4ss/Mods/shared/PalBonds_settings.lua" line and `"Petting" is
    not a PalBonds setting (typo?) — ignored`, each once. The first pet gave
    trust 200; F7 played and F8 did nothing (Dragón confirmed in game; the log
    shows "F7 pressed — starting Play"). The test file was deleted afterwards,
    so the next launch recreates the defaults.
  - **Language, Dragón's call (2026-09-18):** follow the game's language
    automatically IF WE CAN, otherwise default to English. Lead:
    `UKismetInternationalizationLibrary::GetCurrentLanguage()` /
    `GetCurrentCulture()` (Engine.hpp 13925, no parameters, returns an
    FString). Unknown: whether Palworld's in-game language option (it has its
    own `EPalLanguageType`, and its text lives in per-language DataTables
    rather than .locres) changes the engine culture, or whether that reports
    the Steam/OS language. Needs one read-only probe run: log both, then
    switch the in-game language and relaunch. After 1.1.5.
  - **LANG PROBE ARMED in the GAME COPY ONLY (2026-09-18, Dragón asked for the
    test now):** `Scripts/LangProbe.lua`, plus a `pcall(require, "LangProbe")`
    line at the end of the game copy's main.lua. F6 logs `[LANG-PROBE] engine
    language = ... | engine culture = ...` and shows 3 toasts in Latin with
    accents, Cyrillic, Vietnamese, Thai, Chinese, Japanese and Korean. `mod/`
    and git are untouched. **DELETE both after the run**; the game copy must
    match `mod/` again before the 1.1.5 Workshop test.
    - **Probe run 1 (2026-09-18): every script renders correctly in the
      game's toast**, in English and in Spanish: accented Latin, Polish,
      Turkish, Cyrillic, Vietnamese, Thai (including combining marks),
      Chinese (simplified and traditional), Japanese and Korean. So UE4SS's
      Lua → FText conversion is UTF-8-safe. One quirk: `|` displays as a
      quote-like mark, so avoid it in player text.
    - **Engine reading FOLLOWS the in-game language: auto-detection is
      possible.** English session: `language = en | culture = en` (Dragón
      confirmed the pasted console was from the English launch). Spanish
      session (probe run 2, 20:51): `language = es-MX | culture = es-MX`. Read
      with `StaticFindObject("/Script/Engine.Default__KismetInternationalizationLibrary")
      :GetCurrentLanguage()`, returning an FString (`:ToString()`), called on
      the game thread without trouble. Map culture to translation: exact code
      first (es-MX = Latin America, pt-BR, zh-Hans/zh-Hant), then the part
      before "-", else English (Dragón's fallback). Still to confirm: what
      code the Spain-Spanish and Chinese options report.
    - The probe was REMOVED from the game copy after run 2; the game copy
      matches `mod/` again.
  - **TRANSLATIONS — IMPLEMENTED 2026-09-18 for 1.1.5 (Dragón: "why not do
    the translations now so we can ship them tomorrow too"), awaiting a live
    run.**
    - Dragón's rulings: translate the TAGS too. He will re-edit his 16
      Workshop descriptions once 1.1.5 is uploaded; they currently name the
      tags in English on purpose, and "Tímid" is his typo to fix then. Use
      ONE neutral Spanish set for Spain and Latin America, like his
      descriptions.
    - `Scripts/Locale.lua`: 23 strings (12 tags, 6 messages, "A Pal", 4
      F9/F10 toasts) × 16 sets (en, es, fr, de, it, pl, pt, ru, tr, vi, th,
      id, ja, ko, zh-hans, zh-hant). Wording follows his Workshop
      translations where they already name things (tags = "etiquetas de
      personalidad"/"性格タグ"/…, passive friendship gain, trust, giving up
      on you). Feral avoids each language's word for "wild" (Feroz, Rasend,
      Szalony, Azgın…), since every tagged Pal is wild. Scarred is an
      emotional word (Resentido, Verbittert, Kırgın, 心寒…).
    - `Locale.T(key, {name=})` and `Locale.FromCulture(code)`. "auto" reads
      the engine's GetCurrentLanguage at most every 10 s (only from game-thread
      callers: tag refresh and toasts); an unknown code or a failed call
      means English. Settings got `Language` ("auto" or a listed code, in its
      own LANGUAGE section; existing files default to auto).
    - Wired: Indicator's tag maps now hold keys, Capture's
      joined/betrayed/fell/abandoned/shaken toasts, and Interaction's F9/F10
      toasts. Tags refresh on their own, so a language change shows up
      mid-game.
    - Tests: `tools/harness/localetest.js` (A–E); settingstest gained
      Language checks. 22 suites pass, 17 hooks.
    - To verify live: the wording reads naturally (Dragón can judge
      Spanish), and long tags fit under the health bar (German Misstrauisch
      and Distanziert, Russian Отстранённый/Настороженный, Indonesian
      Ditinggalkan).
    - **Live run 1 (Dragón):** Spanish appears correctly. Palworld CANNOT
      change language mid-game, only between launches, so the "tags switch
      within 10 s" idea is moot (a comment was corrected). He saw a female Pal
      tagged "Curioso".
    - **GENDER (2026-09-18, his catch):** in es, pt, fr, it, pl and ru an
      entry is now `{ m = , f = }` (75 of them: tags, plus the joined,
      betrayed, fell, abandoned and shaken messages where a word or pronoun
      changes). `Locale.T(key, { female = })` picks the form; unknown or
      None gender uses the masculine (the neutral form in those languages).
      The gender comes from `UPalIndividualCharacterParameter:GetGenderType()`
      (EPalGenderType: 0 None, 1 Male, 2 Female). Personality reads it ONCE
      into its record (`state.female`, `Personality.IsFemale(palId)`) for the
      tags; Capture reads it at message time (`Capture.IsFemale(pal)`), the
      join resolves it before the capture like the name, and Trust caches it
      with the name for a follower that later despawns. localetest D2.
      Live run 2 (Dragón): female and male forms show correctly.
    - **Review file for Dragón (2026-09-18):** he wants every text checked by
      other AIs and translators. `docs/translations-review.md` is GENERATED
      from Locale.lua by `tools/translations/` (see its README): context,
      rules for reviewers, and one table per language. Corrections come back
      by ID, then regenerate. Pending: his reviewers' feedback, which may
      change strings before or after 1.1.5.
    - **REVIEW APPLIED (2026-09-18).** Dragón had ChatGPT and Gemini review
      the file (`docs/reveiw-chatgpt.txt`, `docs/review-gemini.txt`, his
      files; the first name is his typo). Weighed against my own pass and
      against his descriptions, 26 replacements in Locale.lua:
      - tr Feral Azgın → Gözü dönmüş (sexual meaning; not Vahşileşmiş,
        which contains "wild"; not Yırtıcı, which may clash with the
        Predator Pals);
      - pl Feral → Wściekły/Wściekła; id Scarred → Sakit hati; ja Curious
        → 好奇心旺盛; ko Curious → 호기심 많음;
      - fr Scarred → Trahi/Trahie (not "Blessé", which reads as injured
        under a health bar); fr and it shaken keep the flinch (now
        gendered in fr);
      - id abandoned → "berhenti menunggumu" (ChatGPT's "menyerah padamu"
        could mean "surrendered to you"); tr "Terk edilmiş"; fr "en
        arrière";
      - es shaken → "Su confianza en ti flaquea" (Dragón's pick over his
        own "se derrumba", which describes the betrayal rather than the
        warning); es joined stays "decidió irse contigo" (he felt
        "acompañarte" reads like following);
      - Russian → informal ты everywhere. Dragón left it to me: he wanted
        the mod to read casually, even though his Russian description uses
        вы.
      Rejected: German "Ein wilder Pal"/"Er" (his German description uses
      neuter "das Pal", so the current text matches it), and renaming the
      F10 system in de/pl/ru/ja/ko (those are his descriptions' own terms).
      22 suites pass; deployed; the review file was regenerated.
      `dump_locale.js` now resolves its fengari path.
    - Live language checks (Dragón): every language looked right; the
      longer Russian tags still fit the Pal card.
    - **50% "following" toast (Dragón's idea, 2026-09-18):** "{name} seems
      to like you and starts following you." It is his phrase plus a
      clause saying what the Pal now does. 24th string, all 16 sets
      (gendered in pl, ru, it). `Capture.NotifyStartedFollowing(name,
      female)`, positive tone. Both routes into following go through
      `on_became_bonded` in Trust.lua: StartFollowing, AND crossing 50%
      during the 20% calm-down. That second route previously never cached
      the name, so a later despawn toast would have said "A Pal"; fixed.
      pointstest P3/P12.
    - Order after every interaction: 50% check, then 20% (only for Pals not
      following), then 100%. So a single interaction that crosses 50% skips
      the calm-down (following already calms), and one that reaches 100%
      starts the follow and then joins after the usual 5 s. **Dragón's call
      (2026-09-18): when the same interaction reaches 100%, NO "starts
      following" message, only the join message**
      (`Trust.StartFollowing(pal, st, ratio, quiet)`). The follow itself
      still starts, unchanged. pointstest P5.
    - Settings text, from Dragón's questions: JoinBonus now says 200000 is
      the game's highest rank and the maximum accepted (above that: ignored,
      default used, reported). The chances are explained as weights with a
      worked example (Curious 100 + Aloof 100 + the other five at defaults
      = 260 in total, each about 38%). His old settings file (it lacked
      Language) was deleted; the next launch writes the current one.
    - My own second-pass suggestions (2026-09-18, superseded by the applied review above; weigh them
      together with his reviewers'): id tag_scarred Terluka → Sakit Hati
      (physical, a real error); tr tag_abandoned → "Terk edilmiş", tag_hostile
      → Saldırgan, tag_friendly → Dost canlısı, fell "düştü" → "yenik düştü";
      pl tag_feral → Wściekły/Wściekła, tag_scarred → Zraniony/Zraniona; fr
      abandoned "laissé derrière" → "laissé en arrière"; es shaken 2nd
      sentence → "Su confianza en ti flaquea." Flagged for natives: tr "Bağlı",
      ko 당신, ja noun/adjective mix in tags.
    - **Palworld's own languages (`EPalLanguageType`, Pal_enums.hpp:2822):
      JP, EN, ZH_HANS, ZH_HANT, FR, IT, DE, ES, KO, PT_BR, RU, TH, VI, ID, TR,
      PL, ES_MX.** That is exactly Dragón's 16 Workshop translations plus
      English. Where the game stores the current choice is not found yet
      (no ini holds it; `EditorPlayTextLanguageType` is editor-only).
- **OWN POINTS REWORK — Dragón's rulings (2026-09-18), next work:**
  - The bar runs on PalBonds' own points, not the game's `FriendshipPoint`.
    Every existing number carries over: base bar 500 × level tier
    (×4/×2/×1.5/×1/×0.75/×0.5/×0.25) × 2 for bosses; 20% Friendly/forgive, 50%
    bonded, 100% joins; Pet 50, Play 50, Feed 50 + rarity 10..50, lesser
    Peach 250, Peach 500; passive +2 per 1.5 s while following (stays as is,
    and becomes a setting later); a player hit below 50% drops to 0; a bonded
    hit costs half the bar, and reaching 0 is betrayal; drift past 30 m for
    3 s means all trust is lost.
  - **Removed:** the −150 when something other than the player hits a
    follower. "Since we now make the pals fight together this shouldn't exist
    anymore."
  - **Join bonus: only the flat +50,000** of the game's real trust. The old
    raise-to-21,000 (`CAPTURE_BONUS_TARGET_POINT` in Trust.lua) goes; Dragón
    didn't know it still existed. The +50,000 becomes a setting later.
  - Play's backup branch (`INTERACTION_FRIENDSHIP_GAIN` 25, which skips the
    fled check) moves onto the one grant path at 50. That's a bug fix.
  - The README wording "hit a bonded Pal and it's over" overstates the rule
    (the first hit costs half the bar). Fix the wording.
  - Check what happens to the bars after a save and reload before building on
    it.
  - **IMPLEMENTED 2026-09-18, awaiting Dragón's live run.** In `mod/` and the
    game copy (DEBUG_LOGGING true); not released.
    - Trust.lua: `st.points` in `State`, plus `Trust.GetPoints`,
      `Trust.AddPoints` (refuses owned Pals, clamps at 0) and
      `Trust.GetBarRatio`. OnInteractionSucceeded, the brief-follow end check,
      unbonded hit (→0), bonded hit (−half bar, then betrayal →0), drift (→0)
      and passive (+2) all use it.
    - Removed: `CAPTURE_BONUS_TARGET_POINT` (the rank-3 raise),
      `CAPTURE_AT_FRIENDSHIP_POINT`, `DAMAGE_FRIENDSHIP_PENALTY` (the −150 was
      already unreachable from both hooks since pass 211; its dead branch is
      gone), `Trust.GetBondingThreshold`, `Trust.ComputeBondingThresholdFor`
      (old F9), `lastPoint`/`lastRank`.
    - Interaction.lua: Pet/Play (`grant_wild_interaction`) and Feed (the
      RequestUseToCharacter post-hook) grant through `Trust.AddPoints`. Play's
      backup branch uses the same path at 50 (`INTERACTION_FRIENDSHIP_GAIN`
      removed). Log tags: `[BALANCE-TEST] ... trust a -> b` and
      `[FEED-FRIENDSHIP] wild Feed +n, trust a -> b`.
    - Indicator.lua: `get_friendship_ratio` is now `Trust.GetBarRatio`, one
      name lookup instead of three reflection calls per bar refresh.
    - The game's friendship is now written ONLY by Capture.OnTrustMaxed's flat
      +50,000.
    - **Bug fixed along the way (was in 1.1.4):** `local briefFollow` was
      declared below `Trust.ResetForNewWorld`, so the reset wrote a stray
      global and never cleared the real calm-down table on a world change. It
      is now declared next to `State`.
    - Tests: the new `tools/harness/pointstest.js` (P1–P9 plus a source scan;
      it fails on 1.1.4, including the stray global). bosstest was moved onto
      `Trust.GetPoints`/`GetBarRatio`. All 19 suites pass.
    - Still to do at release: README.md/README.txt wording (the bonded hit
      costs half the bar first); DEBUG_LOGGING back to false.
  - **Despawned Pals are forgotten (Dragón, 2026-09-18):** "the pals are still
    wild so on world reload or even by teleporting away they should despawn
    and that's fine, those don't need to be recorded unless still inside the
    radius of the player area - so let them despawn normally, no need to save
    their data." That answers the 09-16 open question "keep or wipe an invalid
    Pal's trust": wipe it. Implemented: `forget_despawned_pals()` at the top of
    every Trust tick drops any NON-following record whose actor is invalid
    (along with its level cache, drift clock and brief-follow entry), logged
    `[DESPAWN]`. Tested in pointstest P10.
    - **Followers, Dragón 2026-09-18: "if a pal despawn lets show the
      abandoned toast".** Implemented. A bonded follower whose actor goes
      invalid gets its record dropped, `Combat.ForgetDespawnedFollower(key)`
      (every per-follower table dropped by key, with nothing called on the
      dead actor; `forget_follower_tables` is now shared with StopFollowing),
      and `Capture.NotifyBondLostByName(st.displayName, "abandoned")`. The
      name is cached through `Capture.ResolveDisplayName` in
      `Trust.StartFollowing`. A Pal on its 20% calm-down is not bonded, so it
      is forgotten quietly. pointstest P10. This closes the 09-16 "despawn
      mid-countdown, skipped silently forever" bug.
    - Live run 2 (2026-09-18) confirmed: F10, a follower hit by an enemy costs
      nothing, `[DESPAWN]` for non-followers after teleporting, and a follower
      left behind by a teleport breaking through the normal drift path first.
  - **Betrayed Pal un-betrayed by a later hit (found in live run 1, present
    since 1.1.4), FIXED 2026-09-18:** after a betrayal (forced tier
    `warlike_anyway`), the player hitting the Pal again reached the below-50%
    rule, and RevertForgiveness put it back to its rolled personality. A
    naturally peaceful Pal would stop being angry after being betrayed.
    `OnFollowerDamaged` now returns early for `Capture.HasPermanentlyFled`.
    pointstest P11.
  - **Human NPCs can be petted but not fed. It has always been this way, and
    it is the game's own limit.** The wild feed calls
    `OnSelectedOrderWorkerRadialMenu`, which Pal.hpp declares on
    `APalMonsterCharacter` (Pals). Humans are `APalNPC`, its parent, so the
    call fails and the mod correctly grants nothing ("the wild feed did not go
    through"). Pet works because it goes through a different route.
    **Dragón's call: keep it as is.** "It's already plenty rare to interact
    with humans like that, just petting them is enough for now."
- **Today's work: polish the two held-back features** (20% brief follow and
  the 3000 self-defence reach) with live runs. The Workshop mods are off (no
  `ActiveModList` in `PalModSettings.ini`). The local dev copy is on again
  (`dwmapi.dll`, `enabled.txt`) with `mod/` + DEBUG_LOGGING true, and both
  switches set to **true in the game copy only**; `mod/` still has them false
  (= shipped 1.1.3). With the switches on, every harness test passes except
  bosstest G, which asserts the shipped (off) state.
  - Still to watch from run 5:
    - the release goes through `Combat.StopFollowing`, which can leave a
      self-trainer follow action on the wild Pal;
    - hitting the Pal during its brief follow counts as betrayal;
    - "no readable sensor, friendly preset not written".

**Real player reports to fold in (Steam Workshop, LuWicki97, read 2026-09-15):**
- *"been testing this with a friend via invite code. I befriended a digtoise
  and somehow my friend ended up getting it in his team instead."* That player
  concludes co-op isn't functional yet.
  - **Likely cause, unconfirmed:** every player lookup takes the FIRST valid
    `PalPlayerCharacter` in the object list. That was true of the old
    `FindAllOf`/`FindFirstOf` sites, and it is now true of `PlayerRef.Get()`.
    In co-op there are several, so the capture/grant can target another
    player.
  - A real fix needs "the player who interacted", e.g. from the hook context
    or the local controller, not "a player".
- *"often the options didn't pop up properly... tried on a lyleen and
  azurmane next. I didn't get an option at all."* Digtoise worked "somewhat
  fine". This may be the big-Pal targeting (aim sphere from the capsule, see
  `find_targeted_pal`), or it may be co-op-specific. Not reproduced yet.
- Dragón replied on the Workshop page (2026-09-15): the mod is only tested in
  singleplayer; for big Pals, aim at the lower body and get close.

**Multiplayer support (co-op worlds, community dedicated servers): analysed
2026-09-12, not started.** Dragón asked what it would take. Official Pocketpair
servers do not allow mods at all, so that is not a goal. For player-hosted co-op
worlds and modded community servers, the host/server simulates wild Pals' AI,
hate, friendship and capture, and the mod was written for one local player:
- every player lookup takes the first player found (Trust, Combat, Capture,
  Interaction, Personality);
- bonding state is per Pal with no owner, so two players cannot bond separately;
- input is local (F8/F9/F10 keybinds, radial-menu hooks) while trust grants
  (`AddFriendShip`, ~22 call sites), follow/combat actions and capture only take
  effect on the server, and UE4SS Lua has no networking of its own, so client
  requests would have to ride on game RPCs the server already receives;
- trust bars and tags are client-side UI and would need server values;
- a dedicated server has no local player at all, and Workshop mods on dedicated
  servers are Windows-only with every client needing the same mods.
Likely today, untested: the host of a co-op world gets the mod for themselves;
guests do not. Cheapest first step if pursued: a co-op session with a friend,
both with the mod, to see what already works, then decide whether a real
client/server split is worth it. It is a large rework of the "who" logic in
four modules, not a patch.

**Play's cheer emote — SHIPPED.** Cheer is `BP_Action_Emote_0_C` (Dragón
identified it with the F7 probe, which has since been removed). Played as the
last statement of `do_play`, logs `[EMOTE]` only on failure.

**Hotkeys fire while typing in chat — DECLINED, do not propose again.** The
Kick Keybind reference mod caches `PalEditableTextBox` /
`PalMultiLineEditableTextBox` / `EditableTextBox` and checks
`HasKeyboardFocus()` before acting; this project's F8/F9/F10 binds have no such
guard. Dragón, 2026-09-14: F8/F9/F10 are "hardly touched during typing," so
fixing this isn't necessary. Left here only as a historical note of the
mechanism, in case the calculus changes later.


**Play's target-busy gate — do not fix in isolation.** Dragón's call, 2026-09-11:
*"lets skip it for now, but add it as a pending for when the play interaction
gets its full development, right now there's no need to fix something thats
just an added extra"*.

The problem, so it does not need re-diagnosing later: `do_play` gates on the
TARGET's `ActionComponent:ActionIsEmpty()`, and a wild Pal almost always has
some idle action running, so the gate refuses nearly every press. His
2026-09-11 log shows **4 out of 4 F8 presses refused** on it, every one having
found its Pal correctly:

```
19:40:57  F8 pressed — starting Play
19:40:57  target is busy or its action state couldn't be read — skipping Play
```

`ActionIsEmpty()` is the signal this project has already rejected twice as
unreliable (it broke the rest animation in pass 179 and defeated three separate
capture-delay attempts, because it reports empty in the gaps between steps of a
real multi-part action). So the fix is not to tweak the gate — it is to decide
what "the target is available" actually means, as part of giving Play a real
implementation. Play also still has no radial-menu entry, which Dragón wants;
these belong in the same piece of work.

## Next steps

In order:
0. **DONE 2026-09-15 — v1.1.2 published to Nexus and the Steam Workshop**,
   verified on both pages and in the game's installed copy (see "Where we
   stand"). Kept for reference: it was done one store at a time, following
   "Publishing procedure" and "Publishing safety". The files are ready: `release/PalBonds-v1.1.2.zip` (Nexus) and
   `release/workshop/PalBonds/` (Workshop, Version 1.1.2). Both need the new
   `PlayerRef.lua` and `Profiler.lua` — already included. Changelog material:
   the README "Known issues" microstutter entry.
0b. **NEXT UPDATE (Dragón, 2026-09-15: "save this for tomorrow, it will be
   our next update we have to work on") — bosses show neither the trust bar
   nor the personality tag.**
   - **Symptom 1:** a boss Pal never shows its friendship/trust bar.
   - **Symptom 2:** a boss Pal never shows the personality it rolled.
   - **Same cause for both, in Dragón's words: "since they have a different HP
     bar".** What the code confirms: everything Indicator.lua draws attaches to
     the regular nameplate widget, `WBP_PalNPCHPGauge_C`. That covers the
     `BindFromHandle`/`Unbind` hooks, the `pendingGauges` install path, the
     world sweep `FindAllOf("WBP_PalNPCHPGauge_C")`, and `install_trust_bar`
     parenting into that widget's `ProgressBar_HP` panel. A boss's HP bar is a
     different widget, so nothing ever attaches to it.
   - **Found in the UE4SS CXXHeaderDump (2026-09-16), not yet seen live:**
     - `WBP_BossEnemyHPGauge_C` (parent `UPalUICharacterHPGaugeBase`, the same
       base as the normal gauge) has a direct `TargetCharacter` field and a
       `SetTargetCharacter(APalCharacter*)` function, so the Pal comes with the
       widget and no handle lookup is needed. Also `OnDead`, `OnRequestClose`,
       `Destruct`.
     - Its child `WBP_IngameBossHP` (`WBP_IngameBossHP_C`) is the visible
       top-of-screen bar: `BossGaugeHP` / `BossGaugeHP_Back` (ProgressBars),
       `Text_BossName`, `Text_LvValue`, `CanvasPanel_Prefix`, `SizeBox_Overall`.
     - The owner is `WBP_PalNPCHPGaugeCanvas`: `DisplayedBossUGaugeMap`
       (APalCharacter → gauge), `Add Boss Gauge`, `OnEndPlayBossPal`,
       `OnBossDead`.
     - The species flag is `UseBossHPGauge` (data table), plus
       `GetIsBoss`/`GetIsRaidBoss`/`GetIsTowerBoss`/`GetIsPredatorBoss`.
     - Plan: hook `SetTargetCharacter`, attach bar + tag inside the boss
       widget, clean up on `Destruct`/`OnDead`. Placement is Dragón's call.
   - **BUILT 2026-09-16, harness-tested (`bosstest.js`), deployed to the dev
     copy, NOT yet seen in game.** Dragón's calls: every boss type shows it
     ("i've been able to bond with all type of bosses so far"); the trust bar
     goes under the HP bar "like always, ideally with the same length too";
     the tag goes under the bar, as on nameplates. He flagged that several
     bosses stack their bars vertically, so the same offsets may overlap the
     next bar. `Indicator.lua` "BOSS HP BAR" section: hook-fed
     (`pendingBossGauges` → `bossEntries`), one `FindAllOf` only right after
     the hook installs, refreshed on the existing 2 s tick. Bar/tag go into
     `BossGaugeHP`'s own panel (the "BossHP" canvas). Bar height = 35% of the
     HP bar's, clamped 6–10. Tag style copied from `Text_LvTitle` (falls back
     to `Text_BossName`), height 22 — both guesses to check.
     `[BOSS-GEOM]` (diagnostics only) prints the real layout, nesting chain
     and clipping once per session.
   - **Run 1 (2026-09-16, Chillet alpha):** tag appeared ("Bonding"), trust
     bar invisible. Cause: `BossGaugeHP`'s slot is anchored, and
     GetPosition/GetSize returned (4,18)/(4,8) — raw offsets, where 4 is a
     RIGHT MARGIN, not a width. The bar was built 4px wide (a yellow dot at
     the left end of the HP bar in his screenshot). Fixed: our widgets now
     copy the HP bar's anchors and alignment and reuse its left/right
     offsets, so they get the same length either way; the HP bar is 8 tall
     at Y 18, so the trust bar sits at Y 28, 6 tall. `bosstest.js` A1b
     models the stretched layout and fails without the anchor copy.
     Nesting seen: `BossHP` canvas < `SizeBox_128` < `VerticalBox_94` <
     `CanvasPanel_BossHP` < `SizeBox_Overall` < `CanvasPanel_0`; clipping 0.
     Seen attaching to alpha, predator and ThunderBird bosses. Stacking with
     two bosses still untested.
   - **Design reminders:**
     - Bonding a boss already works (the raid-boss test, alpha x2 bar); only
       the display is missing.
     - Keep the 1.1.2 performance rules: hook-driven, no timed world sweeps, a
       rare safety net only.
     - The label-only vs bar entry logic and "owned Pals show no tag" must
       carry over.
0c. **Idea (Dragón, 2026-09-16, "just curiosity"): a Pal crossing 20% should
   stop what it was doing / stop attacking.** It is already coded:
   `Personality.MaybeBecomeFriendlyByBar` swaps the real AI preset to friendly
   and runs `interrupt_and_resense`, which cancels the current action, resets
   `ResponsedMaxBiologicalGrade` and re-senses. Two gaps: it has never been
   confirmed live on a Pal that was ATTACKING at the time, and nothing clears
   the Pal's hate target, so it may resume the fight. Only for unowned,
   not-yet-following Pals whose disposition wasn't already friendly.
   - **Third gap, found 2026-09-16:** a Pal that ROLLED Curious (internal
     "friendly") never gets the reset at all, because the function returns at
     its first check. The commenter's Curious attacker is exactly that case.
   - **Dragón's theory to confirm (2026-09-16):** the commenter's Timid Pal
     joined a same-species Hostile's fight (the joiner behaviour), and after
     the reset it simply joined again because the Hostile was still there.
   - **Spies in place:** `[WON-OVER-SPY]` in `Personality.lua` (diagnostics
     only): state before the reset, which path ran (reset / no reset and
     why), then the Pal's action and hate target every 2 s for 20 s, tagging
     the target `(THE PLAYER)` or `(SAME SPECIES)`. Remove once answered.
   - **Run 1 (2026-09-16), what the log shows (Dragón's own account still
     to compare):**
     - Chillet alpha (tracked 'notinterested'): reset ran cleanly; it was
       calm before and after (petting / looking at the player).
     - **Timid Lamball: NO reset — a real bug.** Its species preset is
       friendly, and `state.presetClassName` still holds that species value
       even though enforcement had swapped its real AI to a private escape
       preset. So the "preset already friendly" check skips the reset of a
       Pal whose real AI is NOT friendly. It kept attacking the player for
       the whole 21 s watch. Fix candidate: record the enforced preset in
       `presetClassName` (or check `enforcementApplied`/`rolledTier`).
     - Curious Chikipi: no reset (the rolled-Curious gap); attacked the
       player for ~10 s, then was being petted and started following.
     - Both reached 50% on the next pet (bar 125 at a 0.25x level gap) and
       followed while their hate was still on the player.
     - **Dragón's corrections (what really happened):** one pet took each
       Pal past 20% but under 50% (Lamball 23 s and Chikipi 10 s between
       Friendly and following — enough time; I misread this). The Lamball
       did NOT join the fight against the other Lamball: it stayed angry at
       him after bonding and he killed that Lamball alone. It only fought
       the Chikipi because a hit landed on it. The log misled me because
       `[HATE-ASSIST] pushed hate` is our command, and `fighting=true
       (follow suspended for a fight)` is our own flag — neither shows what
       the Pal actually did.
     - **NEW BUG (Dragón, 2026-09-16): a failed pet still grants points.**
       Both first pets were done mid-attack animation and visibly failed,
       yet `[BALANCE-TEST]` granted +50. The spy confirms it: both Pals were
       still in `BP_AIAction_CombatPal_C` 2 s later, whereas successful pets
       show `BP_AIActionPairCall_Petting_C` (Chillet; both second pets).
     - Hate API available: `UPalHate` has only `ChangeHate(Attacker, delta)`,
       `ForceHateUp_...`, `DamageEvent`, `AttackSuccessEvent`,
       `SelfDeathEvent` — no clear/reset function.
     - **Dragón's rules (2026-09-16):** (a) "friendly > curious": a rolled
       Curious Pal gets the 20% reset too. (b) "friendly means it shouldnt
       attack unless to defend itself or at least it should forgive if it was
       angry before." His scenario: Curious + Feral roam together, the Feral
       attacks, the Curious joins, the player kills the Feral, the Curious
       keeps attacking, the player gets it to Friendly → it must stop.
     - **BUILT 2026-09-16, harness-tested (`bosstest.js` B1–B5, C1–C3, D1,
       all failing on the previous code), deployed, NOT yet seen in game:**
       - `Interaction.lua` PET-CHECK: a radial pet grants only once the Pal
         runs `...Petting...` (polled every 250 ms, up to 4 s); otherwise
         "the pet never happened", nothing granted.
       - `Personality.MaybeBecomeFriendlyByBar`: every wild Pal crossing 20%
         gets the reset (Curious included); `real_preset_is_friendly` uses
         the rolled tier over the stale species `presetClassName`; the reset
         waits for a pet in progress to end (`when_not_petting`, 500 ms, max
         10 s); a successful swap sets `rolledTier = "friendly"`.
       - `Personality.ForgivePlayer`: `ChangeHate(player, -step)` with steps
         100, 200, 400… (max 12) while the player is the Pal's top hate
         target. Player only; logs `[FORGIVE]`, including "STILL angry" if
         ChangeHate has no effect (the real unknown for the next run).
         Called at the 20% reset and from `Combat.StartFollowing`.
       - `[LEASH-SPY]` now adds `REALLY: <action / hate target>` from
         `Personality.DescribeFight`, so our "follow suspended" flag is no
         longer mistaken for the Pal actually fighting.
     - **Run 2 (2026-09-16 15:38), Dragón:** boss friendship bar now shows
       correctly (two-boss stacking still to check). Won-over Pals kept
       attacking; the bonded Garm (alpha wolf) "never defended me once, nor
       even itself". Pet test inconclusive in the chaos; next time he pets a
       SLEEPING Pal, which should grant nothing.
     - **Run 2, what the log shows:**
       - The ChangeHate forgive is DISPROVEN: five calls, 12 steps and
         -409,500 each, the player still the top hate target every time; each
         won-over Pal attacked for the whole 20 s watch. Removed.
       - What does clear hate on the player: starting to follow. In both runs
         every new follower dropped it within ~3 s (PinkCat 15:43:25→:28,
         Lamball and Chikipi in run 1). The companion preset's player slots
         = Ignore are the only player-facing change → now applied at 20% too
         (see below).
       - Garm self-defence: `[SELF-DEFENCE]` fired against a Lifmunk
         (Carbunclo, a ranged shooter) and was released IN THE SAME SECOND,
         "its target is out of reach" — the reach rule (target further than
         1800 from the player → don't fight). Twice. The log now prints the
         measured distance. Open design question for Dragón.
       - During his fight with the wild Garm pack: hate pushes logged, 16
         combat installs, but REALLY showed the Garm in `WildLife` with no
         hate most of the time, wandering past 1800 → recalled twice. The
         long-standing wild-AI problem, not new.
       - PET-CHECK: 6 pets refused at 15:47:28–42 with the Pal in
         `BP_AIAction_Death_C` (which Pal isn't named; ask Dragón).
     - **BUILT after run 2 (harness B1–B5 fail on the run-2 code):** the 20%
       reset always writes a fresh friendly preset with `Discover_Player` and
       `Damaged_Player` = Ignore; once the Pal no longer hates the player
       (checked every 1 s, up to 20 s) `Damaged_Player` goes back to the
       friendly default so it can defend itself
       (`RESTORE_SELF_DEFENCE_AFTER_FORGIVING`, unverified whether that wakes
       the old hate). `[FORGIVE]` logs either outcome.
     - **Run 3 (2026-09-16 16:10), Dragón:** boss bar + tag CONFIRMED correct
       — "lets settle that for now" (three bosses at once is too rare to find;
       parked). Sleeping-Pal pet correctly gave nothing. Pals still attacked
       after Friendly. Lyleen boss pets didn't match the friendship gain.
       The run felt laggy. His calls: self-defence against ranged attackers
       YES, with the limit raised to 3000 ("before they touch the abandoned
       border"); and the next release is built from the shipped version plus
       these fixes, not this log-heavy dev build.
     - **Run 3, what the log shows:**
       - Player slots = Ignore alone does NOT stop it: the Lamball attacked
         for all 21 s; the Plant Slime "calmed" only by dying.
       - Lyleen (`BP_LilyQueen_GYM_C`): the 3rd pet was "confirmed after
         0.00s" because the 2nd pet's animation was still playing — paid
         twice. Also +10 passive gain between pets (50→60), which is the
         passive-bonding feature, not a pet.
       - The killed wolf: 6 pets refused while in `BP_AIAction_Death_C` —
         correct.
       - Lag: `palbonds-profile.log` put the two diagnostics-only FindAllOf
         (`PalUICharacterHPGaugeBase`, `PalUINPCHPGaugeCanvasBase`, run every
         2 s when SHOW_DIAGNOSTICS is on) at 676 stalls, mean ~145 ms,
         ~3.5 s/min — the dev build's biggest cost by far.
     - **BUILT after run 3 (bosstest B1/B4, C4, D fail on the run-3 code):**
       - FRIENDLY GUARD (`Personality.friendly_guard`): for up to 30 s after
         the 20% reset, every 500 ms, while the Pal's top hate target is the
         player and it isn't in a PairCall (pet/feed), its action is
         cancelled; stops when it calms down (then restores Damaged_Player)
         or starts following. Modelled on why followers calm down: the
         follow action keeps taking the slot.
       - PET-CHECK only pays a NEW petting animation (address differs from
         the one playing when the pet was chosen; never the same animation
         twice; without addresses, only after a non-pet read).
       - `SELF_DEFENCE_RECALL_DISTANCE = 3000` for self-defence fights
         outside player fights (reach check and recall); player fights keep
         1800. The out-of-reach message now prints the distance.
       - Removed the diagnostic panel scan and everything only it used
         (`check_panel_children`, `check_all_panels`, property dumps,
         `register_bind_hook_once`, `find_bind_widget_class_path`,
         `inspect_gauge_widget`) — Indicator.lua 2,483 → 1,881 lines.
     - **Also built after run 3, before run 4 (bosstest B6 and E fail on the
       previous code):**
       - Dragón's idea, "force them to do a rest_animation after reaching
         20% - one that interrupts shortly after they forgive the player":
         the guard, after cancelling an attack, starts PalRandomRest (77) on
         the character ActionComponent when that is idle, and cancels it once
         the Pal calms down (`FRIENDLY_GUARD_PLAYS_REST`, false = cancel only).
         Unknown: whether the fight AI respects a character action.
       - Boss x2 bond meter: run 3 showed `GYM_LilyQueen` (tower Lyleen) at a
         125 bar while `BOSS_LilyQueen_Dark` got 500 — the "BOSS_" prefix
         missed gym bosses. `Trust.is_boss_pal` now also accepts "GYM_",
         `_BOSS`/`_GYM` in the Blueprint class, and any Pal the boss-bar hook
         reported (`Trust.MarkBossActor`, which also drops a multiplier
         cached before the bar appeared). Only the Lyleen pair was bonded in
         run 3; the Centaurs, Lyleen and the predator Mummy were only seen.
     - **Run 4 (2026-09-16 17:33):**
       - Lamball (rolled Curious) attacked all through the guard: 60 AI
         cancels in 30 s, the rest animation started only ONCE (the
         character ActionComponent was busy almost every tick — its attacks
         run there), and the watch showed `CombatPal` with hate on the player
         at every 2 s sample. Cancel+rest is DISPROVEN as a way to stop it:
         the AI re-picks the attack at once from the hate it still has.
         Three mechanisms have now failed (ChangeHate, player slots Ignore,
         cancel+rest). The one that works every time is starting to follow
         (hate gone in ~3 s). Leading hypothesis, UNTESTED: it is the follow
         action's `Trainer = player` (a Pal does not keep hate on its own
         trainer — `FPalHateInfo.bEnabled`), not the slot-holding. Next
         experiment proposed to Dragón: at 20%, install the follow action
         briefly (the Pal walks to the player for a few seconds), then drop
         it. Needs his call — it is a visible behaviour.
       - Human NPCs (Dragón): all showed "Curious" in town. Cause: humans
         were kept out of the roll but their disposition fell back to the
         species default, and the VillageNPC preset maps to "friendly" →
         "Curious". FIXED: `state.isHuman` → disposition "normal" (tag
         Normal). Also found: the 20% reset had rewritten the AI preset of the
         three humans he petted (a SalesPerson and two MobuCitizens) — FIXED,
         humans are skipped (bosstest B7).
       - Raid bosses: the object dump has `BP_LegendDeer_RAID_C`; "RAID_" and
         "_RAID" added to the boss markers (bosstest E2). The boss-bar route
         also covers them, since raid bosses get the boss HP bar.
     - **Dragón, after run 4:** humans stay bondable AND capturable like Pals
       — "in order to let true pacifist runs play out". (Their AI is still
       never touched by the 20% reset.) Go-ahead for the brief-follow test,
       with "remove all the other things" so nothing else muddies it.
     - **BUILT for run 5 (bosstest B1–B5 and F fail on the run-4 code):**
       `Trust.StartBriefFollow(pal, hatesPlayer, onDone)` — at 20% the Pal
       gets the REAL follow (st.isFollowing + Combat.StartFollowing, so the
       companion preset and target discipline come with it), started at once
       while the pet is still playing (Combat won't install follow over a
       fight). Polled every 500 ms: released via Trust.StopFollowing once it
       no longer hates the player and ≥3 s have passed, or at 15 s; kept if
       the bar passed 50% meanwhile. On release Personality writes a plain
       friendly preset and re-senses (no cancel). REMOVED: the friendly
       guard, the rest animation, the player-slot overrides, the
       Damaged_Player restore, `when_not_petting`, `apply_forced_preset`'s
       overrides parameter. `Personality.HatesPlayer` is exported.
       Risks to watch: hitting the Pal during the brief follow counts as
       betrayal; `Combat.StopFollowing` is the betrayal/abandon removal path
       (Wait-swap etc.), now used for a friendly release.
     - **Run 5 (2026-09-16 18:57) — the brief follow ran, then the game
       CRASHED:** `EXCEPTION_ACCESS_VIOLATION reading 0x338`, GameThread, two
       UE4SS frames in the stack — the same signature as the world-change
       crash solved in pass 285 (docs/hook-points.md). Log: LEASH-SPY stopped
       after 19:08:36 (loops no longer serviced), a HUD widget push at
       19:08:40, then the crash — the old quit-to-menu pattern. Awaiting what
       Dragón was doing at that moment.
       - Brief follow worked mechanically every time: CuteFox, ChickenPal,
         PinkCat (via Play) released after ~3 s "NO LONGER angry"; SamuraiDog
         reached 51% during it and kept following. Whether they attacked
         after release: awaiting Dragón.
       - SUSPECT: the release goes through `Combat.StopFollowing` (the
         betrayal path), which could not remove the follow action ("still
         installed = true") and fell back to `Trainer = the Pal itself`. That
         left a self-trainer follow action on three wild Pals, where before
         today this path ran only on rare betrayals. A real follower was also
         present. Unproven; proposed A/B: follower-only + quit vs
         brief-follows-only + quit.
       - CuteFox release: "no readable sensor, friendly preset not written".
       - **Dragón's answers:** he quit the world and loaded it again → crash
         (the pass-285 world-change pattern). He then ran the A/B: **a real
         follower alone + quit/reload also crashes**, so the brief-follow
         release is NOT required — the world-change crash is back in the dev
         build. He is now testing the SHIPPED 1.1.2 Workshop copy (verified
         byte-identical to release/workshop, local dev copy disabled by
         renaming dwmapi.dll and enabled.txt to *.MODS-DISABLED) to see
         whether players are exposed, i.e. whether 1.1.2's microstutter work
         (PlayerRef keeping the player reference, hook-fed nameplates) brought
         it back.
       - Behaviour: the cat (PinkCat) visibly stopped attacking after its
         brief follow. The others reached the bond in one pet — Dragón's
         diagnosis: while a Pal is briefly treated as following, it gets
         passive friendship on top of the pet (he named the game's own +10;
         note also this mod's own follower passive gain in tick_followers).
         SamuraiDog went 50 → 51% during its 3 s brief follow. To fix: no
         passive gain during a brief follow.
     - As the log read it: the
       companion Lamball joined the player's fight against another Lamball
       (HATE-ASSIST), a hostile Chikipi attacked the companion Lamball
       (SELF-DEFENCE), the companion Lamball hit the new companion Chikipi
       once (FRIENDLY-FIRE), and that Chikipi ran up to ~1650 away while
       "fighting".
1. **DONE in v1.1.2 — Microstutters reported by a real user** (Goldaer,
   Workshop comment, 2026-09-14, against 1.1.0). Record kept below and in
   "Known open defects" #0. **Started 2026-09-15, plan agreed with Dragón.**
   Dragón confirms he feels the stutter himself with the mod active and had
   grown used to it. Note for when the next player reports anything: the
   `[RADIAL-REDIRECT-PERF]` line covers only the radial menu, and the verbose
   debug log narrates events without timing them — neither finds a stutter.
   The agreed plan:
   1. **Baseline, no code:** PresentMon (`Proyectos\_tools\PresentMon\PresentMon-2.5.1-x64.exe`,
      Intel-signed, needs elevation → a UAC prompt on Dragón's screen) records
      every frame to `perf-captures/` (gitignored). Same spot, standing still,
      2 minutes, PalBonds ON vs OFF (OFF = rename the dev install's
      `enabled.txt`; UE4SS stays loaded). Analyse spike count, 1% lows, and
      the spike **rhythm**.
   2. **Profiler: BUILT 2026-09-15.** `Scripts/Profiler.lua`, switch
      `local PROFILING = false` (shipped). When true, `main.lua` (which requires
      it FIRST) wraps the UE4SS globals — `RegisterHook`, `RegisterKeyBind`,
      `ExecuteInGameThreadWithDelay`, `ExecuteWithDelay`, `ExecuteInGameThread`,
      `LoopAsync`, `LoopInGameThreadWithDelay`, `NotifyOnNewObject`, plus the
      world searches `FindAllOf` / `FindFirstOf` / `StaticFindObject` — so
      every hook, timer and search in every module is timed with no module
      edits. Hooks are named by path, timers by source `File.lua:line`,
      searches by class. Manual `Profiler.start()/stop()` sections only in the
      personality scan (GetFullName / GetOrInitState / try_enforce per Pal) and
      the nameplate sweep (install_trust_bar loop, update_trust_bars). Output:
      `palbonds-profile.log` (gitignored by `*.log`), one report per 10s —
      per system calls / total / avg / max / >=8ms / >=16ms, then every call
      >= 8ms as a STALL line; times are inclusive. Each report prints os.clock
      elapsed next to wall elapsed: **if they disagree, the durations are not
      trustworthy** (see the os.clock doubt in Profiler.lua's header).
      Tested by `tools/harness/profiletest.js` (37 checks), which was verified
      to fail against two deliberately broken wrappers (returns dropped;
      report written mid-callback). fengari has no `io.open`, so the test uses
      an in-memory one.
      **Dev install has it ON** (only `Profiler.lua`'s switch line differs from
      `mod/`). **RELEASE WARNING:** `main.lua` now requires `Profiler.lua`, so
      `release/PalBonds/` and `release/workshop/PalBonds/` MUST get
      `Profiler.lua` with the switch OFF at the next release, or the mod fails
      to load.
   3. **One measured run** with profiler + PresentMon at the same spot.
   4. **Fix causes, never cut features.** Leading suspects, unmeasured:
      the 8s personality scan (`FindAllOf("PalCharacter")` +
      `FindAllOf("PalPlayerCharacter")` + a `GetFullName()` per Pal — the
      radial menu's own `FindAllOf("PalCharacter")` scan measured 36-74ms),
      the 2s nameplate sweep (`FindAllOf("WBP_PalNPCHPGauge_C")`), the ~2s
      Trust player-cache `FindAllOf`, and the always-on
      `SelectResponseBySenses` hook. Likely direction, to be confirmed with
      Dragón after measurement: track Pals and nameplates from the hooks
      that already hand them to us, so world-wide sweeps become rare safety
      nets. Confirm any suspect with an **in-session toggle**, not two runs.
   5. **Re-measure**, Dragón judges the feel, then 1.1.2 under the usual rules.
2. **Settings screen** decision: where the F9/F10 toggles and balance knobs
   would live. The last part of the Polish category.
3. **Multiplayer** only if Dragón wants it (see Pending).
4. **Bonded-Pal despawn** — parked as a known limitation, see below. Worth
   revisiting only with fresh eyes and a specific new idea, not by
   re-running the experiments already recorded there.

Deliberately NOT next: the controller swap (see "Two routes to the right
brain"), a fallback only, and the current approach works.

## KNOWN LIMITATION: bonded wild Pals despawn when you travel far — parked 2026-09-14

Dragón's call after a long, thorough investigation: *"i think we will leave
this as a known limitation that maybe in a future with a fresh mind we can
fix."* **None of the code from that investigation shipped.** The whole
experimental tree is preserved at
`stale/2026-09-14_despawn-investigation-scripts/` if any of it is ever wanted
again; the release build is clean v1.1.0 plus only the owned-Pal tag fix.

### What the symptom actually is

A bonded (following, not yet captured) Pal vanishes once the player travels
far enough from where she was bonded. She is **not** drifting, **not** being
abandoned, and the player does **not** need to teleport or change maps.
Dragón watched it happen directly, many times, while she was following
normally right beside him.

### What is now CONFIRMED, with evidence

1. **The despawn is a gameplay call, not engine streaming.**
   `UPalCharacterManager::DespawnCharacterByHandle` was hooked read-only and
   caught the real call live, on a Pal being tracked, `isFollowing=true`.
2. **Distance from the player is irrelevant.** Measured at the moment of
   death across three separate runs: **978**, **1564**, and ~1500 units —
   ordinary following range every time.
3. **She is in the persistent level; only her SPAWNER is in a streamed cell.**
   ```
   Pal:     .../PL_MainWorld5.PL_MainWorld5:PersistentLevel.BP_FlowerDoll_C_...
   Spawner: .../PL_MainWorld5/_Generated_/MainGrid_L0_X-7_Y6_...:PersistentLevel.BP_PalSpawner_..._UAID_...
   ```
   Cell streaming destroys the spawner; gameplay code then despawns the Pals
   that spawner owned. (Confirmed against Epic's World Partition docs:
   runtime-spawned actors in the persistent level are not unloaded by cell
   streaming.)
4. **The spawner object is rebuilt fresh on every visit.** Two probes at the
   same landmark, before and after travelling away, returned the same class
   and grid cell but different instance suffixes (`..._1932335164` vs
   `..._1932343169`).
5. **Her identity SURVIVES the despawn.** At +3s and +15s after the despawn
   call: `handle valid=true, parameter readable=true, friendship=74` (and 60
   for a second Pal). The `UPalIndividualCharacterHandle`, the
   `UPalIndividualCharacterParameter` and her real accumulated friendship all
   outlive the actor. **This is the most promising fact for any future fix.**
6. **No live actor remains.** `TryGetIndividualActor` returns a Lua wrapper
   around a NULL UObject (`actorIsValid=false`, location unreadable) — the
   same null-wrapper trap `Personality.lua`'s header already documents.

### Dead ends — do NOT re-run these

- **`RemoveGroupCharacter` at bond time** (detach her from the spawner's wild
  group). Ran clean, returned ok, changed nothing. The wild GROUP list and the
  spawner's SPAWNED-handle list (`GetAllSpawnedNPCHandle`) are different
  things, and despawn travels by handle, not by group.
- **Periodic re-homing to the nearest spawner** (`AddGroupCharacterByGroupId`,
  then `AddGroupCharacter`). Worked exactly as designed — correct wild-Pal
  spawners, correct remove-then-add sequencing, tracked her across 4+ grid
  cells over 2 minutes — and she still despawned. Logical group membership
  does not protect the actor.
- **Home-radius mitigation** (stop her before she reaches the danger zone,
  with a toast). Built and working, but **rejected by Dragón for a real
  design flaw**: the radius is anchored to wherever the player stood when
  bonding started, not to the zone's actual centre, so a player who bonds
  near a corner still loses her well inside the "safe" budget. *"which will
  eventually lead to players still finding the pals can despawn."*
- **Blocking the despawn call from Lua.** Not possible: UE4SS's Lua
  `RegisterHook` has no cancel/veto (verified against the official docs and
  the Palworld modding wiki — return values can be overridden, execution
  cannot be skipped).

### Two crashes came out of this, same signature — read before trying again

`EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000048`, twice,
both immediately around `AddGroupCharacterByGroupId`. The second one was
pinpointed exactly: the log's final line was the "removing from previous
spawner" message with no matching "re-homed to" line after it. The constant
across both was that function's third parameter — an `FString DebugName`
being **constructed fresh from a Lua literal** and passed into a native call.
That is the same root-cause category as this project's older "Crash #4"
(`docs/hook-points-archive.md`). Switching to the plain
`AddGroupCharacter(handle)` — no string, no constructed value — stopped the
crashes completely. **Standing rule reinforced: never build a value from
scratch in Lua to hand into a native call if a no-argument variant exists.**

### If this is picked up again, start here

The identity surviving (point 5) is the whole opportunity. The route is
`UPalCharacterManager::SpawnCharacterByHandle(Handle, FNetworkActorSpawnParameters, callback)`
— respawn the SAME individual, with her real trust intact, rather than
preventing the despawn at all. Two cautions:
- `FNetworkActorSpawnParameters` is a 0x78 struct containing an `FName` and a
  `TSubclassOf<AController>`. **Omit the `FName` rather than construct one** —
  a zeroed field is `NAME_None`, which is safer than the conversion that
  caused both crashes.
- Its `ControllerClass` field is interesting on its own: a respawn through it
  could in principle bring her back running `BP_MonsterAIController_Otomo_C`,
  the "right brain" this project has wanted since the controller finding.
- A simpler-looking alternative, `UPalOtomoHolderComponentBase::ActivatePalByHandle(Handle, FVector, FRotator, bool)`,
  needs no risky parameters at all, but is the Otomo-holder path and most
  likely requires her to be party-owned — the early-capture trade-off Dragón
  has already declined twice.


## Where the real detail lives

`docs/hook-points.md` is the technical log, pass by pass, with the exact class
and function names and what each experiment proved. It is the file to search
when you need to know whether something was already tried. `CLAUDE-archive.md`
holds the older narrative history. `DESIGN.md` holds the original design; note
that its §12 "Priority TODO list" is marked SUPERSEDED and should not be used to
judge current state — **check the code, not the planning docs.**
