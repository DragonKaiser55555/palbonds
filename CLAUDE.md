# 32 — PalBonds (behaviour mod for Palworld)

**Progress: 100%**

Dragón's ruling (2026-09-23): *"we are already past the 1.0.0 version, which I
would consider as the 100% - all the rest of things are just extras and add-ons
to the mod"*. The global rubric agrees — 100% is "finished and uploaded to its
platform(s) for users" — and PalBonds has been live on the Steam Workshop, Nexus
and GitHub since 1.1.0. Everything since is post-1.0 extras, tracked in **OPEN
WORK** below, not as missing percentage.

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
| Polish and configuration | 5% | 100% | 5% |

Following and personality stay at 95% for the spawner-despawn limitation.
Polish reached 100% at 1.1.9, when the in-game settings screen shipped — it was
the last item that category was waiting on. Recalculate whenever a category
moves, and keep the `Progreso:` line of this project's block in
`../game proyects.txt` in sync.

---

## HOW TO READ THIS FILE

This file holds **current truth only**: what is live, what is open, and the rules
and decisions that still bind. It is meant to be read completely, in one call,
at the start of any session.

Everything dated — how a bug was chased, what a test run showed, why a decision
was reached — lives in `CLAUDE-archive.md` and `docs/hook-points.md`. Those are
history. **Never take status from them**: several of their sections describe
problems that have since shipped fixes.

This split exists because the opposite arrangement failed on 2026-09-28: the
boss-defeat fix, live since 1.1.6, was reported to Dragón as open work because a
session read a superseded "STILL OPEN" line and stopped there. His standard:
*"leave open only whats open, close what is close, move to the archive what is
already past history and only keep whatever we still have left."* Keeping this
file honest is Claude's own job — not something to ask him about. When a fix is
verified, close it here in the same pass; when an item can no longer be observed
or reproduced, close it too.

---

## HOW TO MAINTAIN THIS FILE — READ BEFORE WRITING ANYTHING INTO IT

Dragón asked for these rules to be written down (2026-09-28) so the file does not
rot back into the state it was just rescued from: *"i want you to clarify that in
your mds for future updates, so your future selves dont contaminate with trash
again and we have to go all over this once more."*

The failure being prevented is specific. This file had grown to 4,881 lines of
dated session narrative mixed with current status. It was too long to read in one
call, so a session would read part of it, land on a plausible-looking dated
section, and report whatever that section said. On 2026-09-28 that produced two
wrong reports in a row: the boss-defeat fix (live since 1.1.6) named as open
work, and three unrelated player crash reports presented as one active bug. Both
were in the file. Neither was true.

**The nine rules.** They are not stylistic; each one closes a way this went
wrong.

1. **This file holds current truth only** — what is live, what is open, and the
   rules and decisions that still bind. Nothing else belongs in it.
2. **Keep it readable in one call.** It is ~690 lines. Treat **900 as the hard
   ceiling**: past that, archive, never trim meaning to fit. A file that cannot
   be read completely will eventually be read partially, and that is the bug.
3. **Never add a dated section here.** No "RUN 4 RESULTS", no "BUILT
   2026-XX-XX", no "MILESTONE 7", no session logs. Dated narrative goes to
   `CLAUDE-archive.md` (what happened and why) or `docs/hook-points.md` (the
   technical pass log). If you catch yourself typing a date into a heading in
   this file, you are writing in the wrong file.
4. **Finish work in one pass: ship the change, update the status here, move the
   story out.** The rot happens when the fix lands and the account of the fix
   stays behind. Closing an item is part of finishing it, not follow-up.
5. **Never annotate stale content — delete or archive it.** Dragón rejected the
   annotate-it approach explicitly: *"you left an aclaration in the mds, but what
   makes you believe that your future self wont misinterpret or read it as how
   you try to mean it?"* A warning only works if the next session reads it and
   honours it, and reading partially is the failure. Leaving stale text with a
   label on it gives a future session something wrong to find.
6. **Closing criteria, so nothing lingers as "watching":** fixed and not
   recurring over a release or two → closed. Cannot be observed or reproduced →
   closed. Explained by something outside the mod (a player's loader build, their
   other mods) → closed, with the explanation. *"We open new things if we find
   them."* Reopening later is cheap; carrying an item forever is not.
7. **Verify before writing a fact here.** Counts, paths, versions, file names and
   switch states get checked against the code and the filesystem in the same
   pass, not recalled. The old file claimed 8 scripts when there were 15, and
   7 `LoopAsync` fallbacks when there was 1.
8. **Take status from this file and the code — never from the archive.** If the
   two disagree, the code wins and this file gets corrected immediately.
9. **This maintenance is Claude's own job.** *"housekeeping: thats up to you to
   do, idk what you're waiting from me."* Do not bring it to Dragón as a
   proposal, and do not wait to be asked.

**The check that matters** is not whether the edits were made — it is behavioural:
after updating, ask what a session reading *only this file* would say is open,
and whether that answer is right. That is the test Dragón applies, because it is
the only one he can see.

**The same discipline covers the other docs.** `README.md` kept promising an
in-game settings screen as a future feature for a full release after it shipped,
and `DESIGN.md` pointed at a section of this file that no longer existed. When a
release changes what players do, the same pass updates `README.md`,
`release/PalBonds/README.txt` and any pointer between docs — and store
descriptions only when Dragón says so.

---

## STATUS — 2026-09-28

**v1.1.9 is live.** Nexus (file "PalBonds V1.1.9", 124 KB), Steam Workshop
(item 3797816321, updated 27 SEP) and GitHub (`7d06b65`, working tree clean).
CurseForge has it queued — **1.1.8 is still not approved there**; their
moderation is far behind and there is nothing to chase.

**GitHub has no open issues.** Issue #1 (Esaeon) is closed and is still the only
one ever filed.

**What 1.1.9 was:** the in-game settings screen, the removal of ~154
`RegisterKeyBind` key watchers that were corrupting the Lua VM, and a fix for an
unbounded trust-bar leak (0 → 603 tracked entries in 14 minutes, now flat at
11–21).

**Performance, measured honestly:** 1.1.9 is **level with 1.1.8, not faster** —
better on average and p99, slightly worse at the extreme tail, hitches about the
same, all within run-to-run variation. Opening the settings screen costs nothing
measurable. Do not let a changelog claim a performance win.

**Dragón's machine right now:** the local dev stack is **DISABLED** —
`Pal/Binaries/Win64/dwmapi.dll` and `Pal/Content/Paks/LogicMods/CreativeMenu.pak`
are both renamed `*.MODS-DISABLED`, so he is playing the Workshop build.
**Re-enabling it is his call, never Claude's** — two loaders crash the game.

**One thing is deliberately out of sync:** `release/PalBonds/README.txt`
describes the in-game settings screen, but the README inside the shipped
`PalBonds-v1.1.9.zip` does not. The zip was not rebuilt and nothing was
re-uploaded. **Rebuild the zip when 1.2.0 is packaged.**

---

## OPEN WORK

This is the only list that says what is open.

### Agreed, not started

1. **Releasing bonded Pals back into the wild.** Swordfish's request, and the
   only unbuilt feature request left. Dragón calls it *"an extra out of scope
   from this project"*, so the timing is his — but he confirmed on 2026-09-28
   that it is genuinely open and the one he agrees with.
2. **Performance polish**, under his standing rule *"the idea is that we polish
   it as much as we can"*. The three named costs, largest first:
   - the ~64 s personality safety scan — 115–155 ms in a single frame, the worst
     remaining stutter;
   - each feed — 100–146 ms;
   - `find_targeted_pal`'s world sweep — 40–80 ms, but already cached
     one-in-four (`PAL_SCAN_CACHE_MAX_AGE = 4`), so paid roughly once per two
     seconds of held-open radial menu, not per call. The geometry re-runs every
     call and is cheap.

   The route for all three is the one that worked in 1.1.2, and it does not
   touch the feature: take the candidates from a hook that already fires —
   `Personality.ForEachKnownPal` is filled for free by the sense hook — and keep
   `FindAllOf` as a rare safety net and as the fallback when that set is empty.
   It must fail open to the sweep, never replace it. Proposed 2026-09-28,
   awaiting Dragón's call; worth one capture to size before building.
3. **Store descriptions: a TRIM, planned around 1.2.0.** Not an addition — the
   descriptions are already long enough that players skip them. Dragón finished
   the Workshop translations himself on 2026-09-28.

### Waiting on somebody else — do not chase

4. **Hakaishin Beerus' crash.** The only crash report never explained. They have
   been asked several times to open a GitHub issue and have not. Dragón's
   ruling: *"we cant stop a whole proyect for 1 person."* The trace build that
   would answer it is already public — GitHub pre-release `v1.1.6-test2` with
   `docs/crash-testing-guide.md` attached. Nothing to do until they act.
5. **Co-op, untested by anybody:** two real players at once, claims, one player
   leaving mid-bond, a host who also plays, and the dungeon resync. This needs a
   second person, not more code. Shipped in 1.1.7 on the reasoning that players
   become the test.

---

## CLOSED — do not raise these as open work

Each of these was carried as "open" long after it stopped being true, which is
what made this file untrustworthy. They are listed so nobody re-derives them.

- **Boss joins now count as defeated.** Solved run 9, 2026-09-19; shipped 1.1.6.
  `ForceDamageDelegateForCaptureBall` registers the player as an attacker with
  no damage, so the game writes the defeat record and pays the first-kill reward
  itself — and refuses a second payout on a boss already beaten, which was
  Dragón's requirement. Five other levers were disproven first (last attacker
  both fields, the hate table, `IsCapturedProcessing`); do not retry them.
- **The stuck waiting pose after a failed pet or feed.** Fixed through run 7,
  2026-09-19, and never seen since. Closed by Dragón, 2026-09-28: *"how do we
  chase something we cannot see? ... just close it already, we open new things
  if we find them."*
- **Esaeon's crash.** Theirs was the UE4SS build (`c838a8ac`, 15 July);
  updating to Okaetsu's `2281fa31` fixed every one with no PalBonds change.
- **Swordfish's crash.** Reported once as rare, against 1.1.5-era code, never
  mentioned again.
- **Microstutters** (Goldaer) — fixed in 1.1.2 and re-measured: idle with the
  mod on came back within noise of the mod turned off.
- **The in-game settings screen** — shipped 1.1.9.
- **The three gameplay hotkeys still on `RegisterKeyBind`.** NOT work. Dragón's
  ruling, 2026-09-28: nobody has ever reproduced a crash on them, the three
  reports it was theorised from are each explained or stale, and **a matching
  error code is not a matching bug**. Do not propose fixing a crash that exists
  only as a theory.
- **Bonded Pals despawning when you travel far** — a known limitation, stated
  openly in the store descriptions. See its own section below.
- **Hotkeys firing while typing in chat** — declined 2026-09-14, F8/F9/F10 are
  hardly touched while typing. Do not propose again.
- **Alpha Mammorest clipping through the floor** — base game (Pals align to the
  player's facing axis on uneven terrain), answered on Nexus 18 Sep.

---

## What this mod is

Instead of only capturing Pals by force, the player walks up to a wild Pal and
pets, feeds and plays with it. A per-individual trust value rises with good
treatment and slowly while the Pal follows. Cross 20% and its personality turns
friendly; cross 50% and it follows and defends the player; fill the bar and it
joins the party on its own, with no sphere thrown. Hit it yourself, or leave it
too far behind, and you lose it.

Nothing new is authored — no models, textures or animations. Everything reuses
behaviour the game already has.

**Scope:** singleplayer, co-op and self-hosted dedicated servers (co-op since
1.1.7). Official Pocketpair servers still do not allow mods, and modding there
risks a ban.

**Stack:** UE4SS (Okaetsu's experimental Palworld build) with all logic in Lua.
Guessing UE4SS API names has cost four test cycles here, so check the API docs of
the exact installed commit rather than working from memory or a strings grep of
`UE4SS.dll` — both have produced wrong names. Those docs are NOT checked into this
repo (a `docs/lua-api/` reference here was stale); read them from the UE4SS
release for the installed commit, or prove a binding exists with a pcall probe in
game.

**Note on builds:** the dev machine runs `ba2efd55`, the Workshop dependency
installs `2281fa31`. We develop on a build no player necessarily runs.

### What it does, confirmed in live play

- Pet, feed and play on wild Pals through the game's own radial menu, plus the
  Play hotkey, with the player's cheer ending together with the Pal's animation
- Trust bar and personality tag under the wild Pal's health gauge, and under the
  boss HP bar for bosses (alpha, predator, tower and raid)
- Seven personalities rolled per individual, with player-facing names; owned
  Pals never roll and never show a tag
- Bonded Pals follow, stay *behind* the player, and hold still while aimed at
- Combat assist via the Hate system, and self-defence when a companion is
  attacked outside the player's fight
- Feed trust by food rarity (50 + 10..50); Kinship Peaches keep 250 / 500
- Level-scaled bonding bar; boss Pals need twice the trust
- Sphere-less joining, with a celebration animation, a join VFX, a named toast,
  and a flat +50000 friendship head start
- A boss bonded through the mod counts as defeated and pays the first-kill
  reward once, exactly as a sphere catch does
- Betrayal (player hits the Pal) and bond loss by distance
- An in-game settings screen under ESC → PalBonds, changing every setting live,
  including rebinding the three hotkeys
- 16 languages

---

## Where things live

```
32-PalBonds/
  CLAUDE.md            <- this file: current state, rules, open work
  CLAUDE-archive.md    <- all narrative history. NEVER read for status.
  DESIGN.md            <- the original design (its §12 TODO list is SUPERSEDED)
  README.md            <- repo readme (GitHub-facing)
  mod/PalBonds/        <- dev tree, the source of truth
  release/PalBonds/    <- release staging, stripped from mod/
  release/PalBonds/README.txt       <- the readme that ships to players
  release/workshop/PalBonds/        <- Workshop package mirror (Info.json, thumbnail, Scripts)
  release/nexus-description.txt     <- Nexus description (BBCode)
  release/workshop-description.txt  <- Workshop description
  release/PalBonds-v1.1.9.zip       <- the shipped package
  release/test-build/               <- trace builds published to players for crash reports
  tools/harness/       <- offline fengari test harness (node_modules gitignored)
  tools/perf/          <- PresentMon capture and analysis scripts
  perf-captures/       <- frame captures and profile logs (gitignored)
  save-backups/        <- real save data backups (gitignored)
  docs/hook-points.md  <- the technical pass-by-pass log: the real detail
  docs/bug-reports/    <- player logs and crash dumps as received
  images/              <- Steam Workshop screenshots
  stale/               <- archived, not part of the product (gitignored)
```

**There are 15 scripts**, identical in `mod/PalBonds/Scripts/` and
`release/PalBonds/Scripts/` (the latter comment-stripped): `main`, `Logger`,
`Personality`, `Interaction`, `Trust`, `Combat`, `Capture`, `Indicator`,
`PlayerRef`, `Settings`, `Locale`, `Menu`, `Net`, `HostView`, `Session`.

**Live game install (manual dev):**
`...\steamapps\common\Palworld\Pal\Binaries\Win64\ue4ss\Mods\PalBonds\`

**Workshop install (what players get):**
`...\Palworld\Mods\NativeMods\UE4SS\Mods\PalBonds\Scripts\`

`stale/` holds the third-party reference mods. They are worth re-reading before
building anything new — a working reference is as authoritative as an engine
feature, and this project has twice rebuilt from scratch something a reference
mod already solved.

---

## Working procedures

### Deploying a change

Copy the changed `.lua` to **every** copy — `mod/`, both release trees, the
manual live install, the Workshop content folder AND the Workshop native-mods
copy — and confirm with `md5sum` that they match. A change that is only in
`mod/` has not been tested by anyone, and a change that reaches everywhere
except the copy the game actually runs looks exactly like "the fix didn't work"
instead of "the fix never ran". That has already cost a full test cycle, and in
one case Dragón nearly test-ran a build a whole version behind.

### RELEASE GATE — no version ships without these, in order

1. `mod/` is the source of truth; the package is built from it
   (`tools/strip-comments.py`), never edited by hand.
2. All suites pass **against the built release tree**, not only `mod/`.
3. **Dragón runs the exact package in game** and says it works. A green harness
   proves the code behaves the same under stubs; it cannot prove the mod loads,
   that the hooks register, or that anything appears on screen. Until that run
   happens the honest words are "packaged, needs a smoke run".
4. Only then: stores, then GitHub.
5. **The live version's artifacts stay untouched until its replacement is
   actually live** — zip, release trees and tag. While a version is serving
   players it is the rollback and the reference for any bug report about it.

### Shipping a release — the full checklist

1. `mod/` clean: every ship switch off (`DEBUG_LOGGING`, `SHOW_DIAGNOSTICS`,
   `TRACE_PHASES`, `ACTION_CHANGE_PROBE`, `PROFILING`), no temporary flags, no
   diagnostic-only files. Dragón's rule: *"WHEN WE SHIP, NOTHING OF THAT MUST
   REMAIN — no logs, no trash, no extras."*
2. `python tools/strip-comments.py mod/PalBonds/Scripts release/PalBonds/Scripts`,
   then copy those files to `release/workshop/PalBonds/Scripts` and confirm the
   two trees are md5-identical.
3. Bump `release/workshop/PalBonds/Info.json` `"Version"`.
4. `sh tools/harness/runall.sh release/PalBonds/Scripts` — a stripped build is a
   build nobody has tested.
5. Zip with **forward-slash entry names**. PowerShell's `Compress-Archive`
   writes backslashes; build it with Python's `zipfile` instead.
6. **Two pieces of text, both needed, both Dragón's to approve:**
   - a **changelog**, ONE LINE PER ITEM, prefixed `New:` / `Balance:` / `Fixed`;
   - a **short description**, one or two sentences, the blurb on the file entry.
   Draft both. Never claim more than has been measured, never promise fixes or
   dates, and never word something so players read it as a feature they have
   been asking for.
7. Nothing is uploaded, committed or pushed without him saying so, per store.

### Verifying a change — before asking Dragón to test

There is no Lua interpreter on this machine, but `fengari` (a Lua 5.3 VM in
JavaScript) runs the **real mod source** with the UE4SS globals stubbed:

```bash
cd tools/harness && npm install fengari
sh runall.sh ../../mod/PalBonds/Scripts
```

It cannot prove gameplay behaviour. It has still caught bugs no test run could
have distinguished from "it didn't work again": a loop early-out that disabled
the recall for exactly the Pal that needed it; a call placed 850 lines above its
definition (a nil global, swallowed silently); a damage gate that switched
combat assist off completely.

**The rule: a regression test must be run against the broken code too.** A test
that passes both before and after a fix proves nothing. Every bug-driven suite
in there was verified by reverting the fix in a throwaway copy and confirming
the test fails. Do the same for the next one.

### Publishing safety

Dragón, 2026-09-14: *"the idea is that we dont upload things we havent checked
yet... we cant risk something breaking the game for others."*

- `steamapps\workshop\content\1623730\3797816321\` is a **local folder**. It is
  both his subscription and the uploader's source. Deploying fixes there for him
  to test is expected and reaches nobody. Only running the Mod Uploader
  publishes.
- Never run, or suggest running, the Mod Uploader, a release `git push`, or the
  Nexus upload flow unless Dragón asks for that specific step, separately from
  "deploy this so I can test it".
- **One step at a time.** When he names a later step alongside the current one
  ("check the Nexus page, then we do the Workshop"), that describes the order of
  work — it is not authorisation for the second half, including the read-only
  prep, which from his side looks identical to starting it.
- **Ask before every git commit and push**, even small ones.

### Publishing procedure — both stores

**Nexus (mod 5623).** Use **Update** on the existing file's row, never "Add
file" — Update archives the old version and notifies everyone who downloaded it,
including Vortex. Tick **"update mod version to match"**, or the page header
keeps advertising the old version. Fill the changelog; it is what Vortex shows
at the update prompt.

**Steam Workshop (item 3797816321).** Replace EVERY script from
`release/workshop/PalBonds/Scripts/`, bump `Version` in `Info.json` **in place**,
leave `.workshop.json` untouched, then Dragón runs the Palworld Mod Uploader.

- `.workshop.json` holds `publishedfileid` and is the only thing tying the local
  folder to the published item. Lose it and the uploader publishes a DUPLICATE
  mod page.
- **Reload the uploader** if it was open while files changed; it reads
  `Info.json` at scan time, and uploading with stale data pushes new scripts
  under the old version number.
- `last_published_version` in `.workshop.json` is **not** a reliable publish
  check — it has lagged twice. Read the item's change-note page instead.
- `MinRevision` is a floor, not a pin; a Palworld update does not require
  changing it.

### Turning mods off

When Dragón says to disable the local mods, he means the **entire local dev
stack including the loader**, not just PalBonds. Rename, in
`Palworld\Pal\Binaries\Win64\`: `dwmapi.dll` → `dwmapi.dll.MODS-DISABLED`. That
single file is UE4SS's proxy DLL, so without it no Lua mod runs. Also check
`Pal/Content/Paks/LogicMods/` and `~mods/`, and that no other proxy DLL
(`xinput1_3`, `d3d11`, `version`, `winmm`, `dinput8`, `bink2w64`) is present.
**Switching the stack back ON is his call, never Claude's** — two UE4SS copies
loading at once crashes the game.

---

## Rules bought with crashes — do not "simplify" any of them

### Threading

**UE4SS's `main_lua`, `hook_lua` and `async_lua` are coroutines off ONE
`lua_State`, sharing one `global_State` and one GC, with NO LOCK** (narknon,
UE4SS issue #1345). A `RegisterKeyBind` callback runs on UE4SS's **own thread**,
so any Lua it executes races the game thread. Marshalling to the game thread
*inside* the handler is too late — the code before the hop has already run
off-thread. This is what ~154 key watchers were doing in the pre-1.1.9 settings
screen, and it produced `LUA_ERRERR`, ten hook calls that entered and never
returned, and a death inside a hook's own `Context:get()`.

Hooks registered on game functions fire inside the game's own call stack and are
safe. Every keybind body hops to the game thread before touching anything.

**`LoopAsync` is unsafe** — a UE4SS collaborator says so plainly. One dead
fallback using it remains, in `Combat.lua`.

### Native calls

- **Never build a value from scratch in Lua to hand into a native call if a
  no-argument variant exists.** Two crashes came from an `FString DebugName`
  constructed from a Lua literal; switching to the no-string variant stopped
  them completely.
- **CALLING a function that moves an FKey-bearing struct by value across the Lua
  boundary kills the process** (`AV 0x70`). **HOOKING one and READING the FKey**
  as a parameter or UObject property works — reading goes through UE4SS's
  property path, calling marshals a struct it cannot build. A struct with no
  reflected members (`FKeyEvent`) fails as a catchable Lua error instead.
- **Read everything you need from a Pal BEFORE `PalCaptureSuccess` runs.** The
  actor is torn down during capture and every component read fails afterwards.
  This bug has been introduced twice — resolve names and handles up front and
  pass them along as plain values.
- **A UE4SS `FName` prints as `FNameUserdata: <address>` under `tostring()`.**
  The text comes from `:ToString()`. A whole probe round was lost to forgetting
  this.

### Building UI inside the game's menus

1. **Never build inside the `NotifyOnNewObject` callback.** The engine is still
   assembling the menu; mutating it there is `AV writing 0x80`. Wait 50 ms on
   the game thread.
2. **Only ever add a child to a `CanvasPanel`.** Adding to a `VerticalBox`
   reflows the whole column on the engine's NEXT layout pass, after our Lua has
   returned, so there is nothing left to `pcall`. That killed DarnMenu three
   times out of three under ESC-spam.
3. **Never `RemoveFromParent` on a menu we no longer own.** A replaced menu
   lingers and keeps painting; touching its children AVs. The engine frees our
   widgets when it destroys the menu — simply forget them.
4. **Never write `.Text = "string"` directly** — it crashes this game (our own
   crash, 2026-09-04). Text goes through the game's own `BP_PalTextBlock_C` and
   `SetText_GDKInternal`, which also makes the font and colour match the menu.
5. **Build the page on the FIRST CLICK, never ahead of time.** Widget churn
   inside an open menu is DarnMenu's crash family.

### Timers and retries

**Never budget a retry from mod load.** Mod load happens on the title screen. A
Blueprint hook (`/Game/...`) cannot register until that class is loaded, which
does not happen until the player is in a world — and that can be ten minutes
later. Native hooks (`/Script/...`) register immediately, which is why
personality enforcement keeps working while nameplates and the radial menu
quietly do not. Two separate test runs were lost to bounded windows anchored at
mod load: nameplates needed round 136 of a 30-round window; the radial menu gave
up four and a half minutes before Dragón's world existed, so he could not
interact with any Pal for the whole session.

**Any counter that latches something off permanently is wrong** unless the thing
it guards is genuinely unrecoverable — that shape once lost a Pal mid-session.
Leak guards are rolling rates (N per window, recovers when the window turns
over), never lifetime allowances.

**If a bug class is found, grep for the rest of the class before calling it
fixed.** `MAX_[A-Z_]*(ROUNDS|ATTEMPTS)` is the search that finds these.

### Gating global hooks

A hook that fires for every entity or event in the world must be gated on a
cheap check **before any reflection call**. World searches (`FindAllOf` /
`FindFirstOf`) are what stall a frame — a single one costs ~40 ms idle and
55–100 ms in play. Prefer objects a hook already handed us over anything
discovered by polling; keep world sweeps as rare safety nets, and make any such
optimisation **fail open** to the sweep.

---

## Decisions that are settled — do not re-litigate

- **Pet and Feed are radial-menu interactions, not keys.** Play keeps a hotkey
  only because it has no radial-menu equivalent yet.
- **Grumpy and Hostile stay separate personalities.** Dragón: *"while grumpy
  doesnt attack inmediately, it can attack if it sees another pal of its same
  species attacking, so kind of like they join — its an interesting
  personality"*. Do not merge them as a tidy-up.
- **The settings screen says FRIENDSHIP points; the toasts say TRUST.**
  Deliberate. His reasoning: *"they already know the base game as trust points
  and ranks, so if we call our bar 'trust' to modify, they may think they will
  be modifying the trust from the base game instead of our made up points"*. On
  the settings screen it must read as friendship points; in play, "trust" reads
  naturally with nothing to confuse it with. Asked directly about changing the
  toasts: *"dont think of changing the toasts messages"*.
- **Feed trust scales with item rarity; Kinship Peaches are the exception.**
  Feed = 50 base + 10/20/30/40/50 for rarity 0–4. Peaches keep 250 (lesser) /
  500 (full): *"they cannot be cooked or made, only found out, so it makes sense
  that those peaches are special things"*.
- **A low-level Pal bonding in a single interaction is intended, not a bug.** It
  mirrors how trivially a high-level player captures a low-level Pal normally.
- **No fallbacks that hide failure** while the project is in development. A
  failed read shows "unknown", never a plausible-looking default — a "friendly"
  fallback once made most Pals look friendly.
- **`ActionComponent:ActionIsEmpty()` is not a reliable "is busy" signal.** It
  reports empty in the gaps between steps of a real multi-part interaction.
  Three attempts to detect "the animation finished" failed on it. This is also
  why Play's target-busy gate refuses nearly every press — Dragón's call,
  2026-09-11: do not fix it in isolation, it belongs with giving Play a real
  implementation and a radial-menu entry.
- **Never propose removing a working feature to work around a bug.** Fix it, or
  ship with the limitation documented.
- **Never classify something as a known limitation on Claude's own judgment.**
  Dragón: *"dont mark stuff as known limitations unless i state it myself"*.
- **Ask about doubts; don't advance on interpretations.**

### Bonding and betrayal — Dragón's full spec (2026-09-18)

- **"Bonding is a status that starts or should start at 50% friendship."**
  Nothing before 50% is a bond. Any note saying the bond starts at the first pet
  is wrong.
- **Below 50%**, hitting a Pal is an ordinary fight: it defends itself normally,
  with no betrayal and no scarred status, because there is no bond yet. A player
  hit below 50% drops the bar to 0. Pal-vs-Pal damage never costs trust.
- **The 20% calm-down** happens for every Pal crossing 20%, not only hostile
  ones. A hit during it gets whatever reaction the species normally has — no
  forced "fight back". Afterwards the Pal acts completely normally, including
  getting angry again if hit. It still defends its own kind.
- **One forgiveness per Pal.** After that it is the player's carelessness —
  *"we can't let them abuse the poor pals"*. Crossing 20% a second time does
  nothing at all: no calm-down, no Friendly switch, it keeps its original
  personality. His reason: *"most pals will probably not survive too many hits
  from the player, so if we continue making them forgive or act differently, the
  pals will end up dying without having a chance to defend themselves with our
  meddling."*
- **When the bar drops to 0, the Pal returns to its ORIGINAL rolled
  personality**, tag and AI preset. A Hostile Pal reads Hostile again.

### The right brain — both routes ruled on (2026-09-12)

A party Pal runs `BP_MonsterAIController_Otomo_C`; a bonded wild Pal runs
`BP_MonsterAIController_Wild_C`. The game does not make party Pals behave well
by giving them better orders — it gives them a different AI controller.

1. **Capture the Pal earlier — REJECTED, do not propose again.** It would mean
   capturing when following starts instead of at full trust. Dragón: *"it would
   shorten the bond with the player, we would be losing betrayal, passive
   friendship gain, the toasts, etc — too many things just for one."* The
   bonding phase is the product.
2. **Possess the wild Pal with an Otomo controller — held in reserve.** *"lets
   leave it as a risky option if what you're currently doing doesnt work... if
   your method works, then that settles it."* Do not open it while the current
   method is still gaining ground.

---

## Retired approaches — do not resurrect

Each was killed by evidence, not suspicion.

- **Territory / leash following** (`SetupLeash`) — an inner radius tight enough
  to hold followers also caged them, so they could not reach an attacker or
  defend themselves. Also leaked leash actors.
- **The repeated Otomo composite** (`SetRootComposite` + `SetOtomoFollowAction`)
  — reported success every time and moved nobody.
- **`ABP_ReturnPalEffect_C` as the join VFX** — correlates only with switching
  active Otomo, never with a capture.
- **`SelectedFeedingItem` called cold** — crashed the game into an unresponsive
  but running state.
- **`OpenOtomoFeedInventory()`** — needs a real deployed Otomo, so a new player
  could never feed, never bond, never get a first Pal.
- **Guessing UE4SS API names.** `RegisterInitGameStatePostHook` is real;
  `…PostCallback` is not. Four wrong names cost four test cycles.
- **Subtracting hate to steer a target.** The player stayed most-hated
  immediately after `ChangeHate(-999999)`. Every fix built on it was a no-op.
  *Adding* hate works and is what combat assist uses.
- **`TargetActor` and `SetTargetAndNextAction`** on the running combat action —
  declared on `UPalAIActionCombatBase`, neither resolves on
  `BP_AIAction_CombatPal_C` in this build. Use `UPalHate::FindMostHateTarget()`.
- **Stopping a won-over Pal attacking by any means other than following.** Four
  mechanisms failed: `ChangeHate`, player slots set to Ignore, cancel+rest, and
  a friendly guard cancelling actions. What works every time is starting to
  follow — hate on the player drops within ~3 s.
- **Waking a sleeping wild Pal so it can be interacted with.** The game refuses
  the interaction, not us. The only routes are pushing an action on
  `UPalActionComponent` (the exact system behind crash #2) or paying for an
  interaction the player can see did not happen. If ever wanted, the route is
  research: find the game's OWN wake mechanism.

---

## Diagnostic traps that have cost real time

- **Lua errors do NOT appear in `palbonds-live.log`.** UE4SS prints them to its
  own console in red as `Error: [Lua::call_function] lua_pcall returned
  LUA_ERRRUN => ...`. The mod log only contains what `Logger.log` wrote, and a
  function that threw never reached its log line. **When Dragón reports red
  console lines, ask for the console text — do not refute it from the mod log.**
- **`SHOW_DIAGNOSTICS` is a separate switch from `DEBUG_LOGGING`,** and
  `Logger.log` silently drops anything matching `SUPPRESSED_TAGS`. A working
  session and a broken one once produced byte-identical logs because the cause
  was logged under a suppressed tag on both paths. **When a log cannot explain
  something it clearly should have logged, check the filter before theorising.**
- **Dragón's direct in-game observation beats a filtered log.** Two test cycles
  were spent concluding "it never ran" from a blind log, against what he could
  plainly see. When a log cannot distinguish two explanations, fix the log.
- **In dev, use whatever logging the work needs without asking** — it is his
  machine and his standing rule. Strip all of it at release.

---

## KNOWN LIMITATION: bonded wild Pals despawn when you travel far

**This is not a task.** Dragón, 2026-09-28: *"unless something completely new
arises, there's no goal here ... there's no real way to fix it without breaking
the flow of the mod."* It is stated openly in the store descriptions instead.
Do not reopen it with the ideas below — they are recorded so nobody spends
another session rediscovering them.

**The symptom:** a bonded (following, not yet captured) Pal vanishes once the
player travels far enough from where it was bonded — not drifting, not
abandoned, no teleport or map change needed.

**Confirmed:**
1. It is a gameplay call, not engine streaming
   (`UPalCharacterManager::DespawnCharacterByHandle`, caught live on a tracked,
   following Pal).
2. Distance from the player is irrelevant — 978, 1564 and ~1500 units at the
   moment of death across three runs, all ordinary following range.
3. The Pal is in the persistent level; only its **spawner** is in a streamed
   cell. Cell streaming destroys the spawner, and gameplay code then despawns
   the Pals that spawner owned.
4. **Its identity SURVIVES.** At +3 s and +15 s the handle, the parameter object
   and the accumulated friendship are all still readable. This is the only
   promising fact for any future attempt.

**Dead ends — do NOT re-run:** `RemoveGroupCharacter` at bond time; periodic
re-homing to the nearest spawner (worked exactly as designed, tracked across 4+
grid cells, still despawned); a home-radius mitigation (rejected — the radius
anchors to where the player stood, so bonding near a corner still loses the Pal
inside the "safe" budget); blocking the despawn from Lua (UE4SS's `RegisterHook`
has no veto — return values can be overridden, execution cannot be skipped).

**If it is ever picked up with a genuinely new idea**, the route is
`SpawnCharacterByHandle` — respawn the SAME individual with its trust intact,
rather than preventing the despawn. Omit the `FName` in
`FNetworkActorSpawnParameters` rather than construct one; constructing it is
what caused two crashes here. The experimental tree is preserved at
`stale/2026-09-14_despawn-investigation-scripts/`; none of it ever shipped.

---

## Player answers we already owe

**Auri cannot be bonded, and never will be.** She is not a character:
`BP_PalTalkableLevelObject_SkyBoss_C`, whose chain reaches `AActor` without ever
touching `ACharacter`. She is a *level object* — the same family as a warp point
— carrying a person-shaped mesh, with no capsule, no HP, no AI controller and no
`UPalIndividualCharacterHandle`. That explains every symptom: no nameplate, no
HP bar, spheres passing through her, and the mod's total silence (she is never
even a candidate to reject). Supporting her would not extend the mod; it would
be a second mod sharing the folder.

*The short answer for players:* Auri is not a Pal or an NPC in the game's code —
she is a scripted part of the scenery with dialogue attached, with no health, no
stats and no capture target, which is also why Pal Spheres pass through her.
PalBonds only works on things the game itself treats as Pals.

**Bonding takes time on purpose** (Dragón's own Nexus answer, 18 Sep): it scales
with level — a Pal at or above your level takes much longer, a much lower one
needs 2–3 interactions, and a Kinship Peach can be enough. There is **no
cooldown**; the options hide while the Pal finishes a base-game animation or
when you are not aimed at it. And you do not wait around: a Pal at 50% follows
you and keeps bonding while you farm or build.

---

## Species name mapping

Dragón refers to his Pals by their in-game species name; the code and logs show
the internal `CharacterID`/class name. **Check here before ever flagging a log's
species name as a mismatch.**

| Dragón's name | Internal class / CharacterID |
|---|---|
| Petallia | `BP_FlowerDoll_C` (boss form: `BP_FlowerDoll_BOSS_C`) |
| Tanzee | `BP_Monkey_C` |
| Flopie | `BP_FlowerRabbit_C` |
| Daedream | `BP_DreamDemon_C` |

---

## Where the real detail lives

- `docs/hook-points.md` — the technical log, pass by pass, with exact class and
  function names and what each experiment proved. **Search this before trying
  anything that might already have been tried.**
- `CLAUDE-archive.md` — the full narrative history, including this file's own
  earlier versions. History only, never status.
- `docs/bug-reports/` — player logs and crash dumps as received.
- `docs/multiplayer-questions.md` — what co-op still cannot answer alone.
- `DESIGN.md` — the original design. Its §12 "Priority TODO list" is SUPERSEDED.

**Check the code, not the planning docs.**
