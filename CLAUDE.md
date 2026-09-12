# 32 — PalBonds (behaviour mod for Palworld)

**Progress: 92%**

| Category | Weight | Done | Contributes |
|---|---|---|---|
| Design and planning | 10% | 100% | 10% |
| Tooling (UE4SS + mod loading in game) | 15% | 100% | 15% |
| Hook research (the 6 open questions in DESIGN.md §8) | 15% | 100% | 15% |
| Per-individual personality system | 10% | 95% | 9.5% |
| Wild-Pal interaction (pet / feed / play) | 15% | 100% | 15% |
| Trust system | 15% | 95% | 14.25% |
| Following and combat assist | 10% | 85% | 8.5% |
| Threshold capture / flee | 5% | 100% | 5% |
| Polish and configuration | 5% | 0% | 0% |

Recalculate this table whenever a category moves. **Open question for Dragón:**
the last category and the total depend on whether the Steam Workshop page is
actually live — I cannot see that from here. If it is published, "Polish" is
roughly 60% (README, Workshop description, licence, screenshots, folder cleanup
all done; settings screen still missing) and the total is ~95%.

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

**Scope:** singleplayer / self-hosted only. Mods on official Pocketpair servers
risk a ban.

**Stack:** UE4SS (Okaetsu's experimental Palworld build, v3.0.1 Beta, Git SHA
`ba2efd55`) with all logic in Lua. The installed build's authoritative Lua API
is the `docs/lua-api/` folder of that exact commit — not memory, not a strings
grep of `UE4SS.dll` (both have produced wrong API names here; see "Retired
approaches").

---

## Current state

v1.0.0 shipped (git tag-level commit `abe5ec8`, MIT licensed, source at
`github.com/DragonKaiser55555/palbonds`). Everything in the feature list works
in game and has been confirmed by Dragón in live play:

- Pet, feed and play on wild Pals through the game's own radial menu
- Trust bar and personality tag drawn under the wild Pal's health gauge
- Seven personalities rolled per individual, with player-facing names
- Bonded Pals follow, stay *behind* the player, and hold still while aimed at
- Combat assist via the Hate system; companions defend and are pointed at the
  player's current enemy
- Sphere-less joining, with a celebration animation, a join VFX, a named toast,
  and a flat +50000 friendship head start
- Betrayal (player hits the Pal) and bond loss by distance

Two crashes were found and fixed after v1.0.0 and are **not** in the released
zip: the world-change crash (pass 285) and the death/respawn crash (commit
`94adf54`). Whatever ships next must include both.

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
  release/workshop-description.txt
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

## Combat assist and following — where they actually stand (run 32, 2026-09-12)

**Both work.** This is settled by logs, not impression. Run 32, the most recent:

| | result |
|---|---|
| Companions fight the player's target | yes — 9 `[HATE-ASSIST]` pushes, 16 combat actions installed |
| Pals wandering off | **none** — Dragón: *"i didnt see them wander off so thats good"* |
| Pals lost / abandoned | none |
| Recall | 2 strays, 2 returns |
| Log volume | 263 lines, down from 913 in run 30 |

Two problems remain: **friendly fire** and **lag**. A third was found in run
34 (below): **companions never defend themselves outside a player fight.**

### Out-of-combat self-defence — broken, cause found (run 34)

The pass-325 "hybrid" (fight back when hit outside a player fight, don't during
one) only ever changed preset values. Outside a player fight the hit Pal DOES get
hate on its attacker, but `pal_has_own_fight` treats `OtomoFollow` as passive and
keeps follow installed, and `suspend_follow_for_combat` is only ever called from
`OnPlayerCombatTarget`. The follow action holds the slot, so the Pal never enters
combat. Run 34: a Caprity took 12 hits and did nothing until Dragón attacked.
Full analysis in `docs/hook-points.md`, "Runs 33-34".

**Fixed offline, awaiting a live run:** `Combat.OnFollowerAttacked` routes a
third-party hit into suspend + combat action + hate for **only the Pal that was
hit** (Dragón: *"only the pal attacked should respond"*). He floated companions
defending each other as nice-to-have; not built, and it would add to the
pile-on behind friendly fire, so revisit only after the friendly-fire A/B.

### Friendly fire — open, and understood

Run 32: 16 and 6 companion-on-companion hits across two fights; target discipline
cancelled 4 and 3 resulting duels. Dragón: *"they still managed to atk each
other."*

The mechanism is not a mystery. Both companions charge the same enemy in the same
second, stand on top of each other, and melee swings land on whoever is adjacent.
Two preset slots feed it during a fight: `Discover_Equal = Battle` (another
companion is just another same-sized Pal it noticed) and `Damaged_* = Battle`
(being clipped makes it hit back).

Target discipline cancels the resulting duels within a tick — that is why
Dragón sees them "stop moments after" — but it cannot stop them starting.

`QUIET_RETALIATION_DURING_PLAYER_FIGHT` in `Personality.lua` is the A/B switch
for the retaliation half. It is **on**, and the evidence so far says it buys
little: friendly fire per fight ran ~18 (run 28, off) vs ~26 (run 29, on) vs 16
and 6 (run 32, on), 11 in one 3-companion fight (run 33, on). Noisy, no clear
win. Deciding it needs a clean single-variable pair of runs, which has not
happened yet because other fixes kept landing between runs. **Do not flip it at
the same time as anything else.**

Why it cannot fully work on its own: it only removes the damage-triggered half.
`Discover_* = Battle` stays on for the whole combat window, so companions can
still notice each other as targets. Since pass 318 the fight is *assigned*
(combat action installed + hate pushed), so whether `Discover_* = Battle` is
still needed at all is an open, testable question.

### Lag — open, and the cause is now measured rather than guessed

Dragón after run 32: *"still feels laggy"*. It is no longer the logging. The
`[INSTALLS]` line added in pass 333 reports the real cost per fight:

```
that fight cost 12 follow-action rebuild(s) and 8 combat-action install(s)
that fight cost  5 follow-action rebuild(s) and 8 combat-action install(s)
```

Each install is a `StaticConstructObject` plus a `SetAction`. **The follow action
and the combat action share priority slot 10**, deliberately (see the pass-300
note in `Combat.lua`), so they evict each other: combat destroys follow, the
follow tick rebuilds it, combat destroys it again. That thrash is the remaining
lag and it is the next thing to attack.

Untried ideas, in rough order of promise:
1. Do not rebuild follow while the player's combat window is open and the Pal is
   still meant to be fighting. Today `resume_follow_after_combat` fires on every
   target-discipline cancel and every recall, each causing a rebuild that combat
   then evicts.
2. Give the combat action a different priority so the two stop evicting each
   other. Priority values above Logic are not in any reachable enum dump and
   pass 224 already had to correct a wrong priority constant, so this needs
   evidence first, not a guess.
3. Turn `ACTION_CHANGE_PROBE` off. It is now the single largest log source (90
   of 263 lines) and it polls every bonded Pal at 200ms during combat. It has
   answered its questions; it is kept only because it is the best diagnostic this
   project has. **It must be off before shipping regardless.**

---

## In flight right now (2026-09-12, after run 32)

`DEBUG_LOGGING = true` in the **live install only** (both project trees stay
`false`) so a session can read the run.

`ACTION_CHANGE_PROBE = true` in `Combat.lua` — the `[ACTION-TRACE]` probe, 200ms
in combat and 1000ms out of it. Turn off before shipping.

`QUIET_RETALIATION_DURING_PLAYER_FIGHT = true` in `Personality.lua` — the
unresolved A/B above.

Nothing else is mid-flight. Everything through the run-33 cleanup (stale fight
state dropped in `StopFollowing`, F7 emote probe removed, `[COMPANION]` logged
once per Pal) is deployed to all three trees and md5-verified; every harness
suite passes, including the new `stoptest.js`, and `harness3` reports 14 hooks.

Also deployed after run 34, not yet live-tested: self-defence
(`Combat.OnFollowerAttacked`), per-Pal install caps as 60s rates, the
`DISCOVER_BATTLE_DURING_PLAYER_FIGHT` switch (`true`), and the alpha x2 bar.
`selfdefencetest.js` and `captest.js` each fail against commit `1ca339b` and
pass now. **None of this session's work is committed yet.**

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
   before it). Not wandering and not a teleport: both Petallias went unreadable
   in the same second and reported an identical distance. The spawner
   (`APalNPCSpawnerBase`) still owns them. See hook-points "Run 35". Mechanism
   to find first: how capture detaches a Pal from its spawner group.
   *(The old item 1, "a failed radial feed still grants friendship", is fixed in
   code — run 35 logs the refusal.)*
2. **`LoopAsync` fallbacks still present** in `Trust.lua` and `Indicator.lua` —
   dead code that would only run in the emergency it is unsafe for. Removed once
   in pass 278, reverted in 285 to keep that fix minimal.
3. **World-change references never cleared:** `Indicator.trackedBars` holds
   actors across a world change; `Interaction` writes `SpawnedOtomo` into a
   GameInstance-lived widget and never clears it, same for
   `pendingWildFeedTarget`. None caused the pass-285 crash, but all are real.
4. **`FindFirstOf` exposure** — upstream UE4SS issue #1328 reads out of bounds
   and lacks the null guard `FindAllOf` has. The death-crash fix routed the
   8 player lookups in the hot files through the guarded path; it reduces
   exposure and cannot fix the upstream bug.
5. **`find_targeted_pal` costs 42-47ms per scan** and runs while the radial menu
   is open. Improved from 74ms, still the largest single stall in the project.
6. **No settings screen.** The F9 personality-tag toggle is session-only and
   resets each launch; `release/README.txt` documents that.
7. **Companions clip each other in fights** and briefly fight back before
   target discipline cancels it (16 and 6 hits across run 32's two fights). The
   cause is understood — see the combat-assist section — and the containment
   works, but the hits themselves are not prevented.
8. **Lag during fights**, caused by follow/combat action install churn, measured
   per fight by the `[INSTALLS]` log line. Not the logging; that was cut by 71%
   in passes 332-333 and the lag survived it.
9. **Doc drift:** `README.md` line 18 still advertises "Pet (F9), Feed (F10)",
   binds removed back in pass 239, and its whole Status section predates
   following working. `release/workshop-description.txt` never documents F10
   (passive-bonding toggle) at all. Both are player-facing.
10. **Companions do not defend themselves outside a player fight** — fixed
   offline (`selfdefencetest.js`), not yet confirmed live.

---

## Pending, deliberately deferred

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

In order. The first two are the only things standing between this and shipping.

**STABLE BUILD, 2026-09-12 (after run 39): committed as the last stable
version at Dragón's request.** Dragón: *"everything working correctly, saw the
animation stop too together with the pal and nothing broke"*. For that commit:
`DEBUG_LOGGING = false` in ALL THREE trees including the live install (they are
now byte-identical), `ACTION_CHANGE_PROBE = false`, the F7 runtime log switch
and the `[HIT-COST]` timing wrapper removed. To debug again: set
`DEBUG_LOGGING = true` in the LIVE install's `Logger.lua` only, and
`ACTION_CHANGE_PROBE = true` in `Combat.lua` if action traces are needed.

**SAVE BACKUP — restore point before Dragón's raid-boss bonding test.**
`save-backups/2026-09-12_before-raid-boss-test/SaveGames/` (gitignored — personal
data). A full copy of `%LOCALAPPDATA%\Pal\Saved\SaveGames\`, 443 files /
27,722,059 bytes, every file MD5-verified against the original, taken with the
game closed. To restore: close Palworld completely, delete (or rename) the
contents of `%LOCALAPPDATA%\Pal\Saved\SaveGames\`, copy the backup's contents
back in, then launch. The world he plays is the most recently written world
folder. Steam Cloud is ON for Palworld, so the backup also holds a copy of
`Steam\userdata\<account>\1623730\` as `SteamCloud_1623730/` (27 files,
MD5-verified) — restore that too, or Steam may bring back a newer cloud copy.
The account-wide Global Palbox is the local file `GlobalPalStorage.sav` in the
SaveGames account folder, and it is in the backup. Real Steam and world IDs are
deliberately NOT written here: this file is public on GitHub.

Earlier — after run 38: hit lag confirmed much better by Dragón;
feed-by-rarity confirmed (0 = common, 1 = uncommon); peaches keep 250/500 by
his decision. The F8 cheer now stops with the Pal's animation (deployed, not
yet seen in game). Next performance target: ~4.7 ms per damage event still
spent inside the damage hooks (hook-points "Run 38"). Then the spawner
despawn. Nothing from this session is committed.**

Earlier: run 37 confirmed the churn fix (Pals "behaved
nicely", F7 showed logging is NOT the lag). Hit-lag fix + feed-by-rarity now
deployed, awaiting his run** — see hook-points "Run 37 and the hit-lag pass".
The cause found: a full `FindAllOf` walk per damage event in Trust (41 walks
per 30-hit burst offline, now ≤2). Check the new `[HIT-COST]` line and the
`[FEED-RARITY]` lines (rarity scale 0..4 is assumed) in his next log.
Open question for Dragón: Kinship Peaches still grant 250/500.

Earlier the same night:
Dragón's priority is now performance above everything else. Runs 35/36 A/B
shelved as inconclusive; `DISCOVER_BATTLE_DURING_PLAYER_FIGHT` back to `true`.
Fixed and deployed (see hook-points "Performance pass after run 36"): the
recall-vs-assist loop, follow starvation (global throttle deleted), a growth
audit with pruning, and **F7 in dev builds toggles the debug log mid-session**
so its cost can be felt directly. Next after his run: the spawner despawn, then
the personality scan's per-8s world walk. Nothing from this session is
committed.

0. **Runs 35/36 — the friendly-fire A/B**, protocol agreed with Dragón:
   run 35 with `DISCOVER_BATTLE_DURING_PLAYER_FIGHT = true`, archive the log
   as `palbonds-live.log.run35`, flip to `false` in all three trees, run 36.
   Same setup both runs (2-3 bonded companions, a few fights against wild
   Pals). Compare `[FRIENDLY-FIRE]` per-fight totals, `[TARGET-DISCIPLINE]`
   counts, and whether `[ACTION-TRACE]` still shows `CombatPal` with the
   player's enemy as hate target. If companions stop engaging in run 36, the
   switch goes back to `true`; either way delete the losing branch. Run 35
   also checks self-defence (`[SELF-DEFENCE]`) and an alpha's bar
   (`(BOSS: bar x2)`).
0b. **Feed by item rarity** — Dragón wants rarer food to give more trust.
   Mechanism is known (see hook-points, "Research answered"); amounts per
   rarity are his call and not yet given.
1. **The lag — attack the install churn.** See the combat-assist section above
   for the measured cause and three untried ideas. Start with "do not rebuild
   follow while the combat window is open", which is the cheapest and does not
   touch priorities.
2. **Friendly fire.** Understood but unsolved. The `QUIET_RETALIATION_DURING_PLAYER_FIGHT`
   A/B is still unresolved — resolve it with a clean single-variable run pair
   before trying anything new, and delete the losing branch when it resolves.
3. **Turn `ACTION_CHANGE_PROBE` off** and set the live `DEBUG_LOGGING` back to
   `false`. Both are shipping blockers, neither is urgent before then.
4. **Fix the doc drift** (known defect 7) before any further release.
5. **Rebuild the release zip** with the post-1.0.0 crash fixes and cut v1.0.1.
6. **Decide on a settings screen**, which is where the tag toggle and the balance
   knobs belong. This is the last 5% of the progress table.

Deliberately NOT next: the controller swap (see "Two routes to the right brain").
Dragón has ruled it a fallback only, to be opened if the current approach stops
gaining ground. It is still gaining ground.

## Where the real detail lives

`docs/hook-points.md` is the technical log, pass by pass, with the exact class
and function names and what each experiment proved. It is the file to search
when you need to know whether something was already tried. `CLAUDE-archive.md`
holds the older narrative history. `DESIGN.md` holds the original design; note
that its §12 "Priority TODO list" is marked SUPERSEDED and should not be used to
judge current state — **check the code, not the planning docs.**
