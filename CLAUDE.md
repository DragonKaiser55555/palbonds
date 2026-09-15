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
2026-09-15**); only the settings screen is left. Recalculate whenever a
category moves, and keep the `Progreso:` line of this project's block in
`../game proyects.txt` in sync.

**Not yet reflected in the table, decide with Dragón before changing it:** a
subscriber has reported microstutters against 1.1.0 (see "Next steps" #1). If
that reproduces and turns out to be the mod's doing, it is a performance defect
in a shipped build and the affected category should come down accordingly —
but do not move the number unilaterally.

---

## Where we stand — read this first (end of the 2026-09-15 session)

**v1.1.1 IS PUBLISHED on both stores.** It is v1.1.0 plus exactly ONE confirmed
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

**FIRST THING TOMORROW (2026-09-16): the microstutter report.** A Workshop
commenter, *Goldaer*, reports the mod introduces noticeable microstutters,
visible on Steam's performance overlay. Filed against 1.1.0, so 1.1.1 does not
change it. Dragón saw the comment and deferred it deliberately: *"we will
tackle that tomorrow, tonight i want to sleep"*. This is now the top open item,
ahead of the settings screen. Relevant prior work: the `[RADIAL-REDIRECT-PERF]`
timing line (suppressed by default, prints any scan taking 15ms or more), the
gate-before-reflection rule for global hooks, and the fact that run 37 already
ruled out logging as the cause of fight lag.

- **GitHub:** `master` is the only branch. Commit `1d06a5a` is the stable code;
  later commits add the store packages, docs, and a rewritten public README.
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
`steamapps\workshop\content\1623730\3797816321\`. Publishing means: replace the
8 scripts, bump `Version` in `Info.json`, leave `.workshop.json` **untouched**,
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

**Dragón's machine right now (not in the repo), as of 2026-09-15 — WORKSHOP
MODE, manual install disabled:**
- **Re-subscribed to both Workshop items** (PalBonds 3797816321, UE4SS
  Experimental 3625223587) so the item folder would be recreated for the
  uploader. Confirmed working in game before the upload.
- **Manual install is DISABLED**, deliberately and BEFORE resubscribing, so two
  UE4SS loaders and two copies of PalBonds could never run at once:
  `Pal\Binaries\Win64\dwmapi.dll` → `dwmapi.dll.MODS-DISABLED` (kills the whole
  manual stack) and `ue4ss\Mods\PalBonds\enabled.txt` →
  `enabled.txt.MODS-DISABLED` (second layer). Both are plain renames; all 8
  scripts under `ue4ss\Mods\PalBonds\Scripts\` are intact. Reverse the two
  renames to go back to manual/DEV mode.
- **The copy the game runs is `Mods\NativeMods\UE4SS\Mods\PalBonds\`, and it is
  currently at 1.1.1** — md5-identical to `mod/` on all 8 scripts. Steam's
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

0. **Microstutters reported by a subscriber — UNVERIFIED, top priority.**
   Workshop comment from *Goldaer*, 2026-09-14, against 1.1.0: the mod
   "appears to introduce a lot of microstutters that are really noticeable",
   visible on Steam's performance overlay. Not reproduced by us yet and not
   yet confirmed to be the mod's doing. This is the first report of a
   performance problem from someone who is not Dragón, which makes it more
   valuable than an internal hunch — he runs one machine and one save.
   Treat it as real until measurement says otherwise. Scheduled for
   2026-09-16.
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
1. **Microstutters reported by a real user** (Goldaer, Workshop comment,
   2026-09-14, against 1.1.0). Dragón's call at the end of the 2026-09-15
   session: tackle this first, tomorrow. This is a performance defect affecting
   subscribers, which outranks new features. Start by reproducing it with
   Steam's performance overlay, then use `[RADIAL-REDIRECT-PERF]` (needs BOTH
   `DEBUG_LOGGING` and `SHOW_DIAGNOSTICS` true — see "Diagnostics") rather than
   guessing; run 37 already ruled out logging itself as the fight-lag cause, so
   do not re-run that.
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
