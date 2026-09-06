# PalBonds — Design Document

A Palworld mod that lets players earn a wild Pal's trust through care (petting,
feeding, standing by it in a fight) instead of only capturing it by force. High
trust unlocks a temporary follow-and-protect bond; enough trust converts that
bond into a real capture with no Palsphere; losing all trust makes the Pal
flee for good.

Status: design phase. Nothing here has been verified against the live game
yet — every hook point below is a hypothesis to confirm with FModel/UE4SS
before writing real Lua against it. Treat the "Open Research Questions"
section as the actual first task list.

## 1. Goals

- Give every wild Pal an individual, mutable personality/disposition instead
  of a fixed per-species one (a Tanzee *can* end up bold, a Starryon *can*
  end up calm), seeded by the species default but drifting from how the
  player treats that individual.
- Let the player interact with wild, uncaptured Pals the same way they
  already interact with owned ones: pet and feed.
- Track a per-individual Trust value (0.0–1.0) driven by those interactions
  and by combat outcomes while the Pal is bonding with the player.
- At Trust 1.0: capture the Pal directly into the party, no Palsphere thrown,
  no capture minigame.
- At Trust 0.0 (after having risen above 0 first): the Pal flees and is
  permanently flagged as uninterested — back to normal forced capture only.
- Keep the whole thing self-contained enough to run in singleplayer / a
  self-hosted server without needing a game update or official SDK.

## 2. Non-goals (for v1)

- No new models, textures, or animations. Every state we need (follow, fight,
  flee, idle-watch, eat, get-patted) should already exist as an animation/
  behavior the game uses somewhere for owned or wild Pals — we're
  re-triggering and re-routing existing behavior, not authoring new art.
- No promises about official-server play. This targets singleplayer/
  self-hosted first; multiplayer replication is a stretch goal, noted but not
  blocking.
- No UI/HUD work beyond whatever minimal prompt or trust indicator is
  strictly needed to make the mechanic legible. Polish comes after the
  mechanic works.

## 3. Subsystems

Each of these is being treated as an independent module (its own Lua file)
so we can build and test them one at a time rather than needing the whole
system working before anything is visible in-game.

### 3.1 Personality state (`Personality.lua`)

**What it does:** gives each wild Pal instance a current disposition
(curious / skittish / hostile / etc.) that starts at the species default but
can be overridden per-instance, and exposes that value for the AI/behavior
layer to read.

**Precedent:** mods like "Aggressive or Passive Wild Pals" and "Pal Passive
Reworks" already prove the species→disposition link is reachable and
overridable. What we need on top of that is per-*instance* state rather than
a species-wide blanket swap.

**Approach:** on Pal spawn/first-sighting, tag the actor with a custom
attribute (disposition + a random seed or player-history-derived roll) and
have the behavior-tree read hook check our tag before falling back to the
species default.

**Risk:** low-medium. The override point clearly exists; the work is finding
where per-instance actor state can be attached that survives as long as the
actor is loaded (see Trust below — same storage problem, worth solving once
for both).

### 3.2 Wild-pal interaction: pet & feed (`Interaction.lua`)

**What it does:** extends the existing pet/feed prompt (currently gated to
"this Pal belongs to you") so it also appears on wild Pals within some
disposition/distance rules — e.g. a curious Pal that's already watching you
is interactable sooner than a skittish one that's actively running.

**Approach:** find the ownership/gate check in front of the interact prompt
and add an alternate branch for "wild but not hostile and within range,"
routing into the same pet/feed functions already used for owned Pals so we
reuse existing animations and item-consumption logic rather than
reimplementing them.

**Risk:** medium. This is the one piece with no existing mod precedent we
found, so the gate check location is unknown until we inspect it directly.

**Update (2026-09-03, seventy-third pass):** Dragón asked to move Pet/Feed
onto the game's own "4" radial menu instead of F9/F10. Reading the real
`WBP_PlayerRadialMenu` Blueprint (extracted directly from Dragón's own game
pak via `repak` — see `docs/hook-points.md`'s seventy-third pass) found the
real function names (`OpenPlayerActionMenu`, `"Can Open Player Action
Menu"`, `OnDecidedPlayerActionMenu`, `"On Decided Instruction Care"`,
`OnDecidedInstruction_Feed`) but also a strong signal that this whole
system is scoped to the player's own ACTIVE OTOMO
(`GetOtomoHolderComponent`, `TryGetSpawnedOtomo`, `IsOtomoActivated`
everywhere in its strings) — not a generic "whatever Pal you're looking at"
system. Read-only watch hooks are now live on all of the above (Interaction
.lua, forty-second pass) to confirm/deny this directly against a real
session before deciding whether wild-Pal Pet/Feed can reuse this menu or
needs its own lightweight custom wheel. F9/F10 are unchanged for now.

**Update (2026-09-03, seventy-fourth pass):** Dragón corrected the
Otomo-only worry above with a real test — the wheel also works on an owned
Pal that isn't your active Otomo (he petted a Tanzee left roaming at his
base by aiming at it). The existing native `PalInteractComponent`
MENU-WATCH hooks confirm this directly (`ActionType=4`, real
`TargetInteractiveObject` = the Pal's own interactable sphere) — so the
real gate is more likely an ownership check somewhere upstream, not "must
be the one active Otomo." Separately, all 8 new Blueprint hooks failed to
register ("no UFunction with the specified name found") — likely because
the names read from `strings` included Unreal's cosmetic, auto-spaced
DisplayName rather than the real FName (e.g. real name probably
`CanOpenPlayerActionMenu`, not "Can Open Player Action Menu"). Fixed by
trying the no-space form first plus a bounded retry loop, in case the class
also just wasn't loaded yet at mod boot. See `docs/hook-points.md`'s
seventy-fourth pass for the full writeup. Needs another live test.

### 3.3 Trust meter (`Trust.lua`)

**What it does:** a persistent 0.0–1.0 float per wild Pal instance. Gains
from petting/feeding (tunable per-action, diminishing returns to discourage
just spam-feeding once), gains from *winning* a fight while the Pal is
nearby/assisting, and losses from the Pal taking damage while bonding.
Crosses at 0.0 and 1.0 trigger the two threshold events in 3.5/3.6.

**Precedent:** a mod called "Configurable Trust On Capture" tells us a trust
concept already exists somewhere in the game's own data/systems — worth
checking whether we can extend that existing value rather than inventing a
fully parallel one.

**Approach:** same per-instance storage problem as Personality — likely
solved together. Needs hooks on: pet action complete, feed action complete,
this-Pal-took-damage, this-Pal's-opponent-was-defeated-while-Pal-was-
assisting-player.

**Risk:** high. This is the load-bearing subsystem and the trickiest: wild
Pals can despawn/respawn based on chunk streaming, so we need to decide what
happens to an in-progress bond if the Pal unloads (persist by save-ID if
possible; if not, accept that far-away long bonds can reset, and say so
plainly to the player).

### 3.4 Follow & protect (`Combat.lua`)

**What it does:** once Trust crosses a "bonding" threshold (proposed: >0,
i.e. any positive trust), the wild Pal starts following the player like an
owned Pal does, and assists them in fights against other wild Pals/enemies.

**Precedent:** this behavior already exists wholesale for owned Pals. The
plan is to route a bonding-but-uncaptured Pal into that *same* behavior-tree
branch rather than building new follow/fight AI from scratch — reuse, don't
reinvent.

**Risk:** low-medium, contingent on how cleanly that branch can be entered
without the game's normal "this Pal is in your party" bookkeeping getting
confused (party slot logic, UI, etc. all assume a captured Pal — need to
confirm none of that breaks when we fake the follow state without a real
capture).

**Reference-mod findings (2026-09-03, sixty-fifth pass, not yet acted
on):** extracting `PassiveWildPals`'s compiled `.pak` (overrides
`BP_AIAction_WildLife`) surfaced a complete, native leader/follower squad
system already used for wild Pal herds — real classes/functions
`PalSquad`, `GetSquad`, `GetIsSquadBehaviour`, `GetLeader`, `IsLeader`,
`FollowLeader`, `IssueAsyncFollowMove`, `CancelAsyncFollowMoveIfAny`,
`BP_RequestAsyncMoveTo`, `SimpleMoveToActorWithLineTraceGround`. This looks
like a real candidate for "route a bonding Pal into an existing follow
branch" instead of writing custom follow movement — worth investigating
whether a wild Pal can be assigned the player as its squad leader. The
same file also confirmed `GetIndividualHandle` → `TryGetIndividualActor()`
working live in native AI logic (further confirmation this project's own
actor/handle approach is sound) and that the disposition/response system
(`SelectResponseBySenses`, `EPalAIResponseType`, a variable literally named
`TargetIsPlayerOrPlayersOtomoPal`) is read every AI tick, relevant to
`Personality.lua`.

Separately, `RemoteAccessEverything`'s `.pak` (overrides
`WBP_PlayerRadialMenu`) revealed the real Otomo instruction/order system:
`RequestSetOtomoOrder`, `GetOtomoOrder`, `EPalOtomoPalOrderType`, and the
actual instruction message IDs (`PAL_INSTRUCTION_ASSIST`,
`PAL_INSTRUCTION_ATTACK`, `PAL_INSTRUCTION_CARE`, `PAL_INSTRUCTION_ESCAPE`,
`PAL_INSTRUCTION_FEED`) — the real command set for telling an Otomo Pal to
assist in combat, wait, or flee. If a bonding-but-uncaptured wild Pal can
accept these same orders, this could be the real "assist in a fight"
mechanism instead of a custom one. Neither of these has been tested live
yet — both are read-only findings from static analysis of the compiled
Blueprint, not confirmed working for a non-owned wild Pal.

### 3.5 Auto-capture at Trust 1.0 (`Capture.lua`)

**What it does:** when Trust hits 1.0, run a capture with no Palsphere and no
minigame — straight into the party.

**Precedent:** directly proven by existing mods ("Human Mercy Bypass",
"Catch Gun", "Capture the Uncapturables") that already perform sphere-less,
guaranteed captures. This is the least risky subsystem in the whole project.

### 3.6 Permanent flee at Trust 0.0 (`Capture.lua`)

**What it does:** once Trust (having been above 0) drops back to 0.0, the
Pal flees, stops being interactable, and is flagged so it never re-enters
the bonding flow again (back to needing a normal forced capture, same as any
untouched wild Pal).

**Approach:** a simple per-instance boolean flag checked by the Interaction
gate from 3.2, plus routing the Pal into its existing flee/despawn behavior.
Low technical risk; mostly bookkeeping.

## 4. Technical stack

- **UE4SS** (Okaetsu's experimental build) — Lua scripting host, function
  hooking, live object/property access. This is where essentially all of the
  above logic will live.
- **PalSchema** — used opportunistically, not as the primary engine. If any
  piece turns out to be a plain data-table value (e.g. a per-species base
  disposition table, or a capture-rate table row) we'd rather patch it via a
  PalSchema JSON file than hook it in Lua. Everything behavior/event-driven
  (trust changes, following, capture-on-threshold) stays in UE4SS Lua.
- **FModel** — read-only asset/data inspection to find real class, struct,
  and data-table names before writing any hook against a guessed name.
- **UE4SS's own object dumper / Live View** — to find the actual Blueprint
  function names on the running game (class names from FModel don't always
  tell you which function to hook).

## 5. Repo layout

**Update (2026-09-03, hundred-and-twenty-first pass):** this project used to keep two parallel copies of everything — a top-level Proyectos mirror and a second, nested `palbonds-mod/` mirror matching the layout originally documented here. The nested one silently went stale for several files over ~120 passes without anyone noticing, since nothing forced the two to stay in sync. Consolidated into one place, at Dragón's request: everything now lives directly under `32-PalBonds/`, flat, no nested `palbonds-mod/` folder. The layout below is otherwise unchanged, just rooted one level up.

```
32-PalBonds/
├── DESIGN.md              <- this file
├── README.md              <- setup + how to test locally
├── research/               <- Mappings.usmap, unpacked reference-mod assets
├── docs/
│   ├── hook-points.md      <- running checklist of real names we've confirmed
│   ├── phase0-install.md
│   └── phase1-research.md
└── mod/
    └── PalBonds/            <- drop this folder into <Game>/Mods/ once built
        ├── enabled.txt
        └── Scripts/
            ├── main.lua         <- entry point, wires the modules together
            ├── Personality.lua  <- 3.1
            ├── Interaction.lua  <- 3.2
            ├── Trust.lua        <- 3.3
            ├── Combat.lua       <- 3.4
            └── Capture.lua      <- 3.5 / 3.6
```

## 6. Phased roadmap

**Phase 0 — Tooling.** Install UE4SS + FModel against your actual Palworld
install, confirm the pre-built stub mod loads (a "hello world" print in
main.lua on game start is the acceptance test for this phase). Nothing
game-specific yet.

**Phase 1 — Personality reassignment.** Prove we can read and override an
individual Pal's disposition. Smallest slice with the most precedent;
mainly validates the toolchain and our approach to per-instance state, since
Trust needs the same storage mechanism later.

**Phase 2 — Wild-pal petting/feeding.** Get the interact prompt appearing on
a wild Pal and successfully running the existing pet/feed logic against it.
No trust math yet — just prove the interaction itself is reachable.

**Phase 3 — Trust meter.** Wire petting/feeding into a stored trust value,
add combat-outcome hooks (damage taken / opponent defeated while bonding).
No visible behavior change yet beyond the number existing and logging
correctly — verify the math before it drives anything.

**Phase 4 — Follow & protect.** Route positive-trust Pals into the
owned-Pal follow/fight branch. This is the first phase that's visibly "the
mod" in gameplay terms.

**Phase 5 — Threshold outcomes.** Wire Trust 1.0 → sphere-less capture and
Trust 0.0 → permanent flee + flag.

**Phase 6 — Polish & config.** Tunable rates (pet/feed gain, damage loss,
decay over time if we want one), a minimal on-screen trust indicator, config
file so players can adjust pacing, and a pass at what happens across
save/load and chunk unload for in-progress bonds.

**On-screen trust indicator — Dragón's spec (2026-09-02, end of day 1),
IMPLEMENTED 2026-09-03 (forty-third pass), NOT YET TESTED LIVE:** a small
secondary bar under a bonding wild Pal's existing health bar, showing
live FriendshipPoint progress toward CAPTURE_AT_FRIENDSHIP_POINT. Fills
from pets/feeds and from passive gain while the player stays nearby (both
already real, working mechanics in Trust.lua); visibly drops when the Pal
takes damage (DAMAGE_FRIENDSHIP_PENALTY, also already real, since the bar
just reflects the same FriendshipPoint value that penalty already
lowers). Directly motivated by the forty-second pass's diagnosis: passive
gain was confirmed working the whole time, but with zero visual feedback
it looked broken.

**First attempt (forty-third pass) FAILED, cleanly diagnosed:** hooked
the HUD's own per-frame canvas draw event (`AHUD:ReceiveDrawHUD`) and
drew rectangles via `AHUD:DrawRect`. Installed without error, but
Dragón's live test showed no bar at all across a full session where the
underlying trust/capture logic worked perfectly (both test Pals reached
56 friendship and were captured on schedule). The log proved why: the
hook's own one-time "first frame seen" confirmation line never printed —
the hook never fired even once. Conclusion: Palworld's real HUD doesn't
route through that legacy Blueprint event at all (consistent with a
modern, fully UMG-based HUD). Abandoned, not tuned.

**Second attempt (forty-fourth pass) ALSO FAILED:** switched to
`UKismetSystemLibrary:DrawDebugString`, a real native engine debug-text
function (found via this UE4SS install's own bundled `LineTraceMod`,
which calls the same library successfully in this game). Installed
without error, ran a full live test — still no bar, and this pass didn't
even log a success confirmation to explain why. Most likely real cause,
identified afterward: Palworld ships as a Shipping build, and Unreal
strips `DrawDebug*` calls out of Shipping builds by design (compiled to a
no-op, not an error) — meaning no debug-draw function could ever have
worked here, independent of positioning. A dead end on principle.

**Third attempt (forty-fifth pass), READ-ONLY RESEARCH, not yet a working
bar:** Dragón found a real precedent, a Nexus mod ("VisiblePalCaptureCounter")
built for an older Palworld version that writes text directly into the
wild-Pal HP gauge's own real UMG widget (not debug-draw, so it can't be
stripped — it's part of the shipped game's real UI). Checked what's still
real in the current game before reusing anything blind: the text-setting
mechanism it used (`SetText_GDKInternal` on the native text-block base
class) is confirmed unchanged, but the specific widget class/asset path it
hooked has no match anywhere in the current header dump — likely renamed
or restructured since that mod was built, exactly as Dragón warned.
Rather than guess at a new name, `Indicator.lua` now hooks two NATIVE
functions instead (`UPalUICharacterHPGaugeBase:SetTargetCharacter`/
`SetHPPercent`) — hooking the native base fires regardless of whatever
the current Blueprint subclass is actually called, sidestepping the "did
the name change" question entirely, and hands back the real live widget
instance so its actual class name can be read straight from the log.
Read-only, capped logging.

**Live test (forty-sixth pass): negative result on the two hooks, but a
real hit on the existence scan.** Dragón petted and accidentally hit a
wild Lamball over a ~10-minute session — neither `SetTargetCharacter` nor
`SetHPPercent` fired once (confirming those functions aren't what drives
a wild Pal's gauge here). But the periodic `FindAllOf` existence scan
caught something real: `PalUICharacterHPGaugeBase` stayed at 0 the whole
time, while `PalUINPCHPGaugeCanvasBase` consistently showed live
instances of a real class, `WBP_PalNPCHPGaugeCanvas_C` — one the
Blueprint archetype, one a genuine live instance under the running
PlayerUI's widget tree. This confirms the game consolidated what the old
mod knew as one-widget-per-Pal into a single shared canvas managing
multiple Pals' gauges at once, explaining why no per-instance hook ever
fired.

**Forty-seventh pass, still read-only:** with a real live object
confirmed, reused this project's own proven technique
(`Interaction.lua`'s `dump_interesting_properties`, twelfth pass) —
`Class:ForEachProperty()` walked up `GetSuperStruct()`, which surfaces
Blueprint-added fields a static header dump can't show — this time
unfiltered and with added `ArrayProperty` handling (length + element
class names), since the per-Pal gauge slots are almost certainly held in
an array on this canvas. Runs once, the moment the scan finds the real
live instance. Needs one more live test to see the actual field dump.

**Forty-seventh pass RESULT + forty-eighth pass (still read-only):** the
dump succeeded — real class hierarchy confirmed, plus real fields
`DisplayedPalGaugeMap`/`DisplayedBossUGaugeMap`/`DisplayedPlayerGaugeMap`
(all `MapProperty`, the likely per-Pal lookup table) and `Canvas_Root`/
`WrapBox` (UMG panel widgets). `dump_all_properties` can't read
`MapProperty` — and neither can the bundled reference tool
`ConsoleCommandsMod/dump_object.lua`, which explicitly leaves it
unhandled with a "need to add support eventually" comment — so reading
`DisplayedPalGaugeMap` directly looks unsupported by this UE4SS Lua
build. Pivoted to `WrapBox` instead: confirmed via both `UMG.hpp` and the
bundled Lua type stubs that its base class `UPanelWidget` has real,
ordinary `GetChildrenCount()`/`GetChildAt(Index)` functions — standard
UMG child enumeration, present in this build. `Indicator.lua` now checks
the live WrapBox's child count every scan tick, and the first time it's
> 0, lists every child and fully dumps the first one's fields — looking
for its text-block sub-widget (to call the still-valid
`SetText_GDKInternal` on) and whatever identifies which Pal it belongs
to. Needs one more live test (look at a wild Pal so the WrapBox actually
has children) to see the child dump.

**Forty-eighth pass RESULT: inconclusive, not negative — and possibly the
wrong container regardless.** Dragón's test session was only ~95 seconds
long; the WrapBox never got a single child in that time, so nothing was
really ruled out. Separately, a `WrapBox` auto-flows children into ONE
shared list position, which doesn't fit gauges that need to float
independently above each Pal's own screen position — `Canvas_Root` (a
`CanvasPanel`, also confirmed real on the same canvas), whose children
each get their own positioned `CanvasPanelSlot`, is structurally the
better fit. **Forty-ninth pass:** generalized the WrapBox check into
`check_panel_children(fieldName)` and now checks both `WrapBox` and
`Canvas_Root` every scan tick, dumping whichever gets a live child first.
Still read-only. Needs a genuinely longer live test: stand near a wild
Pal with its HP bar visible for 10-15+ seconds, not a quick glance.

**Forty-ninth pass RESULT: real signal — `Canvas_Root` is the live
container.** Its child count climbed 2 -> 11 -> 17 -> 19 -> 20 as Dragón
walked among wild Pals; `WrapBox` never moved. But the dump caught the
wrong child: index 0 turned out to be the `WrapBox` itself — an always-
present structural fixture inside `Canvas_Root`'s own tree, not a Pal.
Real per-Pal children only appear at index 1+ as the count climbs.
**Fiftieth pass:** now re-lists all children on every count change (not
just once), and dumps the first child whose class ISN'T a known
structural container (`WrapBox`, `CanvasPanel`, etc.) — wherever it lands
in the index order, tracked so each real class only gets dumped once.
Still read-only. Needs one more live test near several wild Pals.

**Aside:** also checked a second reference mod Dragón found ("Pal
Analyzer") — turned out to be a compiled LogicMods `.pak` (Blueprint
assets), not UE4SS Lua, so no reusable source/technique came out of it;
just confirms a "look at a Pal, show live text" widget is achievable here
at all. See hook-points.md for detail.

**Fiftieth pass RESULT — the breakthrough.** Every new `Canvas_Root`
child was class **`WBP_PalNPCHPGauge_C`** — the EXACT class the old
reference mod used. It wasn't renamed after all; it just never happened
to get individually header-dumped before, so earlier passes couldn't see
it existed. Its dump confirmed `WBP_EnemyGauge` (the same sub-widget path
the old mod wrote text into) and `SyncId` (type `PalInstanceID`, this
project's own stable per-Pal GUID from Q5) are both real and present.
**Fifty-first pass:** added a targeted read of `.WBP_EnemyGauge`'s own
fields and `.SyncId`'s sub-fields (`DebugName`/`InstanceId`/`PlayerUId`),
using the same safe struct-field-read pattern already proven on
`FPalDamageResult.Defender`. Still read-only. One more live test should
surface the real text-widget field name and a readable Pal ID — enough
to write the first real line of visible trust-progress text.

**Fifty-first pass RESULT: `Text_WorkName` confirmed real**, under the
exact same path (`WBP_EnemyGauge.Text_WorkName`) the old reference mod
used — a `BP_PalTextBlock_C`, subclass of the already-confirmed
`UPalTextBlockBase`. `SyncId`'s sub-fields came back useless (printed a
generic struct-wrapper identity, not real values) since each is itself a
nested `FGuid` struct needing one more level of indexing. **Fifty-second
pass:** fixed the GUID read (`describe_guid()`, indexes `A`/`B`/`C`/`D`
directly) and, since `Text_WorkName` is confirmed, made this whole
effort's FIRST REAL WRITE — `SetText_GDKInternal(true, "PalBonds TEST")`
on the one live gauge widget found, once. A text-set call on an
already-live, already-rendering widget — a fundamentally safer shape
than the native gameplay-action calls that caused this project's three
real crashes early on. If the text shows up in-game, the hard research
question is answered and everything left is wiring real data through.

**Fifty-second pass RESULT: the write call succeeded but nothing showed
up.** No Lua error — the exact signature of a widget whose `Visibility`
is `Collapsed` (setting text ≠ making it visible). `Text_WorkName`'s own
name and its siblings (`CachedIsWork`, work-icon animations) suggest it's
normally shown only for a Pal doing base-camp work, collapsed otherwise —
which fits a wild, non-working Pal exactly. **Fifty-third pass:** now
dumps the widget's real `Visibility` before writing, and forces
`SetVisibility(0/Visible)` immediately before calling
`SetText_GDKInternal` again. If that's all that was missing, the text
should finally appear; if not, next step is checking the parent
container's own visibility rather than this widget alone.

**Dragón's course-correction:** the `Text_WorkName` write above was only
ever meant to sanity-check that writing to a live widget works at all —
never the actual deliverable. Dragón's original spec (quoted at the top
of this section) is a real graphical fill bar under the HP bar, and the
reference mods were given purely to learn technique, never as literal
templates. Given the choice between text-now/bar-later and researching
the real bar first, Dragón chose to research the real bar first.

**Fifty-fourth pass:** the real open question — can UE4SS Lua construct
a brand-new UMG widget at runtime and insert it into a live tree? Nothing
before this pass has ever created a widget; only read/written existing
ones. Research confirmed the pieces exist: `StaticConstructObject` is a
real UE4SS Lua global (proven via the bundled `BPML_GenericFunctions`
mod's own live use of it), `UCanvasPanel:AddChildToCanvas(Widget)` is a
real function returning a `UCanvasPanelSlot` with `SetPosition`/`SetSize`,
and `UProgressBar:SetPercent`/`SetFillColorAndOpacity` is the real class
matching the spec. This pass attempts the full chain once: construct a
`UProgressBar` (Outer = `Canvas_Innner`), set a test percent/color, add it
to `Canvas_Innner` via `AddChildToCanvas`, and position its slot just
under the HP bar. Fully unproven; every step logs its own OK/FAILED so a
partial failure is diagnosable. Result not yet known — needs a live test.

**Fifty-fourth pass RESULT: confirmed working.** Every logged step
returned OK, and Dragón saw a real magenta test bar render in-game on a
wild Chikipi — runtime widget creation is proven possible in this build,
answering the hardest open question in this whole effort. Three
limitations Dragón observed (only one Pal got a bar; it never moved; it
wasn't aligned with the real HP bar) all traced to this version's known
scope: a single global one-shot flag (only the first-found gauge ever got
a bar) and a blind, unreferenced position/size guess.

**Fifty-fifth pass:** fixed both. Bar creation is now keyed per-gauge (by
its own `GetFullName()`) so every wild Pal's gauge gets its own bar, not
just the first. Position is now read from the real HP bar's own slot
(`ProgressBar_HP.Slot`, a `UCanvasPanelSlot`) via `GetPosition()`/
`GetSize()`, and the new bar is placed directly under it instead of a
guess. Still a static 50%/magenta placeholder — not yet wired to real
`FriendshipPoint`, which needs the still-unresolved gauge-to-Pal matching
problem solved first (`SyncId` GUIDs still read all-zero). Needs a live
test with multiple Pals in view.

**Fifty-sixth pass RESULT: Dragón confirmed correct alignment.** Proceeded
to the real next step: wiring live `FriendshipPoint`.

**Fifty-seventh pass:** solved the gauge-to-Pal matching problem via
`bindedHandle` (a `TSoftObjectPtr<UPalIndividualCharacterHandle>`) instead
of the still-broken `SyncId`. `UPalIndividualCharacterHandle` has a real
`TryGetIndividualActor() -> APalCharacter*`; from there,
`actor.CharacterParameterComponent:GetIndividualParameter():GetFriendshipPoint()`
reuses this project's own already-proven route to the friendship value.
`Trust.CAPTURE_AT_FRIENDSHIP_POINT` is now exported so the bar computes
the identical ratio Trust.lua uses for its own capture check. Each bar's
fill is set to the real ratio on creation and refreshed every scan tick
via a new `update_trust_bars()`, so it should actually move as trust
changes. Falls back to the static 50% placeholder, with a clear log
reason, if `bindedHandle` doesn't resolve. Needs a live test: pet a wild
Pal and watch whether its bar starts at a real (non-50%) value and rises.

**Fifty-seventh pass RESULT: two bugs found.** (1) Bars stayed at 50% —
the log showed `handle:IsValid()` itself erroring (no such method on the
raw value), meaning the assumption that `bindedHandle` behaves like a
normal object wrapper was wrong. (2) Pals encountered after walking away
from the spawn area got no bar at all — the per-child scan loop only ran
when the live count differed from the last count it processed, so a
count that cycled back to an already-seen value (one Pal leaves as
another enters) skipped new children entirely.

**Fifty-eighth pass:** added `inspect_bindedHandle_shape`, a one-shot
probe trying several plausible accessors on the raw handle
(`type()`/`tostring()`/`:type()`/`GetFullName()`/`LoadSynchronous()`/
`Get()`/`AssetPathName`) logged under `DIAG-HANDLE` to find its real
shape. `resolve_pal_actor_from_gauge` no longer gates on the broken
`IsValid()` call — tries `TryGetIndividualActor()` directly, falling back
to `LoadSynchronous()` first. Separately, the panel-child scan now always
walks every child when count > 0 (idempotent per-widget calls make this
safe), fixing the missed-Pals bug. Needs another live test.

**Fifty-eighth pass RESULT: worse than before, and both symptoms traced to
real causes.** DIAG-HANDLE showed `bindedHandle`'s raw value
(`TSoftObjectPtrUserdata`) fails every accessor tried — a genuine UE4SS
Lua binding gap, confirmed dead end. Separately, a much bigger bug:
`scan_for_gauge_widgets` silently self-disabled about 50 seconds into
every session (a log-line cap written when this function only did a
lightweight diagnostic, before bar creation/refresh lived inside it too),
killing ALL bar creation and live refresh for the rest of the session —
fully explaining "no bars past the first few seconds" and "stuck at 50%".

**Fifty-ninth pass:** (1) hooks `BindFromHandle` directly to capture the
Pal handle as a live hard-pointer hook argument instead of reading the
broken stored field — the same safe hook-argument pattern this project
already uses elsewhere. (2) the log-cap now only throttles verbose
logging, never the actual scan/bar-creation/refresh work. (3) every
installed bar retries actor resolution each tick until it succeeds
(handles the case where BindFromHandle fires after bar creation).

**Fifty-fifth pass RESULT: every Pal got its own bar, but still shifted
and wider than the real HP bar** — not just a vertical offset. Diagnosed
as a coordinate-space mismatch: the new bar was added into a guessed
container (`Canvas_Innner`) while using position numbers only meaningful
relative to whatever panel `ProgressBar_HP` actually lives in.

**Fifty-sixth pass:** reads `ProgressBar_HP.Slot.Parent` (a real
`UPanelSlot` field pointing to the exact live panel that widget is
already in) and adds the new bar into THAT panel instead of guessing —
guaranteeing identical coordinate space, so the real bar's own
position/size numbers apply directly (offset down by its own height plus
a small gap). Falls back to the old `Canvas_Innner` guess only if that
read fails. Needs a live test to confirm alignment.

**Fifty-ninth pass RESULT: the scan self-disabling fix worked (new Pals
further from spawn got bars), but the bar was still stuck at 50%.** The
log named why: `RegisterHook` for `BindFromHandle` never actually
succeeded — `gaugeWidget:GetClass():GetPathName()` errored ("attempt to
call a TrivialObject value"), a more limited class-object wrapper than
expected. Worse, a self-inflicted bug meant it never got a second try:
the one-shot registration guard was set to `true` unconditionally before
checking success, so that single failure permanently blocked every
future retry for the rest of the session.

**Sixtieth pass:** (1) the one-shot guard now only locks in on an actual
successful `RegisterHook` call, so a failed attempt retries on the next
live gauge instance (frequent and free, since this runs every tick). (2)
tries two candidate hook paths — the full class path via `GetPathName()`
if it happens to be readable, and a fallback built from
`GetClass():GetFName():ToString()` (the plain short class name, already
proven reliable elsewhere in this file) — since UE4SS can often resolve a
uniquely-named Blueprint function by short name alone. Needs a live test:
check the log for a `DIAG-HOOK ... OK` line and whether the bar finally
starts at a real value and moves.

**Sixtieth pass RESULT: heavy, escalating lag, and still stuck at 50%.**
Every attempt failed identically ("no UFunction with the specified name
was found" for `WBP_PalNPCHPGauge_C:BindFromHandle`) — `BindFromHandle`
is actually declared on the parent class
(`UWBP_IndividualParameterBindWidget_C`), not the gauge's own class, so
every candidate tried was built from the wrong name and doomed from the
start. Retrying that doomed call every tick for every visible gauge, with
no cap, is what caused the lag — `RegisterHook` failing a lookup isn't
free internally.

**Sixty-first pass:** (1) tries the correct, hardcoded declaring class
name (`WBP_IndividualParameterBindWidget_C:BindFromHandle`) as the first
candidate — doesn't depend on reading anything off the live widget, so it
also sidesteps the earlier `GetPathName()` failure entirely. (2) hard-caps
total attempt rounds (5) so a persistent failure can't spam `RegisterHook`
indefinitely and burn performance. Needs a live test: confirm the lag is
gone, check for `DIAG-HOOK ... OK`, and whether the bar starts at a real
value and moves when petting a Pal.

## 7. Known constraints & caveats

- **Ban risk:** singleplayer and self-hosted/private servers are safe;
  official Pocketpair servers and most community servers can flag or ban
  modified clients. This project assumes singleplayer/self-host as the
  target, not official multiplayer.
- **Patch fragility:** UE4SS mods hook undocumented internal names. A
  Palworld update can silently break any hook here; expect maintenance
  after game patches, same as every other UE4SS mod in the ecosystem.
- **Multiplayer replication:** if this is ever wanted in co-op, trust state
  and behavior changes need to sync to other clients, which is meaningfully
  harder than the singleplayer case with Lua-level hooking. Out of scope
  until the singleplayer version works.
- **Chunk streaming:** a wild Pal can unload before a bond resolves. Decide
  explicitly (Phase 3) whether trust persists across unload/reload or resets
  — don't let this be an accident.

## 8. Open research questions

This is the actual next to-do list — everything else in this document is
planning until these are answered against the real game files:

1. What's the real class/struct name for a wild Pal's AI Controller /
   Behavior Tree, and where does it read species-default disposition from?

   **ANSWERED, from reading a downloaded mod's asset strings (2026-09-02,
   thirty-second pass), confirmed against the native SDK:** the
   disposition table is `class UPalAIResponsePreset : public UObject` — 8
   fields, all `EPalAIResponseType`: `Discover_Player`, `Discover_Greater`,
   `Discover_Equal`, `Discover_Smaller`, `Damaged_Player`,
   `Damaged_Greater`, `Damaged_Equal`, `Damaged_Smaller` (reaction on first
   sighting something, split by relative threat, plus separately once
   damaged). It's referenced by a plain field, `AIResponsePreset`, on
   `class UPalAISensorComponent : public UActorComponent` — the real,
   native, always-loaded sensing component every Pal has, which also owns
   the actual decision function, `SelectResponseBySenses(CurrentBehavior,
   FindCharacters, IsDamaged, &OutTargetCharacter)`. Both added as
   read-only watches in `OtomoWatch.lua`; not yet observed live. See
   hook-points.md's thirty-second pass for the full source (a third-party
   Nexus mod, "PassiveWildPals," whose own Blueprint asset references
   these exact names — we only read its strings, didn't run or decompile
   it).

   **CONFIRMED LIVE, with a real operational lesson attached
   (2026-09-02, thirty-third pass):** `AIResponsePreset` resolved to real
   named presets on actual wild Pals — `BP_AIResponsePreset_Escape_to_Battle_C`
   (ordinary wild monsters), `BP_AIResponsePreset_friendly_C` (Lamball/
   Chikipi-type), `BP_AIResponsePreset_VillageNPC_C` (human NPCs) —
   `UPalAIResponsePreset` is real and populated exactly as hypothesized.
   BUT the `SelectResponseBySenses` hook used to get this fired 6706
   times in about a second (it's a per-tick sensing function, not a rare
   event like everything else this project has hooked) and caused a real
   frame-rate drop for Dragón — now disabled in `OtomoWatch.lua` (see
   hook-points.md's thirty-third pass). Re-enable only with a dedup/
   sampling guard, never logging every call unthrottled.
2. Where exactly is the "is this Pal owned by the interacting player" gate
   checked before the pet/feed prompt is offered?

   **STRONG CANDIDATE FOUND (2026-09-02, thirty-second pass):**
   `bool TargetIsPlayerOrPlayersOtomoPal(AActor* TargetCharacter)` on
   `class UPalBattleManager : public UPalWorldSubsystem`, reachable via
   the already-trusted `UPalUtility::GetBattleManager(WorldContextObject)`.
   A ready-made, real "is this the player or their own Otomo" check —
   not yet confirmed live, but a two-hop, fully safe call chain (global
   static → subsystem → bool function), added as a read-only watch.

   **NEGATIVE RESULT (2026-09-02, thirty-fifth pass):** tested during a
   real pet/feed of two different owned, active Otomo Pals (Petallia,
   Bristla) — zero hits. Not called by the pet/feed interaction path;
   more likely used in combat/damage decision-making instead.

   **POSITIVE RESULT, SUBSTANTIALLY ANSWERED (2026-09-02, thirty-sixth
   pass):** confirmed firing repeatedly during real combat — an active
   Otomo (Petallia) fighting several wild Pals, and again the instant a
   trust-lost wild Pal flipped to hostile. Targets seen include the
   player, the attacking Otomo herself, and the wild Pals being fought.
   This settles it as a real combat/targeting check (likely "does this
   actor count as friendly for damage/aggro purposes"), not part of the
   pet/feed gate — the original question (interaction-prompt gating) is
   probably a different, still-unfound check, but this function itself is
   now confirmed real and understood. See hook-points.md's thirty-sixth
   pass for the full log evidence.
3. Is there an existing per-instance "trust" or "friendship" field already
   on the Pal actor/save data (the "Configurable Trust On Capture" mod
   implies one exists for post-capture Pals) that we can extend to
   pre-capture Pals, instead of building a fully separate value?
4. What's the cleanest existing UFunction to call for a sphere-less,
   guaranteed capture (per the precedent mods) — can we call it directly, or
   do we need to replicate what those mods do?

   **New lead (2026-09-01, twentieth pass):** `void
   CapturePal_ServerInternal(class APalPlayerCharacter* Player);` belongs to
   a real class, `class APalCapturedCage : public AActor` — a dedicated
   capture-cage actor, found incidentally while researching Q6. Not yet
   investigated for this question specifically (which class instantiates
   it, whether it can target an already-bonded Pal directly) — still open,
   noted here so it isn't lost. See hook-points.md's Question 4 section for
   the fuller list of untested candidate functions found earlier
   (`JudgePalCapture`, `CaptureNewMonster`, `PalCaptureSuccess`, etc.).

   **CONFIRMED LIVE, strongest lead so far (2026-09-02, twenty-eighth/
   twenty-ninth passes):** `UPalUtility::PalCaptureSuccess(APalPlayerCharacter*
   AttackerPlayer, APalCharacter* Monster)` — a global static on the same
   trusted `UPalUtility` class as `GetIndividualCharacterHandleByActor` —
   fires on every real capture, confirmed across a genuine live test, with
   the correct player and captured-Pal actor as arguments. It's a native
   hook, so our observation is a POST-hook (fires after the real function
   already ran); `SpawnOtomo` fires in the very same instant right after,
   suggesting `PalCaptureSuccess` itself triggers the whole post-capture
   hand-off, not just a notification. `APalCaptureJudgeObject::
   OnCaptureSuccess` — the other twenty-eighth-pass candidate — registered
   fine but never fired across three real captures; ruled out as part of
   the normal field-capture flow (its sibling functions, `ChallengeCapture`
   etc., now read as a separate capture-test/arena class). `AddOtomoHandleToFreeSlot`
   still never fired for the player across three genuine captures in a
   row — a consistent negative result now, reinforcing the twenty-seventh
   pass's hypothesis that party-slot assignment is an unhookable native
   field write, quite possibly happening inside `PalCaptureSuccess` itself.
   **This makes `PalCaptureSuccess` the single strongest real candidate
   found so far for a clean, existing, sphere-less capture call** — but it
   has only ever been observed being invoked by the real sphere-throw
   pipeline, so it's unknown what state that pipeline sets up beforehand
   that this function might assume already exists. Calling it out of
   context on a wild Pal that never went through an actual sphere throw is
   a new, different category of risk from anything tried in this project
   so far (a live call into native capture-completion logic, not a field
   read or a hook) and is explicitly NOT something to try yet — needs more
   groundwork (more real captures to confirm reliability, and an attempt
   to find whatever calls `PalCaptureSuccess` to see what precedes it)
   before Dragón's standing "don't try it until we're sure" bar is met.

   **NEW, POSSIBLY BETTER LEAD (2026-09-02, thirtieth pass, Dragón's own
   idea):** enemy camps/settlements sometimes hold a captive Pal in a
   small cage — opening it hands the Pal straight to the player, no
   Palsphere at all. That's a real, existing, dev-built sphere-less
   capture path already in the game, and a better precedent to study than
   calling `PalCaptureSuccess` cold. Found the real class:
   `class APalCapturedCage : public AActor` (native, always loaded) —
   `SpawnedPalHandle` is already a resolved handle before the player ever
   interacts (no sphere-throw physics/chance roll involved at all), and
   `CapturePal_ServerInternal(APalPlayerCharacter* Player)` is the
   function that (very likely) hands that Pal to the player when the cage
   door is opened. This shape — a Pal that already has a handle, handed
   over by one call, no sphere mechanics — is a much closer match to what
   this mod actually wants ("a wild Pal that earned enough trust just
   joins") than trying to reproduce a sphere capture. All of it added as
   new read-only watches; not yet tested live — waiting on Dragón finding
   a real cage and opening it normally.

   **CONFIRMED LIVE (2026-09-02, thirty-first pass) — best result so
   far:** Dragón rescued a caged Pal (Bristla) from a settlement.
   `APalCapturedCage::CapturePal_ServerInternal(APalPlayerCharacter*
   Player)` fired exactly as hoped — real player, real already-live
   handle+actor for the Pal, no sphere involved, Pal joined the party
   immediately (second slot). This is now a directly-observed, working,
   vanilla example of "player + an existing wild Pal handle → straight
   into the party," which is exactly the shape this project's sphere-less
   capture design needs — a stronger, cleaner confirmation than
   `PalCaptureSuccess` (twenty-ninth pass) since there's no sphere-specific
   ambiguity here at all. `AddOtomoHandleToFreeSlot` stayed silent for
   this too — third separate real pathway now where it never fires,
   effectively settling that it isn't the real "join party" mechanism for
   players. Still not something to call blind: only ever observed
   triggered by the cage's own internal flow, on a Pal the cage itself
   created — next step is understanding what (if anything) it assumes
   about the Pal/context before considering a real test.

   **STATIC RESEARCH LIKELY AT ITS CEILING (2026-09-02, thirty-seventh
   pass):** mapped the surrounding party/slot classes in full
   (`UPalOtomoHolderComponentBase`, `UPalPlayerPartyPalHolder`,
   `UPalIndividualCharacterContainer`/`UPalIndividualCharacterSlot`) —
   none expose a UFUNCTION that looks like "add this handle to my
   party." Most likely explanation: the real assignment is a plain,
   non-reflected C++ call that can never appear in a header dump or be
   hooked from Lua, no matter how much more is read. Two more read-only
   watches added (`OnUpdateSlot`, `FindEmptySlot`) in case they catch the
   moment indirectly, but the next real move on this question is very
   likely the field-write experiment itself (write a wild Pal's real
   handle into an existing cage's `SpawnedPalHandle`, then call
   `CapturePal_ServerInternal`) rather than more static reading.

   **THE EXPERIMENT, IMPLEMENTED (2026-09-02, thirty-eighth pass):**
   rather than the cage/field-write route, `Capture.TryDirectCapture`
   calls the simpler, more-proven candidate directly:
   `UPalUtility.PalCaptureSuccess(Player, Monster)` on a wild Pal that
   never went through a real sphere throw. Bound to F11 in
   Interaction.lua, deliberately isolated from normal play (own key, own
   function, not wired into `OnTrustMaxed` yet). Not yet tested live —
   this is the mod's first genuinely experimental call (a hard native
   crash can't be ruled out from Lua), so it's being done deliberately,
   once, with the player's awareness, not silently. Result pending.

   **ANSWERED, CONFIRMED LIVE (2026-09-02, thirty-ninth pass):** Dragón
   tested F11 on three different wild Pals (Sheepball, Cattiva, and a
   Mammorest — a large, boss-tier species) in one session. All three
   joined his real party — no sphere, no crash, confirmed by directly
   checking the party screen. `UPalUtility.PalCaptureSuccess(Player,
   Monster)` is a real, working, sphere-less capture call. `Capture.
   OnTrustMaxed` now calls it for real instead of logging a stub message
   — DESIGN.md §3.5 is implemented. Only known gap: no capture VFX/light
   effect plays (cosmetic only, low priority). This closes the project's
   last major open research question.
5. What identifies a Pal instance stably enough to store custom state
   against it across frames (and ideally across save/load) — object pointer
   (frame-local only), a persistent GUID field, or something else?
6. Which existing behavior-tree branch does an *owned* Pal use to follow and
   assist in combat, and can it be entered by a Pal that isn't in the
   player's party data?

   **PARTIALLY ANSWERED (2026-09-01, nineteenth pass, via FModel):** the
   real class is `BP_MonsterAIController_Otomo` (extends
   `BP_MonsterAIControllerBase` → native `PalAIController`, the same base
   every wild Pal's controller already has). It adds `PathFollowingComponent`
   (a `UPalFollowingComponent`, itself a bare `UPathFollowingComponent`
   subclass — standard engine path-following, same category this mod's own
   `PalMoveToLocation` approximation already uses) and `CombatModuleClass`
   set to `PalAICombatModule_Otomo` (also bare, inherits real combat-assist
   functions from `UPalAICombatModule`: `AIMoveToTargetActor(Target)`,
   `GetTargetActor()`, `IsBattleMode()`). Also has a real `OtomoSlotIndex`
   (int) and `IsReturningFromFarFlag`/`FollowInterpolatedPos`. FModel's
   reference search found zero Blueprint-level references to this class
   anywhere — controller-class assignment is native, non-reflected C++.

   **ADVANCED (2026-09-02, thirty-second pass, via a downloaded mod's
   asset strings):** found the real, native, always-loaded sensing side
   of this question — `class UPalAISensorComponent : public
   UActorComponent`, with `RequestSightCheckAsync(bIncludePlayer,
   bIncludeAliveNPC, bIncludeEdibleDeadNPC, RangeRate, bIgnoreOtomo)` and
   `SightCheckAllAliveNPC(..., ignoreOtomo)` — both take a real
   `bIgnoreOtomo` flag, direct confirmation that "don't treat Otomo Pals
   as threats" is already a first-class, built-in option in the game's
   own sensing system, not something to fake. Also `CheckCombatableByLevelDiff
   (TargetActor)`, a separate real eligibility gate. Bonus, not directly
   on point but relevant to the earlier Daedream/Flopie/Petallia
   multi-follow observation: `class UPalSquad : public UObject` with
   `GetSquad()`/`GetIsSquadBehaviour()`/`GetLeader()`/`IsLeader()`/
   `FollowLeader` — wild Pals have a real, separate leader/follower squad
   system for group behavior, a possible alternate model for "how does a
   non-primary Pal coordinate/follow" independent of the Otomo system.
   None of this is hooked/tested live yet beyond `SelectResponseBySenses`
   (Question 1) — next step is watching these fire on a real wild Pal.

   **UPDATED (2026-09-01, twentieth pass, web research + native SDK):**
   in direct response to "what if it's on the player/save side, not the
   Pal?" — it is. `struct FPalWorldPlayerSaveData` has a real field
   `FPalContainerId OtomoCharacterContainerId;`, and a real native class
   `UPalOtomoHolderComponentBase` (obtained via `GetOtomoHolder(APlayerState*)`)
   exposes what looks like the actual intended game API for this, including
   `bool AddOtomoHandleToFreeSlot(UPalIndividualCharacterHandle* Handle);`
   and `bool ActivateCurrentOtomo(FTransform)` /
   `void ActivatePalByHandle(const UPalIndividualCharacterHandle* Handle,
   const FVector& Location, const FRotator& Rotation, bool
   bKeepActigvateOtomoId);`. Independent confirmation from
   `cheahjs/palworld-save-tools` (GitHub, `character_container.py`): party/
   base/box membership is a save-data container+slot record
   (`{player_uid, instance_id, permission_tribe_id}`), not a live-actor
   property — matching this native finding exactly. This is a meaningfully
   more promising real path than the manual unpossess/spawn-controller/
   possess plan above, since it would let the game's own tested code do the
   controller assignment instead of us guessing at it. **Still unanswered:**
   how to obtain a `UPalIndividualCharacterHandle*` for a never-captured
   wild Pal (every wild-Pal angle used so far returns a
   `UPalIndividualCharacterParameter`, not a handle), and whether
   `ActivatePalByHandle`/`ActivateCurrentOtomo` spawns a fresh actor
   (meaning the original wild actor would need to be despawned first to
   avoid a duplicate) or can take over an already-spawned one. No public
   mod was found that solves this end-to-end.

   **GAP CLOSED (2026-09-01, twenty-first pass):** `class UPalUtility :
   public UBlueprintFunctionLibrary` (the same global-static-helper class
   already used for `GetMinFriendshipRank()` etc.) has
   `GetIndividualCharacterHandleByActor(AActor*)` — the exact conversion
   function, callable directly on any live Pal actor with no manager
   lookup needed — plus `GetOtomoHolderComponent(WorldContextObject)`, a
   simpler general-purpose way to reach the player's
   `UPalOtomoHolderComponentBase` than the previously-found
   `GetOtomoHolder(PlayerState)`, which turned out to belong to an
   Arena/PvP-test-only class. Full candidate pipeline is now sketched
   end-to-end (see hook-points.md's twenty-first pass for the exact call
   sequence and reasoning) — still NOT live-tested. Also found real,
   native confirmation of a second, related mechanic Dragón pointed out
   independently (Pals like Daedream/Dazzi/Flopie following passively
   without being the main active Pal): `class UPalPlayerPartyPalHolder`
   has real `FirstOtomoPal`/`SecondOtomoPal` handle fields and a
   `ChangePalSlot(bool SecondPal)` function — the game natively supports
   two simultaneously-active Otomo Pals, not just one, which independently
   corroborates that this whole handle-based system is the real, central
   mechanism (not a side path) for "which Pals are actively linked to the
   player right now." Still a new, heavier risk category (creating/
   reassigning live actors, first TMap/handle work) — next step is the
   isolated, heavily-logged live test described in hook-points.md, not yet
   attempted, pending Dragón's go-ahead.

   **CONFIRMED LIVE (2026-09-02, twenty-fifth pass):** watched the real
   game do it. The everyday "swap active party Pal" flow does NOT use
   `ActivatePalByHandle`/`ActivateCurrentOtomo` at all (those never fired,
   across two full test sessions) — it's entirely a different, player-
   specific Blueprint class, `UBP_OtomoPalHolderComponent_C`, calling:
   ```
   holder:InactivateCurrentOtomo()
   holder:ActivateOtomo(newSlotID, transform, &isSuccess)
   ```
   confirmed identically across 4 real swaps. `SpawnOtomo(SlotId)` also
   fires often, on a simpler slot-index-only signature — twenty-fifth
   pass first read it as just UI-preview rendering, but Dragón's own
   description of what was actually on screen (twenty-sixth pass)
   corrects that: Pals with an auto-follow partner skill (Daedream,
   Flopie) visibly despawn/respawn as SECONDARY followers on every single
   swap, not just the slot being swapped to — `SpawnOtomo` is very likely
   the real "make this party slot's Pal exist as a world actor" call,
   covering both the primary swap cascade and secondary/follower Pals,
   not a preview. That makes it a real second candidate (simpler than
   `ActivateOtomo`) for getting a wild Pal's handle to appear and follow
   as a secondary, not just as the primary Otomo. Still unconfirmed: what
   fires when a Pal first JOINS the party (a real capture) —
   `AddOtomoHandleToFreeSlot` has only ever been observed on an NPC's own
   holder, never the player's, across everything tried so far (swapping,
   petting, feeding, opening the Palbox). That's the one remaining gap
   before a wild-Pal experiment is justified — see hook-points.md's
   twenty-fifth/twenty-sixth passes for the exact plan (watch a real
   capture happen next).

   **NARROWED FURTHER, still open (2026-09-02, twenty-seventh/twenty-eighth
   passes):** Dragón ran the real capture test — two genuine wild Lamball
   captures, `AddOtomoHandleToFreeSlot` still never fired for the player
   either time, while `ActivateOtomo`/`SpawnOtomo` worked cleanly on the
   freshly-captured Pal's handle within seconds of capture (reassuring:
   activation doesn't care how "new" the party membership is). Digging
   into why: `UPalIndividualCharacterContainer` (the real party-roster
   class) has only plain getters (`FindEmptySlot`, `FindByHandle`,
   `Get`, `Num`) — no `Add`/`Insert` function at all — and
   `UPalIndividualCharacterSlot` has a plain, setter-less
   `UPalIndividualCharacterHandle* Handle` field. Best current hypothesis:
   the real "join the party" step is an unhookable native field write
   (`slot.Handle = newHandle`), not a UFunction — meaning the candidate
   sequence shifts to "call `FindEmptySlot()` (safe getter) → write
   `.Handle` directly (a field write, not a function call — same safest
   category as `ActivatedHandle`'s own read) → `SpawnOtomo`/`ActivateOtomo`
   on that slot" instead of relying on any capture-time hook. In parallel,
   answering a fair methodology question from Dragón (log everything
   instead of guessing function names?) by grepping the full header dump
   broadly rather than narrowly surfaced two better-targeted candidates
   for the actual moment of capture success itself: `UPalUtility::
   PalCaptureSuccess(AttackerPlayer, Monster)` (global static, same class
   as the already-trusted `GetIndividualCharacterHandleByActor`) and
   `APalCaptureJudgeObject::OnCaptureSuccess(Character, Result)` (the
   capture sphere's own success confirmation). Both added as new read-only
   watches (`OtomoWatch.lua`) — not yet tested live. If either fires and
   reveals what runs right after, that would finally show the real
   capture→party-slot link directly instead of via a field-write
   hypothesis. Until one real capture is observed going through, this
   answer stays unconfirmed and no wild-Pal experiment is justified.

Each answer goes into `docs/hook-points.md` as we confirm it, with the
source (FModel dump, UE4SS Live View, or a specific existing mod's approach)
noted so we're not re-deriving the same thing twice.

## 9. Future considerations — keywords flagged by Dragón (2026-09-03, not yet researched)

Noted for later phases, not yet investigated: **prism**, **heart**, **emote**, **happy**. Likely relevant to the game's own existing "Pal is happy/bonding" visual feedback (Palworld already shows heart particles/emotes on Pals in some contexts) — worth checking, before building more custom UI, whether any of these map to a real, already-shipped native signal or asset (e.g. a happiness emote state, a heart particle effect, or a "prism"-named asset/material) that PalBonds could trigger or reuse instead of/alongside the custom trust bar. No research done yet — this is a placeholder to make sure these aren't lost before the indicator work wraps up.

**Partial lead found (2026-09-03, sixty-fifth pass):** extracting `RemoteAccessEverything`'s compiled `.pak` for unrelated reasons turned up a real, complete Emote system — `BP_Action_Emote_Base_C` plus nine numbered variants (`BP_Action_Emote_0_C` through `BP_Action_Emote_8_C`), triggered via `CreateEmoteMenu`/`PLAYER_ACTION_EMOTE`. This directly matches the "emote"/"happy" keyword — a real, existing action class family PalBonds could potentially trigger on a bonding Pal as a "happy" signal instead of/alongside the trust bar. "Heart" is still completely unresearched.

**"Prism" resolved (2026-09-03, sixty-seventh pass):** Dragón's own hypothesis — that "prism" names the capture light-beam animation — was investigated with a real, live "spy" (hooks), not just static reading, per Dragón's explicit request. `grep -rl "Prism" CXXHeaderDump/` found exactly three hits: `BP_CapturePrism.hpp` (`ABP_CapturePrism_C`, the Palsphere throw weapon itself — real fields `SK_Weapon_PalSphere_001`/`CaptureSphereType`), `BP_CapturePrismBullet.hpp` (`ABP_CapturePrismBullet_C`, the thrown projectile — real field `CaptureTarget`, function `SpawnCaptureObject(FGuid, AActor*)`), and `Engine.hpp`'s `ConstraintLimitMaterialPrismatic` (a physics constraint property, unrelated — ruled out). So "Prism" is this game's own internal/legacy name for the Palsphere weapon-and-projectile pair, not a distinct light-beam effect by itself — though `SpawnCaptureObject` remains a strong candidate for where a capture-success visual gets triggered. Read-only hooks were registered on both classes' throw/hit/capture functions (`OnThrowInternal`, `GetCaptureLevel`, `OnEndShootAnimation`, `On Throw`, `DecrementBullet`, `SpawnCaptureObject`, `OnHitToActor`, `IsDestroy`, the projectile-bounce delegate) to confirm the real firing order against an actual capture. **Not yet confirmed live** — needs Dragón to attempt a real capture with the mod running; see `Indicator.lua`'s `register_prism_hooks_once` and `docs/hook-points.md`'s sixty-seventh pass entry.

**Sixty-first pass RESULT: less lag (the cap works — all 5 rounds burned
within the same second), but still stuck at 50%.** The correct declaring
class name, hardcoded, STILL failed with the identical "no UFunction with
the specified name was found" error — a real signal that short-name
`RegisterHook` resolution likely just doesn't work reliably for Blueprint
classes here at all, regardless of which class name is used.

**Sixty-second pass:** reaches the same class object a different way —
`FindAllOf("WidgetBlueprintGeneratedClass")` (the same kind of call this
project's other class discovery already uses successfully) instead of
`gaugeWidget:GetClass()` — then calls `GetPathName()` on that properly-
wrapped object to get the real, full `/Game/...` asset path, tried as the
first hook candidate. The earlier short-name attempts remain as fallbacks.
Needs a live test: check for `DIAG-CLASSFIND` and `DIAG-HOOK ... OK` in the
log, and whether the bar starts at a real value and moves.

**Sixty-second pass RESULT: the class search itself found nothing.**
`FindAllOf("WidgetBlueprintGeneratedClass")` returned no results, so the
full-path attempt never had a path to try. Combined with three earlier
failed hook-path formats, that's four distinct dead ends — strong enough
signal that `RegisterHook`'s short-name resolution just doesn't work for
Blueprint functions in this build, not one more wrong guess to fix.

**Sixty-third pass: pivoting away from hooking entirely.** Instead of
reading or intercepting the game's internal widget↔Pal link, match a
gauge to a Pal from the outside by SCREEN POSITION: every gauge widget's
own `CanvasPanelSlot` gives a screen position; every Pal's world location
converts to the same kind of coordinate via the real, confirmed
`APlayerController::ProjectWorldLocationToScreen`. This pass writes no
matching logic yet — it only probes several Lua calling conventions for
that function's output and logs both sides (Pal projections, gauge slot
positions) side by side, so the next test's numbers confirm whether the
coordinate spaces actually line up before any matching code is built on
an unverified assumption. Needs a live test: check the log for
`DIAG-PROJECT` and `DIAG-POSMATCH`.

**Sixty-third pass RESULT + Sixty-fourth pass: cracked open "Pal Analyzer"
for real confirmation.** Dragón pushed back on an earlier claim that this
reference mod (a compiled Blueprint `.pak`, different format than this
project's UE4SS Lua) couldn't be opened. It can — extracted read-only with
a standard open-source pak tool, no encryption on this mod — and its
readable Blueprint function/property names confirmed two things: (1) it
identifies its target Pal via a camera-forward trace (a different,
single-target technique than ours), then reads stats via the same
actor→parameter route Trust.lua/Interaction.lua already use — independent
confirmation that route is right; (2) it places UI via
`GameplayStatics.ProjectWorldToScreen` — a static Blueprint-library call,
not an instance method — using the exact call shape
(`UEHelpers.GetGameplayStatics():ProjectWorldToScreen(...)`) this project's
own bundled UE4SS install already demonstrates working
(`Mods/SplitScreenMod/Scripts/main.lua`). Switched the screen-projection
probe to this validated call instead of a guess. Needs a live test: check
for `DIAG-PROJECT`/`DIAG-POSMATCH` and whether the numbers line up.

**Sixty-fourth pass RESULT + Sixty-fifth pass: the real fix was already in
this project's own reference material.** Dragón asked for a genuinely
thorough re-read of every reference mod, including the three shipped as
compiled `.pak` files rather than UE4SS Lua source — extracted all of them
read-only (`u4pak` for an older pak version, `repak` for two on a newer
version that tool didn't support). Re-reading `VisiblePalCaptureCounter`'s
full source (not just the earlier narrow search) found it successfully
hooks `BindFromHandle` with the literal path
`/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:
BindFromHandle` — the real format for a Blueprint hook (package-path-dot-
ClassName:Function), which every one of the sixtieth-through-sixty-second
passes' candidates was missing entirely, not just guessing slightly wrong.
Also confirmed (live, in a shipped mod) that a hook-captured hard-pointer
handle supports `TryGetIndividualParameter()` directly, and that gauge
widgets are pooled/reused (via its `Unbind` hook), which this project
hadn't accounted for. Added the real path as the first hook candidate plus
an `Unbind` hook to clear stale handles on reuse. Needs a live test: check
for `DIAG-HOOK ... OK` and whether the bar starts at a real value and
moves.

**Other findings from the same reference-mod survey, not yet acted on:**
`PassiveWildPals` (overrides `BP_AIAction_WildLife`) revealed a complete,
native leader/follower squad system (`PalSquad`, `GetLeader`,
`FollowLeader`, `IssueAsyncFollowMove`) directly relevant to the Follow &
protect subsystem below. `RemoteAccessEverything` (overrides
`WBP_PlayerRadialMenu`) revealed the real Otomo instruction/order system
(`RequestSetOtomoOrder`, `EPalOtomoPalOrderType`, `PAL_INSTRUCTION_ASSIST`/
`_ATTACK`/`_CARE`/`_ESCAPE`/`_FEED`) and a real Emote system (`BP_Action_
Emote_Base_C` + 9 variants) — see updates to sections 3.4 and 9 below.

**Sixty-fifth pass RESULT: fully confirmed working, live.** Dragón tested it
directly — a wild Pal's trust bar starts at 0%, visibly fills while petting,
keeps rising passively afterward, and tracks toward the real capture
threshold. This closes out Phase 6's on-screen trust indicator as
functionally complete, pending only the visual-polish follow-up below.

**Sixty-sixth pass (2026-09-03): trust bar color gradient.** Dragón asked to
stylize the bar (it "looks so simple compared to the healthbar"),
specifically a white-pinkish (empty) → red (full) color gradient. Checked
what `UProgressBar` actually exposes to Lua first: `CXXHeaderDump/UMG.hpp`
only declares `SetPercent`, `SetIsMarquee`, and `SetFillColorAndOpacity` as
callable — the brush/border imagery lives inside `WidgetStyle`
(`FProgressBarStyle`/`FSlateBrush`), not something safe to build from Lua.
So the deliverable "more design" here is the color gradient: added
`compute_trust_bar_color(ratio)` (plain per-channel linear interpolation,
white-pink at 0 to red at 1), wired into both bar creation and every
per-tick refresh, replacing the old static magenta placeholder. Bar now
also starts at 0% instead of the old 50% guess.

**Sixty-seventh pass (2026-09-03): "prism" spy — see section 9 above for
the full writeup and conclusion.** Read-only hooks registered on
`BP_CapturePrism_C`/`BP_CapturePrismBullet_C`'s throw/hit/capture lifecycle
functions. Needs a live capture test to confirm the real firing order.

**Thirty-seventh pass (OtomoWatch.lua, 2026-09-03): the "prism"/beam spy, round 2.** Dragón proposed a sharper test: free a caged Pal at a settlement first (no sphere at all), then capture one with a sphere, and compare. If the same beam shows for both, it can't be Indicator.lua's `BP_CapturePrism`/`BP_CapturePrismBullet` (sphere-weapon-specific) — it has to be something shared by both paths. A broad keyword grep across the whole header dump found the strongest new candidate: `ABP_ReturnPalEffect_C : AActor`, a real Niagara-VFX actor that moves a Pal from a start location to the player over time — structurally exactly "a beam showing a Pal becoming yours," not sphere-specific. Also hooked: `ABP_PalCaptureJudgeObject_C` (the Blueprint subclass of the native judge object OtomoWatch already watches, which never fired — trying the real instantiated subclass directly), `BP_ActionUnlockCagePalLock_C` (the literal cage-unlock interaction, a timing anchor), and `BP_CaptureWire_C` (another real capture-related actor, purpose unconfirmed). All resolved via `FindAllOf("BlueprintGeneratedClass")` (same technique as Indicator.lua's sixty-seventh pass) combined with OtomoWatch's existing retry-until-loaded pattern. **Not yet confirmed** — needs the live test described above. See `docs/hook-points.md`'s thirty-seventh pass entry and `OtomoWatch.lua`.

**Sixty-eighth through seventieth pass (2026-09-03): real lag diagnosis, gold color, fixed the dead FindAllOf technique.** Dragón tested pass 66/67 live (freed a caged Dazzi, captured a Herbil by pets alone, captured a Clovee with a sphere) and reported the gradient "didn't convince" and the game felt "kind of laggy," guessing the new prism spies. Checked the log instead of assuming: the spies logged almost nothing and failed instantly — not the cause. The real, measured cause was 507 `[DIAG-DUMP]` lines in an 8-second burst, from leftover fully-answered property dumps (forty-seventh/fifty-first/fifty-third passes) that still fully re-ran every session — each a synchronous flushed disk write by Logger.lua's own crash-safety design. Stripped those obsolete dumps out. Switched the trust bar to a gold gradient (dim bronze empty, bright gold full) per Dragón's request. Also properly fixed (not just worked around) the FindAllOf-meta-class technique that made every prism-spy hook fail — replaced with FindAllOf(concrete class name) + instance:GetClass():GetPathName(), the same proven shape used elsewhere in this project, with unbounded retry (cheap, targeted calls) since these actors are event-spawned, not persistent. Not yet confirmed live — needs a repeat test. See `docs/hook-points.md`'s matching entry, `Indicator.lua`, and `OtomoWatch.lua`.

**Seventy-first/seventy-second pass (2026-09-03): console spam bug, solid gold, giving up on RegisterHook for the prism/beam classes.** Dragón's test caught a real, ongoing console-spam bug: the seventieth pass's path-resolution fix hit the same `TrivialObject` error as before (proving `instance:GetClass():GetPathName()` doesn't work in this build regardless of how the instance is obtained), and its failure log wasn't rate-limited, so it spammed every ~2s. That's the third distinct Lua-reflection technique now confirmed dead for resolving a Blueprint class's real asset path (also: `FindAllOf("WidgetBlueprintGeneratedClass")` and `FindAllOf("BlueprintGeneratedClass")`); a web search for a published literal path also came up empty. Conclusion: RegisterHook isn't viable for `BP_CapturePrism`/`BP_CapturePrismBullet`/`ABP_ReturnPalEffect_C`/etc. in this build without an external reference no one has found yet. Replaced with plain existence/field polling off live instances (no path or `:GetClass()` needed) in both `Indicator.lua` and `OtomoWatch.lua` — quieter, and actually able to observe something. Also switched the trust bar to a single flat gold color (no gradient) per Dragón's follow-up request. Not yet confirmed live for the prism/beam question; the cage-release comparison test is still pending a low-enough-level settlement. See `docs/hook-points.md`'s matching entry.

**NOTE (2026-09-03, superseded by seventy-third pass):** the "RegisterHook isn't viable without an external reference no one has found" conclusion above no longer holds — the seventy-third pass found a real, reliable reference: this project's own actual game `.pak` file, read directly with `repak`. The polling-based fallback above still works and is still deployed, but a proper `RegisterHook`-based re-implementation for the prism/beam classes (using real paths like `/Game/Pal/Blueprint/Weapon/BP_CapturePrism.BP_CapturePrism_C:...`) is now very likely achievable and is a pending follow-up, not yet done — see `docs/hook-points.md`'s seventy-third pass entry.

**Seventy-third pass (2026-09-03): the real radial-menu functions, via the project's own game pak.** See the update to section 3.2 above and `docs/hook-points.md`'s full seventy-third pass entry for the complete writeup (repak discovery, real function names, the Otomo-scoping caveat, and the new watch hooks in `Interaction.lua`).

**Seventy-fourth pass (2026-09-03):** live test corrected the Otomo-only worry (the wheel also works aimed at an owned, non-active Pal — see the section 3.2 update above) and found all 8 new Blueprint hooks failed to register, likely from reading Unreal's cosmetic display names instead of the real FNames. Fixed with no-space name candidates plus a bounded retry loop. See `docs/hook-points.md`'s seventy-fourth pass.

**Seventy-fifth pass (2026-09-03): InputSpy.lua.** Dragón asked to see which function/hook his own key presses and clicks trigger, to help pin down the real radial-menu functions faster. No generic native "any input" function exists to hook, so a new temporary module binds every valid key/mouse button (the full list UE4SS accepts, from the bundled Keybinds mod) to one shared logger — every press now shows up as its own line, next to whatever hooks fire around the same moment. First time this project binds keys the game itself actively uses (not just unused F-keys), flagged as a new risk category to watch on first use, though `RegisterKeyBind` is understood to be additive and non-blocking. See `docs/hook-points.md`'s seventy-fifth pass for the full writeup.

**Seventy-sixth pass (2026-09-03): real hooks confirmed firing, and a two-path discovery.** `InputSpy` plus the corrected radial-menu hooks (seventy-fourth pass) delivered a full, working, confirmed pipeline for the "4 with no aim target = act on my active Otomo" case: `Can Open Player Action Menu` → `Create` → `Open`, then on click `On Decided Instruction Care`/`OnDecidedInstruction_Feed` + `OnDecidedPlayerActionMenu(index)` (0=Feed, 1=Care). But aiming "4" AT a specific Pal (his base Tanzee) fired NONE of these six — confirmed via the native MENU-WATCH hooks that this case goes through the interact-sphere system instead, a genuinely different, still-unidentified code path. Added 12 more candidate hooks targeting that gap (`SelectMapObjectId`/"Select Page by Map Object" is the strongest lead — "MapObject" is Palworld's internal term for any interactable world object, Pals included). See `docs/hook-points.md`'s seventy-sixth pass. Needs one more live test, aimed specifically at a Pal.

**Seventy-seventh pass (2026-09-03): the aimed-Pal case is conclusively a different system — found and hooked.** Five real "4" presses aimed at the Tanzee produced zero hits across all 18 `WBP_PlayerRadialMenu_C` candidates tried so far — conclusive, not a naming miss. Went back to the real game pak and found `WBP_PalInteractiveObjectIndicatorCanvas`/`WBP_PalInteractiveObjectIndicatorUI` — the real per-object interact-indicator system, resolving a question open since the **twentieth pass** ("find the Blueprint that implements `GetIndicatorInfo`"). Added hooks on both, including the promising `OnUpdateTargetInteractiveObject` delegate and the Otomo-specific `ShowOtomoIndicator(s)` pair. See `docs/hook-points.md`'s seventy-seventh pass. Needs one more live test, same setup (aim at a Pal, press "4").

**Seventy-eighth pass (2026-09-03): Dragón found the real third menu family — `WBP_WorkerRadialMenu`.** Sent screenshots of `WBP_WorkerRadialMenu`/`_Overlay`/`Content` under `WorkerRadialMenu/`, noting base Pals are called "workers" in-game — a strong, and on inspection confirmed, lead for the still-unidentified aimed-Pal code path. Extracted and read via `repak`/`strings`: `WBP_WorkerRadialMenuContent`'s string table literally contains `MsgID_Pet` and `MsgID_Feed` (plus `MsgID_MoveToBox`/`MsgID_MoveToOtomo`/`MsgID_ShowStatus`), and a dedicated `EPalWorkerRadialMenuResult` enum — a cleaner selection signal than the Player menu's raw integer index. Added hooks on both real classes (`WBP_WorkerRadialMenu_Overlay_C`: `Open`/`Close`/`OnSetup`/`OnSelectedMenu`/`OnAnyUIPushed`/`OnPushedStackableUI`/etc.; `WBP_WorkerRadialMenu_C`: `Construct`/`CreateContent`/`SetupContents`/`OnSelectedMenu`/`OnDecideIndex_forBP`/etc.), tagged `[WORKER-WATCH]`, reusing the seventy-seventh pass's `make_hook_round_runner` factory. See `docs/hook-points.md`'s seventy-eighth pass. Needs a live test: aim "4" at a base/worker Pal and check for `[WORKER-WATCH]` lines.

**Seventy-ninth pass (2026-09-03): checked a burst of failure lines Dragón saw, trimmed confirmed-dead candidates.** He quit a session after only 25 seconds; every class's hooks failed that run, including six long-proven `RADIAL-WATCH` ones — meaning the session ended before any radial-menu widget class had loaded (probably still at the main menu), not new evidence against the Worker menu. Separately, removed four `WBP_PlayerRadialMenu_C` candidates conclusively proven dead in an earlier full session (`SelectMapObjectId`, `SelectPageByMapObject`, `SelectPageAndIndex`, `IsOpened` — RegisterHook failed all 8 rounds while sibling candidates on the same class succeeded), and simplified two confirmed-real entries (`CanOpenPlayerActionMenu`, `OnDecidedInstructionCare`) down to their one real spaced form instead of also trying an always-failing guess. Left `ChangeMode`/`DecideMenuAction` and the still-ambiguous dual-candidate lifecycle hooks alone — no solid evidence either way, and the raw log that could resolve it is gone (`Logger.lua` truncates per session). See `docs/hook-points.md`'s seventy-ninth pass.

**Eightieth pass (2026-09-03): WBP_WorkerRadialMenu confirmed live with a full selection-index mapping, and the real lag source found and fixed.** A real 7-action test (pet/feed/view-stats/add-to-party on his Tanzee, pet again, pet/feed on his Petallia) produced clean `OnSetup`/`OnClosed` pairs (exactly 7 each) and, by cross-referencing `OnSelectedMenu_Internal`/`OnSelectedEvent` index pairs against play order, recovered the real selection mapping: **(4,5)=Pet, (3,1)=Feed, (0,2)=ShowStatus, (1,4)=AddToParty** (MoveToBox, the one unexercised option, is presumably the remaining index by elimination) — a much cleaner signal than the Player-menu's integer index ever gave. Separately, found and fixed the actual lag: `UpdateInteractTargetName` fired 2375 times in ~137 seconds with useless `nil` args — a per-tick UI refresh, not a discrete event, same bug class as the ninth pass's `find_targeted_pal` spam. Removed it entirely; `OnUpdateTargetInteractiveObject` already covers the same ground at ~66 fires/session with a real, resolvable target (confirmed firing on an actual `BP_Monkey_C` Pal's interactable sphere). See `docs/hook-points.md`'s eightieth pass.

**Eighty-first pass (2026-09-03): the first REAL (non-watch-only) hook on the vanilla radial menu — REVERTED next pass, see below.** Rather than run another passive verification session, acted on what the eightieth pass already proved: `OnSelectedMenu_Internal` got a dedicated real hook that, on a Pet(4)/Feed(3) selection through the worker wheel, resolved the target Pal and called `Interaction.OnWildPalPetted(pal)` — the same call F9/F10 already make.

**Eighty-second pass (2026-09-03): REAL INCIDENT.** That hook re-captured two of Dragón's own already-owned base Pals — a boss-tier Petallia got auto-added to his party and dropped capture-reward loot, and a second Pal was silently re-captured too. Root cause: `Trust.OnInteractionSucceeded` had NO ownership check — an owned Pal's real `FriendshipPoint` is essentially always past the 55-point capture threshold, so calling it on one was always going to fire the real `PalCaptureSuccess` call. This bug is latent since the thirty-ninth/forty-first pass; it just never fired before because F9/F10 are rarely pressed on owned Pals, unlike the vanilla "4" wheel which is used on them constantly. **Fixed at the root**, permanently, for every path: added `Capture.IsAlreadyOwned(pal)` (checks the real `OwnerPlayerUId` GUID against all-zero, fails safe toward "treat as owned" on any doubt), checked in both `Trust.OnInteractionSucceeded` and `maybe_trigger_capture`. **Also reverted** the eighty-first pass's real hook back to watch-only-only — Dragón correctly called the underlying direction premature: wiring automatic capture-adjacent behavior into a UI action used during completely ordinary play carries a much bigger blast radius than F9/F10 ever did, and deserves more deliberate care than it got in the same pass that shipped it. Separately confirmed by the same test: "4" on a genuinely wild Pal still does nothing — the ownership gate for both radial-menu systems remains unfound. See `docs/hook-points.md`'s eighty-second pass for the full incident writeup.

**Eighty-third pass (2026-09-03): a real path to "vanilla menu, wild target" — no custom art, no forcing anything open.** Dragón correctly pushed back on the custom-menu idea (real icon art/animations/sound is genuinely outside this project's reach) and restated his preferred direction: make the existing "no-aim" wheel act on the wild Pal you're aiming at. Found a strong candidate for how it decides its target: `TryGetSpawnedOtomo()` on `UPalOtomoHolderComponentBase` — a plain native getter returning the active Otomo. If the menu reads this internally, and if UE4SS hooks can override a native function's return value (partial evidence it can, via a bundled mod's `OutParam:set()` usage — not yet confirmed for a plain getter specifically), the whole polished vanilla Pet/Feed pipeline could be redirected onto a wild Pal by substituting just this one value, no new UI needed. This pass only watches: logs every real call/return and safely tests the override mechanism with a true no-op (reads the value, sets it right back, unchanged either way) to learn whether substitution is even possible before ever trying it live. See `docs/hook-points.md`'s eighty-third pass.

**Eighty-fourth pass (2026-09-03): read the eighty-third pass's test session and found the real explanation, plus a better redirect target.** Dragón reported the wild-Pal "4" test still targeting his Otomo; the log from that exact session explained it directly rather than needing another round-trip. Two confirmed findings: (1) the no-op override test passed on all 474 sampled calls — the mechanism works — but `TryGetSpawnedOtomo` also fires ~4x/second even with no menu open, meaning other systems depend on it too, making it an unsafe global override target (same risk shape as the eighty-second pass's incident: a shared function is not a safe place to bolt on Pal-specific behavior); (2) `WORKER-WATCH` failed to register on `WBP_WorkerRadialMenu_C`/`_Overlay` for the ENTIRE session — that class never loaded, meaning the aim-based Worker Menu never opened once, on the party Pal or the wild Pal. Every "4" press that session went through the no-aim Player Menu instead, which by design always acts on the Otomo — fully explaining the result without needing any override to have failed. New plan: redirect via the Player Menu's own confirmed-real action functions (`OnDecidedInstructionCare`/`OnDecidedInstruction_Feed`) calling this mod's own already-safe `do_pet()`/`do_feed()` on the aimed wild Pal, instead of touching the shared getter — needs one more live test (narrating "picking Pet"/"picking Feed" in order) to map which function/args mean which action. Also deduped the `OTOMO-GETTER-WATCH` log (only logs on change now) as a proactive lag-prevention measure. See `docs/hook-points.md`'s eighty-fourth pass.

**Eighty-fifth pass (2026-09-03): first real substitution attempt — scoped, bounded, EXPERIMENTAL.** Dragón's next test (aim "4" at a wild Pal, then pet the real Otomo) showed `OnDecidedInstructionCare`'s bool argument is an output ("valid target found"), not something to redirect — it fired `false` while the Otomo was still unspawned and `true` right after `TryGetSpawnedOtomo` returned a real Otomo, with no Pal parameter passed in at all. That kills the eighty-fourth pass's plan to hook that function directly, and puts the redirect back on `TryGetSpawnedOtomo` — but scoped this time: a new window flag (`radialMenuActionWindowOpen`) is only true between the confirmed-real `Can Open Player Action Menu` and `CloseMenu` fires (plus a 1.5s safety timeout), so the substitution can only ever happen during an actual "4" press, never during the ~4/sec ambient calls other systems make. Inside that window, once per window, it reuses `find_targeted_pal` (the same safe look-based targeting F9/F10 use) and `Capture.IsAlreadyOwned` to confirm a genuinely wild aimed Pal, then calls `ReturnValue:set(wildPal)` — the first real substitution, not a no-op. Honest open question: this function takes no Pal parameter, so whatever actually pets/feeds almost certainly re-reads the same getter rather than being handed a value — unconfirmed until tested live. See `docs/hook-points.md`'s eighty-fifth pass.

**Eighty-sixth pass (2026-09-03): read-only investigation into whether a real, native follow system reaches wild Pals.** Dragón directly challenged whether this project's follow logic (§3.4, `Combat.lua`) — a periodic `PalMoveToLocation` nudge that sometimes gets ignored — was really the best available, and separately asked if the 1.5s follower tick could be a lag source (no evidence it is: ~0.67/sec, touches only actively-bonding Pals, one purposeful native call — nothing like the two real per-tick lag bugs already found and fixed elsewhere). Grepped the game's real header dump for how an actual Otomo decides to follow and found `APalAIController:GetAIActionComponent()` → `UPalAIActionOtomoDefault:SetOtomoFollowAction()` (alongside SetOtomoCombatAction/WorkAction/BaseCampAction/Berserker) — the genuine native decision layer, a much more solid mechanism than nudging against the Pal's own uninterrupted wild AI. The catch: no "Wild"-named composite action class exists anywhere in the dump, so it's a real open question whether a wild Pal's controller has this component active at all, or runs a separate path entirely — guessing wrong and pushing a new composite action onto it blind would repeat the eighteenth pass's `SetActiveAI(false)` mistake, or worse. Shipped only a read-only diagnostic (`Combat.StartFollowing` now logs, once per follow-start, whether the bonding Pal's `AIActionComponent` exists and what it reports) — nothing is set or changed yet. See `docs/hook-points.md`'s eighty-sixth pass.

**Eighty-seventh pass (2026-09-03): REAL BUG FOUND — the eighty-fifth pass's redirect twice substituted the PLAYER, not a wild Pal.** Reading Dragón's latest session log (routine, while answering an unrelated question) turned up 7 real `[RADIAL-REDIRECT]` fires: 5 correctly picked a wild Lamball, but 2 substituted `BP_Player_Female_C` — his own character — because the redirect excluded only the current Otomo from `find_targeted_pal`, not the player (unlike `do_pet`/`do_feed`, which have always excluded the player from this same function), and `Capture.IsAlreadyOwned` wrongly read the player as "wild" off an all-zero owner GUID on a shared component. Confirmed benign in practice — both times the real friendship grant landed on the actual Otomo, meaning the real pet logic doesn't re-read this getter — but that was luck, not a guarantee, and the exact class of gap the eighty-second pass already burned this project on once. Fixed at the source: exclude the player (matching the proven-safe pattern), plus two explicit belt-and-suspenders re-checks. See `docs/hook-points.md`'s eighty-seventh pass for the full writeup.

**Eighty-eighth pass (2026-09-03): ROOT CAUSE FOUND, first real fix attempt shipped.** Live Dragón dumps (via Live View's "Dump as JSON") of the real `PalHUDDispatchParameter_WorkerRadialMenu` object — one from pressing "4" on the owned Otomo, one from a wild Pal — showed the exact break: `OnClose` (the completion delegate, normally bound to `OnSelectedOrderWorkerRadialMenu`) is empty for the wild case, AND `IndividualHandle` is the literal same object in both dumps, never re-pointed at whatever's actually aimed at. `OnSelectedOrderWorkerRadialMenu` is confirmed declared on `APalMonsterCharacter`, the base class of every Pal actor — so the fix is structurally sound, not a guess about whether the function exists. Shipped: a new hook on `/Script/Pal.PalHUDInGame:PushWidgetStackableUI` (+ `PalHUDService:Push`) that, only for a confirmed-wild aimed Pal (`find_targeted_pal` + `Capture.IsAlreadyOwned`, same proven pattern as every prior real hook here), rewrites `Parameter.IndividualHandle` (a plain field read off `CharacterParameterComponent`, new `get_individual_handle()` helper) and calls `Parameter.OnClose:Bind(wildPal, "OnSelectedOrderWorkerRadialMenu")`. The `:Bind()` call syntax itself is the one unconfirmed piece — wrapped in its own `pcall`, logged separately (`[WORKER-BIND-FIX]`) so a live test shows immediately whether it's right, or hands back the exact Lua error to iterate from. Owned-Pal behavior is completely untouched by the wild-only gate. See `docs/hook-points.md`'s eighty-eighth pass for the full writeup and comparison dumps.

**Eighty-ninth pass (2026-09-03): three real tests, zero fires — added a diagnostic instead of guessing further.** Dragón tested the eighty-eighth pass's fix carefully (clean ground, close range, direct aim, repeated "4" presses on a wild Lamball) and confirmed the Worker Menu never opens at all — every press shows the same no-aim Player Menu, and `WORKER-WATCH` still can't register `WBP_WorkerRadialMenu_C` after 8 rounds. That rules out "aim wasn't precise enough" and raises a bigger question: does the hooked `PushWidgetStackableUI`/`PalHUDService:Push` even carry any radial-menu traffic at all (Player menu included), or is the whole hook point wrong? Added an unconditional, deduped diagnostic log (`[WORKER-BIND-FIX-DIAG]`) that prints every widget class pushed through either function, regardless of match — the next single "4" press (any target) will answer this directly. See `docs/hook-points.md`'s eighty-ninth pass.

**Ninetieth pass (2026-09-03): real breakthrough — the Worker Menu opened live, wrong hook point identified and replaced.** Dragón's repeated "4" presses finally produced a full real open-to-close-to-selection cycle for `WBP_WorkerRadialMenu_C` (Construct→OnSetup→...→OnSelectedEvent=Pet→Destruct). Cross-referencing timestamps proved the eighty-eighth pass's hook (`PushWidgetStackableUI`/`PalHUDService:Push`) never fired anywhere near that window despite matching the SDK's documented signature — it simply isn't how this menu delivers its Parameter. `OnSetup` fires with no arguments at all, pointing to the Parameter being a plain Blueprint variable (`self.Parameter`) rather than a function argument. Extracted the fix logic into a shared function and added a new real hook on `WBP_WorkerRadialMenu_Overlay_C:OnSetup` that reads `self.Parameter` directly — the first hook point actually proven to fire during a real Worker Menu open. See `docs/hook-points.md`'s ninetieth pass.

**Ninety-first pass (2026-09-03): Dragón supplied the real missing insight — it's base-worker status, not wild-vs-owned.** Direct correction from live play: the Worker Menu vs. Player Menu choice depends on whether the aimed Pal is a registered base worker, not on ownership — meaning a wild Pal can never trigger the Worker Menu regardless of how correct the eighty-eighth pass's fix is, since the game decides which menu to build before that code ever runs. Found a strong candidate for the real eligibility check: `UPalCharacterParameterComponent.WorkAssignId` / `GetWorkAssign()`, a plain field/getter already safely readable via the same component this file already uses. Shipped a read-only diagnostic only (`[WORKASSIGN-DIAG]`) to confirm this against real base-worker vs. wild data before any override is attempted — spoofing real work-assignment state blind risks corrupting actual base bookkeeping. See `docs/hook-points.md`'s ninety-first pass.

**Ninety-second pass (2026-09-03): second frontier opened — weighted random personality tiers, assignment half only.** Dragón asked to run two independent lines of work in parallel and gave a concrete spec for this second one: every wild Pal individual gets a randomly-rolled personality tier independent of species — 50% normal (species default) / 25% curious / 10% hostile / 15% skittish — so players can occasionally meet a friendly individual of a hostile species or vice versa. Implemented the assignment half in `Personality.lua`: `GetOrInitState` now rolls this once per stable individual ID and folds it into the existing `disposition` field, so every current caller of `GetDisposition` picks it up automatically. Deliberately did not implement enforcement (making the game's real AI act on the rolled tier) — that's a separate, riskier step (overriding `AIResponsePreset` or a throttled `SelectResponseBySenses` hook), still open. Dragón mentioned a third-party "pacifist" mod as possible prior art for that harder half; pending him sharing it. See `docs/hook-points.md`'s ninety-second pass.

**Ninety-third pass (2026-09-03): personality enforcement, first real attempt.** Reverse-engineered the vanilla game's own preset data (`repak`-extracted, byte-diffed against Dragón's saved "pacifist" mod) and found `UPalAIResponsePreset` — a shared, per-species object every wild Pal's `AISensorComponent` points at to decide "what do I do if I see/get hurt by the player," with only 11 real variants existing in the whole game. Confirmed with Dragón before writing anything live: personality should affect behavior as soon as a Pal is nearby, not only after being pet once. Implemented a new recurring 8s scan in `Personality.lua` that, for any wild Pal whose rolled tier isn't "normal," re-points that one Pal's own preset reference at an already-live donor object borrowed from another currently-loaded Pal of a species that naturally matches the tier (Warlike/escape/friendly) — never editing the shared object itself, never touching owned Pals. Whether this actually changes live AI behavior, and whether the scan is cheap enough, are both unconfirmed until Dragón tests it. See `docs/hook-points.md`'s ninety-third pass.

**Ninety-fourth pass (2026-09-03): real lag bug from the first live enforcement test, found and fixed.** Dragón's test reported lag and no visible personality change; the log showed the ninety-third pass's donor search re-called `GetPresetClassName` (with its own logging) for every nearby Pal on every retry, producing 2813 identical log lines in under 3 minutes — fixed by caching one preset-to-actor lookup per scan cycle. Separately, every one of those calls hit a brand-new failure shape (`preset:IsValid()==false`, never seen in this project before), meaning the underlying preset pointer read as null for effectively every Pal this session — `GetOrInitState` now retries this instead of permanently caching a bad first read, but whether that's the real fix is still unconfirmed. Also got a real, clean base-worker `WorkAssignId` data point (Sheepball, `AssignType=1`) for the radial-menu front, though the wild-Pal side of that comparison still didn't fire this session. See `docs/hook-points.md`'s ninety-fourth pass.

**Ninety-fifth pass (2026-09-03): second lag source fixed, deeper enforcement question raised, unrelated mod investigated.** Second live test showed less lag but still real — found and throttled a second unconditional-repeat log (`[ENFORCE]`'s "no donor found," 221 lines) in the same class as the ninety-fourth pass's fix. More significantly, the retry-on-nil fix never once succeeded (0 "resolved on retry" in a 3-minute test), suggesting the AIResponsePreset pointer may only become readable after a real interaction event rather than from passive proximity alone — every prior successful read in this project's history came from the pet/feed handler, never from passive scanning. Proposed a no-new-code diagnostic (pet one wild Pal, check for a retry-success log line) before writing more enforcement code blind. Separately investigated Dragón's "RemoteAccessEverything" mod: confirmed via repak/strings it modifies the unrelated `WBP_PlayerRadialMenu` (adds remote Palbox/storage access), not the Worker Menu this project cares about. See `docs/hook-points.md`'s ninety-fifth pass.

**Ninety-sixth pass (2026-09-03): self-corrected on the "grayed out Pet/Feed" mystery.** Initially concluded the buttons were gated by a deep, save-critical ownership check (`IsActivatedSelectOtomo`) and recommended abandoning this path. Dragón pushed back — asking to change the answer to the gating question rather than fake underlying data, the same technique already used for the Worker Menu's `OnClose`/`IndividualHandle` — which prompted a re-read of the existing `TryGetSpawnedOtomo` redirect and found a much simpler, cheaper bug: the redirect was capped to fire only once per menu-open window, but the getter is called repeatedly during that window, so whatever decides button state very plausibly read an un-redirected later call. Removed the cap (kept the log deduped instead). If this alone fixes the grey-out, the "deep ownership wall" theory was wrong; if not, it confirms something like `IsActivatedSelectOtomo` really is in play and needs its own diagnostic next. See `docs/hook-points.md`'s ninety-sixth pass.

**Ninety-seventh pass (2026-09-03): the ninety-sixth pass's fix was never actually tested — hook registration itself was timing out first.** Dragón's next test still showed grey-out, but the log proved this test never exercised the fix at all: `RADIAL-REDIRECT` fired zero times because every `WBP_PlayerRadialMenu_C` hook (including the one that arms the redirect window) failed all 8 retry rounds and gave up ~37s after mod load — about 90 seconds before Dragón's first "4" press that session. The same simultaneous failure hit every other Blueprint-UI retry loop in the file (`INDICATOR-WATCH` ×2, `WORKER-WATCH` ×2, `WORKER-BIND-FIX`), pointing at a general "these widget classes aren't loaded into memory this early" timing issue, not a naming problem. Fix: extended the shared retry budget from 8 rounds/40s to 60 rounds/5 minutes — bounded, not infinite, since a couple of candidate names are still unconfirmed guesses and this project has hit real log-spam lag bugs twice before. See `docs/hook-points.md`'s ninety-seventh pass.

**Ninety-eighth pass (2026-09-03): real breakthrough — the grey-out theory confirmed correct, plus a self-inflicted lag regression fixed.** With the extended budget, `RADIAL-REDIRECT` fired twice and Pet/Feed were NOT grayed out — Dragón clicked them. This proves the ninety-sixth pass's theory right: there was never a deep ownership wall on the Player Menu, only the once-per-window cap plus the hook-registration timing bug, both now fixed. The log also shows real decision events (`OnDecidedInstructionCare`, `OnDecidedPlayerActionMenu`) firing on the substituted wild Pal right after each click — proving the click genuinely reaches Blueprint decision logic, not just the button's visual state. "Nothing happened" after clicking is expected: since the eighty-second pass's incident, no decision event has been wired to a real action — that's the real next step, not yet done. Separately, Dragón reported new, worse lag this session — traced to the ninety-seventh pass's own extended budget: failed `RegisterHook` errors embed a full identical stack traceback every time (pure waste), and a handful of candidate names are genuinely dead on their classes (proven dead — siblings on the same class resolved in 2-3 rounds while these kept failing to round 19+). Fixed by trimming logged errors to their first line, and by giving a class only 3 more rounds after any sibling target proves it's loaded, instead of the full 60 — a name still unresolved that long after a sibling succeeded is wrong, not slow. See `docs/hook-points.md`'s ninety-eighth pass.

**Ninety-ninth pass (2026-09-03): wired Player Menu Pet/Feed to a real action on wild Pals.** Dragón gave the go-ahead. Deliberately avoided decoding `OnDecidedInstructionCare`/`OnDecidedInstructionFeed`'s ambiguous boolean argument — instead just remembers which named event fired last during the window and acts on it once, at `CloseMenu`, gated hard behind `radialMenuRedirectedThisWindow` (only true when a wild Pal was actually substituted, never the player's own Otomo). The action itself reuses F9/F10's existing `do_pet()`/`do_feed()` wholesale rather than writing anything new — same real-time re-aim, same busy-gate (a stray double-fire just no-ops), and same `Capture.IsAlreadyOwned` guard in `Trust.OnInteractionSucceeded` that was added right after the eighty-second pass's incident. See `docs/hook-points.md`'s ninety-ninth pass.

**Hundredth pass (2026-09-03): found why Pet/Feed worked intermittently — a stale internal timeout, not a game-side busy check.** Dragón's test (own Otomo fine; Gummoss failed; Lamball worked once, then failed on a repeat) matched a real bug: the redirect window's safety-timeout (`RADIAL_ACTION_WINDOW_TIMEOUT_MS`, 1500ms since the eighty-fifth pass) was shorter than how long he actually took to decide — real decision events kept firing 3-4 seconds after menu-open, well past the timeout, so the window had already silently gone stale by the time he clicked. Fixed by extending it to 15 seconds, safe now that `CloseMenu` has proven reliable across every test session. Also found and fixed a second bug in the same area: `radialMenuRedirectedThisWindow` (reused by the ninety-ninth pass as the hard "only act on substituted wild Pals" gate) was actually being set true unconditionally on window-open, before the wild/owned checks ran — meaning it was also true during his own real Otomo interactions, and only escaped causing a double-fire bug by a lucky ordering quirk. Fixed by moving the assignment to the one spot where a wild Pal is actually confirmed and substituted. See `docs/hook-points.md`'s hundredth pass.

**Hundred-and-first pass (2026-09-03): the timeout fix confirmed working (21 of 25 "4" presses fired a real action) — logged the remaining lag as a tracked backlog item instead of chasing it further.** Dragón's next test: WILD-ACTION fired 21 out of 25 real "4" presses this session — a big jump from the handful of successes before the hundredth pass's fix, strong confirmation it's working. He also pasted a burst of ~60 consecutive `RegisterHook` FAILED lines and said the game visibly hitches for a fraction of a second every time he presses "4" — real, felt lag, not imagined. Traced the pasted burst to the hook-registration retry system doing exactly what it's designed to do (this session's UI classes happened to take until round 11 to load, ~55s, versus round 4 in the previous test — normal session-to-session variance, not a new regression) — it still stopped on schedule (confirmed via the log's own "stopping early" lines) and only 2 tracebacks total this whole session, so the ninety-eighth pass's fix is holding. But the frame hitch on every single "4" press is a different, not-yet-investigated cost — likely the substitution logic's own per-call work (re-aiming, component lookups) rather than logging. Rather than chase this now, added a dedicated performance/polish backlog (§10) per Dragón's explicit request to track it instead of fixing blind. Personality: no progress this pass (not the focus) — `resolved on retry` is still 0 for the whole session, species-default preset reads remain 100% "curious" fallback; rolled-tier assignment itself is confirmed still working correctly (real spread across normal/curious/hostile/skittish). See `docs/hook-points.md`'s hundred-and-first pass.

**Hundred-and-second pass (2026-09-03): chased the per-press hitch as Dragón requested — found and throttled a concrete, provable cost.** `find_targeted_pal` (the redirect's own aim-scan) does a full `FindAllOf("PalCharacter")` scan plus a `GetFullName()` and location read per nearby Pal, on every qualifying hook call — up to ~4/sec for as long as the menu stays open, now up to 15 real seconds since the hundredth pass's own timeout extension. That's a real, self-inflicted, non-guessed cost. Throttled it to recompute at most every 250ms (a player's aim doesn't meaningfully change that fast) and added a `[RADIAL-REDIRECT-PERF]` log with the real millisecond cost of each scan, so the next test either confirms this was the hitch or rules it out with real numbers instead of more guessing. See `docs/hook-points.md`'s hundred-and-second pass.

**Hundred-and-third pass (2026-09-03): the throttle's own diagnostic explained why the hitch persisted, then pivoted to feature work per Dragón's call.** Dragón's next test: Pet worked cleanly on every wild Pal he tried this session (zero bugs found), but the felt hitch was still there, and real `[RADIAL-REDIRECT-PERF]` numbers from the log showed why — every actual scan costs 36-50ms, and since the cache resets on every window-open, the first scan of every "4" press still eats that full cost regardless of the 250ms throttle. Root cause is the per-scan cost itself, not call frequency (already fixed). Documented three concrete, not-yet-attempted directions for reducing that cost (cheap-check-first ordering, actor-reference exclusion instead of `GetFullName()`, whole-window actor-list caching) in the backlog, but did not implement any of them — Dragón asked explicitly to set performance aside for now ("we can separate the actual mod from all the other things... later") and pick a feature to work on instead, leaving the choice up to Claude.

**Hundred-and-fourth pass (2026-09-03): real food-item feeding, Stage 1 — research + read-only diagnostics only.** Dragón picked "Feed opens a real food item" from his feature wishlist (chosen over beam/join-text, balancing, diminishing returns, follower AI, follower combat-assist, skittish→curious, play interaction, kinship peaches, settings screen, general optimization, server feasibility) because it closes an already-flagged gap AND is the one missing piece for kinship peaches to work as he described them. Real SDK dump research found `APalMonsterCharacter:SelectedFeedingItem(FPalItemSlotId, int64 Num)` as the likely real item-feeding function (same base class as `OnSelectedOrderWorkerRadialMenu`), `UPalItemUtility.CollectLocalPlayerControllableItemInfos_ByTypeB` as a way to query the player's real food inventory without any UI, and confirmed `EPalItemTypeB` has a dedicated `ConsumePalGainFriendshipPoint` category separate from regular food — very likely the "kinship peach" category Dragón meant. Per this project's read-before-write rule, shipped only two read-only additions this pass: a permanent watch-hook on `SelectedFeedingItem` (to catch it firing naturally in real vanilla play) and an F10-triggered, additive food-inventory dump using the CDO-call pattern already proven safe elsewhere (Capture.lua/Personality.lua) — the exact calling convention for the query's out-param array is unconfirmed and this is the first live test of it. Existing Pet/Feed behavior is completely unchanged. See `docs/hook-points.md`'s hundred-and-fourth pass for the full research writeup and staged plan.

## 10. Performance & polish backlog

Tracked per Dragón's explicit request (hundred-and-first pass) rather than fixed blind — these are real, observed costs, not guesses, but none has been root-caused precisely enough yet to fix safely.

- **Per-"4"-press frame hitch — root cause understood, fix DEFERRED per Dragón's explicit request (hundred-and-third pass).** The hundred-and-second pass's throttle shipped and Dragón's next test confirmed real `[RADIAL-REDIRECT-PERF]` numbers: every actual (non-cached) `find_targeted_pal` scan costs a consistent 36-50ms. That single number explains why the felt hitch survived the throttle — the cache resets on every window-open (by design, so a new "4" press always re-aims fresh), so the very first scan of every press still pays the full 36-50ms cost regardless of the 250ms recompute interval. A single ~40ms blocking call is, on its own, roughly 2-3 dropped frames at 60fps — enough to be felt as a short stutter every time, independent of how many repeat scans the throttle prevents. Root cause is therefore the per-scan cost itself (full `FindAllOf("PalCharacter")` map scan + `GetFullName()` + location/angle math per nearby Pal), not call frequency — frequency was already fixed. Real next-step candidates for actually reducing the per-scan cost (not attempted yet): reorder checks so the cheap distance test runs before the expensive `GetFullName()` per Pal; drop `GetFullName()` entirely in favor of comparing actor references directly for exclusion; or cache the `FindAllOf("PalCharacter")` actor list itself across a whole window instead of only the final chosen Pal. Deferred at Dragón's explicit request ("let's move from that for now... later on, we can separate the actual mod from all the other things we've left around") in favor of feature work — revisit alongside the general optimization pass (last item, this section).
- **Hook-registration retry log volume.** The bounded retry system (`make_hook_round_runner`, `MAX_RADIAL_HOOK_ROUNDS=60`, 5s/round) is working as designed — it's supposed to keep trying until Blueprint UI classes load — but the number of rounds needed varies a lot session-to-session (round 4 one test, round 11 the next), and every round re-attempts every still-unresolved candidate, so a slow-loading session produces a real burst of log writes concentrated in the first ~1 minute. Already trimmed to 1 line per failure (ninety-eighth pass) and cut short once a class proves loaded (also ninety-eighth pass) — but a slow session before that first proof can still produce hundreds of lines in a short window. Possible future directions: detect real widget construction directly instead of blind timed polling; or reduce per-round logging to only what changed since the last round.
- **General `Logger.lua` write cost.** Every `Logger.log` call is a synchronous, immediately-flushed disk write (by design, for crash-survivability — see the project's very first crash-debugging pass). That tradeoff has been worth it for debugging so far, but as more systems log more often, the cumulative cost is worth revisiting once the mod is closer to feature-complete (e.g. a buffered/batched write mode that only forces a flush periodically, keeping crash-survivability for the common case).
- **A real Feed didn't fire properly on a repeat attempt at the same wild Pal (hundred-and-twenty-fourth pass, 2026-09-03).** Dragón fed the same wild Chikipi four times through the real "4" menu; the fourth attempt (same Pal, same session) didn't fire correctly per his own report. Not investigated — flagged by him as "a bug for another time," not urgent. Worth checking against `palbonds-live.log` around that fourth attempt whenever this gets picked up, to see whether it's the same stale-window class of bug already fixed once (hundredth pass) or something new.

## 11. Feature wishlist (Dragón, 2026-09-03)

Sent as a full list after the hundred-and-third pass, with the pick of what to work on next left up to Claude. Tracked here so nothing gets lost; status updated as passes touch each item.

- **Real food-item feeding — IN PROGRESS (hundred-and-fourth pass, Stage 1 of 4).** See the hundred-and-fourth pass changelog entry above and `docs/hook-points.md`'s matching writeup for the full research and staged plan.
- **Kinship peaches** — blocked on the item above (Dragón's own framing: "technically they should work already since they just give friendship points, but for that the feed option needs to open the inventory to pick an edible item"). Real SDK evidence found this pass: `EPalItemTypeB.ConsumePalGainFriendshipPoint = 45`, a dedicated item category separate from regular food — very likely this is exactly that item type already in the game's own data.
- **Join beam VFX** — not started. When a Pal actually joins (capture threshold reached), play a real visual beam/effect, matching the game's own capture-cage light-beam animation. Capture.lua's fortieth-ish pass history already notes the current capture path has no VFX — a possible starting point is the `SpawnCaptureObject`/prism-related functions investigated in §9's "Prism resolved" note.
- **In-game join text — IMPLEMENTED (hundred-and-thirtieth pass, 2026-09-03), NOT YET TESTED LIVE.** A real reference mod ("QuickConsumableSlots") uses a real, proven toast mechanism to show on-screen messages — `PalUtility:GetLogManager(player)` → find the real toast widget class (its name contains "BlinkedLog") off the manager's `OverrideClassMap` → `KismetTextLibrary:Conv_StringToText` → `manager:AddLog(...)`. `Capture.NotifyJoined(pal, player)` fires this (currently a plain "A wild Pal has joined your party!" — a real species name could be added later once/if a Pal-name localization function is confirmed, same category as the item-name lookup the reference mod itself uses) right after `Capture.TryDirectCapture` in `OnTrustMaxed`. Test plan: get a wild Pal to full trust and watch for the toast when it joins.
- **Balancing (taming difficulty)** — explicitly deferred by Dragón himself ("this is for much later... now being fast its useful for testing"). Just numeric tuning once the mechanics are otherwise finished — no research needed yet.
- **Diminishing returns on repeated interactions** — explicitly bundled with balancing by Dragón, same "much later" timing. Would need a per-Pal repeat-interaction counter/decay, not designed yet.
- **Follower Pal AI (real following behavior)** — not started, but now has THREE real, un-reconciled leads instead of zero:
  1. Eighty-sixth pass: `APalAIController:GetAIActionComponent()` → `UPalAIActionOtomoDefault:SetOtomoFollowAction()` — the genuine native follow-decision layer. Never confirmed whether a bonding wild Pal's controller has this component active.
  2. Hundred-and-twenty-ninth pass ("PalFollowerTweaks" reference mod): `PalFunnelCharacter` — the game's own real internal name for a SECONDARY follower (the exact Daedream/Dazzi/Flopie behavior Continuación 6 originally observed), with a real driving action (`BP_AIAction_FunnelFollow_C`), a direct `character:GetTrainer()` ownership getter, and a real hook (`/Script/Pal.PalFunnelCharacter:OnActive`).
  3. **Hundred-and-thirty-first pass ("MultiPals" reference mod) — the strongest lead of the three, and now actually being tested live**: `holder:ActivatePalByHandle(handle, Location, Rotation, bool)` is a REAL, WORKING, PROVEN call (this mod uses it constantly to activate extra already-owned party Pals alongside the main Otomo) — the exact function this project found the name of back in the twentieth pass and wrote off as dead after normal Otomo-switching never called it. A new experimental key, CTRL+O in `Interaction.lua`, calls this exact function directly on a genuinely WILD Pal's handle for the first time — untested territory (every prior use of this function, in this project and in MultiPals, was on an already-owned, currently-recalled party Pal, never a wild one with an actor already live in the world). See `hook-points.md`'s hundred-and-thirty-first pass for the full risk breakdown. **Status: implemented, not yet tried live.**
- **Follower Pals protecting the player in combat** — not started, not researched at all yet. Would likely build on whatever the follower-AI item above establishes.
- **Skittish → Curious after first successful interaction — IMPLEMENTED (hundred-and-twenty-fifth pass, 2026-09-03), NOT YET TESTED LIVE.** `Personality.OnSuccessfulInteraction(palId, palActor)`, called from `Interaction.OnWildPalPetted` (an event already confirmed reliable), flips a Pal's tracked `disposition` from "skittish" to "curious" the first time a real pet/feed lands on it — once, permanently, regardless of whether it got there via a forced "skittish" roll or a naturally-skittish species. Best-effort also tries to make this show up in real AI behavior, reusing the exact same safe, ownership-gated, borrow-an-already-live-donor's-AIResponsePreset pattern the enforcement scan already uses — but only if a live "curious"-preset donor happens to be loaded nearby at that exact moment; if not, the tracked state still updates, logged either way. Test plan: chase down and pet/feed a Pal whose log shows `disposition=skittish`, then check for a `[WON-OVER]` line.
- **"Play" interaction (experimental)** — not started. A new third interaction type (alongside Pet/Feed): both player and Pal play an existing animation together for a smaller/different friendship gain. Would likely reuse `do_interaction()`'s shared shape with a new player action type, same low-risk pattern as Feed's twelfth-pass addition.
- **Settings screen** — not started, explicitly "maybe, for later," flagged by Dragón as being for OTHER mods to use PalBonds' settings, not urgent.
- **General mod optimization** — explicitly last priority by Dragón's own request; see §10 above for the concrete, already-diagnosed per-press hitch as the leading candidate whenever this is picked up.
- **Server-possibility check** — not started, not researched. Whether this mod (client-side UE4SS Lua, direct native calls) could function in a dedicated-server context is an open question with no investigation yet — likely needs checking whether UE4SS itself runs server-side for this game and whether the native functions this mod calls are client-only or safe to call server-side too.

**Hundred-and-fifth pass (2026-09-03): first real confirmation that `SelectedFeedingItem` is the correct hook target, and a workflow-driven diagnostic-placement fix.** Dragón announced he'll test exclusively through the radial menu from now on (not F9/F10 directly) so any behavior difference between the two surfaces immediately. His test fed three Pals via the radial menu: a wild Chikipi (worked, no inventory opened — matches this mod's own approximation exactly, since our wild-Pal redirect still just calls `do_feed()`), then an active-summoned Otomo and a base worker Pal (both opened a real inventory and let him pick Berries — genuine vanilla behavior, entirely outside this mod's own code, since owned Pals are excluded from the wild-Pal redirect). The log confirmed the wild Chikipi case is unchanged and working as before. More importantly, the `[FOOD-DIAG]` watch-hook on `SelectedFeedingItem` fired for real exactly once, for a Pal (`BP_CloverFairy_C`) with a genuine `ContainerId`/`SlotIndex=7`/`Num=1` — the first live confirmation that this function really is the real item-consumption call, not a guess. Which of the two owned-pal feeds this corresponds to is unconfirmed (only one fire logged despite two owned-pal feeds reported) — flagged to Dragón to clarify next test. Separately, found and fixed a real gap: the F10-triggered food-inventory dump (`log_available_food_items`) was wired to the literal `RegisterKeyBind(Key[FEED_KEY])` closure, which never runs when `do_feed()` is invoked indirectly through the radial-menu wild-Pal path — meaning it would never have collected any data under Dragón's new radial-menu-only test workflow. Moved it inside `do_feed()` itself so it fires regardless of entry point. No existing Pet/Feed behavior changed. See `docs/hook-points.md`'s hundred-and-fifth pass for the full log excerpt and analysis.

**Hundred-and-sixth pass (2026-09-03): base-worker vs. active-Otomo feeding CONFIRMED to use two different native functions; food-inventory query still returning nothing, second calling-convention attempt shipped.** Dragón ran a clean, clearly-ordered test (fresh session log) — feed then pet a wild Lamball, feed then pet his active Otomo Foxparks (internal name `BP_Kitsunebi_C`), feed then pet his base worker Chikipi (`BP_ChickenPal_C`) — specifically so each event's timing was unambiguous. Real findings: the wild Lamball went through this mod's own `do_feed()`/`do_pet()` exactly as before (no item, no inventory — matches design). Foxparks (active Otomo) produced NO `F10 pressed`/`[DIAG]` lines at all (confirming owned-Pal interactions are 100% vanilla-native, completely untouched by this mod) and, critically, did NOT trigger the `SelectedFeedingItem` watch-hook — only a plain `AddFriendShip` grant of 10, same flat amount as everything else. The base worker Chikipi's feed DID trigger `SelectedFeedingItem` for real (second confirmation of this exact function, now across two separate sessions and two different Pals). Conclusion, now well-evidenced rather than guessed: base-camp worker Pals and active-summoned Otomos LOOK identical to the player when fed (both open an inventory, both let you pick an item) but go through two different real functions under the hood — `SelectedFeedingItem` is confirmed as the base-worker path; the active-Otomo path is still unidentified. Separately, the food-inventory-query diagnostic (now correctly wired to fire on every `do_feed()` call, per the prior pass's fix) DID fire this time but returned plain `nil` — not a crash, just nothing — for its first calling-convention guess. Shipped a second attempt (omitting the out-param placeholder entirely, capturing extra Lua return values instead) alongside the first, both logged under distinct labels so the next test's log shows directly which shape (if either) actually returns real data. See `docs/hook-points.md`'s hundred-and-sixth pass for the full log excerpt.

**Hundred-and-seventh pass (2026-09-03): the food-inventory calling-convention question is SOLVED, worker-vs-Otomo split reconfirmed a third time on a new species.** Dragón's next identical-shape test (wild/Otomo/worker, feed then pet each) gave decisive log evidence for both open threads. First: `SelectedFeedingItem` fired again for the base worker — this time a Daedream (`BP_DreamDemon_C`), a third distinct species/session confirming the same real function, and this time with a genuinely-assigned `WorkAssignId` (`LocationIndex=0 AssignType=1`, a real `PalWorkAssign_TransportItemInBaseCamp` reference) rather than the ambiguous `LocationIndex=-1 AssignType=0` seen in earlier tests — removing the last shred of doubt that this really is the base-worker feeding path. The active Otomo (Foxparks again) once more produced zero `SelectedFeedingItem` fires — third confirmation of the worker/Otomo split. Second, and more directly actionable: Attempt B (omitting the out-param) failed outright with a precise, real UE4SS error — "UFunction expected 4 parameters, received 3" — hard proof the SDK dump's 4-parameter signature must be called exactly as declared, killing that hypothesis for good. Attempt A (4 args, `{}` placeholder) ran clean with no error but returned Lua `nil` — now understood as expected rather than mysterious: the function is declared `void`, so it has no return value to capture at all; the real output can only ever have been written into the out-param table itself. Fixed by keeping a named local table, passing it in, and reading that same variable back after the call instead of the (necessarily empty) call return — replacing both hundred-and-sixth-pass attempts with this one corrected version. Not yet confirmed live whether this finally surfaces real food-item data. See `docs/hook-points.md`'s hundred-and-seventh pass.

**Hundred-and-eighth pass (2026-09-03): Stage 1 complete — the player's real food inventory is now readable.** Dragón's next test (wild Daedream, Otomo Foxparks, worker Lamball/`BP_SheepBall_C` — a fourth distinct species confirming the base-worker `SelectedFeedingItem` path, Otomo again silent) confirmed the hundred-and-seventh pass's fix worked: the out-param table came back with 2 real entries on both fires. Each entry is a wrapped `FPalStaticItemIdAndNum` struct — read its `StaticItemId`/`Num` fields directly (the same safe field-read pattern this whole file already uses, never a risky whole-struct-by-value call) instead of just logging the opaque handle. This closes Stage 1 of the food-feeding feature: the mod can now genuinely see what food/friendship-treat items the player is carrying. Not yet confirmed live what the actual item names/counts are (this fix went out without a live readback of the new field-read code) — that's the immediate next test, and once confirmed, Stage 2 (building a real `FPalItemSlotId` for one of these items) can start. See `docs/hook-points.md`'s hundred-and-eighth pass.

**Hundred-and-ninth pass (2026-09-03): field reads on the returned entries came back nil, switched to explicit error-visible pcall to find out why.** Dragón fed several wild Lamballs in a row (6 real diagnostic fires) after being given clearer, more explicit instructions (a "feed any Pal" instruction the prior turn was rightly called out as ambiguous — fixed by naming exactly what counts as a wild Pal and giving numbered steps). Every fire again returned 2 real entries, but this time reading `entry.StaticItemId`/`entry.Num` (the hundred-and-eighth pass's fix) came back plain `nil` for every single one — no crash, just nil, and `safe_call()`'s pcall-swallowing meant there was no way to tell a genuinely-null field apart from a wrong access pattern on this particular kind of entry (a `LocalUnrealParam`-wrapped struct pulled out of a TArray-of-structs via an out-param — a shape this project hasn't read struct fields from before; every prior field read has been on a direct component/object field). Replaced `safe_call` with explicit per-step `pcall` in the logging helper so a real error message surfaces if the field access itself is throwing, rather than being silently hidden as an indistinguishable nil. Not yet confirmed live which of the two (a genuinely-empty field vs. a wrong access pattern) this actually is — that's the next test.

**Hundred-and-tenth pass (2026-09-03): the field really is unreadable this way — no error, just genuinely nil, three tests running.** Dragón's next test used the new error-visible logging, and the result is now unambiguous: `StaticItemId(raw field)=nil` with NO "FIELD-READ-FAILED" text anywhere — meaning the `pcall` itself succeeded (no exception), and `entry.StaticItemId` really does evaluate to plain `nil` when read this way, three times in a row. This isn't a wrong-syntax crash to iterate past; it means this project's usual "read a field directly off the object" pattern (proven safe and working everywhere else in this file — components, handles, save-parameter fields) does not work on this particular kind of object: a `LocalUnrealParam`-wrapped struct pulled out of a `TArray<FPalStaticItemIdAndNum>` that came back through a BlueprintFunctionLibrary out-parameter. This is a genuinely different object shape than anything previously read in this project, and continuing to guess at field-access syntax without a stronger lead risks burning more of Dragón's test cycles for no progress — flagged to him directly as a real fork in the road (keep trying UE4SS Lua access patterns on this wrapper type, vs. switch to the simpler `CountLocalPlayerInventoryItemNum64(WorldContextObject, StaticItemId)` function instead, which returns a plain `int64` with no struct-wrapping question at all — trading dynamic discovery of what food the player has for needing to already know real item ID strings up front, which would need extracting the game's own item data table from its `.pak` files, a bigger one-time research step). No code changed this pass — decision pending Dragón's input.

**Hundred-and-eleventh pass (2026-09-03): went straight to the game's own files, as Dragón asked, and found real candidate item names — including a strong lead on "kinship peaches."** Dragón pushed back on the framing (correctly): the wild-Pal inventory never opening isn't a bug (that part of the feature isn't built yet), and he asked to go investigate the game's files directly rather than keep guessing at Lua syntax — this project's own established fallback (`repak` against the real game `.pak`, used successfully in the seventy-third/seventy-eighth/ninety-third/ninety-fifth passes). Extracted `Pal/Content/Pal/DataTable/Item/DT_ItemDataTable_Common.uasset` (the master item table) and read its embedded name table with `strings` (the paired `.uexp` holds only packed binary row data — no readable text; string data for a UE asset's rows lives in the `.uasset`'s own name table). Found real candidate row names: ordinary food (`BerryRed`, `MeatRaw`, `MeatMarbledRaw`, `Milk`, `Honey`, `Egg`) and, notably, `AffectionFruit_01`/`AffectionFruit_02` — "Affection" lines up strongly with `EPalItemTypeB.ConsumePalGainFriendshipPoint` (the dedicated friendship-treat category found in the hundred-and-fourth pass) and is a strong, concrete lead for what Dragón's "kinship peaches" idea actually maps to in the game's real data. These are asset-name-table strings, not yet proven to be the exact `StaticItemId` values the live inventory system expects — that's what this pass's new diagnostic tests. Rather than keep fighting the broken struct-array field read, shipped a parallel, much simpler check: `CountLocalPlayerInventoryItemNum64(player, itemId)` for each candidate name — a plain `int64` return, no TArray/out-param/struct-wrapping question at all. If any of these come back non-zero and match what Dragón is actually carrying, it both confirms the naming convention the game expects AND gives a proven-simple path forward for Stage 2, sidestepping the array approach's dead end entirely. See `docs/hook-points.md`'s hundred-and-eleventh pass.

**Hundred-and-twelfth pass (2026-09-03): REAL GAME CRASH — Crash #4, cause and fix.** Dragón's very next live test (feeding a wild Pal to check the hundred-and-eleventh pass's new item-count diagnostic) crashed the game outright, twice in a row: `EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000070` — a near-null pointer read inside native code. This is a materially different, more serious class of problem than anything else in this project's history: every previous "unconfirmed guess" (the Worker Menu's `OnClose:Bind`, every struct field read) was safe to try live because a wrong guess produces a catchable Lua error — `pcall`/`safe_call` cannot catch a hard access violation inside a native function call, which crashes the whole game process regardless of how carefully the Lua call site is wrapped. The likely cause: the hundred-and-eleventh pass's `CountLocalPlayerInventoryItemNum64` loop (and possibly the `CollectLocalPlayerControllableItemInfos_ByTypeB` call before it) passed a plain Lua string where the native function declares an `FName` parameter — this project has read `FName`s off live objects many times before, but had never previously CONSTRUCTED one from a Lua string to hand INTO a native call, and that distinction turned out to matter. Immediate fix: removed the call to `log_available_food_items()` from `do_feed()` entirely — Feed (both F9/F10 and the wild-Pal radial-menu wiring) is back to exactly its pre-hundred-and-fourth-pass behavior, with zero food-inventory-diagnostic code running on the live hot path. The diagnostic functions themselves are left in the file for reference, marked with an explicit "DO NOT CALL LIVE" warning, but are fully disconnected. This closes the real-food-feeding feature's Stage 1 investigation for now — any future attempt at reading item data this way needs a much higher bar of confidence before testing live again, given the demonstrated crash risk. See `docs/hook-points.md`'s "Crash #4" writeup for the full incident report.

**Hundred-and-thirteenth pass (2026-09-03): post-crash research pivot — found a zero-code-risk path via `UPalItemSlot`, no live test yet.** With the Crash #4 hotfix confirmed holding ("did a test run, it didnt crash"), Dragón separately dumped `T_itemicon_Food_Berries.json` via Live View's "berries" search — read via `device_bash cat` (this file only exists on Dragón's machine, not the cloud workspace). Turned out to be just the inventory icon's `Texture2D` asset, not real item/slot data — confirms the "Food_Berries" naming convention but doesn't hand us anything to build a real `FPalItemSlotId` from. Given the Crash #4 lesson (no more constructing native call parameters from scratch without a much higher confidence bar), went looking in the SDK dump for a path that needs zero new native calls instead: found `UPalItemSlot`, a real, independently-spawned live `UObject` (one per inventory slot) with `SlotIndex`, `ContainerId`, and `ItemId` (`FPalItemId{StaticId, DynamicId}`) fields that map almost exactly onto what `SelectedFeedingItem` needs — meaning Dragón can find and dump one directly via Live View, the same zero-risk method already used successfully for the Worker Menu dispatch object and the berries icon, with no new Lua code and no crash exposure at all. Nothing shipped this pass — pure research. Next: ask Dragón to find and dump a real `UPalItemSlot` holding a food item they know the exact count of, then read whatever comes back. See `docs/hook-points.md`'s hundred-and-thirteenth pass.

**Hundred-and-fourteenth pass (2026-09-03): read every dump JSON Dragón had actually produced — confirmed `UPalItemSlot`'s real value shape, but a major correction: vanilla Feed does not go through `SelectedFeedingItem`.** Dragón's reply to the hundred-and-thirteenth pass's instructions turned out to be a bulk object-search listing, not individual dumps ("tried to dump a few, dunno if i got the right one") — but `ue4ss/IndividualObjectDumps/` on his machine already held every real "Dump as JSON" he'd produced across two sessions, read directly via `device_bash`. Five real `PalItemSlot` dumps confirmed the exact value shape with real numbers (`ContainerId=(ID=<32-hex GUID>)`, `ItemId=(StaticId="<FName>", ...)`, a `Money` slot's `StackCount=856` — a real, plausible confirmation the field reads correctly). But his `UE4SS.log` from the same session shows he fed his Otomo three real times via the vanilla radial menu, and the hundred-and-third pass's permanent `[FOOD-DIAG]` watch on `SelectedFeedingItem` never fired once — a clean negative result. His own dumps of `BP_ActionPairStandby_FeedItem_C`/`BP_ActionPairBehavior_FeedItem_C`/`BP_AIActionPairCall_FeedItem_C` reveal what actually happens instead: a full Blueprint AI-action pairing between the player's `ActionComponent` and the Otomo's own AI controller, with the real `FeedItemSlotId`/`FeedItemNum` sitting as plain fields on the AI-action-call object (independently confirming the struct shape) alongside animation montages, camera work, and a `PawnAction`-based AI queue — not a single safely-replicable native call. This is a real complexity increase for the wild-Pal food feature versus what earlier passes assumed, and needs a design conversation with Dragón before more code gets written. Also found, as a bonus: `PalHUDDispatchParameter_WorkerRadialMenu`'s real dumps carry a plain `IndividualHandle` + `resultType` field, a cleaner potential source of truth for the existing wild-Pal radial redirect than today's aim-tracking (not urgent, that system already works). Cleaned up `ue4ss/IndividualObjectDumps/` (all of it already read here) and an old empty Crash #4 dump file, with Dragón's permission. No code changed this pass. See `docs/hook-points.md`'s hundred-and-fourteenth pass.

**Hundred-and-fifteenth pass (2026-09-03): added a new zero-risk watch hook on `UPalItemSlot:RequestUseToCharacter`, the next candidate for the real food-consumption call.** With `SelectedFeedingItem` ruled out and the real vanilla mechanism (a full AI-action pairing) too complex to safely replicate, went back to `UPalItemSlot`'s own method list and found `RequestUseToCharacter(FPalIndividualCharacterHandle, int32)` — a method ON the slot object itself, meaning if this is what actually consumes the item, calling it would only ever need a slot we FOUND (via `FindAllOf`, already this project's proven-safe pattern) and a target handle read directly off an already-live Pal (exactly like `get_individual_handle()` already does everywhere) — never a struct built from scratch, avoiding the Crash #4 pattern entirely. Added a permanent, read-only `[SLOT-USE-DIAG]` watch on it in `Interaction.lua`, same zero-risk discipline as every other watch hook in the file (confirmed-real function name, no new native calls, just field reads off the object the hook hands us). Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. Test plan: feed the Otomo again through the normal radial menu and check for a `[SLOT-USE-DIAG]` line — if it fires, we get the real consumption mechanism AND, for the first time, a real food item's `ItemId.StaticId`. See `docs/hook-points.md`'s hundred-and-fifteenth pass.

**Hundred-and-sixteenth pass (2026-09-03): CONFIRMED — `RequestUseToCharacter` is the real vanilla item-consumption call.** Dragón's very next real feed produced three real fires of the new watch, with `StackCount` reading 65, then 64, then 63 — a perfect one-for-one decrement matching `UseNum=1` each time. That's direct, live proof this is the function vanilla actually uses to consume a food item, the most important confirmed fact this project has found for the food-feeding feature so far, obtained with zero new native-call risk. Fixed a cosmetic bug in the same pass: plain `tostring()` on an `FGuid`/`FName` field just prints its memory address in UE4SS Lua — added a `readable()` helper that calls the value's own `:ToString()` method first (a safe method call on an already-obtained value, not a new native call) so the next real fire will show the actual GUID and food item name in plain text. Also noticed the target argument's real type is `FPalInstanceID` (from `GetFullName()`), not the `FPalIndividualCharacterHandle` originally assumed from the SDK signature comment — worth confirming with one more real read before assuming either way. Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. See `docs/hook-points.md`'s hundred-and-sixteenth pass.

**Hundred-and-seventeenth pass (2026-09-03): every piece needed to call the real feed function ourselves is now proven safe — added a CTRL+J dry run before ever actually calling it.** Dragón's next feed confirmed the readable-item-name fix (`ItemId.StaticId=Berries`, plain text). The one remaining question — where to get a real `FPalInstanceID` for a Pal we pick ourselves, since `RequestUseToCharacter`'s target argument is that struct type, not the `FPalIndividualCharacterHandle` originally assumed — turned out to already be answered by code this file uses on every interaction: `get_individual_handle(pal)` returns a `UPalIndividualCharacterHandle*`, and that class has a plain field `ID` (an `FPalInstanceID`) plus a `GetIndividualID()` getter. So `get_individual_handle(pal).ID` gives a real, live instance ID for any Pal, via the same safe direct-field-read pattern this file already relies on everywhere — never a struct built from scratch. Every piece — the food slot (found via `FindAllOf`), the target ID (read off an already-trusted object), and the call itself (arguments relayed between live objects, not manufactured) — is now individually proven safe. But actually calling this deducts a real item, a new category versus every watch-only hook so far, so added a fully separate CTRL+J dry run (mirroring the CTRL+K `TryDirectCapture` isolation pattern) that finds the aimed Pal, reads its real `FPalInstanceID`, finds a live "Berries" slot, and logs everything — without calling anything. Test plan: compare the logged StackCount against Dragón's real held count. Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. See `docs/hook-points.md`'s hundred-and-seventeenth pass.

**Hundred-and-eighteenth pass (2026-09-03): the dry run got a perfect match against Dragón's real inventory — upgraded CTRL+J into the real call.** Dragón reported exactly 62 Berries; the dry run's `candidate #1` read `StackCount=62` on every press, while every other match read 1 or 2 (stray amounts on other Pals, not the player's stash) — a clean, unambiguous real-world confirmation the whole chain resolves correctly. Upgraded the same isolated CTRL+J test into the real thing: picks the candidate with the highest `StackCount` (a heuristic grounded in that real evidence) and calls `RequestUseToCharacter(individualId, 1)` on it for real, then re-reads the slot's count immediately after as a before/after check. Every argument is either found (the slot) or read off an already-live object (the target ID) — never constructed from scratch, the key distinction from Crash #4. Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. Dragón was told explicitly this now spends a real item before he tests it. See `docs/hook-points.md`'s hundred-and-eighteenth pass.

**Hundred-and-nineteenth pass (2026-09-03): real testing found the actual gate — `RequestUseToCharacter` only consumes items for the player's own active Otomo, not any Pal — added a fallback and wired in the Happy reaction.** Dragón's own real test (11 CTRL+J presses) showed a clean, deterministic pattern once the log was read: aiming at a wild `BP_ChickenPal_C` returned `ok` but never moved `StackCount` (a silent no-op); aiming at his actual spawned Otomo (`BP_Kitsunebi_C`) worked both times, dropping the count by exactly 1 each time — matching his own report ("saw 2 disappear after taking out my otomo"). So the native call is gated to owned/active Otomos internally, something no static SDK dump could have revealed — only live testing found it. Rather than chase that internal gate, added a self-correcting fallback: re-check `StackCount` after the native call, and only if it didn't move, write `slot.StackCount = before - 1` directly — a new category of operation for this file (a scalar field write, not a read or call), but low-risk (one plain int, no replication machinery) and structurally unable to double-consume. Also wired in the target's Happy reaction afterward (the exact proven call `do_interaction()` already uses, same busy-gate), so one CTRL+J press now attempts the full cycle: consume the item (natively or via fallback) → Pal reacts happily → real vanilla friendship grant. Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. See `docs/hook-points.md`'s hundred-and-nineteenth pass.

**Hundred-and-twentieth pass (2026-09-03): Dragón corrected the whole approach, and a real test confirmed the fix needed is deeper than expected — PAUSED pending his decision.** Dragón rejected the hundred-and-eighteenth/nineteenth passes' "auto-pick the biggest food stack and silently consume it" design outright, correctly pointing out real vanilla Feed opens the actual inventory/item-picker (showing nothing if you're out of food, never auto-selecting or blocking) and that this project's own established method is to find and activate the real system, never approximate one — his words: "dont try to trick the game into doing something, just find how it does and activate it for our feed interaction." That raised a real question: does the existing wild-Pal `TryGetSpawnedOtomo` substitution (already used since roughly the eighty-fifth pass to make wild-Pal Pet/Feed work via the real "4" menu) already unlock the real food-picker system too, since that system also keys off "the current Otomo"? Tested directly — Dragón picked Feed via the real radial menu on wild Pals six times — and the log showed only this project's own gesture approximation firing every time, with zero trace of the real `SelectItemInventory`/`ActionPairStandby/Behavior/Call_FeedItem` machinery that fires reliably for a real Otomo feed. Since hooks in this project are non-blocking, that's clean evidence the game itself won't continue into the real flow for a Pal only substituted at that one getter — there's a deeper eligibility check further in, possibly reading the player's actual authoritative owned-Pal list (`OtomoIndividualIdList`) rather than the substituted getter, which would mean satisfying it means touching a real ownership record — a bigger risk category than anything modified so far. No code changed this pass; work is paused here pending Dragón's call on whether to keep researching that deeper gate or reconsider scope. See `docs/hook-points.md`'s hundred-and-twentieth pass for the full detail.

## 12. Priority TODO list (2026-09-03) — SUPERSEDED, read CLAUDE.md's "EMPEZAR ACÁ" instead

> **⚠️ STALENESS WARNING added 2026-09-06.** This list is from 2026-09-03 and several
> of its entries are now wrong. It is kept for its reasoning and evidence, not for its
> status claims. **The authoritative, current ordered list lives at the top of
> `CLAUDE.md` ("⚠️ EMPEZAR ACÁ").**
>
> This warning exists because a fresh session on 2026-09-06 produced a technical audit
> that reported kinship peaches as "fully blocked" — copied straight from item 8 below —
> when they had in fact been implemented, balanced and live-tested days earlier. Dragón
> caught it immediately. Corrections to the specific items:
>
> - **Item 3 (Join VFX):** the named candidate `ABP_ReturnPalEffect_C` is **ruled out**,
>   not "already found." A dedicated test run (Continuación 163) showed it fires only on
>   Otomo switching, never on any real capture or cage rescue. A fresh candidate is needed.
> - **Item 4 (Personality sensor resolution):** **solved.** A reactive hook on
>   `SelectResponseBySenses` (Continuación 121/167) gets a valid sensor handed to it by
>   the game itself, and caches it per Pal. The proactive scan described below is now
>   only a fallback.
> - **Item 5 (bonding-phase following):** still open, but both leads below have since
>   been **tried and confirmed not to work** — `SetOtomoFollowAction`, the repeated Otomo
>   composite, and the Funnel path all require real ownership. Do not re-try them as if
>   they were untested.
> - **Item 8 (Kinship peaches): DONE, not blocked.** `Interaction.lua`'s
>   `RequestUseToCharacter` post-hook reads the consumed item id and grants 250
>   (`AffectionFruit_02`) or 500 (`AffectionFruit_01`) against the 500-point bonding bar.
>   Live-tested on a Petallia. Item 7 (real food-item feeding) remains shelved, but
>   peaches were never actually blocked on it.

This is the authoritative, ordered pending list, written after a full session of hitting real walls on personality and real-food-item feeding, and after Dragón explicitly asked to stop inventing new research questions and instead work through what's actually left, in order. **Start here next time — don't re-derive this from scratch, and don't reopen anything marked "shelved" below without new information that specifically changes its assessment.**

### Phase 1 — safe, buildable, no research needed (do these first)

1. **"Play" interaction** — a third interaction type alongside Pet/Feed. Reuses `do_interaction()`'s exact shared shape (targeting, busy-gates, the target's reaction, friendship grant) with a new player action type — the same low-risk pattern Feed itself used when it was added. Zero new native-call risk, no open questions, just needs to be written.
2. **Real fleeing on trust-loss** — right now `Capture.OnTrustLost` only sets a permanent flag that blocks further interaction (`Capture.HasPermanentlyFled`); the Pal doesn't actually flee or despawn, it just stands there un-interactable. Needs a small investigation into how the game makes a Pal flee (`APalAIController`'s escape/flee behavior, or the flee-related fields already seen in `try_calm_target`'s `TargetPlayers`/`HateSystem` work), but it's a contained, bounded polish item — not a deep systems question.
3. **Join VFX (capture light-beam)** — a real candidate actor is already found and documented: `ABP_ReturnPalEffect_C` (Continuación 45-46, `hook-points.md`), built around a `UNiagaraComponent`/`LerpStartPos`/`Progress` shape that matches "a Pal visually traveling to join the player." Never wired up. Purely cosmetic — even a wrong first attempt just means no visual effect, no gameplay risk.

### Phase 2 — bounded investigation, real payoff, NOT open-ended (do these once Phase 1 is done)

4. **Personality sensor resolution** — `GetComponentByClass` is confirmed (Hundred-and-thirty-fifth pass, real numbers: 41/41 and 92/92 failures in one session) to NEVER resolve a valid `PalAISensorComponent` for a wild Pal. The `FindAllOf`-based fallback added the same pass ALSO failed (98/98 still fell back to "curious" in the very next test) — a second, still-unexplained failure. A one-time diagnostic (`log_index_build_once` in `Personality.lua`) is already deployed and will show, on the next test, whether `FindAllOf("PalAISensorComponent")` returns few/no instances at all, or returns instances that just don't match any Pal by owner key. **Fixing this unlocks TWO stalled features at once**: real species-default disposition reading, AND the Skittish→Curious real-behavior swap (both blocked by this exact same function). If the next diagnostic still doesn't resolve it, the fallback decision is: accept "personality tier is random-only, never changes real AI behavior" as a permanent limitation and stop spending more sessions on it.
5. **Bonding-phase real following** (the actual open "Follower Pal AI" question — NOT whether a fully-captured Pal follows, which Dragón already confirmed from direct experience it does). Right now a still-bonding wild Pal (before the 5-interaction/trust-maxed threshold) only gets an approximate `PalMoveToLocation` nudge every 1.5s from `Combat.lua` — not real Otomo-quality following. Two leads exist, neither ever actually tried on a live bonding Pal:
   - `APalAIController:GetAIActionComponent()` → `SetOtomoFollowAction()` — the real native follow-decision layer. `Combat.StartFollowing` already has a one-time `[FOLLOW-DIAG]` diagnostic (from Continuación 62) checking whether a bonding Pal's controller even has a usable `AIActionComponent` — **check this first, it's zero-cost and may already have an answer sitting in an old log**, before trying anything that pushes new AI state (that category burned this project once already — the `SetActiveAI(false)` incident, Continuación 3 — so any real attempt here needs to be small, isolated, and reversible, same discipline as `CTRL+K`/`CTRL+J`).
   - `PalFunnelCharacter`/`BP_AIAction_FunnelFollow_C` (the Daedream/Dazzi/Flopie secondary-follower system, confirmed real via the "PalFollowerTweaks" reference mod) — lower priority than the lead above, since reading that mod's actual source (hundred-and-thirty-seventh pass) suggests becoming a `PalFunnelCharacter` likely still requires genuine party membership first, which a still-bonding wild Pal doesn't have.
6. **Pals assisting/protecting the player in combat while bonding** — not started, not researched at all. Explicitly depends on whichever approach in #5 actually works — don't start this before #5 has an answer.

### Phase 3 — shelved / deprioritized, do NOT restart without new information

7. **Real food-item feeding for wild Pals** — treated as a likely-permanent limitation. Ghidra decompilation this session (Hundred-and-thirty-fourth pass) showed the real "is this my Otomo" gate for the widget's `SelectedFeed` is very likely a raw C++ vtable call — a call shape that bypasses Unreal's reflection system entirely, meaning no `RegisterHook`/return-value-override/cached-field-write technique this project has (or could) use can ever see or influence it. Two independent, correctly-executed substitution attempts (overriding `TryGetSpawnedOtomo`'s return value, writing the widget's own cached `SpawnedOtomo` field) already failed for exactly this reason. Current gesture-based approximation (Happy reaction, real friendship grant, no item spent) stays as the permanent design for wild Pals. Do not attempt further substitutions here without a genuinely new technique, not a variation on ones already tried.
8. **Kinship peaches** — fully blocked on #7. Moves only if #7's assessment changes.
9. **Balancing (taming difficulty) and diminishing returns on repeated interactions** — explicitly deferred by Dragón to be done LAST, once all mechanics above are finished. Pure numeric tuning, no research needed when the time comes.
10. **Settings/config screen** — low priority, explicitly "maybe, for later" per Dragón, meant for other mods to hook into PalBonds' own settings, not urgent for this mod's own completion.
11. **General mod optimization** (the `find_targeted_pal` 35-40ms per-"4"-press scan cost, `Logger.lua`'s synchronous-flush-per-line write cost) — explicitly last priority per Dragón's own repeated request. One real lag source WAS found and fixed this session (the `[INDICATOR-WATCH]` hooks, a third of one session's log volume, from dead research never turned off) — but the remaining known costs above are deliberate, accepted tradeoffs for now, not oversights.
12. **Server-possibility check** — not started, not researched, no identified payoff. Lowest priority on the entire list; only worth picking up if dedicated-server/multiplayer becomes an actual goal for this mod.
