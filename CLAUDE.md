# 32 — PalBonds (behaviour mod for Palworld)

**Progress: 97%**

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
| Polish and configuration | 5% | 60% | 3% |

Following stays at 95% for the open spawner-despawn defect. Polish counts the
README, both store descriptions, licence, screenshots, the Workshop 1.1.0 upload
and the Nexus package as done; the settings screen and the Nexus publish are
not. Recalculate whenever a category moves, and keep the `Progreso:` line of
this project's block in `../game proyects.txt` in sync.

---

## Where we stand — read this first (end of the 2026-09-12 session)

**v1.1.0 is the stable, published build.** Dragón: *"consider this version we
currently have as the last stable version of our mod as its better than anything
we have gotten before"*.

- **GitHub:** `master` is the only branch. Commit `1d06a5a` is the stable code;
  the commit after it adds the store packages and these notes.
- **Steam Workshop:** item **3797816321**, "PalBonds - The Befriending Mod",
  updated to 1.1.0 by Dragón. Visibility (hidden or public) is his call. He
  edited the live description himself after `release/workshop-description.txt`
  was saved, so the Steam page is the source of truth for wording.
- **Nexus Mods:** package ready; publishing it is Dragón's step.
  `release/PalBonds-v1.1.0.zip` holds one `PalBonds/` folder (enabled.txt,
  README.txt, LICENSE, the 8 scripts, byte-identical to the Workshop 1.1.0
  scripts). `release/nexus-description.txt` is his text with Nexus headings,
  the Nexus UE4SS requirement and an install section.
- **Confirmed in live play** (runs 37-39 and the raid-boss test): following,
  combat assist, self-defence, the churn and hit-lag fixes, feed by rarity, the
  alpha x2 bar, the F8 cheer stopping with the Pal, and bonding a raid boss
  without breaking anything.

**Dragón's machine right now (not in the repo):**
- **Manual install DISABLED.** `Pal\Binaries\Win64\dwmapi.dll` is renamed
  `dwmapi.dll.MODS-DISABLED` and `ue4ss\Mods\PalBonds\enabled.txt` is renamed
  `enabled.txt.MODS-DISABLED`. He plays the Workshop copies: subscribed to
  PalBonds (3797816321) and UE4SS Experimental (3625223587). Never enable both
  UE4SS copies at once; the game crashes when two load.
- **`steamapps\workshop\content\1623730\3797816321\` is both his subscription
  and the uploader's working folder.** Never unsubscribe on this PC: Steam
  deletes the folder, which is how the uploader lost the item once. To publish
  an update: replace the 8 scripts there, bump `Version` in its Info.json,
  upload with the Palworld Mod Uploader, and mirror the result in
  `release/workshop/PalBonds/` (the recoverable copy).
- The folders 3797815819 and 3797816106 in that directory are leftover uploader
  templates, not real Workshop items (the owner gets an error page). Harmless.
- **Save backups (gitignored):** `save-backups/2026-09-12_before-raid-boss-test/`
  (SaveGames plus `SteamCloud_1623730`, every file MD5-verified),
  `save-backups/workshop-3797816321-published-1.0.0/` and
  `save-backups/recreated-workshop-folder-3797816321/`. To restore saves: close
  Palworld, replace the contents of `%LOCALAPPDATA%\Pal\Saved\SaveGames\` with
  the backup's (and `Steam\userdata\<account>\1623730\` with
  `SteamCloud_1623730`), then launch. The Global Palbox is the local
  `GlobalPalStorage.sav` and is included. Real Steam and world IDs are
  deliberately not written in this public file.

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

Copy the changed `.lua` to all three locations (dev, release staging, live
install) and confirm with `md5sum` that all three match. A change that is only
in `mod/` has not been tested by anyone.

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

1. **Bonded Pals get despawned by their wild spawner** (run 35, and pass 200
   before it). Not wandering and not a teleport: two Petallias went unreadable
   in the same second and reported an identical distance. The spawner
   (`APalNPCSpawnerBase`, with `Tick_Despawning`,
   `LocationResetDistance_SpawnerToCharacterTooFar`, `RemoveGroupCharacter`)
   still owns them. Mechanism to find first: how capture detaches a Pal from its
   spawner group.
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
9. **Doc drift:** the GitHub `README.md` Status section is stale (it still
   advertises "Pet (F9), Feed (F10)" and predates following working). The
   player README and both store descriptions are current.
10. **Hotkeys fire while typing in chat** (see Pending).

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

**Hotkeys fire while typing in chat.** The Kick Keybind reference mod caches
`PalEditableTextBox` / `PalMultiLineEditableTextBox` / `EditableTextBox` and
checks `HasKeyboardFocus()` before acting. This project's F8/F9/F10 binds have
no such guard. Small, worth doing.


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
1. **Dragón publishes on Nexus** with `release/PalBonds-v1.1.0.zip` and
   `release/nexus-description.txt`, and decides when the Workshop item goes
   public.
2. **Spawner despawn** (known defect 1): find how capture detaches a Pal from
   its spawner, then apply that to bonded followers. A read-only probe that logs
   a bonded Pal's spawner and group comes first.
3. **Fix the GitHub README** (known defect 9).
4. **Hotkey guard while typing in chat** (small, Pending).
5. **Settings screen** decision: where the F9/F10 toggles and balance knobs
   would live. The last part of the Polish category.
6. **Multiplayer** only if Dragón wants it (see Pending).

Deliberately NOT next: the controller swap (see "Two routes to the right
brain"), a fallback only, and the current approach works.

## Where the real detail lives

`docs/hook-points.md` is the technical log, pass by pass, with the exact class
and function names and what each experiment proved. It is the file to search
when you need to know whether something was already tried. `CLAUDE-archive.md`
holds the older narrative history. `DESIGN.md` holds the original design; note
that its §12 "Priority TODO list" is marked SUPERSEDED and should not be used to
judge current state — **check the code, not the planning docs.**
