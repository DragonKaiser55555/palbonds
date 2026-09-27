# 32 — PalBonds (behaviour mod for Palworld)

**Progress: 100%**

Dragón's ruling (2026-09-23): *"we are already past the 1.0.0 version, which I
would consider as the 100% - all the rest of things are just extras and add-ons
to the mod"*. The global rubric's own definition agrees -- 100% is "finished and
uploaded to its platform(s) for users" -- and PalBonds has been live on the
Steam Workshop, Nexus and GitHub since 1.1.0, with 1.1.7 (co-op) live on
2026-09-23. Everything after this point (the settings screen, releasing Pals,
further co-op verification, cleanup) is post-1.0 extras, tracked in "Pending"
and in the release sections, NOT as missing percentage.

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

## 1.1.9 IS LIVE (2026-09-27)

- **Nexus:** version 1.1.9, file "PalBonds V1.1.9", 124 KB (our zip is 127,278
  bytes), uploaded 1:40AM, virus scan Safe to use, 1 main file. Changelog and
  short description are Dragón's wording.
- **Steam Workshop:** updated 27 SEP 2:06, full changelog posted.
- **CurseForge:** uploaded, but **1.1.8 is still not approved there** — their
  moderation queue is far behind. Nothing to chase.
- **GitHub:** pushed, `630da5b..a865452`. The repo had been stale since v1.1.7,
  so that commit carries 1.1.8 as well. **No new issues; nothing further from
  Hakaishin** — issue #1 is still the only one and still closed.

**Store descriptions rebased from the live pages** into
`release/nexus-description.txt` and `release/workshop-description.txt`: the
Settings section now describes the in-game screen, and the "an in-game settings
screen is planned" promise is gone. Dragón edited the live pages himself and is
doing the other 15 languages separately.

**STILL STALE — `release/PalBonds/README.txt`.** It ships INSIDE the zip and
still tells players to close the game and edit `PalBonds_settings.lua` in
Notepad (lines ~61, 77, 84-120, 216), and still says the screen is "planned for
a future update". Fixing it means rebuilding and re-uploading the zip, so
Dragón parked it — do it with 1.1.10 unless he says otherwise.

## 1.1.9 PACKAGED — was awaiting upload (2026-09-27)

`release/PalBonds-v1.1.9.zip`, 127,278 bytes, **18 entries, forward-slash
paths** (Compress-Archive writes backslashes — built with Python's zipfile
instead; the 1.1.7 notes already flagged this). `release/workshop/PalBonds/`
synced, `Info.json` Version **1.1.9**. Both trees md5-identical. 27/27 suites
pass against the stripped tree. **Nothing uploaded, committed or pushed.**

**Dev stack disabled at his request** (the standing "all the local mods" rule):
`Pal/Binaries/Win64/dwmapi.dll` -> `dwmapi.dll.MODS-DISABLED`, and
`Pal/Content/Paks/LogicMods/CreativeMenu.pak` -> `.MODS-DISABLED` (it would
otherwise load under the Workshop loader). No other proxy DLL present.
Re-enabling is HIS call, never Claude's.

### PERFORMANCE: A CORRECTION CLAUDE HAD TO MAKE TO ITSELF
The first comparison used `2026-09-24_runF-118-clean.csv` because of its name.
**runF is the PRE-fix measurement** — its 61 hitches/min is the "before" number
in this file's own 1.1.8 section ("61/min -> 30/min"). The shipped 1.1.8
baseline is `2026-09-25_runL-clean-fixed.csv`. Against the right baseline:

| flying, 2 min | 1.1.8 shipped (runL) | 1.1.9 (runJ 0-120s) |
|---|---|---|
| avg fps | 56.4 | 62.3 |
| 1% low | 20.9 | 22.2 |
| 0.1% low | 11.8 | 9.9 |
| p99 frame | 33.9 ms | 31.1 ms |
| worst frame | 107 ms | 138 ms |
| hitches/min | 30.0 | 27.5 |
| stall series | none | none |

**1.1.9 is level with 1.1.8, not faster.** Better on average and p99, slightly
worse at the extreme tail, hitches about the same — all inside run-to-run
variation on different terrain. **So the changelog must NOT claim a performance
win.** The trust-bar leak fix is real and measured (flat 11-21 entries vs
0->603 in 14 minutes) but needs a LONG session to matter, and a two-minute
capture cannot show it.

**Opening the settings screen costs nothing measurable** (runK): its first 30 s,
with the screen opened, were the *best* part of that run — worst frame 110 ms
against 445 ms for the later flying.

**Dragón's own read of the "laggy area", and it fits the data:** that zone is
one he rarely plays, so the game was streaming uncached resources; it improved
the more he played there. runJ's minutes 3-4 (that area) were genuinely worse
than 1-2 — 1% low 22.2 -> 16.6, hitches 27.5 -> 45.5/min, one 413 ms frame.
A weak ~11.4 s stall series showed up in that window only (6/10 slots, ~0.9 by
chance); shipped 1.1.8 shows none. Not enough to act on — noted, not chased.

## 1.1.9 RELEASE BUILD — built, tested offline, AWAITING DRAGÓN'S LONG RUN

`release/PalBonds/Scripts` rebuilt from `mod/` through
`tools/strip-comments.py` (22,097 -> 12,110 lines) and **deployed to the live
install as the thing that would actually ship**. Nothing is zipped, committed or
published — that needs his word.

Removed from the source for the release: `MENU_ENABLED` and `INPUT_PROBE`
(crash-investigation scaffolding) and `InputProbe.lua` itself. Verified off:
`DEBUG_LOGGING`, `SHOW_DIAGNOSTICS`, `TRACE_PHASES`, `ACTION_CHANGE_PROBE`.
27/27 suites pass against `mod/` AND against the stripped `release/` tree.

**This run has NO LOG, on purpose** — that is what a player gets, and it is the
build being tested. If anything goes wrong, redeploy `mod/` with
`DEBUG_LOGGING`/`TRACE_PHASES` on and reproduce.

### SLEEPING WILD PALS — asked 2026-09-26, answer: NO, and why
Dragón asked whether interacting with sleeping wild Pals could be a setting,
explicitly conditional on it being easy and not risking what works. It is not.

* **The game refuses, not us.** The radial substitution has no action-state
  gate, so the menu does appear; the game's own Pet/Feed simply will not run on
  a sleeping Pal, and `PET-CHECK` then correctly grants nothing because the
  interaction never happened. Recorded from his own run 3 (2026-09-16):
  "Sleeping-Pal pet correctly gave nothing."
* **Changing it means one of two bad things.** Either wake the Pal — pushing or
  altering an action on `UPalActionComponent`, which is the exact system that
  caused CRASH #2 on 2026-09-01 and the reason `play_refusal` still refuses a
  busy Pal to this day — or bypass `PET-CHECK` and grant friendship for an
  interaction the player can see did not happen, which breaks the contract the
  whole interaction model rests on.
* If it is ever wanted, the route is research: find the game's OWN wake
  mechanism and use that. Not an add-on.

## 40 MINUTES, NO CRASH (2026-09-26 19:44-20:24) — 1.1.9 candidate

Archived as `docs/bug-reports/2026-09-26_clean-40min-session.log` (12 MB, trace
on). Dragón played normally, opened the screen twice, bonded Pals.

| | before | this session |
|---|---|---|
| crashes | 4 in one evening; 14s and 3m45s with the screen open | **none in 40 min** |
| `LUA_ERRERR` in UE4SS.log | yes, 43s after the 154 armed | **zero** |
| tracked bars | 0 -> 603 in 14 min, straight line | **flat, 11-21 all session**, 146 prunes |
| trace pairs | `gauge.boss` 20/10 | every pair balanced except `gauge.boss` 40/20 |

**The one real finding, now fixed: the boss-gauge hook callback was unguarded.**
Entered 40 times, reached its end 20 -- exactly the 20 boss bars that attached.
UE4SS invokes it twice per call and the second invocation's parameters are not
the shape `hook_get` expects, so it threw. Nothing broke (the bar attaches on
the first invocation) but an exception raised twice a minute inside a hook is
not shippable, and every other hook in that file was already wrapped. Now
`pcall`ed, with a once-only log so a genuine failure stays visible.

**Known cosmetic gap, Dragón's call to leave it:** `SpaceBar` is refused because
UE4SS names that key differently and separator-stripping cannot bridge it. His
ruling: *"spacebar is already jump in the game, doubt anyone will swap such a
core key."* Note that the numpad very likely breaks the same way
(`NumPadOne` vs `NUM_ONE`) -- offered, not taken.

**NOT YET DONE for a release:** the clean build. `DEBUG_LOGGING`,
`TRACE_PHASES`, the trace call sites and the `MENU_ENABLED` / `INPUT_PROBE`
switches all have to come out, and the suite has to pass against
`release/PalBonds/Scripts` -- a stripped build is a build nobody has tested.

## FIRST LIVE RUN OF THE NEW REBINDING — two faults, both fixed (2026-09-26 14:21)

**1. "It locks me when the key fails, especially F1-F5."** The log names it four
times:
```
14:21:24  ignoring F6: it arrived before the screen finished asking
14:21:33  ignoring F5: ...   14:21:41  ignoring F4: ...   14:21:46  ignoring F2: ...
```
`CAPTURE_MIN_WAIT = 0.25` — a deaf period after the click. It was built for the
RegisterKeyBind mechanism, where UE4SS's registration burst could deliver a key
nobody pressed. **That mechanism is gone**, the overlay only reports a key it
actually received while focused, and the guard's only remaining effect was to
swallow the player's FIRST press and then keep holding the keyboard until he
pressed again. **REMOVED.**

Note for the record: it was **not** F1-F5. F5, F4 and F2 each appear in the
ignored list AND in the succeeded list seconds later — same keys, same session.
The variable was *speed*: a quarter second is inside human reaction time, and he
was going quickly down the F-row.

**2. The overlay came up in Japanese.** `KeyConfigParam` is deliberately nil (it
is what stops the widget rebinding a REAL game action), so the widget never runs
the game's own text setup and both of its blocks keep their design-time
defaults. Both are `BP_PalTextBlock_C`, so we now write them ourselves with
`SetText_GDKInternal` (rule 4 — a raw `.Text =` crashes this game): the title
becomes the row being rebound, the line under it
`"Press a key   ·   Esc to cancel"`. New Locale string `menu_press_key_cancel`
in 16 languages; Locale is now **75 strings**.

Covered: menutest asserts both text blocks are written in the player's language,
and that a key reported the instant the overlay is up still counts. 27/27.

## BUILT: the settings screen no longer registers a single key watcher (2026-09-26)

**157 key watchers -> 3.** `Menu.lua` now has zero `RegisterKeyBind` calls; the
only one left in the mod is Interaction's three gameplay hotkeys.

**How rebinding works now.** Clicking a rebind row builds the game's own
`WBP_OptionSettingsOverLayWindow_C` through the same `native_widget` path as
every other native widget on the page, fills it over `inst.page` at
`OVERLAY_Z = 90`, and focuses input on it. One class-wide hook on
`:OnKeySetting` reads the FKey out of the hook parameter. The handler checks
`GetAddress()` against the instance WE put up, so a rebind in the game's own
options screen cannot drive one of our rows. `KeyConfigParam` is left nil so the
widget's apply-logic has no game action to write to.

**`capturable()` was not deleted, it changed job.** It used to decide which keys
got a watcher; it now decides which reported keys are ACCEPTED. Escape cancels,
a mouse button or bare modifier is ignored and the screen keeps waiting.

**A real integration bug the tests caught, not the code review:**
`key_pressed`'s success path does not go through `stop_capture`, so the overlay
stayed on screen after a key was accepted. Fixed.

**AND THE ONE THAT WOULD HAVE KILLED THE FEATURE IN GAME:** the overlay reports
FKey names (`SpaceBar`, `LeftMouseButton`) while `RegisterKeyBind` needs UE4SS's
table (`SPACE_BAR`, `LEFT_MOUSE_BUTTON`). Uppercasing gives `SPACEBAR`, which
matches nothing — so **Space, the headline key the old approach could never
capture, would have been refused the moment it became capturable.**
`Settings.resolve_key_name` now matches on the name with separators stripped,
built lazily from whatever `Key` actually holds.

**Tests:** menutest's rebinding section rebuilt on the overlay — no watcher is
registered at all (`__BINDS` is empty with the page open), the overlay goes up
as a child of our canvas and comes back down on success, on Escape, on a second
click and on timeout, Space and W both bind, a fire from a foreign overlay
instance is ignored, mouse/modifier are refused while waiting, and the keyboard
is handed back on every exit path. 27/27 suites pass.

## SOLVED: ANY-KEY CAPTURE WITHOUT RegisterKeyBind (2026-09-26 13:54)

Six probe rounds, three of which crashed, ending in a confirmed mechanism.
Logs: `docs/bug-reports/2026-09-26_probe-round5-real-key-names.log` and the
round-6 confirmation.

**The answer is the game's own "press a key" modal**, found by grepping the
CXXHeaderDump for every widget class with a reflected key event:

```cpp
class UWBP_OptionSettingsOverLayWindow_C : public UPalUserWidgetOverlayUI
    void OnKeySetting(FKey NewKey);            // FKey as a HOOK PARAMETER
    FEventReply OnKeyDown(FGeometry, FKeyEvent);
    UWidget* BP_GetDesiredFocusTarget();
    UBP_PalTextBlock_C* BP_PalTextBlock_Title / _Command;
    UBP_HUDDispatchParameter_KeyConfig_C* KeyConfigParam;
```
Asset: `/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/`
`WBP_OptionSettingsOverLayWindow.WBP_OptionSettingsOverLayWindow_C`

It takes focus, receives `OnKeyDown`, and passes the pressed key to
`OnKeySetting` as a plain parameter. Hooking that returned clean names:
**`W`, `SpaceBar`, `R`, `G`, `H`, `U`, `S`** — including the two keys
DarnMenu's curated battery explicitly cannot bind. Game thread, no
`RegisterKeyBind`, no struct crossing the boundary by value.

It also sits in the SAME asset family our settings page already builds from
(`WBP_OptionSettings_*`), so using it keeps the game's own look and focus
behaviour instead of imitating them.

**The rule learned across all six rounds — write this down:**
- **CALL** a function taking/returning an FKey-bearing struct by value →
  **the process dies** (AV 0x70; rounds 1 and 2, two different functions on two
  different objects, identical fault).
- FKey nested in a struct with **no reflected members** (`FKeyEvent`) → a clean,
  catchable Lua error (round 3).
- **HOOK** a function and **READ** an FKey as a parameter or as a UObject
  property → **works** (rounds 4-6).
- A UE4SS `FName` needs `:ToString()`; `tostring()` prints the userdata address
  (`Capture.lua:168` has said so all along — round 4 lost a run to it).

**Free bonus:** the same hooks expose the game's own action names and their
current bindings (`MoveForward`/`Forward`->`W`, `Jump`->`SpaceBar`), which is
ready-made conflict detection for a future "that key is already Jump" warning.

### Next: build it (NOT yet started — Dragón's call on the design)
Plan: when a rebind row is clicked, construct the overlay, add it to our page,
let it take focus, read the key from the `OnKeySetting` hook, close it.
**Leave `KeyConfigParam` nil** so the widget's own apply-logic has no game
action to write to — the one real risk is a constructed instance rebinding a
REAL game binding, and a null parameter is what prevents it. Must be verified in
the first test run that no game binding changes.

**Still open and not addressed by any of this:** the three gameplay hotkeys
(F8/F9/F10). The modal needs focus and there is none during normal play, so
those stay on `RegisterKeyBind` — i.e. player-level exposure, minus the 154-way
amplification that is crashing Dragón every few minutes.

## THE KEY IS READABLE FROM A HOOK (2026-09-26 13:37) — route found

**All four hooks on the game's own rebinding widget armed and fired, and the
FKey's name resolved.** Log archived as
`docs/bug-reports/2026-09-26_probe-round4-keynames-resolve.log`.

```
hooked :OnKeyUp / :On Action Key Changed / :On UI Action Key Changed / :On Key Config Changing
KeyConfigChanging -> first FName param = 'FNameUserdata: 0000022C43B4B068'
ActionKeyChanged  -> action='FNameUserdata: ...' | NewKey.KeyName = 'FNameUserdata: ...'
OnKeyUp           -> CachedSettingKey.KeyName = 'FNameUserdata: ...'
```

`FNameUserdata: <address>` is **not** a failure — the property read SUCCEEDED
and returned a real FName wrapper. `tostring()` on a UE4SS FName gives the
userdata address; `:ToString()` gives the text, which `Capture.lua:168` has
documented since it was written. Round 5 fixes only that.

**What this establishes, and it is the thing three crashes were spent looking
for:** an `FKey` is reachable from Lua **as a property, inside a hook** —
`widget.CachedSettingKey.KeyName` and the `NewKey` hook parameter both resolved.
It is only unreachable when it has to cross the boundary **by value in a call**
(rounds 1-2, both fatal) or when nested in a struct with no reflected members
(`FKeyEvent`, round 3, a clean error).

**The rule that falls out of all five rounds:**
- CALL a function taking/returning an FKey-bearing struct → **process dies**.
- HOOK a function and READ an FKey property off a parameter or a UObject →
  **works**, and when it does not, it fails as a catchable Lua error.

So the capture route for any-key rebinding is: a UMG key event delivers the
press, and the key's identity is read as a property. No `RegisterKeyBind`.

**Still open:** the three gameplay hotkeys (F8/F9/F10). `OnKeyUp` needs a
focused widget and there is none during normal play, so nothing here replaces
them yet.

## SELF-INFLICTED: the InputProbe crashed the boot (2026-09-26 13:11) — FIXED

`InputProbe.lua`, written to answer "can a key press be read from the game
thread", **took the game down before it finished loading.** `AV reading 0x70`.
Removed from the live install within minutes; the probe is `INPUT_PROBE = false`
in `main.lua` and the file stays in `mod/` only. Evidence archived as
`docs/bug-reports/2026-09-26_probe-boot-crash.{log,runtime-xml}`.

The log's last line was the probe's own capability-pass header, so it died on
the **first native call**. Two bugs, both worth not repeating:

1. **A failed read was treated as success.** The guard was
   `local remote = safe(function() return c.Player == nil end)` /
   `if remote ~= true then return c end`, and `safe` returns nil when the read
   throws — so `nil ~= true` handed back a controller too broken to read a field
   off. **Every gate must require a positive confirmation, never "not false".**
2. **It ran before the player was in the world.** The line immediately before
   the crash is Session's "still loading — asking again until the player is in
   the world". The controller object existed while its internals did not, so the
   call dereferenced a null `PlayerInput` — `0x70` is a field at a small fixed
   offset off a null base, the shape `docs/hook-points.md` already describes.

Galling detail: this violated the freshness rule copied into that same file's
header from DarnMenu's notes two messages earlier — *only touch objects the
engine handed you recently*. A boot-time `FindAllOf` is the textbook case of a
poll discovering something unbuilt.

**Fixed in `mod/`:** a `world_is_ready()` gate (PlayerRef valid, not
world-closing, held for 2s) before anything native; `live_controller` now
requires `Player` AND `PlayerInput` to both read and validate, and hands both
objects to the candidates so none re-reads a field; and **a crumb is logged
before every individual native call**, so a repeat names the exact call instead
of just the pass. Not redeployed — Dragón's call whether to spend another boot.

## WHAT DARNMENU DOES ABOUT KEYS — checked, and it is NOT a better route (2026-09-26)

Dragón asked whether the reference mod has a safer way to capture a free key
press. **It does not. It uses the identical mechanism, with a shorter list.**
From `DarnMenu/Scripts/main.lua:496-678` and `DarnMenu_API.md:159`:

- A one-time battery of `RegisterKeyBind` calls over a **curated ~69-key set**,
  armed lazily on first use, gated by a capture flag — the same shape as ours,
  which arms 154.
- It documents the two hard UE4SS limits: **no any-key listener**, and
  **keybinds cannot be unregistered.** The second one kills the idea of arming
  watchers only for the duration of a capture — registrations would accumulate
  on every capture with no way to release them.
- It documents the cost of the short list: **Space, Enter, Tab, Esc, arrows,
  symbols and modifier combos are not capturable.** That is precisely the
  restricted key list Dragón rejected at milestone 4 ("on the keybinds you set
  it as options? really?... thats awful"), so copying it walks back his call.
- `ui.lua:3138` carries their own crash note: a keybind callback that touched a
  UObject **crashed their game**; their rule is the same marshal-first we
  already do — which UE4SS issue #1345 says is too late by construction.

**Their docs are still worth mining — three techniques we do not use:**
1. **`IsValid()` does not prove SAME object.** Freeze `GetFullName()` when a
   wrapper is accepted, compare before every use, evict on mismatch. Directly
   applicable to our cached actors (`trackedBars`, `pawnByPalId`, `FollowerActors`).
2. **"Every crash our instrumentation ever attributed was inside a TIMER poll.
   Zero were inside hook callbacks."** An object a hook hands you was vouched
   for at that instant; one a poll discovered is stale by construction. **This
   is a caution against the polling fix proposed above** — it must re-acquire
   the controller fresh, not cache it.
3. **Compare crash stack OFFSETS before trusting any log-tail attribution** —
   two of their "obvious" suspects were exonerated by byte-identical stacks
   appearing with the suspect disabled.

**Applying #3 to our five crashes:** no two are identical. crash1/crash2 share 8
offsets, run3 shares 7 with them and 9 with crash3, run2 shares almost nothing.
But **four of the five have their top frames inside the same UE4SS region
(`bcd`–`bdd`)**. Scattered fault points within one subsystem is what a corrupted
VM looks like; a single broken call site would give a repeating stack. That
supports the concurrency theory — and note we still have **no crash stack from a
run with the suspect disabled**, because run 1 simply never crashed.

## RUN 3: THE LUA VM IS PROVABLY BEING CORRUPTED (2026-09-26 12:31)

Crash while flying, `EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff`,
39 UE4SS frames over a deep Palworld chain — the crash-1/2 shape. Archived as
`docs/bug-reports/2026-09-26_run3-menu-on-AV-flying.log` and
`2026-09-26_run3-menu-on-AV.runtime-xml`.

**The find is in UE4SS.log, not the trace:**

```
12:28:17.848  [Menu] page opened / any key can now be bound (154 key(s) watched)
12:28:18.091  [ENFORCE] the sense budget skipped 53 sense(s) in the last second
12:29:00.324  Error: [Lua::call_function] lua_pcall returned LUA_ERRERR
                                          => error in error handling
12:31:59      crash
```

**`LUA_ERRERR` is an error raised while handling an error** — the classic
fingerprint of a `lua_State` whose stack has been trampled, which is what
concurrent use of one VM produces. It appeared **43 seconds after the menu armed
its 154 key watchers**, and the game limped on for three more minutes.

**Second corroboration in the same run:** `gauge.boss` = 20 entries,
`gauge.boss.done` = **10**. Ten boss-gauge hook invocations entered Lua and
never came back out. Every other traced pair balances exactly
(`gauge.bind` 159/159, `gauge.unbind` 151/151, `sense.enforce` 166/166,
`cache.stableid` 166/166).

**Scoreboard across the three trace runs:**

| | screen never opened | screen opened (run 2) | screen opened (run 3) |
|---|---|---|---|
| lasted | 15 min, clean | 14 s | 3 m 45 s |
| `sense.get` | 15,842 | 353 | 5,283 |
| VM damage | none | died inside `Context:get()`, `abort()` | `LUA_ERRERR` + 10 lost hook calls |

**What the trace did NOT do this time, stated honestly:** run 3's last line is
`sense.addr`, which is *also* the normal early-out for the ~97% of senses that
hit the address dedup — so it is ambiguous between "died inside
`sensor:GetAddress()`" and "returned normally and the crash was elsewhere".
**Instrumentation gap to close:** add one trace immediately AFTER the
`GetAddress()` call so those two cases are distinguishable.

**The leak fix is confirmed working.** Tracked bars per scan this run:
0 → 22 → 49 → 61 → 50 → 55 → 30 → 13 → 24 — it plateaus and oscillates, with 50
`[PRUNE]` lines actively releasing. Run 1 at the same elapsed time was at ~287
and climbing in a straight line to 603.

## RUN 2 RESULT: THE TRACE NAMED IT, AND DRAGÓN WAS RIGHT (2026-09-26 03:13)

**Crashed 14 seconds after the settings screen was opened.** Log archived as
`docs/bug-reports/2026-09-26_run2-menu-on-TRACE-CRASH.log`, crash context as
`2026-09-26_run2-menu-on-abort.runtime-xml`.

**The trace pinned the exact call.** 353 `sense.get` lines, 352 `sense.addr`
lines — exactly one unmatched, and it is the last line in the file:

```
[T0001017 52.147] sense.get      <-- no sense.addr ever followed
```

`sense.get` is written immediately before `Context:get()` in the
`SelectResponseBySenses` hook (`Personality.lua`). The process died inside that
call. Every other one of the 352 completed.

**The contrast is the result:**

| | Run 1 (screen absent) | Run 2 (screen opened) |
|---|---|---|
| duration | ~15 min | ~14 s after opening it |
| `sense.get` calls | 15,842 | 353 |
| keybind watchers | 3 | **157** (3 + the menu's 154) |
| crash | none | yes |

03:13:01 `page opened` + `154 key(s) watched`; 03:13:15 abort. Run 1 survived
forty-five times as many sense calls with the screen gone.

**New signature: `Abort signal received`, not an access violation** — a C++
exception escaping into `std::terminate`, which a Lua `pcall` cannot catch. But
the stack shares frame `UE4SS+bd59e3` with crash 3 (00:13), the one whose shape
matches all three player reports. Same subsystem, two ways of dying.

**Mechanism (now the working theory, was speculation last turn): a race on the
Lua state.** `RegisterKeyBind` callbacks run on **UE4SS's own thread** — this
file already knew that, it is written in `Menu.lua`'s own comment at the capture
block. The handler marshals its *work* to the game thread via `on_game_thread`,
but the `if capturing == nil then return end` check still executes in the Lua VM
on UE4SS's thread. With 157 watchers and keys held down while flying, that
happens constantly, and the game thread is simultaneously inside `Context:get()`
in the sense hook. Two threads, one `lua_State`.

**This also explains the players**, which is what makes it more than a menu bug:
Esaeon, Swordfish and Hakaishin have **three** keybinds registered permanently
(F8/F9/F10 via Interaction's `bind_key`) and no menu at all. Same race, roughly
fifty times rarer — which is exactly "rare", "after a while of simply running
around", and "seconds after the third pet".

**So reducing the count is not the fix.** Three is already enough to crash
players. The fix has to get the mod's key handling off UE4SS's thread entirely,
or make the handler never enter the Lua VM from it. Options, none chosen yet
(Dragón's call):
1. **Immediate mitigation:** stop arming the 154 watchers — returns Dragón to
   player-level risk, does not fix players.
2. **The real fix:** read key presses from a game-thread source instead of
   `RegisterKeyBind` (a hooked game input function), so nothing enters Lua off
   the game thread. Would fix the player crashes too. Needs research first:
   confirm UE4SS's dispatch model, and find a usable game-side input hook.

**Before committing to option 2, verify the threading claim properly** rather
than inferring it from stacks with no game frames.

## ACTIVE: THE CRASH — Dragón reproduced it himself (2026-09-26)

**This is the open player crash, not a new one, and it is now reproducible on
Dragón's own machine.** That is the thing this project has been blocked on
since 19 September, waiting for players to test for us.

**Four crashes in one evening, three with a full Windows crash context**
(archived as `docs/bug-reports/2026-09-26_dragon-UECC-*.runtime-xml`, and the
last run's live log as `2026-09-26_dragon-crash4-petallia.log`):

| # | Time | Dragón was doing | Address | Stack shape |
|---|------|------------------|---------|-------------|
| 1 | 23:50:08 | flying, watching Pals | `0xffffffffffffffff` | UE4SS ×9 ← **Palworld ×5** ← UE4SS |
| 2 | 00:04:40 | flying again | `0x24b31c9a909` | UE4SS ×9 ← **Palworld ×5** ← UE4SS |
| 3 | 00:13:02 | boss Lyleen following | `0x0` | **ucrtbase memcpy** ← UE4SS ×15, no game frames |
| 4 | 00:41:07 | bonding a Petallia | — | UE4SS dump only, no context file |

**Crash 3's shape is Esaeon's and Hakaishin's** (CRT `memcpy` on top, UE4SS
Lua frames below, no game frames, reading `0x0`). Different UE4SS builds so the
offsets differ, but the shape is the same, and Hakaishin's was singleplayer
with PalBonds alone. **Crashes 1 and 2 are a second shape**: Palworld frames
*underneath* the UE4SS frames, i.e. the game called a hook, which called our
Lua, which died.

**Ruled out — the settings screen / keybind capture.** Dragón's own theory, and
the stacks kill it: a UE4SS keybind fires on UE4SS's own thread with no game
frames below it, which is not what crashes 1 and 2 show. For crash 4 the log is
direct: capture ran 00:38:31→00:38:32 and ended cleanly, then two and a half
minutes of normal play before the crash. The Q/E tab-steal leaves the capture
sitting and waiting; it holds nothing and touches no game object.

**Working hypothesis (NOT established):** a cached `UObject` pointer read after
the engine recycled that address. Three *different* faulting addresses (`0x0`,
`-1`, and a misaligned heap address) is the signature of reading a field off an
object of the wrong type, not a null we forgot to check. UE4SS's `IsValid()`
returns true for a recycled address, so every `IsValid` guard in the mod passes
and the read still goes to garbage. The `memcpy` on top of crash 3 fits:
building a Lua string from a garbage FName length.
**Prime suspect: the `SelectResponseBySenses` hook** (`Personality.lua`) —
fires from deep in the game's AI for every Pal that senses anything, dedupes on
raw addresses (`handledSensorAddresses`) and holds pawns in `pawnByPalId` /
`cachedSensorByPalId` between prunes. Flying = maximum actor churn = maximum
address reuse, which is crashes 1 and 2. The crash run's log shows it saturated
("the sense budget skipped 2… 4… 8 senses in the last second").

### The trace run — BUILT AND DEPLOYED, awaiting Dragón's test

`Logger.trace` (built 2026-09-20 for Esaeon, never used by us) now writes
through its **own** path: no `print` (UE4SS's console is the expensive part of a
log line), no `os.date`, a monotonic sequence number, and the per-line flush
kept — the last line written is the operation that killed the process.
Self-tested against the deployed file (format, sequence, detail, flush count).

Trace points added at the hook entries and cached-pointer loops that had none:
`sense.*` (step level, one line per engine call — the suspect), `cache.*`,
`gauge.bind.*` / `gauge.unbind.*` / `gauge.boss.*`, `bar.entry` (Indicator's
tracked-bar loop, keyed), `trainer.step` / `trainer.follower` (after the
early-out, so a flight with no follower stays silent), `dmg.reaction`,
`dmg.hate`.

**The settings screen is OFF for this run — Dragón's call**, as the experiment
that confirms the analysis instead of arguing it: `MENU_ENABLED = false` in
`main.lua`, and `Menu.lua` renamed to `Menu.lua.DISABLED-crash-test` in the
deployed copy so it cannot load at all (Interaction's `WaitingForKey` lookup
fails safely — no screen means nothing is ever waiting for a key).
- still crashes → the screen is cleared, read the trace lines.
- does not crash → the screen or something shipped with it IS involved.

**Deployed to the manual install only**
(`Pal/Binaries/Win64/ue4ss/Mods/PalBonds/Scripts/`), with `DEBUG_LOGGING` and
`TRACE_PHASES` both true. That is the copy that actually runs: `dwmapi.dll` is
present, its files are current, and it is the one that wrote tonight's log. The
Workshop native-mods copy is a stale release build whose loader is not running
(exactly one `mod loading` line in UE4SS.log). **Release staging was
deliberately NOT touched** — this is a diagnostic build.
Tests: 27/27 suites pass against `mod/`; 26/27 against the deployed copy, the
one failure being `menutest`, which fails *because* the menu is gone.

**To restore afterwards:** `MENU_ENABLED = true` in `main.lua`, copy `Menu.lua`
from `mod/` into the live install (the parked `Menu.lua.DISABLED-crash-test`
there is now stale — it is only a marker), and set `TRACE_PHASES = false`.

### RUN 1 RESULT (2026-09-26, ~15 min): no crash, and it found a real leak

Dragón flew and watched Pals for about fifteen minutes with the screen off and
the trace on. **No crash.** That does NOT clear the settings screen — nothing
reproduced, so the comparison has no result either way; what the run actually
bought us is the leak below. 196,115 log lines, 11 MB, no errors, and zero
`PalBonds/Menu` lines, so the switch-off genuinely took.

The sense hook, the prime suspect, came out well: 15,842 calls but only 677 got
past the cheap address dedup — a 96% early-out. It is not the hot path.

**89% of the run was one loop.** `bar.entry` fired 139,454 times. Tracked bars
per scan, over the flight: 0 → 56 → 215 → 339 → 467 → 584 → 603, a straight
line with no plateau. 636 entries created, ~603 still alive at the end, and the
first Pal whose nameplate he saw fourteen minutes earlier was still being
re-validated every two seconds.

**Dragón connected it to something he had reported weeks earlier** — the game
feeling laggier the longer he played — which had been blamed at the time on the
debug log accumulating. That explanation was never measured and was very likely
wrong. This one is measured.

**FIXED (2026-09-26), `Indicator.lua`:** the tracked-bar cache now expires.
`TRACKED_BAR_UNSEEN_PRUNE_SECONDS = 60.0`. Presence is read from
`gaugeHandleByKey` — the bind hook fills it, the unbind hook clears it — so an
entry whose nameplate is on screen refreshes itself with **one table lookup and
no reflection**, and an entry left behind ages out. On prune,
`release_tracked_entry` detaches our bar and label from the pooled gauge (the
same `RemoveChild` pattern `reparent_existing_bar` already uses) and frees
`barInstalledForGauge` for that gauge, compared by address. Keeping the entry
past its gauge's recycle is still deliberate — that is what
`reparent_existing_bar` reuses — the cache just has an expiry now.
`Indicator.BindCounts()` gained a third return (the tracked-bar count) so the
table is countable from outside.

### RUN 2 — Dragón's call, and he was right to insist (2026-09-26)

Claude argued the menu-on comparison was not worth doing because it would
probably also not crash. Dragón: *"but if we turn the log on and i do exactly
the same thing as before and if it does crash, wouldnt that help us prove that
maybe the menu or something on the menu's new code is causing the crash?"* That
is correct and the objection was lopsided — it weighed only the null outcome. A
crash in run 2 would be the strongest evidence this investigation has had.

**THE SCREEN HAS TO BE OPENED for the run to test anything.** `arm_capture()`
runs from `open_page`, not from `Menu.Init`, and it is the only place the ~154
`RegisterKeyBind` calls happen (guarded by `captureArmed`, so once per session).
A run with the menu present but never opened does not exercise the new code.

**Mechanism worth taking seriously — a Lua-state data race.** Each of those 154
watchers fires on **UE4SS's own thread** for every key press for the rest of the
session (the handler's own comment says so). While flying, keys are held down
constantly. If UE4SS's keybind thread enters the Lua state while a game-thread
hook is already in it, that is a race on the VM, and a corrupted VM produces
exactly the signatures seen: `memcpy` on a garbage length, reads of `0x0` and
`0xffffffffffffffff`. **It would also explain the player reports**: they have
three keybinds registered permanently (F8/F9/F10 via Interaction's `bind_key`),
so the same race, roughly fifty times less often. Untested speculation, but it
fits every data point including the ones the menu cannot be blamed for.

**Correction to the earlier analysis:** ruling the keybind path out was right
for crashes 1 and 2 (Palworld frames present = game thread) but NOT for crash 3,
whose stack has no game frames at all — which is what a UE4SS-thread crash looks
like. The shape does not discriminate there.

**Run 2 protocol:** menu ON, leak fix ON, trace ON. Open the PalBonds screen
once at the start. Fly the same way for **30+ minutes** — run 1 was ~15 min and
crash 4 came 28 minutes into its session, so run 1 may simply have been short.
The leak fix stays ON deliberately: the leak is now a known confound, so
removing it makes a crash more attributable to the menu, and run 1 had the leak
present without crashing.

Covered by **perffixtest section D** (8 checks), which tests both directions as
that suite's header requires: a nameplate still bound is NOT pruned after ten
minutes, an unbound one is kept for 30s so reuse still works, past the window it
is dropped AND its widgets are detached, the gauge can host a Pal again
afterwards, and a 25-Pal flyby tracks all 25 in view and releases all 25 once
they are behind you. Verified to fail against the unfixed code (3 checks fail,
25 entries stuck). 27/27 suites pass; deployed.

## TOMORROW STARTS HERE (end of 2026-09-20)

**Today shipped 1.1.6 to all three places and then spent the rest of the day on
multiplayer.** Everything below is committed but NOT released: players still
have 1.1.6.

**State of the machine:** manual dev install ENABLED (`dwmapi.dll`,
`enabled.txt`), Workshop mods unticked, the game copy carries `mod/` with
`DEBUG_LOGGING = true` AND `SHOW_DIAGNOSTICS = true` (Dragón's standing rule:
in dev mode use whatever logging the work needs; strip it at release). `mod/`
itself has both false. A local Palworld **dedicated server** (Steam tool, free)
is installed and is how a GUEST session is tested without a second person.

**Built today, in order:**
1. **Which player is ours** — every lookup prefers the locally controlled
   character. Live-verified; the engine answers the question on this build.
2. **A Pal bonding with another player is left alone** — detected from the Pal
   (its follow action names a player who is not us), refused in the radial menu
   (before any food is spent), in Play and in the grant; `tag_claimed` in all 16
   languages. Harness-tested only: needs two real players.
3. **A guest's copy does nothing** (`Scripts/Session.lua`, NEW FILE — it must
   reach both release trees and the zip at the next release, the PlayerRef.lua
   trap from 1.1.2). Three live runs to get right; the last one is clean.
4. **Duplicate "starts following you"** fixed (pointstest P13).
5. **Missing trust bar after a reload** fixed (worldchangetest I).

**Verified by Dragón in game:** 1, 3, 4, 5 and the singleplayer regression of
all of them. **Not verified:** 2 (needs a friend).

**Next, in his stated order:** multiplayer, then the in-game settings screen,
then releasing Pals back to the wild ("an extra out of scope from this
project"). **Corrected by Dragón 2026-09-23:** that order was never a queue to
wait in -- "if we cannot continue developing multiplayer because we still need
some tests and another player to do so, then we simply advance with whatever we
can". Blocked work never blocks the rest. The immediate options are written up in
`docs/multiplayer-questions.md`:
- a two-player session with a friend (the only thing that can confirm the claim
  system and answer what each player sees);
- or investigate `ChallengeCapture_ToServer` and the other 335 `*_ToServer`
  RPCs, which is how a guest could ever do anything — testable alone on the
  dedicated server.

**The rubric does not move today:** multiplayer is not one of its categories and
nothing in the shipped feature set changed. Recalculate when the settings screen
lands or when co-op becomes a real, released feature.

## 1.1.7 BUILT AND READY TO PUBLISH (2026-09-23) -- Dragón's go-ahead

Co-op ships. His reasoning: no friend with a PC has been found, one machine has
tested everything it can, so players become the test ("what if we ship it and
just let players themselves tell us if they can now play with it or not").

Built and verified before packaging:
- `Session.ALLOW_GUEST_INPUT = true` (was `GUEST_INPUT_PROBE`, shipped false).
  Set it to false to put a guest back to 1.1.6 behaviour.
- The guest-food hole closed: a guest names the inventory slot to charge, so
  the owner now checks that container is that player's OWN (their inventory
  data's six container ids) before taking anything.
- Server test settings file deleted (it had `Pet = 125`); source defaults
  untouched at 50.
- All 24 suites pass AGAINST `release/PalBonds/Scripts` itself, not just
  `mod/`; hoist 2 / undef 4 known false positives; no dev flag on anywhere.
- PERFORMANCE, measured not guessed (PresentMon, `perf-captures/2026-09-23_*`):
  singleplayer 1.1.6 = 73.1 fps avg / 1% low 35.4 / 11.5 hitches per min;
  the co-op build = 77.1 / 41.0 / 7.5. No repeating stall series in either, so
  no timer of ours stutters the game. As a guest on the local dedicated server:
  66.0 / 42.3 / 4.5 standing still, and 54.7 / 17.7 / 24.0 while actually
  playing (hitches spread evenly, none periodic -- action-triggered work, the
  radial-menu target search being the known 40-80 ms one). Dragón's earlier
  "significantly laggier" was dev logging + the UE4SS console, both off now.
- Release trees, zip and README updated: `release/PalBonds` and
  `release/workshop/PalBonds` hold the 14 scripts (the three new files are
  `Net.lua`, `HostView.lua`, `Session.lua`), `Info.json` Version 1.1.7,
  `release/PalBonds-v1.1.7.zip` (17 entries, forward-slash paths),
  README has a new MULTIPLAYER section.
- Both installs (game + server) now hold the EXACT release scripts, logging
  off, for a smoke run. The dev `Logger.lua` (DEBUG + diagnostics true) and
  `ue4ss/UE4SS-settings.ini.devconsole-backup` restore development conditions.
- **NEXUS: LIVE** (2026-09-23, 10:08PM page time): version 1.1.7, one main
  file "PalBonds V1.1.7" (330 KB = our zip's 338,680 bytes), Dragón's six-line
  changelog as agreed, his own short description. Page description untouched.
- **WORKSHOP: prepared, not uploaded.** The upload folder
  (`steamapps/workshop/content/1623730/3797816321/`) and both installed copies
  (`Mods/NativeMods/UE4SS/Mods/PalBonds/Scripts`, `Mods/ManagedMods/PalBonds/
  Info.json`) carry the 14 release scripts and Version 1.1.7, BOMs kept,
  `.workshop.json` untouched -- so his Workshop test runs the real 1.1.7.
- **Dev stack DISABLED for that test:** `Pal/Binaries/Win64/dwmapi.dll` and
  `ue4ss/Mods/PalBonds/enabled.txt` both renamed `*.MODS-DISABLED`. Undo both
  to develop again.
- NOT done, waiting on Dragón: the Workshop upload itself; GitHub (commit,
  release); and deleting `release/PalBonds-v1.1.6.zip` as previous releases did.
- KNOWN UNTESTED at ship time, by anybody: two real players at once (claims,
  one leaving mid-bond), a hosted world where the host also plays, the dungeon
  RESYNC, and whether the guest's own food count updates on screen.

## 1.1.8 SHIPPED TO NEXUS + CURSEFORGE (2026-09-25)

**Nexus LIVE, verified on the page:** header 1.1.8, file "PalBonds V1.1.8",
100 KB (our zip is 103,270 bytes), uploaded 3:56PM, Dragón's changelog and his
short description. **CurseForge: a THIRD store now** -- he uploaded there too
and says moderation takes a long time to approve a file. **Workshop LIVE**,
verified after his test run (`last_published_version` 1.1.8).

**What 1.1.8 is, beyond the clean-ship pass below:**
- **The mounted-identity bug, found the day of release.** On a mount the
  player's own character answers `IsLocallyControlled = false`. PlayerRef's
  `Get` was fixed for that first (the game names our character:
  `UPalUtility::GetPlayerCharacter`), but `IsRemote` and `OwnerKey` still
  believed the engine, so while riding the mod treated Dragón as ANOTHER
  player: his F9 toast and every "left behind" message went into the co-op
  network path ("could not send MSG to a player: no controller") instead of
  onto his screen, and the second F9 press CRASHED
  (`EXCEPTION_ACCESS_VIOLATION`, log at
  `docs/bug-reports/2026-09-25_f9-mounted-crash.log`). Identity is now a
  comparison against the character the game names. The `IsLocallyControlled`
  fallback still exists for co-op, but is unreachable in a singleplayer
  session (`Session.ModeIfKnown()`), so the lie can no longer reach the
  network path where it crashed. Removing the fallback outright was tried and
  broke co-op in 28 checks -- that is why it is fenced rather than deleted.
  Regression test: nettest H0.
- **Performance, measured (perf-captures/2026-09-2[45]_*):** flying, the mod
  went from 25.3 s of game-thread time per 2 minutes to 3.9 s; hitches with
  the mod on went 61/min -> 30/min against 17/min with it off; the false
  world-wipes while flying (27 nameplate bars, 39 personality records, once a
  live follower) are gone. Fixes: the world change is detected from the game's
  own loading events (`LoadingFinished`, the loading-screen widget) with the
  old poll demoted to a 10 s safety net needing two misses; Session no longer
  asks UEHelpers for the world (it walked the object list looking for a
  PlayerController, 43 ms a call); the sense hook has a refilling per-second
  budget; the nameplate sweep builds at most 4 bars per tick.
- **Dragón's verdict before shipping:** tested singleplayer and as a guest,
  nothing broken, toasts and abandonment correct, no crash.

## SETTINGS SCREEN — milestone 9: the polish pass (2026-09-25)

**THE KEYBOARD HOLD WORKS.** Confirmed live: with the phantom-capture bug fixed
there was finally a real capture for it to block, and `SetInputMode_UIOnlyEx`
does stop the game acting on the key being chosen. **Except Q and E.**

### Q and E, and why they are different
They are the game's own menu-tab navigation, routed through its UI layer --
above where input mode reaches, because input mode governs GAMEPLAY input. There
is no Lua-reachable way to consume a CommonUI action. The binding itself still
takes; what leaked was the tab moving underneath our page. Mitigated rather than
fixed: after a key is chosen, everything the page covers is covered again, so it
is never left sitting over a tab the player did not choose. **Excluding Q and E
from being bindable was deliberately NOT done** -- that is the "limiting which
keys the player may have" that Dragón rejected on 2026-09-25.

### The rest of the pass
- **Play now refuses a switched-off personality.** It does not go through the
  radial menu, so the substitution gate that hides Pet and Feed could not cover
  it -- it earned nothing, but the animation still played. "Immune" should mean
  immune.
- **A rebind row is lettered like the rows around it.** It is the one row whose
  label the mod draws itself, at its own size; the size is now read from the
  first native row built and reused, so it cannot drift from the game's.
- **Nothing is said when a change simply works.** The note line printed the
  setting's INTERNAL NAME and value -- code words in front of a player, about a
  row they can already see. It is now only used for the two things a row cannot
  say by itself: a refusal (named the way the player sees it, not by its key)
  and "Saved".
- **`PassiveGainEnabled`**, a switch in Modules: where passive friendship gain
  STARTS, the same shape as ShowPersonalityTags. The key still toggles it for the
  session, and it is per machine while the toggle stays per player, so a guest's
  key still only switches their own followers. The toggle's own message no longer
  claims it returns to ON next launch -- it returns to the setting.

37 settings across 6 sections. All 25 suites pass; menutest 176 checks,
settingstest 208.

## SETTINGS SCREEN — milestone 8: the rebind bug, and balancing (2026-09-25)

### The rebind was binding a key nobody pressed
Dragón: *"i never pressed the d for rebind, it changed to that the first time
automatically"*. The log has it exactly: `any key can now be bound (154 key(s)
watched)` and `Play is now D` in the SAME SECOND, six seconds after the page
opened -- i.e. the instant he clicked the rebind button.

**Cause:** `arm_capture` ran inside `begin_capture`. Registering ~150 key
watchers is not instantaneous -- UE4SS's own thread fires them a moment later --
so that first burst arrived when `capturing` had ALREADY been set, and was taken
as the player's answer.

**And this explains the second symptom too.** *"if i try to change it to a key
that already does something in the game, it triggers the game instead of setting
a new key"*: the spurious capture ENDED the capture and handed the keyboard back
within milliseconds, so the key he then actually pressed reached the game
normally. One cause, both complaints. **Whether `SetInputMode_UIOnlyEx` really
blocks input has therefore still never been tested** -- there was never a live
capture for it to block. The log now says `holding the keyboard while a key is
chosen` when the call succeeds, so the next run answers it outright.

**Fix:** the watchers are armed when the PAGE OPENS, so the burst lands while
nothing is waiting and is ignored; plus a 0.25 s settle window, so nothing that
arrives in the same instant as the click can ever be an answer. Both pinned by
tests. (It had to be `open_page` rather than `build_page`: `arm_capture` is
declared below build_page and a Lua local declared further down is not in scope
above it -- the same lexical-scope trap this file has now hit three times.)

Cost of arming earlier: a player who opens the screen once carries ~150 inert
watchers for the session. Each returns on a single nil test when nothing is
waiting.

### The bonding switch was reading the wrong field
Switching Feral off did nothing to the Feral Pals in front of him. It was keyed
on `GetRolledTier`; **the tag the player sees comes from `GetDisposition`**, and
they are not the same: a Pal whose SPECIES is already Kill_All is kept out of the
roll and carries `rolledTier = "normal"` while wearing the Feral tag. Now keyed
on the disposition, using Indicator's own `PERSONALITY_DISPLAY_NAMES`
vocabulary, so the switch and the tag can only ever agree.

**And the option no longer appears at all** (*"it should fail from the beginning,
not even letting the option appear at all"*). The game's radial menu only offers
a WILD Pal because of the mod's own `TryGetSpawnedOtomo` substitution, so
refusing to substitute a non-bondable Pal means there is nothing to refuse later:
no Pet, no Feed, no Play, and no food spent finding out.

### Balancing (his numbers, both confirmed against the code first)
- `MAX_FOLLOW_DISTANCE` **3000 -> 3500** (Trust.lua) -- the distance a follower
  starts losing trust at and is eventually abandoned.
- `PLAY_HAPPY_FOLLOWUP_DELAY_MS` **6000 -> 5000** (Interaction.lua) -- Play's
  animation follow-up. A stale comment in Trust.lua calling it "Play's 3000ms"
  was corrected while in there.

### The two fruits
They now carry the game's ENGLISH item name in brackets wherever the label is
not already English -- "Fruta de afecto (Kinship Peach)", "Kleine
Zuneigungsfrucht (Little Kinship Peach)". His instruction, and the reasoning is
worth keeping: this project has never had the item's real name in the other 15
languages, and a translation of our own invention leaves a player unable to tell
WHICH item a row means; the English name is the one they can match against a
guide or the wiki.

## SETTINGS SCREEN — milestone 7: a personality can be switched off (2026-09-25)

Dragón: *"i was thinking of adding a check if a personality can be bonded or not,
for players that maybe dont want some personalities to be interactable at all
(like feral or aloof, etc)"*. Built. The screen now carries **36 settings across
6 sections**.

**Layout (his pick, asked before building):** each personality is now two rows --
its chance, then a switch directly under it reading "Curious — can be bonded", so
a personality's two settings are always read together. The label is composed from
`labelPrefix`, which puts the tag's OWN translated word in front of one shared
string: seven switches cost one new translation, and the switch can never end up
worded differently from the tag on the Pal's head.

**What such a Pal shows (also his pick):** the tag, but no bar. The tag is how
the player knows to leave it alone; a bar that could never fill would read as
broken. Switching one off mid-session hides the bars already on screen.

**Where it is enforced, and why there:**
- `Trust.MayBond` -- the function that refuses an interaction BEFORE any food is
  spent, so a switched-off personality never costs the player an item.
- `Trust.AddPoints` -- the funnel every points path in the mod ends in, as the
  backstop, so nothing can slip past by taking another route.
- **Unknown means allowed.** A Pal that has not rolled a personality yet is never
  refused by a switch that cannot apply to it.

**Tested:** a Feral Pal earns points with its switch on and nothing at all with
it off, through MayBond and AddPoints both; another personality is untouched;
every tier the roll can produce is checked to HAVE a switch (so one cannot be
silently unswitchable) and each switch to be a real setting; and the row is
verified to sit directly under its own chance, named after its tag, translating
with the rest of the screen.

## THE TWO WORDS: trust vs friendship — SETTLED, DO NOT "FIX" (2026-09-25)

**The settings screen says FRIENDSHIP points. The toasts still say TRUST. That
is deliberate and it is Dragón's ruling, not an inconsistency to tidy up.**

His reasoning, which is the part worth keeping: *"we are doing this for the
settings to not confuse the players, they already know the base game as trust
points and ranks, so if we call our bar 'trust' to modify, they may think they
will be modifying the trust from the base game instead of our made up points"*.

So the rule is about WHERE the word appears, not which word is right:
- **On the settings screen**, where a player is changing numbers, ours must read
  as *friendship points* — otherwise they think they are editing the base game's
  trust stat and that the mod is reaching into vanilla systems.
- **In the toasts and messages**, during play, "trust" keeps reading naturally
  and there is nothing to confuse it with, so the shipped strings in 16 languages
  stay exactly as they are. Asked directly whether to change them: *"dont think
  of changing the toasts messages"*.

## SETTINGS SCREEN — milestone 6: the two switches cover everything (2026-09-25)

A disabled trigger that still shows its message reads as a broken setting, so
each switch now turns off everything the player would otherwise see:

- **Abandonment off also silences the despawn message**, in both places it can
  come from (the loading-screen flush and the despawn path). Dragón: *"lets let
  them just asume their pals despawned and thats it"*. The Pal is still gone --
  the game despawned it -- the player is simply not told it gave up on them.
- **Betrayal off means a hit costs NOTHING.** Not a smaller penalty and not a
  penalty without the ending: no points lost, no trust-shaken effect, no
  betrayal. His framing: *"lets consider it as an on/off to reduce friendship
  points from player hits"*. The test is the first line of
  `Trust.OnFollowerDamaged`, ahead of everything that is a penalty in any form.
- `trigger_enabled` moved up to sit beside `BONDING_TRIGGER_THRESHOLD_BASE`,
  because the world-change message asks it far earlier in the file than the
  bond-loss path does.

Tested behaviourally: with betrayal off a Pal keeps every point through six
hits and no shaken effect fires; with it on the points drop. All 25 suites pass.

## SETTINGS SCREEN — milestone 5: second screenshot pass (2026-09-25)

Eleven items from a live test. All done; all 25 suites pass (menutest 162
checks, settingstest 176).

### The bugs
- **Save now saves WITHOUT closing.** It used to close, and with the page gone
  the only feedback was the screen vanishing -- which reads exactly like "save
  doesnt save, instead quits the screen". It writes, says "Saved" on the page,
  and stays. **And saving now moves the point Cancel goes back to**, or a Cancel
  after a Save would have undone the values just written to the file.
- **Changing the language rewrites the screen in front of you.** The subtitle
  promised it and it did not happen. Every label, heading, hint and button is
  registered as it is built and rewritten from Locale on a language change, and
  the lists rebuild their own choices. **The reason it silently did nothing at
  first: `refresh_texts` was defined AFTER `sync_control`, so the upvalue was nil
  and its own `pcall` swallowed the failure** -- forward-declared now.
- **The rebind row no longer overflows the list.** It was a HorizontalBox, which
  inside a ScrollBox is given as much width as its children ask for, so the
  fixed-width button hung past the right edge and was clipped. It is an Overlay
  now: it fills the width it is GIVEN and right-aligns the button, clear of the
  scrollbar.
- **Hovering no longer rebinds.** `WBP_OptionSettings_MenuButton_C`'s delegate
  fires on HOVER -- Dragón could not move the mouse across the screen without a
  row demanding a key. The rebind buttons are now `WBP_MenuESC_Button_S_C`, the
  class this file already proves is click-only (the entry, Save, Cancel and
  Restore defaults all use it).
- **The keyboard is held while the screen waits for a key.** Pressing the
  inventory key opened the inventory instead of binding it. UE4SS cannot swallow
  a key, but the engine can be told to stop routing input to gameplay:
  `SetInputMode_UIOnlyEx`, which is what the game's own modal screens use. Our
  bindings are UE4SS-level and still fire, so the key can be read without the
  game acting on it. **Every exit path hands the keyboard back** -- a chosen key,
  a second click, the page closing, the menu being destroyed -- **and an 8 s
  timeout on top**, because the one unacceptable outcome is a player who cannot
  move. All five paths are tested.

### The wording
- **Ours are FRIENDSHIP points.** Dragón's rule: the game's own UI calls its stat
  trust points, so naming ours the same points the player at the wrong system.
  The section is "Friendship points" in all 16 languages.
- **"While a Pal follows you" → "Passive friendship gain while following".**
- **"Display" → "Modules"**, on the screen and in a freshly written file.

### The new settings
- **Modules:** `AbandonmentEnabled` and `BetrayalEnabled`, both switches. The
  gate is inside `on_follower_lost_all_trust`, the single point both endings pass
  through, ahead of everything it guards; with one off the bond survives and the
  points are floored at 5% of the bar so the same check cannot fire again on the
  next tick.
- **Accessibility (new section):** `BarColor`, `TagColor` (including "same as the
  name", which is what it has always been) and `TagSize`. A new schema kind,
  `choice`, validates a value against a list the entry itself carries, so the
  file, the screen and the check all read the same one. The tag size is a SCALE
  on the Pal's own name font, so it is right at any UI scale. Changing any of
  them redraws the Pals already on screen (`Indicator.RefreshAppearance`).
  - **hoistcheck earned its keep twice here:** the colour table and then
    `compute_trust_bar_color` were both left BELOW code that reads them, and a
    Lua local declared further down resolves to a nil global -- the tag colour
    would have silently never applied.

### Open
- **The toasts still say "trust"** (`passive_on`, `passive_off`, and the bond-lost
  messages). Those are shipped text in 16 languages; the terminology rule above
  implies they should say friendship too, but rewriting live player-facing
  strings is Dragón's call, not a silent edit.
- The two fruit labels still name an in-game item in wording of our own.
- Nothing is committed or pushed.

## SETTINGS SCREEN — milestone 4: Dragón's screenshot pass (2026-09-25)

He sent a screenshot of the working screen plus a list. All of it is done.

- **Language is first** now, on the screen and in a freshly written settings
  file (the LANGUAGE block moved to the top of SCHEMA; an existing file keeps its
  own order, and the in-place save finds a key by name, never by position).
- **Every interaction and every food shares one 0..1000 scale, step 10** (Pet,
  Play, FeedBase, the five rarity bonuses, both fruits), and **the passive drip
  has its own 0..100, step 1** -- his numbers, after using the first version.
- **The title, the subtitle and the note line are centred TEXT, not centred
  boxes.** That was the bug in the screenshot: a TextBlock draws left inside its
  slot, so a slot centred on the canvas still leaves the words off to the left.
  `SetJustification(1)` on each, and they span the panel rather than a fixed 700.
- **Three buttons at the bottom: Save, Cancel, Restore defaults.** Cancel is only
  possible because the page snapshots every value when it opens; it restores that
  snapshot live and then `Settings.Discard()`s the pending writes, so the file is
  untouched. Save writes and closes. Restore defaults applies the shipped values
  live and deliberately LEAVES THE PAGE OPEN, so the player can still cancel out
  of it. Bulk restores run in two passes, because "Play = F8" is refused while
  Tags is still sitting on F8 and succeeds once it has moved.
- **The language list shows language names** (Español, 日本語, ...) instead of
  the codes the screenshot showed -- a code name in front of a player is the same
  mistake as the labels were. The stored value is still the code.
- The last row can scroll clear of the bottom edge (a trailing spacer), and the
  rebind buttons sit inside their rows instead of filling them edge to edge.

### Two guards added after looking at his live settings file
His file came back with a lot of zeros. The file itself was **structurally
perfect** -- same 88 lines, same 51 comment lines, every comment in place -- so
the save path is sound, and the values were his own test drags. But the
inspection surfaced two ways this screen COULD have done it by itself, and both
are now closed and tested:
1. **A row is not believed until it hands back the value we put in it.** A native
   row that has not laid out yet can report 0, and the watch would have taken
   that for the player's choice and saved it -- a settings screen that empties
   your settings just by being opened. Bounded to 5 tries so a value a widget
   genuinely cannot hold is followed rather than fought forever.
2. **A value already outside the screen's range widens the row instead of being
   clamped.** The file's bounds are far wider than the screen's, so a hand-edited
   Pet = 5000 would otherwise have been clamped to the slider maximum and then
   saved back at that clamp, quietly rewriting a number the player chose.

`menutest.js` is now **135 checks**, covering all of the above including Cancel
restoring, defaults applying without closing, the widened row, and the
not-ready-widget guard (the fake can now refuse to accept a seeded value).

### Still his call
- **A backup of his settings from before this screen existed** is at
  `save-backups/PalBonds_settings.before-live-screen.lua`. His live file now
  holds test values; Restore defaults in game will reset it, or the backup can be
  copied back.
- Whether the FILE's own 0..100000 ceiling is worth tightening now that the
  screen has sane ranges. Left alone deliberately: narrowing it would make the
  mod refuse a value a player already has and replace it with the default.
- The two fruit labels still name an in-game item in wording of our own.
- Nothing is committed or pushed.

## SETTINGS SCREEN — milestone 3: REBUILT after Dragón's first look (2026-09-25)

His verdict on the first version was that it needed *"a lot of polishing"*, and
every point was right. **The root mistake: the whole screen had been derived
mechanically from the settings schema** — labels from the internal keys, a slider
for every number, each slider's range from the file's validation bounds, and a
fixed list of keys to rebind to. A data structure describes what the program
needs; a screen describes what a person needs. Do not generate the second from
the first. (Saved as a standing memory.)

### What he said, and what was done about each
1. **"showing the label names we used on the file should not be like that ...
   lets keep the labels easy to understand and far from code names"** — every row
   is now a written label. Each schema entry names a Locale entry (`label =
   "set_pet"`), and **the seven personality rows reuse `tag_normal..tag_feral`**,
   the exact words the player already reads over a Pal's head, so the screen and
   the tags can never drift apart. A test asserts that no row shows a code name.
2. **"the settings themselves should change language when one changes
   languages"** — 24 new Locale entries in all 16 language sets (the labels, the
   five section headings, the rebind prompt and the "changes apply right away"
   line). `localetest`'s completeness check covers them like every other string;
   its count canary went 26 → 50.
3. **"you didnt even use the same style of the game ... the name palbonds gets
   half cut in between the tabs above and the button touches the border"** — the
   page is now framed with the game's own `WBP_PalCommonWindow_C`, inset from
   every edge, with the title and the Close button clear of both. The title was
   being cut because the first version hid three of the menu's panels and **the
   ESC menu's own tab strip (`Canvas_TabSet`) kept drawing over the page.** All
   seven panels the menu can show are now covered — each one's own visibility
   remembered first, so closing restores exactly what was there, including a
   panel that was already hidden and is not ours to reveal. Row height is 48 with
   8 between, matching the game's own Options rows.
4. **"you went crazy with sliders ... it was impossible for me to try and set pet
   to anything a bit higher than 50, just a small movement went to the thousands
   already, and why you put a max of 100000?"** — the 100000 is the FILE's
   validation bound and always was (1.1.x), not something invented for the
   screen; the mistake was using it as a slider range. **The schema now carries
   two ranges per setting:** `min`/`max` for what the file accepts, and
   `ui.min/max/step` for what the screen offers. The file's bounds stay wide on
   purpose — narrowing them would make the mod refuse a value a player already
   has and silently replace it with the default. The screen's ranges are sized
   against the trust bar being 500 points at equal level: Pet/Play/Feed 0–250
   step 5, food bonuses 0–100 step 5, the fruits 0–1000 step 25, passive 0–25
   step 1, join bonus 0–200000 step 5000 (friendship ranks really are that big),
   chances 0–100 step 5. A test asserts **no slider has more than 60 stops** and
   that every default lands exactly on a step.
5. **"on the keybinds you set it as options? really? ... so we are also limiting
   players which keys they can change to? thats awful"** — gone. A key row is now
   the label plus the game's own small option button showing the current key;
   click it and **press the key you want**. Reading an arbitrary press means
   UE4SS must hold a binding on every key, so it does — but only from the moment
   the player first opens this screen, never at mod load, and each handler
   returns immediately unless the screen is waiting. Mouse buttons and modifiers
   are excluded (a click on the button would otherwise become the binding, and
   Escape belongs to the menu). Clicking twice gives up. **And while it waits,
   the mod's own keys hold still** (`Menu.WaitingForKey`), or choosing F8 for Play
   would also play with a Pal on the way in.

### Why the key row is not the game's own key row
`WBP_OptionSettings_ListContent_C` *can* show a key, but only through
`SetKeyIcon(InputType, Key)` and `SetConfigButton(ActionName, FilterType,
InputType)` — an engine `FKey` and one of the game's OWN input actions. A mod's
keybind is neither, so pretending otherwise would mean inventing engine key
objects. The label + `WBP_OptionSettings_MenuButton_C` pairing keeps the game's
styling without that.

### Tests
`menutest.js` is now **110 checks**: the labels (no code names, the friendly
text, the tag reuse, and the whole page in French), the control shapes, the
screen's ranges and steps with the "aimable" and "default lands on a step"
rules, the rebind flow end to end (button shows the bound key, no key watched
until asked, click prompts, any ordinary key takes, Escape/mouse/modifiers
refused, clicking twice cancels, a clash refused with the button still honest),
the cover-and-restore of all seven panels, and the save on close. Plus the
`Menu.WaitingForKey` check on both sides (`settingstest` asserts Interaction
consults it). All 25 suites pass against `mod/` and the deployed copy;
`realfilecheck.js` still passes against Dragón's real settings file.

### Still open, and worth his eye rather than my guess
- **The margins are design-unit guesses** (window inset 300/96/300/56, list
  344/238/344/188). They cannot be verified offline; they need a look.
- **Two labels name an in-game ITEM** (`set_peach_lesser`, `set_peach`,
  written as "Small kinship fruit" / "Kinship fruit"). The project has never had
  the game's own item name in the other 15 languages, so these are descriptive
  rather than copied — the same kind of wording he corrected for the tag names on
  2026-09-18.
- Nothing is committed or pushed.

## SETTINGS SCREEN — milestone 2: the live settings layer (2026-09-25)

**Dragón, after testing milestone 1:** *"test run done and saw the palbonds
button, looked neat, so good job ... now lets try to see if you can add the
settings we currently have and we can make them work and change mid-game"*. He
also subscribed to Better Mod Manager so its files could be read.

### DONE and fully tested: a setting can now change while the game runs
This was the real prerequisite (the old "Pending" note said so). All 25 suites
pass against `mod/` and against the deployed copy.

- **`Settings.Set(key, value)`** validates through the SAME `valid_value` the
  file goes through, so the screen cannot store a value the file would refuse.
  **`Settings.OnChange(fn)`** tells listeners. **`Settings.Flush()`** writes the
  changed keys to the player's file in one pass. **`Settings.Schema()`** exposes
  the schema so the screen can build itself from it.
- **Two rules the file never needed**, because a file is validated as a whole
  while the screen arrives one value at a time: the last personality chance
  above 0 cannot be zeroed (the roll would have nothing to pick), and two
  actions cannot share a key. Both refuse with a reason the screen can show.
- **Persistence is surgical.** `Settings.TextWithValues` replaces the value
  token after `Key =` and nothing else — comments, order, blank lines and the
  player's own spacing survive byte for byte — and the result is read back in an
  empty environment and checked against every expected value before it goes near
  the disk. A file that does not parse is never overwritten; the values stay live
  for the session and the console says so.
  - **A flaw found and fixed by its own tests:** locating the key by
    line-anchoring could not see `return { Pet = 50 }`, which is exactly the
    shape of a hand-written file AND of what our own append path produces. It now
    locates through a mask with comments and string CONTENTS blanked, so a
    mention in a comment (`-- Pet = 999 is too much`) is never mistaken for the
    setting, `KinshipPeach` never matches `KinshipPeachLesser`, and a file it
    cannot read confidently is refused instead of edited.
- **Every module refreshes its own locals from a listener** rather than asking
  Settings at use time, so no hot path gained a call: the assignment updates the
  local every closure already captured. Wired in `Interaction` (all the feed,
  pet, play and peach amounts), `Trust` (PassivePerTick), `Capture` (JoinBonus),
  `Personality` (the seven chances, rewritten IN PLACE in the table the roll
  holds), `Indicator` (ShowPersonalityTags applies now, like the key does).
  `Language` was already live through `Locale.Current`.
- **The keys rebind live, and this is the subtle part.** UE4SS can bind a key
  but cannot UNBIND one, so a rebind cannot take the old key back. Every binding
  instead asks, at the moment it fires, what that key is FOR right now: a key the
  player has moved an action off does nothing. The new key is bound only if it has
  never been bound this session. `Interaction`'s three `RegisterKeyBind` calls
  went through `bind_key(action, name, fn)`; **coopstage2test locates those
  handlers by source text, so its anchors moved with them** (the checks stand).
- **Tests:** `settingstest.js` sections **J** (live changes: validation, the two
  extra rules, listeners including one that throws, no disk write while a slider
  drags, in-place saving that keeps the player's file, every refusal case, a
  broken file left alone) and **K** (the modules follow a change; the old key
  goes inert and the new one works). `localetest`'s Settings stub gained
  `OnChange` — a stub without it is a stub of a module that no longer exists.

### DONE: the controls are on the screen, built from the game's own rows
Applied and tested. **`native_widget(menu, classPath)`** builds any of the game's
blueprints (find the class, `LoadAsset` on demand, `WidgetBlueprintLibrary:Create`
with an owning player — a UserWidget without one does not draw); `native_button`
is now written in terms of it.

**The API the rows are built with, all verified in this build's object dump.**
One native row class covers every shape we need, so the screen does not imitate
the game's Options screen, it IS it:
- `WBP_OptionSettings_ListContent_C` (under
  `/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/`)
- `row.BP_PalTextBlock_Name` — the label
- `row:SetSwitcher(bool)` / `row:SetSlider(value, min, max, step, useStep)` /
  `row:SetSelecter_String(labels, index)` — also `SetInteractable`
- read back from `row.WBP_OptionSettings_ListContentSwitch.CurrentIsOn`,
  `...ListContentSlider.CurrentValue`, `...ListContentLR.Current` (0-based)
- the slider's own number is `...ListContentSlider.BP_PalTextBlock_Value`

**The decisions behind it, so none of this is re-derived later.** The whole list
is built from `Settings.Schema()`, so a setting added to the file appears on the
screen with no second place to remember it, and the CONTROL SHAPE is derived from
the entry rather than chosen by hand: `kind` language/key -> a selector, `min 0
max 1` -> a switch, anything else -> a slider.
- **Rows are POLLED every 150 ms while the page is open**, not hooked. The switch
  and the selector have no delegate we could hook without adding three more
  native hooks to the mod; polling runs only while the player is standing in a
  paused menu, the cheapest moment in the game; and one loop that reads every row
  is far less machinery than a hook per control type. The loop carries a token, so
  a page opened again cannot also be polled by an older loop, and it stops on
  close, on supersession and on destruct (all three tested).
- **A refused value is put back into the row.** A screen still showing a number
  the mod did not accept is lying about the state of the game. The reason goes on
  a note line at the bottom, where the player is actually looking.
- **The slider's step follows the range** (1 / 10 / 100): 0..200000 at step 1 is
  200000 positions and unusable. The exact number is drawn beside the slider,
  which is what a player reads anyway.
- **Keys come from a curated list, not "press any key".** Capturing a press means
  binding every key on the keyboard to find out which one was pressed, and taking
  the player's whole keyboard to read one press is what another mod's own notes
  warn against. Anything UE4SS does not know on this build is dropped from the list.
- **ScrollBox and VerticalBox are safe here because they are OURS.** The rule that
  costs crashes is about mutating the GAME's live panels; inside our own subtree a
  reflow is ordinary UMG.
- **One write, on close.** A slider drags through dozens of values and none of
  them touches the disk; closing the page is when the player has finished, and
  they are standing still in a paused menu while it happens.

**A bug menutest H caught before it ever reached the game, worth remembering
because of its SHAPE:** a language and a key have no `min`/`max`, so asking them
for a slider step threw — and because the build loop was unguarded, that one bad
entry took the WHOLE page down, leaving the rows already built dangling and the
player with no screen at all. Fixed twice over: the arithmetic is guarded, and
each row is now built in its own `pcall` so a setting whose shape this code does
not expect costs that one row and nothing else.

**Verified against Dragón's REAL settings file**, not only synthetic ones
(`tools/harness/realfilecheck.js`, and his file is backed up at
`save-backups/PalBonds_settings.before-live-screen.lua`): four values changed, and
the result parses, keeps every other value identical, keeps the same number of
comment lines and the same number of lines overall — nothing reflowed.

**Tests:** `menutest.js` section **H**, 30 checks: a row per schema key and the
sections as headings; the shape derived per entry; rows seeded from the current
values with the slider's range, step and number; the language list offering auto
plus every language and starting on the one in use; the key list offering only
keys UE4SS knows; a drag/switch/selector reaching its setting through the watch;
the chance-zero refusal snapping the row back AND putting the reason on screen;
the watch scheduled only while the page is open and stopped on close and on
destruct; the save happening on close and the value surviving it. The suite's UMG
fake grew the game's row widget (same methods, same read-back fields) plus
SizeBox/ScrollBox/VerticalBox.

**One thing to ask Dragón, not to decide:** the row labels. They are currently
the setting names from the file (`Pet`, `FeedBase`, `ChanceNormal`) because those
are the only names that already exist, they need no translation, and a player who
has edited the file recognises them. Nicer wording is a content decision he has
not made, and inventing it in 17 languages first would be inventing the thing he
asked to decide later.

**Also still open:** nothing is committed or pushed, and the screen has not been
seen in game yet — 24 native rows are built on the first click, which is the one
real risk left (the reference mod's crash family is widget churn inside an open
menu, though its incidents came from pre-building ~100 rows on EVERY ESC open,
automatically; ours builds once, on demand).

### Better Mod Manager (studied 2026-09-25, Dragón subscribed so it could be read)
At `steamapps/workshop/content/1623730/3803996980/`. Credits DarnMenu for the
groundwork, so there is no new hooking technique — but two things are worth
knowing. **It does not touch the ESC menu at all:** it adds a real tab to the
game's main in-game menu (`WBP_InGameMainMenu_C`, `WBP_MainMenu_C`,
`WBP_MainMenu_Tab_C`) and hooks `WBP_PalCommonButtonBase_C`'s `BP_OnClicked` /
`BP_OnHovered` / `BP_OnUnhovered`, which are far cleaner than the ESC row's long
delegate name. That is closer to the "new tab" Dragón originally described, if we
ever want to move. **And it offers mods an optional registration library**
(`modconfig.lua`, loaded from ITS folder, ~15 lines in ours, degrades to nothing
when absent) — a cheap way to appear in its menu later, not a substitute for our
own screen. Its `ui.lua` (15 KB, vs DarnMenu's 200 KB) is the leaner kit to read
for primitives: `T_prt_frame_1px` borders, `WBP_PalInvisibleButton_C` as the
press surface, and a button registry keyed by address + full name (the same
identity rule this project arrived at independently).

## THE IN-GAME SETTINGS SCREEN — milestone 1 built (2026-09-25)

**Dragón's ruling on where it goes:** *"ideally we simply add it to the game
menu the player already knows and uses like the esc menu, and we simply add a
new tab there with the name palbonds mod or something like that - but if that is
not posible then a shortcut key like f7 to open the settings menu would have to
do then"*. The ESC route turned out to be possible, so **F7 is not needed** and
no key is taken from the player.

**And on scope:** *"as for what belongs in it, we can worry about that later,
first we need to see something visible for the player ingame, no point in adding
more values to the settings if we cant even achieve the screen itself"*. So this
milestone is the SHELL only — a row named `PalBonds` and a page with its title
and a Close button. No setting is on it yet, by his instruction. He also chose
the safest placement (bottom of the existing list) and the label `PalBonds`.

**It lives in one new file, `mod/PalBonds/Scripts/Menu.lua`,** initialised last
in `main.lua` inside its own `pcall`. Deliberate: it is the only module that
builds widgets inside a native menu, so it can be dropped from a package without
touching a line of what already ships, and it cannot take the mod down.

### The five rules in that file are crashes somebody already paid for
Do not "simplify" any of them. Each is load-bearing.
1. **Never build inside the `NotifyOnNewObject` callback.** The engine is still
   assembling the menu; mutating it there is `AV writing 0x80`. We wait 50 ms on
   the game thread, which is still inside the open animation, so nothing pops in
   late. (menutest A pins this.)
2. **Only ever add a child to a `CanvasPanel`.** Adding to a `VerticalBox`
   reflows the whole column on the engine's NEXT layout pass — after our Lua has
   returned, so there is nothing left to `pcall`. That is what killed DarnMenu
   three times out of three under ESC-spam, and a plain `AddChild` (no tail
   detach) still reflows, so append-only was never a fix. Our row is therefore
   positioned ABOVE the bottom column on the shared canvas, never inside it.
   (menutest B: the parent is `Canvas_Buttons` and the column gains no children.)
3. **Never `RemoveFromParent` on a menu we no longer own.** A replaced menu
   lingers and keeps painting; touching its children AVs. The engine frees our
   widgets when it destroys the menu, so we simply forget them. (menutest F/G.)
4. **A raw `.Text = "string"` write crashes this game** — our own crash,
   2026-09-04, `Indicator.lua`. Text goes through the game's own
   `BP_PalTextBlock_C` (taken off a live instance on this same menu) and
   `SetText_GDKInternal`, the pair that fixed it. It also means the font and
   colour arrive already matching the menu.
5. **Build the page on the FIRST CLICK, never ahead of time.** Widget churn
   inside an open menu is DarnMenu's crash family: pre-building its page on
   every ESC open caused seven incidents before it was switched off.
   (menutest D.)

### The widget names, all verified against THIS build's object dump
`WBP_MenuESC_C` (the menu) and `WBP_MenuESC_Button_S_C` (its own row
blueprint), plus `Canvas_Buttons`, `Canvas_Content`, `WorldOptionCanvas`,
`CanvasPanel_0`, `VerticalBox_293` and `Text_InviteCode`. Note which of these
are real PROPERTIES on the class (Canvas_Buttons, Canvas_Content, Text_InviteCode)
and which are only reachable through the widget tree (`VerticalBox_293`,
`CanvasPanel_0`) — the lookup tries the property first because that is one
reflection call against the walk's hundreds.

`VerticalBox_293` is the BOTTOM column ("Return to Title"), which is where a mod
row reads as native. The TOP column (`VerticalBox_148`) is auto-sized and reports
height 0, so anchoring under it lands in the middle of the native rows.

The row is created with `WidgetBlueprintLibrary:Create(menu, cls, GetOwningPlayer())`,
NOT `StaticConstructObject` — that is what gives it an owning player. (The older
note under the DarnMenu study says `StaticConstructObject`; the reference's actual
code uses `Create`, and so do we.)

### Sharing the shelf with other menu mods
`Canvas_Buttons` is public space. DarnMenu, **Better Mod Manager** and AntiPhat
all pin a row above the same column and compute the same spot we do, so whoever
injects second draws on top of the first. We read the canvas's bottom-anchored
children (read-only — it mutates nothing, which is what makes it safe on a
native panel) and sit above whatever is already parked there. Learned once and
cached for the session: another mod cannot be installed mid-session.

The stretched slot matters here. The bottom column is anchored (0,1)-(1,1), and a
stretched slot is made of OFFSETS: writing Position/Size into one produces a
rectangle the slot cannot represent and Slate crashed laying it out. Inheriting
the column's Left/Right also matches the native row width for free. (menutest B
asserts the offsets and that no position/size was written.)

### A bug the new suite caught before Dragón ever ran it
Refusing a click whose widget identity does not match ALSO erased the record for
our own genuine button, because a foreign widget on a recycled address shares
that address — so one stray click from another mod's button would have killed our
entry for the rest of the session. The record is now forgotten only when OUR
button is the one that went away. A failed probe is evidence about the probe.

### Tests
**`tools/harness/menutest.js`**, 7 sections, 47 checks: nothing built inside the
construction callback; the row on the canvas above the column with the column's
own offsets; the shared shelf; the page built only on the first click and only
once; only our own buttons act (a native ESC row falls through, a recycled
address is refused, our entry keeps working); ESC pressed twice leaves the older
menu alone; destruct forgets it and the next menu still works. Its UMG fake
reproduces the parts the real crashes came from — a canvas that can REFUSE a
child by returning nothing, and a stretch-anchored slot.

**`tools/harness/runall.sh`** now runs every suite with the right prelude in one
command (`sh runall.sh`, or with a scripts path). Written because a suite given
the wrong prelude ABORTS rather than fails, and an aborted suite reads like a
passing one if you only skim the output. All 25 suites pass against `mod/` and
against the deployed copy; hoistcheck 1 / undefcheck 4 unchanged (the known
false positives). `localetest`'s string-count canary went 25 -> 26 for the one
new translated word.

### Player-facing text
`menu_close` ("Close") added to `Locale.lua` in all 17 languages. The entry
itself reads `PalBonds`, which is the same word everywhere. That is deliberately
the ONLY translated word on the screen so far — anything else added to the page
needs its Locale entry in the same pass, and there is no point translating
placeholder prose that Dragón's content decisions will replace.

### NOT done, and what is next
- **Nothing is committed or pushed.**
- **No setting is on the page yet** — his call, and the next decision to make.
- **The live re-read is still the real prerequisite** (see "Pending"): settings
  are parsed once at load, so a screen that changes a value cannot apply it yet.
  Build that before putting controls on the page, not after.
- **Not verified in game yet.** Deployed to the dev install with
  `DEBUG_LOGGING = true` for Dragón's test run; every claim above is from the
  object dump, the reference implementation and the offline suite, not from a
  screenshot.

## 1.1.8 = THE CLEAN-SHIP PASS (started 2026-09-23)

**Dragón's standing rule, restated after he found disproven mechanisms still
sitting behind `false` switches in a shipped file:** *"when we work on the mod
in dev or local, you're free to activate all logs and whatnots - tries and
tests and old codes [...] but that is ONLY in local and while developing -
WHEN WE SHIP, NOTHING OF THAT MUST REMAIN - no logs, no trash, no extras, no
code that was used just once to check something that's now stale."* From now
on **"let's ship this version" is the whole instruction**: it means produce a
clean package without being told the cleanup part again. Nothing is lost by
deleting -- git history and `docs/hook-points.md` keep the record.

**Done so far (all 24 suites pass after every step, syntax-checked per cut):**
- Combat.lua 4,731 -> 4,431 lines. Deleted: `USE_OLD_MOVE_ORDER_NUDGE`,
  `USE_REPEATED_OTOMO_COMPOSITE` (with `get_or_build_otomo_composite`,
  `OtomoCompositeCache`, `Combat.TickRealOtomoFollow` and its call in
  Trust's tick), `USE_ORBIT_WHEN_AT_GOAL`, `USE_MOVE_TO_ACTOR_FOLLOW`, and the
  whole 165-line native-leash section (`USE_NATIVE_LEASH_FOLLOW`,
  `ensure_leash_for`, `update_leash_anchor`, `release_leash`, the CDO cache and
  the safety counters).
- The `LoopAsync` fallbacks in Trust and Indicator: a path that would only fire
  in an emergency it is not safe for. Both now just log the failure.

**Comments: the package ships NONE of them (Dragón, 2026-09-23).** His
question settled it -- *"why would a player who has no intention to even work
in the mod need to have files with the story of experiments and comments? isn't
that meant for github only?"* So `mod/` keeps every comment (development
source, on GitHub) and `tools/strip-comments.py` builds the shipped trees
without them. The stripper is string-aware: it never touches text inside quotes
or long brackets, so the settings file the player edits keeps its explanations
and messages containing dashes are intact. **18,830 source lines -> 9,748
shipped.** Line numbers in a player's crash report still resolve, because the
stripped tree is committed with each release.

**Diagnostics removed in the same pass** (settled questions, their code deleted
rather than silenced): `dump_follow_action_fields` (15 native reads per follow
install even with logging off), `log_boss_geometry` + `[BOSS-GEOM]` +
`[DIAG-GEOM]` (boss bars confirmed in 1.1.3), Capture's `[EXPERIMENT]`
narration from when the sphere-less capture was one (with `read_owner_id`,
which only fed it), the `[WORKER-BIND-FIX-DIAG]` widget dump and its
`lastLoggedPushedClass`, `[HP-WATCH]` with its `HP_WATCH_VERBOSE` switch, and
`[DAMAGE-WATCH]`. What stays is failure reporting inside live features
(`[DIAG-CREATE]`/`[DIAG-LABEL]` say why a bar or tag failed to build) and the
logging system itself, which is how a player produces a bug report.

### RELEASE GATE — no version ships without these, in order

1. `mod/` is the source of truth; the package is built from it
   (`tools/strip-comments.py`), never edited by hand.
2. All suites pass **against the built release tree**, not only `mod/`.
3. **Dragón runs the exact package in game** and says it works. A green
   harness proves the code behaves the same under stubs; it cannot prove the
   mod loads, that the hooks register, or that anything appears on screen.
   Until that run happens the honest words are "packaged, needs a smoke run".
4. Only then: stores, then GitHub.
5. **The live version's artifacts stay untouched until its replacement is
   actually live** — zip, release trees and tag. While a version is serving
   players it is the rollback and the reference for any bug report about it.
   (Broken once, 2026-09-23: the 1.1.7 zip was deleted while 1.1.7 was the
   live version and 1.1.8 was untested. Restored from git.)

**1.1.8 IS PACKAGED, NOT PUBLISHED:** `release/PalBonds-v1.1.8.zip` (17 files,
101 KB -- 1.1.7's was 339 KB), `Info.json` 1.1.8, both release trees stripped
and identical, all 24 suites pass AGAINST THE RELEASE TREE, syntax checked
after every single cut. The 1.1.7 zip was deleted (it is a GitHub release
asset). Nothing has been committed, pushed or uploaded for 1.1.8.

## MULTIPLAYER IS THE ACTIVE WORK (2026-09-21)

Dragón: make the mod work for co-op, hosted worlds and dedicated servers, by
whatever route works, and ask him for any test that helps -- advance as far as
possible before the two-player session with a friend. The plan (host-
authoritative: the world's owner does every Pal-side job, guests supply input
and show display) and the current test are in `docs/multiplayer-questions.md`,
"THE PLAN", "Net probe run 1" (the private line works both ways), "Stage 1"
(built, and co-op run 1 PASSED: a guest's pets, follow, join and messages all
worked on the dedicated server) and "Stages 2 and 3" (built 2026-09-21,
harness-tested, awaiting co-op run 2: several players per host/server, claims,
dedicated-server detection, the join light and bars/tags for guests via the NEW
`HostView.lua`; release notes for later are listed there). Co-op runs 2 and 3
done (run 3: the whole guest loop works on a dedicated server, combat assist
included); the run 3 fixes (guest-language messages, per-player F10, F8 and
food charging for guests, ask backoff) are built and deployed, awaiting co-op
run 4 -- planned as the single friend session. **Machine state for co-op run 1:** the local
dedicated server has a manual UE4SS (rename its `dwmapi.dll` to remove), the
server net probe, AND PalBonds itself with full logging and a TEST settings file
(`Pet = 125`, delete after); the game's dev copy has `GUEST_INPUT_PROBE = true`
in Session.lua (mod/ ships false) and the client net probe mod in `ue4ss/Mods`.

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

### Shipping a release — the full checklist

Added 2026-09-27 because Claude handed Dragón a changelog and no short
description, and he had to point out it was missing: *"you forgot to give me the
short description, seems you've either not checked your mds for this or you
never added it to your work process"*. It is in the work process now.

1. `mod/` clean: every ship switch off (`DEBUG_LOGGING`, `SHOW_DIAGNOSTICS`,
   `TRACE_PHASES`, `ACTION_CHANGE_PROBE`, `PROFILING`), no temporary flags, no
   diagnostic-only files.
2. `python tools/strip-comments.py mod/PalBonds/Scripts release/PalBonds/Scripts`,
   then copy those same files to `release/workshop/PalBonds/Scripts` and confirm
   the two trees are md5-identical.
3. Bump `release/workshop/PalBonds/Info.json` `"Version"`.
4. `sh tools/harness/runall.sh release/PalBonds/Scripts` — a stripped build is a
   build nobody has tested.
5. Zip with **forward-slash entry names**. PowerShell's `Compress-Archive`
   writes backslashes; build it with Python's `zipfile` instead.
6. **Two pieces of text, both needed, both Dragón's to approve:**
   - a **changelog**, ONE LINE PER ITEM, prefixed `New:` / `Balance:` / `Fixed`;
   - a **short description**, one or two sentences, the blurb that sits on the
     file entry.
   Draft both, never claim more than has been measured, and never promise fixes
   or dates (see the memory on public text).
7. Nothing is uploaded, committed or pushed without him saying so, per store.

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

## Curiosity, and a player answer we will need: Auri cannot be bonded (2026-09-20)

Dragón asked why Auri — the blue-haired NPC with the `Hablar` prompt, standing
near a boss tower — is completely unaffected by the mod. She is popular enough
that players will eventually ask us the same thing, so the answer is recorded
here rather than re-derived later.

**She is not a character.** Identified with UE4SS's own `DumpAllActors`
(`Ctrl + Numpad 7`, bound in `ue4ss/Mods/Keybinds/Scripts/main.lua`) while
standing next to her — she appeared 138 units from the player as:

```
/Game/Pal/Blueprint/FlowGraph/TalkableLevelObject/SkyBoss/
    BP_PalTalkableLevelObject_SkyBoss.BP_PalTalkableLevelObject_SkyBoss_C
```

Her full chain, read from `ue4ss/CXXHeaderDump`:

```
BP_PalTalkableLevelObject_SkyBoss_C
  -> BP_TalkableLevelObjectBase_Modify_C
    -> APalLevelObject_Talkable
      -> APalLevelObjectActor
        -> AActor
```

She never touches `ACharacter`, let alone `APalCharacter`. In the game's own
terms she is a *level object* — the same family as a warp point or a relic —
that happens to carry a person-shaped mesh. Her internal name is `SkyBoss`
because the asset is named after the encounter she belongs to, not after her;
siblings in the same folder are `BP_PalTalkableLevelObject_GrassBoss01` and
`BP_PalTalkableLevelObject_StrongOldMan001_Release`, one greeter per tower.

Her base class carries only: `UPalSkeletalMeshComponent CharacterMesh` (the
body), `UPalInteractableSphereComponentNative` (the `Hablar` prompt),
`UPalNPCTalkFlowComponent` (dialogue), `UPalLookAtComponent` + a single
`IdleAnimation` montage (she turns her head and loops), and
`UPalLimitVolumeBoxComponent` (you cannot walk through her). There is no
capsule, no movement component, no HP, no AI controller and no
`UPalIndividualCharacterHandle`. She also has `VisibilityCondition` /
`OnQuestStateChanged` / `SetHiddenAndDisableCollision` wired to the quest
manager, so she blinks in and out of existence, collision included, as a prop
does.

That single fact explains every symptom Dragón observed: no name plate, no HP
bar, and capture spheres passing straight through her. It also explains the
mod's silence — `find_targeted_pal` builds its candidate list from
`FindAllOf("PalCharacter")` with no filtering afterwards, so she is never a
candidate to reject. Ten F8 presses from two metres away all logged
`not looking at any Pal`, with no rejection line anywhere, because the mod
cannot perceive her at all.

**Why we will not "fix" this.** Every pillar of PalBonds hangs off the
individual character handle she does not have: trust is stored per stable
individual ID, personality reads the AI sensor's response preset, the trust bar
attaches under a `BP_PalNPCHPGauge` widget, and capture calls
`PalCaptureSuccess` on the handle. For her, all four point at nothing.
Supporting her would not extend the mod; it would be a second mod sharing the
folder.

**The short answer for players:** Auri is not a Pal or an NPC in the game's
code — she is a scripted part of the scenery with dialogue attached, with no
health, no stats and no capture target, which is also why Pal Spheres pass
through her. PalBonds only works on things the game itself treats as Pals, so
there is nothing there for it to bond with.

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
2. ~~Singleplayer only~~ **— NO LONGER TRUE as of 1.1.7 (2026-09-23):** co-op
   and dedicated servers are supported and shipped. What is untested is listed
   under "1.1.7 BUILT AND READY TO PUBLISH". Official servers still do not
   allow mods.
3. **`LoopAsync` fallbacks still present** (re-counted 2026-09-23: Trust 5,
   Indicator 1, Combat 1), dead code that would only run in the emergency it
   is unsafe for.
4. **World-change references never cleared:** partly fixed. `Indicator` and
   `Interaction` both have a `ResetForNewWorld` since 1.1.4 (tracked bars,
   boss entries, `pendingWildFeedTarget`, the radial caches). What is still
   never cleared is the `SpawnedOtomo` field PalBonds writes into the
   GameInstance-lived radial widget.
5. **`FindFirstOf` exposure** (UE4SS issue #1328): re-counted 2026-09-23,
   `Capture.lua` has 0 and `Interaction.lua` 1
   `FindFirstOf("PalPlayerCharacter")`. None is per hit.
6. **`find_targeted_pal` costs 40-80ms per scan** while the radial menu is
   open (42-47 ms in 2026-09-15's measurement, 76-78 ms in run 3b's). It is
   the largest named cost left, in singleplayer as well as co-op.
7. **No settings screen.** The F9 and F10 toggles are session-only.
8. **Friendly fire** is contained, not prevented (see the combat section).
9. **Hotkeys fire while typing in chat** — declined by Dragón 2026-09-14 as
   not worth fixing (see Pending).

---

## Pending, deliberately deferred

**SETTINGS ARE READ ONCE AT LOAD (noted 2026-09-23, Dragón asked).** The
settings file is parsed when the mod loads and most modules copy the values
into locals at that moment (`Interaction.lua`'s keys and gains, `Trust.lua`'s
passive tick, `Capture.lua`'s join bonus), so editing the file mid-session
changes nothing until the game restarts. F9 and F10 are the only live
switches, and they are session-only. A live re-read (poll the file, or reload
on demand, and have modules ask `Settings.Get` at use time) is the
prerequisite for the in-game settings screen -- do it first, not after.
**BUILT 2026-09-25** -- see "SETTINGS SCREEN — milestone 2". Editing the FILE
still needs a restart to be noticed; what is live is a change made through
`Settings.Set`, which is how the in-game screen changes one.


**New player report (2026-09-21): Hakaishin Beerus, crash with other mods, plays
co-op.** Posted in Toxik's Steam thread. Report copied to
`docs/bug-reports/hakaishin-0921-rentry.md`. `EXCEPTION_ACCESS_VIOLATION reading
0x0`, VCRUNTIME140 memcpy under UE4SS frames, the same stack hash twice, one of
those with Pal Insight fully removed, so Pal Insight is not shown to be the cause
(Dragón's first read was an HP-bar overlap). Two open leads, NEITHER assumed:
(a) the guest-join fatal crash from `docs/multiplayer-questions.md` if they were
a guest (note: that one is a `LowLevelFatalError` assert, a different signature);
(b) the UE4SS build, since the signature matches Esaeon's `c838a8ac` crash --
but Dragón ruled that Toxik's crash is NOT assumed to be Esaeon's, so ask, don't
diagnose. PalBonds strings "in crash memory" prove nothing (loaded script text is
always in memory). Reply drafted asking: singleplayer/host/guest, what they were
doing, the UE4SS Git SHA, and a PalBonds-only run -- the same triage as Esaeon.

**THEY ANSWERED (2026-09-21, Steam Workshop): it is the known UE4SS build.**
Singleplayer, feeding a Pal, PalBonds alone with every other mod unsubscribed
and its leftover folders deleted, on **UE4SS Git SHA `c838a8ac`** -- the same
15 July build behind every one of Esaeon's crashes, which updating to Okaetsu's
`2281fa31` fixed with no PalBonds change. They also ask whether we can ship an
"older UE4SS compatibility patch", because a newer loader breaks other DLL mods
they use and will not update for. Technical answer for a reply: PalBonds is Lua
only and the faulting frames are inside UE4SS's own native code, so nothing in
this mod can patch it; and the build we point at is Okaetsu's Palworld-specific
one (what the Workshop dependency installs), not the main UE4SS line their DLL
mods broke on, so that exact build is worth trying. What goes in the reply is
Dragón's call.

**AND THAT ANSWER DID NOT HOLD (2026-09-22, their reply).** Two corrections
from them, both of which kill the "it is the old build" conclusion above:
1. They have **only ever used the Palworld UE4SS** (Okaetsu's line), never the
   mainline one — so the premise that a newer mainline loader broke their DLL
   mods was ours, not theirs.
2. They have already tested **`2281fa31` (3 Sept), and it crashes equally**.
   "Trust me, tested it a bunch."
So this is an OPEN crash report on the build we recommend, not a solved one,
and nothing in the Esaeon finding explains it. They also point out that other
Palworld mod authors ship old-UE4SS compatibility patches (DynamicPals on
Nexus, 2 days ago), and that a large group of players deliberately stay on
older builds — Okaetsu's own advice to them was to pick one and stay there.
They were explicit that they are not demanding anything.
**What would actually move this:** the trace build already sitting in
`release/test-build/` (`PalBonds-v1.1.6-test2.zip`, DEBUG + `TRACE_PHASES` on,
`docs/crash-testing-guide.md` written for it) writes one line before every job
it starts, so the last line in the log names the job that was running when the
game died. Publishing it to them is Dragón's call, as `test1` was for Esaeon.
Until that log exists, we cannot say whether a compatibility patch is even a
thing on our side; do not promise one, and do not repeat "update your UE4SS".
**DRAGÓN'S RULING (2026-09-23): wait for them to open the issue and move on.**
"We have already recommended him to do so at least twice already - if he still
fails to do so, we simply continue forward, we cant stop a whole proyect for 1
person." Note the trace build is ALREADY public if they ever want it: GitHub
pre-release `v1.1.6-test2`, with `crash-testing-guide.md` attached.

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
- **ANSWERED AND CLOSED, verified 2026-09-23 (do not re-list these as open):**
  - GitHub issue #1 (Esaeon) is **CLOSED** on the repo. Dragón's instruction at
    the time: close it so nobody reading the repo thinks the project is stuck
    on it or abandoned.
  - The 17 Sep design feedback (ralanost, Warframe666: cooldown feel, no
    indicator, favourite food, bonding through fighting, no distance limit)
    was **answered by Dragón on Nexus, 18 Sep 4:23PM**. His answer is the
    design ruling: bonding takes time on purpose and scales with level (a Pal
    at or above your level takes much longer, a much lower one needs 2-3
    interactions, a Kinship Peach can be enough); there is NO cooldown in the
    mod -- the options hide while the Pal finishes a base-game animation or
    when you are not aimed at it; and you do not wait around, because a Pal at
    50% follows you and keeps bonding while you farm or build.
  - Mammorest through the floor: answered 18 Sep as a base-game clipping issue
    that the pet/feed alignment makes more visible.
- **Icon (Meail):** use the meme image as the Workshop icon. Dragón's call.
- **DRAGÓN'S TRIAGE (2026-09-19):**
  - Crash: do NOT treat the two reports as one bug yet. Swordfish said it was
    rare and hasn't reported again (likely an older version). Esaeon may be a
    conflict with one of their many mods. Next step is information: ask Esaeon to
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
    1.1.5, EVERY other mod disabled (their UE4SS.log: PalSchema disabled, only
    UE4SS's default Lua mods). Crash 5-15 s after a Lamball joined;
    CrashContext: EXCEPTION_ACCESS_VIOLATION reading 0x0, every frame in UE4SS
    (+ VCRUNTIME140 memcpy). palbonds-live.log's last line: [PRESET-SLOTS]
    Warlike, 10 s after the join ([ENFORCE] lines are filtered, so what ran
    after it is invisible). Their UE4SS.log is in UTC ("local disabled due to
    wine") and not flushed per line, so its tail is stale. Their Claude's
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
  - **Esaeon test build (Dragón's idea, 2026-09-19):** give them the fix early
    through GitHub instead of making them wait for 1.1.6, so a miss costs no
    release. Built locally, NOT pushed yet (ask first):
    `release/test-build/PalBonds-v1.1.6-test1.zip` = current `mod/` minus
    DevWatch.lua (its call sites are pcall-guarded no-ops), DEBUG_LOGGING ON so
    their log is written without edits, 1.1.5 README. 17 hooks, all suites pass
    against it. `[ENFORCE]` is no longer filtered from the log (it is what ran
    after his last visible line). Plan: commit to a branch (not master, which
    is the 1.1.5 stable), GitHub pre-release `v1.1.6-test1` with the zip.
  - **PUBLISHED 2026-09-19 (Dragón's go-ahead):** branch `test/join-cleanup`
    (commit `f8fb794`; `master` stays the 1.1.5 stable), GitHub pre-release
    https://github.com/DragonKaiser55555/palbonds/releases/tag/v1.1.6-test1
    with `PalBonds-v1.1.6-test1.zip`. Dragón replies to Esaeon (Nexus and the
    issue) with the link. Esaeon's pronouns are unknown: use they/them.
    Local work continues on the branch.
  - Boss reward popup: `UPalNetworkPlayerComponent:ShowBossDefeatRewardUI_ToClient
    (FPalUIBossDefeatRewardDisplayData{TechnologyPoint, DefeatCharacterID},
    AfterTeleport, DelayTime)` and `ShowDefeatBossBonusExpReward_ToClient(int)`:
    run 3 hooked them on the wrong class (PalPlayerController), which is why
    they "could not hook". Client RPCs go through ProcessEvent, so hooked on
    the right class they should show what a real first kill hands out. The
    popup is the RESULT of the server writing the record, not its cause.
  - **Boss Tier Drops (Workshop 3782109509, subscribed 2026-09-19):** PalSchema
    DATA only (AlphaBossDrops.json / PredatorBossDrops.json rewriting
    DT_PalDropItem rows for BOSS_*). No code, no hooks, nothing about the
    defeat record. It does separate the two things a kill gives: drop-table
    items (every kill) and the first-kill bonus (technology points + bonus EXP,
    what the popup reports).
  - **Run 8 setup (built, deployed, awaiting Dragón):** save backed up and
    MD5-verified first (`save-backups/2026-09-19_before-boss-record-write/`,
    SaveGames 462 files + SteamCloud 27). DevWatch `[BOSS-WRITE]`: 25 s after
    a world loads, if `81_1_grass_FBOSS_22` (the Nitewing he petted) is not in
    the record, it calls
    `UPalPlayerRecordDataUtility:SetRecordData_Bool_ForServer(player,
    rec.NormalBossDefeatFlag, FName(key), true)` once, with the whole flag list
    logged before and after. Five other petted-but-unrecorded bosses are kept
    for later tests. Also `[BOSS-REWARD]`: the reward RPCs hooked on the right
    class (UPalNetworkPlayerComponent) to see what a real first kill gives.
    19 hooks in dev.
  - **RUN 8 SOLVED THE BOSS PROBLEM — Dragón found it (2026-09-19).**
    - The direct write is IMPOSSIBLE: UE4SS refuses to pass the record array to
      SetRecordData_Bool_ForServer ("Tried storing reference to a Lua table for
      an 'Out' parameter ... no table was on the stack"). Route closed.
    - His own experiment: he fired ONE bullet at an undefeated boss (Caprity
      Noct / BerryGoat_Dark) before bonding. When it joined through the mod,
      the game recorded the defeat and paid the first-kill reward
      ([BOSS-REWARD]: TechnologyPoint=1, bonus EXP 6060 — the same shape as his
      real Tarantriss kill: 1 point, 5682). The next boss (Gumoss / PlantSlime),
      petted only, produced nothing. So the lever is REAL DAMAGE BY THE PLAYER,
      recorded by the game itself; last attacker and hate were the wrong knobs.
    - **Fix built (tests pass, deployed):** for a boss only, right before the
      capture, `DamageReactionComponent:ForceDamageDelegateForCaptureBall(player)`
      — the game's own "a capture sphere landed" registration: an attacker, no
      damage. The game then writes the record and pays the reward itself, so a
      boss already beaten gets nothing twice and we write nothing into the save.
      `Capture.RegisterPlayerHitOnBoss`, logged as [BOSS-CREDIT].
    - That event comes back through our own damage hook, so
      `Trust.OnFollowerDamaged` now returns early when `st.captureTriggered` —
      otherwise the mod would punish the player for its own capture (half the
      bar and a "trust is shaken" toast mid-join). Tests: pairwatchtest O,
      pointstest P5.
    - The [BOSS-WRITE] test code in DevWatch is now pointless: remove it
      (keep [BOSS-REWARD], it reads the result).
  - **RUN 9: BOSS DEFEAT VERIFIED WORKING (2026-09-19).** Broncherry
    (SakuraSaurus), bonded with NO shot fired: [BOSS-CREDIT] ok, then the game
    paid the first-kill reward by itself ([BOSS-REWARD] TechnologyPoint=1,
    bonus EXP 6195) and the map marked it defeated. In the same run a Chillet
    (WeaselDragon) he had ALREADY beaten: [BOSS-CREDIT] ok, and NO reward
    fired — the game refuses the second payout on its own, which is exactly
    Dragón's "must not give the key item twice". No betrayal/shaken lines: the
    captureTriggered guard holds. Both joins dropped 8 leftover references.
  - **Esaeon, test build 1 result (2026-09-20, GitHub #1): STILL CRASHES, and
    the join is NOT the trigger.** Crash 139 s in, seconds after the THIRD pet
    on a Chikipi, no join in the whole session (logs saved as
    `docs/bug-reports/esaeon-0920-*`). The crash stack is IDENTICAL to the
    first one, all 64 frames, VCRUNTIME memcpy + UE4SS only, reading 0x0 -- so
    both crashes hit the same place inside UE4SS from different call sites.
    (`PCallStackHash` is the SHA-1 of an empty string in both dumps, i.e. the
    field is unused; their AI read it as "byte-for-byte identical".)
    Their AI blamed Combat's 5 s [POST-BOND-DUMP]: its silence is not evidence
    (that tag has been filtered from the log since the 1.1.2 cleanup), and the
    timing clears it -- it fired at 19:07:44 and the log kept going to
    19:07:53. DELETED anyway (2026-09-20): dead diagnostic, six native reads on
    a possibly-dead action object, exactly the risky shape.
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
  old disabled mechanisms still sit in the code behind false flags. STILL
  PRESENT, verified 2026-09-23 in `Combat.lua`: `USE_OLD_MOVE_ORDER_NUDGE`,
  `USE_REPEATED_OTOMO_COMPOSITE`, `USE_ORBIT_WHEN_AT_GOAL`,
  `USE_MOVE_TO_ACTOR_FOLLOW`, `USE_NATIVE_LEASH_FOLLOW` -- all false. Audit and
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
  - **Creative Menu 1.2.4 studied (2026-09-23, Dragón asked whether we could
    make our menu like its F1 screen).** It is NOT a Lua mod and there is no
    technique to copy: its UI ships as cooked Blueprint/UMG assets in
    `Paks/CreativeMenu_P.pak` (~570 KB, widgets under
    `/Game/Pal/Mods/CreativeMenu/BP/UI/...`), loaded through the game's own
    PalModLoader (`/Game/Pal/PalModLoader/BP_Base`, `WBP_UI`). Its leftover
    LogicMods pak says the LogicMod version is retired and UE4SS is no longer
    needed for it. Reproducing that route needs the Unreal editor plus
    Palworld's asset set and a cooked pak -- a different toolchain from ours.
    The DarnMenu finding above stands as our route: a settings screen in pure
    Lua, attached to the ESC menu rather than a key of its own.
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
- **1.1.6 PACKAGED (2026-09-20, morning) — NOT yet uploaded.** Dragón's call
  that morning: Esaeon never answered, so 1.1.6 ships without any claim about
  the Proton crash, and niconoko's request goes in because it is small.
  - **New setting `ShowPersonalityTags`** (DISPLAY section, 1/0, default 1):
    where the tags START; the Tags key still toggles them from there.
    `Indicator.lua` reads it at load. niconoko (Nexus, 19 Sep): they did not
    want to press the key every session.
  - **Settings added by a later version are now appended to the player's own
    file** (`Settings.TextWithMissingKeys` + `Settings.AppendedTextIsGood`).
    It is an INSERTION before the file's last `}`, never a rewrite, and the
    result is parsed back in an empty environment and checked (every player
    value survived, every new key at its default) before anything is written;
    if the check fails the file is left alone and the console says so. This was
    the scaling problem with the old "never rewrite" rule: every future setting
    would have asked every existing player to delete their file.
  - **Dev instrumentation removed:** `DevWatch.lua` deleted with its four call
    sites (`Interaction.lua` x3, `main.lua`), `Logger.DebugEnabled` deleted
    (only DevWatch used it), `DEBUG_LOGGING = false`, `TRACE_PHASES = false`.
    `Logger.trace` and its call sites STAY, inert: a future test build is one
    flag away. Hooks back to 17 (the two `[BOSS-REWARD]` ones were DevWatch's).
  - **Tests:** settingstest.js sections H (append: added once, own values and
    own text kept, idempotent on the next launch, no-comma and empty files,
    every refusal case of the safety check) and I (the tags start from the
    file). All 22 suites pass against `mod/` AND against
    `release/PalBonds/Scripts`; undefcheck 4 / hoistcheck 2 known false
    positives.
  - **Packaged:** `release/PalBonds-v1.1.6.zip` (14 files, 298 KB), both
    release trees re-synced, `release/workshop/PalBonds/Info.json` → 1.1.6,
    README.txt (x2), README.md and both store descriptions updated (the new
    setting, the append behaviour, and bosses counting as defeated). The 1.1.5
    zip is still there; delete it once 1.1.6 is live.
  - **Deployed to both live installs** (manual `ue4ss/Mods/PalBonds/Scripts`
    and `Mods/NativeMods/UE4SS/Mods/PalBonds/Scripts`), md5-verified, DevWatch
    deleted from the manual copy. The manual loader (`dwmapi.dll`) is enabled.
    Dragón's live settings file is a 1.1.5-era one with no
    `ShowPersonalityTags`, so his next launch is a real test of the append.
  - **FOUND LIVE, run 1 (2026-09-20 14:33): `os.rename` cannot overwrite on
    Windows.** The append built the right text and passed its own safety check,
    then `[SETTINGS] could not write ... — ShowPersonalityTags use their
    defaults`. `write_text_file` wrote `<file>.tmp` and renamed it over the
    target, which works only when the target does not exist — i.e. only when
    CREATING the file, never when replacing one. Every existing player would
    have seen exactly this. Fixed with the move-aside dance DarnMenu also uses:
    tmp → move the current file to `.bak` → rename tmp into place → delete the
    `.bak`, and on any failure the `.bak` goes straight back. **The harness's
    fake `os.rename` now fails when the destination exists, like Windows** —
    it happily overwrote before, which is why 22 green suites still shipped a
    file the game could not write. Tests added for the failed-write path (the
    player's file untouched, no `.tmp`/`.bak` left, console message).
  - **Nexus: LIVE** (checked 2026-09-20): version 1.1.6, "PalBonds V1.1.6",
    297 KB, uploaded 3:01PM, Dragón's six-line changelog and his short
    description. The page description was NOT touched and must not be.
  - **STORE DESCRIPTIONS ARE NOT PART OF A RELEASE (Dragón, 2026-09-20).** I had
    edited both description files for 1.1.6; he told me to revert them: "we are
    not changing the descriptions until i deem it necesary, not for every small
    change we add." The description is already long enough that players skip it
    — his proof is the Steam commenter who asked about multiplayer when the
    description says it is singleplayer-tested only. Both `.txt` files were
    reverted to the live 1.1.5 text. **Planned instead: trim the descriptions
    around 1.2.0**, once several things have settled — the next description work
    is a cut, not an addition.
  - **Workshop staged and live-tested (2026-09-20).** Dev install disabled
    (`dwmapi.dll` and `ue4ss/Mods/PalBonds/enabled.txt` → `*.MODS-DISABLED`).
    Upload folder: 11 scripts md5-identical to `release/workshop`, Info.json
    1.1.6 with its BOM, `.workshop.json` untouched (still 1.1.5 until the
    uploader rewrites it). Dragón's Workshop run was clean, and the append ran
    a second time on the Workshop path: `Mods/NativeMods/UE4SS/Mods/shared/`
    took `ShowPersonalityTags` at 15:09 with no `.tmp`/`.bak` left behind.
  - **Workshop: LIVE** (checked 2026-09-20): change note "Version 1.1.6" with
    the six lines, dated 20 SEP 11:17 Steam time. **`.workshop.json` was
    touched at publish time but still reads `last_published_version` 1.1.5** —
    the same inconsistency seen at 1.1.3 (it kept 1.1.1) while 1.1.5 did write
    back. So that field is NOT a reliable publish check; read the item's
    change-note page instead. Descriptions untouched on both stores.
  - **Left:** GitHub (commit, release notes) and the merge of
    `test/join-cleanup` into `master`.
- **ESAEON'S CRASH: SOLVED, AND IT WAS NOT OURS (2026-09-20).** Their own
  investigation on GitHub #1: every crash in the thread — the preset builder,
  the pet check, the nameplate sweep — had the identical native stack, all
  frames inside UE4SS, none in the game. All of them ran on **UE4SS v3.0.1
  Beta Git SHA `c838a8ac` (15 July 2026)**, a build that appears in UE4SS-RE's
  own tracker for a separate native crash (UE4SS-RE/RE-UE4SS#1351). Updating
  to **Okaetsu's `2281fa31` (3 Sept 2026)** fixed every one of them with **no
  PalBonds change**, verified with the four-run protocol from
  `docs/crash-testing-guide.md`: runs A–D clean, 426 nameplate scans all
  paired, the session ending on a normal tick instead of a cutoff.
  - **Verified here:** the Workshop UE4SS on Dragón's machine IS `2281fa31`,
    so Workshop players get the good build with the dependency. The manual dev
    install is `ba2efd55`, a different build again — worth remembering that we
    develop on a build no player necessarily runs.
  - **What this means for the mod:** three of our defensive fixes (join
    cleanup, sensor checks, the pose release) were built while chasing this and
    are good in their own right, but none of them was the cause. The remaining
    crash report to watch is Toxik's, on Windows with ~40 mods, which is NOT
    assumed to be the same thing (Dragón's ruling).
  - **Open question for Dragón:** whether the mod page should carry a line
    telling manual-install players to update UE4SS if theirs predates
    September 2026. That is a requirement fact, not a feature blurb, so it is
    worth asking even under the "descriptions are not part of a release" rule.
  - Left: reply on Nexus (drafted), then a comment on GitHub #1 and closing
    it — his call, and nothing posted without it.
- **MULTIPLAYER, STEP 1 — WHICH PLAYER IS OURS (2026-09-20, built, tests pass,
  deployed, NOT yet seen in game).** Dragón chose multiplayer as the next work
  and agreed with starting here: "first check which player is doing the things
  so cross player's captures or join dont get mess up". Releasing Pals back to
  the wild stays AFTER multiplayer and the settings screen — "its an extra out
  of scope from this project".
  - **The bug:** every player lookup took the FIRST valid `PalPlayerCharacter`
    in the object list. One player in singleplayer, so always right; in co-op
    every player's character is loaded on every machine, which is how
    LuWicki97 (Workshop, 2026-09-15) watched the Digtoise HE befriended join
    his friend's party.
  - **The fix:** `PlayerRef.pick_local` prefers the character this machine
    controls (`APawn::IsLocallyControlled`, Engine.hpp 8884; the controller
    twin `IsLocalPlayerController` is 8289). `search()` and
    `ProbeForNewPlayer` both use it, so another player's character can no
    longer be mistaken for "a new world loaded" either.
    `Interaction.find_player_controller`'s fallback list prefers the local
    controller the same way (UEHelpers' own GetPlayerController is NOT
    co-op-safe: it accepts any `IsPlayerController()`).
  - **What happens when the question is not answered** (the part that matters):
    somebody says true → that one, wherever it sits; nobody says true, exactly
    one character, and nothing has ever answered true this session → that one,
    so a build that cannot answer keeps singleplayer working exactly as before;
    nobody says true with several characters and the call never worked → the
    first one plus one log line, rather than going blind; otherwise → nil, and
    the caller retries (it never latches). Once anything HAS answered true the
    answer is believed, so a lone character that says "not yours" is not
    adopted.
  - **One `[PLAYER-LIFE]` line per session says HOW our character was
    recognised** — that is the only way to learn from a player's log whether
    this build answers the question at all, which decides whether co-op can
    work.
  - **Tests:** `tools/harness/multiplayertest.js` (A–E, 30 checks). Verified
    against the shipped 1.1.6 code: the four behavioural checks fail there
    (Get picks the wrong player, a foreign character reads as a new world, the
    emote plays on the wrong pawn) while the no-regression check still passes.
    23 suites pass on `mod/`.
  - **Deployed to the manual install only**, with `DEBUG_LOGGING = true` in the
    game copy's Logger.lua (mod/ stays false). The NativeMods copy is left at
    the released 1.1.6.
  - **RUN 1 (2026-09-20, 16:19-16:26): the engine ANSWERS.** `[PLAYER-LIFE] our
    player character is the one this machine controls (IsLocallyControlled),
    out of 1 in this world`. Singleplayer played normally, no Lua errors, and
    the second line of the run is a bonus: at the world change the remaining
    character stopped being locally controlled, which is now another way the
    mod notices the world going away (the reset fired in the same second).
    So co-op can be built on this call.
  - **Next:** a co-op reconnaissance session with a friend, both with the mod,
    to see what already works before any further co-op code.
- **DUPLICATE "starts following you" MESSAGE — FOUND AND FIXED (2026-09-20).**
  Dragón, on his second Petallia: "i think i saw the follow toast twice". The
  log proves it: interaction #2 crossed 50% (told), the passive tick then hit
  the capture threshold — and `maybe_trigger_capture` clears `isFollowing` so
  the follower tick lets go — and interaction #3, landing inside the 5 s wait
  before the join, looked like a fresh 50% crossing. `OnInteractionSucceeded`
  now also requires `not st.captureTriggered` before starting a follow. Test
  `pointstest.js` P13 replays that exact sequence and fails on the shipped
  1.1.6 code (two toasts, "bonding bar crossed" twice).
- **MISSING TRUST BAR — ROOT CAUSE FOUND AND FIXED (2026-09-20, second
  occurrence: Lullu / `BP_LeafPrincess_C`).** Dragón reproduced it in a
  singleplayer run with full diagnostics on. Lullu was fed 13 s after a world
  reload, bonded, followed him, sat on screen for 17 s (AIM-FREEZE lines) — and
  Indicator never once created widgets for her gauge; only 3 gauges were ever
  built in that world.
  - **Mechanism, certain from the code:** a nameplate can find its Pal ONLY
    through the handle the `BindFromHandle` hook hands us (`gaugeHandleByKey`);
    the widget's own `bindedHandle` field is unreadable in this UE4SS build
    (fifty-ninth pass). So a nameplate whose bind we lost can never show a tag
    or bar, and no sweep can recover it, until the game rebinds that widget.
  - **Where the binds were lost:** `Indicator.ResetForNewWorld` wiped
    `gaugeHandleByKey`. The reload is noticed by polling a moment AFTER the new
    world starts loading — both logs show the new world's Pals being rolled a
    second before the reset line — so the new world's nameplates were already
    bound and the reset threw those binds away with the old world's.
  - Both cases (Petallia 16:25, Lullu 20:46) were bonded within ~20 s of a
    reload; the run that did not reproduce it waited longer. NOT caused by the
    guest gate: the Petallia case predates `Session.lua`.
  - **Fix:** the bind hook records when each nameplate was bound
    (`gaugeBoundAt`); the reset keeps binds from the last 20 s
    (`NEW_WORLD_BIND_GRACE_SECONDS`) and re-queues them, and drops older ones as
    before. A kept handle that proves to be the old world's simply fails to
    resolve. `worldchangetest.js` section I.
- **(superseded) MISSING TRUST BAR ON THAT SAME PETALLIA — open, needs one run.** He saw no
  friendship bar on her at all, having started with a Play interaction. The
  log cannot answer it: every Indicator install/scan line is diagnostic-tagged
  and was filtered out of that run. Two candidates, and they are distinguished
  by whether a world reload happened first:
    a) something about installing NEW nameplate bars breaks after a world
       reload (that world was the reloaded one, and only 2 nameplate bars were
       ever tracked in it, against 35 in the first);
    b) nothing is broken: he played her from 804 units (the Play limit is 900),
       where the game shows no nameplate at all, and once he got close she was
       ~5 s from joining.
  **Set up for it (2026-09-20):** the game copy now has `DEBUG_LOGGING = true`
  AND `SHOW_DIAGNOSTICS = true` (mod/ stays false on both). Protocol given to
  Dragón: fresh launch, walk CLOSE to a wild Pal so its nameplate is on
  screen, pet once, look for the bar; then quit to title, load again, and do
  exactly the same with another Pal. Report which of the two showed a bar.
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
