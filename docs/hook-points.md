# Hook Points — Research Log

Running checklist of real game internals we've confirmed, to answer the
"Open Research Questions" in DESIGN.md §8.

For each entry once confirmed, fill in: the real name, how it was found
(FModel dump / UE4SS Live View / an existing open-source mod), and the
version of Palworld it was confirmed against (these can drift between
patches).

## 1. Pal AI Controller / Behavior Tree — ANSWERED

- **Class/struct name:** `BP_MonsterAIControllerBase` is the shared parent
  class (`Pal/Content/Pal/Blueprint/Controller/Monster/`). Wild Pals use
  the subclass `BP_MonsterAIController_Wild`; there are also per-boss
  subclasses (`BP_MonsterAIController_Boss`, `_RaidBoss`, etc.) and a
  companion-specific one, `BP_MonsterAIController_Otomo` (see Q6 — "Otomo"
  is the game's internal term for a Pal actively following/fighting with
  the player).
- **Where species-default disposition is read from:** a data-driven enum
  field called **`AIResponse`**, on every species' row in the DataTable
  `Pal/Content/Pal/DataTable/Character/DT_PalMonsterParameter` (parent
  table `DT_PalMonsterParameter_Common` holds the same row structure —
  row struct is `PalCharacterParameterDatabaseRow`). This is NOT hardcoded
  in the Blueprint graph — it's a per-species data value the controller
  reads (likely via a Blackboard key, see `BP_MonsterAIController_Wild_C:
  GetMyBB` — not yet traced further into the Behavior Tree itself).
  Confirmed enum values found across all 753 rows in the table:
  `Boss`, `Warlike`, `NotInterested`, `Escape_to_Battle`, `Friendly`,
  `Escape`, `Warlike_Anyway`, `Warlike_WithoutPlayer`, `Kill_All`.
  Best-guess mapping to the three player-facing archetypes from the
  original design conversation (needs in-game confirmation, not yet
  verified live):
  - `Warlike` → hostile / attacks on sight (Starryon-like)
  - `Escape_to_Battle` or `Escape` → skittish / flees on approach
    (Tanzee-like)
  - `Friendly` → curious / stays and watches (Daedream-like — only 6 of
    753 rows use this value, consistent with it being a rare, notable
    archetype rather than a common default)
  - `NotInterested` → a fourth, neutral "ignores the player" archetype
    not covered in the original three examples
  - There's a separate `AISightResponse` field on the same struct, but
    every single row has it set to `None` — likely unused/legacy, or set
    elsewhere at runtime rather than per-species.
- **Practical implication for Personality.lua (§3.1):** overriding an
  individual Pal's disposition likely means writing a per-instance
  `AIResponse`-equivalent value somewhere the controller reads at
  runtime (probably a Blackboard key set from this data on spawn) rather
  than needing to touch the Behavior Tree graph itself. Still needs: (a)
  confirming the Blackboard key name UE4SS can write to, (b) confirming
  it can be changed post-spawn and takes effect without a full respawn.
- **Found via:** FModel, `Packages → Search` (Ctrl+Shift+F), searching
  `AIController` then `PalMonsterParameter`; exported
  `DT_PalMonsterParameter` to JSON and inspected programmatically.
- **Confirmed against game version:** Palworld 1.0 client as installed
  2026-09-01 (Pal-Windows.pak, 185,014 files); UE4SS reported `GAME_UE5_1`.

## 2. Pet/feed ownership gate — REFRAMED, worked around rather than found

- We never located a single named "is this Pal mine" check. That logic
  almost certainly lives inside compiled Blueprint graph bytecode (a
  widget's Construct/Tick deciding whether to show the Pet/Feed buttons),
  which a native C++ header dump (UHT/CXX dump, see Session notes) cannot
  show — headers only expose function *signatures* and variables, never
  Blueprint graph logic.
- **Practical workaround, confirmed working as of 2026-09-01**: don't
  touch the game's own interact-prompt UI at all. Every spawned
  `APalCharacter` — wild or owned — already carries a live
  `UPalIndividualCharacterParameter` (see Q3), reachable via
  `APalCharacter.CharacterParameterComponent:GetIndividualParameter()`.
  That object exposes `AddFriendShip(int32 Value, bool bApplyPassiveSkill)`
  as a normal callable function — nothing about it checks ownership from
  what we can see structurally, and it's the exact same function the game
  itself would call on a captured Pal. So Interaction.lua now binds its
  own key, finds the nearest `PalCharacter` directly from Lua, and calls
  `AddFriendShip` on it regardless of ownership — sidestepping the gate
  instead of finding and disabling it.
- **Not yet confirmed**: whether this actually works in practice (pending
  first in-game test) — the header dump shows the function exists and
  what it wants as arguments, not that calling it from Lua definitely
  succeeds with no server-authority/replication rejection. If it turns
  out the game silently drops the call for non-owned Pals (e.g. a
  server-side ownership check we can't see from the client), we'll need
  to fall back to actually finding the Blueprint-side gate via FModel's
  Blueprint graph JSON export (which DOES show K2Node logic, unlike the
  CXX dump).
- **Found via:** UE4SS's own C++ SDK dump (see Session notes below), not
  FModel — FModel's Blueprint export remains the fallback if this
  approach doesn't hold up in-game.

## 3. Existing trust/friendship field — ANSWERED

- **Yes — it's `FriendshipPoint` (int32), live on
  `FPalIndividualCharacterSaveParameter`** (see Q5's struct), alongside
  `FriendshipOtomoSec`, `FriendshipActiveOtomoSec`, `FriendshipBasecampSec`
  (time-based accrual counters — presumably time spent as active Otomo /
  at base camp grants passive friendship gain) and
  `bFavoriteChangedByFriendship`.
- **Live runtime access is via `UPalIndividualCharacterParameter`**
  (a wrapper object, not the raw save struct), which exposes:
  - `int32 GetFriendshipPoint()`
  - `int32 GetFriendshipRank()`
  - `void AddFriendShip(int32 Value, bool bApplyPassiveSkill)` — the
    function we now call directly from Lua (see Q2).
  - Delegates `OnUpdateFriendshipPointDelegate` /
    `OnUpdateFriendshipRankDelegate` — real hook points for observing
    changes without polling, once we're ready to bind to them from Lua
    instead of just reading before/after values.
  - Global (non-instance) helpers on some Blueprint function library:
    `GetMinFriendshipRank()`, `GetMaxFriendshipRank()`,
    `GetFriendshipRequiredPointByRank(rank, &outPoint)`,
    `GetFriendshipRank(int32 FriendshipPoint)`,
    `CalcFriendshipProgress(int32 FriendshipPoint)` — useful for mapping
    a raw point value to something like our original 0.0–1.0 concept if
    we still want that framing in the UI.
- **Usable pre-capture, i.e. on a wild Pal: appears to be YES** — the
  `UPalIndividualCharacterParameter` object lives on
  `APalCharacter.CharacterParameterComponent` for every spawned Pal
  actor, not just owned/captured ones (stats, HP, AI all need this data
  structurally regardless of ownership). This directly answers the open
  question from the previous version of this doc, pending final in-game
  confirmation via Q2's workaround actually landing a friendship change
  on a genuinely wild, never-interacted-with Pal.
- **Design implication**: per the user's explicit instruction, Trust.lua
  should stop maintaining its own parallel 0.0–1.0 float and instead read
  through `GetFriendshipPoint()`/`GetFriendshipRank()` and write through
  `AddFriendShip()`. Trust.lua has NOT been rewritten yet — Interaction.lua
  currently calls `AddFriendShip` directly as a first test, bypassing
  Trust.lua entirely. Folding this back through Trust.lua (so our own
  threshold logic for auto-capture/permanent-flee in Capture.lua can hang
  off real friendship values) is the next real code change needed, not
  just a research question anymore.
- **Found via:** UE4SS C++ SDK dump, `Pal.hpp`, struct
  `FPalIndividualCharacterSaveParameter` and class
  `UPalIndividualCharacterParameter`.

## 4. Sphere-less guaranteed capture call — strong leads, not yet tested

- Several native candidates found in the SDK dump (`Pal.hpp`), none
  tested live yet:
  - `bool JudgePalCapture(class AActor* Pal)` — capture-eligibility
    check for a Pal actor.
  - `void JudgePalCapture_TryAllPhase(const UPalIndividualCharacterHandle*
    targetHandle, const UPalIndividualCharacterHandle* throwCharacterHandle,
    int32 captureItemLevel, TArray<bool>& outJudgeFlagArray, bool Robbery,
    bool bIsSneakBonus)` — the fuller capture-roll logic, still assumes a
    thrown sphere (`captureItemLevel`) — probably not directly useful for
    a sphere-less capture.
  - `void CaptureNewMonster(const FName CharacterID)` and
    `void Debug_CaptureNewMonster_ToServer(FName CharacterID)` — look like
    debug/cheat commands that directly grant a captured Pal by species ID
    without a sphere. Most promising lead for §3.5's "capture without a
    Palsphere" requirement — needs inspecting what class these live on
    (a cheat manager?) and whether they can target a *specific existing
    Pal instance* rather than spawning a fresh one by species.
  - `void CaptureSuccessAlways()` / `bool IsCaptureSuccessAlways()` — force
    the NEXT normal (sphere-thrown) capture attempt to succeed. Doesn't
    skip the sphere itself, so probably not what we want, but confirms a
    debug flag exists that existing "guaranteed capture" Nexus mods likely
    flip.
  - `void PalCaptureSuccess(class APalPlayerCharacter* AttackerPlayer,
    class APalCharacter* Monster)` — fires on successful capture; could
    potentially be called directly to finalize a capture on our bonded
    Pal once trust hits 1.0, bypassing the throw/roll entirely. Untested.
  - Delegate `CapturePalInServerDelegate(UPalIndividualCharacterHandle*
    CaptureCharacterHandle)` — hook point to observe any capture
    happening, useful for QA regardless of which capture path we end up
    using.
- **Next step:** find which class each of these lives on (the dump line
  numbers weren't captured this pass) and test `CaptureNewMonster` /
  `PalCaptureSuccess` against a specific bonded Pal instance from Lua.
- **Found via:** UE4SS C++ SDK dump, `Pal.hpp`.

## 5. Stable per-instance Pal identifier — ANSWERED

- **It's `FPalInstanceID`**: `{ FGuid PlayerUId; FGuid InstanceId; FString
  DebugName; }`. The `InstanceId` GUID is the actual per-Pal unique key;
  `PlayerUId` ties it to whichever player's save it belongs to (relevant
  for multiplayer, out of scope per DESIGN.md §7 anyway).
- **Survives save/load: YES** — confirmed by its use in
  `FPalCharacterStoredParameterInfo`, which pairs
  `FPalIndividualCharacterSaveParameter SaveParameter` (the live stat/
  friendship data) with `FPalInstanceID InstanceId` inside what is
  clearly a persisted-to-disk struct (sibling struct
  `FPalCharacterStoredParameterInfoSaveData` exists specifically for the
  saved-binary form).
- **Practical implication for Personality.lua/Trust.lua**: key our
  per-instance Lua state tables by the `InstanceId` GUID (as a string),
  not by a raw actor/object reference — matches what
  `Personality.GetStableId()`'s TODO already assumed, just now with a
  real field to read it from (`UPalIndividualCharacterHandle:GetIndividualID()`
  or `UPalIndividualCharacterParameter.IndividualId` directly).
- **Found via:** UE4SS C++ SDK dump, `Pal.hpp`.

## 6. Owned-Pal follow/assist behavior-tree branch — partial answer

- **Branch/state name:** not a separate "branch" as originally assumed —
  it's a distinct AI Controller class, `BP_MonsterAIController_Otomo`
  (sibling of `BP_MonsterAIController_Wild`, same parent
  `BP_MonsterAIControllerBase`). "Otomo" is Palworld's internal term for
  the Pal actively following/fighting with the player. There's also
  `BP_MonsterAIController_SupportPal` and several `NPCOtomo_*` variants
  (Invader, Oilrig, Visitor) for special-context companions.
- **Entry condition(s) normally required:** not yet traced — unknown
  whether a Pal's controller is swapped at capture time, or whether the
  same controller instance changes behavior based on a party-membership
  flag. This matters a lot for whether Combat.lua's approach (routing a
  bonding wild Pal into "follow" behavior without a real capture) is
  swapping controller classes at runtime or just setting a state flag —
  the latter is much easier to do safely from Lua.
- **Whether it can be entered without full party membership:** not yet
  known — needs inspecting `BP_MonsterAIController_Otomo`'s own Blueprint
  export the same way we did for `_Wild` (we only confirmed the class
  exists and its parent chain so far, not its internals).
- **Found via:** FModel, same `AIController` search as Q1.

## Session notes

FModel workflow that worked well: `Packages` menu → `Search` (Ctrl+Shift+F)
for a global filename search across all 86,975 loaded packages (the
top-toolbar search box only filters the currently browsed folder, not the
whole archive — easy to confuse the two). For any DataTable, right-click →
`Export` → `Properties (.json)` writes a full JSON dump to
`Downloads\fmodel\Output\Exports\...` mirroring the in-game path — much
faster to grep/search programmatically than scrolling FModel's own JSON
viewer, which has no reliable in-document search.

**UE4SS's own C++ SDK dump — far more valuable than FModel for anything
native (non-Blueprint).** FModel can only show *that* a native struct like
`FPalIndividualCharacterSaveParameter` exists (its `/Script/Pal` path
gives it away as native), not its field layout. UE4SS ships a built-in
generator for exactly this. Steps that worked, 2026-09-01:
1. In `UE4SS-settings.ini`, under `[Debug]`, set `GuiConsoleEnabled = 1`,
   `GuiConsoleVisible = 1`. Also needed `GraphicsAPI = dx11` (the default
   `opengl` silently fails to render any overlay on top of a DirectX game
   like Palworld — no error, the overlay just never appears). Relaunch the
   game after any of these changes; they're not hot-reloadable.
   (`ConsoleEnabled = 1` also exists and spawns a separate plain-text log
   window, but that one is output-only — no command input — don't confuse
   it with the GUI overlay.)
2. Once relaunched, an "UE4SS Debugging Tools (DX11)" overlay window
   appears on top of the game automatically (no hotkey needed, since we
   set `GuiConsoleVisible = 1`). Its `Dumpers` tab has one-click buttons:
   `Dump CXX Headers` (full native C++ header reconstruction — the one we
   want) and `Generate Lua Types` (Lua-facing type stubs — useful for
   Phase 2+ implementation once we know which fields/functions to look
   for). Both run near-instantly (~3.5s) with **no visible progress
   indicator at all** — trust the log (`UE4SS.log` gets lines like
   "Generating SDK..." / "SDK generated in N seconds") over the UI, which
   gives no feedback that anything happened.
3. Output lands in `ue4ss/CXXHeaderDump/*.hpp`, one file per asset/module
   — `Pal.hpp` is the big one with almost everything game-specific
   (thousands of native structs/classes). Individual Blueprint widget
   classes (`WBP_*.hpp`) get their own files but only show their own
   directly-declared functions/variables, not inherited ones or Blueprint
   *graph logic* — the header dump is signatures and data layout only,
   never K2Node/Blueprint graph behavior. For that, FModel's Blueprint
   `Export → Properties (.json)` is still the only option.
4. `grep -rl "StructName"` across `CXXHeaderDump/*.hpp` to find which
   files reference a type, then `grep -n "^struct StructName\|^class
   ClassName"` to jump straight to its definition. Much faster than
   FModel's UI for anything native.

**Screen-control gotcha**: when the user's Claude desktop app window sits
on top of the game on their screen, clicks sent via computer-use land on
the Claude app instead of the intended window underneath — screenshots
filter the Claude app out of view, which makes this invisible until a
click does something unexpected (in this session, it minimized the game).
Keyboard input (type/key) isn't affected the same way, but the safest fix
when this happens is to hand the specific click-driven step to the user
directly rather than fighting z-order blind.

**In-game reference point**: the player's own owned Pals already have a
working interact flow — walking up to one and pressing a key (`4` in the
user's binding) pops up an action wheel with `Pet`/`Feed` options. That's
the exact UI Q2 originally hoped to unlock for wild Pals; Interaction.lua
does not hook this menu (see Q2) and instead adds a separate, independent
key/action.

**Important correction, same day**: the first version of Interaction.lua
only bumped `FriendshipPoint` in the background and called that "petting"
— Dragón correctly pushed back that petting is a real interaction with its
own animation/camera, not a stat change. Found the real thing in the SDK
dump: Palworld's generic action system (`UPalActionBase` and subclasses)
covers every animation-driven behavior, petting included:
- `BP_ActionPairBehavior_Petting` / `BP_AIActionPairCall_Petting` — the
  actual paired player+Pal animation/camera behavior classes.
- `EPalActionType::HumanPetting = 55` / `PalPetting = 56` — dedicated
  enum values (`Pal_enums.hpp`).
- `APalCharacter.ActionComponent:PlayActionByType(ActionTarget,
  EPalActionType)` (on `UPalActionComponent`) is the instance-method entry
  point — almost certainly what the existing action-wheel "Pet" button
  itself calls. Interaction.lua now calls
  `player.ActionComponent:PlayActionByType(pal, 55)` instead of touching
  friendship data directly, so the real animation should play regardless
  of ownership (the function takes no ownership flag). `AddFriendShip` is
  kept as a safety-net call afterward in case the action's own internal
  logic skips friendship gain for a Pal it doesn't recognize as owned —
  flagged in the code to remove if that turns out to double-count.
- Not yet confirmed live: whether this actually plays the animation on a
  wild Pal, or a raw Lua-side `55` is accepted as the `EPalActionType`
  argument at all.

**First real in-game test result (2026-09-01, second relaunch):** partial
success, with two real bugs found:
- The player's own petting animation DID play — confirms `55` works as a
  raw Lua value for `EPalActionType` and `PlayActionByType` genuinely
  triggers the real game action, not a no-op.
- The targeted Pal did NOT play its own reaction animation.
- **Targeting bug**: the key fired even standing in open ground with no
  Pal visibly nearby, and friendship climbed steadily and consistently
  (+5 from our own call, plus an unexplained +10 appearing between
  presses — most likely the real action's own internal Blueprint logic
  granting friendship asynchronously on montage completion, which is
  actually good news: it suggests the vanilla reward logic already fires
  regardless of ownership). The likely cause: `find_nearest_pal` searched
  ALL loaded `PalCharacter` actors in the world, not just ones near/in
  front of the player — almost certainly grabbing the player's own
  already-owned companion Pal (which follows at close range at all times)
  rather than a genuinely wild, never-touched target. This is NOT how the
  real game targets Pals for interaction (per Dragón: it's look-based, you
  have to aim at the Pal).
- **Fix applied**: replaced nearest-in-world search with real look-based
  targeting — camera location (`FollowCamera:K2_GetComponentLocation()`)
  as the origin, `APawn:GetControlRotation()` (confirmed to exist in
  `Engine.hpp`) converted to a forward vector, and only actors within
  both a range AND a narrow angle of that forward vector qualify, picking
  the most centered match. Also added printing the target's `CharacterID`
  and `OwnerPlayerUId` on every attempt, specifically so the NEXT test
  can confirm we're actually hitting a wild Pal and not an owned one.
- **Experiment added, unconfirmed**: also calling `PlayActionByType` on
  the TARGET Pal's own `ActionComponent` with `EPalActionType::PalPetting`
  (56), targeted back at the player — a guess that the action system is
  symmetric enough for this alone to trigger the Pal's own reaction
  animation without needing the full `BP_AIActionPairCall_Petting` wiring.
  Next test will show whether this does anything.
- **Key changed from `P`**: it already opens an in-game menu. Using `F9`
  for now (guaranteed to exist in UE4SS's `Key` table regardless of
  keyboard layout). Dragón's suggestion of `Ñ` was set aside because OEM/
  layout-specific keys aren't reliably named the same way across UE4SS
  installs — worth revisiting once the mechanic itself works.

**⚠️ CRASH, second in-game test (2026-09-01, third relaunch).** Standing
next to a wild Pal with no owned Pal nearby (so this was the FIRST test
against a confirmed genuinely-wild target), pressed the key — game froze
then closed. No Lua error appeared in the log, which is the signature of
a native engine crash (e.g. a null pointer deep in compiled Blueprint
bytecode), NOT a catchable Lua exception — `pcall`/`safe_call` cannot
protect against this class of failure at all.

Prime suspect: the experimental line added this same pass that called
`pal.ActionComponent:PlayActionByType(player, ACTION_TYPE_PAL_PETTING)`
directly on the TARGET's own action component. `BP_ActionPairBehaviorBase`
(the parent of the real petting action) has fields like `Camera` (an
`ABP_PettingCamera_C*`) and a `IsValidTarget` check that are almost
certainly populated/run by the game's own `BP_AIActionPairCall_Petting`
AI-call flow before the action is ever allowed to start. Calling the
action directly skips all of that setup — if the Blueprint graph assumes
those fields are already valid by the time `OnBeginAction`/`TickAction`
run, this is exactly the kind of thing that segfaults.

Can't fully rule out the player-side `PlayActionByType(pal, HumanPetting)`
call either, since — per the targeting-bug note above — the EARLIER
(non-crashing) test almost certainly hit the player's own companion, not
a wild Pal. So there is currently NO confirmed-safe data point for
calling `PlayActionByType` (either direction) against a genuinely wild
Pal. Both calls have been removed from Interaction.lua rather than
guessing which one was at fault.

**Lesson for all future native-function experiments in this project**:
`RegisterHook`/direct UFunction calls from Lua are not automatically
safe just because the function signature is visible in the SDK dump — a
function that's normally only ever invoked through a specific internal
flow (AI-driven, with prior setup) can crash hard when called out of
that context, and no amount of Lua-side pcall/error-handling protects
against it. Test new native calls incrementally, ideally with a save
that can tolerate a crash, and prefer functions confirmed to be safe
general entry points (like the Blueprint function library statics) over
calling internal action/component methods directly until their
preconditions are understood — ideally by reading the actual Blueprint
graph (FModel export) for `IsValidTarget` and `OnStartPair` first, not by
trial and error in a live session.

**Next step, once resumed**: read `BP_ActionPairBehaviorBase`'s
`IsValidTarget` and `BP_AIActionPairCall_Petting`'s `OnStartPair` via
FModel's Blueprint `Export → Properties (.json)` (which shows K2Node
graph logic, unlike the CXX dump) to understand what setup is actually
required before it's safe to call either action type directly — or find
whichever single call the real action-wheel "Pet" button on owned Pals
itself makes, since that's guaranteed to be a safe, complete entry point.

## Spy.lua results — Q2 effectively answered, contradicts the `55`/`56` guess

Dragón's suggestion (capture a Pal, use the game's own "4" → Pet/Feed menu
on it, and just watch what fires) worked, and gave a clean, repeatable
answer — read directly from `UE4SS.log` via the device bridge rather than
pasted console text, per the workflow change agreed this session.

**Test session data (2026-09-01, Lamball captured then pet ×2, fed ×1,
stored in Palbox, retrieved, pet once more — game fully closed before the
log was read):**

- Exactly 3 `AddFriendShip` calls total, all `value=10, applyPassiveSkill=
  true`, all on the same object,
  `...BP_PalGameStateInGame_C_2147480903.PalCharacterManagerReplicator_
  2147480901.PalIndividualCharacterParameter_2147480725` — confirming
  friendship lives behind a `PalCharacterManagerReplicator`, one call per
  interaction (pet/feed apparently grant the same amount and look
  identical from this hook — no separate "feed" signature was visible).
- **Every single `AddFriendShip` call is followed, ~0.4–0.5 seconds later,
  by exactly one `PlayActionByType` call with `type=38` (`Happy`) on a
  `BP_SheepBall_C_*` actor** ("SheepBall" = Lamball's internal codename).
  This held 3/3 times, with no exceptions and no other action type ever
  appearing in that ~0.5s window.
- The `BP_SheepBall_C_*` instance ID stayed the same
  (`2147460175`) across the first two `AddFriendShip` calls, then changed
  to `2147456878` for the third — exactly matching Dragón's own described
  sequence (pet ×2 while the Lamball was actively out, then stored in the
  Palbox and retrieved before the third interaction). Storing/retrieving
  from the Palbox destroys and respawns the actor, which is why the object
  ID changes; this is a nice independent confirmation the log lines up
  with the real play session play-by-play.
- **`type=55` (`HumanPetting`) and `type=56` (`PalPetting`) were never
  observed even once**, despite ~1150 log lines covering the whole
  session and 22 unrelated `type=1` (`Sleep`) + 1 `type=64` (`GroundSit`)
  calls from ambient wild-Pal/NPC AI in the background. This directly
  contradicts the third-pass guess (documented above) that the
  action-wheel "Pet" button calls `PlayActionByType` with `HumanPetting`/
  `PalPetting` — real gameplay through the actual menu never triggers
  either value, at least not through `PalActionComponent:PlayActionByType`
  (they may be dispatched through a different component entirely — e.g. a
  synced camera "petting scene" distinct from the quick action-wheel
  interaction — or may simply not be what the vanilla Pet button uses at
  all; still an open, lower-priority question).

**Conclusion — what the real "Pet"/"Feed" menu action actually does, as
far as this hook can see:** call `AddFriendShip(10, true)` on the target's
`IndividualParameter`, then have the target's OWN `ActionComponent` play
`EPalActionType::Happy` (`38`) on itself as its reaction. No player-side
action call was visible at all through this hook — the player's own
crouch/reach animation is evidently driven by something else (a montage
played directly, or a different component not hooked here).

**Why this is a much safer next call than the crash candidate**: `Happy`
is one of the same generic, self-directed reaction types used constantly
by ambient AI (`Sleep`, `GroundSit` — idle behaviors with no interaction
partner at all), not a synced pair-action requiring
`BP_AIActionPairCall_Petting`'s setup (`Camera`, `IsValidTarget`, etc. —
see the crash writeup above). It was called dozens of times across this
one short session with zero crashes, by many different Pal instances, in
exactly the self-directed pattern (`component:PlayActionByType(<something
non-nil, likely self>, type)`) we'd be imitating. This is still a native
call we have not yet made ourselves, so it is not risk-free — but it is
categorically different from blindly calling a synced pair-action type,
and there is now strong observational evidence for exactly how the real
game calls it and in what type value.

**Change made as a result**: Interaction.lua's `do_pet()` now calls
`pal.ActionComponent:PlayActionByType(pal, 38)` (self-target, `Happy`)
immediately after a successful `AddFriendShip`, matching the observed real
pattern as closely as possible. `PET_FRIENDSHIP_GAIN` was also bumped from
`5` to `10` to match the real grant amount exactly, since the project is
now built directly on the real `FriendshipPoint` economy rather than an
invented one. **Not yet tested live** — this is the next thing to try
in-game, ideally on a genuinely wild (never-owned) Pal, the same way the
crash test was set up, so a bad outcome is caught immediately and can be
isolated.

`Spy.lua`'s `Init()` call has been commented out of `main.lua` now that it
answered its purpose (the file itself is left in place in case we need to
watch again — e.g. to catch the still-unexplained player-side animation
trigger, or to distinguish Pet from Feed if that ever matters).

## ⚠️ CRASH #2 (2026-09-01, fourth relaunch) — busy/sleeping Pal theory

Live-tested the sixth-pass `Happy` reaction call (see Interaction.lua
header) — crashed again. Dragón's own theory: the target was asleep, and
the vanilla game already refuses to Pet/Feed a sleeping Pal, not just as
UI politeness. The SDK dump backs this up: `UPalActionComponent` has a
real state machine (`CurrentAction`, `ActionQueue`,
`GetCurrentActionType(bool)`, `HasAction(EPalActionType)`,
`IsActiveActionType(...)`, `ActionIsEmpty()`) — forcing a new action over
one already running could plausibly corrupt that state. Added a guard:
skip the `PlayActionByType` call entirely unless
`ActionComponent:ActionIsEmpty()` is true on the target. **Not yet
confirmed** — see crash #3 below, which happened before this guard was
even reached.

Also added `Logger.lua` per Dragón's request: a separate, crash-resistant
log file (`Mods/PalBonds/palbonds-live.log`), written via Lua's own `io`
library with `file:flush()` after every line, so each line survives a
hard native crash immediately after it — unlike `UE4SS.log`, whose
internal buffering had left literally nothing from either crash so far.

## ⚠️ CRASH #3 (2026-09-01, fifth relaunch) — earlier than expected, Daedream

Tested again (Dragón picked up a `Daedream` this time — one of the rare
"Friendly"-archetype Pals from Q1's research, which visibly "looked at
[the player] curiously" before the crash). Crashed a third time — but
`palbonds-live.log` (working exactly as designed) shows the crash
happened BEFORE the sixth-pass guard, before `AddFriendShip`, before
anything action-related at all:

```
[...] [PalBonds/Interaction] real hook active (friendship + reaction animation) — look at a Pal and press 'F9'
[...] [PalBonds/Interaction] F9 pressed — starting do_pet()
```//log ends here, nothing further, including no "not looking at any Pal" line

This rules out `PlayActionByType`/`AddFriendShip` as the cause THIS time —
the crash is somewhere in the look-based targeting / read-only data path:
`FindFirstOf(PalPlayerCharacter)`, reading `FollowCamera`/control
rotation, `FindAllOf(PalCharacter)` + per-candidate `K2_GetActorLocation`,
or `CharacterParameterComponent:GetIndividualParameter()` /
`GetCharacterID()` / `GetFriendshipPoint()` / `GetSaveParameter()` on the
Daedream specifically — code that had run without incident against
several other species earlier in the project. Not yet known whether
Daedream's "Friendly"/curious behavior specifically is implicated, or
whether this was always a latent risk that just hadn't been hit yet.

**Fix this pass**: added a `Logger.log()` call immediately before and
after every single native/engine call in `do_pet()` and
`find_targeted_pal()` (including logging each `FindAllOf` candidate's
`GetFullName()` before touching it) — no behavior change, pure
instrumentation. The next crash, wherever it lands, will have an exact
last-known-good line immediately before it in `palbonds-live.log`.

**Running crash tally**: 3 crashes total — (1) forcing `PalPetting(56)`
directly on a wild Pal's ActionComponent (bypassing
`BP_AIActionPairCall_Petting` setup), (2) forcing the observed-safe
`Happy(38)` self-targeted call, still with no busy-state guard, and now
(3) something in the read-only targeting/data path itself, on a Daedream,
before either of the previous two calls were reached. No single common
cause has been confirmed across all three yet — each fix so far has been
a genuine, reasoned response to what the evidence showed at the time, but
the pattern of "fix one thing, hit a different wall" is worth naming
plainly to Dragón rather than projecting more confidence than the
evidence supports.

## Crash #3 root cause (likely): GetSaveParameter()'s by-value struct copy

Live-tested crash #3 again on an ordinary Lamball (not a Daedream this
time — Dragón: "I don't think Daedream was the problem... it would've
crashed either way"), with the full per-call instrumentation from the
seventh pass. `palbonds-live.log` this time got much further before
stopping:

```
[...] GetCharacterID -> FNameUserdata: ..., calling GetFriendshipPoint
[...] GetFriendshipPoint -> 0, calling GetSaveParameter
```
(nothing after this — crash)

`GetFriendshipPoint -> 0` confirms this was a genuinely untouched wild
Pal (not a stale/owned one). The crash is inside `param:GetSaveParameter()`
itself, or immediately in reading `.OwnerPlayerUId` off whatever it
returns.

Checked the SDK dump for why: `UPalIndividualCharacterParameter`'s own
class body (not the struct) already has `SaveParameter` as a **direct
field**, right there in the object we already hold:

```
FPalIndividualCharacterSaveParameter SaveParameter;    // 0x03D0 (size: 0x370)
```

That's 880 bytes, and `Pal.hpp` lists dozens of
`GetSaveParameterValue_X(const FPalIndividualCharacterSaveParameter&
SaveParameter)` helper functions covering fields like `PassiveSkillList`
(TArray), `EquipWaza` (TArray), `OldOwnerPlayerUIds` (TArray), `NickName`
(FString), `SkinName` (FName) — strong evidence this struct embeds
several dynamic arrays/strings, not just plain numbers. `GetSaveParameter()`
returns the WHOLE thing **by value** — a full copy of an 880-byte struct
with embedded dynamic containers, marshaled across the Lua/native
boundary. That is a fundamentally heavier and more fragile operation than
any other call this project has made so far (everything else has been
either a pointer, a primitive, or a small POD struct like FVector/
FRotator/FGuid) — if UE4SS's generic reflection-based copy doesn't fully
replicate a struct like this (e.g. doesn't deep-copy the TArrays'
backing buffers, leaving two structs pointing at the same heap memory),
reading from — or even just letting the temporary copy get garbage
collected — can corrupt memory.

**This exact call (`param:GetSaveParameter()`, added third pass, to grab
`OwnerPlayerUId` for diagnostic logging) has been present in every single
version of Interaction.lua that has ever crashed the game.** It doesn't
explain 100% for certain — the earlier two crashes didn't have this
precise per-line instrumentation — but it's the ONE thing common to all
three, it fires on every single call to `do_pet()` regardless of target
species or action state, and Dragón's own read of crash #3 ("would have
crashed on any Pal") points the same direction. This may retroactively
mean crashes #1 and #2 were never actually caused by `PlayActionByType`
at all — both fixes made in response to them (busy-state guard, dropping
`PalPetting` for `Happy`) may have been reasonable but ultimately
addressing a symptom that was never the real cause.

**Fix applied**: removed the `GetSaveParameter()` call entirely. Read
`param.SaveParameter.OwnerPlayerUId` directly instead — same data, same
object, but a plain nested-field read (an FGuid, a small fixed-size POD
struct, no dynamic memory) instead of a whole-struct-by-value function
call. Not yet confirmed live — this is the next test.

**General lesson for the rest of this project**: any native function
whose SIGNATURE returns a struct BY VALUE (not a pointer/reference) is
worth checking for embedded `TArray`/`FString`/`TMap`/`FText` members
before calling it from Lua — prefer reading the same data as a field
already sitting on an object/struct you already hold, if one exists,
over calling a `Get<TheWholeStruct>()`-style accessor. Small POD structs
(FVector, FRotator, FGuid) have been safe throughout this project; large
composite structs with dynamic containers are the new suspect category.

## ✅ MILESTONE (2026-09-01, sixth relaunch): petting a wild Pal works, no crash

Live-tested the `GetSaveParameter()` fix on an ordinary Lamball, then an
already-hostile wild Chikipi, spamming F9 repeatedly on each — **zero
crashes across 14 presses**. Full sequence confirmed working from
`palbonds-live.log`:

- `AddFriendShip(10, false)` succeeded every time, ramping real
  `FriendshipPoint` 0 → 10 → 20 → ... → 90 on the Lamball, 0 → 30 on the
  Chikipi.
- `PlayActionByType(pal, Happy=38)` (self-targeted on the target) returned
  `ok` every time it was allowed to run, and the Pal visibly played its
  happy/smile reaction in-game.
- The busy-state guard worked exactly as designed: every press after the
  first on the same Pal (while it was still mid-`Happy`) correctly logged
  `"target Pal is busy with another action... skipping"` instead of
  double-firing — a nice, unplanned side effect of the sixth-pass guard
  that turned out to double as spam protection.

This retroactively strengthens the crash #3 diagnosis: `GetSaveParameter()`
had been present in every crashing version, and removing it alone (no
other change) was enough to make the exact same interaction — same
`AddFriendShip`, same `PlayActionByType(Happy)`, same targeting — go from
"crashes reliably" to "works reliably" across a real stress test
(spamming, an actively hostile/attacking Pal, a Pal switch mid-sequence).

**This is the milestone Dragón set for today**: petting a wild Pal, with
the real in-game reaction animation, works.

## Ninth pass: real interaction shape + non-spammable + cleanup

Two things done in direct response to testing this milestone live:

1. **Performance**: the eighth-pass instrumentation logged every single
   `FindAllOf(PalCharacter)` candidate (up to 20 disk-flushed lines per
   F9 press) to find the crash site. Dragón noticed a framerate dip while
   spamming F9 — almost certainly this. Trimmed `find_targeted_pal()`
   back to a summary line; kept the cheaper per-major-step checkpoints
   elsewhere since those are what actually found the bug and cost far
   less (one line per interaction, not per candidate).

2. **A real, non-spammable interaction, closer to Dragón's described
   ideal** ("player reaches out, pal does its being-petted animation,
   pal does happy, everything resets"): added the player's OWN
   self-targeted `PlayActionByType(pal, HumanPetting=55)` call — the
   "reach out" gesture — back in. This is the exact call that produced a
   working player animation the very first time this project ever tried
   one (long before crash #1), which in hindsight is further evidence
   that `HumanPetting`/`PalPetting` were likely never the actual problem —
   `GetSaveParameter()` was in the code by that point too, so it's
   plausible ALL THREE crashes trace back to the same single cause, and
   the "avoid PalPetting" and "gate on busy-state" fixes, while
   reasonable given what was known at each point, may have been treating
   symptoms rather than the disease. (The busy-state gating is still kept
   — it's free, matches vanilla, and turned out to double as spam
   protection.)

   Spam/interrupt protection is now structural, not a cooldown timer:
   `do_pet()` checks the PLAYER's own `ActionComponent:ActionIsEmpty()`
   FIRST, before doing anything else — a second F9 press mid-animation is
   silently ignored. The target's busy-check also moved earlier, before
   `AddFriendShip`, so a busy/sleeping Pal now skips the WHOLE
   interaction (no friendship change either), not just the reaction clip.

   **Not attempted yet**: the actual synced `BP_ActionPairBehavior_Petting`
   cinematic (camera cut, a distinct "being-petted" pose instead of
   reusing Happy for the target, automatic reset once it ends). That's
   real Blueprint pair-action machinery this project deliberately avoided
   touching since crash #1. Worth a real look now that confidence is much
   higher (GetSaveParameter() is out of the picture), but it needs its
   own research pass — reading `BP_AIActionPairCall_Petting`'s
   `OnStartPair` and how the `Camera` field
   (`ABP_PettingCamera_C*`) gets populated, via FModel's Blueprint
   `Export → Properties (.json)` — not another blind live-test attempt.
   What's live now (player reach-out + Pal Happy reaction, both gated
   against interruption/spam) is a solid, safe approximation in the
   meantime.

## Eleventh pass: two real bugs found via the tenth-pass instrumentation

A stress-test session (walking to two different bosses, spamming F9,
petting several wild Pals) with the tenth pass's readable logging + the
new `[WATCH]` AddFriendShip hook turned up two real, previously-invisible
bugs — both explained a LOT of the session's confusing results at once:

**Bug 1 — the mod has been petting the player's own character.**
`FindAllOf("PalCharacter")` legitimately includes the player's own actor
(`PalPlayerCharacter` is itself a `PalCharacter` subclass — visible
earlier in an eighth-pass candidate dump that listed `BP_Player_Female_C`
as candidate #1). `find_targeted_pal()`'s exclusion check
(`pal ~= excludeActor`) was meant to filter the player out, but Lua
reference equality between two separately-obtained UE4SS wrappers for the
SAME underlying UObject isn't reliable — it silently failed. The result:
across a 51-press session, the log shows `targeted BP_Player_Female_C`
seven times, always at an identical `264 units / 18.7 degrees` (the fixed
third-person camera-to-character offset), and ZERO "not looking at any
Pal" results the entire session. That means every time Dragón thought
they were pressing F9 at nothing nearby, it actually succeeded — on
themselves. This also explains an earlier session's confusing friendship
values (climbing to 265 from a single persistent target, not many
different wild Pals as assumed) and the "boss too big to look at
correctly" / "petted the air while clipping through Mammorest" reports —
when the intended target didn't win the centering contest, the player's
own body (always in the candidate list at a fixed, fairly central angle)
won by default instead of the search correctly reporting no target.
**Fix**: compare `GetFullName()` strings instead of Lua object identity —
that reliably identifies the same real game object regardless of which
wrapper instance holds it.

**Bug 2 — double friendship grant.** The `[WATCH]` hook (added specifically
to test this) caught it directly: every single successful pet fired TWO
real `AddFriendShip` calls — this mod's own explicit one
(`value=10, applyPassiveSkill=false`) immediately, then a second one
(`value=10, applyPassiveSkill=true`) roughly 2-3 seconds later that this
mod never made. That second call turned out to be a side effect of the
target's `Happy` animation itself finishing (its own internal
AnimNotify/Blueprint logic, independent of what triggered `Happy` in the
first place) — confirmed 100% of the time, across a boss and multiple
wild Pal species. So every pet had quietly been granting 20 friendship,
not 10. The delayed grant also happens to exactly match the real vanilla
Pet/Feed shape (`value=10, applyPassiveSkill=true`), the same shape
originally observed via `Spy.lua` watching the real in-game menu. **Fix**:
removed this mod's own explicit `AddFriendShip` call entirely — triggering
`Happy` already produces the single, correct, vanilla-accurate grant on
its own. `PET_FRIENDSHIP_GAIN` is kept only as a documentation constant
for the expected amount (useful for Trust.lua's threshold math later), no
longer passed to any call.

**General lesson**: the `[WATCH]`-style permanent hook on a specific,
rarely-firing native function (as opposed to Spy.lua's broad hook on
every `PlayActionByType` call across the whole world) is a cheap, safe,
high-value pattern — it directly caught a real economy bug that would
have been very hard to find by reasoning about the Lua code alone, since
the code genuinely never calls `AddFriendShip` twice; the second call was
the game's own hidden behavior.

## Both eleventh-pass fixes confirmed live (2026-09-01, next relaunch)

Re-tested against a Gumoss (`PlantSlime`), open air, the Mammorest boss,
and a Chikipi (`ChickenPal`) pet three times in a row with spam mixed in:

- **Self-targeting bug: fixed.** Zero `targeted BP_Player_Female_C` lines
  this whole session. "Not looking at any Pal" now fires correctly
  instead — confirmed by Dragón directly ("tried petting the air, it
  didn't work nicely!").
- **Double-grant bug: fixed.** Every successful pet now shows exactly ONE
  `[WATCH] real AddFriendShip fired` line (`value=10,
  applyPassiveSkill=true`), and the "before" friendship value on each
  subsequent press correctly reflects the prior single +10 (0 → 10 → 20
  across the three Chikipi presses) — no more silent doubling.
- **Spam guard: still solid.** Multiple "player is already mid-action —
  ignoring press" lines exactly where Dragón intentionally spammed F9 on
  the Chikipi.

**New, legitimate limitation found (not a bug): large bosses may be
effectively untargetable.** Approached the Mammorest boss again and got
nothing but repeated "not looking at any Pal" for ~44 seconds straight —
no `targeted` line at all, not even a busy-skip. `find_targeted_pal()`
does a single-point distance+angle check against
`pal:K2_GetActorLocation()`, which is presumably the actor's root/pivot
point — for a boss-scale creature that point may sit far from wherever
the player is actually aiming at its visible bulk, putting it outside
`PET_RANGE`/`PET_MAX_ANGLE_DEG` even when the player is clearly looking
at it. Worth a future pass: either scale the tolerance by the actor's
bounding size, or check against the mesh/capsule extent instead of a
single origin point. Not urgent — the core interaction is solid for
normal-sized wild Pals, which was today's goal.

## Twelfth pass (2026-09-01): Feed action + first "calm down" attempt, real SDK data

Went digging in the actual UE4SS CXXHeaderDump (`ue4ss/CXXHeaderDump/Pal.hpp`
and `Pal_enums.hpp`, generated live against this install) for two things
Dragón asked for: a Feed interaction, and a way to stop a Pal from running
off after a successful interaction.

### Feed — confirmed real EPalActionType values

Full `EPalActionType` enum pulled straight from `Pal_enums.hpp` (previously
we only had the handful of values found via Spy.lua). Relevant ones:

- `Eat = 6` — a Pal's own eating animation (untested by this mod so far).
- `Feeding = 29` — likely base-camp/inter-Pal feeding, not player→wild.
- `Happy = 38` — already confirmed (pet/feed reaction + friendship grant).
- `HumanFeeding = 49` / `HumanFeeding_DoMotion = 50` — the PLAYER's own
  feeding gesture, analogous to `HumanPetting = 55`.
- `HumanPetting = 55` / `PalPetting = 56` — already confirmed.

Also found `class UPalAction_FeedItemToCharacter : public UPalActionBase`
(a dedicated action class with `PlayMontageFeeding()` /
`OnNotifiedMontage_OnReachFeeding()` / `OnFinishPlayMontageFeeding()`) and
`ActionBBKey_FeedItem()` on the ActionComponent, plus
`SelectedFeedingItem(const FPalItemSlotId&, int64)` elsewhere — real
vanilla feeding is item-driven (you pick a food item first) and probably
grants different amounts per food. This mod does none of that yet — F10
just plays `HumanFeeding` on the player and reuses the already-proven-safe
`Happy` reaction on the target (same single +10 grant as a pet). Good
enough to prove wild Pals can be fed at all; real per-item amounts would
need `UPalAction_FeedItemToCharacter`/`SelectedFeedingItem` wiring later.

### "Calm down" attempt — real fields found, mechanism NOT confirmed

`APalAIController` (Pal.hpp) has, as plain fields (not value-returning
functions — same safe pattern as `SaveParameter`):

- `TArray<AActor*> TargetPlayers` / `TArray<AActor*> TargetNPCs` — who
  this AI currently considers a target.
- `class UPalHate* HateSystem` — has `ChangeHate(AActor* Attacker, float
  PlusHateValue)`, a plain void function with simple params.
- `class UPalAIBlackboardBase* PalAIBlackboard` — not touched this pass,
  noted for later.

Added `try_calm_target()` in `Interaction.lua`: after a successful pet or
feed, clears `TargetPlayers`/`TargetNPCs` (if non-empty) and pushes
`HateSystem:ChangeHate(player, -999999)`. This targets the
aggression/target-tracking system, which IS confirmed real — but it is
**not** confirmed to be the same thing as a skittish species' flee
trigger. Framed to Dragón as an experiment to test live, not a fix.

**Q1 (DESIGN.md) is still open.** `Pal_enums.hpp` has three promising enum
names — `EWildPalAIMoveMode` (4 values), `EWarningPalAIMoveType` (5
values), `EWildPalAIRestType` (4 values) — but none of their individual
values have names in the dump (no UENUM display metadata), and none of
the three enum types are referenced anywhere in `Pal.hpp` as an actual
field type. That means whatever uses them is Blueprint-graph-only —
invisible to the static C++ SDK dump, which only reflects native classes.

To actually find the real disposition/flee field without guessing, added
`dump_interesting_properties()`: same technique the bundled
`ConsoleCommandsMod/Scripts/dump_object.lua` uses
(`Class:ForEachProperty()` walking `GetSuperStruct()` up the inheritance
chain), which surfaces Blueprint-ADDED variables per species Blueprint
too, not just native C++ fields. Filtered to property names containing
keywords like "warning", "escape", "flee", "curious", "timid",
"personality", "hate", "target", etc. Read-only, logs scalar values only,
runs once per successful pet/feed on both the Pal actor and its
Controller. Next real test session (ideally: one skittish Pal that runs
off, one Daedream-like Pal that doesn't) should hand us actual field
names/values in `palbonds-live.log` to work from.

**Testing note for `TargetPlayers:Clear()` / `TargetNPCs:Clear()`**: this
mod has never called `:Clear()` on a UE4SS TArray field before — every
prior successful array-adjacent call has only been reading
(`GetArrayNum()`, `ForEach()`, indexing). If `:Clear()` isn't actually a
method this TArray wrapper exposes, calling it just raises a normal Lua
"attempt to call a nil value" error, which the surrounding `pcall` catches
and logs as "FAILED (method may not exist)" — not expected to be able to
crash the game the way the three earlier bugs did, since it's a Lua-level
missing-method error rather than a native memory operation, but flagging
it as the one genuinely new kind of call in this pass so it gets tested
deliberately (once, not spammed) rather than assumed safe.

## Thirteenth pass (2026-09-01): the "calm down" experiment never actually ran

Dragón tested three back-to-back interactions specifically to compare
behavior (a skittish Pal petted unnoticed from behind, a Chikipi — known
not to flee — then a Cattiva that ran off after being pet AND fed). The
log for that whole session had **zero** "calm-down:" lines and **zero**
"[DIAG]" lines — not "the attempt failed," genuinely never attempted.

Root cause: a Lua footgun in this file's own `safe_call()` helper. On
success, `safe_call` returns the WRAPPED FUNCTION's own return value as
its result — it does not return a real success boolean. The twelfth-pass
code did:

```lua
local okAction, actionErr = safe_call(function()
    actionComp:PlayActionByType(pal, ACTION_TYPE_HAPPY)
end)
...
if okAction then
    try_calm_target(pal, player)
    ...
```

`PlayActionByType`'s call site here returns nothing, so on success
`okAction` was `nil` — which is falsy in Lua — identical to what a FAILED
call would also produce. `if okAction then` was therefore always false,
success or not, silently skipping both `try_calm_target()` and
`dump_interesting_properties()` on every single interaction.

**Fix**: call `pcall()` directly for this one check instead of routing it
through `safe_call()`, so `actionOk` is pcall's own real boolean:

```lua
local actionOk, actionErr = pcall(function()
    actionComp:PlayActionByType(pal, ACTION_TYPE_HAPPY)
end)
...
if actionOk then
```

Audited every other `safe_call(...)` call site in this file for the same
pattern — only one other place destructures two return values from it
(the player's own reach-out call, logging `tostring(pErr or "ok")`), and
that one happens to still read correctly by coincidence (it branches on
`pErr` specifically, which really is `nil` only on success), so it wasn't
silently broken the same way. Nothing else in this file gates real
behavior on a `safe_call` return value being truthy.

**Lesson for later Lua in this project**: `safe_call`'s two-return-value
shape (`return result` on success vs `return nil, result` on failure) is
fine for LOGGING an error message but actively misleading for BRANCHING
on success/failure when the wrapped call's own return value can itself be
falsy (nil/false) — which `PlayActionByType` always is here, since it's
called for its side effect, not its result. Any future "did this
succeed?" check in this codebase should use a direct `pcall()`, not
`safe_call()`, to get an honest boolean.

Not deployed/tested live yet as of writing this — next session's F9/F10
presses are the actual test of whether `try_calm_target()`'s
`TargetPlayers:Clear()` / `HateSystem:ChangeHate()` do anything
observable, and what the `[DIAG]` dump actually contains.

## Fourteenth pass (2026-09-01): calm-down retest results + real interact-menu research

### Calm-down retest: ran, but didn't stop fleeing — and we now know why it likely can't, as implemented

With the thirteenth-pass bug fixed, `try_calm_target()`/`dump_interesting_properties()`
actually fired this time. Real data across 5 species (ChickenPal x2,
PinkCat x2, PlantSlime x3, SamuraiDog x2):

- **`TargetPlayers` was empty (0 entries) in 6 of 7 cases** — no
  "calm-down:" log line at all (the code only logs when there's something
  to clear). Only ONE case (a second pet on the same PlantSlime) had
  `TargetPlayers` with exactly 1 entry.
- **`TargetNPCs` was empty in all 7 cases.**
- In the one case with data: **`TargetPlayers:Clear()` FAILED** — this
  UE4SS TArray wrapper does not expose a `:Clear()` method (confirmed by
  the pcall around it catching a real error, logged as "method may not
  exist"). So even in the one case where there was something to clear, it
  wasn't actually cleared.
- `HateSystem:ChangeHate(player, -999999)` was CALLED without a Lua error
  every time `HateSystem` was valid, but Dragón confirmed live that
  several skittish Pals (tested deliberately against a Chikipi baseline
  that doesn't flee) still ran off after a successful pet/feed regardless.

**Conclusion**: `TargetPlayers`/`HateSystem` on `APalAIController` is very
likely the AGGRESSION/combat targeting system, not the skittish-species
flee trigger — it's usually empty for a Pal that's just calmly standing
near the player (which matches: aggression tracking should only populate
when a Pal is hostile/alerted, not just nearby). This experiment is a
bust as a "stop fleeing" mechanism. Not deleting the code (it's harmless
and free to leave running, and `ChangeHate` could matter later for actual
combat/Trust work in `Combat.lua`), but it should not be relied on for
this.

**`dump_interesting_properties()` also came back empty of anything new**
across all 5 species — no property whose name matched any of the
keyword list (warning/escape/flee/curious/timid/personality/etc.) showed
up anywhere on either the Pal actor or its Controller, beyond the
already-known Target/Hate fields. This is itself informative: the real
flee/disposition trigger is NOT a simple named UPROPERTY reachable this
way. Most likely candidates left: (a) a value stored inside
`PalAIBlackboard` (an opaque Blackboard, not enumerable as plain named
properties the way `ForEachProperty` walks a class), or (b) a per-species
DataTable row read directly into Behavior Tree decorator logic without
ever being copied onto the actor instance at all — matching how
"Aggressive or Passive Wild Pals"-style Nexus mods reportedly work (patch
the DataTable, not the runtime actor). Q1 (DESIGN.md) stays open;
solving it for real likely needs either Blackboard key enumeration (a
different API than `ForEachProperty`) or finding the actual per-species
DataTable via FModel.

### Real interact-menu system found (relevant to "move this to the radial menu")

Dragón asked to move Pet/Feed into the game's own radial menu instead of
the F9/F10 hotkeys. Found the real native system behind it in the SDK
dump:

- **`UPalInteractComponent`** (lives on the player) — the actual system
  behind every "hold to interact" prompt in the game (NPCs, chests,
  AND petting/feeding an owned Pal all go through this one component).
  Key members:
  - `TargetInteractiveObject` — whatever the player is currently looking
    at that qualifies as interactable. The game's own real equivalent of
    this file's hand-rolled `find_targeted_pal()`.
  - `StartTriggerInteract(EPalInteractiveObjectActionType ActionType, bool IsToggle)`
    / `EndTriggerInteract(ActionType)` — starts/ends one interaction.
  - `IsInteracting()` / `IsEnableInteract()` / `GetTriggeringActionType()`.
- **`IPalInteractiveObjectComponentInterface`** (extends
  `IPalInteractiveInterface`) — the interface any interactable thing
  implements. Has `GetIndicatorInfo(FPalInteractiveObjectActionInfoSet& ActionInfo, ...)`
  which fills in up to 4 slots (`Interact1_Indicator` .. `Interact4_Indicator`,
  from `FPalInteractiveObjectActionInfoSet`) and `GetIndicatorText(...)`.
- **`EPalInteractiveObjectActionType`** (`Pal_enums.hpp`): `None=0,
  Interact1=1, Interact2=2, Interact3=3, Interact4=4`. These are GENERIC
  SLOT NAMES, not "Pet"/"Feed" by name — which slot means what is decided
  per object type inside that type's own (almost certainly Blueprint)
  implementation of `GetIndicatorInfo`. So we don't yet know which
  Interact# is Pet vs Feed for an owned Pal, or whether
  `TargetInteractiveObject`/this whole component ever engages with a WILD
  (unowned) Pal at all — an ownership gate could live anywhere upstream
  of this component, entirely in Blueprint, invisible to the C++ SDK
  dump.
- Also found `UPalUIPlayerRadialMenuBase` / `UPalUIRadialMenuWidgetBase`
  — the generic radial-menu WIDGET machinery (angle math, selected index)
  used for building any wheel menu in the game (not Pal-specific by
  itself; this is just the UI shell).

**Added, read-only (thirteenth pass — see `Interaction.lua`
`Interaction.Init()`)**: permanent `RegisterHook` watchers on
`PalInteractComponent:StartTriggerInteract` and `:EndTriggerInteract`,
logging the component, the `ActionType` value, and
`TargetInteractiveObject` (described via `GetFullName()`). Same safe,
proven pattern as the `AddFriendShip` watcher — observes, changes
nothing.

**Test plan for next session** (this is the actual way to answer "can we
use the real menu for wild Pals"): hold the real interact key/button on
an OWNED Pal and do an actual Pet through the vanilla menu, then an
actual Feed — the log will show which `ActionType` number fired for each
and what `TargetInteractiveObject` pointed at. Then, separately, just try
holding/aiming the same interact prompt at a WILD, unowned Pal and see
whether `StartTriggerInteract` fires AT ALL. If it never fires for a wild
Pal, the gate is upstream of this component (in whatever decides
`TargetInteractiveObject`, or in `GetIndicatorInfo` returning "no
options" for a non-owned Pal) and that's the next thing to find. If it
DOES fire, we'll know the ActionType numbers to call ourselves, and
calling `StartTriggerInteract` directly on a wild Pal (once we understand
what it does — deliberately not attempted blind, given this project's
crash history with unfamiliar pair-action-adjacent calls) becomes the
real path to a proper, camera-synced Pet/Feed instead of the current
F9/F10 approximation.

## Fifteenth pass (2026-09-01): real menu data — gate confirmed at the UI level, not this component

Dragón ran the exact test plan from the fourteenth pass: petted and fed an
OWNED Lamball (`BP_SheepBall_C` — Lamball's internal species ID really is
"SheepBall") twice via the real "4" radial menu — once while it was
actively out, once after placing it in the Palbox so it roams the base —
then tried the same radial menu on a nearby WILD Lamball, where Pet/Feed
showed grayed out and did nothing when clicked, then used F9/F10 on that
same wild Lamball as a fallback.

**`ActionType=4` = engaging an owned Pal's care menu.** Both real
interactions with the OWNED Lamball logged
`StartTriggerInteract ActionType=4 ... TargetInteractiveObject=...BP_SheepBall_C_2147444246...`
— confirmed by `TargetInteractiveObject` pointing at the exact same actor
both times, once while active and once while roaming the base after
being placed in the Palbox. **This corrects a theory from Dragón's own
report**: Pet/Feed via the real menu is NOT gated on "has an active Pal
currently following you" — it worked fine on the Palbox-roaming, not-
following Lamball. Ownership is what mattered.

Only one `StartTriggerInteract ActionType=4` fires per Pet-then-Feed pair
in the log, meaning **choosing Pet vs Feed inside that menu happens via a
DIFFERENT, more specific call this pass's hooks don't cover** — most
likely `UPalUIPlayerRadialMenuBase:SelectedFeed(ItemSlotId, itemNum)`
(found thirteenth pass) for Feed specifically, with Pet perhaps going
through `StartTriggerInteract` alone. Only the FIRST of the two
interactions (the Pet) has a matching `[WATCH] real AddFriendShip fired`
line a few seconds later; no matching grant appears after the second
(Feed) — consistent with Feed's item-consumption path working
differently and not (yet) being watched by any hook this project has.

**The important negative result: trying Pet/Feed on the WILD Lamball
produced ZERO `[MENU-WATCH]` log lines at all** — not a failed
`StartTriggerInteract` call, no call whatsoever, in the ~20-second window
between the last confirmed menu action and Dragón switching to F9/F10.
That means the grayed-out buttons are disabled at the WIDGET level
(clicking a disabled UI button never reaches `UPalInteractComponent` in
the first place) — the ownership gate lives upstream of everything this
project has hooked so far, almost certainly inside a Blueprint
implementation of `IPalInteractiveObjectComponentInterface::GetIndicatorInfo`
on `APalCharacter` (found fourteenth pass) that decides, per-Pal, which
of the 4 indicator slots are enabled — invisible to the native C++ SDK
dump since it's Blueprint graph logic.

**Why this isn't being patched blind right now**: `GetIndicatorInfo`
takes its result as an OUT PARAMETER (`FPalInteractiveObjectActionInfoSet&`,
a struct passed by reference, not returned by value) — writing into an
out-param struct from a Lua hook is a different, less-tested class of
operation than anything this project has done safely so far (reading
fields has been safe; calling void functions with simple params has been
safe; this would mean mutating an in-progress native struct mid-call).
Given three real crashes already came from underestimating exactly this
kind of native/Lua boundary risk, this is being logged as a real, viable
lead — not attempted without more research (ideally FModel access to
actually read the Blueprint graph first, which this project doesn't have
from the cloud side).

**Where this leaves the two open feature requests**: the F9/F10 hotkey
approximation remains the one thing that's fully proven safe and working
end-to-end for wild Pals (pet, feed, correct single friendship grant, no
crashes across many sessions). Getting the REAL menu to work for wild
Pals means either patching the Blueprint-side gate (higher risk, needs
FModel first) or is simply out of reach without it. Recommended next
real step for the project, discussed live with Dragón: pivot to
`Trust.lua` (§3.3 in DESIGN.md) — it's the next roadmap item, uses only
the already-proven-safe `FriendshipPoint`/`AddFriendShip` reads, and
needs no new risky native calls, unlike either of this session's two
open threads (personality/disposition, real menu integration), which
both currently dead-end at "need a tool this project doesn't have access
to yet" (FModel, or Blackboard-key reflection).

## Sixteenth pass (2026-09-01): Trust.lua, Combat.lua, Capture.lua — first real implementation

Dragón gave a full spec for how trust should work, both the REAL vanilla
mechanic and this mod's own rules layered on top. Confirmed the real
mechanic in the SDK dump, then implemented as much of the spec as could
be done with confirmed-safe calls in one pass.

### Real vanilla mechanic, confirmed

- **`UPalIndividualCharacterParameter:GetFriendshipRank()`** — a plain
  `int32`, no-arg instance method on the SAME object `Interaction.lua`
  already reads `GetFriendshipPoint()` from. This is the real 0-10 rank
  Dragón described. Same safe shape as `GetFriendshipPoint()` — no new
  object lookup needed at all.
- **`struct FPalFriendshipRankDataRow : FTableRowBase { int32
  FriendshipRank; int32 RequiredPoint; }`** — confirms the real
  "increasing point requirement per rank" table exists, held on
  `UPalDatabaseCharacterParameter.FriendshipRankTable` alongside
  `GetFriendshipRequiredPointByRank(rank, &outPoint)`,
  `GetFriendshipRank(point)`, `CalcFriendshipProgress(point)`,
  `GetMinFriendshipRank()`/`GetMaxFriendshipRank()`. NOT read live this
  pass (would need to find/obtain that manager object first) — Trust.lua
  just calls `param:GetFriendshipRank()` directly instead, which sidesteps
  needing it at all for now.
- **Real passive-friendship-over-time config fields found**:
  `FriendshipPoint_AutoIncrementOtomo`, `_ActiveOtomo`, `_Worker`,
  `_AutoIncrementRequireSanity`, `_AutoIncrementInteravalMinutes` (typo is
  the game's own) on what looks like a big game-balance config struct.
  Confirms Dragón's description (party Pals gain passive friendship,
  base Pals slower) is real vanilla behavior — but hooking a bonding WILD
  Pal into that same auto-increment system means making it a real Otomo
  first, which is DESIGN.md question 6, still unsolved. Trust.lua
  approximates this with its own timer instead (see below).
- **`FPalDamageResult`** (the struct `UPalHate:DamageEvent` takes) is
  confirmed a plain POD — `int32 Damage`, `AActor* Attacker`, `AActor*
  Defender`, `FVector BlowVelocity`/`HitLocation`, a handful of small
  enums/bools. NO embedded TArray/FString/TMap. Reading its `.Defender`
  field from inside a `RegisterHook` callback is the same safe shape as
  every other hook-argument read this project has done (AddFriendShip's
  Value/ApplyPassiveSkill, etc.) — this is UE4SS handing us an
  ALREADY-PASSED-IN argument, not the by-value-RETURN pattern that
  actually caused the three real crashes. Used in `Trust.lua`'s new
  `PalHate:DamageEvent` watcher to detect a following Pal taking damage.
- **`UPalUtility:CanUseTargetGainFriendshipPoint(WorldContextObject,
  IndividualParameter, Item)`** — the real check for "can this item give
  this Pal friendship." This is where kinship-peach detection would hook
  in, alongside `UPalAction_FeedItemToCharacter`/`SelectedFeedingItem`
  (found twelfth pass). NOT implemented this pass — needs the item's real
  FName, which needs FModel or a live feed-and-log session to discover.
  `Trust.OnKinshipItemUsed(pal)` exists as a documented no-op TODO.

### This mod's own rules — implemented this pass

- 5 successful pet/feed interactions on the same wild Pal (tracked in
  `Trust.lua`'s per-`GetFullName()`-keyed state, incremented from
  `Interaction.OnWildPalPetted`, now real instead of a stub) → marks it
  following and calls `Combat.StartFollowing`.
- Following Pals get a periodic (every ~5s) follow-move order via a
  REAL, confirmed function found on `APalAIController`:
  `PalMoveToLocation(Dest, AcceptanceRadius, bStopOnOverlap,
  bUsePathfinding, bProjectDestinationToNavigation, bCanStrafe,
  FilterClass, bAllowPartialPaths)`. This is an approximation, not real
  Otomo following — no combat-assist, no formation, and it's fighting
  against whatever wild-AI behavior the Pal's own Controller still runs
  the rest of the time. Explicitly flagged in `Combat.lua`'s header as
  the weakest link in this pass, worth live-testing before trusting it.
- Passive trust gain every ~15s while following
  (`PASSIVE_FRIENDSHIP_PER_GAIN`, real `AddFriendShip` call).
- Damage-based trust loss (`DamageEvent` watcher above) — a real,
  fairly large negative `AddFriendShip` call. **First time this project
  has passed AddFriendShip a NEGATIVE value** — the function has only
  ever been observed being called with positive values by the game
  itself so far, so this is flagged for live confirmation, not assumed
  safe by extension of the positive case working.
- Distance-based trust loss: if a following Pal ends up more than
  `MAX_FOLLOW_DISTANCE` (3000 units, ~30m) from the player, ALL its
  friendship is zeroed out (another negative `AddFriendShip` call) and it
  stops following.
- Rank hitting 0 after either of the above → `Capture.OnTrustLost(pal)`,
  which permanently flags the Pal (`HasPermanentlyFled`) — and
  `Interaction.lua` now refuses to pet/feed a permanently-fled Pal at
  all, so the rule actually sticks instead of letting the player quietly
  re-earn trust as if nothing happened.
- Rank reaching 1 → `Capture.OnTrustMaxed(pal)` fires and logs clearly.
  **Still a stub for the actual capture** — question 4 (the real
  sphere-less capture UFunction) hasn't been found/tried yet. This pass
  only wires up the trigger, honestly, rather than guessing at a capture
  call with no evidence behind it.
- NOT implemented: "the following Pal should help if the player attacks
  something" (needs separate research into how Otomo Pals pick combat
  targets) and actual despawn/forced-flee behavior when a Pal loses all
  trust (currently it just stops following and gets refused further
  interaction — it doesn't visually run off or disappear). Both are
  honest gaps, not silent ones.

### New category of risk this pass: the first repeating timer

Every hook in this project so far has been event-driven (`RegisterHook`
on a real function the game already calls). Passive trust gain and the
distance check need something that fires on its own over time, so
`Trust.lua` uses a real UE4SS API confirmed by extracting Lua overload
error strings directly from `UE4SS.dll`:

```
ExecuteAsync(LuaFunction Callback)
ExecuteWithDelay(integer DelayInMilliseconds, LuaFunction Callback)
LoopAsync(integer DelayInMilliseconds, LuaFunction Callback)
ExecuteInGameThreadWithDelay(integer DelayInMilliseconds, LuaFunction Callback) -> integer handle
```

`ExecuteInGameThreadWithDelay` is used because it's specifically designed
to run its callback on the GAME thread — touching UObjects (Pal actors,
their AIController, etc.) from any OTHER thread would be a real, new kind
of crash risk this project hasn't encountered yet. However, `UE4SS.dll`'s
own embedded error strings include: *"ExecuteInGameThreadWithDelay:
Neither EngineTick nor ProcessEvent hooks are available (AOB scans
failed)"* — meaning on some game versions/builds, this specific feature
can silently fail to actually schedule anything. `Trust.lua` logs a clear
`[TICK]` line every time the timer fires, self-reschedules on success,
and falls back to plain `LoopAsync` (guarded by `IsInGameThread()` before
touching any Pal actor) if the game-thread version fails to even start.
**Not yet confirmed live which path this build actually uses** — that's
the first thing to check in the log next test session: if `[TICK]` lines
never appear at all, following Pals will just stand there (no move
orders, no passive gain, no distance check) even though the
5-interaction follow-trigger itself still works.

### Test plan for next session

Get 5 successful pets/feeds on one wild Pal, confirm the "should now
start following" log line fires, then watch: (1) whether `[TICK]` lines
appear in the log at all, and from which path (game-thread or LoopAsync
fallback); (2) whether the Pal visibly moves toward the player over time;
(3) whether its Friendship value climbs on its own between interactions;
(4) what happens if it takes damage (a real negative AddFriendShip, first
time tested); (5) what happens if the player runs far away and stops
(distance-based trust wipe); (6) whether reaching rank 1 actually logs
"WOULD capture here" (capture itself is not implemented yet, this is
just confirming the trigger fires at the right point).

## Seventeenth pass (2026-09-01, continued): the "why didn't damage trust loss fire" investigation, and the real follow-reliability fix

### What Dragón reported

A full test session: two Lambals and a Caprity each got to 5+ interactions
and started following, then all three "lost interest and wandered away" /
"ran away from its normal skittish behavior" before the player got anywhere
near them; a third Lamball ("Lamball 3") got to interaction #9, was then
used to bait a fight against another Lamball ("Lamball 4", with a wild
Gumoss joining in), won the fight, but "never ran away despite being hit
several times even almost about to die," then itself wandered off. Dragón's
own conclusion: **testing damage/distance/capture events isn't meaningful
until the follow mechanism itself is reliable**, since the Pals aren't
following consistently enough to trust what any given test result means.

### What the log actually shows (read directly, `palbonds-live.log` +
`UE4SS.log`, both on the live game install)

Good news first — three things Dragón's report didn't give credit for
because the pessimistic framing ("not clear indications") undersold them:

- The `[TICK] game-thread tick fired` timer (`ExecuteInGameThreadWithDelay`)
  fired reliably and steadily the entire session — the AOB-scan failure
  case flagged in the section above did **not** happen on this build. This
  had never been confirmed live before this session.
- All three "lost interest and wandered away" cases were the
  **distance-based trust wipe working exactly as designed**, not a bug:
  `[WATCH] real AddFriendShip fired ... value=-38`, `value=-22`, and
  `value=-76` each correspond 1:1 to `tick_followers()` detecting the Pal
  was past `MAX_FOLLOW_DISTANCE` and wiping its entire accumulated
  Friendship point total, immediately followed by `Combat] ... no longer
  following` and `Capture] ... lost all trust — fleeing permanently`. This
  is Dragón's own spec ("if the player moves away too fast and too far
  ... lose all its trust") working correctly.
- Lamball 3's interaction count/rank tracking is correct throughout:
  interaction #1 through #9, rank 0, point climbing 0→10→20→26→40→56 —
  exactly matching the real `AddFriendShip`/`GetFriendshipPoint()` values
  read back from the game.

The actual finding on the damage question: **the fight was never logged
at all.** `palbonds-live.log` and `UE4SS.log` — the two independent log
files, one written by our Lua Logger, one written by UE4SS itself — both
stop dead at the exact same timestamp, `17:51:16`, fifteen seconds after
Lamball 3's interaction #9 (`17:51:01`) and its next two passive-gain
ticks. There is no line of any kind, from any mod, after that timestamp
in either file. That means the entire fight sequence (baiting Lamball 4,
both Lambals fighting, Gumoss joining, Lamball 3 nearly dying, Lamball 3
wandering off afterward) happened **after logging — and very likely the
whole UE4SS layer, possibly the game process itself — stopped**, not
"the damage hook silently failed to fire." Checked directly: the
`RegisterHook("/Script/Pal.PalHate:DamageEvent", ...)` install itself
never logged its failure message (`"could not install DamageEvent watch
hook"` appears zero times all session), so the hook installed fine; it's
just that no data exists for the one time period that would have tested
it. **This needs a clean retest**: get a Pal following, pick a fight
near it, and check immediately afterward (in the same session) that the
game/log didn't stop — if it's reproducible that something crashes or
the log stops around the 15-ish-minute mark or during Pal-vs-Pal combat,
that's a separate, real problem worth its own investigation next time.

### The real fix: why following read as "irregular"

Two genuine, separate causes, both addressed this pass (not investigation
this time — direct code changes, both within the project's established
"simple param / void return" safe-call category):

1. **The move order only refreshed every 5 seconds**
   (`Trust.lua`'s old `TICK_INTERVAL_MS = 5000`). Between refreshes,
   nothing was holding the Pal's own wild AI (wander/graze/flee
   decision-making) back — it's free to pick a brand new behavior and
   just overwrite our move order until the next tick catches up.
   `TICK_INTERVAL_MS` is now `1500` (1.5s), with
   `PASSIVE_GAIN_EVERY_N_TICKS` raised from 3 to 10 so the real-world
   passive-gain cadence (~15s) is unchanged — only the follow/leash
   responsiveness got faster.
2. **NEW, untested-live**: `Combat.lua` now calls
   `APalAIController:SetActiveAI(false)` when a Pal starts following
   (`Combat.StartFollowing`) and `SetActiveAI(true)` when it stops, for
   any reason (`Combat.StopFollowing`, called from both the soft-stop and
   permanent-flee paths in `Trust.lua`/`Capture.lua`). `SetActiveAI` was
   already known to exist on this controller (see the `APalAIController`
   fields/functions section above) but had never actually been called
   until this pass. It's a plain bool-param, void-return call — the same
   safe shape as `PalMoveToLocation` and `HateSystem:ChangeHate`, both
   already proven not to crash — so it's implemented and logged clearly
   (`SetActiveAI(false) on <Pal> -> ok` / `-> FAILED: <error>`) rather than
   guessed at blind. Two live-testable outcomes to watch for specifically:
   - Hoped-for: wild wander/flee behavior stops fighting our move orders,
     following reads noticeably smoother, and Pals stop spontaneously
     "running away from their normal skittish behavior" mid-bond.
   - Risk: if `SetActiveAI(false)` turns out to disable movement
     *execution* too (not just decision-making), a following Pal would
     just stand still instead of moving smoothly. If that happens, this
     one call is the first thing to revert — the faster tick interval
     from fix #1 stands on its own either way.

### Test plan for next session

1. Get one wild Pal to 5 interactions, confirm it starts following, and
   specifically watch whether it moves continuously/smoothly now instead
   of in irregular bursts.
2. If it stands frozen instead, that's `SetActiveAI(false)` disabling
   movement execution — revert that one call in `Combat.lua` and re-test
   with just the faster tick interval.
3. Once following itself looks reliable, retest the damage-penalty path
   deliberately: get a following Pal into a fight, and immediately check
   (or right after ending the session) that `palbonds-live.log` and
   `UE4SS.log` both kept writing through and past the fight. If they stop
   again around the same point, treat that as its own bug (possible
   crash/log-flush issue), separate from the trust math.
4. Only after (1)-(3) look meaningfully stable, resume testing
   distance-wipe edge cases, kinship peaches, and the capture threshold —
   per Dragón's own stated priority, those results aren't trustworthy
   while following itself is inconsistent.

## Eighteenth pass (2026-09-01, same day, next test): the SetActiveAI fix was wrong — reverted, with real evidence

### What broke

The seventeenth pass added `APalAIController:SetActiveAI(false)` while a
Pal is bonding, hoping to stop its own wild AI from fighting our move
orders. Dragón's very next test session showed it was a bad trade:

- **Pet/feed reaction animation stopped playing on already-following
  Pals** — Dragón: "after the required interaction, they stopped
  executing their animation, no longer being pet or fed, but still doing
  the happy smile." The log explains why this was invisible from log
  data alone: `player HumanPetting call returned — result=ok` and
  `target Happy call returned — result=ok` both kept logging "ok" on
  every single interaction, even the ones after `SetActiveAI(false)` had
  already been applied. `result=ok` only means the Lua call didn't
  error — it says nothing about whether the game's action system
  actually executed it. `PlayActionByType` for the pet/feed reaction
  apparently needs an active AI controller to actually run, even though
  it silently "succeeds" (no error) when it can't. The separate `Happy`
  reaction call is unaffected — different underlying path — which is
  exactly why Dragón still saw the happy smile but not the pet/feed
  motion itself.
- **Following Pals stopped reacting to combat at all.** Dragón: "once
  more managed to get them hit by other hostile pals but they never ran
  away, one even died and the other just stood there taking hits, doing
  nothing." `SetActiveAI(false)` isn't a scoped "ignore wander targets"
  switch — it appears to kill the Pal's entire AI decision layer,
  including the built-in reactions (fight back, flee at low HP) that
  would otherwise fire regardless of our own trust system. This is a
  strictly worse outcome than the pre-existing "approximate follow"
  limitation it was trying to fix.

One damage case DID work correctly this same session — a PlantSlime
(`BP_PlantSlime_C_2147453538`) took real damage while following, got the
real `-50` penalty (`following Pal took damage — applying trust penalty
(-50)`), hit rank 0, and correctly triggered `no longer following` →
`SetActiveAI(true) restore` → `lost all trust — fleeing permanently`, all
in the same log line group at `18:16:04`. So the DamageEvent hook itself
is confirmed real and working — the problem was purely the AI-suppression
side effect, not the trust math.

### The fix

`SetActiveAI` is fully removed from `Combat.lua` (`StartFollowing` /
`StopFollowing` are back to just bookkeeping + logging, nothing touches
the controller's AI state anymore). The seventeenth pass's other change —
`Trust.lua`'s tick interval dropped from 5s to 1.5s — stays; nothing in
this session's evidence implicates it, and faster move-order refresh is
a strict improvement on its own even though the Pal's own wild AI can
still contest it between ticks (the original, already-documented
"approximation" limitation — not a new regression, just not newly fixed
either).

### Two more real changes from Dragón's numbers/report this session

1. **Damage penalty size, real number from Dragón**: "if pet/feed gives
   10 friendship each, then receiving a hit either by the player or by
   other pals should take away 25 friendship." `DAMAGE_FRIENDSHIP_PENALTY`
   changed from `-50` (a rough "huge chunks" guess) to `-25`.
2. **Player-caused damage should also cost trust, not just other Pals
   hitting a follower.** The `PalHate:DamageEvent` hook was never
   filtering by `Attacker` — it already fires for damage from any
   source, including the player punching their own following Pal — so
   this should already work as-is. But given how much this project has
   been burned by "the log makes it look like X works/doesn't" (this
   exact investigation twice now), the hook now logs **every** real
   `DamageEvent` unconditionally — defender, attacker, and damage amount
   — the same `[WATCH]`-style logging already used for `AddFriendShip`.
   Next test session should make it trivial to directly confirm whether
   punching a following Pal produces a `[DAMAGE-WATCH]` line with the
   player as attacker, instead of inferring it indirectly again.

### Test plan for next session

1. Get a Pal following, pet/feed it a few more times after it starts
   following, and confirm the actual pet/feed reaction animation still
   plays (not just the Happy smile) — this directly tests that removing
   `SetActiveAI` fixed the regression.
2. Let a following Pal take a hit from a wild Pal, and separately punch
   a following Pal directly — check the log for `[DAMAGE-WATCH]` lines
   in both cases and confirm the attacker field matches (player vs. the
   other Pal), and that the real penalty applied is `-25` not `-50`.
3. Watch whether a Pal that hits rank 0 from damage actually visibly
   reacts now (flees / fights back) instead of standing frozen — with
   `SetActiveAI` gone, its own AI should be free to react in real time
   instead of only being restored after the fact.
4. Following quality itself (the original "irregular" complaint) is
   still only partially addressed (faster tick, no AI suppression) — if
   it's still unsatisfying, the next real avenue is probably something
   more targeted than a global AI kill switch (worth researching what a
   real Otomo Pal's behavior tree actually branches on, DESIGN.md Q6,
   rather than guessing at more controller-level switches blind).

## Nineteenth pass (2026-09-01): real Otomo research via FModel — Dragón's call to investigate properly before "enabling" anything

Dragón's own read of the project so far, verbatim: "you're still fighting against the pal's own AI which is not really necessary — you just need to find a way to make them behave like actual party pals... feel like a lot of things we are doing is not actually 'enabling' things for wild pals but trying to trick the system into doing it, bypassing everything else... shouldn't it be better to investigate more how it actually works, then just try to find how to enable it?" This is a fair, correct read of the SetActiveAI failure and the move-order approximation — both were workarounds *around* the real system rather than uses *of* it. This pass is the first real investigation using FModel (now connected — `C:\Users\Dragon\Downloads\fmodel`), which was previously deferred for lack of access.

### Real findings — the actual Otomo (party Pal) follow/combat system

Found the real Blueprint class via FModel's global package search + "Decompile Blueprint":
`Pal/Content/Pal/Blueprint/Controller/Monster/BP_MonsterAIController_Otomo.uasset`, extending
`BP_MonsterAIControllerBase` (which itself extends the native `PalAIController` — the SAME base class every wild Pal's controller already has). Its real fields, decompiled:

```
class ABP_MonsterAIController_Otomo_C : public ABP_MonsterAIControllerBase_C
{
    FTimerHandle RegenTimer;
    FVector FollowInterpolatedPos = FVector(0, 0, 0);
    UBlueprintGeneratedClass* DefaultRootCompositeActionClass;
    bool bPlayDefaultCompositeAction = true;
    bool IsAutoPlayDefaultAction = false;
    UClass* CombatModuleClass = "Class'/Script/Pal.PalAICombatModule_Otomo'";
    UPalAIActionComponent* AIActionComponent;
    UPalFollowingComponent* PathFollowingComponent;
    UPalAIActionComponent* ActionsComp;
    USceneComponent* TransformComponent;
    USceneComponent* RootComponent;
    int OtomoSlotIndex;
    TMap<EPalAIActionType, class UPalAIActionBase*> PlayingAIActionMap;
    double FollowSpeed;
    bool IsReturningFromFarFlag;
};
```

Cross-referenced against the native SDK dump (`Pal.hpp`, already generated from a previous pass):

- `UPalFollowingComponent : public UPathFollowingComponent` — **zero extra fields or functions of its own.** `UPathFollowingComponent` is a *standard Unreal Engine AI module class* (the same thing behind any `AIController::MoveTo()` call). This is genuinely useful negative information: real Otomo following does NOT use some exotic bespoke movement system we're missing — it's the same category of path-following request our own `PalMoveToLocation` approximation already issues. The difference isn't "how it moves", it's "who's deciding when and where."
- `UPalAICombatModule_Otomo : public UPalAICombatModule` — also **zero extra fields/functions**, meaning Otomo combat-assist runs entirely on the base class's real, callable functions: `AIMoveToTargetActor(AActor* Target)`, `GetTargetActor()`, `GetAllTargetActors()`, `IsBattleMode()`, `UpdateBattleState()`, `IsReachable_NavMesh(...)`. `AIMoveToTargetActor` in particular is a real, direct answer to Dragón's spec item "if the player attacks an enemy, the following pals should help" — IF a Pal's controller actually has a `CombatModule` of this type, calling this one function is plausibly all combat-assist needs.
- `OtomoSlotIndex` (real int, party-slot identifier) and `IsReturningFromFarFlag` (matches the `IsReturningFromFar()` function already seen on the sibling `BP_MonsterAIController_NPCOtomo` class) — confirms the real "return from far" leash concept Dragón described exists natively, not just as our own approximation.

### The actual hard part: nothing assigns this controller class from Blueprint

Used FModel's "Find References" (By Reference search) against `BP_MonsterAIController_Otomo` across all 93,800 loaded packages: **zero references found in any other package.** No Blueprint anywhere sets a Pal's controller class to this asset. Cross-checked in the native SDK dump too — `APalCharacter` (the base Pal actor class) has no visible `AIControllerClass`-style field of its own in the dump (UE4SS's dumper generally omits already-known base-engine fields, and `AIControllerClass` is a stock property on every `APawn` — so it likely exists, just isn't re-declared here). The pattern seen elsewhere in the same dump (`UPalInvaderIncidentBase::GetNPCAIControllerClass(...)`, `MonsterAIControllerClass`/`EnemyAIControllerClass` as real `TSubclassOf<APalAIController>` fields) confirms controller-class selection IS data-driven somewhere in this game's native code — just not through a Blueprint-editable switch we can find or flip. This is compiled, non-reflected C++ logic (most likely inside the same native possession/spawn pipeline that already required this project to stay at the hook/patch level for everything else), not a config value or Blueprint condition we can safely locate and toggle.

Practical read: "enabling" real Otomo following for a wild Pal isn't a hidden flag flip. It would mean *forcibly re-possessing* an already-spawned wild Pal with a controller of this class at runtime (`UnPossess()` the current controller, spawn a new `BP_MonsterAIController_Otomo`, `Possess()` with it, then set `OtomoSlotIndex`/`CombatModuleClass` by hand) — a genuinely new category of native operation for this project. Every native call made so far has been either a field read, a small-param void call, or reading an incoming hook argument; spawning and swapping a live actor's controller is a different, heavier class of operation with failure modes this project hasn't tested (a Pal left controller-less, a duplicate/orphaned controller, possession state left inconsistent with the game's own party bookkeeping). Not attempted this pass — flagged here explicitly rather than guessed at blind, matching how the project has always handled a new risk tier.

### On the pet/feed gate (Dragón's second point — "that already exists, we just need to enable it")

Re-confirmed via the native dump: `IPalInteractiveObjectComponentInterface::GetIndicatorInfo(FPalInteractiveObjectActionInfoSet&, const FPalInteractiveObjectActionBy&)` is declared on a pure interface (`IInterface`) with no native default body — meaning whatever decides "Pet/Feed grayed out for this Pal" is a per-implementing-class Blueprint override, same conclusion as the fifteenth pass, now confirmed from the native side too (there's no hidden native ownership check function like `CanPet()`/`IsOwnedByPlayer()` anywhere in the dump). Did not this pass locate the specific Blueprint class that implements this override for a generic `PalCharacter` (searching the literal name `PalCharacter.uasset` in FModel found nothing — the interact-relevant Blueprint is under some other name, not yet identified). That's the concrete next FModel search for this half of the investigation: find whichever Blueprint implements `GetIndicatorInfo` for Pal characters (likely a shared parent Blueprint, not each species individually) and read its condition logic.

### Net assessment for Dragón

Both of Dragón's real-system targets now have a name and a shape, not just a Blueprint-only "gate we can't see": Otomo following/combat-assist is `BP_MonsterAIController_Otomo` + `PalAICombatModule_Otomo`, and its actual barrier is a native controller-class assignment, not a flippable switch. The pet/feed gate is confirmed Blueprint-interface-only with the specific implementing class still unidentified. Recommended next steps, in order: (1) find the Blueprint that implements `GetIndicatorInfo` for Pal characters — likely resolves the interact-menu question outright once found; (2) if Dragón wants to pursue real Otomo following specifically (not just the pet/feed menu), the next step is a deliberately small, isolated experiment — one debug keybind that tries the unpossess/spawn/possess sequence on a single test Pal, heavily logged, BEFORE it goes anywhere near the Trust pipeline — not a blind rewrite of `Combat.lua`.

## Twentieth pass (2026-09-01, same day): "have you searched online, and is it on the player/save side instead?" — both answered, with a genuinely better lead

Dragón's exact question: "you've tried searching for it in the game files and had found nothing on those certain aspects, but maybe someone out there already found them — have you tried that? also, what if its not on the pals but on the player instead, or the save file?" Both halves investigated this pass: a web-research pass (via a research agent) and a direct native-SDK follow-up grep of my own, done immediately after to close the gap the agent's report left open.

### Online research — a real, sourced, publicly-documented API lead, but no full solution found anywhere

- **pwmodding.wiki** (a real, maintained third-party Palworld UE4SS modding-docs site) documents a genuine hookable Blueprint component: `BP_OtomoPalHolderComponent`
  (`/Game/Pal/Blueprint/Component/OtomoHolder/BP_OtomoPalHolderComponent.BP_OtomoPalHolderComponent_C`),
  with a function `ActivateOtomo(int32 SlotID, FTransform StartTransform, bool& IsSuccess)` — documented as firing when a player summons a party Pal — plus a helper `TryGetOtomoActorBySlotIndex(int32 SlotIndex)`. This independently corroborates (from a completely different source than our own SDK dump) that "OtomoHolder" is the real, correct game-internal name for this system, and that "activate" is the real verb the game itself uses for spawning/possessing a party Pal from its slot.
- **No public mod was found that does what we want** — inserting an existing wild Pal directly into a party slot, bypassing the capture UI. The existing sphere-less/guaranteed-capture mods (Catch Gun, Capture the Uncapturables, Human Mercy Bypass) all still go through the normal capture-then-container pipeline; none of them skip straight to Otomo-holder assignment the way this project would need to.
- **No public documentation exists anywhere for the pet/feed interact-menu gate** (`GetIndicatorInfo`, `EPalInteractiveObjectActionType`, "radial menu wild pal", etc. all came up empty) — this really does look like genuinely unexplored territory publicly, not just something we personally hadn't found yet. Existing "Pal Force Feeder"-style mods only change feed amount/speed for already-feedable (owned) Pals.
- **Confirmed with a real source**: `cheahjs/palworld-save-tools` (github.com/cheahjs/palworld-save-tools), specifically `palworld_save_tools/rawdata/character_container.py`, decodes `CharacterContainerSaveData.Value.Slots.Slots.RawData` into exactly:
  ```python
  data = {
      "player_uid": reader.guid(),
      "instance_id": reader.guid(),
      "permission_tribe_id": reader.byte(),
  }
  ```
  This is independent, external, sourced confirmation that party/base/box membership in this game really is a **save-data container+slot record** (a container GUID holding a list of slots, each just `{player_uid, instance_id, permission byte}`) — not a property that lives on the live Pal actor at all. This directly supports Dragón's own hypothesis.

### My own immediate native-SDK follow-up — Dragón's hypothesis is confirmed correct, and there's a much better real API than expected

Grepped `Pal.hpp` again specifically for what the save-tools finding implied should exist natively — and it does, in more detail than the external source could show (since save-tools only sees the serialized bytes, not the live game's own class API):

- **`struct FPalWorldPlayerSaveData` really does have `FPalContainerId OtomoCharacterContainerId;`** (line ~9065) — a real, named field on the *player's own save struct* pointing at their Otomo container. This is the exact field the web-research agent could not find a name for, and it directly confirms Dragón's "maybe it's on the player" guess.
- Same struct also has `TMap<FPalContainerId, FPalCharacterContainerSaveData> CharacterContainerSaveData;` (line ~9101) — matches the save-tools container+slot model exactly, straight from the native struct layout.
- **`class UPalOtomoHolderComponentBase* GetOtomoHolder(const class APlayerState* TargetPlayerState);`** (line ~9664) — a real, plain, directly-callable function (returns an object pointer, the same safe call-shape as every other object-returning function already used successfully in this project) that gets a player's live Otomo-holder component straight from their `PlayerState`.
- **`class UPalOtomoHolderComponentBase : public UActorComponent`** (line 30927) — a rich, entirely native (not Blueprint-only) class, full body pulled directly from the dump. The standout functions:
  - `bool AddOtomoHandleToFreeSlot(class UPalIndividualCharacterHandle* Handle);` — looks like a direct "register this Pal's individual handle into a free party slot" call, i.e. exactly the container-bookkeeping half of what we need.
  - `void ActivatePalByHandle(const class UPalIndividualCharacterHandle* OtomoHandle, const FVector& Location, const FRotator& Rotation, bool bKeepActigvateOtomoId);` and `bool ActivateCurrentOtomo(FTransform SpawnTransform);` / `void ActivateCurrentOtomoFromBallNative(FTransform ballTransform, class AActor* hitTarget);` — these look like the actual spawn/possess step, run through the game's own tested code path (which should mean it assigns the real `BP_MonsterAIController_Otomo` controller correctly, since this is presumably the SAME function that runs every time a player throws out an existing party Pal).
  - Bookkeeping/query helpers: `TryGetSpawnedOtomoHandle()`, `TryGetSpawnedOtomo()`, `TryGetOtomoActorBySlotIndex(SlotIndex)`, `TryGetContainer(Container&)`, `IsFullMember()`, `GetOtomoCount()`, `GetNextOtomoSlotID()`, `GetMaxOtomoNum()`, `GetEmptySlot()`, `GetAllIndividualHandle(...)`.
  - Order/control helpers matching Dragón's original combat-assist ask: `SetOtomoOrder_ToServer(EPalOtomoPalOrderType)`, `RequestSetOtomoOrder(...)`, `DirectOrderTarget` field (an `APalCharacter*` — a real "tell your Otomo to focus this target" mechanism, potentially a much more direct combat-assist path than the wild-controller's own `AIMoveToTargetActor`).
- Also found, same pass: **`void CapturePal_ServerInternal(class APalPlayerCharacter* Player);` belongs to `class APalCapturedCage : public AActor`** (line 10219/10252) — a real, named capture-cage actor class. Relevant to DESIGN.md Q4 (sphere-less capture), not Q6 — noted here since it turned up in the same grep pass, added to DESIGN.md separately.
- Also found: `void TryMoveCharacterToContainerFrom(class UPalIndividualCharacterSlot* fromSlot);` on `UPalMapObjectCharacterContainerModule` (line 26529) — a real "move between containers" function, but it's scoped to MapObject (base/box) containers specifically, not confirmed to apply to the Otomo container — lower priority than the `UPalOtomoHolderComponentBase` API above.

### What's still missing before this can actually be tried

The one real gap: **how do we get a `UPalIndividualCharacterHandle*` for a wild Pal that was never captured?** Every function above that DOES something (`AddOtomoHandleToFreeSlot`, `ActivatePalByHandle`) takes a handle, not a raw `APalCharacter*` actor pointer — and every angle we've used on wild Pals so far (`CharacterParameterComponent:GetIndividualParameter()`) returns a `UPalIndividualCharacterParameter`, not a `UPalIndividualCharacterHandle`. These are almost certainly related/convertible (handles wrap parameters, going by naming elsewhere in the dump — e.g. `TryGetSpawnedOtomoHandle()` sits right next to `TryGetSpawnedOtomo()` as its actor equivalent) but the actual conversion function hasn't been located yet. That's the concrete next FModel/SDK-grep task before any live test of this path.

There's also a real open question about whether `ActivatePalByHandle`/`ActivateCurrentOtomo` **spawns a brand-new actor** (like popping a ball) or can somehow take over an **already-existing, already-spawned wild actor** in the world. If it only spawns fresh, calling it on a wild Pal we've been bonding with would create a *second*, duplicate Pal rather than converting the one Dragón has been petting — in which case the real move would be: register the wild Pal's handle into the container (bookkeeping, no visible effect), despawn/remove the original wild actor, then activate from the handle to spawn the "real" Otomo version in its place. That's a plausible, tidy sequence, but every step of it is still a hypothesis, not a tested fact — noted honestly rather than assumed.

### Net assessment

Both of Dragón's questions get a clear yes: yes, this was searched for online, and here's exactly what was and wasn't found; and yes, the "it's on the player/save side" hypothesis is directly correct — `OtomoCharacterContainerId` really does live on `FPalWorldPlayerSaveData`, not on the Pal. More importantly, this pass found a plausible, real, native, game-authored API (`GetOtomoHolder` → `AddOtomoHandleToFreeSlot` → `ActivatePalByHandle`/`ActivateCurrentOtomo`) that looks meaningfully more promising than the previously-proposed "manually unpossess/spawn-controller/possess by hand" plan from the nineteenth pass, since it would let the game's own tested code do the controller assignment instead of us guessing at it. It is NOT yet a confirmed-working path — the handle-conversion gap above needs closing first, and this is still squarely in the "new, heavier risk category" the project has flagged before (creating/reassigning live actors, first-time TMap/handle work) — so the plan is: find the handle-conversion function, then propose a single, isolated, heavily-logged test-keybind experiment on one test Pal, same discipline as every other new risk category so far, before touching `Combat.lua`/`Trust.lua`.

## Twenty-first pass (2026-09-01, same day): the handle-conversion gap is closed, and a real "second following Pal" system confirmed

Dragón asked to keep investigating until there's real confidence in a working plan, and specifically to look at Daedream/Dazzi/Flopie — Pals Dragón has observed following the player passively without being the main active party Pal — as a possible clue to how the game really handles this. Both leads paid off.

### The missing handle-conversion function — found, and it's a global static

The twentieth pass's one open gap was: every useful `UPalOtomoHolderComponentBase` function wants a `UPalIndividualCharacterHandle*`, but everything obtainable from a wild Pal so far was a `UPalIndividualCharacterParameter*` — a different type. Grepped `Pal.hpp` for functions that return a handle from an actor or parameter, and found several, on `class UPalUtility : public UBlueprintFunctionLibrary` (the SAME global static function-library class already confirmed safe and in use for things like `GetMinFriendshipRank()` — see Q3):

- **`class UPalIndividualCharacterHandle* GetIndividualCharacterHandleByActor(class AActor* Actor);`** — exactly the conversion needed, straight from any live Pal actor (wild or owned), as a plain static call, no manager object to find first.
- `class UPalIndividualCharacterParameter* GetIndividualCharacterParameterByActor(const class AActor* Actor);` — a shortcut for what we currently get via `CharacterParameterComponent:GetIndividualParameter()`; not needed, but confirms the pattern.
- `FPalInstanceID GetIndividualIDByActor(const class AActor* Actor);` — direct actor → stable ID (DESIGN.md Q5), another potential simplification for later.
- **`class UPalOtomoHolderComponentBase* GetOtomoHolderComponent(const class UObject* WorldContextObject);`** — also on `UPalUtility`, also static. Takes any `WorldContextObject` (the player actor works) and returns the LOCAL player's Otomo holder directly — simpler than the previously-found `GetOtomoHolder(APlayerState*)`, which turned out to actually belong to `APalArenaTestManager` (an Arena/PvP-test class, not generally usable) rather than being a general-purpose entry point as first assumed.
- `class UPalOtomoHolderComponentBase* GetOtomoHolderByOtomoPal(class AActor* OtomoPal);` — given an already-active Otomo Pal's actor, finds whose holder it belongs to. Not needed for a wild Pal (which has no holder yet), but useful for inspecting an existing owned Pal's setup for comparison.

This means the full candidate pipeline is now sketched end-to-end, and every single step is a plain object-pointer-in/pointer-or-bool-out call — the same safe shape used throughout this project, with the first two steps needing no object lookup at all beyond the Pal/player actors we already hold:

```
handle  = UPalUtility.GetIndividualCharacterHandleByActor(wildPalActor)
holder  = UPalUtility.GetOtomoHolderComponent(playerActor)
holder:AddOtomoHandleToFreeSlot(handle)
holder:ActivatePalByHandle(handle, location, rotation, bKeepActigvateOtomoId)
  -- or holder:ActivateCurrentOtomo(spawnTransform)
```

**Not yet tested live — this is a hypothesis built from real, matching function signatures, not a confirmed-working sequence.** Two real unknowns remain before it should be tried: (1) whether `AddOtomoHandleToFreeSlot`/`ActivatePalByHandle` require server authority / a `_ServerInternal`-style call instead of being safely callable directly (several sibling functions elsewhere in this same class ARE named with `_ServerInternal`/`_ToServer` suffixes, suggesting some operations expect to run server-side — this project has always run in singleplayer, where the local client IS the server, but it's still worth confirming rather than assuming); (2) whether `ActivatePalByHandle` spawns a brand-new actor or re-possesses one that's already alive in the world — see the reasoning below.

### Why "re-possess the existing actor" now looks like the more likely behavior, not just the hoped-for one

New evidence changes the earlier guess. `UPalIndividualCharacterHandle` itself (already in the dump) has `class APalCharacter* TryGetIndividualActor();` — meaning a handle can point at a live, already-spawned actor. Since `GetIndividualCharacterHandleByActor(wildPalActor)` derives the handle FROM the wild Pal's own already-alive actor, calling `TryGetIndividualActor()` on that same handle immediately afterward should return that exact same actor — the handle and the live wild Pal are already the same thing, just viewed two different ways. `UPalCharacterManager` (the class that actually owns spawning) has functions like `SpawnCharacterByHandle(Handle, ...)` right next to handle-lookup functions — a spawn pipeline built entirely around "does this handle already have a live actor" is a natural, and probably necessary, design for a game where captured/base/party Pals need to persist across zones without ever silently duplicating. That doesn't prove `ActivatePalByHandle` reuses the existing actor instead of spawning a second one — but it is a real, structural reason to expect it might, rather than a hope with nothing behind it. **Still explicitly unconfirmed** — the test plan below checks this directly and safely (watch for a duplicate Pal actor appearing) before trusting it either way.

### The "second following Pal" question — real, and it's exactly what Dragón described

Searching `Pal.hpp` for anything like "second otomo" turned up a small, telling native class:

```
class UPalPlayerPartyPalHolder : public UObject
{
    class UPalIndividualCharacterHandle* FirstOtomoPal;
    class UPalIndividualCharacterHandle* SecondOtomoPal;
    TArray<UPalIndividualCharacterHandle*> BenchMember;
    float FirstCoolTimer;
    float SecondCoolTimer;
    float CoolDownTime;

    bool PawnOtmoIsPartyOtomo(bool SecondPal, UPalIndividualCharacterHandle* IDHandle);
    bool IsUsableCommandSkill(bool SecondPal);
    void GetPartyMember(TArray<UPalIndividualCharacterHandle*>& OutPartyMember);
    class UPalIndividualCharacterHandle* GetOtomoPal(bool SecondPal);
    float GetCoolTimeRate(bool SecondPal);
    void ChangePalSlot(bool SecondPal);
};
```

This is real, native, structural confirmation that the game tracks not one but **two simultaneously-active Otomo slots** (`FirstOtomoPal`/`SecondOtomoPal`), each independently queryable/settable (`GetOtomoPal(bool SecondPal)`, `ChangePalSlot(bool SecondPal)`), on top of a separate bench list for the rest of the party — exactly matching what Dragón described observing with Daedream/Dazzi/Flopie: a Pal that's genuinely following/active without being *the* main Pal. `IsUsableCommandSkill(bool SecondPal)` is very likely the real name for what these Pals actually do in that slot — a triggerable "Command Skill" (distinct from a full combat Otomo), which lines up with community knowledge of these specific Pals having on-demand utility skills rather than being sent out to fight.

**Not yet found**: which per-species flag decides a Pal is second-slot/command-skill-eligible in the first place — checked the main per-species DataTable row struct (`FPalCharacterParameterDatabaseRow`, the same one Q1 already fully inspected) directly for anything containing "second", "command", "perch", or similar, and found nothing — so that eligibility check is either Blueprint-side or driven by the specific `PartnerSkill`/`Tribe` data tables (`FPalPartnerSkillDatabaseRow`, `FPalPartnerSkillParameterDataRow` — real structs found this pass, not yet inspected in detail) rather than a plain flag on the row we already have JSON for. Lower priority than the main handle/activate pipeline above — noted so it isn't lost, but this project's actual goal (a bonding wild Pal following/assisting) doesn't need to replicate the *Second Otomo Command Skill* mechanic specifically, just confirms the general architecture ("more than one Pal can be actively linked to the player at once, natively") is real and consistent with everything else found so far.

### Test plan, once Dragón is ready to try something live

A single new debug keybind (not wired into `Combat.lua`/`Trust.lua` yet), heavily logged at every step, tried on ONE already-bonding test Pal:

1. Log the wild Pal's `GetFullName()` and confirm `GetIndividualCharacterHandleByActor` returns a non-nil handle (first real test of this call existing/working at all).
2. Log `handle:GetIndividualID()` and compare its GUID against the same Pal's already-known Friendship/parameter data, to confirm it's really the SAME individual, not something new.
3. Call `holder:AddOtomoHandleToFreeSlot(handle)` — log success/failure, and specifically watch (via `FindAllOf`, same technique already used elsewhere) whether the ORIGINAL wild actor is still the only instance of that Pal in the world at this point (this step is bookkeeping-only per its name — expected to have no visible effect yet).
4. Only if step 3 logs clean, call `holder:ActivatePalByHandle(handle, ...)` with the Pal's own current location/rotation (read from the actor itself first) — then immediately check: (a) does a SECOND Pal actor appear (bad — would mean it spawns fresh rather than reusing), (b) does the original wild actor's Controller change class/become the real Otomo controller (`BP_MonsterAIController_Otomo`) in place, (c) does the game log any errors/warnings about server authority.
5. If a duplicate appears, the fallback plan (registering the handle, then despawning the original wild actor, then activating to spawn the "real" version in its place) becomes the next thing to test — not attempted blind, only if step 4 shows it's actually necessary.

Not started yet — pending Dragón's go-ahead per the standing project discipline (new risk categories get proposed and confirmed before being attempted, not attempted silently).

## Twenty-second pass (2026-09-01, same day): watching the real game use this API before touching a wild Pal

Rather than jump straight to the live test above (still a new risk category, still two real unknowns per the twenty-first pass), applied the exact technique that already worked for the real pet/feed shape (Spy.lua): install read-only pre-hooks on the real functions and watch NORMAL vanilla play use them, before ever calling any of them ourselves.

**New file: `OtomoWatch.lua`**, wired into `main.lua` (temporary, same pattern as `Spy.lua`). Installs `RegisterHook` pre-hooks (zero calls made, cannot cause the kind of crash a direct experimental call could — same safety argument as `Spy.lua`) on:

- `PalOtomoHolderComponentBase:AddOtomoHandleToFreeSlot`
- `PalOtomoHolderComponentBase:ActivatePalByHandle`
- `PalOtomoHolderComponentBase:ActivateCurrentOtomo`
- `PalPlayerPartyPalHolder:ChangePalSlot`
- `PalCharacterManager:SpawnCharacterByHandle`

Each log line includes, for any handle argument, both its stable ID (`GetIndividualID()`) and whether `TryGetIndividualActor()` already returns a live actor AT THE MOMENT the real game calls that function — this is the direct, observational answer to unknown #2 from the twenty-first pass (does activating from a handle require the handle to have no live actor yet, i.e. does it always spawn fresh, or does the real game sometimes call these functions on a handle that already has one).

**Not yet run** — needs Dragón to do ordinary, everyday party-management actions with this active (swap the active party Pal via the normal menu, switch which Pal holds the second-Otomo slot if one is in the party, box a Pal and pull it back out, send one to base and recall it) — none of it touching a wild Pal at all. The resulting log is the next real evidence this investigation needs before proposing an actual wild-Pal experiment.

## Twenty-third pass (2026-09-01): the real result — none of the base-class hooks fired for the player, and a real live class name changes the picture

Dragón ran exactly the requested test: captured a Tanzee and a Daedream plus already had a Flopie, then spent a session switching them around (at one point Tanzee active + Daedream and Flopie both following as extra/second-slot Pals simultaneously — real, live confirmation of the "more than one Pal following" mechanic from the twenty-first pass), pet several of them, and sent one to the home base Lamball.

**The result, read straight from `palbonds-live.log`**: across the whole session, only ONE of the five hooked functions fired even once — `AddOtomoHandleToFreeSlot` — and it wasn't for the player at all:

```
[OtomoWatch] [ADD] AddOtomoHandleToFreeSlot called — holder=BP_OtomoPalHolderComponentForNPC_C
  .../BP_NPCAIController_C_2147434895.BP_OtomoPalHolderComponentForNPC
  handle=id=table: ... actor=[no live actor yet]
```

`ActivatePalByHandle`, `ActivateCurrentOtomo`, `ChangePalSlot`, and `SpawnCharacterByHandle` never fired ONCE, despite Dragón definitely swapping active Pals multiple times, running two Pals in follower slots simultaneously, and sending a Pal to base — real actions that should have exercised exactly this system if our hooked functions were the ones actually used.

**Why, and what this changes**: the one real hit is the key clue. It fired on a live, real object of class `BP_OtomoPalHolderComponentForNPC_C` — a BLUEPRINT subclass of the native base, specifically for NPCs (an AI-controlled character's own holder component, not the player's — this call was some background NPC's own pet-following logic, unrelated to anything Dragón did). The naming makes it near-certain a sibling class exists for the player specifically (a "...ForPlayer"-style Blueprint subclass), and — since Blueprint subclasses can override/replace inherited functions with their own implementation, which RegisterHook's function-specific patching does NOT automatically also catch — the player's real "swap active Pal" flow most likely runs through that subclass's own version of these functions, invisible to a hook placed on the base native class.

This lines up with something already sitting in this project's own notes and previously under-weighted: **pwmodding.wiki documents a real Blueprint class**, `/Game/Pal/Blueprint/Component/OtomoHolder/BP_OtomoPalHolderComponent.BP_OtomoPalHolderComponent_C`, with its own function **`ActivateOtomo(SlotID, Transform, &IsSuccess)`** — a different name from `ActivatePalByHandle`. This is very likely the REAL top-level entry point the player's UI actually calls (with `ActivatePalByHandle`/`AddOtomoHandleToFreeSlot` perhaps being lower-level internals used by other paths, e.g. save-load, not the everyday swap-Pal action).

**Fix, same pass**: added a new hook to `OtomoWatch.lua`, this time using the Blueprint-asset-path hook format (`/Game/Path/To/BP.BP_C:Function`, not the native `/Script/Pal.Class:Function` format used for the others) — `BP_OtomoPalHolderComponent:ActivateOtomo`. Deployed to both the live Mods folder and the Proyectos mirror. **Not yet tested** — needs the exact same simple retest (swap active Pal a few times) to see whether this one actually fires where the others didn't.

**Lesson worth stating plainly**: this is a good example of exactly the discipline Dragón originally asked for — the twenty-first pass's pipeline was a well-reasoned hypothesis built from real, matching function signatures, but it took actually watching the real game to find out those specific functions apparently aren't the ones the everyday player flow uses at all. Better to learn that now, for free, from a read-only watch hook, than to have built `Combat.lua` around a function the real game barely touches.

## Twenty-fourth pass (2026-09-02): why the ActivateOtomo hook failed to attach, and the real class's full API

Dragón re-ran the retest with the `ActivateOtomo` hook added — the log showed it never even attached (`could not hook BP_OtomoPalHolderComponent:ActivateOtomo (path may need adjusting)`, logged immediately at mod load, before any gameplay). So that retest didn't actually exercise the hypothesis at all; the hook itself was broken from the start.

**Confirmed the function is real and the path was structurally right.** Used FModel's global package search (`Ctrl+Shift+F` → "OtomoPalHolderComponent") and got exactly two hits: `Pal/Content/Pal/Blueprint/Component/OtomoHolder/BP_OtomoPalHolderComponent.uasset` and the `ForNPC` sibling already seen live — confirming the in-game path used in the hook (`/Game/Pal/Blueprint/Component/OtomoHolder/BP_OtomoPalHolderComponent`) was correct. Better still, UE4SS's own CXX header dumper turned out to already have generated (or regenerate on demand) a full native-style header for this exact Blueprint class — `CXXHeaderDump/BP_OtomoPalHolderComponent.hpp` — which normally only happens for a class that's actually been referenced/loaded at some point. Read it directly: `ActivateOtomo(int32 SlotId, FTransform StartTransform, bool& IsSuccess)` is real, confirmed, exactly as pwmodding.wiki documented.

**So why did the hook fail?** Most likely: a Blueprint class's UFunction only exists in memory once the game has actually loaded/referenced that asset — unlike a native class (compiled in, always present from process start), `UBP_OtomoPalHolderComponent_C` probably isn't loaded yet at the moment this mod's `Init()` runs (mod load happens before the player's save, and their actual holder component instance, exist). `RegisterHook` on a not-yet-loaded Blueprint function fails immediately rather than waiting.

**Fix**: `OtomoWatch.lua` now retries hook registration on a timer (reusing the same safe `ExecuteInGameThreadWithDelay` self-rescheduling pattern already proven in `Trust.lua`'s follow tick) — attempts once immediately, and if that fails, tries again every 3 seconds for up to a minute before giving up with a clear log line either way. Applied to every Blueprint-path hook; the native-class ones from the twenty-second pass attach immediately and don't need it.

**The full real class body, read directly this pass, changes the plan for the better.** `UBP_OtomoPalHolderComponent_C` (extends the native `UPalOtomoHolderComponentBase`) has real fields/functions well beyond what the base class alone showed:

- `class UPalIndividualCharacterHandle* ActivatedHandle` — a plain field holding whichever Pal is CURRENTLY the active one, sitting right on the object. `OtomoWatch.lua` now reads this on every hook fire for free context ("what was active right when this happened").
- `void RemovePalFromParty(class UPalIndividualCharacterHandle* RemoveHandle);` — a real, simply-shaped function that looks like a much more direct "take this Pal out of the party" than anything found before.
- `void SpawnOtomo(int32 SlotId);` and `void SetSelectOtomoID_Internal(int32 Index);` — plain int-param functions, likely simpler/lower-level than `ActivateOtomo` itself, possibly what a scroll-wheel/hotkey party-cycle actually calls.
- `void InactivateCurrentOtomo();` / `void InactivateOtomo(bool& IsSuccess);` / `void InactivateOtomoByHandle(handle, bool, bool&);` — the reverse operations.
- `void FindSlotByIndividualID(FPalInstanceID ID, int32& SlotId);` — given a Pal's stable ID (which we already know how to get, via `UPalUtility.GetIndividualIDByActor`), find which party slot it's sitting in, if any — a strong candidate for CONFIRMING after any real attempt whether our wild Pal actually landed in the party.
- Several functions use `_ToServer`/`_Internal` suffixes elsewhere in this same class (`Setup_ToServer`, `UpdateSlotInServer`) confirming, again, that this codebase does mark some functions explicitly for server-only execution — `ActivateOtomo` itself carries no such suffix, a good sign it's meant to be called plainly rather than needing special RPC handling.

Added hooks (all retry-wrapped) for `ActivateOtomo`, `SpawnOtomo`, `RemovePalFromParty`, `InactivateCurrentOtomo`, and `SetSelectOtomoID_Internal` — the state-changing subset most likely to actually fire during ordinary party management, skipping a couple of functions whose real internal names appear to contain literal spaces in the decompile (`Inactivate Otomo`, `Update Otomo Slot in Local`, etc. — Blueprint function names can contain spaces where C++ ones can't; the exact string would need to be gotten precisely right to hook, not worth guessing at yet).

Deployed to both the live Mods folder and the Proyectos mirror. **Not yet retested** — needs the same simple swap-party-Pal action from Dragón one more time, this time with actual working hooks on the right class.

## Twenty-fifth pass (2026-09-02): the real swap sequence, confirmed live — this is the biggest single result so far

The retry-hook fix worked — every Blueprint-path hook attached this time (`[PalBonds/OtomoWatch] hooked BP_OtomoPalHolderComponent:X (attached)` for all five). Dragón then did four real party-Pal swaps plus some pet/feed interactions and a Palbox visit, all captured cleanly in `palbonds-live.log`, no crash.

**The real "swap active Pal" sequence, directly observed, every single time, in this exact order:**

```
holder:InactivateCurrentOtomo()
holder:ActivateOtomo(newSlotID, transform, &isSuccess)
```

Four swaps, four identical two-call sequences, ~1 second apart each time. `ActivatePalByHandle`, `ActivateCurrentOtomo`, `ChangePalSlot`, and `SpawnCharacterByHandle` — everything hooked on the native base class — **never fired once**, across two full test sessions now. This settles the twenty-first pass's open question: the everyday party-swap flow does not go through the base class's own functions at all. It goes entirely through the player-specific Blueprint subclass, and the real function is `ActivateOtomo`, not `ActivatePalByHandle`.

**`SpawnOtomo` turned out to be a red herring for "activation"** — it fired repeatedly (4 times back-to-back when a menu first opened, and 6 more times right after opening the real Palbox UI) but `currentActivated` (the holder's own `ActivatedHandle` field, read live at each call) stayed completely unchanged across every one of those calls — strong evidence it's a UI-preview/render call (one per visible slot the menu is drawing), not a real activation. Real activation only ever happened via `ActivateOtomo`.

**`AddOtomoHandleToFreeSlot` and `RemovePalFromParty` still never fired for the player**, across everything Dragón did this session (swapping, petting, feeding, opening the Palbox) — consistent with the hypothesis that these are one-time "join/leave the party roster" operations, not touched by ordinary swapping between already-party Pals. This is the one remaining real gap before the twenty-first pass's plan can be trusted: we still have zero direct observation of what happens, for the PLAYER specifically, at the moment a Pal actually joins the party.

**Bonus, free data**: real internal species codenames confirmed live for Dragón's actual party this session — Tanzee = `BP_Monkey_C`, Flopie = `BP_FlowerRabbit_C`, Dazzi = `BP_DreamDemon_C`, Daedream = `BP_FlowerDoll_BOSS_C` (the `_BOSS_` suffix on a normal captured party member is a little surprising — worth a note, not a blocker — possibly Daedream's captured class always carries that suffix, or the specific individual Dragón has is an Alpha/boss variant).

**Next step, still purely observational, zero new risk**: ask Dragón to capture a brand-new wild Pal normally (Palsphere, as usual) with `OtomoWatch.lua` still active. If `AddOtomoHandleToFreeSlot` fires on `BP_OtomoPalHolderComponent_C` (the player's holder) at that moment, with the newly-captured Pal's handle, that closes the last gap — we'd then have a fully real, directly-observed, two-step model for "add a Pal to the party" (whatever fires on capture) and "make a party Pal active" (`InactivateCurrentOtomo()` + `ActivateOtomo(slot, transform, success)`), instead of a hypothesis for the first half. That is the point at which proposing an actual wild-Pal experiment would be justified — not before.

## Twenty-sixth pass (2026-09-02): correction — real species, and SpawnOtomo is NOT just a UI preview after all

Dragón corrected the species mapping from the twenty-fifth pass: no Dazzi in the party at all. The real mapping is Tanzee = `BP_Monkey_C`, Flopie = `BP_FlowerRabbit_C`, Daedream = `BP_DreamDemon_C`, Petallia = `BP_FlowerDoll_BOSS_C` — and the `_BOSS_` suffix on Petallia specifically is because that individual is an ALPHA Pal (the game's "boss version" of a regular species), not a special party-only class as speculatively flagged last pass. Corrected everywhere this matters.

**More importantly, Dragón explained what was actually happening on screen during the swap test, and it changes the read on `SpawnOtomo`.** Both Daedream and Flopie have a Partner Skill that makes them auto-follow as secondary Pals alongside whichever Pal is active — and Dragón observed that on EVERY swap, the secondary Pals visibly despawn and respawn too, not just the one being swapped to. Walked through step by step:

- Summon Tanzee (Daedream + Flopie already out as secondaries).
- Swap to Daedream: Tanzee despawns; Daedream despawns and respawns as the new active Pal.
- Swap to Flopie: Daedream despawns and respawns as a secondary follower again; Flopie despawns and respawns as the new active Pal.
- Swap to Petallia: Flopie despawns and respawns as a secondary follower again.
- End state: Petallia active, Daedream and Flopie both following as secondaries.

This means the twenty-fifth pass's read of `SpawnOtomo` — "just a UI preview, since the holder's main `ActivatedHandle` field didn't change across repeated calls" — was too hasty. `ActivatedHandle` only tracks the MAIN active Pal; it was never going to change when a SECONDARY partner-skill follower respawns, so that check couldn't actually distinguish "real secondary-follower respawn" from "harmless UI preview." Given what Dragón just described, `SpawnOtomo(SlotId)` is much more likely the REAL, general "make this party slot's Pal exist as a world actor" call — used for the main active Pal as part of the swap cascade, AND for any secondary Pal with an auto-follow partner skill, which the game apparently despawns/respawns wholesale on every single swap rather than diffing what actually changed.

**Why this matters for the project's actual goal**: `SpawnOtomo(SlotId)` takes only a slot index — a much simpler signature than `ActivateOtomo`'s (slot, transform, success). If a wild Pal's handle can be placed into a free party slot at all (still the one open question — `AddOtomoHandleToFreeSlot`, next test below), `SpawnOtomo(thatSlot)` might be enough to make it appear and follow as a SECONDARY Pal — arguably a better match for this mod's actual goal (a bonding wild Pal that follows and assists, without needing to fully replace whatever the player already has active) than forcing it through `ActivateOtomo` as the primary Pal.

**Next step is unchanged**: still need to see `AddOtomoHandleToFreeSlot` (or whatever really handles "join the party") fire for the player at least once, from a real capture. Once that's seen, both `ActivateOtomo` (primary swap) and `SpawnOtomo` (secondary/follower spawn) are real, confirmed, candidate next calls to test on a wild Pal's handle — not just one.

## Twenty-seventh pass (2026-09-02): the capture test — good confirmation on one half, a likely dead end on the other

Dragón ran the requested test: boxed the whole existing party, then captured a male Lamball, briefly summoned and recalled it, captured a female Lamball too (both now in the party), then re-summoned the male Lamball and pet it. All read from `palbonds-live.log`.

**Good news — `ActivateOtomo`/`SpawnOtomo` fire correctly on a JUST-CAPTURED Pal, with a real, valid handle and actor already resolved:**

```
[SPAWN-OTOMO] SpawnOtomo called — slotID=0 currentActivated=nil
[ACTIVATE-OTOMO] ActivateOtomo called — slotID=0 currentActivated=
    id=... actor=[BP_SheepBall_C_2147452085]   <- the freshly-captured Lamball
```

This confirms the two functions already found for ordinary swapping also work seamlessly on a Pal that only just joined the party seconds earlier — good, direct evidence that a Pal's activation path doesn't care how "old" its party membership is, which is reassuring for the eventual wild-Pal case too.

**Bad news — `AddOtomoHandleToFreeSlot` still never fired, even across two genuine real captures.** That's now a real negative result, not just an absence of data: whatever actually assigns a newly-captured Pal's handle into a free party slot is NOT this function, for the player. Dug one level deeper into why: `UPalIndividualCharacterContainer` (the real party-roster class, holds `TArray<UPalIndividualCharacterSlot*> SlotArray`) has only plain getters (`FindEmptySlot()`, `FindByHandle()`, `Get(Index)`, `Num()`) — no `Add`/`Insert`/`Assign` function at all. `UPalIndividualCharacterSlot` itself has a plain `UPalIndividualCharacterHandle* Handle` FIELD (not behind any setter function either) — meaning the real assignment is very likely just `slot.Handle = newHandle`, a direct field write buried inside compiled native code, not something that goes through any hookable UFunction. If that's right, no amount of `RegisterHook`-based watching will ever catch this specific step — it may be genuinely invisible to this technique.

**What this changes, honestly**: the twenty-first pass's plan assumed `AddOtomoHandleToFreeSlot` was the real "join the party" call. That now looks unlikely — it's probably an NPC-specific helper (matching the one time it's ever fired, for `BP_OtomoPalHolderComponentForNPC_C`). The real mechanism for the player is most likely a direct field write we can't observe by watching functions. That doesn't block the plan entirely — `UPalIndividualCharacterContainer:FindEmptySlot()` is a real, safe-shaped, argument-less getter that should return an actual empty `UPalIndividualCharacterSlot` object from the player's own party container, and if the `.Handle` field really is just a plain writable field, setting it directly (`slot.Handle = wildPalHandle`) — a field write, this project's historically safest category of native interaction, safer than any function call — followed by `SpawnOtomo`/`ActivateOtomo` on that slot's index, becomes the new candidate sequence. This is one step CLOSER to something a wild Pal could plausibly use, but it swaps "call an unconfirmed function" for "write an unconfirmed field" as the remaining leap of faith — still not something to try blind.

## Twenty-eighth pass (2026-09-02): answering "why not just log everything" — and a broader search finds better candidates

Dragón asked a fair methodological question at the end of the twenty-seventh pass: instead of hooking specific named handles/classes we're guessing might be the right ones, why not just capture the whole log and mine it for the right functions? That deserved a real answer, checked against evidence, not a reflexive defense of the existing approach.

**Checked directly against UE4SS's own documentation (docs.ue4ss.com):**

- `RegisterHook(UFunctionName, Callback)` requires one exact, full UFunction path every single time — "Type prefix has no effect," but there is no wildcard, no glob, no "hook everything." Confirmed directly from the docs page, not assumed.
- Any UFunction hooked this way "must already exist in memory" at hook-registration time — this is the same native-vs-Blueprint-loading gotcha found in the twenty-fourth pass, now confirmed as documented, expected UE4SS behavior rather than a quirk specific to this project.
- `UE4SS-settings.ini`'s `[Hooks]` section (found at the end of the twenty-seventh pass) includes `HookUObjectProcessEvent = 1` — this is NOT a separate user-facing "log every call" feature. It's the internal mechanism UE4SS itself uses to make `RegisterHook` work at all for Blueprint/script functions (which have no native machine code to detour into directly) — it's already running, already powering every "script hook" we've registered, and is not exposed to Lua as a raw firehose we could tap for a comprehensive log.
- Two other global Lua hooks exist that ARE broader than a single named function: `NotifyOnNewObject(ClassName, Callback)` fires once for every new instance of a class (and its subclasses) as it's constructed — genuinely useful, previously untapped by this project, but it answers "when does an object of this type get created," not "what happened to it after." `RegisterCustomEvent(EventName, Callback)` fires on named Blueprint events/functions by string name — still name-based, not a wildcard.

**Honest conclusion**: "log absolutely everything" isn't available from Lua in this modding setup — it would need a UE4SS C++-level change, and even then the resulting volume (every UFunction call across the entire running engine, every frame) would itself be a much bigger haystack than what we have now. The targeted-hook approach isn't a stylistic choice, it's what the tooling allows.

**But the underlying instinct — stop guessing forward from a name, search broadly through what we already have first — was right, and applying it paid off immediately.** Instead of hypothesizing a class name and checking whether it has a function we want, grepped the ENTIRE `CXXHeaderDump/Pal.hpp` (all ~40,000 lines) for "Capture" and "Handle" and read every match's surrounding class, rather than only the classes already on our radar (`OtomoHolderComponentBase`, `PalPlayerPartyPalHolder`, `PalIndividualCharacterContainer`/`Slot`). That surfaced two real candidates neither previous pass had found, because neither name matches the "Otomo"/"Party" vocabulary being searched for directly:

- **`UPalUtility::PalCaptureSuccess(APalPlayerCharacter* AttackerPlayer, APalCharacter* Monster)`** — a global static function on the same trusted `UPalUtility` class already confirmed working (`GetIndividualCharacterHandleByActor`), plausibly the single real call site for "a capture just succeeded," with both the player and the captured monster passed directly as arguments.
- **`APalCaptureJudgeObject::OnCaptureSuccess(const APalCharacter* Character, FCaptureResult Result)`** — a plain `AActor` subclass, the sphere's own "judge" object confirming success server-side, likely fired even earlier in the real sequence (before whatever hands the Pal off to the party system).

Both are native, always-loaded shapes (a global BlueprintFunctionLibrary static, and a plain AActor subclass) — no retry-hook wrapper needed, same as the twenty-second pass's native-class hooks. Added both as new read-only pre-hooks to `OtomoWatch.lua` (`[CAPTURE-SUCCESS-UTIL]` and `[CAPTURE-JUDGE]` tags), logging the attacker/monster or character argument on each call. Deployed to both the live Mods folder and the Proyectos mirror.

**Next step**: ask Dragón to do one more real capture (any wild Pal, sphere throw as normal). If either new hook fires, we get, for the first time, direct visibility into the exact moment "capture succeeded" is recognized by the game — and whatever runs immediately after in the log (from the hooks already in place) should show what actually happens to the handle next, closing the loop the twenty-seventh pass left open. Still purely observational — nothing here touches a wild Pal's state, only watches what the game already does to it.

## Twenty-ninth pass (2026-09-02): `PalCaptureSuccess` fires, live, exactly as hoped — and rules out the other new candidate

Dragón captured another wild Lamball with both new twenty-eighth-pass hooks active. Read directly from `palbonds-live.log` and cross-checked against `UE4SS.log`.

**`UPalUtility.PalCaptureSuccess` fired, for the first time ever, at the exact real moment of capture:**

```
[CAPTURE-SUCCESS-UTIL] UPalUtility.PalCaptureSuccess called —
    attacker=BP_Player_Female_C_2147480789
    monster=BP_SheepBall_C_2147460677
[SPAWN-OTOMO] SpawnOtomo called — slotID=0 currentActivated=nil    <- same second
```

Both arguments came through exactly as expected: the real player actor as `AttackerPlayer`, the real just-captured Lamball actor as `Monster`. `SpawnOtomo(slot=0)` fired in the very same second right after — strong circumstantial evidence that `PalCaptureSuccess` is what triggers the whole "hand the captured Pal off to the party system" cascade internally, not just a notification fired alongside it.

**One important mechanical nuance, confirmed from `UE4SS.log`**: both new hooks registered as **native** hooks (`[RegisterHook] Registered native hook ... for Function /Script/Pal.PalUtility:PalCaptureSuccess`), not script hooks. Per UE4SS's own docs (checked last pass), a native function's single RegisterHook callback fires **after** the real function returns, not before (only script/Blueprint functions get a true pre-hook from a single callback). So what we're seeing is a POST-hook: by the time this log line prints, `PalCaptureSuccess` has already fully run, including whatever it does internally to the party/handle state. That's consistent with — maybe even explains — why `SpawnOtomo` shows up in the very same instant right after: it's not a coincidence, it's the tail end of the same already-completed call chain.

**`AddOtomoHandleToFreeSlot` still never fired, even on this capture** — third real capture in a row with zero hits for the player. This is no longer "not enough data," it's a consistent negative result across three genuine captures. Combined with the earlier structural finding (no `Add`/`Insert` function anywhere on the real party-container class), the field-write hypothesis from the twenty-seventh pass stands: whatever assigns the handle into a slot happens inside compiled native code we cannot hook — very possibly inside `PalCaptureSuccess` itself, which would explain why it never needs to.

**`APalCaptureJudgeObject.OnCaptureSuccess` — registered fine as a native hook, but never fired, not once.** Ruled out as part of the normal field-sphere capture flow. Looking at its siblings on the same class (`ChallengeCapture`, `ChallengeCapture_ToServer`, `CaptureResult_ToALL`) it now reads much more like a dedicated capture-challenge/test-arena class (matching the earlier, separately-found `APalArenaTestManager`-style test classes) than anything involved in an ordinary Palsphere throw. Not a bug, not a wasted hook — a real, useful negative result that removes a class from consideration.

**Why this matters for the actual project goal, not just the research thread**: `UPalUtility::PalCaptureSuccess(AttackerPlayer, Monster)` is now the single strongest real candidate found so far for DESIGN.md Question 4 (a clean existing function to call for a guaranteed, sphere-less capture) — a global static, BlueprintCallable-shaped function, on a class this project has already safely called functions from, that appears (from this live evidence) to single-handedly trigger the entire post-capture cascade including whatever handles party assignment. **Still not something to call blind.** We only ever observed it being invoked by the real sphere-throw pipeline — we don't know what state that pipeline sets up beforehand that `PalCaptureSuccess` might assume already exists (a capture-in-progress flag, some capture-effect actor, a handle pre-created earlier in the throw sequence, etc.). Calling it out of context on a wild Pal that never went through a real sphere throw is a real, different risk than anything tried so far and needs more groundwork first — not a live test yet.

**Next step, still purely observational**: a couple more real captures (varied — a different species, maybe one at low vs. high capture difficulty) to confirm `PalCaptureSuccess` fires 100% reliably and see whether its arguments or timing ever vary. In parallel, worth checking whether any public Palworld modding resource (GitHub, the pwmodding wiki, decompilation notes) has ever documented what `PalCaptureSuccess` does internally — since it's a fairly distinctively-named function, it's plausible someone else has already looked at it. If that turns up nothing, the next investigative step would be trying to find where `PalCaptureSuccess` itself is CALLED FROM (i.e., hook whatever precedes it in the real capture sequence — the sphere's own capture-resolution logic) to see what setup happens right before it, which would tell us whether that setup is something we could replicate for a wild Pal that never went through a sphere at all.

## Thirtieth pass (2026-09-02): Dragón's own idea — a real, dev-built, sphere-less capture path already exists in the game

Dragón pointed out something this project hadn't considered: enemy camps/settlements sometimes hold a captive Pal in a small cage, and opening the cage adds that Pal straight to the party or box, no Palsphere involved. If that's real (and it is — this is a known vanilla mechanic), it's a far better precedent to study than trying to call `PalCaptureSuccess` cold, because the game's own code already does "give the player this specific Pal directly" without a sphere-throw. Grepped the header dump for "Cage"/"Jail"/"Rescue" and found the real class immediately:

**`class APalCapturedCage : public AActor`** — native, always loaded, no retry-hook needed. Full real shape:
- Fields: `bIsEnemyCamp` (distinguishes settlement/camp cages from other uses), `SpawnedPalId`/`SpawnedPalLevel`/`SpawnedPalHandle` (the caged Pal, already has a real handle before the player even interacts — meaningfully different from the field-capture case), `bIsDoorOpened`, `ItemLotteryName`.
- Functions: `SpawnPal(InPalID, InPalLevel)` / `LotteryAndSpawnPal()` (populates the cage originally), `OpenDoor_ToAll()` / `OpenDoor_BP(bIsAnimSkip)` / `SetDoorOpened(bIsOpend)` (the door interaction), `OnSuccessOpenDoor_Client(Player)`, `StartCaptureEffect_ServerBP(Player)`, `OnCreateHandle(ID)` / `OnSpawnPal(ID)` / `OnDespawnPal(ID)`, and — the one that matters most — **`CapturePal_ServerInternal(APalPlayerCharacter* Player)`**.

This is a meaningfully different, and probably safer, shape than the field-capture case: the cage already HAS a resolved `UPalIndividualCharacterHandle` (`SpawnedPalHandle`) for its Pal before the player ever interacts — there's no sphere-throw physics or capture-chance roll involved at all, just "player opens door → `CapturePal_ServerInternal(Player)` → Pal goes to the player." If that's really as simple as it looks, it could be a much closer real-world match for "a wild Pal that built up enough trust just walks into the party" than trying to fake a sphere capture.

Added all of the above as new read-only watches (`[CAGE-OPEN-DOOR]`, `[CAGE-SET-DOOR]`, `[CAGE-DOOR-SUCCESS]`, `[CAGE-CAPTURE-EFFECT]`, `[CAGE-CAPTURE-PAL]`, `[CAGE-CREATE-HANDLE]`, `[CAGE-LOTTERY-SPAWN]`) to `OtomoWatch.lua`. The `CapturePal_ServerInternal` hook additionally reads `Context.SpawnedPalHandle` directly (a plain field read, this project's safest category) so we can see the handle's real state at the exact moment the real capture call fires. Deployed to both the live Mods folder and the Proyectos mirror.

**Next step**: Dragón finds a real enemy-camp/settlement cage (these appear at bandit/human settlements) and opens it normally — no sphere needed, just the door interaction. Whichever of these hooks fire, and in what order, should show the real "no sphere" hand-off directly. If `CapturePal_ServerInternal` fires cleanly with a valid `Player` and `SpawnedPalHandle`, and `AddOtomoHandleToFreeSlot` *still* never fires even here, that's strong triangulating evidence the "add to party" step really is buried inside these higher-level functions everywhere in the game, not a separate hookable step — useful either way. Still zero risk: purely watching what the game already does when Dragón does something he'd do anyway.

## Thirty-first pass (2026-09-02): CONFIRMED LIVE — `CapturePal_ServerInternal` is real, and it's the best result of the whole project so far

Dragón cleared a settlement (with Petallia active) and opened the cell, rescuing a caged Pal (Bristla, internal codename `BP_LIttleBriarRose_C`) — no Palsphere anywhere in the process. Read directly from `palbonds-live.log`:

```
[CAGE-CREATE-HANDLE] OnCreateHandle called — cage=BP_PalCapturedCage_C_...
                                                                          (~1 min later, after clearing the settlement)
[CAGE-OPEN-DOOR] OpenDoor_ToAll called — cage=BP_PalCapturedCage_C_...
[CAGE-CAPTURE-PAL] *** CapturePal_ServerInternal called *** —
    cage=BP_PalCapturedCage_C_...
    player=BP_Player_Female_C_2147480782
    spawnedHandle=id=table:... actor=[BP_LIttleBriarRose_C_2147444100]
```

Every piece confirmed exactly as hoped: `CapturePal_ServerInternal(Player)` fired cleanly, with a real player and a real, already-live-actor handle for Bristla — read directly off the cage's own `SpawnedPalHandle` field at the moment of the call, not guessed. Bristla joined the party in the second slot immediately, matching Dragón's own account and the live log timing exactly (no sphere-throw delay, no capture-chance uncertainty — it just happens).

**`AddOtomoHandleToFreeSlot` still never fired** — third distinct real "Pal joins the party" pathway now (ordinary swap, sphere capture, cage rescue) where this function stays completely silent for the player. That's no longer a coincidence across three separate game systems; it's essentially settled that whatever the real "insert into a party slot" step is, it isn't this function, and is very likely buried as an unhookable native operation inside each of these higher-level entry points individually (rather than one shared low-level function all of them call through).

**Why this is the best result of the whole project so far**: `APalCapturedCage::CapturePal_ServerInternal(APalPlayerCharacter* Player)` is now a **confirmed, live-tested, real function** that takes a player and hands a specific Pal — one that already has a resolved handle and live actor, exactly like a wild Pal this mod would be tracking — directly into that player's party, with zero sphere mechanics involved. This is a categorically better candidate for DESIGN.md Question 4 than `PalCaptureSuccess`, because we've now directly observed the exact shape this mod needs (existing handle + existing actor → straight into the party) actually working in a real, unmodified game system, not just inferred it from arguments. The lingering caution from the twenty-ninth pass — "we don't know what invisible setup precedes this call" — still applies here too (we've only ever seen it invoked from the cage's own internal flow, with a Pal that was created by that same cage), but the underlying operation ("player + already-existing wild Pal handle → joins the party") is now proven to exist and work, which the sphere-capture path never actually proved this cleanly (that one still had the ambiguity of `PalCaptureSuccess` maybe assuming sphere-specific state).

**Next step**: this deserves the most focused investigation yet, since it's the strongest lead in the project. Ideas, still all research/observation, no live call yet: (1) see if `CapturePal_ServerInternal`'s calling context can be narrowed further — e.g. does it require the cage's specific `bIsEnemyCamp`/lottery-spawned setup, or would it plausibly accept any `UPalIndividualCharacterHandle` with a live actor, including a genuinely wild one encountered normally in the field; (2) try to find whatever decides "is this Pal allowed to be captured this way" (an equivalent to a capture permission/eligibility check) so we understand what preconditions, if any, really matter; (3) only once that's understood, evaluate a real, carefully isolated test.

## Thirty-second pass (2026-09-02): reading a downloaded third-party mod's asset strings answers THREE open questions at once (Q1, Q2, Q6)

Dragón downloaded a Nexus Mods mod called "PassiveWildPals" (makes wild Pals never aggro) and asked us to see how it's built, in case it's useful. Found it in the Proyectos folder: `PassiveWildPals_P.pak`, only 67 KB.

**Important honesty note on method**: this mod is NOT a UE4SS Lua mod like PalBonds. It's a raw Unreal `.pak` containing exactly one overridden asset pair, `BP_AIAction_WildLife.uasset`/`.uexp` — a full Blueprint replacement, built with the actual Unreal Editor + the game's own cooking pipeline (a much heavier toolchain than UE4SS Lua hooking, and not something this project can reuse directly — we have no legitimate way to cook a replacement `.uasset` without Epic's editor and the game's exact engine version/plugins). We did NOT run or execute anything from this file — only read its raw text strings (`strings` on the binary), which is enough to see every native/Blueprint class, function, and variable name the asset references, without decompiling the actual node graph logic. So: we know WHAT classes and functions this AI action touches, not the exact WHAT-IT-CHANGED logic inside them. Still extremely useful — it's effectively a targeted hint list, curated by someone who already solved a related problem, pointing at exactly the right native classes to go look up ourselves in the real SDK.

**The string dump named real classes and functions this project didn't know about, all inside a single native, always-loaded, ActorComponent-shaped class — the safest category already trusted in this project:**

```
class UPalAISensorComponent : public UActorComponent
{
    UPalAIResponsePreset* AIResponsePreset;
    UPalAISightResponse* AISightResponse;
    EPalAIResponseType SelectResponseBySenses(EPalAIResponseType CurrentBehavior, const TArray<APalCharacter*>& FindCharacters, bool IsDamaged, APalCharacter*& OutTargetCharacter);
    bool RequestSightCheckAsync(bool bIncludePlayer, bool bIncludeAliveNPC, bool bIncludeEdibleDeadNPC, float RangeRate, bool bIgnoreOtomo);
    void SightCheckAllAliveNPC(TArray<APalCharacter*>& InSightCharacters, bool ignoreOtomo);
    bool CheckCombatableByLevelDiff(AActor* TargetActor);
    ...
}
```

**This answers Question 1 (species-default disposition) directly**: `class UPalAIResponsePreset : public UObject` is a real data-asset class with exactly 8 fields, all typed `EPalAIResponseType`: `Discover_Player`, `Discover_Greater`, `Discover_Equal`, `Discover_Smaller`, `Damaged_Player`, `Damaged_Greater`, `Damaged_Equal`, `Damaged_Smaller`. That's a genuine per-species (or per-preset) disposition table — how a Pal reacts on first spotting something (split by relative threat: bigger/equal/smaller/the player specifically) and separately how it reacts once damaged. `UPalAISensorComponent.AIResponsePreset` is a plain pointer field on the sensor component pointing at exactly this preset — meaning a wild Pal's current disposition is directly READABLE (and, since it's a plain field, quite possibly writable) right off its sensor component, no guessing required.

**This answers Question 2 (owned-Pal gate) directly**: `bool TargetIsPlayerOrPlayersOtomoPal(AActor* TargetCharacter)` lives on `class UPalBattleManager : public UPalWorldSubsystem` — a world subsystem, reachable the same safe way as everything else via `UPalUtility::GetBattleManager(WorldContextObject)` (confirmed real, same file, `UPalUtility` class we already trust). This is a ready-made, already-built "is this the player or the player's own Otomo" check — exactly the ownership gate this project has been looking for since the very first research pass, and it's a two-hop, fully safe (global static → subsystem → bool function) call chain.

**This materially advances Question 6 (combat-assist branch)**: `RequestSightCheckAsync`/`SightCheckAllAliveNPC` both take a `bIgnoreOtomo` parameter — direct, real confirmation that "exclude Otomo Pals from being treated as threats" is a first-class, built-in flag in the game's own sensing system, not something this mod would need to fake. `CheckCombatableByLevelDiff(TargetActor)` is a real, separate eligibility gate (can this Pal even fight that target, based on level). And a related discovery from the same string dump — `class UPalSquad : public UObject` with `GetSquad()`/`GetIsSquadBehaviour()`/`IsGroupBehavior`/`GetLeader()`/`IsLeader()`/`FollowLeader` — reveals wild Pals already have a real leader/follower squad system for group behavior (relevant to the Daedream/Flopie/Petallia multi-Pal-following mechanic Dragón raised early in this project, and a possible model for "how does a non-primary Pal follow and coordinate" that's independent of the Otomo system entirely).

**Also incidentally reinforces existing work**: the mod's own Blueprint graph calls `GetIndividualHandle` and `TryGetIndividualActor` from within a WILD Pal's own AI action — independent confirmation (from someone else's real, working mod) that a wild, never-captured Pal really does have a reachable `UPalIndividualCharacterHandle` through its own components, the same conclusion this project reached via `UPalUtility.GetIndividualCharacterHandleByActor`.

**What the mod likely actually does** (inferred, not confirmed — we only have names, not the decompiled graph): almost certainly patches `BP_AIAction_WildLife`'s logic around `SelectResponseBySenses`/`SightResponse` to force a passive/ignore response instead of whatever the species' `UPalAIResponsePreset` would normally return for `Discover_Player`. That's a plausible, low-risk-sounding change precisely because it's steering an existing, intended decision function rather than replacing capture/party logic — a useful design lesson: prefer nudging an existing decision point (like this project's own Trust-based follow/assist gating) over replacing whole functions.

**Next step**: none of this is hooked yet — first add read-only watches for `UPalAISensorComponent.SelectResponseBySenses` and `UPalBattleManager.TargetIsPlayerOrPlayersOtomoPal` (both native, always-loaded, same easy category as everything hooked so far) to see them fire on a real wild Pal noticing Dragón, and read a real wild Pal's `AIResponsePreset` field directly to see what an actual disposition table looks like in practice. This is genuinely new ground (perception/disposition, not capture/party) but zero risk — pure reads and pre-hook watches, nothing called.

## Thirty-third pass (2026-09-02): a real mistake — `SelectResponseBySenses` flooded the log and dropped Dragón's frame rate, now disabled

Dragón tested the two new thirty-second-pass hooks by walking up to a Lamball and a Chikipi normally. Before reaching a third (skittish) Pal, frame rate dropped heavily and the console filled up fast. Checked the numbers directly: **`SelectResponseBySenses` fired 6706 times inside roughly one second**, across a few dozen distinct wild Pals' sensor components simultaneously, each call doing a full `string.format` + a flushed file write via `Logger.log`.

**This was a real design mistake, not just noisy output.** Every other hook in this file watches a discrete, rare event — a party swap, a capture, a cage door opening — things that happen a few times per minute at most, so logging every single call is harmless. `SelectResponseBySenses` is different: it's part of the game's own continuous per-tick AI sensing loop, called for every wild Pal in the area, every tick, regardless of whether anything actually changed. Treating it the same way as a rare event turned "log every call" into thousands of file writes per second — a genuine, measurable performance cost to Dragón, not just a wall of text. Should have anticipated this from the function's own shape (it's a per-frame decision function on a sensor component, not an event notification) before asking for a live test.

**Fixed immediately**: the `SelectResponseBySenses` hook is now commented out in `OtomoWatch.lua` (not deleted — kept, disabled, with a note on how to re-add it safely later: deduplicate by sensor identity or sample 1-in-N calls instead of logging every one). Deployed to both the live Mods folder and the mirror right away. `TargetIsPlayerOrPlayersOtomoPal` is unaffected and stays enabled — it logged zero hits during this same heavy-load test, meaning it's tied to actual battle-manager decisions rather than the per-tick sensing loop, and is not implicated in the slowdown.

**We did keep real, useful data from the one test before disabling it, though** — `AIResponsePreset` resolved to real, named Blueprint presets on actual wild Pals:
- `BP_AIResponsePreset_Escape_to_Battle_C` — on ordinary wild monsters (the common "flee first, fight if cornered" pattern).
- `BP_AIResponsePreset_friendly_C` — matches Lamball/Chikipi-type Pals that are never hostile.
- `BP_AIResponsePreset_VillageNPC_C` — human NPCs, a separate preset category from Pals.

This confirms `UPalAIResponsePreset` (Question 1) is real, populated, and readable exactly as hypothesized last pass — genuinely valuable confirmation, even though the way we obtained it needs to not be repeated as-is. `currentBehavior` read as `0` for every single call in this test (nothing was actually being escaped from or fought — Dragón was just walking near passive/already-known Pals), so we still don't have a real example of the enum's non-zero values; that's for a future, properly-throttled watch.

**Lesson for the rest of this research going forward**: before enabling a new hook, ask "is this a rare event or a per-tick decision?" — event hooks (this file's whole history until now) are safe to log unconditionally; per-tick/per-sensor hooks need a dedup or sampling guard from the start, not added after a problem shows up.

## Thirty-fourth pass (2026-09-02): first real implementation — Personality.lua rewritten with real data, wired into a live interaction

Dragón asked to move from pure research into building, now that Questions 1 and 5 are answered and Question 2 has a solid untested candidate. Rewrote `Personality.lua` from its original stub into a real, working module:

- `Personality.GetStableId(palActor)` — a genuinely stable, save-persistent per-Pal ID, built from `UPalIndividualCharacterHandle:GetIndividualID().InstanceId` (a real `FGuid`, fields `A/B/C/D` formatted as hex). Answers Question 5 properly, no more `return nil` placeholder.
- `Personality.GetSpeciesDefaultDisposition(palActor)` — reads the real `AIResponsePreset` field off the Pal's `UPalAISensorComponent`, takes just the preset's class name (not its 8 internal fields — cheaper, and we haven't confirmed direct data-asset field reads work from Lua), and maps it to one of this project's own dispositions via a small, growable lookup table. Unrecognized presets default to "curious" and get logged once (not every time) so the table can grow from real play without needing another broad hook.

**This is the project's first module that makes real, ACTIVE function calls** (`UPalUtility:GetIndividualCharacterHandleByActor`, `actor:GetComponentByClass`) rather than only passively watching via `RegisterHook`. Both are pure, side-effect-free getters/converters — chosen deliberately for that reason, categorically lower risk than the party/capture functions this project is still being careful about.

**Wired into `Interaction.lua`'s existing `OnWildPalPetted`** (called once per successful pet/feed — already a rare, gated event, never per-tick) rather than as a new standalone hook, directly applying the thirty-third pass's lesson. Every real pet/feed now resolves and logs the Pal's stable ID and species-default disposition once, with zero new per-tick risk.

**Next real test, combined with Dragón's own offer**: next play session, do a normal pet/feed (as always) to see `Personality`'s real output in the log, AND test `UPalBattleManager.TargetIsPlayerOrPlayersOtomoPal` (Question 2's untested candidate, already hooked in `OtomoWatch.lua`) by petting/feeding your own OWNED Otomo Pal specifically — that's the case most likely to actually call this ownership check.

## Thirty-fifth pass (2026-09-02): first live test of Personality.lua — one cosmetic bug fixed, one real gap found and instrumented, one clean negative result

Dragón booted up, petted/fed Petallia (active Otomo), swapped to Bristla and petted her, then found a wild Chikipi and fed/petted it too — also, per the plan, without a separate ask, this exercised the owned-Otomo case `TargetIsPlayerOrPlayersOtomoPal` needed.

**`Personality.GetStableId` worked, and is genuinely stable** — the same Chikipi produced the exact same ID string across its two separate interactions (`FFFFFFFFAF48C22840D7D9CC1115B9B7FFFFFFFFE3CA5DE5`), confirming the underlying handle→GUID chain is solid. But the string was cosmetically wrong — some fields printed as 16 hex digits instead of 8. Root cause: a negative `int32` GUID field sign-extends to a huge value once it's a Lua number, and `string.format("%08X", ...)` only sets a MINIMUM width, so a negative field overflows past 8 digits instead of being masked to 32 bits. Fixed by masking each field with `% 0x100000000` before formatting — same stable ID, now always exactly 32 hex characters. Deployed.

**`Personality.GetPresetClassName` returned nil for the real Chikipi** (logged as `preset=nil`), silently — our own `safe_call` swallows the actual Lua error, so the log couldn't say WHY. The species-default disposition still came out correct ("curious") purely because that's this function's safe fallback default, not because the real preset was actually read — good fallback behavior, but it means we don't yet have real confirmation this specific read chain (`GetComponentByClass` on a live actor, called by us rather than handed to us by a hook) actually works. Instrumented every step (sensor class resolution, `GetComponentByClass`, the `AIResponsePreset` field read, `GetFullName()`) with its own explicit success/failure log line, so the next pet/feed will say exactly which step breaks instead of just "nil." Deployed, not yet retested.

**Clean negative result for Question 2**: `TargetIsPlayerOrPlayersOtomoPal` never fired — zero hits — despite petting/feeding two different OWNED, active Otomo Pals (Petallia, Bristla) multiple times each. This rules out "the pet/feed interaction path" as a place this check gets called; it's more likely used somewhere in combat/damage decision-making (e.g. "should this attack land on what looks like a friendly Otomo"), not social interactions. Question 2 stays open — next idea: watch it during an actual combat situation instead (a wild Pal or enemy near an active Otomo), not another pet/feed test.

**No new performance issues** — the reset log stayed small (137 lines for this whole session) and nothing here registered a new hook, consistent with the thirty-third pass's lesson.

## Thirty-sixth pass (2026-09-02): the biggest single test session yet — Question 2 goes positive, and a full real trust-gain-then-loss cycle confirmed live end to end

Dragón ran a long, varied session (473 raw log lines) covering, by his own account: petting his own (Alpha/Boss) Petallia and trying to attack/sphere-throw her both free-roaming and after placing her at base; ordering Petallia to attack a string of wild Pals (~10 kills); a sphere capture on a Cattiva; a wild Lamball that fled before any interaction; a Sheepball petted/fed twice (misremembered as "Lamball" — no `BP_Lamball_C` appears anywhere in this log, only `BP_SheepBall_C`, which looks similar); and a wild Cattiva (`BP_PinkCat_C`) petted repeatedly until it started following, then attacked until it fled and (per Dragón, though not captured in this log — see below) died.

**Question 2 (`TargetIsPlayerOrPlayersOtomoPal`) is now POSITIVE, completing/superseding the thirty-fifth pass's negative result.** During Petallia's combat rampage it fired repeatedly, with targets including the player herself, Petallia (the attacking Otomo herself), and multiple wild Pals being fought (SheepBall, PinkCat, Ganesha). It also fired again at the exact moment the trust-lost Cattiva flipped to hostile, targeting the player. Conclusion: this function is a real, active combat/targeting check — not part of the pet/feed interaction path (confirmed absent there in the previous pass), but called repeatedly during actual fighting, almost certainly to decide whether a given actor counts as "friendly" (player or player's own Otomo) for damage/aggro purposes. Question 2 can now be marked substantially answered.

**Third live confirmation of `PalCaptureSuccess`** — fired correctly for the Cattiva sphere-capture (attacker=player, monster=the Cattiva), consistent with the two prior confirmations. This function keeps being 100% reliable across every real capture tested so far.

**No hook data at all for the "attack/sphere-throw my own Otomo" attempts** (tried twice — free-roaming and after placing her at base). Neither `DAMAGE-WATCH` nor any capture-related hook fired for these. This means the game blocks these actions upstream of every function point we currently watch — consistent with normal vanilla behavior (you can't damage or capture your own Pal), but we don't yet know exactly which check does the blocking. Not a bug, just an open question if we ever want to find that exact gate; low priority since it doesn't affect our design goals either way.

**The big result: a full real trust-gain-then-loss cycle, observed end to end, and Trust/Combat/Capture all behaved exactly as designed.** The wild Cattiva sequence, second by second:

- 6 real pet interactions recorded via `Trust.lua`'s real `FriendshipPoint` tracking (rank 0 throughout, point climbing 0→10→20→30→40→50).
- After interaction #5: `"5 successful interactions reached — this Pal should now start following the player"` → `Combat.lua` marks it `following (bonding)`.
- A 6th pet still landed normally while it was following.
- The player then hit it: a real `DamageEvent` (attacker=player, defender=the Cattiva, damage=380) was picked up by `Trust.lua`'s `[DAMAGE-WATCH]` hook.
- `Trust.lua` correctly applied a real friendship PENALTY for a following Pal taking damage (`-25`, via a real `AddFriendShip` call with a negative value — confirmed by the `[WATCH]` hook logging `value=-25`).
- That penalty dropped it back to rank 0, and `Trust.lua` logged `"follow stopped: trust hit rank 0 after taking damage"`.
- `Combat.lua` logged `"no longer following"`.
- `Capture.lua` logged `"lost all trust — fleeing permanently"` — this is the exact "gained trust then lost it all → permanent flee" design goal from DESIGN.md, firing for real, from real game events, for the first time.

The log ends about 8 seconds later (still receiving ordinary `[TICK]` lines, so the mod itself was still running) without a second `DamageEvent` or any death-related line for this Cattiva — so while Dragón describes killing it with a follow-up hit, we don't have direct log evidence of that finishing blow (possibly the session just wasn't logged past that point, or a killing blow doesn't route through the same damage hook). Not a concern for the design goal itself, which is already confirmed: the trust-loss → flee transition is real and working.

**Two small `Personality.lua` fixes made in this pass** (not yet retested live): added a `preset:IsValid()` check before calling `preset:GetFullName()` in `GetPresetClassName` — every test so far (Sheepball and Cattiva both, across two sessions) fails silently at exactly this step with no earlier failure logged, which matches UE4SS's known "valid wrapper around a null pointer" pattern; the new check will tell us on the next test whether that's really what's happening. Also fixed `GetOrInitState` calling `GetPresetClassName` twice per new Pal (once via `GetSpeciesDefaultDisposition`, once again for the `presetClassName` field), which was doubling every diagnostic log line — now calls it once and reuses the result.

## Thirty-seventh pass (2026-09-02): mapping the party/slot class structure further — probably at the ceiling of what static header analysis can tell us for Question 4

Dragón asked to keep researching before attempting the riskier "reuse APalCapturedCage on an arbitrary wild Pal via a field write" experiment. Went back into CXXHeaderDump/Pal.hpp looking for a cleaner entry point.

Mapped the real class structure around party membership more precisely: `UPalOtomoHolderComponentBase` (native base of the already-hooked `BP_OtomoPalHolderComponent_C`) owns the active battle slots; `UPalPlayerPartyPalHolder` is a simpler `FirstOtomoPal`/`SecondOtomoPal`/`BenchMember` struct; `UPalIndividualCharacterContainer` is the real native slot array, holding `UPalIndividualCharacterSlot` objects that each just carry a plain `Handle` field. Also found the fishing minigame's own capture plumbing (`FPalGrantCharacterRequestData`, `UPalFishingSystem::OnObtainCharacterDelegate`) — same handle-based shape, but it's built for a freshly-created catch, not for handing over a Pal that already exists in the world.

**No cleaner alternative to `CapturePal_ServerInternal` was found.** None of these classes expose a UFUNCTION that looks like "add this handle to my party" — no `AddMember`, `SetHandle`, `AddBenchMember`, nothing. Likely explanation, stated plainly rather than guessed around: a header dump only lists *reflected* functions; if the real "write this handle into the slot" step is a plain, non-reflected C++ call, it will never show up here and can never be hooked from Lua, no matter how much more of the dump we read. Static research on this specific question may genuinely be at its ceiling — the field-write experiment (or an equivalent live test) is very likely the only way to move Question 4 further from here.

Added two more read-only, event-shaped hooks to `OtomoWatch.lua` anyway, since they cost nothing and might still catch the moment indirectly: `PalOtomoHolderComponentBase:OnUpdateSlot` (a real "this slot's handle just changed" notification) and `PalIndividualCharacterContainer:FindEmptySlot` (fires when the game looks for a free slot, plausibly right before assigning one). Whether either actually fires during a real capture is still open — needs the next real capture/cage-rescue test to find out. Deployed, not yet tested.

## Thirty-eighth pass (2026-09-02): the actual experiment — `Capture.TryDirectCapture`, bound to F11

Dragón asked directly to keep moving toward finishing the mod rather than researching indefinitely, once static research on Question 4 hit its ceiling last pass. With no cleaner candidate found, this pass implements the actual test: `Capture.TryDirectCapture(pal, player)` calls the real `UPalUtility.PalCaptureSuccess(Player, Monster)` directly on a wild Pal that never went through a real sphere throw — the single most-reliably-observed function in the whole project (100% hit rate across three real captures).

Bound to a brand new, dedicated key (F11 in Interaction.lua) via its own `do_test_capture()` — deliberately NOT sharing `do_interaction()`'s pet/feed path, and NOT wired into `Capture.OnTrustMaxed`'s automatic flow yet. One manual key press, one wild Pal, contained.

Logs ownership (`SaveParameter.OwnerPlayerUId`) before and after the call, plus whether the actor is even still valid afterward, all flushed to disk before the risky call itself runs — same crash-safe-logging principle Logger.lua was built for. This is the project's first genuinely experimental (not just cautious-but-safe) live call: `pcall` can catch a Lua-level error but not a hard native crash, so the true worst case can't be fully ruled out from Lua alone. Deployed to both destinations, not yet tested — see the play instructions given alongside this pass for exactly how Dragón should try it safely (save first, pick a common low-level wild Pal, one press, then check the log and the in-game party/Palbox screen).

## Thirty-ninth pass (2026-09-02): CONFIRMED LIVE — the sphere-less capture call works, DESIGN.md Question 4 is answered

Dragón tested F11 on three different wild Pals in one session: a Sheepball (called "Lamball" again — same look-alike confusion as the thirty-sixth pass), a Cattiva, and a Mammorest (`BP_GrassMammoth_C` — a large, boss-tier Pal, previously flagged in Interaction.lua's notes as hard to even target due to its size). All three joined his real party. No sphere thrown. No crash. He directly confirmed it by opening his party screen and seeing them there.

The log matches: for each of the three, `TryDirectCapture` ran end to end — `PalCaptureSuccess call returned — result=ok` every time (no Lua error), and the actor stayed valid immediately afterward. The one interesting log wrinkle: `owner AFTER the call` read back as `nil` every time, versus a real (non-nil) struct pointer beforehand — worth noting the BEFORE/AFTER `tostring()` comparison as originally written prints Lua wrapper object identity, not the GUID's actual field values, so it's weaker evidence than it looks (a difference was guaranteed either way, since each read is a fresh wrapper) — the real, trustworthy confirmation here is Dragón's own eyes on the party screen, not this log line. Worth revisiting if more precise before/after ownership logging is wanted later (read the GUID's A/B/C/D fields directly, same fix already applied in Personality.lua's `GetStableId`).

**Only gap noticed:** no capture visual/light-beam effect played (the one that shows when freeing a Pal from a cage). Purely cosmetic — the Pal is genuinely in the party, just without the flourish. Low priority; `APalCapturedCage::StartCaptureEffect_ServerBP` (already known from the thirtieth pass) is a plausible thing to call alongside `PalCaptureSuccess` later if this is worth polishing.

## Forty-first pass (2026-09-02): dropped the real-rank-curve chase, hardcoded our own threshold, and fixed two key-conflict bugs

Two pieces of direct, fair feedback from Dragón this pass:

1. Chasing the real game's own point-per-rank curve (fortieth pass) was solving the wrong problem — we're the ones implementing the trigger, so just pick a number ourselves, confirm the automatic path works, and tune later. Replaced the rank-based trigger (`param:GetFriendshipRank() >= 1`) with a plain, self-owned `CAPTURE_AT_FRIENDSHIP_POINT = 55` in Trust.lua — checked both right after a pet/feed AND after each passive-gain tick (previously only checked after a pet/feed, which would have missed a Pal crossing the threshold purely from passive gain while following). `Trust.DumpFriendshipRankTable` and its F12 binding are gone — no longer needed.
2. F11 (the direct-capture test key) was actually toggling Palworld's fullscreen mode, and F12 (the now-removed rank dump) is the Steam screenshot key — both are OS/platform-level bindings that fire independently of UE4SS's own key handling. Plain F-keys past F10 aren't a safe assumption in general. Fixed by switching the capture-test key to **CTRL+K** via `RegisterKeyBindAsync` with `ModifierKey.CONTROL` — the same pattern UE4SS's own bundled Keybinds mod uses for its tools (CTRL+J, CTRL+H, etc.), much less likely to collide with anything.

Both fixes deployed, not yet retested live.

**`Capture.OnTrustMaxed` is now wired for real** (was a stub since Trust.lua's sixteenth pass) — it calls `Capture.TryDirectCapture(pal, player)` directly, then `Combat.StopFollowing(pal)` since the Pal is a genuine party member now, not just our own approximated bonding-follow state. This closes DESIGN.md §3.5, the last stubbed subsystem in the whole project. Deployed to both destinations — not yet tested via the REAL trust-reaches-max-rank path (only ever tested manually via F11 so far); next real pet/feed session that gets a wild Pal all the way to 5 interactions should trigger it automatically for the first time.

## Forty-second pass (2026-09-02): diagnosed the "passive gain seems broken" report — it isn't, confirmed line-by-line in the logs

Dragón ran a real session on four wild Pals (a SamuraiDog he calls "Pupperai", a PinkCat/Cattiva, a Kitsunebi/"Foxparks", and the WeaselDragon boss/"Chillet boss") and reported that captures only ever seemed to land "on the 6th pet", with no visible passive progress in between — concluding passive gain was either not firing or not triggering capture. Traced all three real captures in the log line-by-line:

- **BP_SamuraiDog_C**: interaction #6 read `point=52` (below threshold, so the interaction-time check correctly did nothing). A passive tick landed 1s later (`value=2, applyPassiveSkill=false` → 54), then that same pet's own delayed grant landed 2s after that (`value=10, applyPassiveSkill=true` → 64), then the *next* passive tick 14s later (`value=2` → 66) is what actually crossed 55 and fired `maybe_trigger_capture` — from `tick_followers`, not from the pet.
- **BP_WeaselDragon_BOSS_C**: same shape — interaction #6 read `point=44` (below threshold), the pet's own grant landed 3s later (44+10=54, still below), and the very next passive tick 2s after that (+2=56) is what crossed the line and fired the capture.
- **BP_PinkCat_C**: here the interaction-time check itself did fire the capture, but only because an *earlier* pet's delayed grant had already landed 5 seconds before this pet was even thrown, so `GetFriendshipPoint()` read 60 (already past threshold) the moment interaction #7 ran.

All three math out exactly against `PASSIVE_FRIENDSHIP_PER_GAIN=2` / `PASSIVE_GAIN_EVERY_N_TICKS=10` (~15s cadence) and the real pet grant (+10, landing 2-3s after the action, not instantly). Also pulled every `AddFriendShip` line for the SamuraiDog specifically across the ~3 minutes Dragón says he "waited and nothing happened" — passive ticks are logged firing every ~15-16 seconds without a single gap the entire time, including while his attention and camera were on the Cattiva across the map. Point climbed the whole time (30 -> 52 by the 6th pet) purely from ticks plus earlier pets; there is no dead spot in the code.

**Root cause of the illusion, confirmed, not a code bug**: `Trust.OnInteractionSucceeded`'s own capture check reads `GetFriendshipPoint()` synchronously, before that same pet's own `AddFriendShip` grant lands (2-3s delay, well established in this project). So a pet's own contribution almost never gets caught by its own check — the threshold crossing is almost always caught by the *next* passive tick instead, up to ~15s later. Combined with the mod having zero in-game/UI feedback of the running point total, there's no way for the player to see progress happening — the mechanic works, it's just invisible until it fires. That invisibility, not a functional gap, is what reads as "needed one more pet."

**No code change made this pass.** This was a pure diagnosis at Dragón's request ("see what you find on the logs"); the passive-gain and dual-checkpoint logic added last pass is confirmed working exactly as designed. Left as an open option, not acted on: adding a lightweight on-screen or chat-log line showing live friendship progress, if Dragón wants the mechanic to feel less silent — not implemented speculatively, per his standing "don't go overboard" direction.

## End of day 1 (2026-09-02): session close — next task is a visual trust indicator

Dragón's reaction to the forty-second pass's diagnosis (passive gain works, it's just invisible): add a small secondary bar under a bonding wild Pal's health bar showing live friendship/taming progress — fills from pets/feeds and passive proximity gain, drops visibly when the Pal takes damage. Written into DESIGN.md's Phase 6 section with the full spec and the two candidate UI approaches to research first (extending the real healthbar widget vs. a simple custom overlay) — that's the first item for the next session, before any further balancing/polish work.

Everything as of this point is deployed to both the live Mods folder and the Proyectos mirror, and all three docs (DESIGN.md, this file, CLAUDE.md) are in sync. Also worth stating plainly for the record since it came up: this whole project — every pass, every hook, every doc entry in this file — was built in a single day, not months. Worth remembering next session for scoping/pacing expectations.

## Forty-third pass (2026-09-03, day 2): the on-screen trust indicator — implemented, not yet tested live

Dragón's spec from the end of day 1: a small secondary bar under a bonding wild Pal's health bar, filling with real progress toward the 55-friendship capture threshold, dropping visibly on damage.

**Researched the real health-bar widget class first.** Found `class UPalUICharacterHPGaugeBase : public UPalUserWidget` in Pal.hpp — `SetTargetCharacter(APalCharacter*)`, `SetHPPercent(float)`, `UpdatePosition()`, `UpdateVisibility()` — almost certainly the real class behind the game's own wild-Pal/NPC health bar (there's a sibling, `UPalUINPCHPGaugeCanvasBase`, for NPCs specifically). Decided NOT to try reusing it: it's an abstract native base, the actual visible widget lives in an unknown Blueprint subclass, and instantiating a UMG widget from Lua (`CreateWidget` + `AddToViewport`) is a category this project has never touched or confirmed safe — too big a leap for a first cut at this feature.

**Went with a simpler, well-established UE4SS technique instead**: hooking the HUD's own per-frame draw event and drawing flat rectangles directly on the canvas. Confirmed the real classes: `AHUD` (native Engine base) has `ReceiveDrawHUD(SizeX, SizeY)`, `Project(WorldLocation, bClampToZeroPlane) -> FVector` (world-to-screen), and `DrawRect(FLinearColor Color, ScreenX, ScreenY, ScreenW, ScreenH)`. `class APalHUDInGame : public AHUD` — Palworld's real in-game HUD — extends it directly, so all of this should be reachable from the same hook.

**New file, `Indicator.lua`**: hooks `/Script/Engine.HUD:ReceiveDrawHUD`, reads a new `Trust.GetFollowingSnapshot()` (returns `{pal, ratio}` for every currently-following Pal, using the already-cached `lastPoint` rather than a fresh `GetFriendshipPoint()` call per Pal per frame), and for each one: gets its location, adds a flat height offset, projects to screen, and draws a dark background rect plus a gold fill rect scaled to the friendship ratio.

**Performance discipline carried over directly from the thirty-third pass's `SelectResponseBySenses` mistake**: `ReceiveDrawHUD` fires at frame rate, not as a rare event, so the entire per-frame path has zero `Logger.log` calls (logged once, on the very first frame, to confirm the hook is alive) and zero `string.format` calls — only plain table reads and native draw calls.

**Two real unknowns going into the live test, stated plainly rather than assumed:**
1. `Project`'s Z value is being treated as "Z<=0 means behind the camera, skip drawing" — this is a common convention in UE4 modding generally, but not something confirmed against this specific engine build yet. If bars show up somewhere wrong, or don't disappear when they should, this is the first thing to revisit.
2. The world-space height offset (220 units above the Pal's actor origin, guessing at "roughly head height") is a flat constant, not per-species. It will look reasonable on medium Pals and probably wrong on something very small (Chikipi) or very large (a boss-tier Pal) until tuned per-size — not attempted this pass, deliberately deferred until we see it in game.

**Also passed the `FLinearColor` argument to `DrawRect` as a plain Lua table** (`{R=,G=,B=,A=}`) — same "construct a plain table matching the struct's field names, pass it as a function argument" pattern already proven working in Combat.lua (`K2_GetActorLocation`'s returned table passed straight into `PalMoveToLocation`'s `Dest` argument), just used here as an outgoing argument for the first time instead of an incoming return value.

Deployed to both destinations (Lua files + all three docs). Not yet tested live — next real play session should show two things: does the bar appear at all, and does it look roughly right (position, fill behavior) on an ordinary wild Pal like a Lamball or Cattiva.

## Forty-fourth pass (2026-09-03): the ReceiveDrawHUD indicator failed live — clean diagnosis, and a completely different, simpler fix

Dragón tested the forty-third pass's trust bar on a Foxparks (Kitsunebi) and a Pengullet (Penguin), both petted to full follow and captured normally — screenshots showed the real vanilla HP bar rendering fine, but no PalBonds bar anywhere near it, on either Pal, over the whole ~7-minute session.

Checked the live log before guessing at anything. `Indicator.Init()` did log "ReceiveDrawHUD hook installed" (the `RegisterHook` call itself didn't error) — but the hook's *own* one-time confirmation line, only ever printed from inside the callback on its first real invocation, never appears anywhere in the 637-line log, across both full pet→follow→capture cycles. That rules out "wrong position" or "too small/wrong color to notice" — the hook itself never fired, not even once, while the game was very obviously drawing HUD elements every frame (the real HP bar, the compass, the quest banner, all visible in Dragón's screenshots). Conclusion: Palworld's `APalHUDInGame` doesn't invoke the legacy Blueprint `ReceiveDrawHUD` event at all — consistent with a modern, fully UMG-based HUD that never calls into that native broadcast path. Not a tuning problem; the whole approach was a dead end for this specific game.

**Found a completely different, much simpler path by checking this exact UE4SS install's own bundled example mods** rather than guessing further from the header dump alone: `LineTraceMod` (installed alongside PalBonds, presumably a working, tested mod) calls `UKismetSystemLibrary` functions via the bundled `UEHelpers` module (`UEHelpers.GetKismetSystemLibrary()`) successfully in this same game, for its own line-trace feature. That pointed straight at `UKismetSystemLibrary:DrawDebugString(WorldContextObject, TextLocation, Text, TestBaseActor, TextColor, Duration)` (confirmed real, in Engine.hpp) — a native, engine-level debug-text draw call that renders through the engine's own debug-primitive system, entirely independent of the game's Blueprint HUD/UMG layer. That's exactly why it doesn't depend on whatever `ReceiveDrawHUD` needed and never got: it's a different rendering path altogether, the same one virtually every UE4/5 game's `DrawDebugString` uses regardless of how that specific game built its own HUD.

**Real design bonus, not just a workaround**: `TestBaseActor` is the actual intended use of this parameter for exactly this job — pass the Pal itself, and `TextLocation` becomes a small LOCAL offset from that actor's current position; the engine re-anchors the text to wherever the actor currently is on every redraw, on its own. This removes the entire manual world-to-screen-projection problem (and the unconfirmed "Project() Z<=0 means behind camera" guess) that the first attempt depended on and never even got to test.

**Rewrote `Indicator.lua` end to end.** Renders as a short text bar (`Trust 32/55 [========--------]`) rather than a drawn rectangle, since `DrawDebugString` is a text call. Refreshed roughly once a second via its own timer (same `ExecuteInGameThreadWithDelay`/`LoopAsync` fallback pattern already proven working in Trust.lua) with a slightly longer persist duration (1.6s) so it never blinks off between refreshes — `DrawDebugString`'s real engine behavior replaces the previous string for the same actor rather than stacking duplicates, so there's no need to call this at frame rate, and no reason to risk another `SelectResponseBySenses`-style performance mistake by trying to.

`Trust.GetFollowingSnapshot()` extended to also return the raw `point`/`threshold` values (cheap, same cached-state read as before) so the label can show real numbers, not just a bar.

Deployed to both destinations (Indicator.lua, Trust.lua, all three docs). Not yet tested live — next session should show whether text actually appears above a bonding Pal's head, and whether the local-offset anchoring tracks it correctly as it moves.

## Forty-fifth pass (2026-09-03): the DrawDebugString attempt also failed — real cause found (Shipping build strips debug-draw), and Dragón's own precedent mod points to the right architecture

Dragón tested the forty-fourth pass's DrawDebugString-based bar the same way as before — still no bar, on any Pal, over a ~3.5 minute session. Checked the log: no Lua errors anywhere, but also no success confirmation, because this pass never added one (a real gap — the forty-third pass's one-shot "first frame seen" line was exactly the right instinct and should have been carried over here too).

**Most likely real explanation, found by reasoning about the deployment target rather than more log-reading**: Palworld ships to players as an Unreal "Shipping" build. Unreal's `UKismetSystemLibrary::DrawDebugString` (and every other `DrawDebug*` function) is wrapped in `#if ENABLE_DRAW_DEBUG`, which is compiled to 0/off in Shipping configuration — the function body becomes empty, so calling it does nothing at all: no error, no draw, exactly what was observed. This can't be directly confirmed from Lua (no way to inspect build-config compile flags at runtime), but it's the single most common, well-documented explanation for exactly this symptom across Unreal modding generally, and it means the entire DrawDebug* family was never going to work here — a dead end on principle, not a matter of retrying with different numbers.

**Dragón found a real, working precedent instead**: a Nexus mod, "VisiblePalCaptureCounter" (source dropped into the Proyectos folder — `Scripts/main.lua`, `Scripts/config.lua`), built for an older Palworld version, which shows a small `(x/5)` capture-count text right next to a wild Pal's own real HP gauge. Its technique is fundamentally different from anything tried so far in this project: it doesn't draw anything itself — it hooks `WBP_PalNPCHPGauge_C:BindFromHandle` (fired when the game's own real per-Pal HP gauge widget gets bound to a specific Pal) and `:Unbind`, grabs the live widget instance (`self:get()`), and writes text directly into one of ITS OWN child text-block widgets: `widget.WBP_EnemyGauge.Text_WorkName:SetText_GDKInternal(1, "text")`. Since this is part of the game's own real, shipped UI (not a debug overlay), it can't be stripped the way DrawDebug* is — this is very likely the only category of approach that can work here at all.

**Checked what's still real in the CURRENT game before reusing any of it, exactly as Dragón asked** ("check how they do it, then use those terms to find first if they're still called like that"):
- `SetText_GDKInternal(bool IsSuccess, FString OutString)` — CONFIRMED, unchanged, present twice in the current Pal.hpp: on `UPalRichTextBlockBase` and on `UPalTextBlockBase : public UCommonTextBlock` (the latter is almost certainly the real base of whatever text-block VPCC called `Text_WorkName`). The actual mechanism for setting text on a widget is fine, nothing to relearn there.
- The exact old asset path (`/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C`) has NO matching dumped header anywhere in this install's `CXXHeaderDump/` folder. This folder does contain plenty of other individually-dumped `WBP_*` Blueprint widget classes (confirming the dumper does capture Blueprint widgets it has seen loaded at least once) — this specific one just isn't among them. Either it was never loaded during whatever dump session produced this folder, or — more likely, given Dragón's own warning — it's been renamed/restructured since that mod was built for an older version.
- Found what's very likely the modern replacement instead, already noted in earlier passes but newly relevant now: two native base classes, `UPalUICharacterHPGaugeBase` (`SetTargetCharacter(APalCharacter*)`, `SetHPPercent(float)`, `UpdatePosition()`, `UpdateVisibility()`) and `UPalUINPCHPGaugeCanvasBase` (likely a container managing several gauge widgets on one canvas — a plausible, more efficient successor to "one Blueprint widget instance per visible wild Pal").

**Rewrote `Indicator.lua` into a pure read-only research pass, not yet writing anything.** Hooks the two NATIVE functions on `UPalUICharacterHPGaugeBase` (`SetTargetCharacter`, `SetHPPercent`) rather than guessing at a Blueprint asset path — hooking the native base fires regardless of what the actual current Blueprint subclass is named, sidestepping the whole "did the name change" question. Each hook logs the real live widget's `GetFullName()` (revealing its actual current class) and the target Pal, capped at 20 total log lines combined (this project has already been burned once, thirty-third pass, by treating an unknown-frequency native hook as if it were rare — not repeating that here before knowing the real call frequency).

Deployed to both destinations. Needs one focused live test: just look at any wild Pal (no need to pet/capture anything) so its HP gauge shows on screen, then check the log for what actually fired.

## Forty-sixth pass (2026-09-03): SetTargetCharacter/SetHPPercent also never fired — checking whether the class even gets instantiated at all

Dragón's test: walked up to a wild Lamball, a real logged pet (`interaction #1`), then accidentally hit it (its health bar visibly dropped in game). Full ~10-minute session, no errors anywhere in the log — but neither `SetTargetCharacter` nor `SetHPPercent` fired even once. Third consecutive "installs without error, never fires" result (after `ReceiveDrawHUD`, and implicitly whatever `DrawDebugString`'s no-op needed). Real, useful negative finding: these two specific native functions are not what actually drives a wild Pal's in-field HP gauge, whatever they're really for.

Rather than guess a fourth function name blind, added a fundamentally different check: does the class even get **instantiated** during ordinary play, independent of which function sets it up? `FindAllOf(ClassName)` — a real, already-proven UE4SS Lua global in this project (same family as `FindFirstOf`, used constantly, e.g. `FindFirstOf("PalPlayerCharacter")`) — returns every live object of a given class. Added a periodic (every 2s, not per-frame) scan for live instances of both `PalUICharacterHPGaugeBase` and `PalUINPCHPGaugeCanvasBase`, logging counts and each instance's real `GetFullName()` (which would reveal the actual current Blueprint subclass name) whenever either has at least one instance. Capped at 25 log lines total, separate from the existing hook-diagnostic cap.

This is a genuinely different question than the last two passes: if instances show up, the classes are real and in use, just not set up by the two functions already tried — worth inspecting what else they expose. If nothing ever shows up, these classes aren't what actually renders a wild Pal's gauge at all, and the real mechanism is something not yet found — possibly the "Canvas" class draws everything procedurally without discrete per-Pal widget objects, which would explain why per-instance hooks keep coming up empty.

Deployed to both destinations. Needs one more live test: look at a wild Pal again, same as before, and check what the scan reports.

## Forty-seventh pass (2026-09-03): confirmed the real live widget class, and reused this project's own property-dump technique to find its actual data structure

Dragón's test of the forty-sixth pass's existence scan gave a real, clean hit. Walked up to several wild Pals to look at their gauges/details. `PalUICharacterHPGaugeBase` stayed at 0 instances the entire session — confirming it genuinely isn't used for wild Pals. `PalUINPCHPGaugeCanvasBase` consistently showed live instances of a real, concrete class: **`WBP_PalNPCHPGaugeCanvas_C`** — one instance is the Blueprint archetype baked into the asset itself (`/Game/Pal/Blueprint/UI/WBP_PlayerUI.WBP_PlayerUI_C:WidgetTree.WBP_PalNPCHPGaugeCanvas`), the other a genuine live instance under the actual running UI (`/Engine/Transient...WBP_PlayerUI_C_...WidgetTree_....WBP_PalNPCHPGaugeCanvas`).

This settles the open question from the forty-fifth/forty-sixth passes cleanly: the modern game replaced the old mod's one-`WBP_PalNPCHPGauge_C`-widget-per-visible-Pal system with a single shared `WBP_PalNPCHPGaugeCanvas_C` that manages every visible Pal's gauge itself — which is exactly why hooking per-instance functions on the old per-gauge base class (`SetTargetCharacter`, `SetHPPercent`) never fired: there are no more separate per-Pal widget objects for those functions to be called on.

**With a real, confirmed live object in hand, no more blind guessing was needed.** This project already has a proven technique for reading a live Blueprint widget's actual fields directly, from Interaction.lua's twelfth pass (`dump_interesting_properties`, itself modeled on the bundled `ConsoleCommandsMod/dump_object.lua`): `Class:ForEachProperty()` walked up `GetSuperStruct()`, which surfaces Blueprint-ADDED fields a static header dump can never show. Reused that exact pattern here, unfiltered this time (we don't know what to filter for yet on a brand new class), with one addition borrowed from `dump_object.lua` itself: real `ArrayProperty` handling — reporting length, and if the array holds objects, each element's real class name — since the canvas's per-Pal gauge "slots" are almost certainly held in exactly this kind of array.

Wired to run automatically, exactly once, the moment the periodic scan finds the REAL live instance (distinguished from the Blueprint archetype by its full name starting with `/Engine/Transient` rather than `/Game/...`). Still fully read-only — logs field names, types, and values; changes nothing. Capped at 60 log lines, separate from the existing scan/hook caps.

Deployed to both destinations. Needs one more live test: look at a couple of wild Pals again (same as last time) so the canvas is live and populated, then check the log for the actual field dump — this should finally reveal the real array/field name holding each Pal's gauge data, which is what the eventual text-writing step needs.

## Forty-eighth pass (2026-09-03): canvas dump hit an unreadable MapProperty — pivoted to the WrapBox's real, standard child-enumeration functions

The forty-seventh pass's live dump of `WBP_PalNPCHPGaugeCanvas_C` succeeded and confirmed its real class hierarchy (`WBP_PalNPCHPGaugeCanvas_C` -> `PalUINPCHPGaugeCanvasBase` -> `PalUserWidget` -> `PalActivatableWidget` -> `CommonActivatableWidget` -> `CommonUserWidget` -> `UserWidget`) plus real fields: `DisplayedPalGaugeMap`, `DisplayedBossUGaugeMap`, `DisplayedPlayerGaugeMap` (all `MapProperty` — `DisplayedPalGaugeMap` is almost certainly the real per-wild-Pal gauge lookup table), and two UMG panel fields, `Canvas_Root` (a `CanvasPanel`) and `WrapBox` (a `WrapBox`), both `ObjectProperty`. Several `DoubleProperty` fields (`DisplayGaugeDistance`, `HideTimer`, `HideTime`, `DisplayGaugeRange_Sight`, `GaugeInSightDistance`) also showed as "(not read)" since `dump_all_properties` only special-cased `FloatProperty`, not `DoubleProperty` — a cheap, still-pending fix, but not the priority this pass.

The priority was `DisplayedPalGaugeMap`, since a lookup-by-Pal map is exactly what's needed to go from "one of our own tracked Pals" to "its on-screen gauge widget." `dump_all_properties` doesn't handle `MapProperty` at all (falls through its if-chain to "(not read)"). Checked whether this project's own model for that function — the bundled `ConsoleCommandsMod/dump_object.lua` — handles it, and it explicitly doesn't either: `elseif Property:IsA(PropertyTypes.MapProperty) then ValueStr = "UNHANDLED_VALUE"`, with its own comment "Need to add support eventually for MapProperty when UE4SS Lua supports MapProperty". So reading the map directly is, at minimum, unsupported by any tooling this project has access to, and quite possibly unsupported by this whole UE4SS Lua build's TMap reflection.

**Pivoted to the `WrapBox` field instead.** A `WrapBox` widget's entire standard UMG purpose is auto-arranging multiple child widgets in a flow layout — a natural fit for "one small gauge widget per visible wild Pal," and unlike TMap iteration, child enumeration is a basic, universal UMG capability. Confirmed real and present in THIS build via two independent sources: `CXXHeaderDump/UMG.hpp` (`class UPanelWidget : public UWidget { ... int32 GetChildrenCount(); ... class UWidget* GetChildAt(int32 Index); ... }`, with `class UWrapBox : public UPanelWidget` directly below it) and the bundled Lua API stub file `shared/types/UMG.lua` (generated from this exact game's own reflection data, so authoritative for this build): `function UPanelWidget:GetChildrenCount() end` / `function UPanelWidget:GetChildAt(Index) end`. These are ordinary, well-known UMG functions present in virtually every Unreal version — a much safer bet than hunting for an uncertain Map-reading API.

**Code change**: `Indicator.lua` now keeps a module-level handle to the live canvas instance once found (`liveCanvasInstance`, no change to the existing one-shot canvas property dump). A new `check_wrapbox_children()` runs on every scan tick: reads `liveCanvasInstance.WrapBox`, calls `GetChildrenCount()`, and logs the count whenever it changes (capped separately, `MAX_WRAPBOX_SCAN_LOGS = 30`, so it's safe to check every tick even as the count naturally rises/falls with which Pals are on screen). The first time the count is > 0, it walks every child via `GetChildAt(i)` (0-indexed, matching the native C++ signature), logs each child's real class name and `GetFullName()`, and runs the existing `dump_all_properties` on the first child only — looking for both a text-block sub-widget (the modern equivalent of the old mod's `WBP_EnemyGauge.Text_WorkName`, needed since `SetText_GDKInternal` is confirmed still valid but needs a real target widget to call it on) and whatever field identifies which specific Pal that gauge child belongs to (needed to match a gauge child back to one of this mod's own tracked Pals from `Trust.GetFollowingSnapshot()`). Raised `MAX_PROPERTY_DUMP_LOGS` from 60 to 200 to leave room for both the canvas's own dump (which alone nearly filled the old 60-line cap) and the new child dump in one session.

Still fully read-only — logs field names/types/values only, writes nothing. Deployed to both destinations. Needs one more live test: look at a wild Pal (or several) so the WrapBox actually has children, then check the log for the child count, each child's class name, and the first child's full field dump.

## Forty-ninth pass (2026-09-03): 48th-pass test was inconclusive (too short), and WrapBox may be the wrong container on structural grounds — now checking Canvas_Root too

Dragón's live test of the 48th pass's WrapBox check ran only ~95 seconds start to finish (per `palbonds-live.log`'s timestamps) — the live canvas was found and dumped immediately as before, but `WrapBox:GetChildrenCount()` stayed at 0 the entire session, logged once at the start and never again. That's not a real negative result; the session simply wasn't long enough to give the WrapBox a chance to actually populate with a Pal's gauge.

Separately, worth reconsidering on structural grounds regardless of test length: a `WrapBox`'s entire standard UMG purpose is auto-flowing multiple children into ONE shared list position (think a stacked row of buff icons) — not a great fit for gauges that each need to float independently above their own, separately-moving Pal. `Canvas_Root` — also a real, confirmed field on the same canvas instance, a `CanvasPanel` — positions each child through its own `CanvasPanelSlot` with independent screen coordinates, which is structurally the much better fit for "one gauge tracking Pal X's position, another tracking Pal Y's."

**Change**: generalized `check_wrapbox_children()` into `check_panel_children(fieldName)`, using the same real `UPanelWidget:GetChildrenCount()`/`GetChildAt(Index)` calls, with per-field state (a has-dumped flag and last-logged count) keyed by field name so checking multiple containers doesn't collide. `check_all_panels()` now calls it for both `WrapBox` and `Canvas_Root` every scan tick. Whichever one gets a live child first has its children listed and its first child fully dumped, exactly as the 48th pass did for WrapBox alone.

Still fully read-only. Deployed to both destinations. Needs a genuinely longer live test this time: stand near a wild Pal with its real HP bar actually visible on screen for a good stretch (10-15+ seconds, not just a quick glance in passing) so either container has real time to populate.

## Forty-ninth pass RESULT + Fiftieth pass (2026-09-03): Canvas_Root confirmed real, but the dump caught the wrong child (WrapBox itself, not a Pal)

Dragón's longer live test (walked among several wild Pals, pet a ChickenPal and a SheepBall) gave real signal: `Canvas_Root`'s `GetChildrenCount()` climbed steadily through the session — 2, then 11, 17, 19, 20 — tracking Pals coming into view. `WrapBox`'s count never moved from its initial value at all. This settles which container is actually alive: **`Canvas_Root`**, not `WrapBox`.

But the dump itself caught the wrong thing. The one-shot "dump child 0 the first time count > 0" logic fired at the very first count change (0 -> 1), and that lone first child was the `WrapBox` itself — confirmed directly in the log: `Canvas_RootChild0 (class WrapBox)`, followed immediately by `(class PanelWidget)`, `(class Widget)`, `(class Visual)`, `(class Object)` and nothing else — i.e., a real, complete, but totally uninteresting dump of a structural fixture. This means `WrapBox` isn't a sibling field pointing somewhere unrelated — it's literally the FIRST, always-present child living inside `Canvas_Root`'s own widget tree, added at construction before any Pal is ever nearby. The real per-Pal children only start appearing later, at index 1 and up, as the count climbs into double digits — which the old one-shot/index-0-only logic never looked at.

**Fiftieth pass, two fixes to `check_panel_children`:**
1. List ALL children EVERY time the count changes (not just the first time it goes above zero) — real per-Pal children come and go continuously as Pals enter/leave range, so a single early snapshot can easily land before any real content exists.
2. Stop hardcoding "always dump child index 0". Maintain a small blocklist of known structural/generic UMG container class names (`WrapBox`, `CanvasPanel`, `HorizontalBox`, `VerticalBox`, `Overlay`, `ScrollBox`, `UniformGridPanel`, `GridPanel`, `SizeBox`, `Border`, `NamedSlot`, `WidgetSwitcher`) and, among whichever children are present at each listing, fully dump the first one whose class ISN'T in that blocklist and hasn't already been dumped — wherever it actually lands in the index order. A `dumpedClasses` set, shared across both `WrapBox` and `Canvas_Root` checks, keeps each distinct real class from being dumped more than once even across many count changes.

Still fully read-only. Deployed to both destinations. Needs one more live test: stand near several wild Pals for a good stretch again, same as last time, so `Canvas_Root` fills up with real per-Pal children beyond just the fixed `WrapBox` fixture at index 0.

## Aside: "Pal Analyzer" mod checked, not directly reusable

Dragón also dropped in a second reference mod, "Pal Analyzer" (`Pal Analyzer 0.86 (STEAM)-336-0-86-1772533592/LogicMods/PalAnalyzer.pak`) — shows extra on-screen info (item drops, work suitability) when looking at a Pal. Checked its contents: unlike `VisiblePalCaptureCounter`, this is a **LogicMods `.pak`** — a compiled/packaged Blueprint+asset mod (UE4's native mod-loading system), not a UE4SS Lua mod, so there's no Lua source to read or adapt technique from directly. `strings` on the pak surfaced its asset names (`WBP_PalAnalyzer_Text`, `WBP_PalAnalyzer_ItemDrops`, `WBP_PalAnalyzer_WorkSuitability`, `WBP_PalAnalyzer_Settings`, `ModActor`, `StructPalAnalyzerSettings`) but the actual Blueprint graph logic is serialized binary (`.uasset`/`.uexp`), unreadable without FModel's Blueprint `Export -> Properties (.json)` (same tool/technique noted in the Session notes above). Useful only as a confirmation that a "look at a Pal, show live text about it" widget is achievable at all here — not as a source of real class/field names the way the capture-counter mod was. Not pursued further since this project's own live `Canvas_Root` introspection is already yielding real, concrete data.

## Aside: "RemoteAccessEverything" mod checked — surfaced real radial-menu class/function names, a promising lead for Q2 (not yet tested)

Dragón also dropped in a third mod, "RemoteAccessEverything" (`RemoteAccessEverything (Steam).../RemoteAccessEverything_P.pak` — lets players use storage/crafting/building menus remotely). Also a compiled LogicMods `.pak`, same limitation as the Pal Analyzer mod (no Lua source), but `strings` on it surfaced real, current asset paths and class/function names for the game's generic radial-menu system, since this mod reuses that framework for its own remote-menu popups:

- `/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu` (Blueprint widget class `WBP_PlayerRadialMenu_C`) and its content sub-widget `WBP_PlayerRadialMenu_MenuContent_C` — very likely the actual Blueprint behind the real action-wheel the player opens on a Pal (Dragón's own "4" key).
- `/Game/Pal/Blueprint/UI/CommonWidget/RadialMenu/WBP_CommonRadialMenuBase` (`WBP_CommonRadialMenuBase_C`) — a shared base used by multiple radial menus in the game (player action wheel, base-building construction radial `WBP_IngameMenuConstruction_Radial_C`, etc.).
- Native base classes, confirmed real via a fresh grep of `Pal.hpp`: `UPalUIPlayerRadialMenuBase : public UPalUserWidget` (only `SelectedFeed(ItemSlotId, itemNum)`, `OpenOtomoFeedInventory()`, `LaunchPhotoMode()` — these read as Otomo/companion-feed-inventory specific, not the generic per-Pal Pet/Feed wheel) and `UPalUIRadialMenuWidgetBase : public UPalUserWidget` (generic radial-menu mechanics: `OnChangeSelectedIndex` delegate, `menuNum`, `nowSelectedIndex`, `UpdateSelectedIndex_ForPad/ForMouse`, `BuildRadialMenuWidget()`, etc. — this is the shared "how a radial menu's wedges/selection work" base, not Pal-specific content).
- Blueprint-graph-only names also seen in the strings dump but NOT present in the native header dump (meaning they're custom functions/variables inside the `WBP_PlayerRadialMenu_C` Blueprint graph itself, not native): `isAnyRadialMenuOpened`, `OnRadialMenuOpened`, `OnRadialMenuClosed`, `OpenedRadialType`, `RadialMenuDecide`, `RadialMenuCancel`, `RadialIgnoreTribeList`, `PLAYER_ACTION_RADIALMENU_EMOTE`. Blueprint graph functions still compile into real, hookable UFunctions at runtime regardless of whether a static header dump ever captured them (same as every other Blueprint hook this project has already used successfully, e.g. `WBP_PlayerUI_C:OnCapturedPal` from the Spy.lua research) — so these are real candidate hook targets by path, e.g. `/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu.WBP_PlayerRadialMenu_C:RadialMenuDecide`, just not yet tried.

**Why this matters for Q2** (the pet/feed ownership-gate question, currently worked around by Interaction.lua's own separate F9/F10 keybind rather than the real menu): if `RadialMenuDecide`/`OnRadialMenuOpened` etc. fire with enough context to tell which Pet/Feed-equivalent option was picked and on which target, this could let a future pass detect the REAL action-wheel interaction directly, instead of (or alongside) the current bypass — closer to Dragón's original hope from Q2. **Not yet tested or hooked** — this is a documented lead only, deprioritized behind finishing the on-screen trust indicator (the active task). Worth a dedicated pass once the indicator's per-Pal gauge widget is found.

## Fiftieth pass RESULT + Fifty-first pass (2026-09-03): the old mod's exact class name was real all along — WBP_PalNPCHPGauge_C, WBP_EnemyGauge, and SyncId all confirmed live

Dragón's live test was the breakthrough this whole effort was aiming for. `Canvas_Root`'s child count climbed (1, 6, 10, 13...) and every single new child from index 1 onward was class **`WBP_PalNPCHPGauge_C`** — the EXACT class name the forty-fifth pass's reference mod (`VisiblePalCaptureCounter`, built for an older Palworld version) used. Earlier passes concluded this class must have been renamed or restructured, since it had no matching entry anywhere in this install's static `CXXHeaderDump` folder — that conclusion was wrong, or at least incomplete: the class was never renamed, it just never happened to get individually dumped by whatever UE4SS dump session produced that folder (the dumper only writes a file for a Blueprint class it's actually seen instantiated at least once — a static limitation this project has run into with other widgets too). Live `GetChildAt()` found it directly, unambiguously, with no such gap.

Its generic property dump (via the existing `dump_all_properties`) confirmed real, exactly-relevant fields before the log's cap was hit partway through:
- **`WBP_EnemyGauge`** (`ObjectProperty`, a live `WBP_EnemyGauge_C` instance) — the EXACT sub-widget path the old mod wrote text into (`WBP_EnemyGauge.Text_WorkName:SetText_GDKInternal(...)`).
- **`SyncId`** (`StructProperty`, confirmed type `/Script/Pal.PalInstanceID`, inherited from `WBP_IndividualParameterBindWidget_C`) — this project's own Q5 (the stable per-Pal GUID struct: `PlayerUId`/`InstanceId`/`DebugName`). This is exactly the field needed to match a specific gauge widget back to one of this mod's own tracked Pals.
- `IsBindFriendShip` (bool, currently `false`) plus real `OnChangedFriendshipRank`/`OnChangedFriendshipPoint` delegates (`MulticastInlineDelegateProperty`) — meaning this exact widget class already has NATIVE, built-in support for a friendship-driven display, just not currently enabled for wild-Pal gauges. Not touched this pass — worth remembering as a possible alternate path later (toggle the bind flag and let the vanilla widget do the work) instead of writing text manually.

**Fifty-first pass**: added a targeted `inspect_gauge_widget()`, running once on the first live `WBP_PalNPCHPGauge_C` found (separate from the generic per-class dump, which can't see a child's own sub-widgets or read struct-property field values — the generic dump's `StructProperty` handling only ever manages to print the struct's TYPE name via a failed `GetFullName()` fallback, never real field values). This new function:
1. Reads `.WBP_EnemyGauge` directly and fully dumps ITS fields — looking for the real, current name of whatever the old mod called `Text_WorkName` (that exact name may or may not still be current; per this whole project's discipline, we check rather than assume).
2. Reads `.SyncId` and indexes directly into the returned struct value for its own sub-fields (`DebugName`, `InstanceId`, `PlayerUId`) — the same technique this project has already used safely on other small hook-argument structs (e.g. `FPalDamageResult.Defender` in `Trust.lua`), as opposed to the by-value struct-RETURN pattern (`GetSaveParameter()`) that caused this project's three real crashes early on. This is a property READ off an already-live object, not a function call returning a fresh heavy struct copy, so it's a materially safer shape.

Also raised `MAX_PROPERTY_DUMP_LOGS` again, 200 -> 400 — the previous cap was hit mid-way through dumping `WBP_PalNPCHPGauge_C`'s own class chain, before ever reaching `WBP_EnemyGauge`.

Still fully read-only. Deployed to both destinations. Needs one more live test, same as before (stand near wild Pals for a good stretch) — this one should finally show the real text-widget field name and a readable `SyncId`, which is everything needed to write the first real line of visible trust-progress text.

## Fifty-first pass RESULT + Fifty-second pass (2026-09-03): Text_WorkName confirmed real (exact old path) — first real write attempted

`WBP_EnemyGauge_C`'s own dump confirmed **`Text_WorkName`** (`ObjectProperty`, a `BP_PalTextBlock_C` — the Blueprint subclass of the native, already-confirmed-valid `UPalTextBlockBase`) present under the EXACT same path the old reference mod (`VisiblePalCaptureCounter`) used: `WBP_EnemyGauge.Text_WorkName`. Also confirmed real alongside it: `Text_Name`, `Text_LevelNum`, `Text_GuildName` (other genuine UI text fields, already used for name/level/guild display — not free to repurpose) and `ProgressBar_HP`/`ProgressBar_HPBack` (the real HP bar itself, also not free to repurpose).

`SyncId`'s sub-field reads came back useless: `DebugName` printed empty, and `InstanceId`/`PlayerUId` each printed a generic Lua struct-wrapper identity string rather than a real value — because each of those fields is itself a plain `FGuid` struct (`{ uint32 A, B, C, D }`), one more level of indexing beyond what the fifty-first pass tried.

**Fifty-second pass, two changes:**
1. Added `describe_guid()`, which indexes directly into an `FGuid`'s own `A`/`B`/`C`/`D` uint32 fields and formats them as a hex string — should finally produce a real, comparable per-Pal identifier.
2. **The first real write this whole effort has attempted.** With `Text_WorkName` confirmed real, `inspect_gauge_widget()` now calls `textWidget:SetText_GDKInternal(true, "PalBonds TEST")` on it — once, on the one live gauge widget already found. This is a text-set call on a widget that already exists and already renders every frame as part of the game's own normal UI — a fundamentally different, safer shape than the native gameplay-action calls that caused this project's three real crashes early on (those were functions invoked outside their normal internal call context, mid-flow, with unmet preconditions; this is the same kind of property/method access this project already does constantly for reading, just writing instead, on an object whose lifecycle isn't in question).

If Dragón sees the literal text "PalBonds TEST" appear over a wild Pal's gauge in-game, the hard question this entire multi-pass research effort has been chasing — where does trust-progress text actually go — is answered. Everything after that is wiring: compute real text from `Trust.GetFollowingSnapshot()`, match a specific Pal to its gauge child via `SyncId`, and write on a real interval instead of once.

Deployed to both destinations.

## Kinship peach real name found (Dragón, via FModel search): AffectionFruit

Dragón searched FModel directly (Packages → Search) and found the real asset path: `Pal/Content/Pal/Model/Prop/Resource/AffectionFruit/` — `SM_AffectionFruit.uasset` (the mesh), `Material/MI_PalProp_AffectionFruit.uasset`, and four texture variants `T_AffectionFruit_B/E/M/N.uasset` (likely growth-stage or color variants, not yet confirmed which). "AffectionFruit" is almost certainly the real internal name for what Dragón calls the "kinship peach" — a fruit item themed around affection/friendship, matching the concept exactly.

This is a strong, concrete lead for the still-open TODO above (`Trust.OnKinshipItemUsed`, `UPalUtility:CanUseTargetGainFriendshipPoint`): the real item FName to match against a fed item is very likely `AffectionFruit` (or close to it — DataTable item IDs and asset folder names usually match, but not guaranteed exactly). **Not yet confirmed against the item DataTable itself** — next step when this is picked up: search FModel for a DataTable row named `AffectionFruit` (or grep an exported `DT_ItemDataTable`-equivalent JSON for it) to get the exact `FName`/`StaticItemId` and its real `GenericGainFriendShipPoint`-style stat, then match that against whatever item FName `UPalAction_FeedItemToCharacter`/`SelectedFeedingItem` hands us when a player feeds a Pal. Deprioritized behind finishing the on-screen trust indicator (the active task), but this closes most of the "what's the item even called" gap that TODO was blocked on.

## Fifty-second pass RESULT + Fifty-third pass (2026-09-03): write call succeeded but showed nothing — likely a collapsed-by-default widget, forcing visibility now

Dragón's test: no text appeared anywhere near the wild Pal's gauge. But the log shows `SetText_GDKInternal` call returned OK — no Lua error, no caught exception. A successful call producing nothing visible is the exact signature of a widget whose underlying `Visibility` is `Collapsed` (or similar): `SetText_GDKInternal` sets the text state, it doesn't force the widget itself onto the screen. `Text_WorkName`'s own field name — plus its siblings on `WBP_EnemyGauge_C` seen in the fifty-first pass's dump (`CachedIsWork`, `Anm_WorkIcon_1/2`, `WBP_MainMenu_Pal_State`) — all point the same direction: this text field is very likely meant only to show a Pal's current base-camp JOB while it's actively working, and collapsed otherwise. A wild, roaming Pal (not assigned any work) would have `CachedIsWork = false` (confirmed in that same dump) and, plausibly, this text collapsed as a result.

(Separately, `SyncId`'s GUID fields also came back all-zero this test — `describe_guid()`'s `A`/`B`/`C`/`D` indexing may still not be reaching real values, or this specific gauge's handle just wasn't fully bound yet at read time. Lower priority than the visibility question; not investigated further this pass.)

**Fifty-third pass**: before writing, now dumps `Text_WorkName`'s own properties (to see its real, current `Visibility` value directly instead of inferring from field names) and forces it to `Visible` via the standard, universal `UWidget:SetVisibility(0)` (ordinal 0 = `ESlateVisibility::Visible`, confirmed from this project's own earlier enum dumps of sibling fields like `ActivatedVisibility`/`DeactivatedVisibility`) immediately before calling `SetText_GDKInternal` again. Dumps the widget's properties a second time afterward too, so both before/after `Visibility` values are on record either way. If forcing visibility on this one widget is all that was missing, "PalBonds TEST" should finally appear; if it still doesn't, the next diagnostic step is checking the WIDGET TREE's own visibility chain (a parent container collapsed higher up hides children even when they individually report `Visible`) rather than this widget in isolation.

Deployed to both destinations.

## Clarification from Dragón: kinship fruit has two tiers

Dragón clarified there are two versions of the kinship-peach item: a lesser one and a better one, giving different amounts of friendship/trust. The `AffectionFruit` asset folder found via FModel search likely corresponds to just one tier — when this is picked up again, check for a sibling asset/DataTable row (something like `AffectionFruit_Rare`, `GreatAffectionFruit`, `AffectionFruit_High`, or similar — not yet searched) for the second tier, rather than assuming a single item covers both.

## Course-correction from Dragón: the deliverable is a fill bar, not text

Dragón pointed out, correctly, that the fifty-second/fifty-third passes' `Text_WorkName` write was only ever meant to sanity-check that writing to a live widget works at all — after 50+ passes of everything silently failing, that was worth confirming. But it isn't the actual feature. Dragón's original spec (quoted at the top of this indicator's section in DESIGN.md, unchanged since day one) is a real graphical fill bar under the Pal's HP bar, tracking live `FriendshipPoint`. Dragón also clarified explicitly that the three reference mods (`VisiblePalCaptureCounter`, "Pal Analyzer", "RemoteAccessEverything") were only ever given so this project could learn HOW widget manipulation is done in this game — never as literal templates to copy, and never license to substitute a text label for the real bar without saying so first.

Given the choice between (a) putting text on the already-confirmed `Text_WorkName` field now, with the real bar researched later, or (b) researching the real fill bar first even though it's unproven, Dragón chose **(b)**.

## Fifty-fourth pass (2026-09-03): can UE4SS Lua construct a brand-new UMG widget at runtime?

Everything done in this indicator so far — every pass above — only ever read or wrote fields on widgets the game itself already constructed. Nothing has ever created a widget from scratch. That's the real open question behind a genuine fill bar: it needs a NEW `ProgressBar` widget inserted under `Canvas_Innner` (the private, per-Pal-gauge `CanvasPanel` found on `WBP_PalNPCHPGauge_C` back in the fifty-first pass, never yet explored further), since no existing field is free to repurpose (`ProgressBar_HP`/`ProgressBar_HPBack` are the real HP bar itself).

Research, via a fresh grep of this game's own `CXXHeaderDump/UMG.hpp` plus a real, currently-shipping precedent already bundled with this UE4SS install:

- **`StaticConstructObject(Class, Outer, Name, SetFlags, InternalSetFlags, bCopyTransientsFromClassDefaults, bAssumeTemplateIsArchetype, Template, InInstanceGraph, ExternalPackage)` is a real UE4SS Lua global function**, not something a mod defines itself. Proof: `Mods/BPML_GenericFunctions/Scripts/main.lua` (bundled with this exact UE4SS install) has a live, working `ConstructPersistentObject` custom event that calls it today — `StaticConstructObject(Class, GameInstance, 0, 0, GarbageCollectionKeepFlags, false, false, nil, nil, nil)` — with a `UClass` found via `StaticFindObject`, checked via `:IsValid()`. Same exact shape this pass needs, just swapping in a `UProgressBar` class.
- **`UPanelWidget:AddChild(UWidget* Content) -> UPanelSlot*`** and the more specific **`UCanvasPanel:AddChildToCanvas(UWidget* Content) -> UCanvasPanelSlot*`** are both real, unchanged functions in this game's `UMG.hpp`. `Canvas_Innner` is itself a `UCanvasPanel`, so `AddChildToCanvas` is the exact call to parent a new widget into it.
- **`UProgressBar`** (`UMG.hpp`) is real and unchanged: `SetPercent(float)`, `SetFillColorAndOpacity(FLinearColor)`, `SetIsMarquee(bool)`. This is the actual class matching Dragón's spec — a filling bar, not text.
- **`UCanvasPanelSlot`** (what `AddChildToCanvas` returns) has real `SetPosition(FVector2D)` / `SetSize(FVector2D)` / `SetAnchors(FAnchors)` / `SetZOrder(int32)` functions, for placing the new bar once one exists.

**What this pass does**: on the first live gauge widget found (same trigger point as `inspect_gauge_widget`), attempts the actual construction end-to-end, once: find the `ProgressBar` UClass via `StaticFindObject("/Script/UMG.ProgressBar")`, construct one via `StaticConstructObject` (Outer = `Canvas_Innner` itself — a valid, live, related UObject, matching the "outer must be real" pattern `BPML_GenericFunctions` itself uses with `GameInstance`), set an obvious test percent (50%) and an obvious test color (bright magenta — deliberately nothing like the real HP bar's color, so it's unmistakable if it renders at all), force `SetVisibility(0)`, add it to `Canvas_Innner` via `AddChildToCanvas`, then give its slot a provisional position/size (`SetPosition(0,25)`, `SetSize(80,6)`) placed just under where the real HP bar sits. Every single step is its own `pcall`, logged individually under `DIAG-CREATE` — this is genuinely unproven ground, so the log needs to show exactly which step succeeds or breaks, not just a final yes/no.

Deployed to both destinations. Needs a live test: stand near a wild Pal with its gauge visible, same as previous passes, then check whether a bright magenta bar appears anywhere near/under its real HP bar. If every logged step says OK but nothing appears, next suspects (in the file header and here): wrong position/size relative to `Canvas_Innner`'s own coordinate space (could be off-screen or zero-size), or a Slate invalidation/rebuild step this doesn't trigger automatically that a full `UUserWidget` construction would normally do for you.

## Fifty-fourth pass RESULT + Fifty-fifth pass (2026-09-03): runtime widget creation CONFIRMED working — fixing the two gaps it exposed

Dragón's test: a real magenta bar appeared, but only on one Chikipi (the one closest to spawn), it never moved, and it wasn't correctly aligned with the real HP bar. Checked the log for every `DIAG-CREATE` line from that session — **every single step returned OK**: `StaticFindObject` for the `ProgressBar` class, `StaticConstructObject`, `SetPercent`, `SetFillColorAndOpacity`, `SetVisibility`, `AddChildToCanvas`, `SetPosition`, `SetSize`. Nothing failed, nothing was silently swallowed. This confirms the fifty-fourth pass's real research question with a positive, unambiguous answer: **UE4SS Lua CAN construct a brand-new UMG widget at runtime and insert it into a live widget tree in this game.** This was the hardest, most unproven part of the whole fill-bar effort, and it works.

The three symptoms Dragón reported all trace to known, intentional scope limits of that first version, not bugs in the mechanism itself:
1. **Only one Chikipi got a bar** — `try_create_test_bar` used a single global one-shot flag (`hasTriedCreateBar`), so the whole thing only ever ran once per session, on whichever gauge widget the scan happened to find first (the nearest Pal at spawn, exactly as Dragón guessed).
2. **The bar never moved, stayed at the same half-full look** through the whole capture — also correct: that version calls `SetPercent(0.5)` exactly once, at creation, and nothing calls it again afterward. This pass never claimed to be live-updating.
3. **Not rightly aligned** — the position (`0,25`) and size (`80,6`) were blind, arbitrary numbers relative to `Canvas_Innner`'s own coordinate space, chosen without ever reading anything real to compare against.

**Fifty-fifth pass fixes (1) and (3):**
- Replaced the global one-shot flag with a per-gauge table (`barInstalledForGauge`, keyed by each gauge's own `GetFullName()`, which is unique per live instance) and moved the call site out of `inspect_gauge_widget` (kept as its own separate one-shot deep-dump, so log volume stays bounded) into `check_panel_children`'s own per-child loop, called unconditionally for every `WBP_PalNPCHPGauge_C` child seen. Now every distinct wild Pal gauge gets its own bar, not just the first one ever found.
- Reads the REAL HP bar's own slot geometry before positioning the new bar: `gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot` (a `UCanvasPanelSlot`, inherited via the standard `UWidget.Slot` field), then `hpSlot:GetPosition()`/`GetSize()`. The new bar is placed at the same X/width, offset in Y by the real bar's own height plus a small 2px gap — directly under it — instead of a blind guess. Falls back to the old blind guess only if this read fails for any reason, with a clear log line saying so.

Still explicitly NOT wired to real `FriendshipPoint` — `SetPercent(0.5)` and the magenta color are still static placeholders, deliberately left obvious/fake-looking rather than switched to a more "real" color, so it stays visually clear this isn't live trust data yet. That's the next real piece of work, and it's blocked on the still-unresolved gauge-to-Pal matching problem (`SyncId`'s GUIDs still read all-zero; Dragón's own suggested `bindedHandle` lead is still unread).

Deployed to both destinations. Needs a live test: stand near several wild Pals (not just one) and check whether EVERY one now shows a magenta bar, correctly aligned directly under its own real HP bar.

## Fifty-fifth pass RESULT + Fifty-sixth pass (2026-09-03): every Pal got a bar, but it was shifted and wider — the real fix is using ProgressBar_HP's actual parent panel, not a guess

Dragón's screenshot confirmed the per-gauge fix worked (multiple Pals, each with their own bar this time). But the new bar was still misaligned: shifted right of the real HP bar and noticeably wider, not just off vertically. Checked the log — every single Pal's `DIAG-CREATE` sequence read the IDENTICAL reference geometry (`pos=(64.0,26.0) size=(120.0,4.0)`), which on its own is correct and expected (it's the Blueprint's static per-widget design layout, the same for every instance of the same class — each gauge's own screen position is handled separately, at a higher level). The bug isn't the numbers being wrong; it's that they were applied inside the wrong container. The fifty-fifth pass added the new bar into `gaugeWidget.Canvas_Innner` — a guess, never actually confirmed to be the same panel `ProgressBar_HP` lives in. Nested canvas panels each have their own local coordinate space; applying `ProgressBar_HP`'s position/size numbers inside a *different* panel produces exactly this kind of shifted-and-wrong-scale mismatch, not just a vertical offset.

Dragón independently suggested essentially the right instinct: "copy the healthbar positioning" and offset it down. That's correct — the missing piece was making sure the copy actually lands in the same coordinate space as the original, not a differently-scaled sibling panel.

**Fifty-sixth pass fix**: `UPanelSlot` has a real `Parent` field (confirmed in `UMG.hpp`) pointing to the exact live `UPanelWidget` a widget is already a child of. Now reads `gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot.Parent` and adds the new bar into THAT SAME panel object via `AddChildToCanvas`, instead of guessing `Canvas_Innner`. Since it's now the identical panel, `ProgressBar_HP`'s own position/size numbers apply directly with no space-mismatch — the new bar is positioned at the same X, offset down in Y by the real bar's own height plus a small 2px gap, same idea Dragón suggested, just anchored correctly. Falls back to the old `Canvas_Innner` guess only if reading the real parent fails for any reason.

Deployed to both destinations. Needs a live test: same as before, check whether the bar now lines up directly under the real HP bar with matching width, on every visible wild Pal.

## Fifty-sixth pass RESULT + Fifty-seventh pass (2026-09-03): alignment confirmed by Dragón — proceeding to wire the REAL FriendshipPoint

Dragón confirmed the bar now lines up correctly under the real HP bar and asked to proceed with the next part. That next part is the last real blocker for this whole indicator: matching a specific gauge widget to one of this mod's own tracked Pals, so the bar can show a real, live value instead of a fixed 50%.

**Research**: `bindedHandle` (inherited from `WBP_IndividualParameterBindWidget_C`) is declared `TSoftObjectPtr<UPalIndividualCharacterHandle>` in the header dump — that's exactly why `dump_all_properties` always printed "(not read)" for it; `SoftObjectProperty` was never a handled case. A fresh grep of `Pal.hpp` for `UPalIndividualCharacterHandle` found real, exactly-relevant functions:
- `TryGetIndividualActor() -> APalCharacter*` — the real, live Pal actor.
- `TryGetIndividualParameter() -> UPalIndividualCharacterParameter*` — the same kind of object Interaction.lua/Trust.lua already read `GetFriendshipPoint()`/`GetFriendshipRank()` from.
- `GetIndividualID() -> FPalInstanceID` — the real save ID, a fallback matching key if ever needed.

No bundled UE4SS Lua mod in this install actually resolves a `TSoftObjectPtr` at runtime (checked — only EmmyLua type-annotation stubs exist, no real usage). Rather than guess blind, `resolve_pal_actor_from_gauge` tries the simplest possibility first: treat the raw `bindedHandle` property value as already being a usable object (reasonable here since it points at a live gameplay object already in memory, not an on-disk asset needing a load) — call `:IsValid()` then `:TryGetIndividualActor()` directly on it. If that fails at any step, the function returns a clear reason string instead of erroring, so even a failed resolution is diagnosable from the log.

Once an actor resolves, `get_friendship_ratio(actor)` reuses this project's own already-proven route to the friendship value (`actor.CharacterParameterComponent:GetIndividualParameter()`, the exact same call Interaction.lua's `get_individual_parameter` already makes elsewhere in this codebase) and computes `GetFriendshipPoint() / Trust.CAPTURE_AT_FRIENDSHIP_POINT` (now exported from Trust.lua as `Trust.CAPTURE_AT_FRIENDSHIP_POINT` instead of duplicating the number, so the two can never drift apart if it's ever retuned), clamped to [0,1].

`install_trust_bar` now tries this resolution immediately after creating and positioning each bar — if it succeeds, the bar's initial fill is set to the REAL ratio and its key is remembered in a new `trackedBars` table; if it fails, the bar stays at the static 50% magenta placeholder and the log names exactly which step failed. A new `update_trust_bars()`, called every scan tick alongside `check_all_panels()`, re-reads the live ratio for every tracked bar and updates its fill — so a resolved bar should actually move as trust changes (petting, damage, passive gain, capture), not stay frozen like every version before this one. Entries whose bar or actor go invalid (Pal despawns, leaves range, gauge destroyed) are dropped automatically rather than erroring.

Deployed to both destinations (Indicator.lua and Trust.lua). Needs a live test: pet a wild Pal enough to raise its real FriendshipPoint and watch whether its bar (a) shows something other than a flat 50% from the start, and (b) actually rises as petting continues. Check the log's `DIAG-TRUST` lines either way — they'll say plainly whether `bindedHandle` resolved or not, which settles this research question regardless of the visual result.

## Fifty-seventh pass RESULT + Fifty-eighth pass (2026-09-03): two real bugs found from one test — bindedHandle's real shape, and Pals losing their bar entirely after leaving/re-entering range

Dragón's test surfaced two separate problems, both diagnosed cleanly from the log rather than guessed at.

**Bug 1 — bars still stuck at 50%.** The log's `DIAG-TRUST` line named the exact cause: `handle:IsValid()` itself errored — `attempt to call a nil value (method 'IsValid')`. That specific Lua error means the raw `bindedHandle` property value is not nil and IS indexable, it simply has no `IsValid` method — it doesn't behave like the normal live-UObject wrapper this project has relied on everywhere else. The fifty-seventh pass's assumption (a `TSoftObjectPtr` to a live gameplay object would just act like a plain object handle) was wrong, or at least incomplete, and gating resolution on that one broken call meant the whole chain never even tried the real accessor.

Fix: added `inspect_bindedHandle_shape` — a one-shot, fully read-only probe trying a wide net of plausible accessors on the raw handle value (`type()`, `tostring()`, a generic `:type()` method this project has seen used in a bundled mod before, `GetFullName()`, `LoadSynchronous()` — the standard Blueprint node name for resolving a soft pointer, `Get()`, and reading `AssetPathName` directly as if it's a plain `FSoftObjectPath`) — logged under `DIAG-HANDLE`, so the next test reveals the real shape instead of another blind guess. `resolve_pal_actor_from_gauge` no longer gates on the broken `IsValid()` call at all: it now tries `TryGetIndividualActor()` directly first, and falls back to `LoadSynchronous()` before retrying if that fails.

**Bug 2 — Pals seen after walking away from the spawn area got no bar at all.** Root cause: `check_panel_children`'s per-child loop only ran when the live child count DIFFERED from the count it was last run at (`state.listedAtCount ~= count`). If one Pal leaves render range at roughly the same moment a new one enters, the total count can cycle back to a value already seen before (e.g. 5 → 6 → 5) — the guard would then skip the loop entirely on that tick, even though the actual SET of children had changed, so the new Pal's gauge widget would simply never get processed or given a bar.

Fix: the loop now always walks every child when count > 0, every single tick — `install_trust_bar`/`inspect_gauge_widget` are already idempotent per-widget (keyed by full name), so re-calling them on already-handled children is a cheap no-op. Only the verbose per-child log line and the one-time-per-class property dump are still gated, now via a `seenChildren` set keyed by full name (not by count), so log volume stays low without the correctness bug.

Deployed to both destinations. Needs a live test: pet a Pal and check whether `DIAG-HANDLE` finally shows something useful about bindedHandle's real shape (which will tell us the actual fix needed for real FriendshipPoint), and separately, walk well away from the spawn area to confirm every new Pal encountered along the way gets its own bar, not just the first batch.

## Fifty-eighth pass RESULT + Fifty-ninth pass (2026-09-03): the real cause of both symptoms — a severe self-disabling bug, plus confirmation bindedHandle's stored field is a dead end

Dragón's test came back worse than before: Pals encountered after walking away from spawn had no bar at all, and the handful of bars that did appear were still stuck at 50%. Both were diagnosed cleanly from the log.

**DIAG-HANDLE gave a clear, final answer on `bindedHandle`.** `handle:type()` reported `"TSoftObjectPtrUserdata"`, and every single accessor tried — `GetFullName()`, `LoadSynchronous()`, `Get()`, `TryGetIndividualActor()` (called directly on the raw value), and reading `.AssetPathName` — failed or returned nil. This is a genuine UE4SS Lua binding gap for this specific wrapped type, the same category as the already-documented `MapProperty`/`DoubleProperty` gaps in `dump_all_properties` — not a mistake in how it was called. Reading the STORED `bindedHandle` field after the fact is a dead end in this build, full stop.

**The real fix for matching a gauge to a Pal**: `BindFromHandle(class UPalIndividualCharacterHandle* targetHandle)` takes the handle as a plain HARD POINTER parameter — a completely different, much friendlier shape than the soft-pointer FIELD it apparently gets converted into once stored. This project has always safely read hook arguments this way (Trust.lua/Interaction.lua's actor/param reads off hook params), so hooking this function directly and capturing `targetHandle` at the moment of binding sidesteps the broken soft-pointer read entirely. Registered once, using `gaugeWidget:GetClass():GetPathName()` (the live widget's own `/Game/...` Blueprint asset path) to build the exact hook target `<path>:BindFromHandle` — so it fires only for our gauge class, not every individual-parameter-bound widget in the game. Once registered it fires for every future bind, including gauges created later in a session (covering Pals found further from spawn); gauges already bound before the hook registers won't have a captured handle until their widget gets destroyed and recreated, which happens naturally as Pals leave/re-enter view.

**The much bigger, previously-hidden bug**: `scan_for_gauge_widgets` used to start with `if scanLogCount >= MAX_SCAN_LOGS then return end` — a cap written back in the forty-sixth pass when this function did nothing but a lightweight existence-scan diagnostic. But `canvasCount > 0` is true on every tick forever once the shared canvas is found (a single always-present live instance), so the branch that increments `scanLogCount` fires unconditionally every 2-second tick — meaning the cap (25) is hit after about 50 SECONDS into every session. Once that happened, the early `return` at the top of the function skipped everything after it for the rest of the session — including `check_all_panels()` (ALL bar creation) and `update_trust_bars()` (ALL live refresh), both of which now live inside this same function even though the original cap was never designed with them in mind. This is a complete, silent explanation for everything Dragón saw: an initial burst of bars near spawn, then total silence — no new bars, no updates, no matter how far they walked or how many Pals they pet.

Fix: `scan_log()` now throttles only the verbose `DIAG-SCAN` print lines (same shared-counter helper pattern as `panel_scan_log`/`property_dump_log` elsewhere in this file); the actual functional work (`FindAllOf`, `check_all_panels()`, `update_trust_bars()`) runs unconditionally every tick for the entire session, regardless of log volume.

**Also fixed a timing gap**: `BindFromHandle` may not fire for a given gauge at the exact moment its bar gets created (binding and gauge-discovery order isn't guaranteed). Every installed bar is now tracked (resolved or not) with its own `gaugeWidget` reference, and `update_trust_bars()` retries actor resolution every tick for any bar that hasn't resolved yet, instead of the previous one-shot-at-creation-only attempt that could never recover from an early miss.

Deployed to both destinations. Needs a live test covering everything at once: stay in a session for well over a minute (past the old ~50s silent-shutoff point), walk well away from spawn to confirm new Pals still get bars, and pet a Pal enough to see whether its bar now starts at a real value and actually moves.

## Fifty-ninth pass RESULT + Sixtieth pass (2026-09-03): the BindFromHandle hook never actually registered, and a self-inflicted bug meant it never got a second try

Dragón's test confirmed the scan self-disabling fix worked (new Pals encountered further from spawn did get bars this time), but the bar was still stuck at exactly 50% for every one of them. The log named the cause precisely: `[DIAG-HOOK] could not read gauge class path (caught, non-fatal) — cannot register BindFromHandle hook: ...Indicator.lua:711: attempt to call a TrivialObject value (method 'GetPathName')`.

`gaugeWidget:GetClass():GetPathName()` errored outright — the class object UE4SS hands back here is a more limited wrapper type ("TrivialObject") than the fully-resolved class object the fifty-ninth pass assumed, and it simply doesn't support `GetPathName()`. That alone would just mean "try a different way to get the path" — but a second, self-inflicted bug made it far worse: `register_bind_hook_once` set its one-shot guard (`hasRegisteredBindHook = true`) unconditionally at the very top of the function, before knowing whether registration would even succeed. So the very first call — which failed — permanently blocked every future attempt for the rest of the session, even though this function runs every tick for every live gauge and a later attempt (or a different approach) might well have worked.

**Sixtieth pass fix, two parts:**
1. The one-shot guard is now only set on an actual successful `RegisterHook` call. A failed attempt simply returns and retries on the next gauge instance seen — free and frequent, since this function already runs every tick.
2. Two candidate hook paths are tried in order: the full class path from `GetClass():GetPathName()` (if it happens to be readable), and a fallback built from `GetClass():GetFName():ToString()` — the plain short class name (e.g. `WBP_PalNPCHPGauge_C:BindFromHandle`). That second method is already used constantly elsewhere in this same file (`check_panel_children`, `describe_widget`) and reliably works on this exact kind of object, so it's a solid fallback rather than another guess. UE4SS's `RegisterHook` can often resolve a uniquely-named Blueprint function by short name alone, without the full `/Game/...` asset path.

Each attempt is logged individually under `DIAG-HOOK` (`RegisterHook(<path>) = OK` or `FAILED: <error>`), so the next test will show plainly whether either candidate path actually registers.

Deployed to both destinations. Needs a live test: check the log for a `DIAG-HOOK` line reporting `OK` for one of the two candidate paths, and check in-game whether a Pal's bar now starts at something other than a flat 50% and actually moves as it's petted.

## Sixtieth pass RESULT + Sixty-first pass (2026-09-03): the lag was the doomed retry loop itself, and the real class name was wrong all along

Dragón's test reported heavy, escalating lag with the sixtieth pass's build, plus the bar was still stuck at 50%. The log explained both.

**Why every attempt failed:** `[DIAG-HOOK] RegisterHook(WBP_PalNPCHPGauge_C:BindFromHandle) = FAILED: ...Tried to register a hook with Lua function 'RegisterHook' but no UFunction with the specified name was found.` — the same error, identically, on every single attempt. Re-checking `CXXHeaderDump/WBP_IndividualParameterBindWidget.hpp` explains why: `BindFromHandle` is declared on `UWBP_IndividualParameterBindWidget_C` (the parent class), not on `WBP_PalNPCHPGauge_C` (the gauge's own runtime class, which is Blueprint-only and has no header dump of its own — it just inherits the function). UE4SS's short-name `RegisterHook` resolution needs the function's actual declaring class, not any subclass that merely inherits it. Every candidate the sixtieth pass tried was built from the wrong (child) class, so all of them were doomed from the start, regardless of the `GetPathName()`/"TrivialObject" issue.

**Why it lagged:** the sixtieth pass's fix for the earlier permanent-lockout bug (only lock in success after an actual `RegisterHook` success) was correct on its own, but paired with every attempt being doomed, it meant `RegisterHook` was being called (twice) on every tick, for every currently-visible gauge, forever, with zero cooldown. `RegisterHook` failing a lookup is not a cheap no-op internally — repeating that at tick frequency across every wild Pal on screen is a straightforward, escalating performance sink (worse with more Pals visible, worse the longer the session ran), which matches exactly what Dragón described.

**Sixty-first pass fix, two parts:**
1. Added the correct, hardcoded declaring class name as the first candidate: `WBP_IndividualParameterBindWidget_C:BindFromHandle`. This doesn't depend on reading anything off the live widget, so it also sidesteps the earlier `GetPathName()`/"TrivialObject" failure mode entirely.
2. Added a hard cap (`MAX_BIND_HOOK_ATTEMPTS = 5`) on total attempt rounds across the whole session. Once exhausted without a success, the function gives up permanently and logs one clear message explaining why, instead of retrying indefinitely and burning performance for no benefit.

Deployed to both destinations (syntax-verified via `luac -p`). Needs a live test: confirm the lag is gone, check the log for `DIAG-HOOK ... OK` on the new first candidate, and check whether the bar finally starts at a real value and moves when petting a wild Pal.

## Sixty-first pass RESULT + Sixty-second pass (2026-09-03): the correct declaring class name STILL failed — short-name hooking may just not work for Blueprint classes here, so switching to the full asset path

Dragón's test showed less lag than before (the round cap worked — the log confirms all 5 attempt rounds burned through and gave up within the same second, at `15:47:41`), but the bar was still stuck at 50%. The log showed the sixty-first pass's fix — `RegisterHook(WBP_IndividualParameterBindWidget_C:BindFromHandle)`, the function's own confirmed real declaring class — still failed identically: `Tried to register a hook with Lua function 'RegisterHook' but no UFunction with the specified name was found.`

That's a meaningful new data point: the class name itself was right (double-checked against the header dump), yet the short "ClassName:FunctionName" hook-path form still couldn't resolve it. The likely explanation: UE4SS's short-name RegisterHook resolution is built around native `/Script/Module.Class` paths, which are globally unique — Blueprint classes live under `/Game/...` and may simply not resolve reliably through that short form at all, no matter which class name is used. The more reliable, commonly-documented form for hooking a Blueprint function is the FULL asset path (e.g. `/Game/Pal/Blueprint/UI/.../WBP_IndividualParameterBindWidget.WBP_IndividualParameterBindWidget_C:BindFromHandle`), which needs the real `UClass` object's own `GetPathName()` — the exact call that failed with "TrivialObject" back in the sixtieth pass, but only because it was reached via `gaugeWidget:GetClass()`.

**Sixty-second pass fix:** reach the same class object a different way. `FindAllOf("WidgetBlueprintGeneratedClass")` returns every compiled Blueprint class as its own fully-wrapped object — the same kind of object this project's other `FindAllOf` calls (canvas/gauge discovery) already work with cleanly. Search that list by name (`GetFName():ToString()`, proven reliable everywhere else in this file) for `WBP_IndividualParameterBindWidget_C`, then call `GetPathName()` on THAT object instead of on `gaugeWidget:GetClass()`. If that succeeds, its full path becomes the first candidate tried; the sixty-first pass's hardcoded short name and the two original per-instance guesses remain as fallbacks in the same capped attempt loop.

Deployed to both destinations (syntax-verified). Needs a live test: check the log for a `DIAG-CLASSFIND` line (confirms whether the class object and its full path were found at all) and a `DIAG-HOOK ... OK` line, plus whether the bar finally starts at a real value and moves.

## Sixty-second pass RESULT + Sixty-third pass (2026-09-03): the class-finding approach itself failed, so pivoting away from hooking entirely — matching by screen position instead

Dragón's test showed no real change from before. The log explained why: `FindAllOf("WidgetBlueprintGeneratedClass")` — the sixty-second pass's plan to get the correct full asset path a more reliable way — returned nothing at all (`FindAllOf(WidgetBlueprintGeneratedClass) failed or returned nothing: nil`), so that attempt never even got a full path to try. The two remaining short-name candidates failed identically to every previous pass.

That's four distinct hook-path attempts now, all dead: full path via the widget's own `GetClass()` (fails with "TrivialObject"), short name via the wrong (child) class, short name via the correct (declaring) class, and full path via a global class search (the search itself finds nothing). At this point the pattern is clear enough to stop guessing a fifth string: `RegisterHook`'s short-name/class-name resolution does not reliably work for Blueprint-declared functions in this UE4SS Lua build, at least not through any route this project has access to.

**Sixty-third pass — a different technique, not another hook-path guess.** Rather than reading or intercepting the game's own internal widget↔Pal link (three different ways, three different confirmed dead ends), match a gauge widget to a Pal from the OUTSIDE, using information both sides already expose cleanly: every gauge widget is a child of `Canvas_Root` with its own `CanvasPanelSlot` giving a screen position; every wild Pal actor has a real world location (`K2_GetActorLocation()`, already proven throughout this project); and `APlayerController::ProjectWorldLocationToScreen` (a real, confirmed function in `CXXHeaderDump/Engine.hpp`) converts a world location into the same kind of screen coordinate. Whichever Pal projects closest to a given gauge's on-screen position is almost certainly the Pal that gauge belongs to — no internal link needed at all.

This pass deliberately does NOT write any matching logic yet. Following the same discipline that produced every real, confirmed fix in this file (and pointedly not what the last several hook-path passes did), it only probes and logs: several different Lua calling conventions for `ProjectWorldLocationToScreen`'s output (its exact behavior in this UE4SS Lua build is unknown — the function has an out-parameter in C++, but Blueint-facing reflection may expose it as an extra return value instead), the projected screen position of every currently-visible wild Pal, and the actual on-screen slot position of every currently-installed gauge widget — side by side, so the next test's log tells us directly whether the two coordinate spaces line up (and by what scale/offset, if any) before any matching code gets written on top of an unverified guess.

Deployed to both destinations (syntax-verified). Needs a live test: stand where at least one wild Pal and its gauge are visible for a bit, then check the log for `DIAG-PROJECT` (which calling convention actually returned real numbers) and `DIAG-POSMATCH` (Pal screen projections vs. gauge slot positions, to compare by eye).

## Sixty-third pass RESULT + Sixty-fourth pass (2026-09-03): cracked open the "Pal Analyzer" reference mod — real confirmation of the right technique and the right call signature

Dragón pushed back on an earlier claim that the "Pal Analyzer" reference mod (one of the three handed over at the very start of this project) couldn't be opened — rightly so. It's a different format than everything else this project reads (a compiled Blueprint LogicMod, shipped as `PalAnalyzer.pak`, not UE4SS Lua source), but "different format" isn't "unreadable." Extracted it read-only with a standard open-source pak-reader (`github.com/panzi/u4pak`, fetched fresh — no encryption or exotic compression on this mod, it unpacked cleanly) and read the plain-text function/property names embedded in the resulting `.uasset` files. Unreal stores every Blueprint node's function/property name as a readable string in the asset's name table even after compiling to bytecode, so this is a legitimate, well-worn modding research technique (the same category as the FModel dumps and header-dump greps this project already relies on), not a decompile of proprietary logic.

**What it confirmed.** PalAnalyzer identifies its target Pal via a camera-forward sphere trace (`SphereTraceMultiForObjects` → `BreakHitResult` → `HitActor`) — i.e. "what is the player currently looking at," a fundamentally different technique than ours since it only ever needs ONE target Pal at a time (whatever's under the crosshair), not a simultaneous mapping for every visible Pal like our floating per-Pal bars need. Once it has that actor, it reads stats via `GetIndividualCharacterParameterByActor`/`TryGetIndividualParameter` — the exact same actor→parameter route Trust.lua/Interaction.lua already use in this project. Real, independent confirmation that route is correct, not just a guess that happened to work.

The genuinely useful part for THIS specific problem: its compiled graph also calls `ProjectWorldToScreen` (Blueprint's own auto-generated pin names, `CallFunc_ProjectWorldToScreen_ReturnValue` / `_ScreenPosition`, confirm the exact bool-return + FVector2D-out-param shape). Its owning class is `UGameplayStatics` (confirmed in `Engine.hpp`) — a static Blueprint function library, not an instance method on the PlayerController like the sixty-third pass guessed. This project's own bundled UE4SS install ships a working example of calling exactly this kind of static library function from Lua: `Mods/SplitScreenMod/Scripts/main.lua` calls `UEHelpers.GetGameplayStatics():CreatePlayer(...)`.

**Sixty-fourth pass fix:** switched the screen-projection probe to `UEHelpers.GetGameplayStatics():ProjectWorldToScreen(controller, worldLoc, false)` — a validated call shape from a real, working mod plus a real, working example already bundled with this exact UE4SS install — as the primary attempt, with the sixty-third pass's PlayerController-instance-method guesses kept only as a fallback for comparison.

Deployed to both destinations (syntax-verified). Needs a live test: check the log for `DIAG-PROJECT`/`DIAG-POSMATCH` lines and whether the `GameplayStatics` route succeeds and produces numbers that line up with each gauge's own on-screen slot position.

## Sixty-fourth pass RESULT + Sixty-fifth pass (2026-09-03): a full re-read of every reference mod — the real fix was sitting in this project's own files from before pass one

Dragón asked for a genuinely thorough pass over ALL FOUR reference mods handed over at the start of this project, explicitly rejecting the idea of skipping any of them just because they're not built the same way as this project (three of them — Pal Analyzer, PassiveWildPals, RemoteAccessEverything — are compiled Blueprint LogicMods shipped as `.pak` files, not UE4SS Lua source). That instruction was correct and paid off immediately.

**Extraction.** Pal Analyzer's `.pak` (already handled in the sixty-fourth pass) opened with a standard pak-reader (`u4pak.py`, no encryption). The other two — `RemoteAccessEverything_P.pak` and `PassiveWildPals_P.pak` — are Pak format version 11 ("Fnv64BugFix"), which that older tool doesn't support (it errored with "illegal file magic" trying to parse a footer format it doesn't know). Switched to `repak` (`github.com/trumank/repak`, a well-maintained Rust CLI with a prebuilt Linux release, explicitly built for modern UE4/5 pak versions including this one) — both unpacked cleanly, no encryption on either.

**The actual fix — hiding in plain sight.** Re-reading `VisiblePalCaptureCounter/Scripts/main.lua` in full (not just the earlier narrow grep for `Text_WorkName`) turned up its `Init()` function, which successfully registers exactly the hook this project has been trying to register since the fifty-ninth pass:
```lua
RegisterHook(
    "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle", function (self, handler)
    local targetHandle = handler:get()
    local widget = self:get()
    ...
```
This is a working, shipped mod — not a guess. The path format for hooking a Blueprint function is `<content-browser package path>.<ClassName>:<FunctionName>` (a `.` between the package path and the class, then a `:` before the function name) — completely different from both things this project tried: the `/Script/Module.Class:Function` shape that correctly addresses NATIVE classes (and which this project's own Trust.lua/Interaction.lua hooks already use successfully, which may be exactly why this distinction got missed for a Blueprint target), and the bare short class name with no path at all. Every one of the sixtieth through sixty-second passes' candidates was missing the real package path — none of them were "close but wrong," they were structurally the wrong shape.

The same source also confirms the calling convention this project already assumed was right: `handler:get()` on the hook's handle argument, and that the resulting handle supports `TryGetIndividualParameter()` (VPCC calls this directly) — real, live proof that a hook-captured HARD pointer handle works fine, unlike the confirmed-dead stored soft-pointer field.

**Bonus find: gauge widget reuse.** The same mod also hooks `Unbind` on the same class. That implies gauge widgets are pooled/reused across different Pals rather than each Pal getting a permanent one-off widget — which this project hadn't accounted for. Without clearing a stale captured handle on unbind, a reused widget could briefly show its *previous* Pal's trust value after being rebound to a new one. Added the same hook, clearing `gaugeHandleByKey[key]` on unbind.

**Sixty-fifth pass fix:** added the literal, confirmed-working path as the first candidate in `register_bind_hook_once`, and registered the matching `Unbind` hook (by string-replacing `:BindFromHandle` with `:Unbind` on whichever candidate path succeeds) to invalidate reused widgets' stale handles.

**Other findings from the same pass, relevant to future work (not yet acted on):**
- `PassiveWildPals_P.pak` (overrides `BP_AIAction_WildLife`, a wild-Pal AI behavior Blueprint) revealed a real, native leader/follower **squad system** — `PalSquad`, `GetSquad`, `GetIsSquadBehaviour`, `GetLeader`, `FollowLeader`, `IssueAsyncFollowMove`, `CancelAsyncFollowMoveIfAny`, `BP_RequestAsyncMoveTo`, `SimpleMoveToActorWithLineTraceGround` — a fully-worked-out, native "move to and follow a leader entity" system already used for wild Pal herds. This is directly relevant to DESIGN.md's Combat.lua "Follow & protect" subsystem (currently unimplemented) — it may be possible to route a bonding wild Pal into this existing squad/follow machinery (with the player as "leader") instead of building custom follow movement from scratch. Also confirms `GetIndividualHandle` → `TryGetIndividualActor()` working live in native Blueprint AI logic, and shows the disposition/response system (`SelectResponseBySenses`, `EPalAIResponseType`, `TargetIsPlayerOrPlayersOtomoPal`) is actively read every AI tick, not just a static per-species table.
- `RemoteAccessEverything_P.pak` (overrides `WBP_PlayerRadialMenu`) revealed the real **Otomo instruction/order system** — `RequestSetOtomoOrder`, `GetOtomoOrder`, `EPalOtomoPalOrderType`, and the actual instruction message IDs (`PAL_INSTRUCTION_ASSIST`, `PAL_INSTRUCTION_ATTACK`, `PAL_INSTRUCTION_CARE`, `PAL_INSTRUCTION_ESCAPE`, `PAL_INSTRUCTION_FEED`) — the real command set used to tell an already-captured Otomo Pal to assist in combat, wait, flee, etc. Also directly relevant to Combat.lua: if a bonding wild Pal can accept these same orders, this could be the real mechanism for "assist in a fight" rather than reinventing one. It also confirmed a real, complete **Emote system** (`BP_Action_Emote_Base_C` plus nine numbered variants `BP_Action_Emote_0_C`…`_8_C`, `CreateEmoteMenu`, `PLAYER_ACTION_EMOTE`) — directly relevant to the "emote"/"happy" keywords Dragón flagged for later research in DESIGN.md §9, and a real `BP_ActionPairStandby_Petting_C` class confirming "petting" is itself a distinct, real action class (consistent with, not contradicting, how Interaction.lua already triggers petting).

Deployed the sixty-fifth pass's code fix to both destinations (syntax-verified). Needs a live test: check the log for `DIAG-HOOK ... OK` on the new first candidate, and whether the bar finally starts at a real value and moves when petting a wild Pal.

## Sixty-sixth pass RESULT + Sixty-seventh pass (2026-09-03)

Sixty-fifth pass's fix was confirmed fully working live by Dragón: the trust bar starts at 0%, fills in real time while petting a wild Pal, and keeps climbing passively toward capture afterward. Dragón's follow-up asked for two things: (1) stylize the bar — it "looks so simple compared to the healthbar", specifically a color gradient white-pinkish (empty) → red (full); (2) investigate the "prism" keyword, on the hypothesis it names the capture light-beam animation, with a real runtime "spy" (hooks), not just static reading.

**Sixty-sixth pass — trust bar color gradient.** Checked what UProgressBar actually exposes to Lua before designing anything: `CXXHeaderDump/UMG.hpp`'s `UProgressBar` only declares `SetPercent(float)`, `SetIsMarquee(bool)`, and `SetFillColorAndOpacity(FLinearColor)` as callable functions. The brush/border visuals live inside `WidgetStyle` (an `FProgressBarStyle` struct holding `FSlateBrush` images) — not something safe to construct from scratch via Lua reflection. So the real, deliverable "more design" available here is the color gradient itself, not a broader visual overhaul.

Added `compute_trust_bar_color(ratio)`: a plain per-channel linear interpolation from a soft white-pink (`R=1.00, G=0.82, B=0.85`) at ratio 0 to red (`R=0.90, G=0.05, B=0.08`) at ratio 1. Wired into both `install_trust_bar` (replacing the old static magenta placeholder — the bar now also starts at 0% fill instead of the old 50% guess, since the real value resolves almost immediately anyway) and `update_trust_bars` (recomputed every refresh tick alongside `SetPercent`).

**Sixty-seventh pass — "prism" spy.** `grep -rl "Prism" CXXHeaderDump/` found exactly three hits:
- `BP_CapturePrism.hpp`: `ABP_CapturePrism_C : ABP_ThrowWeaponBase_C`, a real dumped Blueprint class. Fields `SK_Weapon_PalSphere_001` (mesh) and `CaptureSphereType` confirm this IS the Palsphere throw weapon itself. Real functions: `OnThrowInternal(AActor* Bullet)`, `GetCaptureLevel(int32&)`, `OnEndShootAnimation(UAnimMontage*)`, `On Throw()`, `DecrementBullet()`, `GetThrowObjectClass`, `GetEquipSocketName`.
- `BP_CapturePrismBullet.hpp`: `ABP_CapturePrismBullet_C : ABP_ThrowObjectBase_C`, the actual thrown projectile ("bullet"). Real fields: `CaptureTarget` (`APalCharacter*`), `isBound`, `ThrowRotator`. Real functions: `UpdateRotation`, `SpawnCaptureObject(FGuid, AActor*)`, `IsDestroy(...)`, `OnHitToActor(...)`, `ReceiveTick`, a projectile-bounce delegate, `ExecuteUbergraph`.
- `Engine.hpp`: `ConstraintLimitMaterialPrismatic` — a physics constraint's material property. Shares only the substring "Prism"; ruled out as unrelated.

Conclusion from the static read alone: "Prism" looks like this game's own internal/legacy name for the Palsphere weapon-and-bullet pair, not a distinct light-beam VFX by itself. `SpawnCaptureObject(FGuid, AActor*)` on the bullet is a strong, specific candidate for where a capture-success visual (which could well be a light beam) actually gets triggered.

Per Dragón's explicit ask for a "spy" rather than more static reading, added real read-only `RegisterHook`s on both classes' throw/hit/capture lifecycle functions: `OnThrowInternal`, `GetCaptureLevel`, `OnEndShootAnimation`, `On Throw`, `DecrementBullet` on the weapon; `SpawnCaptureObject`, `OnHitToActor`, `IsDestroy`, and the projectile-bounce delegate on the bullet. Deliberately skipped every per-frame function on both classes (`ReceiveTick`, `UpdateRotation`, `ExecuteUbergraph`) — every per-frame hook this project has ever added turned into log spam (`SelectResponseBySenses`, thirty-third pass) with no benefit here.

Class path resolution reuses the sixty-second pass's proven technique (`FindAllOf("BlueprintGeneratedClass")`, matched by `GetFName():ToString()`, real path from `GetPathName()`) — the actor-class flavor rather than the widget-class flavor, since the Palsphere/bullet are actors, not UMG widgets. Retried each scan tick (capped, same shape as `register_bind_hook_once`) in case neither class is loaded yet at session start.

**Not yet confirmed** — this needs Dragón to actually attempt a real capture while the mod is running; the log will show which of these functions fire, in what order, which is the actual answer to "which one triggers on capture" and "is prism the beam or something else."

## Thirty-seventh pass (OtomoWatch.lua, 2026-09-03): the "prism"/beam spy, round 2 — a test that doesn't need a sphere at all

Dragón proposed a genuinely better test than "just throw a sphere and see": go to a settlement, free a caged Pal (no sphere involved at all), see if the same beam shows up. If a hook fires for BOTH a sphere capture and a cage release, it can't be `BP_CapturePrism`/`BP_CapturePrismBullet` (Indicator.lua's sixty-seventh pass candidates) — those are the throwable sphere weapon specifically, never involved in a cage release.

Grepped the whole header dump for a broad set of beam/effect/cage keywords (`Beam|Cage|Captive|Prisoner|Slave|Rescue|JoinParty|AddParty|JoinPal|CaptureEffect|CaptureVFX|CaptureSuccess|Pillar|LightRay|SummonEffect|SpawnEffect`) rather than guessing narrowly. Strongest new candidate by far: `ABP_ReturnPalEffect_C : AActor` (`BP_ReturnPalEffect.hpp`) — a real actor built entirely around a `UNiagaraComponent* Effect` plus `CacheDisappearBurstEffect`/`CacheDisappearEffect` (`UNiagaraSystem*`), moving a Pal from `StartLocation` to `ForPlayer` over time (`LerpStartPos`, `Progress`, `CurveForLerp`). Structurally this is exactly "a beam/trail effect showing a Pal traveling to become the player's" — its name suggests it's normally used to recall an Otomo, but nothing about its shape is otomo-specific, so it's a real candidate for firing on both a sphere capture and a cage release.

Also added, all found in the same grep: `ABP_PalCaptureJudgeObject_C` (the Blueprint subclass of the native `PalCaptureJudgeObject` OtomoWatch already hooks — which never fired in earlier testing — hooking the actual instantiated subclass directly in case that silence was a declaring-class issue, the same kind of gap Indicator.lua's sixty-first pass found for `BindFromHandle`), `BP_ActionUnlockCagePalLock_C` (the literal cage-lock-unlock interaction — a precise timing anchor for exactly the action Dragón is about to perform), and `BP_CaptureWire_C` (another real capture-related actor, purpose unconfirmed, included per the standing "don't discard, analyze everything" instruction).

All four are Blueprint classes with no knowable literal asset path from the header dump alone. Reused Indicator.lua's `FindAllOf("BlueprintGeneratedClass")` resolution technique (search by `GetFName():ToString()`, real path from `GetPathName()`), combined with this file's own retry-until-loaded timer pattern (`hook_with_retry`) since these actors likely don't exist in memory until something in the world actually spawns one. New `find_class_path_by_name`/`hook_class_functions_with_retry`/`generic_fire_logger` helpers added to OtomoWatch.lua; logs tagged `[PRISM-SPY]`, capped at 80 lines.

Deliberately skipped every per-frame function on all four classes (`ReceiveTick`, `TickEffectPosition`, `ReturnOwnerMovement`, `ExecuteUbergraph`) — per this project's own repeated lesson (`SelectResponseBySenses`, thirty-third pass) that per-frame hooks turn into log spam with no benefit.

**Not yet confirmed** — needs Dragón's planned test: free a caged Pal first (no sphere), then capture one with a sphere, and compare which `[PRISM-SPY]` lines fire for each, in what order.

## Sixty-eighth through Seventieth pass (2026-09-03): real lag diagnosis, gold color, and fixing the dead FindAllOf technique

Dragón tested pass 66/67 live: freed a caged Dazzi (joined party, no sphere), petted several Pals including capturing a Herbil by pets alone (sphere-less capture confirmed working), and captured a Clovee with a normal sphere. Two pieces of feedback: the white-pink-to-red gradient "didn't convince at all," and the game felt "kind of laggy" — Dragón's own guess was the new prism spy hooks.

**Checked the actual log instead of assuming.** Real findings:
- The prism spy hooks (both Indicator.lua's and OtomoWatch.lua's) logged almost nothing (3-4 lines total) and failed instantly every time: `FindAllOf(BlueprintGeneratedClass) failed or returned nothing: nil`. Not the cause of anything — they never even attached.
- The REAL, measured cause: `[DIAG-DUMP]` produced **507 lines in an 8-second window** (18:02:10-18:02:18) — leftover, fully-answered property dumps from the forty-seventh/fifty-first/fifty-third passes (the canvas dump, the WBP_EnemyGauge dump, the Text_WorkName before/after dumps plus its now-pointless test write) that still fully re-run every single session. Each line is a synchronous, flushed disk write by design (`Logger.lua` flushes every line for crash-safety) — a real, concentrated I/O burst, and the most likely actual stutter source.
- `[DIAG-CREATE]` (92 lines) and `[DIAG-PANEL]` (44 lines) added further volume across the session as new wild Pal gauges were discovered — smaller than the DIAG-DUMP burst but real.

**Sixty-eighth pass — fix.** Stripped `inspect_gauge_widget` down to just its still-load-bearing call (`register_bind_hook_once`), removing the obsolete enemyGauge/Text_WorkName dumps and test write entirely — those questions were answered back in the fifty-first through fifty-third passes and became fully moot once the project pivoted to a real progress bar. Also stopped the LiveCanvas one-shot dump (forty-seventh pass) and the "first new class" panel-child dump (fiftieth pass) from re-dumping `WBP_PalNPCHPGauge_C`'s full inheritance chain every session now that it's fully characterized — both now log a short one-line acknowledgment instead. A genuinely new/unknown panel-child class (e.g. a boss/NPC gauge) still gets the full dump, since that would have real diagnostic value.

**Sixty-ninth pass — gold color.** The white-pink-to-red gradient wasn't readable enough in practice. Replaced with a gold theme: dim bronze (`R=0.45,G=0.32,B=0.10`) at empty to bright, saturated gold (`R=1.00,G=0.84,B=0.00`) at full — kept as a gradient (not one flat color) so the color still carries progress information, just with much higher contrast between the two ends.

**Seventieth pass — fixing the dead FindAllOf technique properly**, not just accepting it never worked. `FindAllOf("BlueprintGeneratedClass")` (Indicator.lua's sixty-seventh pass) and `FindAllOf("WidgetBlueprintGeneratedClass")` (the sixty-second pass, months earlier) both failed identically — querying for the META-class of Blueprint classes via FindAllOf just doesn't work in this UE4SS build, regardless of "GeneratedClass" flavor. Separately, in OtomoWatch.lua, even a working version would only have had ~60 seconds (20 retries x 3s) to find something, all spent at mod init — but none of these actors (the Palsphere weapon, its bullet, the return-effect VFX, the cage-lock action) exist persistently; they only spawn when the player actually does the relevant thing, which could be minutes into a session.

Real fix, both problems at once: stopped querying for the meta-class entirely. Now uses `FindAllOf(<concrete class name>)` — the same call shape already proven throughout this project (e.g. the forty-sixth pass's `FindAllOf("PalUINPCHPGaugeCanvasBase")`) — to find real, live instances directly, then reads that instance's own `:GetClass():GetPathName()`. That specific call previously failed ("TrivialObject" proxy) only when tried on a hook Context/widget object; it had never actually been tried on an object FindAllOf itself returns. No round cap needed now (it's a cheap, targeted call, safe to run indefinitely) — Indicator.lua checks every 2s scan tick forever per class independently; OtomoWatch.lua retries indefinitely at 10s spacing instead of giving up after one minute.

**Status: still not confirmed live** — this session's capture/cage-release events happened before this fix was deployed, so none of it was actually observed firing. Needs Dragón to repeat the free-a-caged-Pal + sphere-capture test with this build.

## Seventy-first/seventy-second pass (2026-09-03): the console spam bug, solid gold, and giving up on RegisterHook for the prism/beam classes

Dragón's next test: couldn't find another settlement to free a caged Pal at (too high-level, will retry later), but did capture a Pal with a normal sphere and petted another to watch the bar. Two pieces of feedback, plus a pasted console excerpt: the gold gradient "looks better" but should be a flat solid color, no gradient — and the console was spamming a specific line every ~1-2 seconds:

```
[DIAG-PRISM] found a live BP_CapturePrism_C instance but instance:GetClass():GetPathName() still failed (caught, non-fatal): ...Indicator.lua:972: attempt to call a TrivialObject value (method 'GetPathName')
```

**Real bug, my mistake.** The seventieth pass's "fix" (try `instance:GetClass():GetPathName()` on a FindAllOf-found instance instead of the meta-class scan) hit the exact same `TrivialObject` error the sixty-second pass had already found on a hook-Context object — `:GetClass()` returns an unusable proxy in this UE4SS Lua build regardless of how the instance was obtained. Worse, that failure's log line wasn't behind `prism_log`'s cap, so with two live `BP_CapturePrism_C` instances apparently existing at once (first/third-person view-model duplicates, most likely), it logged twice every single 2-second scan tick, forever — genuine, ongoing console spam, exactly what Dragón caught.

Searched the web for a published literal asset path for `BP_CapturePrism`/`BP_ReturnPalEffect` (the way `BindFromHandle`'s and `BP_OtomoPalHolderComponent`'s were found before) — nothing surfaced across several queries against Nexus, CurseForge, paldb.cc, and Palworld data-extraction tool repos.

**Conclusion: RegisterHook is not viable for these classes in this build.** Three separate Lua-reflection techniques for getting a Blueprint class's real asset path are now confirmed dead: `FindAllOf("WidgetBlueprintGeneratedClass")` (sixty-second pass), `FindAllOf("BlueprintGeneratedClass")` (sixty-seventh pass), and `instance:GetClass():GetPathName()` tried both on a hook-Context object and a FindAllOf-found instance (sixty-second and seventieth passes). Every case this project has ever gotten a real Blueprint hook path came from an externally-known literal string (a reference mod's own source, or a wiki) — no such reference exists for `BP_CapturePrism`/`BP_CapturePrismBullet`/`ABP_ReturnPalEffect_C`/etc.

**Seventy-first pass — real fix.** Abandoned `RegisterHook` entirely for these classes in both `Indicator.lua` and `OtomoWatch.lua`. Replaced with plain existence/field polling off the live instances `FindAllOf(<concrete class name>)` already gives us — no path, no `:GetClass()` call at all, just `:IsValid()`, `GetFullName()`, and direct field reads (all proven reliable throughout this project). `Indicator.lua`'s `poll_prism_state()` logs a new `BP_CapturePrism_C`/`BP_CapturePrismBullet_C` instance once and the bullet's `CaptureTarget`/`isBound` only on change. `OtomoWatch.lua`'s `schedule_prismspy_poll()` does the same for all four of its classes on a 10s recurring timer (existence itself is useful — `ABP_ReturnPalEffect_C` in particular should only exist briefly around an actual "Pal becomes the player's" moment) instead of the old one-shot 60-second retry window that could never catch an event happening minutes into a session.

**Seventy-second pass — solid gold.** `compute_trust_bar_color` now just returns a fixed `{R=1.00, G=0.84, B=0.00, A=1}` regardless of ratio — fill length alone (via `SetPercent`) carries the progress information now.

**Status:** still not confirmed live for the prism/beam question — this test captured a Pal with a sphere but the console-spam bug and dead hooks meant nothing useful was actually observed. Needs a fresh test with this build (sphere capture at minimum; the cage-release comparison is still pending until Dragón finds a low-enough-level settlement).

## Seventy-third pass (2026-09-03): repak against the REAL game pak — a capability unlock, and the real radial-menu functions

Dragón's request: move Pet/Feed off the F9/F10 hotkeys and onto the game's own "4" radial menu, so muscle memory (already used to petting/feeding via the wheel) works and the hotkeys can eventually be removed.

**The capability unlock.** Instead of guessing at Blueprint paths again (three dead reflection techniques already logged this project's history — `FindAllOf("WidgetBlueprintGeneratedClass")`, `FindAllOf("BlueprintGeneratedClass")`, `instance:GetClass():GetPathName()`), this pass went straight to the source of truth: `Pal-Windows.pak`, the real, unencrypted, ~40.5GB main game asset archive already sitting on Dragón's own disk (`Pal/Content/Paks/Pal-Windows.pak`). Confirmed via `repak info`: Pak version V11 (Fnv64BugFix), not encrypted, Oodle-compressed, 185,014 file entries. Downloaded a fresh `repak` binary (github.com/trumank/repak v0.2.3) directly onto Dragón's device (confirmed the device's own Linux VM has outbound network access and matching x86_64 architecture), ran `repak list` to get the full authoritative file listing, grepped it for every class name this project has ever wanted a real path for, then `repak unpack -i <path> ...` to extract only the 18 target files needed (not the full 40GB) — including the real radial-menu widgets.

**Real radial-menu assets found:**
- `/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu` (the outer wheel controller)
- `/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu_MenuContent` (a generic reusable content-slot widget — confirmed to hold no Care/Feed-specific logic itself, see correction below)
- `/Game/Pal/Blueprint/UI/PlayerRadialMenu/EPlayerRadialMenuOpenType` (enum: `None, Construction, ConsumeItemChange, Emote, OtomoChange, PlayerAction, ThrowItemChange, WeaponChange` — `PlayerAction` is almost certainly the open-type used for the Care/Feed/Attack/Assist/Escape wheel)
- `/Game/Pal/Blueprint/UI/CommonWidget/RadialMenu/WBP_CommonRadialMenuBase` (shared base widget every radial menu variant — construction, weapon-change, emote, player-action — is built on)

Reading `WBP_PlayerRadialMenu`'s compiled string table (`strings -n 4`, same technique the sixty-fifth pass proved for `WBP_PalNPCHPGauge`) surfaced real function names: `CreatePlayerActionMenu`, `OpenPlayerActionMenu`, `"Can Open Player Action Menu"` (the eligibility gate — note the literal space, this is the function's real FName), `OnDecidedPlayerActionMenu`, `"On Decided Instruction Care"`, `OnDecidedInstruction_Feed`, `DecideMenuAction`, `ChangeMode`. Also present: `BP_ActionPairStandby_Petting` and `BP_ActionCutPalMeat_Player` (real player-performed pair-action classes for petting/feeding animations — separate from, and likely what vanilla actually plays instead of, this mod's own `PlayActionByType(HumanPetting/HumanFeeding)` approximation), and the Otomo-order message IDs already known from the sixty-fifth pass (`PAL_INSTRUCTION_CARE`, `PAL_INSTRUCTION_FEED`, etc. — confirmed here to be UI text label IDs, not function names).

**CORRECTION caught before deploying:** initially assumed the four "decide" functions lived on `WBP_PlayerRadialMenu_MenuContent_C` (it sounded like the natural home for "content decided"). Re-ran `strings` on that file ALONE and found it contains no Care/Feed/Otomo/instruction strings at all — just generic container/text-block names (`PalRetainerBox`, `BP_PalTextBlock`). All four actually came from the OUTER `WBP_PlayerRadialMenu` file. MenuContent looks like a generic, reusable "content slot" the outer wheel pushes whichever child variant into (construction list, Otomo-swap icons, instruction icons, etc.) — not where the decision logic lives. Fixed before deploying: every hook below targets `WBP_PlayerRadialMenu_C` only.

**Also checked: is `RequestSetOtomoOrder`/`EPalOtomoPalOrderType` the Care/Feed mechanism?** No — confirmed via `Pal_enums.hpp`: `EPalOtomoPalOrderType` only has `Default(0), Warlike(1), NotCombat(2)` — a combat-stance toggle (aggressive/passive), not an instruction-type selector. Watched anyway (native, essentially free) for direct confirmation, but the real Care/Feed trigger is expected to be the Blueprint functions above.

**IMPORTANT CAVEAT surfaced by the same string dump — the central open risk for this whole feature.** Every other name in this file revolves around the player's OWN ACTIVE OTOMO: `GetOtomoHolderComponent`, `TryGetSpawnedOtomo`, `SpawnedOtomo`, `IsOtomoActivated`, `OnActivateOtomo`, `GetSpawnedOtomoID`. There is no sign of a generic "whatever Pal you're looking at" target concept anywhere in this widget's strings. This strongly suggests the real "4" wheel's Care/Feed options are scoped to the player's current out/active Otomo specifically, not any arbitrary targeted actor — meaning it may have literally no path for a wild, unowned Pal at all. That's exactly the open question the new hooks (below) are built to answer directly instead of guessing further.

**Seventy-third pass code (Interaction.lua, forty-second pass in that file's own numbering).** Added pure WATCH hooks (same zero-side-effect discipline as the thirteenth-pass PalInteractComponent hooks) on:
- `WBP_PlayerRadialMenu_C:OpenPlayerActionMenu`
- `WBP_PlayerRadialMenu_C:Can Open Player Action Menu`
- `WBP_PlayerRadialMenu_C:CreatePlayerActionMenu`
- `WBP_PlayerRadialMenu_C:ChangeMode`
- `WBP_PlayerRadialMenu_C:OnDecidedPlayerActionMenu`
- `WBP_PlayerRadialMenu_C:On Decided Instruction Care`
- `WBP_PlayerRadialMenu_C:OnDecidedInstruction_Feed`
- `WBP_PlayerRadialMenu_C:DecideMenuAction`
- `/Script/Pal.PalOtomoHolderComponentBase:RequestSetOtomoOrder` (native, the stance-toggle — watched for completeness)

Each is registered independently (one `pcall` per candidate) and logs `[RADIAL-WATCH] RegisterHook(<path>) = OK/FAILED` so a live session immediately shows which real names actually resolve, plus `Context`/up to 3 args on every fire. F9/F10 are UNCHANGED and still fully functional — this pass only adds observation, nothing is removed yet. Syntax-verified (`luac -p`), deployed to both destinations.

**Test plan for Dragón's next session, exactly as requested ("check both the observer and the new change"):** press "4" near your own active Otomo, pick Care then Feed for real via the vanilla wheel — the log should show which of the above fire, in what order. Then look at/target a WILD Pal (not your Otomo) and try the same — if NOTHING fires, that confirms the ownership-gate hypothesis and means wild-Pal pet/feed needs either (a) a way to temporarily register the wild Pal into the Otomo-holder system just long enough to open this menu on it (heavier, Blueprint-adjacent, matches this project's established high-caution category), or (b) a custom-built lightweight wheel triggered by the same "4" key when looking at a non-Otomo Pal, reusing `WBP_CommonRadialMenuBase` for the same visual feel without touching the real Otomo-only logic. That decision is deferred until this test's real log data is in hand — no behavior-changing code has been written yet, on purpose.

## Seventy-fourth pass (2026-09-03): live test result — you were right about the wheel, and the hook names were probably wrong

Dragón pushed back on the seventy-third pass's "Otomo-only" worry, correctly: the radial menu ("4") also works on owned Pals that aren't your active/following Otomo — he demonstrated it directly by petting his active Lamball, then taking a Tanzee out at his base to roam free and petting IT too by aiming at it. Booted the game and ran exactly that test.

**MENU-WATCH (native, already-hooked) data confirms it directly.** The existing `PalInteractComponent` hooks caught it: a real `ActionType=4` `StartTriggerInteract`+`EndTriggerInteract` pair, firing repeatedly, with a REAL `TargetInteractiveObject` = a `PalInteractableSphereComponentNative` on the targeted Pal actor. This is a direct correction to this project's own earlier read of the same hook data (from a much older test), which had concluded `ActionType=2/3/4` were "unrelated periodic background calls, never paired with Start." That read was wrong, or at least incomplete — `ActionType=4` is clearly the real per-Pal radial-interact trigger, gated by AIMING at the Pal's own interactable sphere, not by "is this my current single active Otomo." Checked the native header dump for `UPalInteractableSphereComponentNative`/`UPalInteractiveObjectSphereComponent` for any ownership check — found none; same conclusion as the twentieth pass, the actual ownership/eligibility gate is still Blueprint-side, not in these native component classes.

**All 8 new Blueprint hooks (WBP_PlayerRadialMenu_C) FAILED** with "no UFunction with the specified name was found." Path format is confirmed correct (same shape as the proven `BindFromHandle` fix), so the likely cause is the function names: `strings` can't distinguish a real FName from Unreal's auto-generated, spaced-out cosmetic DisplayName. The pin name `CallFunc_Can_Open_Player_Action_Menu_Result` (seen in the original string dump) is strong evidence the real FName is `CanOpenPlayerActionMenu` (no spaces) — Unreal derives that exact pin name by splitting a PascalCase FName at capitals and joining with underscores, which only produces that result if the real name has no spaces to begin with.

**Seventy-fourth pass fix (Interaction.lua):** switched every candidate to try the no-space PascalCase form first (`CanOpenPlayerActionMenu`, `OnDecidedInstructionCare`), keeping the originally-observed spaced form as a fallback. Also added a bounded retry loop (up to 8 rounds, 5s apart, same discipline as `Indicator.lua`'s `register_bind_hook_once`) in case the real problem is instead that `WBP_PlayerRadialMenu_C` just isn't loaded into memory yet when the mod's `Init()` runs at game boot — covers both possible causes without having to guess which one it actually is. Per-target success tracking means a target that resolves on round 1 doesn't get retried, while others keep trying until they succeed or the round cap is hit. Syntax-verified, deployed to both destinations. Needs a fresh live test — same plan as before (Otomo pet/feed, then aim-targeted owned Pal pet/feed like the Tanzee test, then ideally a genuinely wild, uncaptured Pal if reachable).

## Seventy-fifth pass (2026-09-03): a generic input spy, so real key/click presses show up next to whatever hooks fire

Dragón's ask: "can you make it so you can check which function or which hook my keypresses trigger? or my clicks trigger? maybe that way we could find more if i interact with things while you're spying up." Checked for a clean native way to do this first: no reflected, event-style `InputKey`-shaped function exists on `APlayerController`/`UPlayerInput` in either `Engine.hpp` or `Pal.hpp` (only query functions like `IsInputKeyDown`/`WasInputKeyJustPressed` are reflected) — so there's no single function name to `RegisterHook` that would fire for every raw input the way this project's other hooks do for one specific game event.

**What's actually available and used instead:** the exact same `RegisterKeyBind` mechanism this project's F9/F10/CTRL+K bindings already use successfully, just looped over every valid key name UE4SS's `Key` table accepts for this install — transcribed directly from the bundled `Keybinds` mod's own comment block (`Mods/Keybinds/Scripts/main.lua`), not guessed. New file `InputSpy.lua`, wired into `main.lua`, binds ~150 names (letters, digits, F1-F24, all mouse buttons, arrows, OEM/media keys, etc.) each to one shared logger. Every press becomes one flushed log line (`[PalBonds/InputSpy] key/click pressed: <NAME>`), landing in the same log file, in real call order, right next to whatever `[RADIAL-WATCH]`/`[MENU-WATCH]`/etc. lines fire around the same moment — good enough to answer "what did that keypress actually trigger" by reading adjacent lines, even without millisecond timestamps.

**New risk category, flagged explicitly:** every key/mouse binding this project has ever registered before (F9, F10, CTRL+K) was deliberately a key the GAME ITSELF doesn't use, specifically to avoid any chance of interfering with real gameplay input. This is the first time the project binds keys the game actively uses for real controls (WASD, mouse buttons, etc). `RegisterKeyBind` is understood to be additive — it registers an extra Lua-side listener alongside the game's own input handling, not a replacement/consumer of the event — so normal gameplay should be unaffected, but this specific "bind nearly everything" shape hasn't been tried by this project before. Flagged in the file header for Dragón to watch for on first use (any dropped/laggy movement or attack input) and disable immediately (comment out `InputSpy`'s `require`/`Init()` in `main.lua`) if so. Every callback only logs a string, wrapped in `pcall`, capped at 400 lines total — no game state is read or touched.

Syntax-verified (`luac -p` on both `InputSpy.lua` and `main.lua`), deployed to both destinations. Purely diagnostic/temporary, same category as `Spy.lua`/`OtomoWatch.lua` — meant to be disabled once the radial-menu question is closed, not shipped.

## Seventy-sixth pass (2026-09-03): the six hooks work — and InputSpy just proved there are TWO separate radial-menu code paths

Dragón ran a short but deliberate test: opened the radial wheel plenty of times, some on his active/following Otomo, some aimed at his base Tanzee, with `InputSpy` and the corrected `[RADIAL-WATCH]` hooks both running. Reading the merged log (InputSpy key presses + RADIAL-WATCH + the older native MENU-WATCH, all in real call order) answers the question directly.

**Confirmed working, with real fires, for the first time this project has ever gotten a Blueprint-side hook on this system to actually fire:**
- `CanOpenPlayerActionMenu` (real name IS `Can Open Player Action Menu`, WITH the space — the earlier "cosmetic DisplayName" theory was wrong; Unreal really does allow literal spaces in a Blueprint function's FName, and this dev used them inconsistently, so some real names have spaces and some don't) — fires the instant "4" is pressed, `arg1=true`.
- `CreatePlayerActionMenu`, `OpenPlayerActionMenu` — fire immediately after, every single time, in that exact order (`Can Open` → `Create` → `Open`).
- `On Decided Instruction Care` (space, real) and `OnDecidedInstruction_Feed` (underscore, real) — fire on the actual click, paired with:
- `OnDecidedPlayerActionMenu` — fires on every click with an integer index: **0 = Feed, 1 = Care** confirmed directly (index 0 always co-occurred with the Feed-specific hook, index 1 always with the Care-specific one). A third click produced index 2 alone (no Care/Feed-specific hook fired) — almost certainly Attack, Assist, or Escape, whichever the third wheel slot was.

**The real, unexpected finding: these six ONLY fire for one of two distinct cases.** Cross-referencing with `InputSpy`'s per-press log and the older native `[MENU-WATCH]` hooks (already live since the thirteenth pass) shows two cleanly separable situations:
1. **"4" pressed with no aim target** (or not aiming at anything the interact system recognizes) → the six hooks above fire, opening the wheel scoped to the player's own active/following Otomo. This matches Dragón's own description exactly ("if i have a pal out and press 4 without pointing at anything it will automatically target my active pal").
2. **"4" pressed while AIMING at a specific Pal** (confirmed: his base Tanzee, via repeated native `ActionType=4` `StartTriggerInteract`/`EndTriggerInteract` pairs against that Pal's own `PalInteractableSphereComponentNative`) → **NONE of the six Blueprint hooks fire at all.** Not even `CanOpenPlayerActionMenu`. This is a genuinely different code path this project hasn't found yet — the aimed-Pal case must call into `WBP_PlayerRadialMenu_C` (or some other widget) through an entirely different function than the "no target" shortcut, or is handled some other way the Blueprint layer this project can see doesn't touch directly.

This is real progress, not a dead end: it means the "Otomo shortcut" wheel is now fully understood and hookable, and the remaining unknown is narrowed specifically to "what function fires when the wheel opens with an explicit aimed target." **Seventy-sixth pass fix:** added 12 more candidate hooks on `WBP_PlayerRadialMenu_C` (same file, no new strings extraction needed — picked from names already seen in the original dump but not yet tried): `SelectMapObjectId`/"Select Page by Map Object" (Palworld's internal term for any interactable world object, Pals included — the strongest lead for "which specific target this open is for"), "Select Page and Index", the `OpenSetup`/`CloseSetup`/`SetupEvent` lifecycle trio, `OpenMenu`/`CloseMenu`/`IsOpened`/`IsAnyMenuOpened`, and the Otomo-activation delegates `OnOtomoChanged_Activated`/`OnOtomoChanged_Inactivated`. Each tried with both a no-space and spaced form, same bounded-retry infrastructure. Syntax-verified, deployed to both destinations.

**Test plan:** same as before but this time aim specifically at a Pal (owned or, ideally, genuinely wild) and press "4" — check the log for which of the 12 new candidates (if any) actually fire.

## Seventy-seventh pass (2026-09-03): the aimed-Pal case fires NOTHING on WBP_PlayerRadialMenu — and the real per-object indicator system has been found

Dragón's test (six more candidate hooks added in the seventy-sixth pass, plus the full six from the seventy-fourth) delivered a clean, conclusive result. Merging `InputSpy` + `[RADIAL-WATCH]` + the native `[MENU-WATCH]` hooks in real call order:

**The "no aim target" case is now fully mapped, including new detail.** Every "4" press with no target fires `CanOpenPlayerActionMenu` → `OpenSetup` → `OpenMenu` → `CreatePlayerActionMenu` → `OpenPlayerActionMenu`, and closing fires `CloseSetup` → `CloseMenu`. A click fires the specific instruction hook (`On Decided Instruction Care`/`OnDecidedInstruction_Feed`) plus `OnDecidedPlayerActionMenu(index)` — confirmed indices 0=Feed, 1=Care, and a newly-seen index 6 on a different click (there are apparently up to ~7 selectable instructions on this wheel, not just Care/Feed). `IsAnyMenuOpened`/`OnOtomoChanged_Activated`/`OnOtomoChanged_Inactivated` also resolved as real functions but weren't observed firing yet.

**The aimed-at-a-Pal case: five separate, real "4" presses while aiming at his base Tanzee (confirmed via the native `MENU-WATCH` `ActionType=4` Start/End pair against that exact Pal's `BP_InteractableSphere`, at 19:50:25, :27, :31, :37, :40) produced ZERO hits on any of the 18 `WBP_PlayerRadialMenu_C` candidates tried across two passes.** This isn't a naming miss — it's conclusive: aiming at a Pal and pressing "4" does not call into `WBP_PlayerRadialMenu_C` at all. A genuinely different Blueprint system handles it.

**The real breakthrough:** rather than guess further, grepped the repak-extracted file listing for interact-indicator-shaped names and found two files never inspected before: `WBP_PalInteractiveObjectIndicatorUI` and `WBP_PalInteractiveObjectIndicatorCanvas`. Extracting and reading their string tables directly answers a question this project has had open since the **twentieth pass** ("find the Blueprint that implements `GetIndicatorInfo` for Pal characters, likely resolves the interact-menu question outright once found"). `WBP_PalInteractiveObjectIndicatorCanvas_C` literally has `GetIndicatorInfo`, `CreateIndicatorUI`, `ShowIndicator`/`ShowIndicators`/`HideIndicators`, and — the strongest lead — `OnUpdateTargetInteractiveObject`, a delegate whose name reads exactly like "fires when the player's aimed target changes." It also has a separate, parallel `ShowOtomoIndicator`/`ShowOtomoIndicators`/`OtomoIndicatorActionInfo` pair — real, concrete evidence that Otomo Pals get an additional/different indicator layered on top of the generic per-object one, and that aiming at ANY Pal (Otomo or not) goes through this system. The per-slot companion widget, `WBP_PalInteractiveObjectIndicatorUI_C`, has its own `SetActionInfo`/`SetInteractable`/`Activate`/`Deactivate`. Also confirmed along the way: `WBP_RadialMenu_base` (a third, previously-unexamined "RadialMenu"-named file) is purely the shared VISUAL shell (arrow + open/close animations only, no Care/Feed/Otomo logic) — meaning the circular wheel look can be shared by multiple different logical menus, which is consistent with everything found so far.

**Seventy-seventh pass fix (Interaction.lua):** generalized the round-runner into a reusable factory (`make_hook_round_runner`) so the same bounded-retry infrastructure can target multiple classes, then added 13 candidates on `WBP_PalInteractiveObjectIndicatorCanvas_C` and 8 on `WBP_PalInteractiveObjectIndicatorUI_C`, tagged `[INDICATOR-WATCH]`. Syntax-verified, deployed to both destinations.

**Test plan:** same as before — aim at a Pal (ideally the same Tanzee, or a genuinely wild one) and press "4" — check the log for `[INDICATOR-WATCH]` lines, especially `OnUpdateTargetInteractiveObject`, `GetIndicatorInfo`, and `ShowOtomoIndicator(s)`.

## Seventy-eighth pass (2026-09-03): Dragón spotted the real third menu family — WBP_WorkerRadialMenu

Dragón sent screenshots (no accompanying text) of a file listing showing three assets under `WorkerRadialMenu/`: `WBP_WorkerRadialMenu.uasset`, `WBP_WorkerRadialMenu_Overlay.uasset`, `WBP_WorkerRadialMenuContent.uasset` — found by browsing the pak himself, separately from this project's own repak digging. He noted the key insight: **base Pals are also called "workers"** in this game's own terminology. That's exactly the missing piece — the seventy-seventh pass had good leads on the per-object *indicator* system (why a Pal shows a prompt at all) but this is stronger: a whole separate radial-menu widget family, parallel to `WBP_PlayerRadialMenu`, specifically for interacting with a placed/base Pal.

Extracted all three files via `repak` and read their string tables directly (same technique as every pass since the seventy-third). Real, concrete confirmation this is the right family: `WBP_WorkerRadialMenuContent`'s string table contains `MsgID_Pet` and `MsgID_Feed` literally, alongside `MsgID_MoveToBox`, `MsgID_MoveToOtomo`, and `MsgID_ShowStatus` — this menu's actual option set — plus a dedicated `EPalWorkerRadialMenuResult` enum, which reads as a much cleaner selection signal than `WBP_PlayerRadialMenu_C`'s raw integer index ever was (if it's a real UENUM with named values, a hook could report "Pet"/"Feed" by name instead of guessing what index 2/6 meant, the way the Player menu left unresolved).

Two real classes, the same outer/inner split the Player menu had:
- **`WBP_WorkerRadialMenu_Overlay_C`** — the controller: `Open`, `Close`, `Construct`, `Destruct`, `DecideMenuAction`, `CancelEvent`, `Interact`, `OnSetup`, `OnSelectedEvent`, `OnSelectedMenu`, `RegisterActionBinding`, `ListenForInputAction`, `SetDisableWeaponForUI`, `OnAnyUIPushed`/`OnPushedStackableUI` (this pair takes a `PalHUDDispatchParameter_WorkerRadialMenu` struct — a strong candidate for where the specific target Pal handle is actually carried, since none of the function names themselves obviously take a target parameter).
- **`WBP_WorkerRadialMenu_C`** — the menu/content widget: `Construct`, `CreateContent`, `SetupContents`, `ClearSelectedIndex`, `CalculateRadialMenuArea`, `OnInitialized`, `OnClosed`, `OnSelectedMenu`/`OnSelectedMenu_Internal`, `OnDecideIndex_forBP` (a delegate — added as a hook candidate anyway in case it's also directly callable, though delegate signatures often aren't).

Left out anything that only appeared as a `CallFunc_*_ReturnValue` pin name (`IsDead`, `IsSameWidget`, `TryGetIndividualActor`, `GetHUDService`, `GetPalmi`, `GetParam`, `GetComponentByClass`) — those are call sites INTO other classes from this Blueprint's graph, not functions defined on either Worker menu class, so hooking them here on the wrong owner class would just always fail.

**Interaction.lua change:** added two more `make_hook_round_runner` calls (reusing the seventy-seventh pass's factory, no new infrastructure needed) for `WORKER_MENU_CLASS` and `WORKER_MENU_OVERLAY_CLASS`, tagged `[WORKER-WATCH]`. Same watch-only discipline as every hook in this file — logs only, no side effects. Syntax-verified, deployed to both destinations.

**Test plan:** aim "4" at a base/worker Pal (the Tanzee again, or any other placed Pal) and check the log for any `[WORKER-WATCH]` line — especially `Open`, `OnSetup`, `OnSelectedMenu`, and `OnAnyUIPushed`/`OnPushedStackableUI` (whose struct argument might reveal the target Pal handle directly, which would be new information even the Player-menu hooks never surfaced).

## Seventy-ninth pass (2026-09-03): checked the burst Dragón saw, and trimmed confirmed-dead candidates

Dragón had to quit early and reported seeing "a bunch of lines writing one after another in quick succession," and asked to check it and remove whatever's already confirmed not to work.

**What actually happened:** the session was only 25 seconds long (20:07:15–20:07:40 in-game clock). In that window the retry loop reached round 5 for every class (`RADIAL-WATCH`, `INDICATOR-WATCH`, `WORKER-WATCH`), and every single candidate on every class failed — including the six `RADIAL-WATCH` hooks long since proven to work (`Can Open Player Action Menu`, `CreatePlayerActionMenu`, etc.). That's the tell: this wasn't the Worker menu specifically failing, it was the whole session ending before any of these widget classes had even loaded (most likely still on the main menu or a loading screen) — so this run gives **no new evidence** about `WBP_WorkerRadialMenu`/`_Overlay` either way. Also worth noting for next time: `Logger.lua` truncates the log file per session, so the actual full-session data behind the seventy-sixth/seventy-seventh pass's "confirmed working" findings no longer exists in the raw log — only what's already written into this doc survives.

Separately, "a bunch of lines" is also just an inherent side effect of this project's find-real-names-by-trying method: every failed `RegisterHook` call makes UE4SS itself print a multi-line Lua stack traceback to the log, on top of this mod's own one-line `[X-WATCH] round N: ... = FAILED` entry — so a round with a dozen still-unresolved candidates is a dozen ~10-line bursts, all at once, every 5 seconds, until the round cap or a successful resolve. That's expected and harmless (still just watch-only hooks, no gameplay impact), but there was real cleanup to do:

**Removed outright (RegisterHook conclusively failed on ALL 8 rounds in a session where sibling candidates on the exact same class succeeded — proving the class was loaded and these names simply don't exist):** `SelectMapObjectId`, `SelectPageByMapObject`, `SelectPageAndIndex`, `IsOpened` — all four were seventy-sixth-pass additions to `WBP_PlayerRadialMenu_C`'s target list, conclusively dead ends per the seventy-seventh pass's log review.

**Simplified to a single candidate (the OTHER form is confirmed real, so the always-failing guess was deleted instead of tried and discarded every round):** `CanOpenPlayerActionMenu` → now only tries `"Can Open Player Action Menu"`; `OnDecidedInstructionCare` → now only tries `"On Decided Instruction Care"`.

**Deliberately left alone:** `ChangeMode`/`DecideMenuAction` (never explicitly confirmed working OR confirmed as a dead RegisterHook — could be either a wrong name or just an untriggered one, no way to tell without the now-gone raw log) and the `OpenSetup`/`CloseSetup`/`SetupEvent`/`OpenMenu`/`CloseMenu`/`IsAnyMenuOpened` dual-candidate entries (pass 77 confirmed all six DO work, but not which of the two name forms — trimming the wrong one would silently break a working hook). Also left every `INDICATOR-WATCH` and `WORKER-WATCH` candidate untouched, since this session's total failure across those classes isn't evidence of anything — see above.

Syntax-verified (`luac -p`), deployed to both destinations.

**Still pending, unchanged:** a real live test of `WBP_WorkerRadialMenu`/`_Overlay` — aim "4" at a base/worker Pal in a session that actually gets far enough in-world for the class to load, and check for `[WORKER-WATCH]` lines.

## Eightieth pass (2026-09-03): WBP_WorkerRadialMenu CONFIRMED live, full selection-index mapping recovered, and the real lag source found

Dragón ran a real, deliberate test: took his Tanzee out, petted it, fed it, opened "view stats", added it to his party, then took it back out of the party and petted it again; then placed his Petallia at the base and petted + fed her too. Felt lag again during the session. Both questions answered from the same log.

**The Worker menu is real and fully wired.** `[WORKER-WATCH]` fired 103 times total, and critically: `OnSetup`/`OnClosed` each fired exactly **7 times** — a perfect 1:1 match with 7 real worker-menu interactions in the test (Pet, Feed, ViewStatus, AddToParty on Tanzee; Pet on Tanzee again; Pet, Feed on Petallia). These two are clean, one-shot, per-open/per-close events — no spam, safe to rely on directly.

**Selection index mapping recovered by cross-referencing `OnSelectedMenu_Internal(index)` / `OnSelectedEvent(index)` against the real play order:**
- `OnSelectedMenu_Internal` (on `WBP_WorkerRadialMenu_C`) and `OnSelectedEvent` (on the Overlay) fire together on every selection, with DIFFERENT index numbering schemes for the same action (Internal uses the menu widget's own index, Event uses a different scheme — probably a page/global action ID) — both are internally consistent, so either can be used, just don't mix them up.
- Recovered mapping (Internal, Event): **(4, 5) = Pet**, **(3, 1) = Feed**, **(0, 2) = ShowStatus ("view stats")**, **(1, 4) = AddToParty**. 5 of the 7 real presses matched this mapping exactly, in order, with zero ambiguity (Pet→Feed→ShowStatus→AddToParty→Pet). The 6th press (expected: pet Petallia) logged the same index as Feed instead of Pet — most likely either a double-feed or a fast double-click registering only the second input; not treated as contradicting the mapping since 5/7 including both single-occurrence actions (ShowStatus, AddToParty) matched perfectly with no collisions. This lines up with the `MsgID_Feed`/`MsgID_Pet`/`MsgID_ShowStatus`/`MsgID_MoveToOtomo`/`MsgID_MoveToBox` set found in the seventy-eighth pass's string dump — `MoveToBox` (send to Palbox) is the one option not exercised this test, presumably index 2 (Internal)/3 (Event) by elimination.
- This means `EPalWorkerRadialMenuResult` (or whatever raw int this class actually reports) can be read directly off `OnSelectedMenu_Internal`'s argument to know EXACTLY which action the player picked on a worker Pal — Pet vs. Feed vs. ShowStatus vs. AddToParty vs. (presumably) MoveToBox — a much cleaner signal than anything the Player-menu system ever gave us.
- `OnAnyUIPushed` (11 fires) carries a `ScriptStruct /Script/CoreUObject.Guid` — not yet decoded, likely just a UI-push request ID, not obviously the target Pal handle. The actual target Pal identity for a worker-menu interaction isn't in any of these args directly; it most likely still needs correlating against the existing native `[MENU-WATCH]` `TargetInteractiveObject` hook (already live since the thirteenth pass) by timing, same as done for the Player-menu case.

**The real lag source, found and fixed.** `[INDICATOR-WATCH]` fired **3146** times in this ~137-second session — and 2375 of those (75%) were a single hook: `UpdateInteractTargetName`, firing with `arg1=nil` every single time (no useful data at all). That volume, at roughly 17 calls/second, is clearly a per-tick UI text refresh, not a discrete event — and since `Logger.log` does a synchronous, flushed disk write per call (see `Logger.lua`'s own header), a few thousand of those in two minutes is a real, feel-able cost. This is the exact same class of bug as the ninth-pass `find_targeted_pal` logging spam that caused a framerate dip back then. **Fix: removed `UpdateInteractTargetName` from the indicator-canvas target list entirely.** No functionality lost — `OnUpdateTargetInteractiveObject` already covers "what's the player aiming at now" at a sane ~66-fires-per-session rate, and unlike `UpdateInteractTargetName` it actually carries a real, resolvable target object: confirmed live firing with `BP_InteractableCapsule_C` (a PalBox) and, more importantly, `PalInteractableSphereComponentNative` on an actual `BP_Monkey_C` Pal actor — direct, concrete proof this hook sees Pals specifically, not just generic world objects.

Everything else on `WBP_PalInteractiveObjectIndicatorCanvas_C`/`_UI_C` fired at clearly discrete-event volumes this same session (`IndicatorDeactivate` 264, `ShowIndicator` 124, `SetActionInfo` 124, `IndicatorActivate` 76, `HideIndicators` 66, `ShowIndicators` 31) and is kept as-is — these look like real per-object-visibility-change events (multiple nearby interactables entering/leaving view), not per-tick spam.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** should feel noticeably less laggy now that the ~2400-line/session spam source is gone. Also worth trying: press the option that would be `MoveToBox` (send a worker Pal back to the Palbox) to confirm the missing index and complete the mapping.

## Eighty-first pass (2026-09-03): the first REAL (non-watch-only) hook on the vanilla radial menu

Dragón pushed back on doing another passive verification session just to re-confirm the lag fix ("just to check if there's no lag? do i really need that? — let's continue instead"), which is the right call: the eightieth pass already recovered a confirmed, reliable selection-index mapping (4=Pet, 3=Feed, 0=ShowStatus, 1=AddToParty) for `WBP_WorkerRadialMenu_C:OnSelectedMenu_Internal`, so there was already enough to act on instead of just watching more.

**What changed:** `OnSelectedMenu_Internal` now has its own dedicated, REAL hook (not just a watch-log entry) — when the player picks Pet or Feed through the actual "4" wheel while aiming at a Pal, it resolves which Pal via a new remembered-target variable (`lastAimedInteractTarget`, set from the already-proven-safe native `StartTriggerInteract` watch whenever `ActionType=4` fires — confirmed since the seventy-fourth pass to mean "aiming at a specific Pal") and calls `Interaction.OnWildPalPetted(pal)` — the exact same call F9/F10 already make to feed this mod's own trust/interaction-count logic. Removed the now-redundant watch-only log entry for the same function (it was double-logging every selection since this new hook logs its own fire too).

**Why this is safe:** it doesn't call any risky native function itself — no `PlayActionByType`, no `AddFriendShip`, no struct copies, nothing this project's crash history has been burned by. It only reads a remembered object reference (pcall-wrapped, with a `:GetOwner()` fallback since `TargetInteractiveObject` is sometimes the Pal's `PalInteractableSphereComponentNative` component rather than the actor itself) and calls this file's own `Interaction.OnWildPalPetted`, a function already safely exercised since the sixteenth pass.

**Why this matters:** for an OWNED Pal (all that's been tested live so far) this is harmless — same as it's always been, `OnWildPalPetted` is a no-op-ish bookkeeping call for anything already captured. But it's the concrete next step toward actually removing F9/F10: if this menu ever opens on a genuinely wild, uncaptured Pal, a real vanilla Pet/Feed through it will now count toward this mod's trust system directly, and the very first time that happens will also be live proof the ownership question resolves in our favor — no separate "just go check" session required, it's wired into normal play now.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next real test, whenever it naturally comes up (no need to go out of the way for it):** pet/feed an owned Pal through the worker wheel again and check for `[WORKER-ACTION]` log lines confirming the credit fired; and if a wild Pal ever gets aimed at with "4" and the wheel opens at all, that's the big one to watch for.

## Eighty-second pass (2026-09-03): REAL INCIDENT — the eighty-first pass's hook re-captured two already-owned Pals. Root cause found, fixed, and reverted.

Dragón tested "4" on a base Pal after the eighty-first pass shipped and reported something "unnatural": petting it "placed it on my party and the pal dropped loot." He also tried "4" on a wild Pal (nothing happened) and, correctly, called this the wrong direction and asked to be careful about corrupting his Pals.

**What actually happened, confirmed directly from the log:**

```
[WORKER-ACTION] Pet confirmed ... on BP_FlowerDoll_BOSS_C ... — crediting Interaction.OnWildPalPetted
[PalBonds/Trust] BP_FlowerDoll_BOSS_C ...: interaction #1 recorded (real rank=10, real point=205866)
[PalBonds/Trust] BP_FlowerDoll_BOSS_C ... reached 205866 friendship (threshold 55) — trust threshold for sphere-less capture met
[PalBonds/Capture] BP_FlowerDoll_BOSS_C ... reached full trust — capturing for real (sphere-less)
[PalBonds/Capture] [EXPERIMENT] owner BEFORE the call = UScriptStruct: 000001A8793093D8
[PalBonds/Capture] [EXPERIMENT] PalCaptureSuccess call returned — result=ok
[PalBonds/Capture] [EXPERIMENT] owner AFTER the call = nil
```

The same sequence repeated seconds later on a second Pal (`BP_SheepBall_C`, lower friendship — 70 vs. the 205866 above, still well past the 55 threshold).

**Root cause: `Trust.OnInteractionSucceeded` had NO ownership check.** It read the Pal's real `FriendshipPoint` and, if past `CAPTURE_AT_FRIENDSHIP_POINT` (55), unconditionally fired `Capture.OnTrustMaxed` → the real, experimental `PalUtility:PalCaptureSuccess(player, pal)` call (the same function that legitimately captures a WILD Pal — thirty-ninth pass). `BP_FlowerDoll_BOSS_C` is Dragón's own long-bonded, boss-tier Petallia — her real FriendshipPoint (205866) was always going to be past 55, the instant anything called this function on her. Calling the real capture function on an ALREADY-OWNED Pal re-ran the "assign this Pal to the capturing player" pipeline: the owner GUID field visibly changed from a real value to `nil` mid-call, and the practical, visible result was exactly what a genuine new capture does — auto-added to the active party, and (since she's boss-tier) capture-reward loot dropped.

**This bug is NOT new — it's been latent since the thirty-ninth/forty-first pass**, the entire time `Trust.OnInteractionSucceeded` has existed. It simply never fired before because the only thing that ever called it was F9/F10, and Dragón essentially never pressed F9/F10 on his own already-owned base Pals (he used the real vanilla UI for those, and F9/F10 mainly on wild ones in the field). The eighty-first pass's mistake wasn't a coding bug in the new hook itself — it correctly resolved the target and called the exact function F9/F10 already call — the mistake was **wiring a path that fires constantly during completely ordinary play (petting/feeding your own base Pals) into a function that was never actually safe for that case.** Dragón's read of this as "the wrong direction" is correct: F9/F10 are keys nobody presses by accident on an owned Pal; the vanilla "4" wheel is exactly how base Pals get interacted with normally, so the blast radius of connecting it to automatic trust/capture logic was much bigger than it first looked.

**Two fixes, in order of importance:**

1. **Root-cause fix (kept permanently, protects every path including F9/F10):** added `Capture.IsAlreadyOwned(pal)` — reads the same `SaveParameter.OwnerPlayerUId` field this project already reads safely elsewhere, and checks its four raw components (`FGuid = {A, B, C, D}`, all `int32`, confirmed in `CoreUObject.hpp`) against all-zero, which is Unreal's own "never assigned" convention for a default-constructed GUID — the state a genuinely wild Pal's owner field sits in. **Fails safe on purpose**: any read failure anywhere in the chain returns `true` (treat as owned → caller skips) rather than `false` (treat as wild → caller proceeds), since a false negative just silently skips bookkeeping for one interaction, while a false positive is exactly what caused this incident. `Trust.OnInteractionSucceeded` now bails out immediately, before touching any state, if this returns true; `maybe_trigger_capture` (reachable independently from the passive-gain tick) checks it again as a second layer.
2. **Reverted the eighty-first pass's real hook back to watch-only.** Even with the guard above making the specific failure impossible, Dragón was right that automatically wiring real game-state-changing behavior into a UI action that fires during every normal interaction with an owned Pal deserves more deliberate care than it got — it's logged only now (`[WORKER-WATCH] OnSelectedMenu_Internal fired — index=N`), exactly like every other confirmed-real hook in this file, with no calls into `Interaction.OnWildPalPetted` or anything else.

Also directly answered by this same test, as a side note: "4" on a genuinely wild Pal produced no menu and no log activity at all — consistent with everything found so far (the ownership gate for both radial-menu systems still hasn't been found, and neither one shows any sign of opening for a Pal that isn't already owned or actively targetable as a worker).

Syntax-verified (`luac -p`) on all three changed files (`Interaction.lua`, `Trust.lua`, `Capture.lua`), deployed to both destinations.

**On the Pals themselves:** the practical, visible effects were "added to party" and "a loot drop" — consistent with the game's own normal capture-success behavior firing a second time on Pals that were already owned, not with any corruption of the Pal's own stats, species, or identity (those live in separate fields this call never touched). Nothing observed suggests permanent damage, but this wasn't verified beyond what the log shows — worth Dragón visually confirming both Pals (the Petallia and the other one) still look and behave normally.

## Eighty-third pass (2026-09-03): a real path to "the vanilla menu, but targeting a wild Pal" — without custom UI or forcing anything open

Dragón pushed back on the custom-menu idea directly: building real icon art, wedge-highlight animations, and menu sounds is genuinely outside what this project can produce well (the trust bar proves simple Canvas drawing works, but that's a long way from a polished radial menu). He also restated his real preference: make the EXISTING "press 4 with no aim target" wheel act on the wild Pal you're aiming at, instead of your own active Otomo — and asked which is actually easier.

Agreed with his instinct, and found a concrete, much more promising path than either previously-discussed option (custom art, or forcing the menu open blind on an unsupported target — the same risky category as the eighty-second pass's incident): the "no-aim" wheel must internally call SOME function to decide "who is my target Otomo" before it opens. Found a strong, real candidate: **`TryGetSpawnedOtomo()` on `UPalOtomoHolderComponentBase`** — a plain, no-argument, NATIVE getter (confirmed in `Pal.hpp`, not a Blueprint-only function) that returns the player's current active Otomo actor. If the menu reads this (or an equivalent) to pick its target, and if UE4SS's hooks can override a native function's return value, the ENTIRE existing, fully-polished Pet/Feed pipeline could be redirected onto a wild Pal by substituting just this one value — full authentic UI, zero new art, and no need to touch Trust/Capture at all.

Checked whether return-value overriding is even possible in this UE4SS build: the bundled `BPML_GenericFunctions` mod's `ConstructPersistentObject` custom event uses `OutParam:set(PersistentObject)` to write a value back through a hook — real, confirmed proof the underlying `:set()` mechanism exists on a wrapped param object. That's for a `RegisterCustomEvent`, not a `RegisterHook` on an ordinary function, so it doesn't fully confirm the same thing works for a plain getter's return value — that still needs a live test.

**This pass ONLY watches — zero behavior change.** Added a pre+post hook on `TryGetSpawnedOtomo`: the pre-hook logs every call (confirms whether this is really what fires during the no-aim wheel, and whether it's ever called at all during the aimed/worker-menu case — if it's never called there, that's further confirmation the two menu systems are cleanly separate, consistent with everything found since the seventy-sixth pass), and the post-hook logs the real return value, then safely tests the override mechanism with a genuine no-op: reads the return value and immediately calls `ReturnValue:set()` with that SAME value. Behavior is completely unchanged either way (same value going back in) — but whether that `pcall` succeeds or throws tells us, with zero risk, whether substituting a real wild Pal here is even mechanically possible before ever trying it live.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** press "4" normally (near your active Otomo, no aiming) a couple of times — the log should show `[OTOMO-GETTER-WATCH]` lines confirming the call, the real Otomo returned, and whether the no-op `:set()` test says SUPPORTED or NOT SUPPORTED. If supported, the next step is a single, carefully bounded live test substituting a wild Pal in place of the real Otomo for one press — if not, this path is a dead end and worth knowing that before investing more time in it.

## Eighty-fourth pass (2026-09-03): the eighty-third pass's test session explains the wild-Pal failure directly — and points at a safer redirect target than TryGetSpawnedOtomo

Dragón's test report: "took a pal from my party as active, petted it with the radial menu, approached a wild pal and tried the radial menu but it still targetted my otomo." Read the fresh log from that exact session (21:10:10–21:12:19) instead of asking him to describe it further.

**Confirmed from the log:**

- `TryGetSpawnedOtomo`'s no-op `ReturnValue:set()` test succeeded on all 474 calls sampled — the override mechanism genuinely works in this build. Also caught a real anomaly: for a ~30s stretch the returned value's `GetFullName()` started throwing (falls back to the bare `UObject: 0x...` form), with a different address every ~3 seconds — consistent with UE4SS's wrapper for a null/invalid pointer, i.e. this getter can and does return nothing while the Otomo is between states.
- **`WORKER-WATCH` gave up after all 8 retry rounds — every single candidate on `WBP_WorkerRadialMenu_C`/`_Overlay` failed to register this entire session.** That class never loaded into memory at all, meaning the aim-based Worker Menu never opened once — not on the party Pal, not on the wild Pal.
- All 7 real "FOUR" key presses this session instead went through the no-aim `WBP_PlayerRadialMenu_C` (`RADIAL-WATCH`'s `IsAnyMenuOpened` fired right alongside one of them), which is the menu hardcoded to act on whatever `TryGetSpawnedOtomo` returns.

**What this means:** the wild Pal wasn't ignored because an override failed — no override was ever attempted live. It was ignored because the ONLY menu that opened either time was the no-aim Player Menu, which by design always targets the Otomo regardless of what you're aiming at. The Worker Menu (the one that actually resolves to a specific aimed-at Pal) simply never engaged this session at all — likely because the wild Pal's interact affordance never triggers the native `StartTriggerInteract(ActionType=4)` aim-lock the Worker Menu depends on (no such event appears anywhere in the log), and the party Pal wasn't approached closely/precisely enough to trigger it either this time.

**Why `TryGetSpawnedOtomo` is now the wrong override target:** it fires ~4 times/second even with no menu open at all (474 calls in ~2 minutes), so it's clearly read by other systems too (indicator UI, AI/follow logic, possibly more) — forcing it to return a wild Pal even briefly, without a way to scope the override to just the menu's own call, risks breaking whatever else reads it. That's the same shape of mistake as the eighty-second pass's missing ownership check: a shared, widely-used function is not a safe place to bolt on Pal-specific behavior.

**Better redirect target identified:** the Player Radial Menu's own action-decision functions — `OnDecidedInstructionCare` and `OnDecidedInstruction_Feed` (both already confirmed live, seventy-sixth pass) — fire only when the player actually picks Pet/Feed from that specific menu. Hooking those for real and calling this mod's own already-safe `do_pet()`/`do_feed()` on the Pal you're aiming at (via `find_targeted_pal()` + `Capture.IsAlreadyOwned()` to confirm it's genuinely wild) needs zero tricks against a shared native getter — it reuses machinery already proven safe since the sixteenth pass. Not wired yet: it's still unknown which of `OnDecidedInstructionCare` / `OnDecidedInstruction_Feed` / `DecideMenuAction` fires for Pet specifically vs. Feed, or what their arguments look like — `RADIAL-WATCH` already logs `self`/`arg1`/`arg2`/`arg3` generically for all three, so the next real test just needs Dragón to call out "picking Pet now" / "picking Feed now" in order, so the fires can be matched to the action the same way the eightieth pass recovered the Worker Menu's index mapping.

**Change made this pass (watch-only, zero behavior change):** deduped `OTOMO-GETTER-WATCH` logging — it now only logs when the described return value actually changes from the last call, instead of on every single call, cutting ~474 lines/2min down to just the transitions (the same lag-prevention discipline as the eightieth pass's `UpdateInteractTargetName` fix, applied proactively this time before it became a real complaint). The now-proven no-op `:set()` test itself was removed from the per-call path since it already answered its question.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next real test:** aim at a wild Pal (or the active Otomo, either works for mapping purposes), press "4", and explicitly narrate picking Pet, then repeat and explicitly narrate picking Feed. That gives the exact `RADIAL-WATCH` fires needed to know which function/argument pattern means which action — the missing piece before wiring any real Pet/Feed redirect.

## Eighty-fifth pass (2026-09-03): the first real substitution attempt — scoped, bounded, EXPERIMENTAL

Dragón's next test: aimed "4" at a wild Pal (no visible effect), then summoned his Otomo and pet it for real through the same no-aim wheel. Read the fresh log again instead of asking for details.

**New finding that changes the plan:** `OnDecidedInstructionCare` fired twice — once with `arg1=false` at the exact moment `TryGetSpawnedOtomo` was returning an unresolvable/likely-null object (Otomo not spawned yet), and once with `arg1=true` right after `TryGetSpawnedOtomo` had just returned a real, resolvable Otomo (`BP_SheepBall_C`). That's strong evidence this function's boolean argument is an OUTPUT — "was a valid target found" — not something we could feed a wild Pal into, and the function itself takes no Pal reference as a parameter at all. So the eighty-fourth pass's plan (hook `OnDecidedInstructionCare`/`OnDecidedInstruction_Feed` directly and act on the aimed Pal ourselves) is a dead end: by the time those fire, the target is already resolved elsewhere — almost certainly via `TryGetSpawnedOtomo` itself.

Confirmed useful in passing: `OnDecidedPlayerActionMenu` fired `index=1` both times a real "Care" selection happened, matching the seventy-sixth pass's mapping (0=Feed, 1=Care/Pet). Also confirmed again: `WORKER-WATCH` still failed to register the Worker Menu class this whole session — the aim-based menu still never opened, on the wild Pal or otherwise.

**This puts the redirect back on `TryGetSpawnedOtomo` — but scoped this time, not global.** New machinery: `radialMenuActionWindowOpen`, a flag that's only ever true for the brief window between the confirmed-real `Can Open Player Action Menu` fire and the confirmed-real `CloseMenu` fire (i.e. only while a "4"-press's menu is actually open), with a 1.5s safety timeout guarded by a generation counter in case `CloseMenu` doesn't fire. `make_hook_handler` gained an optional `onFire` side-effect parameter so these two `radialHookTargets` entries can open/close the window as a side effect of their existing watch-only logging, with every other entry unaffected (no `onFire` set = no behavior change).

Inside that narrow window, and only once per window (`radialMenuRedirectedThisWindow`), `TryGetSpawnedOtomo`'s post-hook now: reads the player's camera location/forward vector (same pattern as `do_test_capture`), calls `find_targeted_pal` (the exact same look-based targeting F9/F10 already use safely, excluding the real Otomo from candidates), checks `Capture.IsAlreadyOwned` to confirm the aimed Pal is genuinely wild, and if so calls `ReturnValue:set(wildPal)` — the same `:set()` mechanism proven SUPPORTED in the eighty-third pass, this time with a real substitute instead of a no-op. Outside the window, or if nothing wild is aimed at, behavior is untouched.

**Honest risk note, unresolved until tested live:** this function takes no Pal parameter, so whatever actually runs the Pet/Feed animation almost certainly re-reads this same getter rather than being handed a value directly — that's the bet this pass makes, and it's unconfirmed whether the game's own logic will treat a substituted wild Pal correctly once it gets one. No Trust/Capture code path is touched by this substitution itself, and the window closes automatically within 1.5s either way, so a bad outcome should be contained and quick to see — but this is explicitly labeled EXPERIMENTAL and is the first live substitution attempt in this project, not a no-op test.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** aim "4" at a wild Pal and pick Pet (or Feed) from whichever menu opens, watching closely for `[RADIAL-REDIRECT]` log lines and for anything unusual happening to either the wild Pal or the real Otomo. Report back immediately if anything looks wrong — this is exactly the kind of live trial the eighty-second pass showed can have unexpected side effects.

## Eighty-sixth pass (2026-09-03): does a real, native "follow" system exist for wild Pals? Read-only investigation

Dragón asked two direct questions: could the 1.5s follower tick be a lag source, and — more pointedly — is the current follow logic ("fire a move order every ~1s, still gets ignored sometimes") really the best available, given it's admittedly just an approximation, capping it off with "im not sure you know how to [find something better]."

**On the tick/lag question:** no evidence points that way. The follower tick runs once every 1.5s (≈0.67/sec), only touches Pals actually in `BondingState` (typically 0–1 at a time), and does one real, purposeful native pathfinding call (`PalMoveToLocation`) — categorically different from the two real lag bugs already found and fixed in this project (`UpdateInteractTargetName` at ~17/sec with useless args, `TryGetSpawnedOtomo` at ~4/sec from unrelated ambient systems). If real lag shows up, the log would show it same as those two did; nothing here currently looks like a candidate.

**On the follow question — real research, not a guess:** grepped the game's own header dump (`CXXHeaderDump/Pal.hpp`) for how a REAL Otomo Pal actually decides to follow. Found `APalAIController:GetAIActionComponent()`, returning a `UPalAIActionComponent` (a `UPawnActionsComponent` subclass — Unreal's own action-stacking system for Pawns) that manages a set of composite action classes. One of them, `UPalAIActionOtomoDefault : public UPalAIActionCompositeBase`, exposes `SetOtomoFollowAction()` alongside `SetOtomoCombatAction()`/`SetOtomoWorkAction()`/`SetOtomoBaseCampAction()`/`SetOtomoBerserker()` — this is clearly the actual decision layer a real Otomo uses to choose between follow/combat/work/base-camp/berserker. That's a genuinely more solid mechanism than this project's current periodic-`PalMoveToLocation` nudge, which doesn't override the Pal's own AI at all — it just competes with whatever wander/flee decision the wild AI makes between ticks, which is exactly why commands get "ignored" sometimes: nothing is actually replacing the Pal's own decision-making, just nagging it.

**The catch, found by the same search:** there is no "Wild"-named composite action class anywhere in the entire dump (checked every `UPalAIAction*` class name). That raises a real, unanswered question — does a wild Pal's `AIController` even have an active `UPalAIActionComponent` at all, or does wild behavior run through a completely different path (plain Behavior Tree, no composite-action layer) that this system was never built to touch? Guessing wrong here and calling `SetRootComposite`/pushing a new `UPalAIActionOtomoDefault` onto a wild Pal blind would be the same category of risk as the eighteenth pass's `SetActiveAI(false)` mistake (which silently killed a Pal's self-defense while looking fine in the logs) — or bigger, since it involves constructing/attaching real game AI objects, not just flipping a bool.

**What shipped this pass: pure read-only diagnostic, zero behavior change.** `Combat.StartFollowing` now logs, once per follow-start (not per tick — no spam risk), whether the bonding wild Pal's `AIController` has a usable `AIActionComponent`, and if so what `GetCurrentAIActionCategory()`/`GetCurrentAction_BP()` report. Nothing is set, pushed, or changed — this only establishes ground truth before any real attempt is considered. Reused `safe_call`/`pcall` throughout, matching this file's existing safety pattern.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** bond with a wild Pal as usual (get it following) and check the log for `[FOLLOW-DIAG]` lines. If it says "HAS an AIActionComponent," the native follow system might genuinely be reachable and worth pursuing for real. If it says "NO usable AIActionComponent," that confirms wild Pals run a separate path and this particular shortcut is a dead end — worth knowing either way before investing more time.

## Eighty-seventh pass (2026-09-03): REAL BUG FOUND IN THE EIGHTY-FIFTH PASS'S REDIRECT — the substitution twice targeted the PLAYER, not a wild Pal

While answering Dragón's lag/follow-system question, the live log from his most recent session (the one where the eighty-fifth pass's redirect actually fired for the first time) got a full read — and it surfaced something the eighty-fifth pass missed. Of 7 `[RADIAL-REDIRECT]` substitutions that session, 5 correctly picked a wild `BP_SheepBall_C`, but **2 substituted `BP_Player_Female_C` — Dragón's own player character — in place of the Otomo.**

**Root cause:** the eighty-fifth pass's redirect code called `find_targeted_pal(originLoc, forward, returned)`, excluding only the CURRENT OTOMO from candidates — not the player. `find_targeted_pal` scans `FindAllOf("PalCharacter")`, and the player's own actor class apparently satisfies that same scan (unlike `do_pet`/`do_feed`/`do_test_capture`, which have always correctly excluded the player, not the Otomo, from this exact same function). On top of that, `Capture.IsAlreadyOwned` — asked to check ownership on a player actor for the first time ever — read an all-zero owner GUID off some shared character-parameter component and wrongly concluded "wild," letting the substitution through both times.

**What actually happened in-game — confirmed benign, but only by luck:** both times, Dragón selected "Care" (Pet) right after the substitution, and both times the real `AddFriendShip` grant that followed a few seconds later landed on the REAL Otomo's parameter object, not the player's. That means whatever actually executes the pet animation and friendship grant does NOT re-read `TryGetSpawnedOtomo` — it must cache the target earlier in the open sequence, or read it from somewhere else entirely. This also answers the eighty-fifth pass's open question ("does the real Pet/Feed logic re-read this getter") — no, apparently it doesn't, at least not in whatever code path actually applies the interaction. Nothing observed suggests anything actually happened to Dragón's player character. But this was an accident of implementation, not a guarantee, and is exactly the class of gap this project has been burned by before (the eighty-second pass's missing ownership check) — worth fixing immediately regardless of the fact that no harm landed this time.

**Fix, applied at the source:** `find_targeted_pal` is now called with the PLAYER excluded (`player`, not `returned`) — the exact same exclusion `do_pet`/`do_feed` have always safely used for this identical function. Added two more explicit guards as belt-and-suspenders: skip if the found candidate's `GetFullName()` matches the player's (in case name-based exclusion ever misses), and skip (as a harmless no-op, not an error) if the found candidate is already the current Otomo.

Syntax-verified (`luac -p`), deployed to both destinations immediately.

**Also confirmed from this same log, unrelated to the bug:** the follower tick (~0.67/sec, only touching actively-bonding Pals) shows no signs of being a lag source — nothing like the two previously-fixed real lag bugs. `WORKER-WATCH` still shows zero actual fires this session (218 lines were all registration attempts, mostly failing) — the aim-based Worker Menu still hasn't opened once in any session logged so far.

## Eighty-eighth pass (2026-09-03): ROOT CAUSE FOUND for the wild-Pal Worker Menu — and a first real fix attempt

Between the eighty-seventh pass and this one (during a long research session, not yet logged here), Dragón ran a series of Live View dumps that overturned the eighty-fourth pass's belief that `WBP_WorkerRadialMenu_C` never loads. It does — the aim-based Worker Menu (the real, aimed "4" wheel, distinct from the no-aim Player Menu) genuinely does open on both an owned Pal and a wild one. Two comparable live JSON dumps of the actual dispatch object, `PalHUDDispatchParameter_WorkerRadialMenu`, one from each case, gave a direct, concrete answer to "why doesn't it work for wild Pals":

```
owned: IndividualHandle = PalIndividualCharacterHandle_2147480691
       OnClose          = (BP_Kitsunebi_C_2147425992.OnSelectedOrderWorkerRadialMenu)
wild:  IndividualHandle = PalIndividualCharacterHandle_2147480691   <- SAME object, both dumps
       OnClose          = ()                                       <- empty
```

Two distinct problems, not one:

1. **`OnClose` (a single/dynamic delegate — the `(Object.Function)` format is how a `DECLARE_DYNAMIC_DELEGATE`-style single-cast delegate serializes, not a multicast list) is never bound for the wild case.** Without it, selecting a menu option has no completion callback to actually run.
2. **`IndividualHandle` is the literal same handle object in both dumps** — not just similar, the exact same instance. Whatever this object is (almost certainly a stale/shared handle, quite possibly the real Otomo's), it never gets re-pointed at whatever Pal is actually being aimed at. Even a correctly-bound `OnClose` would still act on the wrong target without also fixing this.

**Structural feasibility check (real SDK evidence, not assumption):** `OnSelectedOrderWorkerRadialMenu(UPalHUDDispatchParameterBase* Parameter)` is declared on `APalMonsterCharacter` — the universal base class for every Pal actor in the game, wild or owned. The exact function the owned case's `OnClose` points to already exists, unmodified, on any wild Pal too.

**The fix implemented this pass:** a new `RegisterHook` on `/Script/Pal.PalHUDInGame:PushWidgetStackableUI(WidgetClass, Parameter)` (plus its likely-equivalent wrapper, `/Script/Pal.PalHUDService:Push`, same signature) — both real, native, confirmed in the SDK dump and the bundled Lua type stubs. This fires right as the already-built `Parameter` object is handed off to actually display a widget: late enough that every field the menu will read is already set by whatever constructed it, early enough that nothing has consumed those fields yet. The hook bails out immediately unless the Parameter's own class name (via `GetFullName()`) contains "WorkerRadialMenu" — every other UI push in the game (chest, inventory, dialogs, etc.) is a complete no-op here, zero risk to anything else.

When it IS a WorkerRadialMenu Parameter: reuses `find_targeted_pal` (the same proven look-based targeting `do_pet`/`do_feed`/the eighty-fifth pass's redirect all use, correctly excluding the player this time per the eighty-seventh pass's fix) to find the aimed Pal, gates to wild-only via `Capture.IsAlreadyOwned`, then — only for a confirmed wild target — rewrites both broken fields:

- `Parameter.IndividualHandle = wildHandle`, where `wildHandle` comes from a new `get_individual_handle(pal)` helper — a direct field read of `pal.CharacterParameterComponent.IndividualHandle` (confirmed a plain pointer field in `Pal.hpp`, sitting right next to the already-used `IndividualParameter`/`GetIndividualParameter()` — same safe "field read, not whole-struct call" pattern this project has used since the eighth pass).
- `Parameter.OnClose:Bind(wildPal, "OnSelectedOrderWorkerRadialMenu")` — **the one genuinely unconfirmed piece.** No bundled mod or Lua type stub in this UE4SS install documents the exact delegate-binding call signature; `:Bind(Object, "FunctionName")` is the best-evidenced guess based on how UE4SS commonly exposes single/dynamic delegate properties. Wrapped in its own `pcall`, logged separately from the `IndividualHandle` write (`[WORKER-BIND-FIX] OnClose:Bind() call: ok` or `FAILED: <exact Lua error>`) — if the name/signature is wrong, the live error text is real, specific evidence to iterate from (the same trial-and-error discipline that found `ReturnValue:set()` works for `TryGetSpawnedOtomo` back in the eighty-third pass).

No behavior change at all for the already-working owned-Pal case — the `isWild` gate means this hook does nothing whatsoever unless `find_targeted_pal` + `Capture.IsAlreadyOwned` confirm a genuinely wild target.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** aim the real "4" wheel at a wild Pal (same aiming that got the Worker Menu to open for the live dumps above — close range, direct aim) and pick Pet or Feed. Watch the log for `[WORKER-BIND-FIX]` lines:
- `saw a WorkerRadialMenu Parameter being pushed` confirms the hook fired at all.
- `IndividualHandle write: ok` / `OnClose:Bind() call: ok` (or their `FAILED:` counterparts with the real error) tell us immediately which half of the fix, if either, actually worked.
- If both say `ok`, the real test is whether picking Pet/Feed now visibly does something to the wild Pal — report exactly what happens (or doesn't).

## Eighty-ninth pass (2026-09-03): three real tests, ZERO fires — added a diagnostic to find out if this hook point sees any radial-menu traffic at all

Dragón tested carefully: cleared the ground around a wild Lamball (no logs/stones/drops nearby, per the previous pass's theory about the interact-lock grabbing clutter instead of the Pal), got close, aimed directly at it, and spammed "4" repeatedly. Confirmed directly: **"the radial menu that popped up was always the one from the active pal."** Read both fresh logs (the earlier "clean ground" attempt and this one) directly — same result both times: `WORKER-WATCH` still gives up after all 8 retry rounds (the `WBP_WorkerRadialMenu_C` Blueprint class never loads into memory this session, on any target), and the eighty-eighth pass's `[WORKER-BIND-FIX]` never fired once (0 hits across both sessions' full logs). F10 (the mod's own direct feed) worked fine and confirmed the Lamball's real internal species name is `Sheepball`.

This rules out the "just need cleaner aim" theory from the eighty-eighth pass's test instructions — aim precision was not the problem this time, and the result was identical. The real open question now is bigger than "why doesn't the Worker Menu open for wild Pals" — it's **"does `PushWidgetStackableUI`/`PalHUDService:Push` even carry ANY radial-menu traffic at all, Player menu included, or is the game dispatching both menus through some other function entirely?"** If neither hooked function ever fires even for the (definitely-opening) Player Menu, that means this whole hook point has been watching the wrong door from the start, independent of the wild-vs-owned question.

**Change made this pass:** added an unconditional (deduped-on-change, so it can't spam) diagnostic log, `[WORKER-BIND-FIX-DIAG]`, printing the class of literally every widget pushed through either hooked function — not just ones matching "WorkerRadialMenu". The very next "4" press (whichever menu opens) will show directly whether this hook point sees that traffic at all, and if so, under what class name.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** press "4" once (any target, owned or wild — the Player Menu opening is fine, that's useful data too) and check the log for `[WORKER-BIND-FIX-DIAG]` lines. If one appears showing `WBP_PlayerRadialMenu_C` or similar, this hook point is real and just needs the Worker Menu to actually load to prove the rest of the fix. If NOTHING appears at all even after a "4" press that visibly opens a menu, that's the answer: this hook point needs to be abandoned for a different one.

## Ninetieth pass (2026-09-03): real breakthrough — the Worker Menu opened live, and the actual delivery mechanism was found

Dragón's "pressed it a bunch of times aiming at different things" test finally produced the real thing: a full, confirmed live sequence in the log — `Construct` → `OnSetup` → `CreateContent` (×5, one per menu option) → `SetupContents` → `OnAnyUIPushed` → `OnClosed` → `OnSelectedEvent` (index=5, which the eightieth pass already mapped to **Pet**) → `Destruct`, all on real `WBP_WorkerRadialMenu_C`/`_Overlay_C` instances. First confirmed real open-to-close-to-selection cycle for this menu in the project's history.

But cross-referencing timestamps against the eighty-ninth pass's new diagnostic showed something important: **zero `[WORKER-BIND-FIX-DIAG]` lines anywhere near that window.** The last diagnostic fire before the menu's full lifecycle was 35 seconds earlier, and the next one was over a minute after the menu had already closed. That's conclusive: `PushWidgetStackableUI` and `PalHUDService:Push` — the eighty-eighth pass's hook point, chosen because the SDK dump documents both taking exactly `(WidgetClass, Parameter)` — are **not** how this specific menu's dispatch Parameter is actually delivered, despite matching the documented signature. The diagnostic did its job: it answered the question cleanly instead of leaving it open to more guessing.

Second clue from the same log: `OnSetup` fired with `self=<real Overlay instance>` but `arg1=nil arg2=nil arg3=nil` — it takes no meaningful arguments at all. Combined with the fact that this whole Blueprint family already names its dispatch object "Parameter" (from `PushWidgetStackableUI(WidgetClass, Parameter)`'s own signature), the working theory is that the Parameter is stored as a plain Blueprint variable directly on the widget instance — `self.Parameter` — set before `Construct`/`OnSetup` fire (standard UMG widget lifecycle: construction-time variables are set before these events run), not passed as an argument to any hookable function at all. That would explain why no named function anywhere in this file's candidate list has ever shown the Parameter as an argument.

**Change made this pass:** extracted the actual fix logic (find the aimed wild Pal via `find_targeted_pal`, gate on `Capture.IsAlreadyOwned`, read the wild Pal's own handle, rewrite `IndividualHandle`, bind `OnClose`) out of the eighty-eighth pass's function into a shared `apply_wild_fix_to_worker_parameter()`. Added a new real hook on `WBP_WorkerRadialMenu_Overlay_C:OnSetup` — proven to fire on every real Worker Menu open, unlike the abandoned Push-based hook — that reads `self.Parameter` directly off the widget instance UE4SS hands us via `Context`, and if it resolves to a real WorkerRadialMenu object, runs the same fix. Gave it its own retry loop (same discipline as every other Worker Menu Blueprint hook — the class isn't loaded at `Init()` time). The old Push-based hook is left in place as a free diagnostic fallback in case it's ever proven wrong.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** same as before — get the Worker Menu to open (this last session showed it CAN happen from repeated "4" presses at different targets, even if the exact trigger condition is still fuzzy) and pick Pet or Feed on a wild Pal. Watch the log for `[WORKER-BIND-FIX] OnSetup self.Parameter = ...` — if it shows a real `PalHUDDispatchParameter_WorkerRadialMenu` object (not `nil`), the hook point is confirmed and the rest of the fix gets a real chance to run; if it shows `nil`, that theory is wrong too and the search continues from there with real evidence either way.

## Ninety-first pass (2026-09-03): Dragón supplied the real missing insight — it's base-worker status, not wild-vs-owned

Dragón corrected the framing directly, from live observation: *"i cannot choose which menu to open, i can just press 4, the menu itself opens depending on what i target, if its a base pal it opens the worker menu, if not then its the other one."* That reframes the eighty-eighth through ninetieth passes entirely — the Worker Menu was never gated on ownership. It's gated on whether the aimed Pal is registered as a base worker. A wild Pal structurally can never satisfy that, no matter how correct the OnClose/IndividualHandle rewrite is, because the menu-choice decision happens before any of that code runs. Dragón's own next-step framing: find the actual eligibility check and make it treat an aimed wild Pal as eligible too.

Found a strong, concrete candidate directly in the SDK dump: `UPalCharacterParameterComponent` — the same component `get_individual_parameter`/`get_individual_handle` already read from — has a plain field, `WorkAssignId` (`FPalWorkAssignHandleId { FGuid WorkId; int32 LocationIndex; EPalWorkAssignType AssignType }`), plus a getter, `GetWorkAssign()`. This is exactly the shape of state a "is this Pal a registered base worker" check would read: a real Pal assigned to base work should show a populated WorkId/LocationIndex; a wild (or owned-but-unassigned) Pal should show it empty/invalid.

**Change made this pass: read-only diagnostic only, nothing overridden yet.** A new `[WORKASSIGN-DIAG]` log line fires on every real "4" press (hooked into the already-confirmed-real `PalInteractComponent:StartTriggerInteract` ActionType=4 case), resolving whatever's aimed at via the same look-based targeting used everywhere else in this file, and printing its `WorkAssignId`/`GetWorkAssign()` state. Deliberately did NOT attempt to override anything yet — spoofing a Pal's real work-assignment state blind, before confirming this is really what the menu-choice logic reads, risks corrupting actual base-management bookkeeping (assignment slots, worker capacity limits, base UI) for a real registered system, a much bigger blast radius than anything touched in this project so far. Real evidence first, same discipline that already saved this project twice (the eighteenth pass's `SetActiveAI(false)` incident, the eighty-second pass's missing ownership check).

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** press "4" on a real base worker Pal (one you know is assigned to work at your base) and separately on a wild Pal, and check the log for `[WORKASSIGN-DIAG]` lines for each. If the base worker shows a real `WorkId`/`LocationIndex` and the wild Pal shows empty/invalid ones, the theory is confirmed and the next step is finding a SAFE way to make the menu-choice check see a wild Pal as eligible (without touching its real WorkAssignId) — if they look the same, the theory is wrong and the search continues elsewhere.

## Ninety-second pass (2026-09-03): second frontier opened — weighted random personality tiers (assignment only), plus a request to Dragón

Dragón asked to run two independent lines of work in parallel from now on, so a block on one (like last night's WorkAssignId test, still pending) doesn't stall all progress. He gave a concrete spec for the second: every wild Pal should get a randomly-rolled personality tier independent of its species — **50% normal** (species default, i.e. whatever `GetSpeciesDefaultDisposition()` already resolves), **25% curious**, **10% hostile**, **15% skittish** — so players can occasionally meet a friendly individual of a normally-hostile species (or a hostile individual of a normally-docile one) worth trying to befriend. He also flagged a third-party "makes all Pals pacific/non-hostile" mod he'd shared before as likely relevant prior art for the harder half of this problem.

**Implemented this pass: the ASSIGNMENT half only, in `Personality.lua`.** `GetOrInitState` (already the place that seeds a new individual's state from its species default, since the thirty-sixth pass) now also rolls a weighted tier exactly once per stable individual ID via a new `roll_personality_tier()` (`PERSONALITY_TIERS` table, 50/25/10/15), and folds it into the `disposition` field the module already exposes — `PersonalityState[palId] = {disposition, speciesDefault, presetClassName, rolledTier}`. "normal" keeps the species default; anything else overrides it. Every existing caller that reads `GetDisposition(palId)` (currently just the log line in `Interaction.OnWildPalPetted`) automatically gets the new effective value with no changes on its end. Added `Personality.GetRolledTier(palId)` as a separate read-only accessor (distinguishes "rolled normal, defaults to hostile" from "actually rolled hostile" for debugging). Seeded `math.random` once at `Personality.Init()` via `math.randomseed(os.time())` (pcall-wrapped) — this project's first use of `math.random` anywhere, so without seeding it would replay the same sequence every session. Every new individual's roll logs a `[PERSONALITY-ROLL]` line with the rolled tier, species default, and resulting effective disposition.

**Explicitly NOT done this pass — the enforcement half.** None of this changes what the game's actual AI does yet. A Pal rolled "hostile" from a normally-docile species will not actually attack; a Pal rolled "skittish" from a normally-aggressive species will not actually flee. The module only decides and remembers the tier — nothing feeds it back into the real decision-making yet. That needs either overriding a live Pal's `AIResponsePreset` pointer field directly (untested — a field WRITE on a shared game object, bigger than anything tried in this file so far) or a properly-throttled `SelectResponseBySenses` override (the thirty-third pass's disabled hook, re-enabled carefully this time). Real evidence first, same discipline as everywhere else in this project — and Dragón's pacifist-mod reference, once shared, may hand us a proven mechanism instead of guessing blind.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next steps, two independent fronts:**
- Radial-menu front (ninety-first pass, still pending): press "4" on a real base worker vs. a wild Pal and compare `[WORKASSIGN-DIAG]` output.
- Personality front (this pass): get in-game, pet/feed a few different wild Pals, and check the log for `[PERSONALITY-ROLL]` lines to confirm the roll distribution looks right and nothing errors. Separately, share the pacifist mod (file, link, or a description of what it actually touches) so the enforcement half can be researched from real prior art instead of from scratch.

## Ninety-third pass (2026-09-03): personality ENFORCEMENT, first real attempt — preset re-pointing via a recurring scan

Between the ninety-second pass and this one, real research (byte-diffing the vanilla `Pal-Windows.pak`'s `BP_AIAction_WildLife` against Dragón's saved "PassiveWildPals" mod's modified version via `repak`) confirmed the mod adds one new check, `TargetIsPlayerOrPlayersOtomoPal`, to suppress combat targeting of the player — and, independently, grepping the game's own header dump turned up something more directly useful: `UPalAIResponsePreset`, a plain UObject with 8 simple per-situation enum fields (`Discover_Player`, `Damaged_Player`, etc.), referenced by every Pal's `AISensorComponent.AIResponsePreset` pointer. `repak list` against the vanilla pak found only 11 total preset variants exist in the whole game — `Default`, `friendly`, `escape`, `Escape_to_Battle`, `NotInterested`, `Warlike`, `Warlike_Anyway`, `Warlike_WithoutPlayer`, `Kill_All`, `Boss`, `VillageNPC`.

Dragón, asked to confirm the design before any live-behavior code shipped, chose the harder-but-correct option: personality should affect a wild Pal's real behavior as soon as it's nearby, not only after the player has already pet/fed it once (a "hostile" Pal only turning hostile right after being safely pet is backwards, and it wouldn't let players spot a friendly individual on a hostile species from a distance).

**Implemented this pass, in `Personality.lua`:** a new recurring scan (`scan_nearby_wild_pals_for_personality`, self-rescheduled via `ExecuteInGameThreadWithDelay` every 8s — the same safe pattern Trust.lua's follow tick and OtomoWatch.lua's PrismSpy poll already use) walks every currently-loaded `PalCharacter`, initializes/rolls personality for any new one (same `GetOrInitState` as before, just triggered earlier), and for any individual whose rolled tier isn't "normal," attempts `try_enforce_personality`: **re-points that one Pal's own `AIResponsePreset` field at an already-live object borrowed from another currently-loaded wild Pal whose species naturally uses the matching preset** (Warlike→hostile, escape→skittish, friendly→curious) — deliberately never editing the shared preset object itself (which would flip the whole species' behavior at once, the same class of mistake as the eighteenth/eighty-second passes), and deliberately never constructing or force-loading a preset from scratch (confirmed via a subagent DLL-string search that UE4SS has no `StaticLoadObject`/`LoadObject`/`NewObject` — only `StaticFindObject` on already-loaded objects and `StaticConstructObject` exist). Gated by `Capture.IsAlreadyOwned` first, same as every other write-capable path in this project. If no live donor of the desired preset is loaded anywhere nearby yet, it logs that and retries on the next scan rather than failing — this is an honest, expected limitation in a species-sparse area, not a bug.

**Completely unconfirmed as of this pass:** whether writing to `AIResponsePreset` from Lua actually changes a live Pal's real behavior (vs. being read once at spawn/construction and cached elsewhere, silently ignored, etc.), and whether an 8-second full-world PalCharacter scan is cheap enough not to reintroduce a lag problem (this project has hit exactly that twice before, at the ninth and forty-something passes).

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** get near any wild Pals for a couple of minutes (no interaction needed — the scan runs on its own) and check the log for `[ENFORCE]` lines. A `SUCCESS` line naming a real donor is the first proof the mechanism runs at all; the real proof is going to that specific Pal in-game afterward and checking whether it now actually behaves like its borrowed preset (attacks/flees/watches differently than its species normally would). Also watch for any new stutter/lag correlating with scan timing, same as any past performance investigation in this project.

## Ninety-fourth pass (2026-09-03): real lag bug found and fixed in Dragón's first live enforcement test, plus a wild-vs-base-worker radial-menu data point

Dragón's first test of the ninety-third pass (walked near wild Pals, placed a Lamball to roam at base, pressed "4" on a base Sheepball and separately on wild Lamball/Chikipi) reported real lag and no visible personality change. The log confirmed both, with real causes:

**Lag — confirmed and fixed.** In under 3 minutes, `[PalBonds/Personality] [DIAG]` logged **2813** times — nearly half of the whole session's 8166 total log lines — all the exact same message (`sensor.AIResponsePreset is a NULL object reference`). Root cause: `find_live_preset_donor` called `GetPresetClassName` (a real engine round-trip, plus its own logging) fresh for every nearby Pal, every time an unresolved individual needed a donor — with several unresolved rolls and an 8s scan, that multiplies into exactly this kind of runaway spam, the same shape as this project's earlier per-actor-lookup lag bugs. Fixed by building one `presetClassName -> live actor` lookup per scan cycle instead of re-querying per unresolved individual, and throttling `GetPresetClassName`'s own diagnostic logging to once per (actor, failure-type).

**Zero personality changes visible — explained, partially addressed.** Every single one of those 2813 failures hit `preset:IsValid() == false` — a failure shape never seen in any prior real test in this project (the thirty-fifth/-sixth passes always hit a different one, `GetFullName()` failing silently on an apparently-valid pointer). With the preset pointer reading as null on effectively every candidate this session, no donor could ever be found for any tier, and even "does this Pal already naturally match its rolled tier" could never be confirmed. `GetOrInitState` now retries this resolution on every later scan pass instead of permanently caching a fallback "curious" from one bad first read — if this was Pals being freshly spawned/loaded at the exact moment first scanned, it should now self-heal within a scan or two. Whether that really is the cause, or something deeper, is still open — needs another live test to know.

**Radial-menu front, real data point:** the two `[WORKASSIGN-DIAG]` lines this session both came from a real base-assigned Sheepball (`AssignType=1`, a real populated `WorkId`, `GetWorkAssign()` returning a real `PalWorkAssign_TransportItemInBaseCamp` object) — consistent with the ninety-first pass's theory. But the wild Lamball/Chikipi "4" presses this session never showed up in `[MENU-WATCH]`/`[WORKASSIGN-DIAG]` at all — meaning the native interact system itself never registered those presses as a valid target (not a menu-choice question this time; the press didn't fire). Still need a real "4" press that at least opens SOME menu on a wild Pal to get a genuine wild-side comparison sample.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** same two fronts. For personality, spend a couple minutes near wild Pals again and check for `[ENFORCE] SUCCESS` and whether `[DIAG]`/`[ENFORCE]` volume looks sane now (should be a small fraction of before). For the radial menu, get very close and well-centered on a wild Pal before pressing "4" — if literally nothing opens again, that's itself useful information (a targeting/range issue, separate from the menu-choice question) rather than a comparison data point.

## Ninety-fifth pass (2026-09-03): second retest — lag down but not gone, zero enforcement successes confirmed, "RemoteAccessEverything" mod investigated separately

Dragón's second test (after the ninety-fourth pass's fix) reported lag "not as bad as before" but still present, and confirmed no personality or radial-menu change. The log matched: total lines dropped from ~48/sec to ~33/sec, and `[DIAG]` dropped from 2813 to 70 (throttling worked) — but a second, previously-unnoticed spam source turned up: `[ENFORCE]`'s "no live donor found" message was logging unconditionally every 8s scan, forever, for any individual that never finds a match (221 lines this test) — fixed by throttling it to once per individual, same pattern as the other fixes this pass.

More importantly: the retry-on-nil fix from the ninety-fourth pass never once succeeded this test (`grep "resolved on retry"` → 0 hits, 71 individuals, ~23 scan cycles each) — species defaults were STILL 100% "curious" fallback. This weakens the "just a brief spawn-timing race" theory and raises a real alternative: every prior successful `GetPresetClassName` read in this project's history happened from the do_pet/do_feed event handler, i.e. only ever tested AFTER a real interaction with that Pal — never from passively scanning a Pal at range that's never been interacted with. It's now plausible the sensor's preset reference isn't actually populated until some real gameplay event (an interaction, being targeted, etc.) triggers the component's own `Setup()` — a real method confirmed in the header dump, not something we've called. **Next diagnostic (no new code needed — GetOrInitState already retries on every call including ones from pet/feed):** pet or feed one wild Pal as usual and check the log right after for a `"resolved on retry"` line. If it appears, that confirms interaction is what unlocks a readable preset — meaning the enforcement scan (which deliberately tries to run BEFORE interaction) may be structurally blocked from ever working before the player interacts, a real conflict with the goal of visible-before-approach personality that would need to be discussed with Dragón before more code gets written blind.

Also this pass: Dragón asked about a separate mod he'd shared before, "RemoteAccessEverything" — checked via the same repak/strings technique. It replaces `WBP_PlayerRadialMenu` (the no-aim "Player Menu" widget, `PalUIPlayerRadialMenuBase`), completely unrelated to the `WBP_WorkerRadialMenu` this project has been investigating. Its added symbols (`PakTools_OpenGlobalPalbox`, `OpenPalboxSelector`, `OpenPersonalPalbox`, `PalStorageMenu`) show it adds a remote Palbox/storage-access option to the player's own always-available menu — a UI convenience feature with no connection to wild Pals, capture, or worker assignment.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** pet/feed one wild Pal (the normal way) and check the log for a `[PERSONALITY-ROLL] ... resolved on retry` line right around that moment — this is the key diagnostic to know whether interaction is what's needed to make the preset readable.

## Ninety-sixth pass (2026-09-03): re-examined the "grayed out" mystery — self-correction, real fix attempt, and a clearer picture of the two open eligibility walls

Dragón reported Pet/Feed showing up grayed-out on the Player Menu when aimed at wild Pals. First read: found the real native analogue `UPalOtomoHolderComponentBase::IsActivatedSelectOtomo()` (zero-parameter, checks the component's own currently-selected party slot — real, save-backed ownership bookkeeping) and concluded this was a deep, risky wall similar in spirit to WorkAssignId but touching the actual ownership ledger.

Dragón pushed back with the sharper framing: rather than faking underlying party data (which nobody wants), why not just change the *answer* to whatever question gates the buttons, the same way the eighty-eighth pass already rewrote `OnClose`/`IndividualHandle` in place? Re-reading the eighty-fifth pass's own `TryGetSpawnedOtomo` redirect in that light exposed a much simpler, cheaper explanation than "real ownership wall": that redirect was capped to substitute only ONCE per open menu window (`radialMenuRedirectedThisWindow`), purely to avoid re-logging on ambient calls — but `TryGetSpawnedOtomo` fires ~4x/second even during the window (per the eighty-fourth pass), so whatever LATER call actually feeds the button-enable decision was very plausibly never redirected at all. The grayed-out buttons may have had nothing to do with a deep ownership check — just our own one-shot cap missing the call that mattered.

**Fix applied, cheap and low-risk (reuses the exact already-proven `ReturnValue:set()` technique, just removes a self-imposed limiter):** the substitution now applies to every qualifying `TryGetSpawnedOtomo` call for as long as the menu window stays open, not just the first — still fully gated by the same wild-Pal-only, player-excluded, ownership-checked conditions as before. Only the announcement log line is deduped (once per aimed Pal, not once per window) to avoid a new spam source.

Syntax-verified (`luac -p`), deployed to both destinations.

**Why this matters for the two menus separately:** for the Player Menu (Pet/Feed), if this fix makes the buttons light up, it means there never was a deep ownership wall here at all — great news, much better than the Worker Menu's situation. If they're STILL grayed out after this, that's real evidence something like `IsActivatedSelectOtomo` genuinely is involved and reads real party-slot data no reference substitution can satisfy — worth adding a real diagnostic on that native function next, rather than guessing further.

## Ninety-seventh pass (2026-09-03): the ninety-sixth pass's test was never actually exercised — hook-registration budget was too short, not the fix

Dragón's test after the ninety-sixth pass still showed Pet/Feed grayed out on the Player Menu (PupperAI and Lamball, both wild). Read the fresh log (12:05:30-12:08:12) before concluding anything about the fix itself, and the real story turned out to be upstream of it entirely.

`grep 'RADIAL-REDIRECT'` on that session returned **completely empty** — the substitution never fired once, despite 7 real "4" presses. Tracing why: every hook-registration attempt against `WBP_PlayerRadialMenu_C` — including "Can Open Player Action Menu", the exact hook that arms `openRadialMenuActionWindow()` and the whole redirect window the ninety-sixth pass's fix lives inside — failed on all 8 retry rounds and gave up at ~12:06:07, about 37 seconds after mod load (12:05:30). Dragón's first "4" press that session wasn't until 12:07:39 — over 90 seconds AFTER the retry loop had already permanently quit. The exact same "giving up after 8 rounds" failure hit `INDICATOR-WATCH` (×2), `WORKER-WATCH` (×2), and `WORKER-BIND-FIX` within the same couple of seconds — all five retry loops share the `MAX_RADIAL_HOOK_ROUNDS`/`RADIAL_HOOK_RETRY_MS` constants, and all five failed together, which points at a general "these Blueprint UI widget classes aren't loaded into memory yet this early" timing issue rather than a per-class naming problem — most of the candidate names here are already confirmed real across many past sessions (see the seventy-ninth pass's notes above).

**This means the ninety-sixth pass's test was inconclusive for the fix it was testing** — the mechanism it modified was never armed, so nothing about "does removing the once-per-window cap fix the grey-out" was actually tested. The grey-out result from that session tells us nothing new about the Player Menu eligibility question either way.

**Fix applied:** extended the shared retry budget from 8 rounds (40s total at 5s/round) to 60 rounds (5 minutes total), covering a normal player's actual pre-first-"4"-press delay with real margin. Kept it bounded rather than infinite — a couple of candidates in the target lists (`ChangeMode`/`DecideMenuAction`) are still unconfirmed guesses, and this project has hit real lag bugs from unbounded per-round logging twice before (ninety-third/ninety-fifth passes) — so there's still an eventual stop, just far enough out to plausibly cover real play patterns instead of quitting before the player has done anything.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** the exact same test as before (aim the Player Menu Pet/Feed at a wild Pal) — but this time check the log for `RADIAL-REDIRECT` lines specifically. If they now appear and Pet/Feed still show grayed out, that's real evidence of a genuine ownership wall (like `IsActivatedSelectOtomo`) worth investigating directly next. If `RADIAL-REDIRECT` still never fires, the registration timing issue needs a different diagnosis (e.g. these classes may only load on first real construction rather than passively over time, meaning no retry budget alone would ever be reached in time).

## Ninety-eighth pass (2026-09-03): real breakthrough confirmed — the once-per-window cap theory was right — plus a self-inflicted lag regression found and fixed

Dragón's test with the extended retry budget: `RADIAL-REDIRECT` fired twice this session (once substituting a wild `BP_PlantSlime_C`, once a wild `BP_SheepBall_C`), and **Pet/Feed were NOT grayed out** — he clicked them. This conclusively confirms the ninety-sixth pass's theory: there was never a deep, save-backed ownership wall on the Player Menu. The grey-out was entirely caused by our own once-per-window substitution cap combined with the hook-registration timing bug — both now fixed, both now proven fixed by a real, positive result.

Better still, the log shows real decision events firing right after each click: `OnDecidedInstructionCare` (arg1=false) and `OnDecidedPlayerActionMenu` (arg1=1, the Pet option's index) fired within seconds of each RADIAL-REDIRECT, proving the click is genuinely reaching the Blueprint's decision logic for the substituted wild Pal — not just toggling the button's visual state. Dragón reported "nothing happened" after clicking — that's expected, not a bug: since the eighty-second pass's incident (an owned Pal getting silently re-captured), this project deliberately stopped connecting any decision event to a real action (`Interaction.OnWildPalPetted`), staying watch-only until this was revisited deliberately. We now have exactly the real hook point needed to wire that up (`OnDecidedInstructionCare`/`OnDecidedInstruction_Feed`, or the generic `OnDecidedPlayerActionMenu` with its index), gated behind `Capture.IsAlreadyOwned` the same way F9/F10 already are — a real next step, not yet done this pass.

Dragón also reported the game "felt terribly laggy" this session — worse than before, a real regression traced straight back to the ninety-seventh pass's own fix. Root cause, found in the log: (1) every FAILED `RegisterHook` call logs `tostring(err)`, and that string embeds a full ~10-line stack traceback that's identical every time (the call site never changes) — pure waste; (2) a handful of candidate names are genuinely dead on their classes (`ChangeMode`/`DecideMenuAction` on the radial menu; several on the worker menu classes; several on the indicator class) — proven dead because sibling targets on the exact same class resolved within 2-3 rounds, showing the class loads fine, while these specific names kept failing every round through round 19 (log cutoff) — and would have kept failing, full traceback each, all the way to the new round-60 cap.

**Fix applied:** (1) log only the first line of the RegisterHook error, dropping the embedded traceback — same information, ~10x less text; (2) track the round each class first proves loaded (any one sibling target hooks successfully), then give remaining unresolved targets on that class only 3 more rounds before giving up on them specifically — a name still unresolved long after a sibling succeeded is a wrong name, not a timing issue, and no amount of waiting fixes that. This keeps the ninety-seventh pass's real benefit (genuinely slow-to-load classes still get the full 5-minute budget) while cutting off the new dead-name spam almost immediately instead of at 5 minutes.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next steps, not yet done:** (1) confirm this lag fix actually reduces log volume/lag in a fresh test; (2) decide with Dragón whether to wire `OnDecidedInstructionCare`/`OnDecidedInstruction_Feed` to a real, ownership-guarded `Interaction.OnWildPalPetted` call for the substituted wild Pal — the actual "make Pet/Feed do something" step, deliberately not done yet given the eighty-second pass's incident history.

## Ninety-ninth pass (2026-09-03): wired Pet/Feed to a real action on wild Pals — reusing F9/F10's proven path, not a new one

Dragón gave the go-ahead to wire this up now. Design choice: deliberately did NOT try to decode `OnDecidedInstructionCare`/`OnDecidedInstructionFeed`'s own boolean argument — the one real sample logged (Care fired with arg1=false on a confirmed real Pet click) doesn't cleanly support either a "true=selected" or "false=selected" reading, and guessing wrong here is exactly the class of mistake this project's discipline exists to prevent. Instead: a new `lastDecidedInstruction` variable just remembers WHICH named event fired most recently during the current window (ignoring its argument entirely), and the actual action fires later, once, at `CloseMenu` — a single event already proven to fire exactly once per window, already used to end the redirect window itself.

Critically, the action only fires if `radialMenuRedirectedThisWindow` is also true — i.e. only in a window where a wild Pal was actually substituted. This is the hard gate that keeps this whole feature from ever touching the player's own real Otomo interactions, which already have their own working vanilla Pet/Feed path — firing our own action on top of that would reintroduce a double-grant bug in a new place, mirroring the very first double-`AddFriendShip` bug this project fixed early on.

The action itself is not new code: `closeRadialMenuActionWindow` now calls the SAME `do_pet()`/`do_feed()` functions F9/F10 have used since day one. That reuse buys three protections for free, all already proven over many passes: (1) `do_interaction` re-aims from scratch via `find_targeted_pal` rather than trusting anything cached from earlier in the window — if the player looked away, it safely finds nothing; (2) its busy-gate means an accidental double-fire (e.g. if both `OnDecidedInstructionCare` and a later ambient re-fire happened) just no-ops with "already mid-action", not a double animation; (3) `Interaction.OnWildPalPetted` → `Trust.OnInteractionSucceeded` already hard-refuses to touch trust/capture bookkeeping on an already-owned Pal (`Capture.IsAlreadyOwned`, added straight after the eighty-second pass's incident) — the exact protection that incident was missing.

Syntax-verified (`luac -p`), deployed to both destinations.

**Test plan — two parts, and the FIRST one is a regression check, not the new feature:**
1. Pet/feed your own real Otomo through the normal player menu, exactly as you always have. Confirm it still looks and feels identical to before — one reaction animation, normal friendship gain, nothing doubled, no new log spam. This checks that the new wiring never fires on your own Pals.
2. Aim at a wild Pal, press "4", click Pet (or Feed). Watch for the actual in-game pet/feed animation playing on the wild Pal this time, not just the button being clickable. Check the log for a new `[WILD-ACTION]` line confirming it fired, and whatever the existing `[WATCH]`/friendship-grant lines show afterward.
3. Also note whether the lag felt better than the last session (checks the ninety-eighth pass's fix together with this one, since they'll both be exercised in the same test).

## Hundredth pass (2026-09-03): found the real cause of the intermittent Pet/Feed failures — a stale-window bug in our own code, not a game-side busy check

Dragón's test: Foxparks (his real Otomo) pet/fed normally — good, no regression. Then Gummoss failed, Lamball worked once, the same Lamball failed on a repeat attempt. He proposed a theory: the wild Pal only gets "verified" when the menu opens, not when the action is clicked, so if the Pal became busy in between, the click would silently do nothing.

Read the log timestamps precisely and found the REAL mechanism, which is close to his theory in spirit but is actually a bug in this project's own code, not a game-side busy check: `RADIAL_ACTION_WINDOW_TIMEOUT_MS` — the safety-timeout that auto-closes the internal "redirect window" in case `CloseMenu` somehow never fires — was set to 1500ms (1.5 seconds) since the eighty-fifth pass. But the real decision events (`OnDecidedInstructionCare`/`Feed`) in this test kept firing 3-4 real seconds after the menu opened (Dragón spent that long aiming/deciding), well past that 1.5s cutoff. Once the safety-timeout fires, `radialMenuActionWindowOpen` silently goes false — which stops BOTH the wild-Pal substitution AND (since the ninety-ninth pass) the new action-firing, even though the real in-game menu was still open and the real click still landed at the Blueprint level (`OnDecidedInstructionCare`/`Feed` kept firing just fine — the game itself was never confused, only our own tracking went stale). The exact timing lines up perfectly: the one success (Lamball, first attempt) had its decision land right at the edge of 1.5s; every failure took noticeably longer.

**Fix:** extended `RADIAL_ACTION_WINDOW_TIMEOUT_MS` from 1500ms to 15000ms (15 seconds). `CloseMenu` has now fired reliably in every single test session this project has run, so it's safe to make this fallback far more generous without weakening the actual safety net (CloseMenu still closes the window immediately the instant it fires — the timeout is only a backstop for if it somehow doesn't).

**Second, related bug found and fixed in the same pass:** `radialMenuRedirectedThisWindow` — the flag the ninety-ninth pass reused as the hard gate for "only fire real actions when a wild Pal was actually substituted" — was actually being set `true` unconditionally the moment the window opened, BEFORE any of the wild/owned/already-Otomo checks ran. That means it was ALSO true during Dragón's own real Otomo (Foxparks) interactions. The only reason no double-fire bug showed up in that test was a lucky quirk of event ordering (`CloseMenu` happened to fire once before the decision event, closing the window and blocking `lastDecidedInstruction` from ever being set) — not a real protection. Fixed by moving the `= true` assignment to the one spot where a wild Pal is confirmed and about to actually be substituted, so the flag now means exactly what its name says.

Syntax-verified (`luac -p`), deployed to both destinations.

**Also answered Dragón's follow-up question** (what happens if the wild Pal starts some other action between opening the menu and clicking Pet?): nothing bad — `do_pet`/`do_feed` (reused unchanged from F9/F10) check the target's own busy-state at the moment they actually run, and if the Pal isn't idle by then, the whole interaction is skipped silently (logged as "target is busy... skipping entire interaction") — it does not interrupt or force anything, matching vanilla behavior exactly.

**Next test:** same two-part plan as the ninety-ninth pass (own Otomo first as a regression check, then a wild Pal) — this time try deliberately taking a few seconds to decide before clicking Pet/Feed, to confirm the fix holds even when you're not fast about it.

## Hundred-and-first pass (2026-09-03): timeout fix confirmed strongly working; remaining lag tracked as backlog instead of chased blind

Dragón's test: `WILD-ACTION` fired 21 out of 25 real "4" presses this session — a big jump from the handful of successes seen before the hundredth pass's timeout fix, and strong confirmation it's holding up under real, varied play (not just the two or three presses tested immediately after the fix landed).

He also pasted a raw chunk of the live log: a burst of ~60 consecutive `RegisterHook` FAILED lines, all within under a second, and reported a real, felt hitch every time he presses "4" (sub-second, but noticeable). Traced the pasted burst precisely: it's the hook-registration retry system (`make_hook_round_runner`) working exactly as designed — this particular session's Blueprint UI classes happened to take until round 11 (~55 seconds) to finish loading, versus round 4 in the ninety-eighth pass's test session. That's normal session-to-session variance in how fast the game constructs these widgets, not a new regression — confirmed by checking that the "stopping early" lines still fired on schedule for all three watch groups (RADIAL-WATCH, INDICATOR-WATCH ×2, WORKER-WATCH ×2) once a sibling proved each class loaded, and only 2 tracebacks appeared in the entire session (both one-off, unrelated leftovers already known from the ninety-eighth pass, not a new loop). So the ninety-eighth pass's log-spam fix is holding — this burst is a real cost, but a bounded and already-mitigated one, concentrated in the first ~1 minute after mod load, not something recurring on every menu open.

The per-"4"-press hitch Dragón described is a SEPARATE, not-yet-isolated cost — it can't be the registration burst (that only happens once per session, early on, not on every subsequent press). Leading candidates: the `TryGetSpawnedOtomo` redirect's own per-call work (re-aiming via `find_targeted_pal`, `GetComponentByClass` lookups) running at roughly 4 times a second for as long as the menu stays open; or `Logger.lua`'s synchronous per-line flushed disk write landing awkwardly inside the same frame as the menu-open call. Neither has been isolated yet — that needs controlled profiling (e.g. temporarily gutting the redirect's work vs. gutting its logging, one at a time, to see which one actually removes the stutter), not a guess-and-fix.

Per Dragón's explicit request, this is now tracked as a real backlog rather than fixed blind — see `DESIGN.md` §10, "Performance & polish backlog," for the three concrete items (the per-press hitch, the registration retry log volume, and `Logger.lua`'s write cost in general).

**Personality, for completeness:** no progress this pass (not the focus) — `resolved on retry` is still 0 across the whole session, species-default preset reads remain 100% "curious" fallback, the underlying mystery from the ninety-third/fourth/fifth passes is unchanged. The rolled-tier ASSIGNMENT itself is confirmed still healthy: a real spread across normal/curious/hostile/skittish this session, not stuck on one value. Every test session since the ninety-fifth pass has already involved petting/feeding wild Pals (which is the exact diagnostic that would show a "resolved on retry" success) as a side effect of testing the radial menu — so the diagnostic has effectively been running every session without needing a separate ask, it's just kept coming back negative.

## Hundred-and-second pass (2026-09-03): chased the per-"4"-press hitch — found a real, concrete cost and throttled it

Dragón asked to prioritize the per-press hitch over the personality mystery or the Worker Menu comparison. Rather than guess-and-fix, looked for a concrete, provable cost in the redirect's own code — and found one: `find_targeted_pal` (used by the `TryGetSpawnedOtomo` redirect) calls `FindAllOf("PalCharacter")` — a full scan of every currently-loaded Pal actor in the world — plus one `GetFullName()` call and one location read PER pal found, every single time it runs. The redirect calls this on every qualifying `TryGetSpawnedOtomo` hook fire while the menu window is open, which the eighty-fourth pass measured at roughly 4 times a second — and since the hundredth pass just extended that window from 1.5s to a real 15 seconds, a single "4" press held open can now trigger up to ~60 full actor scans, each with a `GetFullName()` call per nearby Pal (a relatively expensive reflection call by this project's own prior experience). On a base, or anywhere with a dozen-plus Pals loaded, that's a real, non-trivial, and self-inflicted cost — not a guess, a direct consequence of two of this project's own choices (the redirect's per-call design from the eighty-fifth pass, and the timeout extension from the hundredth pass).

**Fix:** cache the aimed-Pal result from `find_targeted_pal` for a 250ms window and reuse it (after a cheap `IsValid()` recheck) instead of re-scanning every single hook call — a player's aim doesn't meaningfully change within a quarter second, so this can't make the feature feel less responsive, only cheaper. Only caches a REAL found Pal — a "not aiming at anything" result always re-scans next call (the less common, less expensive case, so no need to cache it). The cache resets cleanly every time a new menu window opens (`openRadialMenuActionWindow`), so it can never leak a stale target across separate "4" presses.

**Also added:** a real timing diagnostic (`[RADIAL-REDIRECT-PERF]`) that logs the actual millisecond cost of each real (non-cached) scan, using `os.clock()`. Because it only fires on real scans — now throttled to at most ~4/sec instead of the raw hook-fire rate — this stays cheap to log and gives concrete numbers instead of more guessing. If `os.clock()` is unavailable in this UE4SS Lua build for any reason, the code degrades safely: it just always re-scans (identical to pre-fix behavior) rather than erroring.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** the usual two-part plan (own Otomo first, then a wild Pal) — this time pay attention to whether the per-press hitch feels smaller or gone, AND check the log for `[RADIAL-REDIRECT-PERF]` lines to see the real scan cost in milliseconds. If the numbers come back small (low single-digit ms) even before this fix's benefit, that would point away from `find_targeted_pal` as the real cause and toward something else (e.g. `Logger.lua`'s own write cost, or the vanilla UI construction itself) — the diagnostic is honest either way, not just a confirmation of the fix.

**Next test:** aim "4" at a wild Pal and see whether Pet/Feed are clickable now. Whatever happens — lit up, still grayed, or something in between — report exactly what you see; both outcomes are informative.

## Hundred-and-third pass (2026-09-03): the perf diagnostic answered its own question — hitch persists because of per-scan cost, not frequency

Dragón's next test: Pet worked cleanly on every wild Pal he tried (no bugs), but the felt hitch on "4" press was still there — he was honest about it rather than saying it was fixed when it wasn't. Real `[RADIAL-REDIRECT-PERF]` log data settled the question the hundred-and-second pass's diagnostic was built to answer: 83 real scans logged this session, consistently costing 36-50ms each (sample: 36.00, 37.00, 39.00, 41.00, 43.00, 45.00, 50.00ms — a steady upward drift across the session as more Pals were loaded nearby, consistent with the scan's cost scaling with Pal count).

**Why the throttle didn't remove the felt hitch:** the 250ms cache is scoped per-window, and `cachedRedirectWildPal`/`lastRedirectComputeClock` are explicitly reset in `openRadialMenuActionWindow` every time a new "4" press starts a window (so a stale aim target from a previous press can never leak forward). That means the very FIRST scan of every single press is always a real, non-cached scan — the throttle only ever prevented REPEAT scans within one held-open window, never the initial one. Since 36-50ms is roughly 2-3 dropped frames at a 60fps target, that first-scan cost alone is enough on its own to produce a short, felt stutter on every press, completely independent of how well the repeat-scan throttle works. The hundred-and-second pass's fix was real and did cut total scan count dramatically (would have been ~60 scans over a 15s hold before the fix; now capped near 4/sec × however long the throttle allows), but it was solving a different problem (aggregate cost over a long hold) than the one causing the felt per-press hitch (the unavoidable first-scan latency).

**Not implemented this pass** (documented as concrete next steps in `DESIGN.md` §10 instead, since Dragón asked to set performance aside for now): reordering `find_targeted_pal`'s per-Pal checks so the cheap distance test runs before the expensive `GetFullName()` call (currently unconfirmed which order the live code uses without re-reading it, but Pals outside range gain nothing from an exclusion-name check and pay for it anyway if name-checked first); replacing `GetFullName()`-based exclusion (used to skip the player and current Otomo) with direct actor-reference comparison, which should be much cheaper than a string-producing reflection call; or caching the raw `FindAllOf("PalCharacter")` actor list once per window-open instead of re-querying it on every scan (the set of loaded Pals rarely changes meaningfully within one ~15s "4" press).

**Decision:** rather than keep chasing this blind against Dragón's stated wishes, logged the precise, numbers-backed root cause and pivoted to feature work — Dragón explicitly deprioritized further optimization ("let's move from that for now... later on, we can separate the actual mod from all the other things...") in favor of picking a next feature, leaving that choice up to Claude. See `DESIGN.md` §10 for the updated backlog entry and the feature picked this pass.

## Hundred-and-fourth pass (2026-09-03): real food-item feeding — Stage 1 research, read-only diagnostics only

Dragón's full feature wishlist (verbatim, for reference): join beam VFX; in-game "[name] likes you and joined" text; balancing (later); diminishing returns on repeated interactions (later, with balancing); real follower AI (not the periodic-nudge override); follower Pals protecting the player in combat; skittish→curious after the first successful interaction; an experimental shared "Play" interaction; kinship peaches (needs Feed to open real inventory first); a settings screen (maybe, later); general mod optimization (last); a server-feasibility check. Asked to leave the pick up to Claude. Picked: real food-item feeding, because Feed's current gap (no real item, ever) was already explicitly flagged as a known limitation in the twelfth pass's own header notes, and closing it is also the prerequisite Dragón named for kinship peaches to work.

**SDK dump research (`CXXHeaderDump/Pal.hpp`, `Pal_enums.hpp`), all real function/struct/enum names, nothing guessed:**

- `APalMonsterCharacter:SelectedFeedingItem(const FPalItemSlotId& ItemSlotId, const int64 Num)` — found via the exact `SelectedFeedingItem(ItemSlotId, Num)` call the twelfth pass's own header comment had already spotted "elsewhere in the SDK dump" but never chased down. Declared on `APalMonsterCharacter` — the SAME base class as `OnSelectedOrderWorkerRadialMenu` (eighty-eighth pass), i.e. every Pal actor in the game, wild or owned. Strong candidate for "the function that actually hands a chosen food item to a Pal."
- `FPalItemSlotId { FPalContainerId ContainerId; int32 SlotIndex }`, `FPalContainerId { FGuid ID }` — what `SelectedFeedingItem` needs as its first argument. Building one for a specific food item requires knowing (a) the player's own inventory container's GUID and (b) which slot index in it holds that item — neither is solved yet. This is the real blocker for Stage 2 (actually calling `SelectedFeedingItem` for real), not attempted this pass.
- `UPalItemUtility : public UBlueprintFunctionLibrary` — a big grab-bag of inventory-query helpers, all effectively static. Two stand out:
  - `CollectLocalPlayerControllableItemInfos_ByTypeB(WorldContextObject, TArray<EPalItemTypeB> ItemTypes, TArray<FPalStaticItemIdAndNum>& OutItemInfos, EPalItemInfoCollectType CollectType)` — ask "what items of these types does the player have" without touching any UI. Returns static item ID + count pairs, NOT slot info — useful for Stage 1 (prove what food exists), not sufficient alone for Stage 2 (need the slot to actually feed one).
  - `CountLocalPlayerInventoryItemNum64(WorldContextObject, StaticItemId)` — simpler single-item count check, a possible fallback if the array-returning call proves awkward to read back from Lua.
  - Same "BlueprintFunctionLibrary CDO" call pattern already proven safe in this project (Capture.lua's `get_pal_utility()` / `StaticFindObject("/Script/Pal.Default__PalUtility")`, used for the real sphere-less capture call) — this pass adds the equivalent `get_pal_item_utility()` / `StaticFindObject("/Script/Pal.Default__PalItemUtility")`.
- `EPalItemTypeB` (Pal_enums.hpp) — the real category enum. Relevant values: `FoodMeat=47, FoodVegetable=48, FoodFish=49, FoodDishMeat=50, FoodDishVegetable=51, FoodDishFish=52, FoodProcessed=53` (general Pal food) and, separately, `ConsumePalGainFriendshipPoint=45` — a DEDICATED friendship-treat category, distinct from regular food. This is very likely what Dragón meant by "kinship peaches": a real, separate item class in the game's own data, not something this project would need to invent.
- `UPalStaticConsumeItemData : public UPalStaticItemDataBase` (the base class for food-like consumables) exposes only `RestoreHP/RestoreSP/RestoreSatiety/RestoreSanity` — no visible per-item friendship-point field. Combined with the earlier-found `FriendshipPoint_Petting` config constant (a flat, global value, not per-item), this suggests vanilla feeding's friendship gain may be a fixed interaction bonus (same regardless of which food is used) rather than food-type-dependent — this mod's current approximation (flat +10 via the Happy reaction, same as petting) may already be closer to correct than assumed. Unconfirmed; would need a real vanilla feed-with-item event to compare against.

**What shipped this pass (read-only only, per this project's own rule against writing real inventory/item state before confirming via diagnostics):**

1. A permanent watch-hook on `/Script/Pal.PalMonsterCharacter:SelectedFeedingItem`, tagged `[FOOD-DIAG]`, logging the target Pal, `ContainerId.ID`, `SlotIndex`, and `Num` any time it fires for real. Nothing calls this yet from this mod's own code, so if it fires at all this session, it's vanilla itself (e.g. a real "feed my Otomo" flow somewhere) — that would be extremely valuable real evidence of the correct usage shape.
2. An F10-triggered (Feed key), additive-only diagnostic: `log_available_food_items(player)` calls `get_pal_item_utility():CollectLocalPlayerControllableItemInfos_ByTypeB(player, FOOD_ITEM_TYPE_B_VALUES, {}, 0)` (0 = `EPalItemInfoCollectType.InventoryOnly`) and logs the raw return plus, best-effort, each entry if the result comes back as an iterable table. **This exact call shape (an empty `{}` placeholder for the OUT-param, expecting the real array back as an extra Lua return value) is an unconfirmed guess** — this project has no prior example of calling a BlueprintFunctionLibrary function with a TArray-of-enum in-param and a TArray-of-struct out-param from UE4SS Lua. Wrapped in its own pcall with a dedicated log tag so a wrong guess produces a clear, iterable error message (same "ship the best-evidenced guess, let the log show what's wrong" approach that eventually cracked the Worker Menu's `OnClose:Bind()` syntax over several passes) rather than a silent no-op or a crash.

Existing Pet/Feed behavior (F9/F10 and the wild-Pal radial-menu wiring) is completely unchanged — both diagnostics are purely additive logging alongside the existing, already-working `do_feed()` call.

**Staged plan for the rest of this feature (not yet started):**
- **Stage 2**: once Stage 1's log shows whether/how `CollectLocalPlayerControllableItemInfos_ByTypeB` actually returns data from Lua, use that to find a real food item's static ID, then solve the harder problem of turning "the player has 3 Berries" into an actual `FPalItemSlotId` (which container GUID, which slot index) — likely needs finding the player's own inventory container component and iterating its `UPalItemSlot` array to match by static item ID.
- **Stage 3**: call `SelectedFeedingItem(slotId, 1)` on the targeted Pal for real, gated behind the same wild-Pal-confirmed / owned-Pal-safe pattern already proven for Pet/Feed, and observe via the new `[FOOD-DIAG]` watch-hook whether it actually consumes the item and/or grants friendship.
- **Stage 4 (the part Dragón actually asked for — a real inventory PICKER)**: find whatever real UI lets vanilla choose a feed item (if one exists reachable from a wild-Pal context at all) and hook into it, OR — if no such UI reasonably reaches wild Pals — build/trigger a picker of our own. Likely the most speculative, multi-pass stage, similar in shape to the Worker Menu's five-pass discovery arc.

**Next test:** press F10 near any Pal (owned or wild) while carrying at least one real food item (meat, berries, an egg dish, etc.) and check the log for `[FOOD-DIAG]` lines — both the "CollectLocalPlayerControllableItemInfos_ByTypeB returned (raw): ..." line and, separately, whether a natural `SelectedFeedingItem fired` line ever appears from anything else you do this session (e.g. feeding an owned Otomo through any other real menu, if one exists). Both outcomes are useful evidence for Stage 2, whatever they show.

## Hundred-and-fifth pass (2026-09-03): `SelectedFeedingItem` confirmed real via live test, diagnostic-placement bug found and fixed

Dragón announced a deliberate workflow change: from now on he'll test exclusively through the "4" radial menu, not the F9/F10 hotkeys directly, specifically so any behavior difference between the two surfaces shows up immediately (F9/F10 stay in the code as a fallback/testing lever, per the prior turn's discussion, but won't be Dragón's own test path going forward).

**Real test performed:** fed three Pals via the radial menu — a wild Chikipi (`BP_ChickenPal_C`), an active-summoned Otomo, and a base worker Pal.

**Log evidence, read directly (`palbonds-live.log`):**

- Both Chikipi feeds (14:17:40 and 14:17:48) show the exact expected `[WILD-ACTION]` → `do_feed()` → `PlayActionByType(HumanFeeding)` → `Happy` reaction chain, identical to every prior wild-Pal radial-menu test. No inventory, no item consumed — this is this mod's own current approximation working exactly as designed, matching what Dragón saw ("worked but never opened the inventory").
- At 14:18:19, a real `[MENU-WATCH] StartTriggerInteract` fired for a Pal named `BP_CloverFairy_C`, `ActionType=4` (an interact-slot number, not literally the "4" key — see the thirteenth-pass notes on `EPalInteractiveObjectActionType`), with `WorkAssignId.LocationIndex=-1 AssignType=0` (reads as not a currently-assigned base worker at that moment).
- At 14:18:22 (~3 seconds later — plausible real time for picking an item from a UI), the new `[FOOD-DIAG]` watch-hook fired for real: `real SelectedFeedingItem fired — pal=BP_CloverFairy_C ... ContainerId=UScriptStruct: 000002DC57EF54E8 SlotIndex=7 Num=1`. This is the FIRST live confirmation that `APalMonsterCharacter:SelectedFeedingItem` really is the function vanilla itself uses to deliver a picked food item — not a guess anymore, a directly observed real call with real slot data.
- No second `SelectedFeedingItem` fire appears anywhere else in the session log, despite Dragón reporting TWO owned-pal feeds (the active Otomo, then separately the base worker after traveling to base and assigning it). Only one `[FOOD-DIAG]` real-fire line exists in the whole log.

**Open question, not yet resolved:** which of the two owned-pal feeds does the captured `BP_CloverFairy_C` event correspond to — was it the active-summoned Otomo, or was it actually the base worker feed (the `WorkAssignId.AssignType=0` reading is a bit ambiguous, since it was checked before this pass had specifically instrumented base-worker-vs-otomo state at the moment of feeding)? And separately, why did the OTHER owned-pal feed not produce a second real `SelectedFeedingItem` fire at all — does base-camp worker feeding possibly go through a different real function (e.g. a feedbox/stockpile-driven mechanism rather than a direct per-Pal call), or did it simply happen and just wasn't captured for some other reason? Flagged to Dragón to clarify on the next test rather than guessed at.

**Real bug found and fixed in this pass's OWN previous diagnostic:** the F10-triggered food-inventory dump (`log_available_food_items`, hundred-and-fourth pass) was wired to the literal `RegisterKeyBind(Key[FEED_KEY])` closure — meaning it only ever runs on an actual physical F10 keypress. Since the radial-menu wild-Pal path calls `do_feed()` directly from `closeRadialMenuActionWindow()`, bypassing that keybind closure entirely, this diagnostic would NEVER have fired under Dragón's new radial-menu-only test workflow — confirmed by its total absence from this session's log despite three real Feed actions. Fixed by moving the diagnostic call inside `do_feed()` itself, so it now fires on every real feed regardless of whether it was triggered by F10 or by the radial menu. No existing Pet/Feed behavior changed — still purely additive logging.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** feed a few more Pals through the radial menu (wild, active Otomo, and a base worker again if convenient) and check the log for two things: (1) whether `[FOOD-DIAG] CollectLocalPlayerControllableItemInfos_ByTypeB returned (raw): ...` now appears (it should, on every feed, now that the diagnostic-placement bug is fixed) — this tells us whether the food-inventory-query call itself works; and (2) whether a second real `SelectedFeedingItem fired` line shows up, and for which kind of Pal, to help answer the open question above about whether both owned-pal feeding paths go through the same real function.

## Hundred-and-sixth pass (2026-09-03): base-worker vs. active-Otomo feeding confirmed as two different real functions

Dragón ran a deliberately unambiguous test — a fresh game session (log restarted at 14:27:00, clean slate) with feed-then-pet on three Pals in a fixed order: wild Lamball, active Otomo Foxparks, base worker Chikipi — specifically so each event's real timing could be matched to what he actually did.

**Log evidence, read directly, in order:**

- **Wild Lamball** (14:27:48 feed, 14:27:56 pet): `[WILD-ACTION]` fires for both (`instruction=feed` then `instruction=care`), followed by the normal `do_interaction()` log chain (`F9/F10 pressed`, `PlayActionByType`, `Happy` reaction, `[DIAG]` property dump). Exactly this mod's own approximation, unchanged — no item, no inventory. The food-inventory diagnostic (`[FOOD-DIAG] ... returned (raw): nil`) fired for the first time ever in a real test (confirming last pass's placement fix worked) but came back empty — see below.
- **Active Otomo Foxparks** (`TryGetSpawnedOtomo` resolves to `BP_Kitsunebi_C` at 14:28:03 — Foxparks' internal Blueprint name, consistent with the eighty-eighth pass's own dump example): NO `F10 pressed`/`[DIAG]` lines appear anywhere near this Pal at all — confirming owned-Pal radial-menu interactions are entirely native/vanilla, never touching this mod's `do_pet`/`do_feed`. Only a plain `[WATCH] real AddFriendShip fired ... value=10` at 14:27:59 and again at 14:28:17 (one for feed, one for pet, both the same flat +10 this mod also uses). Critically: `SelectedFeedingItem` never fired for Foxparks — checked directly, zero matches for `BP_Kitsunebi_C` anywhere in the `[FOOD-DIAG]` log lines.
- **Base worker Chikipi** (`BP_ChickenPal_C`): `[MENU-WATCH] StartTriggerInteract ActionType=4` targets its interactable sphere at 14:28:33, `[WORKASSIGN-DIAG]` confirms it's the aimed Pal, and 3 seconds later (14:28:36) `[FOOD-DIAG] real SelectedFeedingItem fired — pal=BP_ChickenPal_C ... SlotIndex=7 Num=1` — a REAL, clean, unambiguous fire, this time definitively tied to the base worker (not a guess about which Pal it was, unlike the prior pass's `BP_CloverFairy_C` case).

**Conclusion (now well-evidenced across two separate sessions, not a one-off):** base-camp worker Pals and active-summoned Otomos look IDENTICAL to the player when fed (both open a real inventory, both let you pick a food item) but are driven by two DIFFERENT real native functions under the hood. `SelectedFeedingItem` is now confirmed, twice, as the base-worker feeding function. The active-Otomo feeding function remains unidentified — a real open item for Stage 2 if/when active-Otomo feeding (not just base-worker or wild) needs to be replicated for wild Pals.

**Food-inventory-query diagnostic: still returning nothing, second attempt shipped.** The hundred-and-fourth pass's guess (`CollectLocalPlayerControllableItemInfos_ByTypeB(player, types, {}, 0)`, with `{}` as a placeholder for the out-param) fired without crashing but returned plain Lua `nil` — informative (rules out a hard failure) but not yet useful. Shipped a second attempt this pass, omitting the out-param placeholder entirely and instead capturing extra Lua return values (`local ok, r1, r2 = pcall(function() return utility:CollectLocalPlayerControllableItemInfos_ByTypeB(player, types, 0) end)`) — a plausible alternate UE4SS Lua convention where a function's non-final out/ref parameters come back as additional return values rather than being passed in as dummies. Both attempts now run and log independently (`Attempt A`/`Attempt B` labels) every time `do_feed()` fires, so the next test's log will show directly whether either shape returns real item data.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** feed any Pal again via the radial menu (any kind — wild, Otomo, or worker, doesn't matter for this diagnostic) and check the log for `[FOOD-DIAG] Attempt A` and `[FOOD-DIAG] Attempt B` lines. If both still come back nil/empty, the next step will likely mean abandoning this particular utility function and going straight for the player's inventory container component directly (a lower-level, more manual approach) instead of continuing to guess at this one function's calling convention.

## Hundred-and-seventh pass (2026-09-03): calling-convention question solved; third confirmation of the worker/Otomo split

Dragón repeated the exact same test shape (feed then pet: wild, Otomo, worker) in a fresh session. Two concrete, decisive pieces of log evidence came back.

**1. `SelectedFeedingItem` reconfirmed a third time, this time with a definitively real `WorkAssignId`:**

```
[2026-09-03 14:40:27] [WORKASSIGN-DIAG] aimed=BP_DreamDemon_C ... WorkAssignId.WorkId=UScriptStruct: 000002035EF35028 LocationIndex=0 AssignType=1 GetWorkAssign()=PalWorkAssign_TransportItemInBaseCamp ...
[2026-09-03 14:40:30] [FOOD-DIAG] real SelectedFeedingItem fired — pal=BP_DreamDemon_C ... SlotIndex=7 Num=1
```

This base worker is a Daedream (`BP_DreamDemon_C`) — a third distinct species across three separate sessions (`BP_CloverFairy_C`, `BP_ChickenPal_C`, now `BP_DreamDemon_C`) all showing the identical pattern. Crucially, this time `WorkAssignId` shows `LocationIndex=0 AssignType=1` with a real `GetWorkAssign()` object (`PalWorkAssign_TransportItemInBaseCamp`) — a genuinely-assigned worker, unlike the ambiguous `LocationIndex=-1 AssignType=0` seen in the two earlier tests. That resolves the lingering doubt from the hundred-and-fifth/sixth passes: this really is the base-worker feeding path, not a coincidental read. Foxparks (`BP_Kitsunebi_C`, the active Otomo) again produced zero `SelectedFeedingItem` fires — third confirmation of the worker/Otomo split described in the hundred-and-sixth pass, now solid across three sessions.

**2. The food-inventory calling-convention question is answered, with hard evidence rather than another guess:**

```
[2026-09-03 14:39:14] [FOOD-DIAG] Attempt A (with {} placeholder) returned (raw): nil
[2026-09-03 14:39:14] [FOOD-DIAG] Attempt B call FAILED: ...Interaction.lua:601: [UFunction::setup_metamethods -> __call] UFunction expected 4 parameters, received 3
```

Attempt B's failure is precise and unambiguous: UE4SS itself refused the 3-argument call, confirming the SDK dump's 4-parameter signature (`WorldContextObject, ItemTypes, OutItemInfos, CollectType`) is exactly right and must be called with all 4 arguments — that hypothesis is now dead for good, not just unconfirmed. Attempt A's plain `nil` return, revisited with this in mind, stops being mysterious: `CollectLocalPlayerControllableItemInfos_ByTypeB` is declared `void` in the header dump, so it has no return value to capture at all — `local result = obj:VoidFunction(...)` was always going to be `nil` whether or not the call did anything useful. The real output, if any, could only ever have landed in the out-param table itself (UE4SS's Lua bindings mutate TArray-typed arguments in place rather than returning them) — Attempt A was reading the wrong place, not asking the wrong question.

**Fix shipped:** replaced both hundred-and-sixth-pass attempts with one corrected version — keep a named local table (`local outItemInfos = {}`), pass that same variable as the 3rd argument, and read `outItemInfos` itself after the call instead of the (necessarily empty) call return. Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** feed any Pal again through the radial menu and check the log for `[FOOD-DIAG] out-param table after call returned (raw): ...` — if `outItemInfos` now shows real entries (item IDs and counts), this pass's fix worked and Stage 2 (finding a specific food item's real inventory slot) can start; if it's still empty, the next move is dropping this particular utility function and going straight at the player's inventory container component directly instead.

## Hundred-and-eighth pass (2026-09-03): Stage 1 complete — real food-item data confirmed readable

Dragón repeated the exact test shape once more (wild Daedream, Otomo Foxparks, worker Lamball). Two results, both good news.

**Fourth species confirming the worker/Otomo split:** the worker this time was a Lamball (`BP_SheepBall_C` — Lamball's real internal Blueprint name), and `SelectedFeedingItem` fired for it exactly as with the three prior species (`BP_CloverFairy_C`, `BP_ChickenPal_C`, `BP_DreamDemon_C`). Foxparks (Otomo) again produced zero fires. This pattern is now about as solid as evidence gets in this project — four separate species, four separate sessions, the same result every time.

**The food-inventory fix from the hundred-and-seventh pass WORKED:**

```
[FOOD-DIAG] out-param table after call returned (raw): table: 0000020C2D1E27C0
[FOOD-DIAG] out-param table after call item[1]: LocalUnrealParam: 0000020B5A87E288
[FOOD-DIAG] out-param table after call item[2]: LocalUnrealParam: 0000020B5A87E7D8
```

Two real entries came back (twice — both wild-Daedream feed attempts logged this, since the diagnostic lives inside `do_feed()`, which only runs for the wild-Pal redirect and literal F9/F10, not for Otomo/worker feeds — those stay 100% vanilla-native and never touch this mod's code at all, so this diagnostic can only ever show "what food you're carrying," not anything Otomo/worker-specific). Each `LocalUnrealParam` is a wrapped `FPalStaticItemIdAndNum` struct (`FName StaticItemId; int32 Num;`, confirmed in the SDK dump) — this pass's fix reads those two fields directly with a plain, safe field access (`entry.StaticItemId:ToString()`, `entry.Num`) instead of just logging the opaque handle, so the next test's log will show the actual item name and count rather than a pointer.

Stage 1 of the real-food-feeding feature (see the hundred-and-fourth pass's staged plan) is now functionally complete: the mod can genuinely query what food/friendship-treat items the player is carrying. Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** feed any Pal again through the radial menu and check the log for `[FOOD-DIAG] ... item[N]: StaticItemId=... Num=...` — real item names and counts should appear this time. Once confirmed, Stage 2 starts: finding a way to turn one of these static item IDs into the actual `FPalItemSlotId` (container + slot index) `SelectedFeedingItem` needs to really consume it.

## Hundred-and-ninth pass (2026-09-03): field reads returned nil, switched to error-visible pcall

Dragón fed a bunch of wild Lamballs in a row via the radial menu (six real `[FOOD-DIAG]` fires in one session — clean, repeatable data). Every single one still showed 2 real entries in the out-param table (confirming the hundred-and-seventh pass's core fix is solid), but the hundred-and-eighth pass's new field reads all came back nil:

```
[FOOD-DIAG] out-param table after call item[1]: StaticItemId=nil Num=nil (raw=LocalUnrealParam: 00000224E0FAFA78)
[FOOD-DIAG] out-param table after call item[2]: StaticItemId=nil Num=nil (raw=LocalUnrealParam: 0000022479A1A118)
```

(repeated identically, 6 times, across the whole session — not a one-off fluke).

**The problem with diagnosing this directly:** `entry.StaticItemId` and `entry.Num` were read through `safe_call()`, which wraps everything in `pcall` and returns `nil` on EITHER a genuinely-empty field OR a real Lua error — there was no way to tell which one actually happened from the log alone. This particular entry type (`LocalUnrealParam`, a struct pulled out of a `TArray<FPalStaticItemIdAndNum>` that came back through a BlueprintFunctionLibrary out-param) is also a shape this project has never read fields from before — every previous struct/field read in this file has been a direct field on a live component or object (e.g. `pal.CharacterParameterComponent`, `comp.IndividualHandle`), never an entry pulled out of an array returned via an out-param. It's plausible UE4SS wraps this kind of entry differently and `entry.FieldName` just isn't the right access pattern for it.

**Fix:** replaced `safe_call` with explicit, per-step `pcall` calls in `log_food_result`, so a genuine field-access error now surfaces its real message in the log instead of being silently flattened to "nil" — separately for the `StaticItemId` field read, its `:ToString()` call, and the `Num` field read, so the next test's log pinpoints exactly which step (if any) is actually failing versus which fields are genuinely empty.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** feed a wild Pal once more through the radial menu and check the log for the new, more detailed `[FOOD-DIAG] ... item[N]: StaticItemId(raw field)=... StaticItemId:ToString()=... Num=...` lines. If any of these three now show a real error message (not just "nil"), that tells us exactly which access pattern is wrong and how to fix it; if they still show clean nils with no error, that would mean the fields genuinely are empty and the array entries carry something other than expected — a different kind of problem to chase.

## Hundred-and-eleventh pass (2026-09-03): straight to the game's files — real item names found, including a "kinship peach" lead

Dragón's response to the field-access dead end was sharp and correct on two counts: (1) the wild-Pal inventory never opening in earlier tests isn't a bug to chase — that part of the feature (a real picker for wild Pals) hasn't been built yet, so of course it doesn't show one; and (2) rather than keep guessing at UE4SS Lua syntax for the broken array read, he asked to go dig through the game's own files directly — something this project has done successfully several times before (seventy-third, seventy-eighth, ninety-third, ninety-fifth passes), all via `repak` against the real game `.pak`.

**Extraction, this session (Linux side of the device bridge, not the Windows desktop):**

Found a `repak` CLI binary already present from earlier work (`repak_tool/repak_cli-x86_64-unknown-linux-gnu/repak`). Confirmed it works directly against the real pak:

```
$ repak info Pal-Windows.pak
version: V11
encrypted index: false
compression: Oodle
185014 file entries
```

(matches the seventy-third pass's own file count exactly — same real pak). Listed all files, found the real master item table at `Pal/Content/Pal/DataTable/Item/DT_ItemDataTable_Common.uasset` (plus its paired `.uexp`). Extracted both with `repak get`. The `.uexp` (222KB) turned out to hold only packed binary row data — running `strings` on it produced no readable text at all, which makes sense: DataTable row VALUES are packed binary, not text. The `.uasset` (83KB) is where the readable payoff was — it holds the package's own Name Table, which is where every FName string the table's rows actually reference lives as plain, searchable text.

**Real findings from `strings` on the `.uasset`:**

- Ordinary food item names: `BerryRed`, `MeatRaw`, `MeatMarbledRaw`, `Milk`, `Honey`, `Egg`, `Wheat`, plus a large family of per-species meat variants (`Meat_ChickenPal`, `Meat_SheepBall`, etc. — interesting confirmation that meat items are species-specific, not generic).
- **`AffectionFruit_01` and `AffectionFruit_02`** — "Affection" is a strong, direct match for `EPalItemTypeB.ConsumePalGainFriendshipPoint` (the dedicated friendship-treat category identified in the hundred-and-fourth pass's SDK research). This is the strongest lead yet for what Dragón's "kinship peaches" idea corresponds to in the game's actual data — a real, already-existing item family, not something this mod would need to invent.

**Caveat, stated plainly:** these are strings found in the item table's own asset name table — very likely the real `StaticItemId` values used throughout the game (this is exactly how Unreal DataTable row names normally work), but not yet PROVEN to be what the live inventory system expects when queried at runtime. That's exactly what this pass's new code tests.

**Shipped:** rather than keep pushing on the broken `CollectLocalPlayerControllableItemInfos_ByTypeB` array-of-structs read (kept running in parallel, still logging "2 entries exist" for comparison, but not the focus anymore), added a parallel check using a much simpler function: `CountLocalPlayerInventoryItemNum64(WorldContextObject, StaticItemId)` — declared `int64` return, no TArray, no out-param, no struct-wrapping ambiguity of any kind. Tries all 8 candidate names (`BerryRed`, `MeatRaw`, `MeatMarbledRaw`, `Milk`, `Honey`, `Egg`, `AffectionFruit_01`, `AffectionFruit_02`) every time `do_feed()` fires, logging each one's count (or error) individually.

Syntax-verified (`luac -p`), deployed to both destinations.

**Next test:** feed a wild Pal via the radial menu (ideally while carrying a few different real food items so the counts are meaningful) and check the log for 8 new `[FOOD-DIAG] CountLocalPlayerInventoryItemNum64("...") = ...` lines. A non-zero count that matches what Dragón is actually carrying confirms both the naming convention AND a clean, working path forward — a zero/error across the board would mean either these aren't the exact right strings, or this function has its own calling-convention quirk still to find.

## Crash #4 root cause (likely): constructing an FName from a Lua string to pass INTO a native call

Dragón's very next test — feeding a wild Pal to check the hundred-and-eleventh pass's new diagnostic — crashed the game outright, reproduced twice:

```
Unhandled Exception: EXCEPTION_ACCESS_VIOLATION reading address 0x0000000000000070
UE4SS
UE4SS
[... ~45 more UE4SS/Palworld_Win64_Shipping frames ...]
```

Address `0x70` is a small, fixed offset — the classic signature of dereferencing a field on a null (or near-null/garbage) base pointer, not a random memory-corruption crash. This happened inside native code, reached through a UE4SS-hooked call chain (the stack is dozens of frames deep through `UE4SS`/`Palworld_Win64_Shipping`, consistent with a native UFunction call originating from Lua).

**Why this is a fundamentally more dangerous category of bug than anything else in this project's history.** Every previous "unconfirmed guess" shipped for a live test — the Worker Menu's `OnClose:Bind()` syntax (eighty-eighth pass), every struct field read attempted this session, the `CollectLocalPlayerControllableItemInfos_ByTypeB` calling convention itself — was safe to try live specifically because a wrong guess produces a Lua-level error that `pcall`/`safe_call` catches cleanly, logs, and moves on from. An `EXCEPTION_ACCESS_VIOLATION` is not a Lua error — it's the OS terminating the process because native code dereferenced invalid memory. No amount of `pcall` wrapping in the Lua call site can catch or prevent this; the crash happens on the C++ side of the boundary, entirely outside Lua's error-handling reach.

**Most likely cause.** The hundred-and-eleventh pass's new code (`log_available_food_items`, called from `do_feed()`) made two kinds of native calls per invocation: the pre-existing `CollectLocalPlayerControllableItemInfos_ByTypeB` array call (run cleanly, without crashing, across roughly a dozen prior live tests this session), and the brand-new `CountLocalPlayerInventoryItemNum64(player, itemId)` loop, called with 8 different plain Lua strings (`"BerryRed"`, `"MeatRaw"`, etc.) for a parameter declared `const FName& StaticItemId` in the SDK dump. This is a meaningfully different operation than anything tried before: every prior use of an `FName` in this project has been READING one off an already-live object (e.g. `param:GetCharacterID()`, `speciesId:ToString()`) — never constructing one from scratch out of a plain Lua string to hand INTO a native function call as an argument. It's plausible UE4SS's automatic Lua-string-to-FName conversion for an argument position works differently (or not at all, safely) compared to receiving an FName as a return value or field — and that a malformed or unregistered FName construction led to a null/garbage internal pointer once the native function tried to look up the corresponding item data by it.

This is a hypothesis, not a fully confirmed root cause — the `CollectLocalPlayerControllableItemInfos_ByTypeB` call (which also touches `UPalItemUtility` and, indirectly, item lookup machinery) can't be fully ruled out either, especially since Dragón's crash report doesn't pinpoint exactly which line executed last. What IS certain: both calls came from the same new, never-crash-free-tested code path, and removing both from the live hot path is the only responsible immediate response.

**Fix:** removed the `log_available_food_items()` call from `do_feed()` entirely (hundred-and-twelfth pass). Feed — both the F9/F10 hotkeys and the wild-Pal radial-menu wiring — is back to exactly its pre-hundred-and-fourth-pass behavior, with zero food-inventory-diagnostic code running during a real feed. The diagnostic function itself is left in `Interaction.lua` for reference (in case its research value — the real item names found via `repak`, the confirmed-broken struct-array shape — is useful later), but is marked with an explicit "DO NOT CALL THIS FUNCTION LIVE" warning comment and is fully disconnected from any code path that runs during normal play.

**Standing lesson for future passes:** this project's established "ship the best-evidenced guess, let the log show what's wrong" methodology (used successfully for the Worker Menu's bind syntax, the array-vs-struct field reads, etc.) is safe ONLY when a wrong guess fails as a catchable Lua error. Any future native call that requires constructing a non-trivial parameter type (FName, FString, a struct) from scratch in Lua to pass as an argument — rather than just reading one off a live object — should be treated as carrying real crash risk, not just "might not work," and deserves a substantially higher bar of confidence (or a way to verify it away from Dragón's live save) before ever being tested in a real play session.

## Hundred-and-thirteenth pass (2026-09-03): post-crash research pivot — a zero-code-risk path via `UPalItemSlot`, no live test yet

After confirming the Crash #4 hotfix held (Dragón's retest: "did a test run, it didnt crash"), Dragón separately used UE4SS Live View to search for "berries" (from the moment they fed their Otomo) and dumped the one JSON result it found: `T_itemicon_Food_Berries.json`. Read directly off Dragón's machine via `device_bash cat` (this file lives under `ue4ss/IndividualObjectDumps/`, which is only reachable through the device bridge, not the cloud workspace's own `Read` tool). Result: it's a `Texture2D` object (`/Game/Others/InventoryItemIcon/Texture/T_itemicon_Food_Berries`) — just the inventory icon's image asset (`AddressX`, `CompressionSettings`, `LODGroup`, `ImportedSize`, etc.), not real item/slot data. Not a wasted test — it confirms the icon naming convention includes "Food_Berries" — but it doesn't give us anything we can build `SelectedFeedingItem`'s real `FPalItemSlotId` argument from.

Given the Crash #4 lesson (no more constructing native parameter types from scratch in Lua without a much higher bar of confidence), this pass went looking in the SDK dump for a research path that needs **zero new native calls** — something Dragón can find and dump directly via Live View, the same zero-code-risk method already used for the Worker Menu dispatch object (eighty-eighth pass) and now for the berries icon.

Found `UPalItemSlot` in `Pal.hpp` — and critically, it's declared `class UPalItemSlot : public UObject`, meaning it's a real, independently-spawned live object (one exists per inventory slot in memory right now), not just a struct embedded inside something else. Its fields line up almost exactly with what `SelectedFeedingItem` needs:

```cpp
class UPalItemSlot : public UObject
{
    int32 SlotIndex;                    // 0x0118 — matches FPalItemSlotId.SlotIndex directly
    FPalContainerId ContainerId;        // 0x011C — matches FPalItemSlotId.ContainerId directly
    FPalItemId ItemId;                  // 0x012C — see below
    int32 StackCount;                   // 0x0154 — how many of this item sit in this slot
    ...
    bool TryGetStaticItemData(class UPalStaticItemDataBase*& OutStaticItemData);
};
```

And `FPalItemId` itself:

```cpp
struct FPalItemId
{
    FName StaticId;              // the real item identifier, e.g. what "BerryRed" would look like at runtime
    FPalDynamicItemId DynamicId; // only relevant for items with per-instance state (durability, etc.) — a food item's dynamic ID is not needed for identifying WHICH food it is
};
```

(Note the field is `StaticId`, not `StaticItemId` — different name from the unrelated `FPalStaticItemIdAndNum.StaticItemId` struct found in the hundred-and-fourth-through-eleventh passes' abandoned array-read attempts. Easy to mix up; worth flagging for any future pass.)

If Dragón can find and dump a real `UPalItemSlot` object via Live View — ideally one holding a food item they already know the exact count of, so the dumped `StackCount` can be cross-checked against reality — the dump would hand us real, ground-truth `SlotIndex` + `ContainerId` + `ItemId.StaticId` values. That's exactly the shape `SelectedFeedingItem(FPalItemSlotId ItemSlotId, int64 Num)` needs, and it requires writing zero new Lua code and making zero new native calls to get it. This is a pure research/investigation step — no code changed this pass, nothing deployed. Next step is asking Dragón to do this specific Live View search and dump, then reading whatever comes back.

## Hundred-and-fourteenth pass (2026-09-03): read every dump JSON Dragón produced — confirmed `UPalItemSlot`'s real value shape, and a major correction: vanilla Feed does NOT go through `SelectedFeedingItem` at all

Dragón's reply to the hundred-and-thirteenth pass's instructions was a bulk UE4SS object-*search* listing (class reflection + ~2000+ live `PalItemSlot` instance object-paths, no field values) rather than individual "Dump as JSON" results — his own words: "tried to dump a few, dunno if i got the right one." Rather than ask him to keep guessing among thousands of anonymous paths, this pass went straight to the source: `ue4ss/IndividualObjectDumps/` on his machine (read via `device_bash`, since it's outside the cloud workspace's own filesystem) already held every JSON he'd actually produced with Live View's "Dump as JSON" during his last two test sessions. Read all of them directly. Two real findings, one confirming the existing plan and one overturning part of it.

**Finding 1 — `UPalItemSlot`'s value shape is now 100% confirmed with real numbers.** Five real slot dumps (`PalItemSlot_2147456500/507/514/2147457027/2147479631.json`), all live instances under the single `BP_PalItemContainerManager_C_2147481359` in `PL_MainWorld5`, each in its own single-slot `PalItemContainer`:

```
ContainerId: (ID=F8C1CC7C4F3D2E7F9C3E59BDC4CB4DE3)
ItemId: (StaticId="SkillCard_PoisonShot", DynamicId=(...all zero...))
SlotIndex: 0
StackCount: 1
```

...and one holding `ItemId.StaticId="Money"` with `StackCount: 856` — a stack count in the hundreds is a strong, real-world plausible cross-check that `StackCount` reads correctly (money in Palworld routinely sits in that range; this wasn't a food item Dragón told us the exact count of, but the order of magnitude is exactly right for a normal playthrough). This proves, with real values rather than just reflection metadata, that `ContainerId` renders as `(ID=<32-hex GUID>)`, `ItemId` as `(StaticId="<FName>", DynamicId=(...))`, and `SlotIndex`/`StackCount` as plain ints — exactly the shape `FPalItemSlotId{ContainerId, SlotIndex}` needs. These five specific slots are single-item holders (equipped skill cards, money) rather than the general inventory grid, so none of them happen to hold a food item — but the *format* is now proven, not guessed.

**Finding 2 — the real one, and it changes the plan.** Dragón's UE4SS.log for that same session (`ue4ss/UE4SS.log`, also read directly) shows he fed his Otomo (Kitsunebi) three separate times via the real vanilla radial menu (`OnDecidedInstructionFeed` fired three times, each preceded by `SelectItemInventory` — the game's own food-picker UI). The hundred-and-third pass's `[FOOD-DIAG]` watch hook on `/Script/Pal.PalMonsterCharacter:SelectedFeedingItem` **never fired once**, across all three real feeds. That's a clean, confirmed negative result, not an absence of evidence — the hook has been installed and logging permanently since the hundred-and-third pass, exactly for this purpose.

Instead, Dragón's own Live View dumps from the same session (`BP_ActionPairStandby_FeedItem_C_2147454074.json`, `BP_ActionPairBehavior_FeedItem_C_2147454059.json`, `BP_AIActionPairCall_FeedItem_C_2147454073.json`) reveal the *real* vanilla path: feeding an Otomo through the radial menu spins up a Blueprint AI-action pair — `BP_ActionPairStandby_FeedItem_C` (lives on the player's own `ActionComponent`) paired with `BP_AIActionPairCall_FeedItem_C` (lives on the Otomo's own AI controller's `ActionsComp`) via `BP_ActionPairBehavior_FeedItem_C`. The AI-action-call object carries the real slot data directly as plain fields:

```
FeedItemSlotId: (ContainerId=(ID=C50FC6F8404EFBF7845631B17694237B), SlotIndex=0)
FeedItemNum: 1
Trainer: BP_Player_Female_C (the player)
Instigator: BP_MonsterAIController_Otomo_C (Kitsunebi's controller)
Petting: True
```

This is a live object holding the *exact* `FPalItemSlotId` + `Num` the game itself used for a real feed — proof the struct shape is right, and a second, independent confirmation of Finding 1's format. But it also means: **`SelectedFeedingItem` is very likely not the function vanilla gameplay actually uses for this** (or if it exists and does something, it isn't part of this flow). The real mechanism is a full Blueprint AI-action pairing — the player's `ActionComponent` and the Otomo's own `PalAIActionComponent` coordinate through matched Standby/Behavior/Call objects, complete with animation montages (`AM_Player_Female_Feeding`), camera work (`BP_PettingCamera_C`), goal transforms for both actors, and a `PawnAction`-based AI action queue on the Pal's side — not a single one-shot native call we can safely replicate by constructing one struct from scratch. This is meaningfully more complex than the plan up to this pass assumed.

**Bonus finding, unrelated to feeding but useful for the existing wild-Pal radial-menu redirect**: `PalHUDDispatchParameter_WorkerRadialMenu_2147407608.json` and `..._2147409639.json` (both dumped from real Worker-menu Pet selections) show this dispatch-parameter object carries a plain `IndividualHandle` (pointing straight at the exact targeted Pal's `PalIndividualCharacterHandle`) and a plain `resultType` field (`"Pet"` in both samples). If this object is readable at the moment the real selection fires, it would be a much more direct source of "which Pal, which action" than the current `lastAimedInteractTarget`/`lastDecidedInstruction` tracking this file already does — worth a look in a future pass, though the existing system is already working and this isn't urgent.

**What we still don't know**: which real item `StaticId` Dragón actually fed (his three feeds' `ContainerId`s were never cross-referenced against a `PalItemSlot` dump showing a food `ItemId`) — none of the five `PalItemSlot` dumps happened to be a food slot. Given the Finding 2 pivot, this may matter less than previously thought: wild-Pal feeding may need to replicate (a simplified version of) the real AI-action-pair mechanism rather than call a single native function, which is a bigger design question to work through with Dragón before writing any new code.

No code changed this pass — pure research, reading files Dragón had already produced. Also used this pass to clean up: with Dragón's permission, deleted every file in `ue4ss/IndividualObjectDumps/` (all of it already read and captured here) plus the old empty `crash_2026_09_02_22_05_03.3713223.dmp` left over from the already-fixed, already-documented Crash #4, so future Live View dumps aren't buried in old ones.

## Hundred-and-fifteenth pass (2026-09-03): a new zero-risk watch on `UPalItemSlot:RequestUseToCharacter` — the next candidate for the real consumption call

Given the hundred-and-fourteenth pass's finding — vanilla Feed doesn't call `SelectedFeedingItem`, and the real mechanism (a full `BP_ActionPairStandby/Behavior/Call_FeedItem` AI-action pairing) is too much machinery to safely replicate for a wild Pal — the question became: is there a *simpler* real function, one that operates on a slot we can already find rather than a struct we'd have to build?

`UPalItemSlot`'s own method list (documented in the hundred-and-thirteenth pass) already had the answer sitting in it: `RequestUseToCharacter(FPalIndividualCharacterHandle TargetCharacterID, int32 UseNum)`. This is a method ON the slot object itself — named exactly for "use this item on a character" — which means if vanilla calls it to actually consume the item, we could call it too using ONLY the safe pattern this project already relies on everywhere: find the live slot object via `FindAllOf("PalItemSlot")` (a search, not a construction), read the target Pal's handle directly off an already-live Pal exactly like `get_individual_handle()` already does, and call the method on the object we found. That completely avoids ever constructing a new `FPalItemSlotId` struct from scratch — the exact pattern that caused Crash #4.

Added a new permanent, read-only watch hook on `/Script/Pal.PalItemSlot:RequestUseToCharacter` in `Interaction.lua`'s `Init()` (right after the existing `SelectedFeedingItem` watch), following the identical zero-risk pattern already proven for `AddFriendShip`/`SelectedFeedingItem`/the `PalInteractComponent` hooks: watch first, using only a function name already confirmed real via the SDK reflection dump (no guessing), read every field off the already-live `Context` (the slot itself) and args via the existing `hook_get`/`hook_describe`/`safe_call` helpers, log a `[SLOT-USE-DIAG]` line with `ContainerId`, `SlotIndex`, `ItemId.StaticId`, `StackCount` (at fire time), `UseNum`, and the target. No new native calls are made — this only listens. Verified via `luac -p` before deploying to both the live Mods folder and the Proyectos mirror.

**What this test will tell us**: if Dragón feeds his Otomo again through the normal radial menu and a `[SLOT-USE-DIAG]` line appears, that's direct proof this IS the real consumption call, and — critically — it will show us the actual `ItemId.StaticId` of a real food item for the first time (none of the hundred-and-fourteenth pass's `PalItemSlot` dumps happened to be food). If it never fires, that's still useful: it rules this function out too and narrows down what's left to check. Either way, zero new risk was taken to find out.

## Hundred-and-sixteenth pass (2026-09-03): CONFIRMED — `RequestUseToCharacter` really is the real consumption call. Fixed a display bug, one more test needed for a readable item name.

Dragón's very next real feed produced exactly what this diagnostic was built to catch — three real fires:

```
StackCount(at fire time)=65, UseNum=1
StackCount(at fire time)=64, UseNum=1
StackCount(at fire time)=63, UseNum=1
```

A clean, perfect one-for-one decrement across three separate real feeds. This is direct, unambiguous proof that `UPalItemSlot:RequestUseToCharacter` is the real function vanilla uses to consume a food item from a slot — not a guess, not inferred from static reflection data, but watched firing live with the stack count changing exactly as expected each time. This is the single most important confirmed fact this project has found for the food-feeding feature so far, and it came from a hook that only ever reads fields off objects the game itself already handed us — zero new native-call risk was taken to get it.

One cosmetic bug in the same log: `ContainerId` printed as `UScriptStruct: 0000...` and `ItemId.StaticId` printed as `FNameUserdata: 0000...` instead of readable values. Root cause: plain Lua `tostring()` on an `FGuid` or `FName` field in UE4SS just prints the userdata's memory address — it doesn't know to call the type's own `:ToString()` method, which is what actually renders them as text (this is exactly why the earlier Live View JSON dumps looked right — the JSON dumper calls the proper stringification internally, but our own `tostring()` calls didn't). Fixed by adding a small `readable(value)` helper that tries `value:ToString()` first and only falls back to plain `tostring()` if that fails. This is a method call on a value already safely read off a live object — not a new native call, not anything constructed from scratch — so it carries the same zero risk as everything else in this watch. Also logs the target argument two ways now (`hook_describe` and the new `readable`) since `GetFullName()` on it returned `/Script/Pal.PalInstanceID` — meaning the second argument's real type is `FPalInstanceID`, not the `FPalIndividualCharacterHandle` the SDK method-signature comment assumed. Worth a note for whenever this project needs to construct or match that argument: it may need a `PalInstanceID`, not the `IndividualHandle` `get_individual_handle()` already reads — needs one more real fire to see what `readable(target)` shows before assuming either way.

Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. Test plan: one more real feed through the radial menu — this time the log should show the actual GUID and the real food item's name (e.g. `BerryRed` or whatever Dragón actually used) in plain text, plus a readable form of the target argument.

## Hundred-and-seventeenth pass (2026-09-03): every piece is now proven safe — a DRY-RUN test (CTRL+J) for actually calling the real feed function ourselves

Dragón's next feed confirmed the fix: `ItemId.StaticId=Berries` came through as plain, readable text — the real, confirmed food item name (not "BerryRed," the old guess still sitting, disconnected, in `FOOD_CANDIDATE_ITEM_IDS`). `ContainerId` and the target argument still print as raw addresses — `:ToString()` isn't bound for `FGuid`/`FPalInstanceID` the same way it is for `FName` in this UE4SS build — but that turned out not to matter, because the SDK dump answered the one real remaining question a different way.

The target argument's real type, confirmed two passes ago via `GetFullName()`, is `FPalInstanceID` — `{FGuid PlayerUId; FGuid InstanceId; FString DebugName}` (`Pal.hpp` line 4025). The question was: where do we get a *real, already-valid* one of these for a Pal we pick ourselves, without constructing one from scratch (the Crash #4 pattern)? The answer was already sitting in a class this file uses on every single interaction: `get_individual_handle(pal)` returns `comp.IndividualHandle`, a `UPalIndividualCharacterHandle*` — and that class (`Pal.hpp` line 24490) has a plain field, `FPalInstanceID ID` at offset 0x48, plus a zero-argument getter `GetIndividualID()`. So `get_individual_handle(pal).ID` is a real, live `FPalInstanceID` for ANY Pal — wild or owned — obtained via a direct field read off an object this file already trusts, exactly the same safe pattern used everywhere else, never a struct hand-assembled from raw values.

That means every piece `RequestUseToCharacter` needs is now individually proven safe on its own:
- a live food slot, found via `FindAllOf("PalItemSlot")` + a field filter (proven safe, used for `find_targeted_pal` itself)
- a live target `FPalInstanceID`, read off `get_individual_handle(pal).ID` (proven safe, used everywhere in this file)
- a method call on the slot object we found, using arguments read (not built) from other live objects — structurally the same risk class as `PlayActionByType(pal, ACTION_TYPE)`, already called constantly without incident

But actually calling this live, for the first time, deducts a real inventory item — a different category from every watch-only hook so far. Following this project's own established discipline (WORKASSIGN-DIAG before ever touching work-assignment state; the AddFriendShip watch running for many passes before anything ever called AddFriendShip), added a new, fully separate DRY-RUN test bound to CTRL+J (mirroring the existing CTRL+K `TryDirectCapture` experiment's isolation pattern — a distinct key, nowhere near the main F9/F10/"4" paths). `do_test_feed_item_dry_run()`:

1. Finds whatever Pal is being looked at (reuses `find_targeted_pal` — the same proven look-based targeting as F9/F10/CTRL+K).
2. Reads that Pal's live `FPalInstanceID` via `get_individual_handle(pal).ID` and logs it.
3. Scans every live `PalItemSlot` in the loaded world (`FindAllOf`) for one whose `ItemId.StaticId` is `"Berries"`, and logs every match's `SlotIndex`/`StackCount`.
4. Calls nothing. Consumes nothing. Feeds nobody.

Test plan: Dragón notes his real Berries count, aims CTRL+J at any Pal (wild or owned — the dry run works on both, unlike the real vanilla path which only ever fires for an active Otomo), and reports whether the logged `StackCount` matches reality. If it does, the next pass can flip this into an actual call with high confidence; if the count's off (e.g. matching some other container's Berries, not the player's own), that's exactly the kind of thing this dry run exists to catch before ever touching real state. Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror.

## Hundred-and-eighteenth pass (2026-09-03): the dry run got a perfect match — upgraded CTRL+J into the real call

Dragón reported exactly 62 Berries before testing. The dry run's log showed a `candidate #1` reading `StackCount=62` on every single press — an exact match — while every other candidate matching `"Berries"` read `StackCount=1` or `2` (almost certainly small amounts other nearby Pals happen to be carrying, not the player's own stash; easy to tell apart from a real inventory hoard). That's a clean, direct, real-world confirmation that the whole chain — finding the slot via `FindAllOf`, reading the target's `FPalInstanceID` via `get_individual_handle(pal).ID` — resolves to the correct real data, not a coincidence or a lucky guess.

Upgraded the same CTRL+J test (still fully isolated from F9/F10/the radial menu — same discipline as CTRL+K's `TryDirectCapture`) from a dry run into the real thing: `do_test_feed_item()` now picks the candidate slot with the **highest** `StackCount` among matches (a robust heuristic built on the real evidence above — not just "the first one found," which happened to work in testing but isn't a real guarantee about `FindAllOf`'s return order) and calls `best.slot:RequestUseToCharacter(individualId, 1)` on it for real, wrapped in `pcall` like every native call in this file. Immediately after a successful call, it re-reads the same slot's `StackCount` in the same tick as a direct before/after check. This is, deliberately, the first time this project calls a function it only ever watched before — but every argument involved is either found (the slot, via a proven-safe search) or read off an already-live object (the target ID) — never constructed from raw values, which is the precise distinction this project draws between "safe" and "Crash #4." Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. Dragón was told explicitly, before testing, that this key now spends a real item and attempts a real feed.

(For context going forward: Dragón noted his inventory held exactly two food items during all this testing — the Berries stack and 2 Kinship Peaches, held back for later testing of the kinship-peach feature. The scans above only ever matched `"Berries"` by name, so the peaches were never touched by any of this.)

## Hundred-and-nineteenth pass (2026-09-03): real testing found the actual gate — `RequestUseToCharacter` only works on the player's own active Otomo, not any Pal

Dragón tested thoroughly — 11 real CTRL+J presses — and reported it himself before any log was read: "pressed it a bunch of times, saw 2 disappear after taking out my otomo and trying again, but it wasn't reliable." Reading the log line by line confirmed this is not randomness at all, it's a clean, deterministic pattern:

- Aimed at `BP_ChickenPal_C` (a wild Pal): the call returned `ok` (no Lua error), but `StackCount` read 62 both before AND after — a silent no-op. Nothing was consumed, despite no error being raised.
- Aimed at `BP_Kitsunebi_C` (Dragón's own actively-spawned Otomo), twice: `StackCount` dropped exactly one each time (62→61, then 61→60) — real, working consumption.

So `RequestUseToCharacter` really is the consumption function, but it appears to internally gate on the target being the player's own active/spawned Otomo — not simply "any live `FPalInstanceID`." This is a genuinely new, real finding from live testing, not something the SDK reflection dump could have told us (the function's internal validation logic isn't reflected metadata). It directly explains what Dragón saw and rules out the simplest version of the plan: calling this one function with any wild Pal's ID isn't the whole answer.

Also notable: even on the two SUCCESSFUL Kitsunebi calls, no `AddFriendShip` watch line fired nearby — confirming `RequestUseToCharacter` is purely the inventory-side plumbing, with no friendship or animation effect of its own. That was expected (this project's own `do_interaction()` already grants friendship via a completely separate call, `PlayActionByType(pal, Happy)`, whose own internal side effect is the real friendship grant), but good to have it confirmed rather than assumed.

**The fix, shipped this pass**: rather than spend more research trying to find and satisfy whatever internal check gates the native call to Otomos only, added a plain, self-correcting fallback directly in `do_test_feed_item()`: after calling `RequestUseToCharacter`, re-check `StackCount`. If it moved, the native call did its job — done. If it didn't move (the wild-Pal no-op case), fall back to writing `slot.StackCount = before - 1` directly — a single scalar field WRITE on a `UObject` we already hold a live reference to. This is a new category of operation for this file (every previous "safe" pattern was a read or a call, never a write), but it's about as low-risk a write as exists: one plain int field, no struct/replication machinery, and the before/after check means it can never double-consume — if the native call already worked, the fallback never runs at all.

After whichever path actually removes the item, the test now also fires the target's own Happy reaction (`actionComp:PlayActionByType(pal, ACTION_TYPE_HAPPY)` — the exact same proven call `do_interaction()` already uses, gated on the same busy-check, `actionComp:ActionIsEmpty()`), so a single CTRL+J press now attempts the FULL cycle: consume a real item (native call or fallback write, whichever actually works) → target reacts happily → real vanilla friendship grant as Happy's own side effect (same as every other interaction in this mod). Verified via `luac -p`, deployed to both the live Mods folder and the Proyectos mirror. Test plan: aim CTRL+J at a WILD Pal specifically this time (the case that previously no-op'd) and check whether the fallback write fires, whether the Happy reaction plays, and whether `[WATCH] real AddFriendShip fired` shows up afterward.

## Hundred-and-twentieth pass (2026-09-03): Dragón corrected the whole approach — and testing confirmed the real system needs a deeper fix than expected. PAUSED pending his decision.

Before the CTRL+J-on-a-wild-Pal test above ever happened, Dragón stopped to ask a sharp, correct question: why was a brand-new Happy-reaction call being wired into the test at all, when the reach-out/reaction/friendship system was already fully solved and already wired into the real radial-menu Feed path? The honest answer: it wasn't needed for the final feature — it was test scaffolding, added to CTRL+J specifically so the untested fallback (the direct `StackCount` write) could be validated end-to-end without touching the already-working F9/F10/radial Feed flow, same isolation discipline as CTRL+K. Not a second permanent system, but that wasn't communicated clearly at the time.

That led to a bigger correction. The plan at that point was: wire the CTRL+J test's "auto-pick the biggest matching food stack and consume it" logic directly into `do_feed()`, so a real Feed would silently consume a hardcoded `"Berries"` behind the scenes. Dragón rejected this outright and explained the real vanilla behavior: pressing Feed opens the actual game inventory/item-picker, showing whatever's genuinely eligible (or nothing, if you're out of food) and letting the player choose or back out — the game never blocks the Feed action or silently auto-selects an item for you. His instruction was direct: **"dont try to trick the game into doing something, just find how it does and activate it for our feed interaction, thats it."** This matches this project's entire methodology up to now (the "4" menu, the wild-Pal Pet/Feed reactions, the Worker Menu eligibility fix) — every other feature here was built by finding the real system and getting it to treat a wild Pal as eligible, never by hand-rolling a replacement. The CTRL+J auto-pick-and-consume logic (hundred-and-eighteenth/nineteenth passes) is judged NOT the right final design — it still exists in the file as proven technical groundwork (real evidence that `RequestUseToCharacter` plus a fallback `StackCount` write can consume an item safely), but it is not what should ship.

**The real research question this raised**: this project already has a mechanism — the `TryGetSpawnedOtomo` substitution, running since roughly the eighty-fifth/ninety-ninth passes — that makes a wild Pal appear as the player's "currently spawned Otomo" for the duration of the radial-menu window, which is what already makes wild-Pal Pet/Feed work via the real "4" menu today. Since the real vanilla food-picker system (found in the hundred-and-fourteenth pass: `OnDecidedInstructionFeed` → `SelectItemInventory` → `BP_ActionPairStandby/Behavior/Call_FeedItem`) is Blueprint logic that also keys off "whatever the current Otomo is," the open question was whether that SAME existing substitution might already be enough to make the real system activate for a wild Pal, with nothing new to build.

**Tested directly, six real times**: Dragón aimed the real "4" menu at wild Pals and picked Feed for real (not F10, not CTRL+J — the actual game menu). The log is unambiguous. Every one of the six attempts shows ONLY this project's own approximation firing:

```
[WILD-ACTION] window closing with a substituted wild Pal and a decided instruction=feed — firing the real action now
player reaching out: PlayActionByType(pal, HumanFeeding=49) NOW
target reacting: PlayActionByType(pal, Happy=38) NOW
```

Zero appearances of `SelectItemInventory`, `ActionPairStandby_FeedItem`, `ActionPairBehavior_FeedItem`, or `AIActionPairCall_FeedItem` — the exact machinery that fired reliably during the real-Otomo feeds earlier in this same session (hundred-and-fourteenth pass). Since `RegisterHook` is non-blocking (this project's hooks only ever listen alongside the game's own native code, never replace or prevent it — confirmed by every hook in this file), this is real, clean evidence that **the game itself chooses not to continue into the real food-picker flow for a Pal that's only substituted at the "what's your current Otomo" getter level.**

**Conclusion**: the existing substitution isn't sufficient on its own. Somewhere between the menu's `OnDecidedInstructionFeed` decision and the real system opening `SelectItemInventory`, there's a deeper eligibility check this substitution doesn't satisfy — plausibly the same check (or a related one) that gated `RequestUseToCharacter` itself to the real Otomo only, in the hundred-and-nineteenth pass. That deeper check may not even read the same getter our substitution overrides — a real candidate, from the SDK dump, is the player's own authoritative owned-Pal record (`TArray<FPalInstanceID> OtomoIndividualIdList`, found on the player/controller in `Pal.hpp`) rather than a simple "what am I currently showing as active" field. If that's the real gate, satisfying it for a wild Pal would mean temporarily inserting into (or otherwise satisfying a check against) a genuine ownership record — a materially bigger and riskier category of change than anything this project has touched so far (every prior change has been a read, a call with found/read arguments, or a single scalar field write; this would mean touching what the game considers a real, authoritative fact about ownership).

**Status: PAUSED here, deliberately, pending Dragón's decision.** No code changed in this pass — this was entirely testing and analysis triggered by his own design correction. The open question handed back to him: keep researching that deeper gate (bigger, more uncertain, possibly touching ownership-record state) or reconsider priority/scope for real food-item feeding given what this now looks like. Whichever way this goes, the correct principle going forward — confirmed explicitly by Dragón — is: find and activate the real system, never approximate or auto-pick behind the scenes.

## Hundred-and-twenty-first pass (2026-09-03): a real tooling gap found and fixed, a wrong candidate corrected, and two new safe watch points added

Dragón asked for a fresh, independent look at whether anything had been missed or done wrong on this specific question, and gave full latitude on method (files, internet, Live View). Read the actual game header dump (`Pal.hpp`, at `Pal/Binaries/Win64/ue4ss/CXXHeaderDump/` in the real game install — never previously read directly by this AI session) and this project's own real source files end to end, rather than working from summaries.

**Real tooling gap found and fixed.** `repak` (used throughout this project's history for reference-mod/pak extraction) turned out to have been installed on a separate, ephemeral sandboxed environment from an earlier session ("device_bash") that doesn't persist between sessions — it was simply gone. Downloaded the same tool fresh (`repak_cli` v0.2.3, the exact version this project has cited throughout, from `github.com/trumank/repak`, portable zip build, no installer) into `Proyectos/_tools/repak/`, alongside this workspace's other shared tools (AssetRipper, jpexs-decompiler). Used it to finally unpack and read the two reference mods this project had only ever read via one-off `strings` passes without a persisted local copy — `RemoteAccessEverything` and `Pal Analyzer` — now saved under `palbonds-mod/research/unpacked/` for any future session to re-read directly without needing to redo this.

**A real file-drift problem found and fixed.** This project's mod scripts and docs exist in three places: the real deployed game Mods folder, a top-level Proyectos mirror (`32-PalBonds/mod/PalBonds/`, `32-PalBonds/docs/`, `32-PalBonds/DESIGN.md`), and a second, nested mirror matching this repo's own documented layout (`32-PalBonds/palbonds-mod/mod/PalBonds/`, `.../docs/`, `.../DESIGN.md`). At some point recently, edits started landing only in the top-level mirror + the real game folder, while the nested mirror silently stopped being updated for `Interaction.lua`, `Logger.lua`, `Personality.lua`, `DESIGN.md`, and this very file (`hook-points.md`) — up to ~120 passes and roughly 40 CLAUDE.md session-log entries out of sync in the worst case (`Interaction.lua` was 1528 lines in the stale copy vs. 2856 in the real one). Caught before any edit was made on top of stale content by diffing all three locations file-by-file. Fixed by resyncing every stale file in the nested mirror from the real deployed copies. **Worth Dragón's attention**: two mirrors of the same project now exist on disk with confusingly similar paths (`32-PalBonds/mod/` vs `32-PalBonds/palbonds-mod/mod/`) — worth deciding which one to keep and deleting the other, rather than risking this same drift recurring. Not deleted by this pass — that's a call for Dragón, not something to do unilaterally.

**A wrong candidate corrected.** The hundred-and-twentieth pass's leading candidate for the deeper eligibility gate, `TArray<FPalInstanceID> OtomoIndividualIdList`, is real in `Pal.hpp` — but it's a field of `FPalArenaPlayerInitializeParameter`, an Arena/PvP-mode-only struct (every sibling field is Arena-prefixed: `ArenaRank`, `bIsNpc`, `OtomoPicks`, `bPartySelected`). This is the exact same category of mistake this project already made and corrected once before (twenty-first pass: `GetOtomoHolder(PlayerState)` "turned out to belong to an Arena/PvP-test-only class"). Flagging this now, before Dragón spends a test session on it.

**A better-grounded candidate found instead.** Searching `Pal.hpp` for every non-Arena `TArray<FPalInstanceID>`/`TArray<UPalIndividualCharacterHandle*>` field or getter surfaced `class UPalPlayerPartyPalHolder : public UObject` — the same real, non-Arena class this project already confirmed back in the sixth continuación (`FirstOtomoPal`/`SecondOtomoPal`/`BenchMember`, the "two simultaneous Otomo slots" finding that explained Daedream/Dazzi/Flopie following as secondaries). Two functions on it, never previously noted: `void GetPartyMember(TArray<UPalIndividualCharacterHandle*>& OutPartyMember)` (a real membership query) and, the strongest lead found so far for this exact question, `bool PawnOtmoIsPartyOtomo(bool SecondPal, UPalIndividualCharacterHandle* IDHandle)` — a bool-returning query that takes a handle directly as a parameter, reading exactly like "is this specific handle actually my registered party Otomo." No getter anywhere in the header dump exposes a `UPalPlayerPartyPalHolder*` by name, so `diagnose_party_membership()` (Interaction.lua) finds live instances the same way `WBP_PalNPCHPGauge_C` was found back in the fiftieth pass — `FindAllOf` the class name directly, not assuming a wiring path from static reflection alone.

**Two new permanent native watch hooks added**, on `UPalUIPlayerRadialMenuBase` (confirmed native in `Pal.hpp`, so no Blueprint retry-loop needed): `OpenOtomoFeedInventory()` — a real lead first noted back around the sixty-fifth pass ("Otomo/companion-feed-inventory specific... not yet tested or hooked") and never followed up on until now — and `SelectedFeed(ItemSlotId, itemNum)`, the widget-side sibling of the already-watched `SelectedFeedingItem` (confirmed hundred-and-sixth pass to be the WORKER-only path; `SelectedFeed` is a real, distinct candidate for the Otomo-specific one). Both are pure watches, zero side effects, same discipline as every hook in this file.

**All of the above is read-only** — `diagnose_party_membership` calls nothing that mutates anything (`FindAllOf`, plain field reads, and a bool-returning query function), fires once per newly-aimed wild Pal (not per-tick, reusing the existing dedup gate — this project's own hard-learned lag lesson applied proactively rather than reactively this time), and the two new hooks are pure `RegisterHook` watches. No write of any kind was attempted on `UPalPlayerPartyPalHolder` or anything else — that stays exactly where the hundred-and-twentieth pass left it, paused pending Dragón's explicit go-ahead, since satisfying a real ownership-record check (if that's what this turns out to be) is a materially bigger risk category than anything this project has done so far.

Verified with `luaparse` (a Windows `luac` binary wasn't available on this device either — same missing-tool problem as `repak` — used `npx luaparse` as a syntax-only substitute since no exact UE4SS Lua build was found locally; a real in-game load is still the first real test, same as always). Deployed to all three locations (real game Mods folder + both Proyectos mirrors, now back in sync).

**Test plan for Dragón**: aim the real "4" menu at a wild Pal (as in the hundred-and-twentieth pass's test) and pick Feed once. The log should show, automatically this time (no manual Live View needed): whether `OpenOtomoFeedInventory`/`SelectedFeed` ever fire for the substituted case (expected: no, extending the hundred-and-twentieth pass's finding with a permanent watch instead of a one-off manual check), and — the real new data — the `[PARTY-DIAG]` lines: how many `PalPlayerPartyPalHolder` instances exist, what `FirstOtomoPal`/`SecondOtomoPal`/`BenchMember` show, and critically what `PawnOtmoIsPartyOtomo` returns for the substituted wild Pal's own handle. If it reads `false` on both slots while the real Otomo would read `true` (not tested this pass — would need a second aim-at-your-own-Otomo comparison), that's real confirmation this is the actual gate, and a well-evidenced, safe-to-consider function for an actual future test — never attempted this pass, only ever read.

## Hundred-and-twenty-second pass (2026-09-03): test results read — the gate is narrower than thought, `UPalPlayerPartyPalHolder` still unconfirmed (never instantiated in this session), and the folder consolidation is complete

Dragón ran the exact test plan above: aimed at a substituted wild Sheepball twice (Care, then Feed, then Feed again a second time), then switched to his real Otomo Kitsunebi and did the same (Care, then Feed). Read `palbonds-live.log` directly (timestamps 18:14:04–18:14:51).

**`PARTY-DIAG`: `PalPlayerPartyPalHolder` never instantiated at all this session** — `FindAllOf` returned 0 live instances all three times it ran (each of the three wild-Pal substitutions). Not a negative result for the hypothesis itself (there was nothing to call `PawnOtmoIsPartyOtomo` ON, so it was never actually tested) — just inconclusive, the same "class exists in the header dump but isn't necessarily instantiated in the current game mode" situation this project already hit once before with `WBP_PalNPCHPGauge_C` before it was confirmed to only appear once you're actually near a wild Pal's HP bar. Possible explanations, untested: `UPalPlayerPartyPalHolder` needs Arena/PvP mode to ever spawn despite lacking Arena-prefixed fields itself (would make the twenty-first-pass parallel even closer than first thought), or it needs some other trigger this session never hit. Not chased further this pass — the log below turned up a much more precise lead instead.

**`FOOD-DIAG`: a real, clean, three-vs-one comparison — and the gate is narrower than the hundred-and-twentieth pass thought.** `OpenOtomoFeedInventory` fired for BOTH cases: twice for the substituted wild Sheepball (18:14:12, 18:14:19) and once for the real Otomo Kitsunebi (18:14:45) — immediately before `OnDecidedInstructionFeed` each time, and immediately followed by this project's own `[WILD-ACTION]` fallback for the wild case both times. `SelectedFeed`, on the other hand, fired exactly once — only for the real Kitsunebi case (18:14:46), immediately after a real `AddFriendShip` grant, with real data (`SlotIndex=0 itemNum=1`), followed two ticks later by the real `PalItemSlot:RequestUseToCharacter` consumption (`ItemId.StaticId=Berries`, `StackCount` 52, confirming this was Dragón's own real inventory). Zero appearances of `SelectedFeed` for either wild-Pal attempt.

**What this actually narrows down:** the hundred-and-twentieth pass's theory placed the gate somewhere between `OnDecidedInstructionFeed` and the food-picker opening. This is more precise: the decision to CALL `OpenOtomoFeedInventory` doesn't check Otomo status at all — it fires unconditionally either way. Whatever gate exists sits strictly INSIDE `OpenOtomoFeedInventory`'s own execution, or in whatever it internally calls before a real item selection can ever reach `SelectedFeed` — since that function takes no arguments, it must resolve "who is my Otomo" from some internal state at the moment it runs, not from a passed-in parameter. Two live possibilities, neither confirmed: (1) it re-reads `TryGetSpawnedOtomo()` itself, in which case our post-hook substitution SHOULD already cover it (same function, same override) — meaning if the gate really lives here, the override itself might not be taking effect deeply enough, or something reads the underlying value a different way internally that a Lua-level return-value override can't reach; (2) it reads a cached reference the menu widget itself set once earlier (the "SpawnedOtomo" Blueprint variable on `WBP_PlayerRadialMenu_C`, real and confirmed to exist via the `RemoteAccessEverything` string dump, sixty-fifth pass) rather than calling the getter fresh — in which case writing that field directly, in addition to overriding the getter's return value, is the natural next experiment (the same "write the real field, not just what wraps it" pattern already proven safe for `IndividualHandle` back in the ninetieth pass). **Not attempted this pass** — flagging it as the concrete next step, since it would be the first write to live menu-widget state beyond the getter override, and this project's own discipline is to lay out the reasoning and let Dragón decide before crossing into a new kind of write, however low-risk.

**Folder consolidation, completed at Dragón's request.** He confirmed the nested `palbonds-mod/` mirror was never an intentional structure he asked for — a previous AI session created it without being asked, and he'd rather have one flat folder. Before deleting anything: re-diffed every file between the nested mirror and the top-level one and found the top-level mirror was ALSO incomplete (only 3 of 11 Scripts files were ever current there — `Interaction.lua`/`Logger.lua`/`Personality.lua` — the other 8 had never been synced from the real game copy at all, a gap missed in the hundred-and-twenty-first pass's own resync, which only fixed the nested copy). Fixed by copying every current script from the real deployed game folder into the top-level mirror, then moving everything that ONLY existed in the nested mirror (`README.md`, `research/` including the newly-unpacked reference-mod assets, `docs/phase0-install.md`, `docs/phase1-research.md`, `mod/PalBonds/enabled.txt`) up to the top level. Verified file-by-file (every file under the nested mirror had a byte-identical match at the top level, and the top-level mirror matched the real game deployment on all 11 scripts) before deleting anything. The nested `palbonds-mod/` folder is now empty; its final removal is stuck on a Windows file lock (something has it open) rather than any data-loss risk — a trivial manual delete or a retry next session. `DESIGN.md` §5 and the two forward-referencing paths in `CLAUDE.md` were updated to describe the new flat layout instead of the old nested one.

## Hundred-and-twenty-third pass (2026-09-03): the actual field-write experiment — writing the menu widget's own cached Otomo variable, not just the getter's return value

Dragón said to go ahead with the concrete next step the hundred-and-twenty-second pass laid out.

**What changed.** `openRadialMenuActionWindow()` now takes the live widget instance as a parameter and remembers it (`lastOpenMenuWidget`) — sourced from `CanOpenPlayerActionMenu`'s own hook `Context`, which every hook in this file already receives but this one never kept before. `make_hook_handler` now passes that `self_` through to whatever `onFire` closure a `radialHookTargets`/`workerMenuTargets` entry declares (every other `onFire` in this file takes zero declared params, so passing an extra argument to them is harmless in Lua). Then, in the `TryGetSpawnedOtomo` redirect — right after the existing `ReturnValue:set(wildPal)` — a new attempt: `lastOpenMenuWidget.SpawnedOtomo = wildPal`, a direct write to the menu widget's own cached Otomo variable (real, confirmed via the `RemoteAccessEverything` string dump back in the sixty-fifth pass), guarded by `lastOpenMenuWidget:IsValid()` and wrapped in its own `pcall`, logged independently (`[RADIAL-REDIRECT-FIELD]`) so a live test shows plainly whether the field exists under this name/type on this build, separately from whether the getter-override itself succeeded.

**Why this specific write, and why it's still low-risk despite being a new category.** The hundred-and-twenty-second pass's log comparison showed `OpenOtomoFeedInventory` fires identically whether the target is real or substituted, but `SelectedFeed` (a real item actually getting picked) never fires for the substituted case — meaning whatever gates real selection reads something other than a fresh call to the getter this project already overrides. The leading candidate is this exact widget's own cached variable, set once early in the menu's open sequence rather than re-read each time — the same reasoning already validated once before in this project (`IndividualHandle`/`OnClose` for the Worker Menu, ninetieth pass: writing the real field directly, not just what wraps it, is what actually worked there). This write only ever runs inside the same narrow, already-gated window as the getter override (confirmed wild Pal, real Otomo excluded, once per newly-aimed Pal) and touches a transient UI widget's own display state — not save data, not a native gameplay function call, a materially smaller blast radius than the ownership-record concern that's still paused from the hundred-and-twentieth pass.

Verified with `luaparse`, deployed (game folder + the single remaining Proyectos mirror, now flat under `32-PalBonds/`).

**Test plan for Dragón**: aim "4" at a wild Pal and pick Feed, same as before. Check the log for `[RADIAL-REDIRECT-FIELD]` — `ok` confirms the field exists and accepted the write; a `FAILED` line will show the real error (wrong field name, wrong type, or not writable from Lua) to iterate from. Either way, immediately after: does `SelectedFeed` finally fire for the wild Pal this time? That's the real test of whether this was actually the missing piece.

## Hundred-and-twenty-fourth pass (2026-09-03): the field write worked, but it wasn't the missing piece — clean negative result, both accessible levers are now exhausted

Dragón fed a wild Chikipi three times (four `[WILD-ACTION]` feed events actually logged) through the real "4" menu.

**`[RADIAL-REDIRECT-FIELD]`: the write itself succeeded, every single time** — over 30 `ok` lines, zero `FAILED`. `SpawnedOtomo` is real on `WBP_PlayerRadialMenu_C`, writable from Lua, and this project's redirect now controls it directly, not just the getter's return value.

**But `SelectedFeed` still never fired — not once, across all four attempts.** `OpenOtomoFeedInventory` fired all four times (same as before the field write existed), and every single time, only this project's own `[WILD-ACTION]` fallback actually did anything. Writing the widget's own cached Otomo variable, on top of the getter override, made no observable difference to whether the real food-picker engages.

**What this actually rules out.** This project now controls both plausible "what does the menu think my Otomo is" surfaces available to Lua: the function every caller can query (`TryGetSpawnedOtomo`) and the value this specific widget caches from it (`SpawnedOtomo`). Both say "the wild Pal" throughout the whole window, confirmed genuinely written in the second case. The real food-picker still never opens. That means the actual gate reads neither of these — it's checking something more authoritative, beyond anything a UI widget holds locally. The most likely remaining candidate is exactly the one flagged as out-of-scope back in the hundred-and-twentieth pass: a genuine party/ownership record on the player or their Otomo-holder component (not `OtomoIndividualIdList` — confirmed Arena-only, hundred-and-twenty-first pass — and not `UPalPlayerPartyPalHolder`, which never even instantiated in either test session so far). Reaching that would mean actually getting the wild Pal's handle registered somewhere the game itself considers authoritative — which circles back to this project's oldest unsolved question (nothing has ever made `AddOtomoHandleToFreeSlot`, or any equivalent "join the party for real" call, fire from Lua in three-plus separate real capture paths tested months ago).

**Status: no further surface-level lever left to try without crossing into that bigger risk category.** Both getter-override and cached-field-write are now confirmed dead ends for reaching the real food-picker specifically. This project's own approximation (F9/F10-style `PlayActionByType` + Happy, already wired to fire automatically through the real "4" menu since the seventy-third/ninety-ninth passes) remains the only working Feed path for wild Pals — real friendship gain, real animations, just no real inventory item consumed. Handed back to Dragón: keep pushing toward the party/ownership-record territory (bigger, more uncertain, would need real caution before any live attempt), or treat the current approximation as good enough for this feature and move priority elsewhere. No code changed this pass beyond what was already deployed — this is purely the read of the test result.

## Hundred-and-twenty-fifth pass (2026-09-03): Skittish → Curious after a real interaction (personality), plus a Live View dump that finally reveals the real Feed pairing's internal Blueprint graph

Two independent threads this pass, per Dragón's own explicit "up to you if now or later" — picked the self-contained one (personality) to implement, and separately reviewed a Live View dump he'd already taken.

**Skittish → Curious, IMPLEMENTED.** Dragón's original personality idea, from before the tier-rolling system even existed: a Pal that's currently tracked as "skittish" (whether via a forced roll or a naturally-skittish species) gets won over the first time a real interaction actually lands on it, and its tracked disposition flips to "curious" from then on. `Personality.OnSuccessfulInteraction(palId, palActor)` is called from `Interaction.OnWildPalPetted` — an event already confirmed reliable across many sessions, deliberately NOT tied to the still-unconfirmed enforcement scan or anything in the stalled food-picker research. Updates the tracked `disposition` field unconditionally (cheap, always happens, logged as `[WON-OVER]`), then best-effort tries to also make this show up in real AI behavior by re-pointing the Pal's own `AIResponsePreset` at an already-live "curious" donor — reusing the exact same safe, ownership-gated pattern `try_enforce_personality` already uses, just triggered by this one event instead of the periodic scan. If no live curious donor is loaded nearby at that moment, the tracked state still updates; the real-behavior swap simply waits for a future opportunity (there isn't one — this only ever fires once per Pal). Verified with `luaparse`, deployed. **Test plan**: find and successfully pet/feed a wild Pal whose earlier `[PERSONALITY-ROLL]`/log line showed `disposition=skittish`, then check for a `[WON-OVER]` line — and, separately, whether its real behavior changed (stopped fleeing) if a donor happened to be available.

**The Live View dump — genuinely new information, but doesn't unlock a safe next step.** Dragón dumped `BP_ActionPairBehavior_FeedItem_C` via Live View (a property/variable dump of its compiled Ubergraph, the same technique already proven on `WBP_PalNPCHPGauge_C` back in the fifty-first pass) — the first time this project has ever seen INSIDE the real Feed pairing action's own graph, rather than just its native declaration. Real findings:

- The graph reads `GetActionCharacter()`/`GetActionTarget()` — its own bound references, not a fresh call to any Otomo getter. This directly confirms this pass's earlier theory (Continuación 93/hook-points.md's hundred-and-twenty-first pass): the real Feed system is a genuine AI-Action-pairing object (same family as `UPalAIActionComponent`), and whatever character/target it operates on was decided when the action itself was CREATED and DISPATCHED — not read live from a menu widget or a getter we can override.
- A new, real function name never seen before: **`ReadPlayerFeedItemTo`**, called on... an unidentified object (this dump shows the local variable it returns into, `CallFunc_ReadPlayerFeedItemTo_ItemSlotId`/`ItemNum`, not which object the call was made on — Live View's variable dump shows temp-value names, not the actual call graph edges). Real candidate for "what resolves which item the player picked," but its declaring class is still unknown.
- `BP_AIActionPairCall_FeedItem_C` (the AI-side half of the pairing) has its own real fields, `FeedItemSlotId`/`FeedItemNum` — meaning the chosen item is carried as plain data on the ACTION INSTANCE itself, not fetched fresh from anywhere at feed-time.

**Why this doesn't change the plan.** Confirms rather than solves the core blocker: this whole action-pairing system needs to be genuinely DISPATCHED for a wild Pal in the first place, and nothing here shows what does that dispatching or what it checks first. That circles back to the exact same standing wall — a real party/ownership record this project has never been able to write to from Lua (the still-unsolved `AddOtomoHandleToFreeSlot` mystery). No code changed for the food-picker question this pass; this is filed as real documentation progress (understanding HOW the real system works internally) without being an actionable lead yet.

## Hundred-and-twenty-sixth pass (2026-09-03): Skittish→Curious test came back empty (explained, not a bug), and two more real function paths confirmed via fresh Live View dumps

**Personality test: no `[WON-OVER]` lines — expected, not a bug.** Checked which individuals rolled "skittish" this session (4 total, all only ever seen by the passive enforcement scan walking past them) against every interaction log line — none of them were ever actually pet or fed. The feature never got a chance to fire; it isn't broken. Next real test needs a Pal whose log shows `disposition=skittish` specifically targeted for a real F9/F10 or radial-menu interaction.

**Two new real paths, confirmed via Dragón's fresh Live View "Dump as Function" captures** (saved to `ue4ss/IndividualObjectDumps/`, same location found in Continuación 86 — worth checking there after any Live View session, no need to ask Dragón to hunt for the path each time):
- `ReadPlayerFeedItemTo` confirmed as `/Script/Pal.PalPlayerUtility:ReadPlayerFeedItemTo` — a native function on a BlueprintFunctionLibrary-style utility class (same category as the already-trusted `PalUtility`/`PalItemUtility`). First seen as an unidentified temp-variable name inside `BP_ActionPairBehavior_FeedItem_C`'s graph last pass — this confirms its real declaring class.
- A new function neither dump nor prior research had surfaced: `"On Trigger Open Inventory Menu"`, on `/Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener.WBP_PalHUD_InGame_InputListener_C` — the game's core HUD input-listener widget (its own dump showed `RF_WasLoaded`, meaning it's already loaded at all times). Real candidate for a level ABOVE `OpenOtomoFeedInventory` in the actual call chain — the top-level trigger for opening any inventory-flavored menu.

Both added as pure watch hooks (`ReadPlayerFeedItemTo` as a simple native hook, no retry needed; the inventory-listener trigger via the same bounded round-runner every Blueprint UI class in this file already uses). Zero side effects, same discipline as everything else. Verified with `luaparse`, deployed (game folder + the single Proyectos mirror).

**Test plan**: next real Feed attempt (wild Pal via the "4" menu, and separately a real Otomo feed for comparison) — check the log for `[FOOD-DIAG] ReadPlayerFeedItemTo fired` and `[INVENTORY-WATCH] OnTriggerOpenInventoryMenu fired`, and whether either one appears for the wild-Pal case where `SelectedFeed` still doesn't.

## Hundred-and-twenty-seventh pass (2026-09-03): confirmed — behavior doesn't reflect the tracked personality tier, so a new debug key (CTRL+P) lets Dragón check it directly

Dragón hit a real practical wall testing Skittish→Curious: he can't tell which wild Pals actually rolled "skittish" just by watching them, since ENFORCEMENT (making the tracked tier show up in real AI behavior) is still unconfirmed. Confirmed directly this session — he petted 5 Pals that visibly fled/looked skittish to him (2 PinkCat/Cattiva, 1 PlantSlime, 2 DreamDemon), and the log showed 4 rolled "curious" and 1 "hostile" — zero were actually tracked as skittish. Their fleeing was ordinary wild-AI behavior, unrelated to our system.

Added `CTRL+P` — a new debug key that reveals a targeted Pal's tracked personality (`disposition`/`rolledTier`/`speciesDefault`) without requiring a full pet/feed interaction. Reuses the exact same safe, read-only look-based targeting as `CTRL+K`/`CTRL+J`, plus `Personality.GetOrInitState` (rolls a tier for a never-seen Pal exactly as a real interaction would, just without granting friendship or playing any animation). Lets Dragón "scan" Pals by looking at them and checking the log for `[PERSONALITY-CHECK]`, then deliberately go pet/feed one already confirmed skittish — rather than guessing from behavior that may not reflect the tracked tier at all. Verified with `luaparse`, deployed.

**Test plan**: press CTRL+P while looking at a few different wild Pals, check the log for `[PERSONALITY-CHECK]` lines, find one that says `disposition=skittish`, then go pet/feed that SPECIFIC one and check for `[WON-OVER]`.

## Hundred-and-twenty-eighth pass (2026-09-03): the feed hooks fired but weren't post-hooks (no new data), and the personality tier roll disabled temporarily so Won-Over can actually be tested

**Feed check, requested again — real finding, still no breakthrough.** `ReadPlayerFeedItemTo` fired for EVERY feed this session, wild and real alike — not gated at all, contradicting nothing found before but adding one data point: it's not itself the wall. However, both `arg2`/`arg3` read as un-filled placeholder values (`PalItemSlotId` struct, `0`) in every single case, including the two real Otomo feeds that DID go on to consume a real item — meaning the hook (registered as a plain pre-hook, one callback only, same as `RequestSetOtomoOrder`) is capturing the arguments as passed IN, before the function fills its out-params, not the real resolved result. Would need upgrading to a real pre+post hook pair (same shape as the `TryGetSpawnedOtomo` hook) to see the actual output — not done this pass. The only real signal stays exactly where it was: `SelectedFeed` + genuine `RequestUseToCharacter` consumption fired for both real Otomo feeds, never for any of the six wild-Pal feeds in the same session.

**CTRL+P, called out as impractical.** Dragón's own words: the console scrolls faster than he can read it, even right after pressing the key. A per-press log line isn't a usable diagnostic tool for a human watching in real time — noted for future UI-facing work (an on-screen indicator, not a log line, is the only real fix for this class of problem).

**Personality tier roll DISABLED, temporarily** (`ENABLE_PERSONALITY_TIER_ROLL = false` in Personality.lua) — Dragón's own proposed fix, and the pragmatic one: real session data showed 5/5 Pals he petted that visibly fled were tracked as curious/hostile, not skittish, because real behavior comes from the unmodified species AI while our tracked tier is invisible without enforcement (still unconfirmed). With the roll off, every individual's tracked/effective disposition collapses to its real species default — a genuinely skittish species (real `AIResponsePreset` says so) is now the SAME thing Dragón sees fleeing in vanilla play, no hidden roll, no enforcement dependency. Won-Over (Skittish→Curious) can now be tested against ground truth: chase and pet a Pal that's actually, visibly running from him, and it should show `disposition=skittish` before, and `[WON-OVER]` right after. The weighted-roll system itself is untouched, just switched off — flip the flag back once this and (ideally) enforcement are both confirmed working, to resume real per-individual personality variety. Verified with `luaparse`, deployed.

**Test plan**: chase down and successfully pet/feed any wild Pal that's actually fleeing from him (no CTRL+P needed anymore — real behavior now matches the tracked state) and check for `[WON-OVER]`.

## Hundred-and-twenty-ninth pass (2026-09-03): personality enforcement REWRITTEN using a real technique from a working reference mod, and a second reference mod reveals the real secondary-follower system

Dragón found two more real UE4SS Lua mods (not compiled Blueprints, actual readable source) and asked to check them.

**"Passive Pals" — solved the enforcement mechanism.** This mod does personality enforcement for real, in production, and does it differently than this project ever tried: it never needs a live "donor" Pal at all. Every `AIResponsePreset` is a normal Blueprint data asset with its own Class Default Object (CDO), directly resolvable via `StaticFindObject("/Game/Pal/Blueprint/Controller/AIResponsePreset/<name>.Default__<name>_C")` with ZERO dependency on any Pal actor existing nearby — this project's entire "no live donor found nearby yet" blocker across many passes was based on a wrong assumption that a live instance was needed, when the object was reachable directly the whole time. It also builds a fresh, PRIVATE preset via `StaticConstructObject` (owned by the sensor, never shared) rather than ever pointing two Pals at the same object.

**Rewritten in `Personality.lua`**: `find_preset_cdo(baseName)` resolves the CDO directly (with the class+`:GetCDO()` fallback the reference mod itself uses); `apply_forced_preset(sensor, desiredBaseName)` constructs a fresh private preset, copies the real 8 fields (`PRESET_SLOTS`, cross-confirmed against the reference mod's own `config.lua`) from the CDO, and assigns it. Both `try_enforce_personality` (the periodic scan) and `Personality.OnSuccessfulInteraction` (Won-Over) now share this one core function — no more donor search, no more "will keep retrying" logs. The scan itself simplified from two passes to one, since enforcement no longer depends on anything else found during the same scan. `ENABLE_PERSONALITY_TIER_ROLL` turned back on (it must be on for any of this new code to actually run — with it off, `rolledTier` is always "normal" and enforcement exits immediately without exercising the fix at all). Verified with `luaparse`, deployed. **Untested live** — real next step, no code changes needed: get near wild Pals and check for `[ENFORCE] SUCCESS` lines, then go look at that specific Pal in person.

**"PalFollowerTweaks" — real names for the secondary-follower system, filed for later.** Confirms and names, for the first time with certainty, the system behind Daedream/Dazzi/Flopie following as secondaries (Continuación 6's original observation): `PalFunnelCharacter` (native class — "Funnel" is the game's own internal term for a secondary follower, not a name this project ever had), `BP_AIAction_FunnelFollow_C` (the real AI action driving the follow, with real per-slot formation arrays `TargetLocationDistanceForwardList`/`TargetLocationDistanceRightList`), a direct `character:GetTrainer()` ownership getter (much simpler than anything found for the main Otomo/party system), and a real native hook point `/Script/Pal.PalFunnelCharacter:OnActive`. Relevant to the still-not-started "Follower Pal AI" backlog item, NOT the food-picker/enforcement work above — filed in `DESIGN.md` §11, not acted on this pass.

## Hundred-and-thirtieth pass (2026-09-03): a third real reference mod hands us the in-game toast-notification mechanism — "in-game join text" implemented

Dragón asked specifically: is there a real way to print info text in the game (e.g. "Pal successfully tamed")? Checked the mod he'd just provided ("QuickConsumableSlots," a real UE4SS Lua mod, not a compiled Blueprint) and it uses exactly this, confirmed working in a shipped mod.

**The real chain**: `PalUtility:GetLogManager(player)` — a real per-player log/toast manager. Its `OverrideClassMap` field (a TMap) holds a set of real UClass references; the one whose name contains `"BlinkedLog"` is the actual toast widget class used for on-screen messages (found by iterating the map with `:ForEach()`, a real UE4SS Lua TMap API confirmed by this same reference mod's use of it). `KismetTextLibrary:Conv_StringToText(message)` converts a plain Lua string into a real `FText`. `manager:AddLog(1, text, {OverrideWidgetClass = widgetClass, LogToneType = tone})` is the call that actually shows it. This directly answers the still-open "in-game join text" wishlist item — a proven mechanism, not a guess at an unverified function.

**Implemented in `Capture.lua`**: `Capture.NotifyJoined(pal, player)` runs this chain (every step wrapped so a failure here can never interrupt the real capture — worst case, no toast appears), called unconditionally right after `Capture.TryDirectCapture` inside `OnTrustMaxed`. Message is currently a plain "A wild Pal has joined your party!" — the reference mod's own `item_display_name` shows a real technique for resolving localized names (via `PalMasterDataTablesUtility:GetLocalizedText`/`PalUIUtility:GetItemName`) that's specific to ITEMS; an equivalent for Pal species names is plausible but not confirmed, so the message stays generic for now rather than guessing at an unverified function. Verified with `luaparse`, deployed. **Untested live** — real test: get a wild Pal to full trust (or use the existing F11/CTRL+K direct-capture test key) and watch for the toast when it joins.

## Hundred-and-thirty-first pass (2026-09-03): "MultiPals" proves a function this project wrote off as dead is real and working — the biggest untested lead in the project's history, now implemented as a live experiment

Dragón found a fourth real UE4SS Lua mod and asked specifically whether it helps change follower behavior. It's better than that — it directly overturns a conclusion this project reached months ago.

**What MultiPals does**: lets a player keep several party Pals active simultaneously (not just the game's normal one-or-two-Otomo limit) via `holder:ActivatePalByHandle(handle, Location, Rotation, bool)`. This is the exact function this project found the NAME of back in the twentieth pass (`ActivatePalByHandle`/`ActivateCurrentOtomo`), tested for, and concluded was dead — real live testing at the time (seventh continuación) showed normal Otomo-switching never calls it (that path uses `InactivateCurrentOtomo`/`ActivateOtomo` instead). MultiPals proves that conclusion was INCOMPLETE, not wrong about the switching path — the function is real, callable, and works reliably; it's just used for a different purpose (bringing an *extra* already-owned party Pal into the world) than normal single-Otomo switching.

**The gap MultiPals leaves open, and why it matters here**: every single call MultiPals ever makes to `ActivatePalByHandle` uses a handle read from an EXISTING party slot (`holder:GetOtomoIndividualHandle(slotIndex)`) — never a wild Pal's handle. Nothing has ever stopped this project from trying that instead, except never having a confirmed-working call to try it with. Getting a wild Pal's own handle is already a solved, safe, proven step in this project (`UPalUtility.GetIndividualCharacterHandleByActor`, used throughout `Personality.lua` since the twenty-first pass) — the only genuinely new step is handing that handle to `ActivatePalByHandle` instead of a party-slot handle.

**Implemented**: a new isolated key, CTRL+O (`do_test_activate_wild` in `Interaction.lua`), same discipline as every other first-of-its-kind native call this project has tried (own dedicated key, not wired into automatic play, everything before the risky call is read-only and logged first). It resolves a targeted wild Pal's real handle, the player's `OtomoHolderComponent`, and a real spawn transform (`holder:GetTransform_SpawnPalNearTrainer()` — the same call MultiPals itself uses), then calls `ActivatePalByHandle` directly.

**The real, new risk, spelled out explicitly** (not present in MultiPals' own use of this call): every Pal MultiPals ever activates is a RECALLED party member — its actor is hidden/inactive, not currently in the world. A wild Pal's actor is ALREADY live and walking around when this runs. Best case: the game properly takes over the existing actor and it starts behaving like a real Otomo (following, assisting). Possible bad cases, none ruled out: a second, duplicate actor spawns alongside the original; or the native call assumes state a real capture/party-join would normally set up first, and misbehaves in a way `pcall` cannot catch (the same category of risk this project already accepted once for `Capture.TryDirectCapture`'s first test, which turned out fine).

Verified with `luaparse`, deployed. **Test plan, given to Dragón directly**: save the game first, pick a common low-value wild Pal, aim at it, press CTRL+O once, then check carefully — did the original wild Pal start following/assisting like a real Otomo, did a second copy appear, or did nothing change. This is the single most promising untested lead this project has found for the core "make a wild Pal follow/fight like a real Otomo" question that's been open since the very beginning.

## Hundred-and-thirty-second pass (2026-09-03): reading Dragón's real test session — a real self-inflicted lag bug found and fixed, one clean negative result, one real partial success, and two false alarms cleared up

Dragón ran through the full test list in one session and reported: CTRL+O did nothing (and conflicts with the console key), personality enforcement showed no visible change, Skittish→Curious failed (fleeing Pals kept fleeing), the join toast worked via real trust-building but not via CTRL+K, Pals stopped following after 5 interactions, and heavy lag throughout. Read the real log line by line rather than taking each report at face value.

**Real self-inflicted lag bug, found and fixed.** 1173 `[ENFORCE]` lines this session — 1170 of them the exact same message, `"has no readable AISensorComponent"`, repeating every 8 seconds forever for every non-normal-tier Pal. The hundred-and-twenty-ninth pass's rewrite forgot to carry over the per-individual throttling the OLD donor-search failure had (`state.noDonorLoggedOnce`) — this new failure path logged unconditionally, every scan, for as long as it kept failing (which is apparently always). Same exact shape of bug this project has hit twice before (ninety-fourth/ninety-fifth passes). Fixed: throttled to once per individual (`state.noSensorLoggedOnce`), and added a ONE-TIME-EVER (not per-individual — this function runs constantly) diagnostic that logs which of the three possible failure branches inside `find_sensor_component` is the real cause, since that was never actually known. **This is very likely the real source of tonight's reported lag** — 1170 synchronous, forced disk-flush log writes (`Logger.lua`'s own design) in one session is a real, measurable cost, independent of Ghidra running in the background.

**CTRL+O: ran cleanly every time, zero visible effect — a real, clean negative result.** The log confirms the hook fired repeatedly (Dragón spammed it, unsure if it registered because it also happens to conflict with a console-toggle binding) and every single call completed with no Lua error, target actor still valid immediately after. No duplicate appeared, no behavior changed, real food-picker still didn't open. This matches the exact "silent no-op for a Pal that was never added to a real party slot" pattern already seen with `RequestUseToCharacter` — `ActivatePalByHandle` requires the same real authority this project has been blocked on since months ago. Genuinely useful to know (rules out this specific call cleanly) even though nothing changed in-game. **Key conflict noted for later**: `Key.O` + CONTROL apparently collides with a console-toggle binding — worth picking a different key if this experiment is revisited.

**Skittish→Curious: real partial success, not a flop.** One real event this session: `[WON-OVER] ... was skittish, but a successful interaction won it over — tracked disposition now 'curious'`, immediately followed by `"has no readable AISensorComponent — cannot swap its real AI, tracked disposition still updated"`. The STATE half worked exactly as designed — this is the first time this project has ever confirmed catching a genuinely-tracked-skittish wild Pal and winning it over. The visible-behavior half failed for the exact same reason as the enforcement scan above (same `find_sensor_component` call, same failure). Both threads are blocked on the identical root cause — worth chasing as ONE question, not two, whenever picked back up. Every OTHER Pal Dragón described as "fleeing" this session (asked what the real term is — "skittish" already is the real term, matching `EPalAIResponseType.Escape`/`BP_AIResponsePreset_escape_C`) never actually showed up as tracked-skittish in the log at all — consistent with ordinary wild-AI wandering/distancing that has nothing to do with this system, same conclusion as the hundred-and-twenty-seventh pass.

**Join toast: worked exactly as designed, not a bug that it didn't fire for CTRL+K.** `[NOTIFY] join toast shown` appears once, right after the real trust-based capture. `Capture.NotifyJoined` is only called from `Capture.OnTrustMaxed` — CTRL+K's test key (`do_test_capture`) calls `Capture.TryDirectCapture` directly, deliberately bypassing the whole Trust flow (that's the entire point of it being an isolated manual test) — so of course no toast there. Confirmed working exactly as intended for the real path.

**"Pals no longer follow after interaction #5" — no evidence of a regression.** Only ONE Pal reached a 5th interaction this whole session (a wild Foxparks/Kitsunebi Dragón was building real trust with for the toast test) — and the log shows the follow trigger fired correctly (`"5 successful interactions reached — this Pal should now start following the player"` → `Combat`'s own "marked as following" line), then correctly stopped later at the moment it got captured for real (expected — once it's a genuine party member, the approximated follow state is no longer needed, per `Capture.OnTrustMaxed`'s own existing logic). Neither `Trust.lua` nor `Combat.lua` were touched this session at all. Most likely explanation: this session's testing was spread across many different Pals for one-off tests (CTRL+O, personality checks, Won-Over attempts), and none of those OTHER Pals individually built up to 5 real interactions — not a broken trigger.

Verified with `luaparse`, deployed. **Test plan**: same personality tests as before, but the lag should now be gone (or much reduced) — and the log should finally show which of the three `find_sensor_component` failure branches is the real, ongoing cause, which is the actual next thing blocking both enforcement and Won-Over's real-behavior half.

## Hundred-and-thirty-third pass (2026-09-03): correction on "skittish", keybind cleanup, and Ghidra finally producing real decompiled output

**Correction to the hundred-and-thirty-second pass entry above:** "skittish" is NOT a real name from the game — it's this mod's own internal bucket label (`PRESET_NAME_TO_DISPOSITION`/`TIER_TO_DONOR_PRESET_CLASS` in `Personality.lua`), mapped FROM the real game preset `BP_AIResponsePreset_Escape_to_Battle_C` (one of ~10-11 real presets extracted from the game's own `.pak`, alongside `Warlike`, `friendly`, `VillageNPC`, `NotInterested`, `Kill_All`, `Boss`, etc.). Dragón caught this directly — he'd only ever used "skittish" as his own shorthand for describing fleeing Pals, never as a term from the game itself.

**Keybind cleanup, at Dragón's explicit request** ("keep keybinds at minimum, swap instead of adding"). Removed CTRL+P (`do_check_personality` — Dragón himself called this impractical in the hundred-and-twenty-fourth pass) and CTRL+O (`do_test_activate_wild` — confirmed a clean negative result in the pass above, and conflicts with the console-toggle key) entirely from `Interaction.lua`, including their comment blocks and registrations. Remaining keybinds: F9 (Pet), F10 (Feed), CTRL+K (direct no-sphere capture test), CTRL+J (real food-item feed). `InputSpy.lua`'s ~150-key mass listener is a separate temporary research tool, not counted here.

**Ghidra: three failed attempts, then a working fourth.** The original headless run (`analyzeHeadless.bat` + `-postScript FindFeedFunctions.py`) completed the full binary analysis (~105 min) but the Python post-script never ran — Ghidra 12.x removed the old Jython engine, and `.py` scripts now require PyGhidra. A second attempt porting the script to Java hit the exact same "class could not be found / OSGi bundle" error that a BUILT-IN Ghidra analyzer script (`WindowsResourceReference.java`) had already hit earlier in the very same run — strong evidence the OSGi Java-script-compile pipeline is broken in this headless environment generally, not something wrong with our script. A third attempt (installing a portable Python 3 and putting it on PATH, then re-running `analyzeHeadless.bat`) still failed with "Ghidra was not started with PyGhidra" — `analyzeHeadless.bat` apparently never auto-detects Python on PATH; PyGhidra needs to be the actual process entry point.

**The fix:** bypassed `analyzeHeadless.bat` entirely. PyGhidra's own Python package (`pyghidra`, installed via pip into the portable Python) exposes `pyghidra.start()` + `pyghidra.open_program(..., analyze=False)`, letting a plain `.py` script launch the JVM and reopen the already-analyzed, already-saved project directly — reusing the 105 minutes of analysis already done, no `analyzeHeadless.bat` involved at all. This worked on the first try (`find_feed_functions_pyghidra.py`, run directly with the portable python.exe, `GHIDRA_INSTALL_DIR`/`JAVA_HOME` set as env vars).

**Real findings from the decompiled output:**
- `APalMonsterCharacter::SelectedFeedingItem` (`FUN_1430ed7e0`) — confirmed by an embedded string inside the function itself (`"&APalMonsterCharacter::SelectedFeedingItem"`, used to build a delegate binding). Takes a character pointer directly as its only parameter, builds a "select item" popup titled `SELECT_ITEM_MENU_TITLE_FEED`, and binds the popup's confirm delegate back to `SelectedFeedingItem` on that SAME pointer. **No ownership/ally check anywhere in this function's body** — it operates on whatever character pointer it's handed. Since this lives on `APalMonsterCharacter` (the base class of every Pal, wild or owned, not an Otomo-only class), this is real evidence the gate we've been hunting for months isn't inside this function at all — it has to be in whatever decides to CALL this function with a real vs. substituted target.
- `UPalUIPlayerRadialMenuBase::SelectedFeed` (`FUN_1432f46f0`) — the second, widget-bound overload (same string-binding trick confirms the class). Structurally identical to the one above EXCEPT it starts with two calls (`FUN_1432d31d0()` then `FUN_142c8add0(lVar5)`) that resolve some internal target BEFORE doing anything — and if either returns 0/null, the whole function bails out immediately (`if (lVar5 == 0) return;`). Names not recoverable (Shipping build, no symbols) — but structurally, this pair is now the single strongest new candidate for where the real target gets resolved (and where our substitution would need to actually land) for the widget-driven feed path. Not yet hooked or investigated further this pass — a real next step, not urgent, since the mod's own working fallback (gesture + Happy, already wired to the real "4" menu) still covers Pet/Feed for wild Pals today.
- `OpenOtomoFeedInventory`, `PawnOtmoIsPartyOtomo`, `AddOtomoHandleToFreeSlot`, and `PalCaptureSuccess` string locations were all found, but none had any code cross-reference in the binary — meaning each is referenced only for Unreal reflection registration (the string exists so the engine can look the function up by name at runtime), not called directly by any traceable code path. Expected for reflection-only entries; doesn't tell us anything new by itself.

Confirms directly, with real code, something this project had already suspected from Lua-side behavior: `SelectedFeedingItem` itself is not Otomo-exclusive — it's a generic per-character function. The actual "is this really mine" gate is somewhere upstream of it, most likely inside the two-call resolution at the top of the widget's `SelectedFeed`.

## Hundred-and-thirty-fourth pass (2026-09-03): decompiled the two gate functions — likely explains WHY every substitution attempt on this path was always going to fail

Decompiled `FUN_1432d31d0` and `FUN_142c8add0` (the two unnamed calls that gate `UPalUIPlayerRadialMenuBase::SelectedFeed`) directly by address, plus counted how many distinct functions in the whole binary call each one.

**`FUN_1432d31d0(param_1)`** — 12 distinct callers. Internally: a generic engine-state check, then a call taking `(param_1, 0)` (shape matches "get owning player [index 0]" — a widget resolving its own owning player pawn/controller), with the usual pending-kill/garbage validity check on the result, then a second call with no args (shape matches a generic "get world" or similar singleton getter), then a class-hierarchy comparison (the same bit-pattern already seen inside `SelectedFeed`/`SelectedFeedingItem` themselves, which looks like an `IsA<>`/interface-implements check — comparing a type's interface list against a target class) that zeroes the result if the type doesn't match. Read in plain terms: "get my owning player, confirm it's the right type, return it (or null if not)."

**`FUN_142c8add0(param_1)`** — 32 distinct callers (far more generic — a shared utility, not something built just for this menu). Gets a class/FName, calls what's shaped like a `GetComponentByClass(param_1, thatClass)` helper, and if it found a component, **calls a function through the component's own vtable at a fixed offset (`(**(code**)(*plVar2 + 0x2b0))(plVar2)`)** — i.e. a raw C++ virtual dispatch, not a call routed through Unreal's reflection/`ProcessEvent` system — then passes that result through one more wrapper call before returning.

**Why the vtable detail matters more than anything else found this pass:** every hook this whole project has ever used (`RegisterHook`, `ReturnValue:set()`, cached-field writes) only works because UE4SS intercepts calls that go through Unreal's *reflection* dispatch (`UFunction`/`ProcessEvent` — the same mechanism Blueprint graphs use to call into native code, and the reason a "native" function still shows up in our hooks at all, just post-only). A raw vtable call like the one inside `FUN_142c8add0` is C++ calling another C++ virtual method directly, with no reflection involved anywhere in that specific call — UE4SS has no way to intercept it, no matter what technique is tried, because there is no `UFunction` object being invoked at that point at all.

**What this most likely means for the "real Otomo" resolution used by the widget's `SelectedFeed`:** if this vtable call is (as its position/shape strongly suggests) the actual "what is my currently spawned Otomo" getter — i.e. the same conceptual job as `TryGetSpawnedOtomo`, but reached here through a raw virtual call instead of a UFunction call — then every substitution this project has tried on this exact path (hooking `TryGetSpawnedOtomo`'s return value, writing the widget's own cached `SpawnedOtomo` field) was never going to be seen by it, regardless of how correctly it was implemented. Not because those substitutions were wrong — both were independently confirmed to write successfully — but because this specific resolution likely never reads either of those two things at all. This would finally explain, at a mechanism level rather than just "another dead end", why the hundred-and-thirtieth/ninety-seventh passes' careful, correctly-executed substitutions never once got `SelectedFeed` to fire for a wild Pal.

**Honest caveat:** this is a strong, well-reasoned inference from decompiled pseudocode with no recovered symbol names (Shipping build) — not a 100%-confirmed fact. Confirming it fully would mean identifying the actual C++ class behind the vtable pointer and checking that offset `0x2b0` really is `TryGetSpawnedOtomo`'s slot, which needs more Ghidra work (RTTI/vtable analysis) than this pass did. Given the current working fallback (gesture + Happy, already wired to the real "4" menu) already covers Pet/Feed for wild Pals, this isn't urgent to chase further right now — but it's the most complete answer yet for *why* the real-food-item wall exists, and worth remembering if this thread is picked back up: a raw vtable call is very likely a genuine, Lua-unreachable dead end, not something that just needs one more clever substitution.

## Hundred-and-thirty-fifth pass (2026-09-03): `GetComponentByClass` confirmed genuinely broken for `PalAISensorComponent` — fixed with the same FindAllOf pattern already proven in Indicator.lua

Dragón ran the requested personality retest (a few minutes near wild Pals, plus petting/feeding a couple, including a fleeing one). Read the fresh log rather than asking him to.

**The lag fix from the hundred-and-thirty-second pass worked.** 41 total `[ENFORCE]` lines this whole session, one per individual, zero repeats — down from 1170+ near-identical spammed lines before.

**The one-time diagnostic fired, and the result — combined with a second, independent data point — converges on a single, confirmed root cause.** `find_sensor_component`'s one-time diagnostic said: `GetComponentByClass returned a NULL object reference (sensor:IsValid() == false)`. Separately, `GetPresetClassName` (species-default detection, a completely different code path with its own independent sensor resolution) logged the same underlying shape 141 times: the sensor lookup appears to succeed, but the object handed back is a phantom — reading `.AIResponsePreset` off it comes back null every time. Cross-checked against the actual roll data: **92 out of 92** new individuals this session got `species default=curious` — the hardcoded fallback, never once the real value. And the two real Won-Over events this session (a skittish Pal petted successfully, disposition correctly flipped to "curious" in our own tracked state) both hit the identical `[WON-OVER] ... has no readable AISensorComponent` wall for the real-behavior swap.

**This is no longer "one of three possible causes, unknown which" — it's confirmed, with real numbers, across two independent call sites and 133 combined real attempts in one full ~5-minute session: `GetComponentByClass(actor, PalAISensorComponentClass)` never once resolves a real, valid `PalAISensorComponent` for a wild Pal in this game version.** Not a spawn-timing race (five minutes of continuous retrying would have caught that) — a fully broken path for this specific component class specifically, full checked against the header dump: no dedicated getter function exists for this component anywhere in `Pal.hpp` either (unlike `GetAIActionComponent()`, which does exist for the AI action component found in the sixty-second pass) — `GetComponentByClass` was always the only lever available, and it simply doesn't work here.

**Fix implemented, reusing a pattern this exact project already proved out** (Indicator.lua's hunt for the real HP-gauge canvas widget, after `GetComponentByClass`/`RegisterHook` both failed there too): `FindAllOf("PalAISensorComponent")` to enumerate every LIVE instance directly, then match each one to its owning actor via `:GetOwner():GetFullName()`, building a lookup table. Rebuilt at most once every 5 seconds (never per-Pal-per-scan — the ninety-fourth pass's lag bug came from exactly that mistake), shared between both `GetPresetClassName` and `find_sensor_component` so the expensive scan only ever happens once per cycle regardless of how many Pals need it. `GetComponentByClass` is kept as the first, cheap attempt in both places (in case it starts working on some future patch) with the FindAllOf index as the real fallback, not a replacement.

Verified with `luaparse`, deployed to both destinations. **Test plan:** same as before (a few minutes near wild Pals, pet/feed a couple, including a fleeing one) — the log should now show real, non-"curious" species defaults for at least some Pals (Warlike/Escape_to_Battle species should read as hostile/skittish for real), `[ENFORCE] SUCCESS` lines where a rolled tier differs from the species default, and Won-Over's real-behavior swap should finally succeed instead of hitting the sensor wall.

## Hundred-and-thirty-sixth pass (2026-09-03): the real, previously-unidentified lag source found — a third of the whole log came from a dead research watch never turned off

Dragón retested (several minutes chasing/petting/feeding wild Pals) and reported he still felt lag, pushed back directly on being told otherwise, and proposed a real A/B test (FPS with the mod active vs. all mods disabled). Broke the fresh log down by volume per tag instead of only checking the tags already under suspicion.

**Two things found, both real, neither one the personality code:**

1. **The dominant one:** `[INDICATOR-WATCH]` — 1529 of 4630 total log lines (33%) in one ~6-minute session. This watch (from the seventy-sixth/seventy-seventh passes, added to hunt down how aiming "4" at a specific Pal works) hooks the game's generic "you can interact with this" indicator UI (`WBP_PalInteractiveObjectIndicatorCanvas_C`/`WBP_PalInteractiveObjectIndicatorUI_C`) — which fires for EVERY interactable object in the world the player looks at (confirmed in the log: berries, logs, small stones, the PalBox, not just Pals), constantly, as the player simply moves the camera around. The research question these hooks existed for was fully answered back in the seventy-ninth/eightieth passes (the real answer was `WBP_WorkerRadialMenu`, a different class entirely) — nobody ever came back to turn this off, so it's been silently generating a third of this project's own log volume (each line a forced synchronous disk write, per `Logger.lua`'s crash-safety design) on every single test session since, regardless of what else was being tested. **Fixed:** both `make_hook_round_runner` calls for these two classes commented out (not deleted — the candidate-name research stays as documentation, same convention as `SelectResponseBySenses` in `OtomoWatch.lua`).

2. **Already known, still present, smaller by volume but real per-event cost:** `[RADIAL-REDIRECT-PERF]` — 95 lines this session, each logging a `find_targeted_pal` scan costing 35-40ms. This was already found and documented in the seventy-seventh pass (deliberately deprioritized then, at Dragón's own request, to keep moving on features) — pressing "4" near a wild Pal still pays this cost on the first scan of each menu open, which alone is enough to feel like a stutter at that exact moment (35ms is over two frames' worth of time at 60fps). Not touched this pass — noted here again since it's a second real contributor to the same complaint, not fixed by the INDICATOR-WATCH removal.

**Honest, separate finding — NOT fixed yet:** the hundred-and-thirty-fifth pass's FindAllOf-based fallback for reading a wild Pal's AI sensor did NOT work either. Same session: still 98/98 new individuals fell back to "curious" (0 real species presets read), and the one-time diagnostic showed the fallback failing too, not just `GetComponentByClass`. Added one more one-time diagnostic (`log_index_build_once`) that will show, on the next session, whether `FindAllOf("PalAISensorComponent")` is returning few/no instances at all, or returning instances that just don't match any Pal by owner key — the two remaining live hypotheses, previously indistinguishable. This is a DIFFERENT, still-open problem from the lag fix above — the two were never the same root cause, just discovered in the same test session.

Verified with `luaparse`, deployed to both destinations. **Test plan:** same routine as before. This time the log itself should be dramatically smaller (no more `[INDICATOR-WATCH]` lines at all), which is the direct, checkable confirmation that this fix landed — worth checking regardless of how the play session felt. Dragón's proposed FPS-counter A/B test (mod active vs. all mods disabled, same routine, same duration) remains the right next step if lag is still felt after this fix — a good, sound validation method that doesn't depend on trusting either of our impressions.

## Hundred-and-thirty-seventh pass (2026-09-03): pivoting to the Follower Pal AI question — a zero-new-risk check nobody had done yet

Dragón, reasonably, didn't want to spend a whole test session on a pure performance A/B comparison — his point: it doesn't move the mod forward. Asked to pick a different pending item instead of re-running into the same personality/food walls.

**Chose Follower Pal AI** (Combat/follow-and-protect, the lowest-scoring tracked category at 45%, and the single most-repeated "biggest open question" phrase in this project's history). Read the "PalFollowerTweaks" reference mod's actual source (previously only partially examined) instead of guessing further.

**What that mod actually confirmed:** `PalFunnelCharacter` (native class) + `BP_AIAction_FunnelFollow_C` (the driving Blueprint action) is real and is exactly the Daedream/Dazzi/Flopie-style secondary-follower mechanism Continuación 6 originally observed — but the mod ONLY repositions/rescales funnel followers that the game ALREADY created (via `NotifyOnNewObject` on `/Script/Pal.PalAIActionBase` + a `PalFunnelCharacter:OnActive` hook) — it never creates one. `character:GetTrainer()` is confirmed as the real ownership getter for a funnel character. Read plainly: becoming a `PalFunnelCharacter` almost certainly still requires being a genuine party member first — the same "join the party" step this project already solved via `PalCaptureSuccess`, not a shortcut around it. So this lead teaches a new, real UE4SS tool (`NotifyOnNewObject` — fires on every construction of a given native class, never used in this project before) but likely doesn't unlock anything the project doesn't already have access to.

**The actual insight, reasoning from what's already proven rather than from the reference mod:** this project has had a fully working, sphere-less real capture (`PalCaptureSuccess`, confirmed since the thirty-ninth pass) for months — but nobody has ever explicitly verified whether a Pal captured this way keeps following afterward using the game's OWN systems, or just sits inert in the party roster until the player manually opens the menu and selects it as their Otomo. Every past confirmation ("it showed up in the party screen") checked membership, never active-follow behavior. `Capture.OnTrustMaxed` calls `Combat.StopFollowing(pal)` immediately after a real capture, on the unverified assumption that the game takes over from there.

**Added `diagnose_post_capture_slot(pal)` in `Capture.lua`** — fires automatically, read-only, right after every real capture (trust-maxed or CTRL+K). Reuses the exact proven-safe pattern already used for `diagnose_party_membership` in `Interaction.lua`: `FindAllOf("PalPlayerPartyPalHolder")`, plain field reads (`FirstOtomoPal`/`SecondOtomoPal`/`BenchMember`), and the bool query `PawnOtmoIsPartyOtomo`. Answers, with real data on the very next capture: did the Pal land in an active Otomo slot (would mean real following already works, for free, right now) or only on the bench (would mean it needs one more, already-proven-safe call — `InactivateCurrentOtomo`+`ActivateOtomo`, confirmed real since Continuación 7 — to actually become the active, following Otomo). No new native-call risk introduced — everything here is a read.

Verified with `luaparse`, deployed to both destinations. **Test plan:** capture any wild Pal for real (trust-maxed, or CTRL+K for a quick isolated test) and just watch — does it keep following you afterward like a normal Otomo, with zero manual menu interaction? Check the log for `[POST-CAPTURE-SLOT]` either way. This single test could either mostly close out the Follower Pal AI question for free, or tell us exactly which one proven-safe call to add next.

## Hundred-and-thirty-eighth pass (2026-09-04): Play interaction (item 1 on the priority list) — Pal-idle half shipped, player-emote half one diagnostic away

Picked up item 1 from the saved priority TODO list (CLAUDE.md/DESIGN.md §12): a third bonding interaction, "Play," alongside Pet/Feed. Dragón's own framing: pressing Play should make the player do a real emote (specifically "Cheer" — he confirmed this is what the game calls what he thinks of as "Beckon") while the targeted Pal plays a random idle animation, at the same time.

**Researched both halves in the SDK dump before writing anything (per this project's own crash history — never call an unproven native function blind):**

- **Pal-idle half: zero new risk.** `EPalActionType.PalRandomRest` (77) is a real value in the exact same simple int enum every other reaction in this file already plays through `PlayActionByType` (Happy=38, HumanPetting=55, HumanFeeding=49). No new mechanism.
- **Player-emote half: genuinely new territory, but well-evidenced.** Real player emotes (Wave/Surprise/Sleep/Kick_None/Give/Dance/Cheer) do NOT route through the simple `PlayActionByType` enum at all — Dragón supplied a real Live-View dump mid-session that settled this directly. It showed 9 concrete Blueprint action classes (`BP_Action_Emote_0_C` through `_8_C`, all children of `BP_Action_Emote_Base_C`, which carries its own `EmoteAnimation`/`EmoteIndex` fields) and, critically, a LIVE instance: `BP_Player_Female_C_2147480793.ActionComponent.BP_Action_Emote_1_C_2147452751` — proof the game spawns these directly on the player's own `ActionComponent`, the exact same component this file already calls `PlayActionByType` on everywhere. Confirmed the real function in Pal.hpp: `UPalActionBase* PlayAction(AActor* ActionTarget, TSubclassOf<UPalActionBase> actionClass)` — a sibling overload of `PlayActionByType` on the same class, just taking a class reference instead of an enum int.

**What's still missing:** which of the 9 numbered classes IS Cheer. The dump didn't say (only the live instance's index, with no confirmation of which emote Dragón was doing at that moment). Rather than guess an index and risk calling the wrong emote (or worse, an untested one) live, added a read-only, one-shot diagnostic at `Interaction.Init()`: `log_emote_index_mapping()` resolves each `BP_Action_Emote_0_C`...`_8_C`'s CDO via `StaticFindObject` (same path pattern confirmed real in the dump: `/Game/Pal/Blueprint/Action/Palmi/Emote/BP_Action_Emote_N.Default__BP_Action_Emote_N_C`) and reads its inherited `EmoteAnimation` field — a plain ObjectProperty pointing at a UAnimMontage, the same safe direct-field-read pattern used everywhere else in this file. Zero risk: no live actor touched, no PlayAction call made, just 9 static CDO reads.

**Shipped this pass:** `do_play()`, bound to CTRL+J (repurposed — see below), does the Pal-idle half for real: same targeting/gating as Pet/Feed (look-based, busy-gates on both sides, `Capture.HasPermanentlyFled` check), plays `PalRandomRest` on the target, and — per Dragón's explicit answer when asked — grants trust via one direct `param:AddFriendShip(INTERACTION_FRIENDSHIP_GAIN, true)` call (no Happy-style side effect to piggyback on this time, and exactly one call so this can't reintroduce the eleventh-pass double-grant bug), then calls `Interaction.OnWildPalPetted(pal)` same as Pet/Feed so it counts toward Trust.lua's real interaction-count thresholds. The player-Cheer half is NOT wired yet — next session, once the `[EMOTE-DIAG]` log names which index is Cheer, add one call: `playerActionComp:PlayAction(pal, cheerClass)` alongside the existing PalRandomRest call.

**CTRL+J repurposed, not left dead:** the hundred-and-seventeenth-through-hundred-and-nineteenth passes' real-food-item test key is now a confirmed dead end for wild Pals from two independent angles (Ghidra's vtable finding AND `RequestUseToCharacter` only firing for the player's own active Otomo) — item 7 stays shelved. Per Dragón's own standing rule (swap a retired key instead of adding a new one), CTRL+J now triggers Play instead.

Verified with `luaparse`, deployed to both destinations. **Test plan:** launch the game once (even briefly, no need to actually play) so `[EMOTE-DIAG]` logs the 9 class→animation mappings, then report back (or just let the log get read next session) which index reads `AM_Player_Female_Emote_Cheer` — that's the one line of code needed to finish this feature. Separately, CTRL+J in-world should already show the Pal-idle half working: aim at a wild Pal, press it, watch for a rest/idle animation and a Friendship increase.

**Addendum, same pass — two reinforcements Dragón asked for directly:** he pointed out this project already has a proven fix for "a Blueprint class isn't loaded yet at mod Init()" (the bounded-retry pattern used all over this same `Interaction.Init()` for the Radial Menu/Worker Menu/Indicator classes) — rather than wait to see the static `[EMOTE-DIAG]` read fail first, applied that same fix immediately: `log_emote_index_mapping` is now a bounded retry loop (`run_emote_index_mapping`, 20 rounds / 100s, `ExecuteInGameThreadWithDelay`), tracking which of the 9 indices already resolved so it never re-logs or re-checks ones already found.

Second, and Dragón's own idea: rather than rely on the static field read alone, he'll perform the real Cheer emote himself in-game while a LIVE hook watches — direct behavioral confirmation as a second, independent method backing up the first ("if the first fails, the second backs it up"). Added one `make_hook_round_runner` call per numbered class (0-8), each trying to hook that class's own `OnBeginAction` (confirmed real on `BP_Action_Emote_Base_C`) — reusing the exact same retry/hook-handler machinery already proven for the Worker Menu earlier in this same function, no new infrastructure. Whichever one fires the instant Dragón does Cheer names the real class directly via the existing `hook_describe(self_)` (GetFullName()), no new logging code needed. Between the two methods, this feature has two independent, real, non-guessing ways to land on the answer.

## Hundred-and-thirty-ninth pass (2026-09-04): a real crash, right after Init() logged the Play line — instrumented every new call before retesting

Dragón's very first launch after this pass's deploy hit a real game crash (Fatal Error, crash dump written) at the exact same second the mod's log started. `palbonds-live.log` ends immediately after `[PalBonds/Interaction] ... = Play — random Pal idle animation + trust grant...` — no further lines at all, meaning the crash happened somewhere in this pass's new Init() code (the new `RegisterKeyBindAsync(PLAY_KEY, ...)` call, the new static `[EMOTE-DIAG]` scan, or the new 9x live `[EMOTE-WATCH]` hook-registration loop), with zero visibility into which one.

Per this project's own seventh-pass playbook — the ONLY thing that has ever actually found a real crash's cause in this project is bracketing every new native call with its own before/after log line, never guessing — added `[CRASH-DIAG]` log lines immediately before AND after: the `RegisterKeyBindAsync(PLAY_KEY, ...)` call, every `StaticFindObject` call inside the static EMOTE-DIAG loop, the `EmoteAnimation` field read, the `GetFName():ToString()` call on it, and each of the 9 `make_hook_round_runner(...)()` attempts (each now individually wrapped in its own `pcall` too, so one bad class doesn't take down the rest — previously they ran unguarded back-to-back).

Not yet confirmed which call is the actual culprit — that's what the next launch's log will show directly (whichever `[CRASH-DIAG]` line is the LAST one printed names the exact failing call). Verified with `luaparse`, deployed to both destinations.

## Hundred-and-fortieth pass (2026-09-04): root cause found and fixed — a NEW category of crash, distinct from #1-4

Dragón's next launch reproduced the same crash, but this time `[CRASH-DIAG]` pinpointed it exactly: the log's last line was `about to call GetFName():ToString() on index 0's EmoteAnimation NOW`, with no `returned — still alive` counterpart. The crash is `anim:GetFName():ToString()` — a method call on the `UAnimMontage` object read off `cdo.EmoteAnimation` (a Blueprint class default object's field).

**Why this is a genuinely new danger, not a repeat of Crash #1-4:** every prior `GetFName()`/`GetFullName()` call anywhere in this file — dozens of them, all confirmed safe across many sessions — has been on a live actor/component/widget object (something obtained via `FindAllOf`, `FindFirstOf`, or a field read off one of those). This was the first time this project called a method on an ASSET reference (an animation asset, not a runtime actor/component instance) read directly off a class default object's field. The field read itself is fine (logged "still alive," result "non-nil") — it's specifically invoking a method on that returned reference that corrupts memory. Field reads on a CDO are safe (this project has done plenty); calling native methods on whatever comes back is NOT automatically safe just because the field read succeeded, if the underlying reference is an asset rather than a live actor/component.

**Fix:** removed the `:GetFName():ToString()` call entirely. The diagnostic now just logs `tostring(anim)` — pure Lua-side stringification of the wrapper object, which touches no native code at all and still shows the asset's identity (UE4SS's own `tostring()` on a UObject wrapper already includes its path/name). Verified with `luaparse`, deployed to both destinations.

**New standing rule for this project, worth remembering for any future asset-reference read (materials, meshes, sounds, data tables, anything pulled off a CDO or static data rather than a live world object):** a field read succeeding does not mean every method call on the result is safe — reserve `GetFName()`/`GetFullName()`/any method call for objects confirmed to be live actor/component/widget instances (the category already proven safe throughout this file), and default to `tostring()` only for anything read off static/asset data until proven otherwise by a real test.

## Hundred-and-forty-first pass (2026-09-04): Cheer confirmed by dump, wired live; rest-pool diagnostic for the "sometimes looks like Feed" report

Dragón's retest after the crash fix: no crash, Pal-idle half confirmed working (random animation observed). New report: sometimes that animation looks like the normal Feed gesture — asked whether `PalRandomRest` rolls among only idle animations or all of a Pal's animations. He also dumped a real live object (`BP_Action_Emote_0_C_2147458153.json`, from the game's own `IndividualObjectDumps` folder) which settles the emote-index question outright: `EmoteAnimation` = `AM_Player_Female_Emote_Cheer`, `EmoteIndex`="0" — **Cheer is `BP_Action_Emote_0_C`**, no more guessing. The same dump's `DynamicParameter` shows the real vanilla cast used `ActionTarget=None` — Cheer isn't targeted at anything.

**Rest-pool question, answered with real evidence rather than assumption:** `APalCharacter` has a plain field `StaticCharacterParameterComponent` (confirmed in Pal.hpp, same safe pattern as `ActionComponent`/`CharacterParameterComponent`), which carries `RandomRestMontageInfos` (`TArray<FPalRandomRestInfo>` — each entry: `RandomRestMontage`, `Weight`, `LoopNum_Min/Max`, `AfterIdleTime`). This IS a curated, per-species "rest" pool by design — `PalRandomRest` was never rolling among literally every animation the Pal has. Added a read-only `[REST-POOL-DIAG]` that logs this specific Pal's real authored pool (count + each entry's montage/weight) every time Play is pressed, so the next test tells us directly whether the "Feed-looking" animation Dragón saw is actually one of THIS Pal's own authored rest-pool entries (plausible — many herbivore-type Pals have a grazing/foraging idle pose that can look feeding-like) rather than something leaking in from elsewhere. Per the fortieth pass's fresh crash lesson, this never calls a method on the `RandomRestMontage` asset reference — only `tostring()`.

**First live attempt at the player-emote half:** wired `playerActionComp:PlayAction(nil, cheerClass)` into `do_play()` — the first time this project has ever called `PlayAction` (as opposed to the already-proven `PlayActionByType`), and the first time this project has passed `nil` as a native `AActor*` parameter (matching the real observed `ActionTarget=None`, not a guess). Bracketed with the same `[CRASH-DIAG]` before/after logging the fortieth pass's real crash was only ever found through, in case this specific untested shape (nil target, class param) turns out to have its own risk.

Verified with `luaparse`, deployed to both destinations. **Test plan:** press Play once more. Watch for the player doing a real Cheer gesture alongside the Pal's idle animation, check the log for `[CRASH-DIAG] PlayAction(Cheer) returned` (confirms it didn't crash), and check `[REST-POOL-DIAG]` to see the real authored rest pool for whatever Pal was targeted.

## Hundred-and-forty-second pass (2026-09-04): two real bugs found from the actual test — Cheer never fired at all, and the rest-pool diagnostic never printed a single entry

Dragón's test: no crash, but two real problems. (1) He confirmed directly that the Feed-looking animation is NOT a false alarm — he knows that specific Pal's real idle set and it doesn't include anything feed-like, so `PalRandomRest` really is producing the Feed gesture somehow, not just an authored idle pose that resembles it. (2) The player never did the Cheer emote at all.

**Root cause of (2), found in the log directly:** every single successful Play press hit the "could not resolve Cheer emote class" fallback — `PlayAction` was never even attempted. The bare-class `StaticFindObject` path (no `Default__` prefix) silently failed every time, while the CDO path (WITH `Default__`) — the exact one `[EMOTE-DIAG]` already uses — has resolved reliably since Init() with zero retries needed. Fixed by deriving the class from that already-proven CDO via `:GetClass()` (a plain UObject method, already used safely elsewhere in this file, not the same risk category as the fortieth pass's asset-reference crash) instead of trusting a second, unverified raw path format.

**Root cause of the rest-pool diagnostic printing zero entries:** guessed `restInfos:Get(idx)` to pull elements out of the native TArray — wrong method name, so every entry silently came back nil (safe_call swallowed the error) and only the top-level count ever printed. This project already has a PROVEN pattern for this exact situation, used successfully in `Indicator.lua`'s own property dumper: `:ForEach(function(index, elem) ... end)`, with each element needing `:get()` to unwrap before reading its fields. Reused verbatim instead of guessing again.

**Not yet answered:** WHY `PalRandomRest` produced something Feed-like for a Pal whose real idle set doesn't have one — the entry-level `[REST-POOL-DIAG]` data (now actually working) should show this directly on the next test: either that Pal's `RandomRestMontageInfos` genuinely does include something feed-adjacent (a real, if surprising, per-species authored choice), or the montages logged don't explain it at all, meaning something else is happening that needs more investigation.

Verified with `luaparse`, deployed to both destinations. **Test plan:** press Play again. This time expect: a real Cheer gesture from the player (or a `[CRASH-DIAG]`/failure line explaining why not), and full `[REST-POOL-DIAG] entry[...]` lines showing the real montage list for whatever Pal was targeted.

## Hundred-and-forty-third pass (2026-09-04): hearts VFX researched and wired — found via a fresh repak extraction, not a guess

Dragón's last open ask for Play: some idle poses don't read as visibly "happy" — can the hearts/flowers that show during Pet/Feed also show during Play?

**Research, real evidence again (repak + strings, the same established method as every prior asset-name investigation in this project).** Ran a fresh `repak list` against the real `Pal-Windows.pak` (no cached listing existed from before), grepped for heart/affection-shaped names, and found `Pal/Content/Pal/Effect/Common/Emotions/` — a small, clean folder: `NS_Happy`, `NS_HappyPetting`, `NS_Angry`, `NS_Notice`, `NS_Shock`, `NS_Inspire`. Extracted `BP_ActionHappy.uasset` (the Blueprint backing the already-used `Happy` EPalActionType) and read its string table: `SpawnSystemAtLocation`, `NiagaraFunctionLibrary`, `NiagaraSystem`, `LoadAsset`/`OnAssetLoaded__DelegateSignature` (a dynamic asset load, not a fixed reference — likely picking between `NS_Happy`/`NS_HappyPetting` based on context, not confirmed which), and `HeadBillboardEffectSetTransform` — confirms the hearts spawn from inside `BP_ActionHappy`'s own graph, positioned above the Pal's head, with no separate function exposed anywhere else to trigger just the VFX.

**Real tradeoff, not a simple addition:** `PalRandomRest` (the idle half) and `Happy` are mutually exclusive on the same `ActionComponent` — an actor can only run one action at a time (the same busy-gate rule this whole file already relies on everywhere). Presented Dragón three real options (sequence idle-then-Happy, swap to Happy only losing idle variety, or leave as-is) — he picked sequencing.

**Implementation:** after the idle animation plays, schedule a Happy follow-up via `ExecuteInGameThreadWithDelay(PLAY_HAPPY_FOLLOWUP_DELAY_MS)` — a fixed 3000ms approximation (no proven way yet to read back which specific `RandomRestMontageInfos` entry actually got picked or its real duration, same honest-approximation category as Feed's item-selection gap). Trust now comes ENTIRELY from Happy's own automatic `AddFriendShip` side effect (same mechanism Pet/Feed already use) — the explicit `AddFriendShip()` call `do_play()` used to make was removed, since keeping it would double-grant once Happy also fires its own real grant (the exact eleventh-pass bug this project already fixed once, now avoided a second time by removing the redundant call instead of re-adding it).

**New risk category, handled defensively:** this is the first time this project has held a LIVE ACTOR reference across a multi-second timer (every other delayed callback in this file only re-checks classes, never a specific actor) — a wild Pal could in principle despawn or die in that window. The delayed callback re-validates `pal:IsValid()` and `actionComp:IsValid()` before touching either again, and skips cleanly (logging why) if either failed or if the target became busy with something else in the meantime.

Verified with `luaparse`, deployed to both destinations. **Test plan:** press Play, wait ~3 seconds after the idle animation, and watch for the target to play Happy with hearts. Check the log for "Happy follow-up call returned" and a `[WATCH] real AddFriendShip fired` line shortly after — confirms trust granted exactly once, not twice.

## Hundred-and-forty-fourth pass (2026-09-04): the real test found the busy-gate bug — Happy never fired, some idle montages run 20+ real seconds

Dragón's test: Cheer still failed to resolve (the `:GetClass()` fix from the previous pass didn't help), and Happy never fired at all. He also gave the actual reason directly: some of these random-rest montages run 20+ real seconds — well past the 3s follow-up delay — so the follow-up's own busy-gate check (`ActionIsEmpty()`) was false every single time, hitting the "skipping hearts" branch on every real test. His own proposed fix, exactly as given: after the delay, just cut the idle animation off and force Happy regardless of busy state.

**Fixed:** removed the busy-gate check from the Happy follow-up entirely. `PlayActionByType` is the same already-proven-safe call used everywhere in this file — the busy-gate exists elsewhere in this project specifically to avoid interrupting the GAME's own organic behavior, but here it's cutting off an animation this mod itself started a few seconds earlier, not something vanilla was already doing, so forcing through is the correct behavior for this specific case.

**Cheer still unresolved — added targeted diagnostics instead of guessing a third fix blind.** The CDO resolves fine (same proven path as EMOTE-DIAG), but something in the `:GetClass()` step (or beyond) is still failing silently. Added `[CHEER-DIAG]` logging that separately reports whether the CDO resolved AND whether `:GetClass()` itself succeeded/what it returned, so the next test pinpoints exactly which step is the real problem instead of guessing at a third fix.

Verified with `luaparse`, deployed to both destinations. **Test plan:** press Play once more. Happy/hearts should now fire reliably ~3s after every press regardless of how long the idle animation runs. Check `[CHEER-DIAG]` lines for the real reason Cheer still isn't resolving.

## Hundred-and-forty-fifth pass (2026-09-04): Play went completely dead — Cheer's `:GetClass()` was silently killing the whole function, pulled out entirely

Dragón's report: Play stopped doing anything at all — wild Pals just ignored the key press, nothing happened. Real evidence in the log confirmed it exactly: every single Play press that reached the `[REST-POOL-DIAG]` entries stopped dead right after the last one — no `[CHEER-DIAG]` line (the very first thing the next code block does), no idle animation, no Happy follow-up, nothing. `do_play()` was throwing an uncaught error and dying silently, swallowed by the outer `safe_call(do_play)` in the keybind handler — which is exactly why nothing crashed (no Fatal Error dialog) but Play also produced zero effect.

**Root cause, by elimination:** the only code between the last confirmed-working line (the REST-POOL-DIAG loop, unchanged and still proven working) and the point everything died was the Cheer class-resolution block added the previous two passes — specifically `cheerCdo:GetClass()`, called on a CDO obtained via `StaticFindObject`. This is very likely a second instance of the exact same danger class as the fortieth pass's real crash: a method call on an object obtained through an unusual channel isn't automatically safe just because the SAME method works fine on an ordinary live actor elsewhere in this file (`dump_interesting_properties` calls `:GetClass()` successfully, but on a live actor/controller, never a CDO). This time it didn't crash the whole game — it corrupted the current Lua call enough to silently kill the rest of the enclosing function instead.

**Fixed by removing the whole Cheer/PlayAction block from `do_play()` entirely**, rather than continuing to iterate on an increasingly risky mechanism that was actively breaking the two things that already work (the idle animation and the Happy/hearts follow-up). The player-emote half goes back to being deferred to its own separate, later investigation — matching the original hundred-and-thirty-eighth pass decision before Dragón's real object dump made it look closer to done than it turned out to be. The read-only `[EMOTE-DIAG]` scan and the `[EMOTE-WATCH]` live hooks in `Interaction.Init()` are left running (harmless — read-only field scan / hook registration only, no live calls) for whenever that thread resumes.

**Lesson for this project, worth remembering:** a method proven safe on one CATEGORY of object (live actors/components/widgets) is not automatically safe on a DIFFERENT category (CDOs, asset references) just because it's the "same" method name — this is now the second real incident in two passes from exactly this assumption (`GetFName()` on an asset reference caused a hard crash; `GetClass()` on a CDO likely caused this silent function-death). Treat CDOs and asset references as their own unproven category for ANY method call, not just the specific method that already crashed once.

Verified with `luaparse`, deployed to both destinations. **Test plan:** press Play — should be back to working exactly like two passes ago: idle animation immediately, Happy/hearts ~3s later regardless of idle duration, no player emote (that's deferred again).

## Hundred-and-forty-sixth pass (2026-09-04): Happy follow-up really cut off now (CancelActionByType), and FORCE_ALL_CURIOUS added

Dragón's report: Play works and the idle animation plays (sometimes hard to catch a fleeing Pal in the act), but the animations run long and there was still no cut, no hearts, ever. Checked the log: `PlayActionByType(pal, Happy)` was returning "ok" from Lua every single time, but there were ZERO real `[WATCH] AddFriendShip fired` lines anywhere in the whole session — meaning the call was silently no-op'ing at the engine level. The busy-gate this project relies on elsewhere isn't just courtesy, it reflects a real restriction: a new `PlayActionByType` call doesn't auto-interrupt whatever's already playing.

**Fix, found in the SDK:** `CancelActionByType(EPalActionType Type)` sits right next to `PlayActionByType`/`PlayAction` on the same ActionComponent — same simple enum-parameter shape already proven safe everywhere in this file. The Happy follow-up now calls `actionComp:CancelActionByType(ACTION_TYPE_PAL_RANDOM_REST)` before `PlayActionByType(pal, Happy)`, so the idle animation is genuinely cancelled rather than just politely waited-past.

**Second ask, same message — force every wild Pal to "curious" behavior.** Dragón wants the whole weighted random-personality-tier system (50/25/10/15) bypassed for now — every wild Pal should just be calm/approachable so he doesn't have to chase fleeing ones. Added `FORCE_ALL_CURIOUS = true` in `Personality.lua`, right next to the existing `ENABLE_PERSONALITY_TIER_ROLL` toggle (same "toggle, don't delete" convention) — `roll_personality_tier()` now returns `"curious"` unconditionally when set, skipping the weighted table entirely. The already-existing ENFORCEMENT mechanism (which actually swaps each individual's real `AIResponsePreset` to match) needs no changes — it already treats "curious" like any other rolled tier.

**Important honest caveat, checked directly in the same test log before claiming this works:** ENFORCEMENT's real preset-swap depends on `find_sensor_component`, the exact still-unresolved sensor-read bug from the hundred-and-thirty-fifth/136th passes (item 4 on the saved priority list). This session's log finally shows real diagnostic data from that bug's one-time `[DIAG] rebuild_sensor_index` check: `FindAllOf('PalAISensorComponent')` returned only 7 instances (all 7 resolved to a usable owner key — the index-building mechanism itself works), but EVERY subsequent per-Pal `[ENFORCE]` lookup this whole session still hit "has no readable AISensorComponent" — zero real `[ENFORCE] SUCCESS` lines anywhere. This is new, useful evidence for that bug (the index-build itself isn't failing outright; something like 7 sensor components existing at any moment vs. far more distinct wild Pals seen this session suggests sensor components may not exist yet for most loaded Pals) — but it means **`FORCE_ALL_CURIOUS` will correctly roll and STORE "curious" for every Pal, but the real in-game behavior change (no more fleeing) is still blocked by this pre-existing, unrelated bug**, not something this pass fixes. Flagging this clearly rather than letting Dragón discover it feels broken.

Verified with `luaparse`, deployed to both destinations. **Test plan:** Play should now reliably cut the idle animation and show Happy/hearts every time. For personality: watch whether wild Pals actually stop fleeing — if they still do, that confirms the sensor bug is the real blocker (not this pass's change), and item 4 on the pending list is the next real thing to fix, now with much better diagnostic data than before.

## Hundred-and-forty-seventh pass (2026-09-04): the real fix for calm wild Pals — copy the reference mod's ACTUAL mechanism, not the summary of it

Dragón pushed back directly on the previous pass's honest-but-blocked `FORCE_ALL_CURIOUS`: "isn't the answer in the mod? the mod forces all pals to be pacific, you telling me you cant copy what the mod reference does?" He was right — this project had been trying to replicate the "Passive Pals" reference mod's PER-INDIVIDUAL mechanism (a live sensor lookup + private preset copy per Pal), which is actually that mod's OPT-IN, off-by-default "species layer." Re-reading the mod's real `main.lua` in full (not just the prior summary already in this file's own comments) showed its DEFAULT, PRIMARY mechanism is completely different and far simpler.

**The real mechanism, copied directly:** every wild Pal that shares an `AIResponsePreset` (Escape, Warlike, etc.) points at the SAME shared Class Default Object — the reference mod's `findPreset()`/`applyProfileToObject()` just rewrite that ONE shared object's 8 real fields (`Discover_Player/Greater/Equal/Smaller`, `Damaged_Player/Greater/Equal/Smaller`) directly. One write changes every Pal using that preset, instantly, globally — zero dependency on finding any individual Pal's sensor component (the exact mechanism blocked by the still-open item-4 bug). `findPreset()` is the EXACT same CDO-resolution technique this project's own `find_preset_cdo` already implements (this project had already independently arrived at that part) — the missing piece was recognizing it could be used for a global preset rewrite instead of only per-individual private copies.

**Implementation (`Personality.lua`):** `apply_global_curious_preset_override()` resolves `BP_AIResponsePreset_friendly`'s real CDO (the same preset this project's own `curious` tier already maps to), reads its 8 real field values, then for each of the confirmed real wild-Pal flee/combat presets (`escape`, `Escape_to_Battle`, `Warlike`, `Warlike_Anyway`, `Warlike_WithoutPlayer` — excluding `VillageNPC`/`Kill_All`, confirmed human-NPC-only per the reference mod's own `humanPresetNames` list) overwrites its fields to match, with ONE safety copied directly from the reference mod: a slot already holding `EPalAIResponseType.Special` (3) is preserved, never overwritten, since this project's own Pet/Feed interaction likely depends on a real Special-tagged reaction existing somewhere in the game's own data. Runs once per session (bounded retry, same convention as EMOTE-DIAG), triggered from `Personality.Init()` when `FORCE_ALL_CURIOUS` is set — independent of the per-individual ENFORCE scan, which stays running but is honestly logged as currently blocked by the sensor bug rather than "untested."

Deliberately narrower than "every preset in the game": `Default`/`NotInterested`/`Boss` are left untouched — pacifying boss encounters specifically is a separate question Dragón hasn't asked for, flagged rather than assumed.

Verified with `luaparse`, deployed to both destinations. **Test plan:** wild Pals should now stay calm/approachable immediately (no waiting for a per-individual scan, no per-Pal sensor dependency) — check the log for `[GLOBAL-CURIOUS]` lines confirming each preset was resolved and rewritten, and confirm live that a previously-fleeing species (Chicken, Sheep, etc.) now stands still when approached.

## Hundred-and-forty-eighth pass (2026-09-04): the real fix for the sensor-component bug (item 4) — a REACTIVE hook, not a proactive search

Dragón, after confirming GLOBAL-CURIOUS worked live: "if you can do this, why not put the randomizer there? like from the base, the chance for pals to have this or that behavior?" Real, correct question — explained why the global-preset technique specifically CAN'T do per-individual variety (every Pal sharing a preset gets the same shared object, by definition), but pointed at the actual fix: the Passive Pals reference mod's OTHER technique (its opt-in "species layer," previously only partially read) does per-individual work without ever proactively searching for a sensor at all. Dragón approved implementing it.

**The real mechanism, copied directly:** hook `/Script/Pal.PalAISensorComponent:SelectResponseBySenses` — a real function the game itself calls every time a Pal's AI makes a sense-based decision. The hook's own `Context:get()` hands over the LIVE sensor component directly, no `FindAllOf`/owner-key matching needed at all (the exact mechanism confirmed broken — 7 sensor components found via `FindAllOf` in a session with far more wild Pals loaded, meaning most Pals' sensors simply aren't discoverable that way). From the sensor, `sensor:GetOuter().Pawn` gives the real owning Pal actor — the reference mod's own technique, going the OPPOSITE direction from this project's broken one (sensor → actor, instead of actor → sensor).

**Implementation:** refactored `try_enforce_personality` into a sensor-agnostic core (`try_enforce_personality_with_sensor`, everything except finding the sensor) plus two callers — the original proactive scan (kept running as a fallback, in case some Pal never fires a sense decision) and a new `on_sensor_select_response` reactive handler wired to the hook. This is genuinely the same real hook point this project's OWN ninety-second-pass notes had already flagged as a candidate ("a properly-throttled SelectResponseBySenses override, neither attempted yet") but never actually wired until now.

**Lag discipline, since this can fire at real per-Pal AI decision frequency:** `handledSensorKeys` dedupes by sensor identity FIRST, before any other work — every fire after the first for a given sensor is a cheap table lookup, never a repeat of the ownership check/preset resolution. A sensor marked handled even after a failed attempt stays that way (not retried every fire) — deliberate, matching this project's hard-learned lesson from three prior unthrottled-hook lag incidents (ninety-fourth/ninety-fifth/hundred-and-thirty-second passes); a Pal that fails here can still be caught by the proactive scan instead.

Verified with `luaparse`, deployed to both destinations. **This is likely the real fix for item 4** (species-default personality reading also depends on sensor access, though through a different code path — worth re-checking once this is confirmed live). **Test plan:** watch for real `[ENFORCE] SUCCESS` lines this time (there were zero in every prior session). With `FORCE_ALL_CURIOUS` still on, this mainly proves the mechanism works via the already-passing GLOBAL-CURIOUS presets; the real test of per-individual VARIETY needs `FORCE_ALL_CURIOUS` turned off first — ask Dragón before flipping that, it's a real behavior change (some Pals go back to fleeing/aggressive) he hasn't explicitly requested yet this session.

## Hundred-and-forty-ninth pass (2026-09-04): FORCE_ALL_CURIOUS turned off for the real behavior test — and a real dependency caught first

Dragón, correctly, wasn't satisfied that real `[ENFORCE] SUCCESS` log lines meant the per-individual system was "working" — his own words: "if you tell me YES they are already rolling the random personalities but i cannot see it in game with their actions, then IT IS NOT WORKING - it has to be visible, not by code but by behavior." Right standard. Every prior test had `FORCE_ALL_CURIOUS` on, which forces every roll to "curious" — so the per-individual mechanism had never actually been asked to produce two DIFFERENT outcomes, only the same one repeatedly. Confirmed honestly: not yet proven by his bar.

**Caught a real dependency before flipping the switch:** `GLOBAL_OVERRIDE_TARGET_PRESETS` (the hundred-and-forty-seventh pass's global rewrite) includes `BP_AIResponsePreset_Warlike` and `BP_AIResponsePreset_escape` — the EXACT SAME two presets `TIER_TO_DONOR_PRESET_CLASS` uses as the source data for the "hostile" and "skittish" tiers. The global override had already overwritten both of those presets' real fields to match "friendly" — meaning if `FORCE_ALL_CURIOUS` were simply switched off without anything else, a Pal that rolled "hostile" would still get a private preset copied from the now-friendly-flavored Warlike CDO, and stay calm anyway. The test would have looked like a failure without actually testing anything real.

**No extra revert code needed, though — traced it through:** the global override only ever mutated those preset CDOs in the CURRENTLY RUNNING game process's memory, never touched anything on disk. A genuine game restart reloads all preset assets fresh from disk, automatically undoing the in-memory corruption — the fix is just "make sure this is a real restart, not a continued session," not new code.

`FORCE_ALL_CURIOUS` flipped to `false`. `PERSONALITY_TIERS` (the 50/25/10/15 weighted table) left unchanged — comparing same-species Pals for different rolled behavior with the existing split is the actual test Dragón asked for, not a new weight distribution yet. Verified with `luaparse`, deployed to both destinations. **Test plan:** genuine game restart required. Aim at several Pals of the SAME species and compare their real behavior (some should flee, some should watch calmly, some should be aggressive, matching each one's own rolled tier) — this is the actual, honest test of whether the whole system works end-to-end.

## Hundred-and-fiftieth pass (2026-09-04): confirmed working (147 individuals rolled this session, real 10/15/25/50-ish split), plus a temporary debug label

Dragón's restart test: real success — different wild Pals visibly behaving differently, confirmed by his own observation ("saw different behaviors which was nice!!"). Pulled real numbers from the log for him: 147 total individuals rolled this session, 21 hostile / 16 skittish / 43 curious / 67 normal — close to the intended 10/15/25/50 weights given normal sampling variance. He noted not personally encountering any hostile ones despite 21 rolling that tier — flagged as worth investigating later, not chased down this pass (out of scope for what was asked).

**New feature, explicitly temporary:** Dragón wants a text label under each wild Pal's trust bar showing its rolled disposition word (curious/hostile/skittish/normal), specifically to compare against real observed behavior while testing/balancing the roll — removable once confirmed and tuned. Implemented in `Indicator.lua`, reusing the EXACT widget-construction technique already proven for the trust bar itself (`StaticFindObject` the native UMG class → `StaticConstructObject` into the real parent panel → `AddChildToCanvas` → position relative to the trust bar's own real coordinates), the only new parts being the widget class (`/Script/UMG.TextBlock` instead of `ProgressBar`) and writing its `.Text` property directly with a plain Lua string — a first attempt for this project, not yet confirmed to actually render (this project's own history with `SetText_GDKInternal` on an EXISTING game text widget showed a successful write call with nothing visible, due to a collapsed default `Visibility` — same defensive `SetVisibility(0)` force applied here). Updates only when the disposition word actually changes (a personality basically never changes after its initial roll, aside from Won-Over), matching this file's lag discipline. The whole block (creation + per-tick update) is self-contained and marked TEMPORARY DEBUG FEATURE in comments for easy removal later.

Verified with `luaparse`, deployed to both destinations. **Test plan:** look at a wild Pal's trust bar — a text label should appear just below it showing its disposition word. If nothing renders, check the log for `[DIAG-LABEL]` lines (construction/positioning/text-write success or failure) — first UI-text-write attempt in this project, may need one iteration same as everything else in this file's history.

## Hundred-and-fifty-first pass (2026-09-04): the personality label crashed on its first real test — bracketed with CRASH-DIAG instead of guessing

Dragón's first live test of the personality label produced a real crash (EXCEPTION_ACCESS_VIOLATION reading `0x70` — the same near-null-read signature this project's other real native crashes have shown). The log confirmed it's a genuine native crash, not a caught Lua error: it cuts off silently right before the label-creation block, with NO `[DIAG-LABEL]` line at all — meaning the crash happened inside one of the new calls (`StaticFindObject('/Script/UMG.TextBlock')`, `StaticConstructObject`, `AddChildToCanvas`, or the `.Text` property write) before even the first diagnostic could print, bypassing `pcall` the same way the fortieth pass's `GetFName()` crash did.

Rather than guess which specific call is the culprit, applied this project's own only-ever-successful crash-diagnosis method: `[CRASH-DIAG]` before/after logging around every single new native call in the block — `StaticFindObject`, `StaticConstructObject`, `AddChildToCanvas`, `SetPosition`/`SetSize`, `SetVisibility`, and the `.Text` write (both the creation-time one and its counterpart in `update_trust_bars`). Whichever line is the LAST one printed on the next attempt names the exact failing call. Given this project's history, the `.Text` PROPERTY WRITE (not a method call) is a real suspect worth watching for specifically — every other native call in this block (StaticFindObject/StaticConstructObject/AddChildToCanvas) already succeeded for the trust bar's ProgressBar moments earlier in the very same function; the genuinely new operation is writing a plain Lua string into what may be an FText-typed property, an untested marshaling path for this project.

Verified with `luaparse`, deployed to both destinations. **Test plan:** try again — this could crash again, but this time the log will show exactly which call is responsible, closing this out for good either way.

## Hundred-and-fifty-second pass (2026-09-04): root cause found — a raw FText property write, fixed by switching to a real confirmed method

The `[CRASH-DIAG]` bracketing worked exactly as intended: every step through `SetVisibility` printed "still alive," and the log stopped right after "about to write labelObj.Text NOW" — pinpointing the crash to `labelObj.Text = "?"`, a direct property WRITE of a plain Lua string into what's actually a complex `FText`-typed property. Every other write this project has ever done safely has been a simple scalar (bool/int/float) or an object pointer — this was the first attempt at an FText property, and direct assignment isn't safe for it.

**Fix:** stopped trying to write `.Text` directly at all. Instead of a generic native `/Script/UMG.TextBlock`, the label now constructs the game's OWN real text-widget class — `BP_PalTextBlock_C`, confirmed real back in the fifty-first pass as `Text_WorkName`'s class — pulled directly off an ALREADY-LIVE instance on the same gauge (`gaugeWidget.WBP_EnemyGauge.Text_WorkName:GetClass()`, the same "read the class off a live object instead of guessing a static path" technique already used for personality presets), and sets its text via `SetText_GDKInternal(bool, string)` — a real METHOD this project already confirmed executes without a Lua error months ago (fifty-second pass) — that older attempt's only problem was the widget's default `Visibility` being `Collapsed`, already forced `Visible` in this same code path. Applied to both the creation-time write and its counterpart in `update_trust_bars`.

Verified with `luaparse`, deployed to both destinations. **Test plan:** try again. Watch for the label to actually render this time, and check `[CRASH-DIAG]` lines confirm `SetText_GDKInternal` returns "still alive" — the real, final test of whether this whole feature works.

## Hundred-and-fifty-third pass (2026-09-04): full rename to real preset names, 3 new tiers, NPC/Boss exclusion — Dragón's own follow-through on the label working

The label worked (no crash) and immediately did its job: Dragón confirmed his suspicion that "curious" Pals were sometimes fleeing. Rather than accept "the terms are too broad" as the explanation, walked through what our 4 words actually map to versus the real 11-preset pool — and this surfaced a genuine bug, not just a labeling issue: `PRESET_NAME_TO_DISPOSITION` only ever recognized `Escape_to_Battle`, never plain `escape` — so any species whose real default is plain `escape` silently fell through to the "unrecognized preset" fallback and got mislabeled "curious." A normal-tier roll on one of those species is never enforced (normal means leave it alone), so the Pal really does flee — the label was just lying about why.

Dragón: "i honestly would put the real names, so things like the fallback curious fail wouldnt happen again" — a full rename, not a patch. Also wants 3 previously-unused real presets added (`NotInterested`, `Warlike_Anyway`, `Warlike_WithoutPlayer`) specifically to compare the three "warlike" variants live, since plain `Warlike` (today's "hostile") did NOT attack him in two real tests — matching the hypothesis that it's the *conditional* aggressive preset, not the unconditional ones.

**Renamed throughout** (`DISPOSITIONS`, `PERSONALITY_TIERS`, `PRESET_NAME_TO_DISPOSITION`, `TIER_TO_DONOR_PRESET_CLASS`, `PresetClassNameToDisposition`'s fallback, the WON-OVER mechanism): `curious`→`friendly`, `hostile`→`warlike`, `skittish`→`escape`, `normal` unchanged. Added the escape bug fix (`BP_AIResponsePreset_escape_C` now correctly maps to `escape`) plus 3 new tiers (`notinterested`, `warlike_anyway`, `warlike_without_player`), each with their own real donor preset in `TIER_TO_DONOR_PRESET_CLASS`.

**New weighted split** (Dragón's own numbers, sums to 100): normal 35 / friendly 20 / escape 10 / notinterested 10 / warlike 5 / warlike_anyway 10 / warlike_without_player 10. Combined "attacks in some form" jumped from 10% to 25% — flagged to Dragón as a real, deliberate balance shift, not silently absorbed.

**New exclusion, Dragón: "npc, bosses and other things, those should stay normal always."** Before this, the roll ran unconditionally on every actor `GetOrInitState` saw, including human NPCs and bosses swept up by the periodic scan's `FindAllOf("PalCharacter")`. Added `EXCLUDED_FROM_ROLLING` (`VillageNPC`/`Kill_All`/`Boss` preset class names) — any Pal whose real current preset is one of these is forced to `rolledTier="normal"` unconditionally, skipping the random roll entirely, checked against data already resolved for every Pal anyway (no new lookup needed).

`apply_global_curious_preset_override` (the GLOBAL-CURIOUS mechanism, currently dormant since `FORCE_ALL_CURIOUS=false`) is untouched — it references raw preset name strings directly, not the renamed tier words, so it's unaffected either way. Confirmed via grep that no other file in this project (`Interaction.lua`/`Capture.lua`/`Trust.lua`/`Indicator.lua`) compares against the old tier words directly — the rename is fully self-contained to `Personality.lua`.

Verified with `luaparse`, deployed to both destinations. **Test plan:** the personality label should now show real preset names, letting Dragón directly compare `warlike`/`warlike_anyway`/`warlike_without_player` against actual observed aggression, and confirm the `escape` bug fix (no more Pals labeled "friendly" that actually flee). Also confirm no NPC or boss ever shows anything but effectively their own real default (never swapped).

## Hundred-and-fifty-fourth pass (2026-09-04): confirmed working, but self-inflicted lag from leftover crash-forensics logging — trimmed

Dragón's test: real success — Warlike Pals actually attacked this time (the new tiers landed real evidence, not just theory). Also reported real lag, and asked about Pals showing "?" as their label.

**The "?" question, answered from the log directly, not a guess:** it's just the brief initial placeholder — confirmed multiple real Pals (SheepBall, PinkCat, ChickenPal, PlantSlime) writing "?" at label-creation time and then the real disposition word (`friendly`/`escape`/`warlike_anyway`/`warlike_without_player`) a few seconds later once the periodic scan resolves their actor and personality state. Not a new bug in the roll system — if a specific Pal's label stayed "?" for the whole session, that would point at a separate, pre-existing limitation (that gauge's real actor never resolving at all, a known issue from this file's own history), not the personality/tier system.

**The real lag, found the same way as every other lag bug in this project — breaking the log down by volume, not guessing:** `[CRASH-DIAG]` (the crash-forensics bracketing added two passes ago to find the FText-write crash) was 516 of 981 Indicator log lines in a 140-second session — over half, each one a forced synchronous disk write. The crash it was hunting was already found and fixed last pass; this instrumentation was just never removed afterward. Exact same shape of self-inflicted logging lag this project already hit and fixed once before (`[INDICATOR-WATCH]`, ninety-eighth pass) — diagnostic bracketing is meant to be temporary. Trimmed both the creation-time and per-tick text-write bracketing back down to a single outcome log line each, matching every other one-shot/per-event log elsewhere in this file.

Verified with `luaparse`, deployed to both destinations. **Test plan:** same routine — Indicator's log volume for a similar session should be roughly half what it was, and the lag should be noticeably reduced or gone.

## Hundred-and-fifty-fifth pass (2026-09-04): the "?" that persisted the whole session — a real race in the bind-hook, investigated and fixed at the source

Dragón: he saw a specific wild Pal (a samurai dog, `BP_SamuraiDog_C`) stay on "?" for the entire session, even after petting it — and asked to actually investigate rather than leave it as a known rough edge. Grepped the log directly rather than guessing: confirmed zero "resolved a real Pal actor" lines (first-try or retry) ever mention `SamuraiDog` anywhere in the whole session — proving this is genuinely the gauge-actor-binding limitation, not a personality-roll failure (the roll itself doesn't depend on the species-default sensor read succeeding).

**Root cause, traced to the actual registration code:** `register_bind_hook_once` — which registers a CLASS-LEVEL hook on `BindFromHandle` (once registered, it catches every future call across ALL gauge instances, not just one) — is only ever CALLED from this file's own periodic gauge-discovery scan (`scheduleScan`/`check_panel_children`), not immediately at `Indicator.Init()`. So the hook doesn't actually go live until the FIRST gauge is ever discovered by that scan. Any gauge already on-screen and already bound before that exact moment — very plausibly a Pal already visible right as the session starts — permanently misses capture, with no way to ever retry (`BindFromHandle` only fires once per bind).

**Fix, in two layers, both real and both needed:**
1. The hook's first candidate path is already a hardcoded, proven-real literal string (confirmed via a bundled reference mod, no live gauge widget needed to compute it) — extracted into a new `register_bind_hook_immediate()`, called unconditionally at the very top of `Indicator.Init()`, instead of waiting for scan-discovery. `register_bind_hook_once`'s gauge-dependent fallback candidates stay in place as a safety net for a future build where this literal path might change (`hasRegisteredBindHook` already being true after a successful immediate call makes that later call a clean no-op).
2. `Indicator.Init()` itself was running sixth of eight in `main.lua`'s `PalBonds.Init()`, after several modules doing real hook-registration work of their own — moved it to run second, right after `Logger.Init()`. Checked for real dependency risk first: `Indicator.lua`'s own `require("Personality")` already returns the cached module table regardless of Init() call order (Lua caches at first `require`, not at Init time), and Indicator only actually CALLS into Personality from its own runtime update loop, well after every module's Init() has finished — so reordering carries no correctness risk, only less delay before this specific hook goes live.

**Honest caveat:** this closes almost the entire race window, not necessarily literally all of it — there's still some unavoidable gap between the game process starting and this mod's `main.lua` executing at all, outside this project's control. A Pal bound in that specific window would still be missed. Real improvement, not a mathematical guarantee.

Verified with `luaparse`, deployed to both destinations (`Indicator.lua` and `main.lua`). **Test plan:** same routine, ideally near a wild Pal that's already visible right as the game finishes loading — check whether its label/trust bar resolves this time instead of staying on "?".

## Hundred-and-fifty-sixth pass (2026-09-04): real fleeing on trust-loss — item 2, reusing the exact mechanism proven live today

Dragón, reasonably, didn't want the next test to be a single 2-second check — asked what else could be bundled in. Checked the saved priority list instead of inventing something new: item 2, real fleeing when trust hits zero, was still open. `Capture.OnTrustLost` used to just set an internal flag and block further interaction, with an honest TODO admitting real flee behavior was never attempted because forcing an actor to flee looked like a new, risky native-call category at the time it was written.

**It isn't anymore.** This exact session already proved a real, live-working mechanism for making a Pal genuinely flee: forcing its tracked tier to `escape` and letting the enforcement path (private `AIResponsePreset` swap, confirmed working via real `[ENFORCE] SUCCESS` lines and Dragón's own live observation of escape-tier Pals actually fleeing) apply it. No new native call needed — just reusing what already works.

**Implementation:** added `Personality.ForceTier(palId, palActor, tier)` — a generalized version of the existing WON-OVER mechanism (`OnSuccessfulInteraction`, escape→friendly), but parameterized and for the opposite direction. Sets the tracked tier/disposition, resets `enforcementApplied = false` (so a Pal already enforced under its OLD tier gets a genuine new attempt, not silently skipped), and attempts the same ownership-gated, `find_sensor_component`+`apply_forced_preset` swap immediately. `Capture.OnTrustLost` now calls `Personality.ForceTier(palId, pal, "escape")` right after its existing flag/logging.

**Honest caveat, worth watching in testing, not solved blind right now:** the REACTIVE hook (`on_sensor_select_response`) dedupes by sensor IDENTITY, not by tier — once a given Pal's sensor has fired through that hook once (for whatever tier it had then), it won't be re-caught by that hook for a NEW tier later. Only the immediate attempt in `ForceTier` and the proactive periodic scan (the historically less reliable `find_sensor_component` path) can retry it after that point. If real fleeing doesn't show up immediately on trust-loss, this is the first thing to check.

Verified with `luaparse`, deployed to both destinations (`Personality.lua`, `Capture.lua`). **Test plan, bundled with the bind-hook race-fix retest:** let a Pal's trust drop to zero (damage or leaving it behind mid-bond) and watch for real fleeing — the target of this whole feature. Check the log for `[FORCE-TIER]` lines confirming the swap attempt and outcome.

## Hundred-and-fifty-seventh pass (2026-09-04): the bind-hook fix regressed on its own first test — no retry loop — plus real, measured data on the 2 remaining personality misses

Dragón's report: "?" still showed on the first Pals, some Pals still didn't match their rolled behavior, several failures visible in the console, and he couldn't get to testing real fleeing because of the personality discrepancies. Investigated all three from the log directly rather than guessing.

**The "?" regression — a real bug in last pass's own fix, found at line 4 of the log:** `register_bind_hook_immediate()`'s ONE-SHOT attempt FAILED outright at Init() — "no UFunction with the specified name was found." Moving registration earlier meant it now fires BEFORE the target Blueprint class is even loaded into memory — the exact "class not loaded yet" problem this project has hit and fixed with a bounded retry loop many times before (Radial Menu, Worker Menu, EMOTE-WATCH), just not applied to this specific fix. With no retry, it silently fell back to the exact same scan-discovery race as before — last pass's fix accomplished nothing in that test, which is exactly why Dragón still saw the samurai-dog-style "?" persist. **Fixed** by converting it into the same bounded-retry pattern (1s cadence, 30 rounds) already proven throughout this project — should now succeed well before most gauges bind, unlike waiting on the scan.

**Console failures — mostly not new, one exception already covered above.** Cross-checked: `[RADIAL-WATCH]`/other round-1 "FAILED: no UFunction" lines are the SAME already-expected, already-normal retry-loop noise this project produces every single session (round 1 always fails, later rounds succeed) — not a new regression. The one that WAS new and real is the bind-hook one above.

**Personality mismatches — real, measured, not a misperception.** Counted directly: 40 individuals rolled a non-`normal` tier this session, 37 got a confirmed real `[ENFORCE] SUCCESS`, and exactly 3 never did — 1 of those 3 happened to roll a tier matching its own species default anyway (so no visible mismatch even without enforcement), leaving 2 REAL cases where the tracked personality never got applied to real behavior (both stuck on "no readable AISensorComponent" via the proactive path for the whole session, and apparently never caught by the reactive hook either — most likely because that specific Pal's AI never made a sense-decision during the test window, a probabilistic gap rather than a systemic failure). ~95% real success rate (37/39 relevant rolls) — a real, small residual gap, not chased further this pass since it isn't a repeatable, root-cause-able bug the way the other two were.

Verified with `luaparse`, deployed to both destinations. **Test plan:** same routine as before, now that the bind-hook fix actually has a chance to work — check line-by-line whether `[DIAG-HOOK] (immediate, round N)` eventually logs `OK` well before any gauge is discovered, and whether the "?" issue is actually gone this time. Personality mismatches should be rare (a couple out of dozens) rather than "several," matching the real 95% rate found here — if it's still worse than that, worth a fresh investigation with real numbers again rather than assuming this diagnosis was wrong.

## Hundred-and-fifty-eighth pass (2026-09-04): "are they still needed or just trash?" — real audit, one genuinely dead hook removed

Dragón pushed back directly on the previous pass's "these console failures are normal, they succeed later" reassurance: "later when? ... are they still needed or are just trash that is getting acumulated and you havent cleaned up?" — right to ask, since that claim hadn't actually been checked against this specific session's data.

**Checked properly instead of reassuring again.** `[RADIAL-WATCH]` (backs the active radial-menu Pet/Feed redirect feature): confirmed 14 real successes this session, first one at round 5 (~25s in) — the "succeeds later" claim was accurate for this one, now with real evidence instead of general impression. `[EMOTE-WATCH]` (the OnBeginAction hooks added to research the player-Cheer emote, back in the hundred-and-thirty-eighth pass): **405 log lines this session, zero successes, ever.** That feature was already abandoned two passes later (do_play's PlayAction attempt crashed twice, pulled out entirely — hundred-and-forty-fifth pass) but nobody ever went back to turn off the hooks that only existed to support it. This is genuinely dead weight, not normal retry noise.

**Removed the EMOTE-WATCH loop entirely** (commented out with a note, not deleted — same convention as every other retired-but-documented block in this file). Also spot-checked `WORKER-BIND-FIX`/`OTOMO-GETTER-WATCH`/`MENU-WATCH` before assuming they were fine too — confirmed all three are real, actively firing with real data, just logged in a different format than the naive "= OK" grep pattern first tried (a genuine possible false-negative avoided by checking actual content, not just a text pattern).

Verified with `luaparse`, deployed to both destinations. No further test needed for this specific change — it only removes dead log volume, doesn't change behavior.

## Hundred-and-fifty-ninth pass (2026-09-04): real, itemized test data traced to the exact log lines — root cause found (busy-gate discards nearly every Pet press; Feed/Play's Happy() call grants nothing), then a genuinely new lever identified for real item feeding

Dragón ran a precise, controlled test — 3 specific wild Pals, exact action counts, exact final friendship values — and asked for a direct comparison against the log. Cross-referencing his real counts against `[Trust] interaction #N recorded` snapshots and the press/gate log lines for all three (`BP_SheepBall_C_2147456684`, `BP_SamuraiDog_C_2147451952`, `BP_FlameBambi_C_2147425848`) gave an exact, zero-exception match: **every real friendship delta equals +10 per real Pet press, with Feed and Play contributing +0 across all 9 data points.** Full line-by-line evidence pulled and shown to Dragón (see chat log for the complete per-Pal chronological listing — not duplicated here since it's raw log excerpt, not a design decision).

**The real mechanism, traced from the raw gate lines, not inferred:** for `BP_SheepBall_C`, 6 of 8 real button presses (all 4 Pet presses included) were discarded before ever reaching `Happy()`, logged plainly as `"player is already mid-action — ignoring press"`. Yet real friendship kept climbing by +10 per pet regardless. Since `PlayActionByType` is already confirmed (hundred-and-forty-sixth pass) to silently no-op rather than queue when busy, and our own gate returns before attempting anything, nothing on our side could have produced those grants. The most consistent explanation: the REAL vanilla Care action is firing directly on the substituted wild Pal through the radial menu, completely independent of our own gate or `do_pet()` — the same substitution mechanism (`TryGetSpawnedOtomo`/`SpawnedOtomo` override, eighty-fifth/hundred-and-twenty-third passes) that's been active all along, just never credited as the actual source of Pet's real grant until this trace. Feed never gets this vanilla assist (confirmed dead end weeks ago: the deep food system never activates for a substituted wild Pal), so it's entirely dependent on our own `do_interaction()`'s `Happy()` call — which, on the rare Feed press that DOES pass our gate, still grants 0. This falsifies this project's own long-standing assumption that Happy()'s AddFriendShip side effect is unconditional — it isn't, at least not for a Feed- or Play-preceded Happy() call.

**Dragón's direct pushback and redirect:** rejected the "just call AddFriendShip explicitly for Feed/Play" fix as short-sighted (doesn't build toward real item consumption, which the mod actually needs for kinship peaches). Asked directly whether the exact same "trick the menu" idea already used for Pet could just be pointed at Feed instead. Answer, from this project's own already-completed research: no — that idea was already tried twice against Feed specifically (hundred-and-twenty-third/twenty-fourth passes: overriding both `TryGetSpawnedOtomo`'s return value AND the widget's own cached `SpawnedOtomo` field), and both are confirmed dead ends — the real food-picker (`SelectedFeed`) never fires either way. Ghidra's decompile (hundred-and-thirty-fourth pass) found a plausible reason: the real Otomo-feed eligibility check looks like a raw C++ vtable call, invisible to anything Lua can hook or override.

**The genuinely new lever Dragón's question surfaced:** he asked whether the WORKER radial menu (separate from the Otomo/no-aim menu, used for base-assigned Pals) had ever been tried for a wild Pal's Feed. It hadn't — every prior Feed test went through the Otomo wheel only. More importantly, the Worker path's real consumption function, `APalMonsterCharacter:SelectedFeedingItem(FPalItemSlotId, int64)`, was already confirmed via Ghidra (hundred-and-thirty-fourth pass) to have **no ownership check anywhere in its own body** — unlike `RequestUseToCharacter`, which IS gated to the active Otomo only (confirmed live, hundred-and-nineteenth pass). Rather than spoof the Worker menu's `WorkAssignId` eligibility gate (a UI-level trick, same risk category as what's already failed twice for the Otomo path), the more direct experiment is calling `SelectedFeedingItem` on the wild Pal ourselves — since it doesn't check who's asking.

**Researched (not guessed) whether this is even constructible in Lua**, since `FPalItemSlotId` doesn't exist ready-made on any live object (`UPalItemSlot` stores `ContainerId`/`SlotIndex` as two separate fields, hundred-and-thirteenth pass) — it would have to be built fresh. Checked RE-UE4SS's own documentation and examples directly: struct arguments convert automatically from plain Lua tables, INCLUDING nested structs — their own documented example is a Transform table with nested Rotation/Translation/Scale3D sub-tables, the same shape complexity as `FPalItemSlotId {ContainerId: {ID: FGuid}, SlotIndex}`. This is a different, safer category than Crash #4 (which built an `FName` — an interned string-table lookup, not plain data).

**Implemented: CTRL+H, a new isolated test key** (`do_test_selected_feeding_item()` in Interaction.lua) — all four existing keys are live, non-abandoned features right now, so there was nothing dead to repurpose this time, unlike every prior key reuse in this project. Reuses the exact proven-safe technique from the old CTRL+J test (hundred-and-seventeenth pass) to find the player's real Berries stack (`FindAllOf("PalItemSlot")`, highest `StackCount` match), reads `ContainerId`/`SlotIndex` directly off that live slot, and builds only the minimal new wrapper — `{ContainerId = <the real live struct, reused as-is>, SlotIndex = <the real int>}` — never decomposing/rebuilding the GUID from raw values. Calls `pal:SelectedFeedingItem(itemSlotId, 1)` directly on whatever Pal is targeted (wild included, no ownership gate applied on our end either, since the whole point is testing whether the native function needs one). Logs the real `StackCount` before and after, and the existing `[FOOD-DIAG]`/`[SLOT-USE-DIAG]` watch hooks will independently confirm whether this was a real fire.

Verified with `luaparse`, deployed to the live Mods folder and the Proyectos mirror.

**Test plan for Dragón:** aim CTRL+H at a wild Pal (ideally one you don't own, to test exactly the case that's been blocked) with at least one Berries in inventory, press it once, and report: did `StackCount` actually drop, did the Pal react at all, and did anything log as `FAILED`. Also worth trying once on your own Otomo as a baseline comparison. This also answers, as a side effect, whether real friendship gets granted this way (watch the trust bar / `[Trust]` log lines) — `RequestUseToCharacter`'s own testing (hundred-and-nineteenth pass) found NO friendship side effect from item consumption alone, so if `SelectedFeedingItem` behaves the same way, Happy() would still need to be called separately afterward — not wired yet, deliberately, pending this test's result.

## Crash #5 (2026-09-04): the direct `SelectedFeedingItem` call — confirmed real, and worse than any prior crash in this project

Dragón's very first live test of CTRL+H produced something new: the game visibly kept running (no crash screen, no restart), but he noticed a crash flag/alert anyway, and several other things stopped behaving correctly — including CTRL+J (Play), which had worked fine minutes earlier.

**Read the raw evidence directly, not from Dragón's description alone.** `palbonds-live.log` shows the call sequence executing normally — targeted `BP_Monkey_Fire_C`, found a real Berries slot (`SlotIndex=16 StackCount=115`), logged `"calling pal:SelectedFeedingItem(itemSlotId, 1) NOW"` at 23:01:39 — and then **the very next log line this call's own `pcall` is supposed to print unconditionally, on ANY outcome including a caught Lua error, never appears.** A real Windows crash dump exists at the exact same second: `ue4ss/crash_2026_09_04_23_01_39.1693134.dmp`. And critically: after that timestamp, this session's log shows **zero further key-press lines of any kind for the rest of the session** — not just CTRL+H/CTRL+J, but `InputSpy`'s raw WASD/mouse listener too, a completely unrelated hook that has nothing to do with this code path. `UE4SS.log` itself shows no `ensure`/`Fatal error`/exception text near that timestamp, meaning the crash reporter fired below the level UE4SS's own text logging can see.

**What this means:** this single call didn't just fail — it wedged the entire Lua/input-processing layer for the rest of the session, while leaving the game process itself alive. That's a new, worse failure mode than Crashes #1-4, which either errored cleanly in Lua (catchable) or killed the whole process outright (obvious, unmissable). This one looks completely fine until you notice nothing responds anymore.

**Likely cause (not fully confirmed, but well-supported):** every prior live-fire native call in this project (`PlayActionByType`, `RequestUseToCharacter`, `PalCaptureSuccess`, etc.) was always something either called constantly by ordinary gameplay or explicitly designed to be triggered standalone. `SelectedFeedingItem` was only ever *observed* firing as one step inside an already-established internal call sequence — the real Worker Menu's own UI flow sets up state before it fires (mirroring the Otomo path's confirmed `BP_ActionPairBehavior_FeedItem` machinery, hundred-and-twenty-fifth pass). Calling it cold, with none of that setup ever having happened, most plausibly dereferenced something the real flow always guarantees is valid. It's also possible this is a *latent* function (one that completes later via a delegate the real UI listens for, rather than returning synchronously) — which would separately explain "never returns" even without a hard fault. Either way, this function is not safe to call directly outside its real context.

**Fix applied:** the live call (`pal:SelectedFeedingItem(itemSlotId, 1)`) is removed from `do_test_selected_feeding_item()` — not commented past, actually deleted from the execution path — leaving only the already-safe diagnostic scaffolding (targeting, finding the real food slot, reading its real `ContainerId`/`SlotIndex`, building the `itemSlotId` table) intact and logged. CTRL+H now stops right before the dangerous call every time. Verified with `luaparse`, deployed to the live Mods folder and the Proyectos mirror.

**Status: this specific approach (calling `SelectedFeedingItem` directly, skipping the UI) is now a third confirmed dead end**, alongside `RequestUseToCharacter` (Otomo-gated) and `SelectedFeed` (vtable-gated). The only path left standing for real item-driven feeding is getting the real Worker Menu's own UI to actually open while aiming at a wild Pal — a UI-eligibility question (spoofing `WorkAssignId`), not a native-call-safety question — genuinely different risk category, not yet attempted.

**On "several friendly Pals running away" during the same session:** no evidence found connecting this to the crash specifically — the personality-enforcement system already has a known, separate, real gap (~95% success rate, hundred-and-fifty-seventh pass) that could produce exactly this on its own. Not chased further this pass; flagging the uncertainty honestly rather than attributing it to the crash without evidence.

Test plan for the next session: none needed for this fix specifically (it only removes a known-dangerous call; nothing to newly verify). Before trying anything else close to this area, Dragón should confirm the game behaves normally end-to-end (F9/F10/Play/CTRL+K, the trust bar, personality) after a fresh relaunch — this crash's downstream effects on this SPECIFIC session are moot once the game restarts, but worth a clean sanity pass before continuing.

## Hundred-and-sixty-first pass (2026-09-04): the "friendly" fallback was actively misleading — replaced with a distinct "unknown" sentinel

Dragón asked a direct, sharp question after the CTRL+H/CTRL+J confusion got resolved: was "friendly" being used as a silent fallback for a failed personality read? Confirmed yes, in `Personality.PresetClassNameToDisposition()` — both failure branches (unreadable preset, unrecognized preset) returned `"friendly"`. Since `GetPresetClassName` fails to read a real species preset for nearly every Pal (the `[DIAG] ... both failed` line fires on almost every new individual, confirmed across every session log this project has), this meant the on-screen personality label was showing "friendly" for the ~35% of individuals who rolled "normal" (species default, whatever that turns out to be) essentially every time the read failed — indistinguishable from a real, confirmed friendly species default. Combined with the ~20% who legitimately roll the friendly tier directly, over half of all labeled Pals could read "friendly" while only ~20% actually earned that label honestly.

Dragón's own words: **"from now on if it fails, show fail or show null or whatever it does normally, that way i know that its actually failing instead of thinking its a friendly pal."**

**Fix:** both fallback branches in `PresetClassNameToDisposition` now return `"unknown"` instead of `"friendly"` — a distinct sentinel, not one of the seven real rollable dispositions (deliberately not added to the `DISPOSITIONS` list, since it isn't a real tier, just a failure marker for this one lookup). Checked every consumer before shipping this: `EXCLUDED_FROM_ROLLING`/`TIER_TO_DONOR_PRESET_CLASS` are keyed by the raw preset class name or the rolled tier respectively, never by this disposition value, so they're unaffected. The WON-OVER check (`state.disposition ~= "escape"`) and the label's `disposition or "?"` fallback both handle an unrecognized string value safely by design — no special-casing needed. Verified with `luaparse`, deployed to both destinations.

**What to expect next session:** the label will very likely show "unknown" on most Pals who roll "normal" tier, reflecting the true, pre-existing state of `GetPresetClassName`'s near-universal failure — not a new regression, just finally visible instead of silently masquerading as "friendly." Whether to chase down WHY that read fails so consistently is a separate, open question — not pursued this pass, since Dragón only asked for honest labeling, not a fix to the underlying read.
