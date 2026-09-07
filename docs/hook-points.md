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


## Historial archivado (Ninth pass a Hundred-and-eightieth pass)

**2026-09-06:** este archivo había crecido a más de 760KB. El log técnico completo de las pasadas "Ninth" a "Hundred-and-eightieth" (2026-09-01 a 2026-09-05, antes de la investigación de balance) se movió, sin resumir ni borrar nada, a `hook-points-archive.md`. **No hace falta leerlo para continuar el trabajo** — las 6 secciones de referencia de arriba y las pasadas recientes de abajo (Hundred-and-eighty-first en adelante) ya tienen todo lo necesario. Mismo criterio aplicado a `../CLAUDE.md` / `../CLAUDE-archive.md`.

## Hundred-and-eighty-first pass (2026-09-05): balance research — real friendship-rank curve retrieved, easy/balanced toggle implemented, do_pet() correction, live diagnostic queued for the two remaining unknowns

Dragón asked for four things ahead of the balance pass: an easy/balanced difficulty toggle, what data is readable off a Pal, the real per-rank friendship-point curve (found once before, never saved), and the real Kinship Peach friendship values.

**Correction on the previous pass's do_pet() claim.** Said "do_pet() is confirmed dead" based on a grep for a literal `RegisterKeyBind.*F9` that missed the real binding — `PET_KEY = "F9"` and the actual registration is `RegisterKeyBind(Key[PET_KEY], ...)`, a variable lookup the literal-string grep couldn't match. F9 is still live and still calls `do_pet()` directly. The earlier trace of `do_interaction`'s player-busy gate rejecting the call is still correct, but only for the specific case of `do_pet()` being invoked FROM `closeRadialMenuActionWindow` (the "4" menu Care flow) — where the real vanilla Care action has already occupied the player's action slot by the time it runs. Called directly via F9 (no real vanilla action having just fired), the player usually isn't mid-action, so `do_interaction` can genuinely succeed there. So: dead only in the "4"-menu call path, not dead overall.

**Real data available off a Pal**, read directly off `FPalIndividualCharacterSaveParameter` (the same plain field, already safely read elsewhere in this project for `OwnerPlayerUId`): `Level`, `Rank` (talent rank) plus `Rank_HP`/`Rank_Attack`/`Rank_Defence`/`Rank_CraftSpeed`, `Talent_HP`/`Talent_Melee`/`Talent_Shot`/`Talent_Defense` (IVs), `Exp`, `Hp`/`MaxHP`, `IsRarePal`, `Gender`, `FriendshipPoint` itself, and more. All plain scalar fields, same safe read pattern as everything else this project already does.

**Real friendship-rank point curve — retrieved via repak against `Pal-Windows.pak`, hand-decoded from the raw binary.** `Pal/Content/Pal/DataTable/Friendship/DT_FriendshipRankTable.uasset`/`.uexp` (struct `FPalFriendshipRankDataRow { int32 FriendshipRank; int32 RequiredPoint; }`, confirmed in the header dump) is tiny (263-byte uexp) — hex-dumped and manually decoded the little-endian int32 pairs directly, since the file was too small to justify scripted tooling. Real values, Rank → RequiredPoint: 1→6000, 2→13000, 3→21000, 4→30000, 5→40000, 6→55000, 7→80000, 8→110000, 9→150000, 10→200000. (The asset also has 4 special named rows — `Friendship_Rank`/`_Minus1`/`_Minus2`/`_Minus3` — likely a separate negative/penalty tier, not decoded this pass, not relevant to the positive 1-10 curve Dragón asked for.) **This is nowhere near our own `CAPTURE_AT_FRIENDSHIP_POINT = 55`** — rank 1 alone needs 6000 real points. Flagged as a real design decision for Dragón: track the mod's own smaller/faster scale (current approach) or actually key off vanilla's real curve (much slower, but "authentic").

**Real vanilla Petting/Kinship-Peach values — NOT pinned down statically, queued as a live diagnostic instead.** Found the real balance-constants class (`UPalGameSetting`, confirmed in the header dump with a dedicated `FriendshipPoint_Petting` field alongside `_AutoIncrementOtomo`/`_AutoIncrementActiveOtomo`/`_AutoIncrementWorker`/`_Starvation`/`_Sick`/`_Dead`/etc.), but its Blueprint defaults (`BP_PalGameSetting.uasset`) don't serialize that field's name in its own local asset — likely inherited from elsewhere (an .ini config or a different base) rather than easily hand-parseable from this one file. Similarly, `UPalStaticItemDataBase` (the Kinship Peach's own static item data class) has no obviously-named friendship field — probably a generically-reused field (`FloatValue1` is a candidate) whose meaning depends on item type, not confirmable from the header dump alone. Rather than keep guessing statically, added `run_balance_diagnostic_once()` to `Interaction.lua` — a one-shot, read-only diagnostic that runs automatically at `Init()`: reads `UPalGameSetting`'s CDO fields directly (`FriendshipPoint_Petting` and siblings), and resolves `AffectionFruit_01`/`AffectionFruit_02`'s real static item data via `UPalUtility.GetItemIDManager()` → `GetStaticItemData()` (both confirmed real in the header dump) and fully dumps their properties to find whichever field actually holds the friendship bonus. No gameplay effect, no key needed — just needs one normal game launch to produce the numbers in the log.

**Easy/balanced toggle — implemented.** `Trust.lua` gained `EASY_TEST_MODE` (defaults `true`) as the single flag controlling `INTERACTIONS_TO_START_FOLLOWING`/`PASSIVE_FRIENDSHIP_PER_GAIN`/`DAMAGE_FRIENDSHIP_PENALTY`/`CAPTURE_AT_FRIENDSHIP_POINT`, each now split into an `EASY_*`/`BALANCED_*` pair. The `BALANCED_*` numbers are deliberate placeholders (identical to `EASY_*` for now) — real values are Dragón's call once the balance pass has the data above to work from; this pass only confirms and builds the mechanism, not the numbers.

Verified with `luaparse` on both files, deployed. **Next session:** just launching the game once should produce the `[BALANCE-DIAG]` lines with the real Petting value and the Kinship Peach's real property dump — no action needed beyond that.


## Hundred-and-eighty-second pass (2026-09-05): real crash in the balance diagnostic — a CDO passed as WorldContextObject, fixed with a live player actor

The previous pass's `run_balance_diagnostic_once()` crashed the game for real (`EXCEPTION_ACCESS_VIOLATION`) on Dragón's very next launch — but not before the `UPalGameSetting` reads already succeeded and logged real numbers (`FriendshipPoint_Petting = 30`, `FriendshipPoint_AutoIncrementOtomo = 10`, `_AutoIncrementActiveOtomo = 50`, `_AutoIncrementWorker = 1`, `_Min = -15000`, `_Max = 250000`, `_Starvation`/`_Sick`/`_Dead = -100`, `_SleepOnSide = 100`). The crash happened immediately after, before any item-related log line printed.

**Root cause:** `utility:GetItemIDManager(utility)` — passed the `Default__PalUtility` CLASS DEFAULT OBJECT itself as the function's `WorldContextObject` argument. A CDO isn't a live, in-world object — it has no real `UWorld` to resolve. The native function almost certainly walks `WorldContextObject->GetWorld()` internally and dereferenced garbage from that. Same category of danger already documented once before in this project (pcall catches Lua errors, never a native crash beneath them) but a NEW specific trigger: this is the first time this project passed a CDO as a `WorldContextObject` argument specifically, as opposed to calling a plain method that only reads a CDO's own fields.

**Fixed** by resolving `FindFirstOf("PalPlayerCharacter")` (the same live, in-world actor this file already resolves everywhere else) and passing that instead — a genuinely valid `WorldContextObject`. Added explicit before/after `[BALANCE-DIAG]` log lines around both this call and the subsequent `GetStaticItemData` calls, so if anything still goes wrong, the log pinpoints exactly which call, per this project's established crash-diagnosis discipline.

**Worth noting for Dragón's balance question:** `GetStaticItemData` reads the item's static DEFINITION, not anything from his personal inventory — both `AffectionFruit_01` and `AffectionFruit_02`'s real properties should get dumped regardless of which one (if either) he currently owns.

Verified with `luaparse`, deployed. **Test plan:** launch the game once more — the fixed call should get past where it crashed before and print the real property dump for both Kinship Peach tiers.

**Same pass, follow-up fix:** the crash fix above worked (no crash on Dragón's retest), but the item dump then got skipped entirely — `Interaction.Init()` runs before the player character exists in-world (still loading/at the menu), so the single `FindFirstOf("PalPlayerCharacter")` attempt found nothing. Same "class/actor not loaded yet" race this project has fixed with a bounded retry loop many times before (Radial Menu, Worker Menu, Indicator's BindFromHandle, EMOTE-WATCH). Restructured the item-dump half into `run_item_balance_diagnostic(round)`, retrying every 3s for up to 40 rounds (2 minutes) until a live player appears, then proceeding exactly as before. The `UPalGameSetting` half needed no such fix — it never depended on a live player.


## Hundred-and-eighty-third pass (2026-09-05): second real crash in the balance diagnostic — a raw Lua string passed as an FName argument, fixed with FindOrAddFName

Dragón's retest got further (the WorldContextObject fix worked, `GetItemIDManager` succeeded) but crashed again, traced precisely via the before/after logging added last pass: the log showed `[BALANCE-DIAG] about to call GetStaticItemData(AffectionFruit_01) NOW` with no matching "returned" line ever following — the crash happened inside that exact call.

**Root cause:** `manager:GetStaticItemData(itemId)` passed a plain Lua string (`itemId`) directly where the native function signature expects a real `FName` (`GetStaticItemData(const FName StaticItemId)`, confirmed in the header dump). This is the first time this project has passed a raw Lua string INTO a native function call as an FName argument — every prior FName use in this codebase only ever READ one back (`:ToString()`/`:Equals()` on an FName the engine already handed over, e.g. `ItemId.StaticId` comparisons), never constructed one to send TO a function.

**Real, proven fix, found in this UE4SS install's own bundled mods** (not guessed): `BPModLoaderMod`/`ConsoleEnablerMod` both construct a real FName via `UEHelpers.FindOrAddFName(string)` before ever passing one into a native call. Added `UEHelpers` to `Interaction.lua`'s requires and wrapped `itemId` through `FindOrAddFName` before the call.

Verified with `luaparse`, deployed. **Test plan:** relaunch — this is the diagnostic's third attempt after two real crashes, so if it fails again the honest move is to stop iterating blindly on this one and step back to figure out why, rather than keep guessing at native call shapes one at a time.

**Confirmed working, third attempt.** Real data for both Kinship Peach tiers, no crash:

| | AffectionFruit_01 (full) | AffectionFruit_02 (lesser) |
|---|---|---|
| `FloatValue1` (likely the friendship bonus) | 20000.0 | 2000.0 |
| Rarity | 3 | 1 |
| Price | 30000 | 20000 |
| RestoreSatiety | 10 | 1 |
| RestoreSanity | 100 | 10 |

Every stat scales by exactly 10x between the two tiers, reinforcing that `FloatValue1` (a generically-reused field on `UPalStaticItemDataBase`, confirmed via the earlier header-dump search finding no dedicated friendship field) really is the real friendship-point bonus — its magnitude (2000/20000) sits naturally in the same scale as the real friendship-rank curve found two passes ago (6000 at rank 1, up to 200000 at rank 10), not an arbitrary small UI number. Closes the balance-research side task from this pass — Dragón now has real numbers for: vanilla Petting (30), the four AutoIncrement passive-gain rates, the four penalty values, the full 1-10 friendship-rank curve, and both Kinship Peach tiers' real bonuses.


## Hundred-and-eighty-fifth pass (2026-09-05): real balance numbers implemented — small vanilla-scale bonding, level-gap-scaled threshold, lump bonus at capture

Dragón's real design, refined through a live back-and-forth after the initial balance-research pass: rather than large custom numbers (1000/2000/7000/21000 per interaction) driving the bonding bar directly, wild bonding uses real, small, vanilla-scale amounts (Petting ≈30, Feed ≈60, both Kinship Peach tiers at their real discovered values), and the level-gap multiplier scales the SIZE of a small bonding threshold (`BONDING_TRIGGER_THRESHOLD_BASE = 100`, Dragón's own example number) rather than each individual gain — a much-higher-level Pal needs a proportionally bigger bar filled with the same real numbers, not bigger numbers. Once that threshold is reached, one lump bonus (`CAPTURE_BONUS_TARGET_POINT = 21000`, real vanilla Rank 3) pushes the Pal's real total up before the actual capture call, so the newly-owned Pal starts meaningfully bonded instead of at a tiny real total.

**Why this is simpler and lower-risk than the first draft:** Pet/Play need NO override of vanilla's own real grant at all — Happy's internal AddFriendShip side effect just applies untouched, same as it always has. Feed (currently zero real credit for wild Pals) gets an explicit grant sized off the real Petting amount rather than an arbitrary round number. Only the THRESHOLD comparison and the one-time capture bonus are new code — no new native call shapes, nothing like the FName/CDO crash risk from the research phase itself.

**Trust.lua:** `Trust.ComputeLevelMultiplier(palActor)` — reads `SaveParameter.Level` off both the Pal and the live player (same field, confirmed via `IsPlayer` on the save struct), returns 0.2/0.5/1/2/4 by level gap (gaps between Dragón's five named breakpoints default to the "roughly equal" x1 tier — an interpretation, flagged as such). Returns a flat 10x instead while `EASY_TEST_MODE` is on, per Dragón's explicit ask to skip level-gap math during testing. `get_bonding_threshold(pal)` = `BONDING_TRIGGER_THRESHOLD_BASE / multiplier`, used by `maybe_trigger_capture` (the actual gate) and exposed as `Trust.GetBondingThreshold` for Indicator.lua's bar ratio (previously read a flat global constant — now correctly per-Pal). `maybe_trigger_capture` now also applies the lump capture bonus (never reducing an already-higher total, e.g. from peach use) before calling `Capture.OnTrustMaxed`. `OnFollowerDamaged` gained an `attackerIsPlayer` parameter — a normal hit still costs `DAMAGE_FRIENDSHIP_PENALTY` (rescaled -150, roughly 5x real Petting, keeping Dragón's original ratio at the new scale), but player-inflicted damage hard-resets the Pal's real FriendshipPoint to 0 and immediately flees it ("betrayal") — detected via FullName comparison against the live player in the DamageEvent hook, same pattern already used elsewhere in this project for excluding the player by name rather than by reference. Passive gain while following changed from a flat amount every Nth tick to `PASSIVE_FRIENDSHIP_PER_TICK = 10` every tick (~1.5s) — a real vanilla-scale starting rate (matching `FriendshipPoint_AutoIncrementOtomo`), not the exact real interval (which wasn't captured), left as the one number Dragón plans to retune live in-game (he's considering 200/sec-equivalent after testing) — deliberately NOT scaled by the level-gap multiplier, since gains stay flat now and only the threshold scales.

**Interaction.lua:** `FEED_FRIENDSHIP_BASE = 60` (2x real Petting, keeping Dragón's original "Feed worth double Pet" ratio at vanilla scale), `KINSHIP_PEACH_LESSER/FULL_FRIENDSHIP_BASE = 2000/20000` (the real values found in the balance-research pass). The `RequestUseToCharacter` manual-decrement post-hook (already the confirmed place where a real wild Feed lands) now also reads the consumed item's ID, grants the matching amount directly via `AddFriendShip`, and calls `Interaction.OnWildPalPetted` so the interaction counts toward follow-triggering/capture bookkeeping — none of this existed before (real wild Feed granted zero trust until now).

**Left deliberately untouched, flagged for Dragón:** `INTERACTIONS_TO_START_FOLLOWING` (still 5 raw interactions, not yet the percentage-of-bar trigger discussed earlier) — the earlier-diagnosed root cause (the interaction counter not incrementing reliably once Pet/Feed mostly route through real vanilla actions) is still unfixed. This pass only implemented the real point VALUES Dragón specified; the follow-trigger redesign is a separate, not-yet-actioned piece.

Verified with `luaparse` on all three files, deployed. **Test plan:** bond with a wild Pal near your own level (roughly x1) and watch the bar fill via normal Pet/Feed; try a much-lower-level Pal to confirm the bar fills faster (smaller threshold); confirm a full Kinship Peach one-shots an equal/lower-level Pal; confirm the Pal's real FriendshipPoint lands at 21000 right at capture; test a player-inflicted hit on a following Pal for the betrayal reset.


## Hundred-and-eighty-sixth pass (2026-09-05): Dragón's exact multiplier tiers + refined base numbers

Dragón gave exact bar-multiplier tiers (4x/2x/1x/0.5x/0.25x by level gap) and asked whether they correctly translate the original gain-multiplier idea (0.2x/0.5x/1x/2x/4x). Checked: four of five are exact reciprocals (1÷0.5=2, 1÷1=1, 1÷2=0.5, 1÷4=0.25), the fifth (top tier) rounds 1÷0.2=5 down to a cleaner 4 — a correct, faithful translation.

**Direction flip caught while implementing:** `Trust.ComputeLevelMultiplier` now returns a BAR-SIZE multiplier directly (bigger number = bigger/harder bar), the mirror image of the old gain-multiplier framing. This meant `get_bonding_threshold` had to change from dividing to multiplying (`BASE * multiplier`, not `BASE / multiplier`), and — easy to miss — `EASY_TEST_MODE`'s flat override had to invert too: Dragón's "10x easier while testing" now means returning `1/10`, not `10`, since a bigger bar-size multiplier makes things HARDER under the new framing, not easier. Renamed `EASY_TEST_FLAT_MULTIPLIER` to `EASY_TEST_SPEEDUP` to make the inversion explicit at the point of use rather than leaving a confusingly-named constant holding an inverted value.

**Refined base numbers, all Dragón's exact figures:** `BONDING_TRIGGER_THRESHOLD_BASE` 100→500, `PASSIVE_FRIENDSHIP_PER_TICK` 10→5 ("10 seems too high"), Kinship Peach amounts moved off the raw real vanilla `FloatValue1` values (2000/20000) to clean numbers sized directly against the new 500 base (250 lesser / 500 full — the full peach now grants exactly one base bar's worth in a single use at equal level, a clean one-shot). Pet/Play (real vanilla ≈30), Feed (60), damage penalty (150), and betrayal (hard reset to 0) were already correct from the previous pass, confirmed unchanged.

Verified with `luaparse` on both files, deployed.

**Same pass, follow-up:** `EASY_TEST_MODE` flipped to `false` — Dragón wants to test the real level-gap-based multiplier first, and will ask explicitly to flip it back on only when testing something needing fast repeated bonding (following, combat assist, etc.).


## Hundred-and-eighty-eighth pass (2026-09-05): real lag bug caught by Dragón — level multiplier recomputed every tick for every visible Pal, fixed with a permanent per-Pal cache

Dragón reported terrible lag spikes, especially running into new areas, and correctly diagnosed the cause himself: `Trust.ComputeLevelMultiplier` was being called fresh every single tick for EVERY Pal with a visible trust bar (Indicator.lua's `get_friendship_ratio`, called from `update_trust_bars`, itself running every scan tick for every tracked bar) — not just Pals actually being interacted with. Each call did a real component lookup + field read on the Pal AND a fresh `FindFirstOf("PalPlayerCharacter")` + another component lookup on the player, every time — cost that scales directly with how many Pals are on screen, the same "real per-tick work instead of a cached read" mistake this project has hit and fixed several times before (`SelectResponseBySenses`, `UpdateInteractTargetName`, the earlier trust-bar full-rebuild fix).

**Fix, Dragón's own exact diagnosis and proposed solution:** "it should be calculated on the interactions... maybe saved in the cache." A Pal's level never changes mid-session, so the multiplier is now cached PERMANENTLY per-Pal (`LevelMultiplierCache`, keyed by the same `GetFullName()` identity already used throughout this file) the first time it's computed for that Pal — any later call, whether from a real interaction or the bar just wanting to display something, is a cheap table lookup instead of a fresh computation. Only real staleness risk: a mid-session player level-up leaves already-cached Pals using the old multiplier — accepted as a minor, rare trade-off against a real, definite, scales-with-Pal-count lag source.

Verified with `luaparse`, deployed. **Test plan:** the same kind of session that showed terrible lag before (running into a new area with several Pals) should feel meaningfully better now.


## Hundred-and-eighty-ninth pass (2026-09-05): removed the fallback entirely — a non-interacted Pal's threshold is never computed, not even once

Dragón's sharper follow-up to the previous pass's caching fix: even a single one-time computation (and cache write) per Pal is still wasted work for the vast majority of Pals, which spawn and despawn in the background and are never actually approached — "only save the data of pals that are being interacted — no interaction = no data needed besides the rolled personality." A cached fallback value is still a fallback.

**Fix:** `Trust.GetBondingThreshold(palActor)` now checks for a real `Trust.State` entry (created only by an actual interaction) BEFORE calling `ComputeLevelMultiplier` at all — no entry means it returns `nil`, not a default constant. `Indicator.lua`'s `get_friendship_ratio` treats `nil` as "nothing to show yet" and returns a ratio of 0 directly, skipping the division (and, critically, skipping the per-Pal level lookup and player lookup that used to happen even for the discarded fallback path). Zero per-Pal level computation, zero cache writes, for any Pal that hasn't had a real interaction — exactly Dragón's ask.

Verified with `luaparse` on both files, deployed.


## Hundred-and-ninetieth pass (2026-09-05): the bigger fix — the trust bar itself no longer builds for a Pal with no real interaction

Dragón asked a sharper structural question: does the bar get built for every Pal that spawns, or only ones you look at? Traced precisely: `Indicator.lua` scans the game's own native NPC-gauge container (`Canvas_Root`) every 2 seconds and builds/updates a custom trust bar for EVERY Pal the game itself currently shows a native HP gauge for — every Pal near/visible to the player, not just ones interacted with. In a busy area that's 15-20+ Pals, all getting a periodic point-read and widget refresh forever, regardless of interaction history — a real, separate, ongoing cost on top of the level-multiplier bug fixed two passes ago.

Compared directly against the "Pal Analyzer" reference mod (re-examined earlier this session): it doesn't piggyback on the game's own native gauge visibility at all — it runs its own `SphereTraceMultiForObjects` with a radius it controls, a narrower, self-defined scope.

**Dragón's choice: only build/update bars for Pals with a real interaction on record** (same principle already applied to the level multiplier, extended to the bar's existence itself). `Trust.HasBondingState(palActor)` — a plain `State[key] ~= nil` table lookup, no actor/component resolution of its own — gates `install_trust_bar` in `Indicator.lua` before any widget work happens. `resolve_pal_actor_from_gauge` was already being called unconditionally every scan tick (needed for the pre-existing reuse-check), so adding this cheap lookup on top introduces no new real cost. Deliberately does NOT mark `barInstalledForGauge[key]` when skipping this way (neither for "actor not resolved yet" nor "no interaction yet") — both cases need to keep re-checking on later scan ticks rather than permanently giving up on that exact gauge widget, so a Pal you interact with later still gets its bar once the cheap check starts passing.

Verified with `luaparse` on both files, deployed. **Test plan:** walking through a busy area with many Pals should no longer show bars on Pals you haven't interacted with at all — only Pals you've actually pet/fed get one, and lag from this specific source should drop further.


## Hundred-and-ninety-first pass (2026-09-05): DAMAGE-WATCH was logging every hit in the entire game world, not just followers

Dragón read a pasted log excerpt and asked what all the noise was, then specifically flagged `[DAMAGE-WATCH]` as suspicious — it was firing for damage between wild Pals with no relation to the player's bonding Pals at all. Checked the code directly rather than guessing: the log line's own comment admitted it, dated back to the Eighteenth pass, whose only goal at the time was proving the hook fires at all. That question closed long ago, but the unconditional log line was never scoped down afterward. The real penalty logic right below it already correctly checked `State[defenderName] and State[defenderName].isFollowing` before doing anything — only the log line itself ran unconditionally.

**Fix:** moved the log line inside that same existing check, so it only prints for a Pal actually being tracked as following. Verified with `luaparse`, deployed. **Confirmed working in the very next real session** (pass 193's test): 14 real combat checks fired, `[DAMAGE-WATCH]` logged zero lines — proof the fights happening weren't relevant to any tracked Pal.


## Hundred-and-ninety-second pass (2026-09-05): DIAG-PANEL trimmed — same pattern, a widget-structure investigation from the fifty-first pass never got its logging turned back down

Same log excerpt, same question. `[DIAG-PANEL]` (Indicator.lua) was logging a "child count changed" line every time the game's own native gauge-pool container gained/lost a widget, plus an identify line for every distinct gauge widget object ever seen that session — both left over from mapping out that pool's structure back in passes 28-30, fully documented and closed since the fifty-first pass. In a busy area the count changes almost every 2s scan tick, so this was pure, unconditional log volume for a question with no more open ends.

**Fix:** cut both log lines. Kept everything functional — `inspect_gauge_widget`/`install_trust_bar` still run on every gauge child every scan (needed for the trust bar system), and the "unreadable child" error-path log stays (a real fault signal, not investigation noise). Also kept the one-time-per-genuinely-new-class property dump, since that still has real value if the game ever introduces a gauge class this project hasn't seen. Verified with `luaparse`, deployed. Confirmed in the next session: dropped from over a thousand lines in a comparable session to a single line.


## Hundred-and-ninety-third pass (2026-09-05): a dedicated test run closed all four of OtomoWatch's remaining open threads at once

Dragón asked for one real test session designed specifically to close out OtomoWatch.lua's genuinely-still-open investigation threads, so the confirmed-dead ones could be cut. Four things were watched across one session containing a real sphere capture (DreamDemon), a real sphere-less capture (FlowerDoll, auto-triggered via `Trust`'s bonding threshold), and a real cage release (Hedgehog Ice) at a settlement:

- **`ABP_PalCaptureJudgeObject_C` / `[CAPTURE-JUDGE]`**: never fired across any of the three capture-type events. Consistent with every session before it (twenty-eighth pass onward) — confirmed, for good, that this class belongs to the Arena/challenge capture flow, not normal field capture. **Removed** (both the existence poll in OtomoWatch.lua and the native `RegisterHook` on `PalCaptureJudgeObject.OnCaptureSuccess`).
- **`ABP_CaptureWire_C`**: never fired either, across the same three events, on top of every prior session. Its purpose was never even confirmed. **Removed** (the existence poll in OtomoWatch.lua).
- **`PawnOtmoIsPartyOtomo` / `[PARTY-DIAG]`** (Interaction.lua, fires on real wild-Pal "4"-menu substitution): checked 17 times this session, including real substitutions — `FindAllOf(PalPlayerPartyPalHolder)` found 0 live instances every single time. Confirmed dead for this project's actual scope (singleplayer, no Arena) — that class structurally doesn't exist outside Arena mode. **Removed** the call site in Interaction.lua; the diagnostic function itself is left in place, commented at the call site, in case Arena support is ever revisited.
- **`ABP_ReturnPalEffect_C` / `[PRISM-SPY]`**: the real surprise. Every single instance this session lined up almost to the second with an `[INACTIVATE-CURRENT]` event — the "put your current Otomo away" call that fires on an Otomo SWAP, not a capture. It never fired near either real capture or the cage release. This overturns the months-old "capture light-beam" theory from the forty-fifth/forty-sixth passes — an early test just happened to have a Pal-swap land close in time to a capture, which is why it looked related. The mystery is genuinely solved now, just not with the expected answer. Since there's nothing left to investigate about it, **removed** the existence poll in OtomoWatch.lua.
- **`UBP_ActionUnlockCagePalLock_C`**: fired exactly once, right at the real cage-door-open moment — confirmed real and working as expected, same as prior sessions. **Kept** (it's the one poll that's actually telling the truth about something), even though there's no further gameplay use planned for it right now.

All four removals verified with `luaparse` on `OtomoWatch.lua` and `Interaction.lua`, deployed to both destinations. No behavior change for anything Dragón actually uses — this was pure now-answered research instrumentation.


## Hundred-and-ninety-fourth pass (2026-09-05): personality label restored for every spawned Pal — decoupled from the interaction-gated trust bar

Dragón confirmed the recent lag fixes made a real difference ("the game doesnt feel as laggy") but flagged a real regression: the hundred-and-ninetieth pass's fix (only build widgets for Pals with a real interaction on record) accidentally took the personality label down with it, since both were built together inside the same `install_trust_bar` function, gated by the same `Trust.HasBondingState` check. The label is the one thing Dragón explicitly wants visible on every spawned Pal from a distance, without interacting at all — he's also floated eventually exposing this as a real on/off setting once the wording/styling gets a polish pass.

**Fix: decoupled the two.** `install_trust_bar` now always builds the personality label for every gauge (personality is rolled once per individual regardless of interaction history, so there's no reason to gate this on bonding state), and only conditionally builds the real trust/friendship `ProgressBar` when `Trust.HasBondingState` is true — keeping the hundred-and-ninetieth pass's lag fix fully intact for the part that actually needed it (the bar's own per-tick refresh cost).

This required two supporting fixes, both real bugs that would have surfaced immediately on live testing otherwise:
- `reparent_existing_bar` used to require `entry.bar` to already be valid just to move the LABEL to a recycled gauge — a label-only entry (no bar yet) would always fail this check and fall through to full re-construction, silently building a duplicate label every time its gauge got recycled. Now handles bar and label independently, moving whichever actually exists.
- `update_trust_bars`'s per-tick validity check used to require `entry.bar:IsValid()` unconditionally — with `entry.bar` now legitimately `nil` for non-interacted Pals, this would have dropped (and rebuilt) every label-only entry, every single tick. Fixed to only require bar validity when a bar exists.

Also added `try_upgrade_entry_with_bar(entry)`: when a label-only Pal has its first real interaction, this builds the real trust bar right then and attaches it to the entry that's already there — called both right after a gauge-reuse in `install_trust_bar` and from `update_trust_bars`'s own per-tick loop (a cheap `Trust.HasBondingState` table lookup), so the bar appears the moment bonding starts rather than waiting for that exact gauge widget to recycle.

Verified with `luaparse`, deployed. **Test plan:** every spawned Pal should show its personality word again immediately, with the friendship bar itself still only appearing once you've actually interacted with that specific Pal.


## Hundred-and-ninety-fifth pass (2026-09-05): the FlowerDoll instant-vanish bug fixed, and the raw 5-interaction/one-shot triggers replaced with real bar-percentage triggers

Dragón reported a jarring real bug: feeding a wild Petallia a Kinship Peach via the real inventory-based Feed menu filled her whole bonding bar in one lump grant, and she vanished into the party instantly — no player feeding animation, no Pal eating animation, no Happy reaction, nothing. He also asked to confirm whether two previously-discussed bar-percentage triggers (>10% bar → becomes friendly, >50% bar → starts following) were actually implemented yet, since neither seemed to be firing for a Petallia he was petting.

**Root cause of the instant-vanish, confirmed in the code:** `Trust.maybe_trigger_capture` called `Capture.OnTrustMaxed(pal)` — the real capture, which makes the Pal actor vanish from the world — completely synchronously, the instant the friendship threshold was crossed, with zero regard for whatever real animation might still be playing. Not peach-specific: any threshold crossing could in principle cut an animation short, but the peach's single large grant made it happen every single time instead of only occasionally with gradual pet-by-pet gains.

**Fix, per Dragón's own stated preference (wait for the real animation to finish, not a fixed delay, since animation lengths may vary and it "plays more natural into the flow"):** `ActionComponent:ActionIsEmpty()` — already a real, proven busy-check this project uses elsewhere (`do_interaction`'s own gate, on both the player and the target Pal) — is now polled on the Pal every 500ms after the threshold is crossed, and the real capture only fires once it reports idle. A generous 20-second safety cap (some real animations, like Play's idle-rest clips, have been observed running 20+ seconds) prevents ever waiting forever if it somehow never resolves true. If the Pal's `ActionComponent` can't even be read at all, falls back immediately to Dragón's explicit fallback number — a flat 5-second delay — instead of polling something unreadable.

**Confirmed: neither bar-percentage trigger existed in code.** "Start following" still used the raw `INTERACTIONS_TO_START_FOLLOWING = 5` counter (already flagged as unreliable since pass 132 — Pet/Feed mostly route through real vanilla actions now, which don't reliably hit that counter). The "becomes friendly" mechanic was a one-shot, escape-tier-only event fired on a Pal's very first successful interaction (`Personality.OnSuccessfulInteraction`) — nothing checked bar percentage at all.

**Both replaced, per Dragón's explicit numbers, and per his instruction to remove the old mechanics entirely rather than keep them as a fallback:**
- `Trust.lua`: `FOLLOW_TRIGGER_RATIO = 0.5` and `FRIENDLY_TRIGGER_RATIO = 0.2`, both fractions of the same `get_bonding_threshold(pal)` used everywhere else. Checked in `Trust.OnInteractionSucceeded` right after a real point read — `tick_followers`' passive-gain path doesn't need its own copy of this check, since it only ever processes Pals that are ALREADY following, which by construction can only happen after the 50% follow-trigger already fired via the interaction path.
- `Personality.lua`: `Personality.OnSuccessfulInteraction` renamed and generalized to `Personality.MaybeBecomeFriendlyByBar(palId, palActor)` — removed the old "only if currently 'escape'" restriction, since the new trigger is meant to apply from any starting disposition (any Pal that's had real, sustained positive interaction warms up, not just the shy tier). Called from `Trust.OnInteractionSucceeded` (which has the real ratio) instead of from `Interaction.lua`'s old event-only call site, which was removed.

Verified with `luaparse` on `Trust.lua`, `Personality.lua`, and `Interaction.lua`, deployed. **Test plan:** feed a wild Pal a Kinship Peach via the real "4" menu and confirm the eat/happy animation actually plays out before it vanishes into the party; separately, pet/feed a Pal past 20% of its bar and confirm its personality label flips to "friendly", then continue past 50% and confirm it starts following, without needing five distinct interactions to count.

## Hundred-and-ninety-sixth pass (2026-09-05): live retest of the Hundred-and-ninety-fifth pass's four fixes — one confirmed working, three real bugs found and root-caused (two fully, one partially), none fixed yet

Dragón ran a real test round covering all four items from the previous pass and reported back point by point, plus pasted a large raw log excerpt. **No code was changed in this pass — investigation only, halted mid-way by Dragón's explicit "wait stop here" before any fix was written.** This entry exists to hand off the investigation state precisely, since the session ended here.

**1. Personality label — CONFIRMED WORKING.** Dragón: "thanks i see it again, very useful." The always-visible-label decoupling from pass 194 holds up in real play. No further action needed on this item.

**2. Instant-vanish bug — STILL HAPPENING. The pass-195 fix (`ActionComponent:ActionIsEmpty()` polling) does not work, and Dragón correctly diagnosed why in his own report before any log was read:** "i asume its because you set it at the actionisempty(), which probably happens briefly between interactions, so its not a reliable method." Confirmed exactly right by the pasted log: `wait_for_animation_then_capture`'s very first poll (0.5ms after starting) already reported `idle == true`, while `Combat.lua`'s own separate, already-existing read-only diagnostic (`[FOLLOW-DIAG]`, from the "eighty-sixth pass," reading `pal.Controller:GetAIActionComponent():GetCurrentAction_BP()`) fired ~0.8ms EARLIER in the same log window showing a real, non-nil, still-running AI action (`BP_AIActionPairCall_FeedItem_C`). So `pal.ActionComponent:ActionIsEmpty()` is not tracking the same "busy" state as the AI's real multi-step Feed/eat/happy action pair at all — it clears almost instantly, for reasons unrelated to how long the real animation sequence actually runs.

**Fix identified but NOT implemented:** replace the poll signal in `Trust.lua`'s `wait_for_animation_then_capture` from `pal.ActionComponent:ActionIsEmpty()` becoming `true` to `pal.Controller:GetAIActionComponent():GetCurrentAction_BP()` becoming `nil` (or some other confirmed-non-busy state on that same accessor) — keeping the exact same overall structure already in place (bounded `ExecuteInGameThreadWithDelay` polling, the existing generous safety cap, and Dragón's explicit flat-5-second fallback if this signal turns out to be unreadable on a given Pal). This was the very next planned step when the session was halted.

**3. Follow trigger not producing visible following behavior — NOT YET ROOT-CAUSED WITH DIRECT LOG EVIDENCE for the specific case Dragón reported.** Dragón: "didnt work, tested it with another petallia, reaching above 50%, she never followed, only roamed around with her usual AI." The pasted log's only visible follow-trigger firing (`[Trust] bonding bar crossed 50% (ratio=1.04)` + `[Combat] ... marked as following (bonding)`) happened in the SAME instant as the capture threshold also being crossed (a Kinship Peach pushing past both 50% and 100% at once) — so that particular log has no time window in which following behavior could ever have been observed; it is not evidence of a bug in that instance. The second Petallia Dragón describes (crossing 50% without also capturing) never appears in the pasted log at all.

Working hypothesis, NOT confirmed: `Combat.lua`'s actual follow mechanism (`Combat.StartFollowing` sets `BondingState[key] = true`, then `Trust.lua`'s `tick_followers()` reissues `Combat.IssueFollowMoveOrder` → `controller:PalMoveToLocation(...)` roughly every 1.5s) has always been documented in this project (including in `Combat.lua`'s own header comments) as a periodic external "nudge" competing with the wild Pal's own AI between ticks, not a real Otomo-style AI override — this is literally the pending Fase 2 / item 5 on Dragón's own priority list ("Seguimiento real durante el vínculo... [FOLLOW-DIAG] nunca se leyó"), predating this session. It's plausible the trigger is now firing correctly (confirmed by log) but the underlying follow mechanism itself is the same known-weak approximation, not something newly broken. This needs either more log evidence from a case where the trigger fires without an immediate capture, or a direct decision from Dragón on whether to reopen the deferred "real follow during bonding" work now.

**4. Friendly trigger fires correctly (tracked state), but the real in-game AI never actually changes — ROOT-CAUSED IN TWO LAYERS, neither fixed.** Dragón: "if a pal is running away (escape) or already fighting the player (warlike), and the interaction changes its personality to friendly, it still keeps doing what it was doing... this obviously defeats the process of changing their personality." Confirmed twice in the log: right after `[WON-OVER] ... crossed the friendly-trigger fraction of its bonding bar`, the very next line both times is `[WON-OVER] ... has no readable AISensorComponent — cannot swap its real AI, tracked disposition still updated`.

*Layer 1 (root cause of the specific failure seen):* `Personality.MaybeBecomeFriendlyByBar` (renamed/generalized from the old `OnSuccessfulInteraction` in pass 195, but its internal sensor-lookup code was carried over unchanged) still calls the OLD, already-documented-as-unreliable proactive `find_sensor_component(palActor)` scan — the exact same mechanism this project already replaced with a much more reliable REACTIVE hook (`on_sensor_select_response`, listening to the game's own `SelectResponseBySenses` calls) for the periodic tier-roll enforcement path, back in the "Hundred-and-forty-eighth pass." That reactive-hook fix was never ported over to this WON-OVER/bar-triggered code path, which is why it still fails almost every time.

*Layer 2 (a deeper problem discovered while investigating layer 1, not yet worked around):* even if `MaybeBecomeFriendlyByBar` were switched to use the reactive hook's sensor, two further obstacles exist, both read (not fixed) this pass:
- `on_sensor_select_response`'s dedup table, `handledSensorKeys[sensorKey] = true`, is set PERMANENTLY the first time a given Pal's sensor is ever seen by the reactive hook — which for any Pal already fleeing/fighting BEFORE the player ever interacts with it (i.e., exactly the escape/warlike-tier Pals Dragón is testing) has almost certainly already happened during that Pal's original tier enforcement. This would silently block any future re-enforcement attempt for that same sensor, even after a later disposition change.
- `try_enforce_personality_with_sensor(palActor, palId, sensor)` (the shared function both the proactive scan and the reactive hook ultimately call into) reads `state.rolledTier` — the Pal's ORIGINAL rolled tier at spawn — not `state.disposition`, the current (possibly WON-OVER-changed) value. So even with a valid sensor in hand, this shared function would enforce the wrong (original) tier, not "friendly" — it was never designed to be disposition-change-aware. `MaybeBecomeFriendlyByBar`'s own separate inline enforcement code does correctly target `TIER_TO_DONOR_PRESET_CLASS["friendly"]` explicitly, so the fix, whatever it ends up being, needs its own reliable sensor source rather than simply routing through `try_enforce_personality_with_sensor` as-is.

Investigation was mid-way through reading `try_enforce_personality_with_sensor`'s exact gate logic (including a separate `state.enforcementApplied` boolean, itself set once-ever rather than per-target-disposition) and had not yet located where the proactive `try_enforce_personality` scan is actually called from on a timer, when the session was halted. No fix was designed for this item.

**Outstanding, never addressed this pass:** Dragón separately pasted a large raw log excerpt and asked "also please explain me all this" — that plain-language walkthrough was never given; the log was used directly as root-cause evidence for items 2–4 above instead. Still owed in a future session if he asks again.

No code changes in this pass. Live deployed state remains exactly what pass 195 shipped (label fix confirmed good; capture-delay via `ActionIsEmpty()` confirmed insufficient; 50%/20% ratio triggers confirmed firing correctly at the trigger-point level, with the follow-behavior and friendly-AI-swap failures described above still present). The Hundred-and-ninety-fifth pass's entry above should be read with this correction in mind — its capture-delay fix did not hold up under Dragón's follow-up test.

## Hundred-and-ninety-seventh pass (2026-09-05): all three outstanding bugs from the previous pass fixed — real evidence found in the game's own header dump for each, none confirmed live yet

Dragón approved proceeding with all three items left open by the previous pass, gave explicit design direction on two of them, and separately spotted a real, useful clue mid-session: the game's own "!" notice icon, which visibly interrupts whatever a Pal is doing to turn and face the approaching player — pointed at as a possible model for interrupting a mid-action Pal on a personality change (item 4 below). Located the real `Pal.hpp` on Dragón's actual game install this pass (`Palworld/Pal/Binaries/Win64/ue4ss/CXXHeaderDump/Pal.hpp`) and grepped it directly for each fix rather than reasoning from memory of earlier passes' notes.

**Item 2 (instant-vanish capture bug) — FIXED, matching the plan already identified in the previous pass.** `Trust.lua`'s `wait_for_animation_then_capture` no longer polls `pal.ActionComponent:ActionIsEmpty()` (confirmed unreliable last pass). New helper `is_pal_ai_action_idle(pal)` reads the SAME accessor `Combat.lua`'s own `[FOLLOW-DIAG]` already reads safely: `pal.Controller:GetAIActionComponent():GetCurrentAction_BP()` becoming nil (or invalid). Same overall structure kept: bounded polling every `CAPTURE_DELAY_POLL_MS` (500ms), the same 20-second safety cap, and the same flat 5-second fallback if the Controller/AIActionComponent chain itself can't be read.

**Item 4 (friendly swap doesn't change real behavior for a mid-action Pal) — Dragón corrected the diagnosis first.** He clarified directly: the swap DOES work and IS visible for a Pal that's idle/neutral (e.g. a notinterested Pal crossing 20% really does start acting friendly) — the actual problem is narrower: a Pal already mid-fleeing or mid-fighting keeps executing that already-decided action, since swapping `AIResponsePreset` only changes what a FUTURE decision reads, not whatever's already running. His question: is there a way to interrupt the current action so the Pal can act on its new personality instead of finishing the old one?

Grepped `Pal.hpp` for a real interrupt mechanism instead of reattempting anything like the eighteenth pass's `SetActiveAI(false)` (which killed a Pal's entire AI decision layer, not just its current action). Found two genuinely real, simple, never-before-called functions:
- `UPalAIActionComponent:AllCancelAction_Logic_HardScript_Reaction(Instigator)` — cancels whatever's running at the AI-decision priority tiers (the ones ordinary wild-AI flee/fight decisions run at), as opposed to lower-priority scripted background behavior. A plain single-pointer-argument call, on the same `AIActionComponent` this project already reads safely via `Controller:GetAIActionComponent()`.
- `UPalAISensorComponent:RequestSightCheckAsync(bIncludePlayer, bIncludeAliveNPC, bIncludeEdibleDeadNPC, RangeRate, bIgnoreOtomo)` — declared right next to `SelectResponseBySenses` in the header dump, almost certainly the real function behind the "!" notice trigger Dragón pointed at (a fresh sight check would naturally feed into a new `SelectResponseBySenses` decision, now reading the just-swapped preset).

New `interrupt_and_resense(palActor, sensor, palId)` in `Personality.lua` calls the cancel first, then the fresh sight check — mirroring the natural notice-and-turn sequence — and is now called right after every SUCCESSFUL preset swap in all three call sites that can change a Pal's tier: `try_enforce_personality_with_sensor` (the periodic/reactive enforcement path), `Personality.MaybeBecomeFriendlyByBar` (the 20%-bar trigger), and `Personality.ForceTier` (used by `Capture.OnTrustLost`'s flee-on-zero-trust). Best-effort only — any failure here leaves the tracked disposition/preset swap intact, just without the interrupt; every native call is bracketed with its own before/after log line (`[INTERRUPT]`), per this project's standing crash-diagnosis discipline, since both functions are being called live for the first time ever in this project.

**Item 3 (follow trigger fires but no visible following behavior) — Dragón explicitly asked to reopen the deferred real-follow work**, using the `AIActionComponent`/`UPalAIActionOtomoDefault` lead `Combat.lua`'s own "eighty-sixth pass" comment had already found and left untested, plus the `PalFunnelCharacter`/Daedream-style secondary-follower research from hook-points.md's "hundred-and-thirty-seventh pass."

Grepped `Pal.hpp` and confirmed the real mechanism: `UPalAIActionComponent:SetRootComposite(NewCompositeAction, Priority)` pushes a composite action onto the component's root; `UPalAIActionOtomoDefault : public UPalAIActionCompositeBase` exposes `SetOtomoFollowAction()`/`SetOtomoCombatAction()`/`SetOtomoWorkAction()`/`SetOtomoBerserker()`/`SetOtomoBaseCampAction()` — the literal decision layer a real Otomo Pal uses. New `attempt_real_otomo_follow(pal, key)` in `Combat.lua`, called from `Combat.StartFollowing` right after the existing read-only `[FOLLOW-DIAG]` check: resolves the native class via `StaticFindObject("/Script/Pal.PalAIActionOtomoDefault")`, builds a fresh instance owned by the Pal's own `AIActionComponent` via `StaticConstructObject` (the same safe-construction pattern already proven in `Personality.lua`'s `apply_forced_preset`), calls `SetOtomoFollowAction()` on it, then `actionComp:SetRootComposite(fresh, priority)`.

Gated STRICTLY on the same check `[FOLLOW-DIAG]` already does (a usable `AIActionComponent` must actually be readable) — if that's ever false for some wild Pal, this does nothing extra and the existing `PalMoveToLocation` move-order tick (`Trust.lua`'s `tick_followers`) stays the only follow mechanism, unchanged, in parallel. This is ADDITIVE, not a replacement — even a silent failure here can't make following worse than it already was. `EAIRequestPriority::Type` is a native, non-Palworld-specific Unreal engine enum (the classic Pawn Actions/AIModule system); its standard order is SoftScript=0, HardScript=1, Reaction=2, Logic=3, Ultimate=4 — "Logic" (3) was used, matching the tier ordinary AI-decided (non-player-scripted, non-reaction) behavior runs at, but this specific value is NOT confirmed against Palworld's own build and is flagged as the one real assumption in this fix.

**Real evidence found in the ALREADY-DEPLOYED live install's own log while investigating** (before this pass's changes were even copied over): `palbonds-live.log` already contained one real `[FOLLOW-DIAG]` line from a past session, never previously read — `BP_FlowerDoll_C` (Petallia) confirmed `HAS an AIActionComponent while wild — category=0 currentAction=BP_AIActionPairCall_FeedItem_C`. This directly answers the eighty-sixth pass's original open question (does a wild Pal's AIController even have a usable AIActionComponent at all) — yes, at least for this species/controller class — meaning `attempt_real_otomo_follow` above should actually get a chance to run rather than silently no-op on the Controller/AIActionComponent gate.

This is the biggest risk category this project has taken since the SetActiveAI(false) incident (constructing and attaching a real AI action object, not just reading a field or issuing a movement command) — every native call in `attempt_real_otomo_follow` is bracketed with its own before/after log line for the same reason.

Verified with `luaparse` (Trust.lua, Combat.lua, Personality.lua — all three parse clean), deployed to the real game install (`Palworld/Pal/Binaries/Win64/ue4ss/Mods/PalBonds/Scripts/`) and the `32-PalBonds/mod/` mirror. **NONE of the three fixes are confirmed live yet.**

**Test plan for the next session:**
1. Feed a wild Pal a Kinship Peach (or anything that crosses the capture threshold in one jump) via the real "4" menu — the eat/feed/happy animation sequence should now play out fully before the Pal is captured, instead of vanishing instantly. Check the log for `[PalBonds/Trust] ... finished its current AI action — proceeding with the real capture now` (or the safety-cap/fallback lines, if the new signal itself turns out unreadable).
2. Get a Pal that's actively fleeing or fighting to cross the 20% friendly-trigger threshold, and watch whether it visibly stops fleeing/fighting and starts acting friendly shortly after. Check the log for `[INTERRUPT]` lines confirming `AllCancelAction_Logic_HardScript_Reaction`/`RequestSightCheckAsync` were actually called and whether they returned `ok`.
3. Bond with a wild Pal until it starts following (crossing 50%) and watch whether it now follows noticeably better/differently than before — check the log for `[REAL-FOLLOW]` lines: does the Controller/AIActionComponent gate pass, does `StaticConstructObject`/`SetOtomoFollowAction`/`SetRootComposite` all report `ok`, and does the Pal's actual in-game movement look different (smoother, combat-assisting, etc.) from the existing move-order nudge alone. Report exactly what's observed either way — if `SetRootComposite` reports `ok` but nothing visibly changes, that's real evidence the "Logic" priority guess is wrong, not that the whole approach failed.

**Addendum, same pass — caught and fixed a real bug before ever deploying it (not found by testing, found by re-reading the diff):** `attempt_real_otomo_follow` was originally written and called from `Combat.StartFollowing` (textually earlier in the file) before its own `local function` declaration further down — the exact same mistake this project already made once and documented (hook-points.md's "hundred-and-fortieth pass," `hook_describe`): a local referenced before its own textual declaration silently resolves as a nil global instead of the intended upvalue, and since the call site was wrapped in `safe_call` (which swallows the resulting error), this would have failed 100% of the time with zero log trace at all — following would have looked completely unchanged, no crash, no error, nothing to even suspect. Caught by re-reading the file's own function-declaration order right after writing it, before the first deploy. Fixed by moving `attempt_real_otomo_follow`'s full definition (with its header comment) to before `Combat.Init()`, ahead of `Combat.StartFollowing`. `luaparse` does NOT catch this class of bug (referencing an undeclared local is still syntactically valid Lua, it just resolves as a global at runtime) — it only confirms the file parses, never that a local is actually in scope where it's used. Worth remembering for every future multi-function-add pass in this project: check declaration ORDER, not just syntax, whenever a new local function is both defined and called within the same file.

## Hundred-and-ninety-eighth pass (2026-09-06): live test of the hundred-and-ninety-seventh pass's three fixes — two real bugs found and fixed from direct log evidence, one confirmed engaging correctly, one deliberately not chased further

Dragón ran a real test covering all three items and pasted a large raw log excerpt from the actual session. Read it directly line-by-line rather than going only off his summary, cross-referencing his four questions against exact log lines.

**Item 4 interrupt — STILL failed, and the log shows exactly why: the fix from the previous pass never even got a sensor to act on.** For the specific Pal actually being bonded with (`BP_FlowerDoll_C`, palId `D71C177644B59AC1DF19BEA624D7FA83`), the WON-OVER trigger fired correctly (`crossed the friendly-trigger fraction of its bonding bar`), immediately followed by `has no readable AISensorComponent — cannot swap its real AI`. Since `apply_forced_preset` never ran, `interrupt_and_resense` (this project's own new fix from the previous pass) never got called either — it was never actually put to the test. This confirms the ORIGINAL diagnosis from the hundred-and-ninety-sixth pass ("layer 1": `MaybeBecomeFriendlyByBar` still uses the old one-shot, no-retry `find_sensor_component` search) is still the real, unaddressed blocker — Dragón's redirected question (interrupt the current action) was a real, separate problem, but it never got the chance to prove itself because the swap it depends on kept failing at an earlier step.

**Real fix this pass:** the reactive hook (`on_sensor_select_response`, listening to the game's own `SelectResponseBySenses` calls) sees a real, valid sensor reference for essentially every wild Pal in range, constantly — that's the whole reason its dedup table exists. New `cachedSensorByPalId` cache, populated by this hook for EVERY Pal it ever sees (previously the hook returned early for "normal"-tier Pals before any of this ran, and never cached anything for anyone) — a passive table write, no new native call. `MaybeBecomeFriendlyByBar` and `ForceTier` now check `find_cached_sensor(palId) or find_sensor_component(palActor)` — the cache first (a real, already-proven-valid reference, sourced from an actual live game callback instead of a search), falling back to the old scan only if nothing was ever cached for that Pal.

**Item 2 (capture-delay) — the previous pass's fix over-corrected, confirmed by all three real capture waits in this same log hitting the 20-second safety cap without exception.** `GetCurrentAction_BP()` never once returned nil across any of the three real waits — meaning a wild Pal's AIActionComponent apparently never actually reaches a "no action" state (some baseline wild-AI action — wander/graze/idle — always occupies it), so waiting for nil just burns the full cap every time. This is what let Dragón's Petallia wander far enough to leave render range (`267870 units away`) before capturing.

**Real fix:** stopped waiting for the signal to become nil, and instead wait for it to CHANGE from whatever action instance was occupying the component at the moment the wait started (compared by `GetFullName()` identity, e.g. `..._2147414499` vs `..._2147410040` — real, distinct object identities already visible in the pasted log). The specific action blocking capture (`BP_AIActionPairCall_FeedItem_C`, the real multi-step Feed sequence) finishing means the AI moves on to something else — whether that's a new wander action or (if it ever happens) nil — either counts as "done," rather than requiring the narrower and apparently-unreachable "no action at all" state.

**Item 3 (real follow) — CONFIRMED ENGAGING successfully all three times in this log**, exactly matching the design: `[REAL-FOLLOW] ... StaticConstructObject(UPalAIActionOtomoDefault) ok` → `SetOtomoFollowAction() ok` → `SetRootComposite(priority=Logic) ok`, every time the 50% follow trigger fired, running in parallel with the old `PalMoveToLocation` move-order tick exactly as designed (additive, not a replacement). Whether it's actually visibly BETTER following, or whether it enables real combat-assist, is still unconfirmed from a log alone — that composite class also exposes `SetOtomoCombatAction()` as a separate mode, which this project only calls when explicitly told to (not yet); whether the composite itself internally switches modes in response to combat (the way a real Otomo would) is unknown and needs an in-game observation, not a log line, to answer.

**Dragón's own idea, considered but NOT implemented this pass:** since `SetRootComposite` is now confirmed to really work, could the SAME mechanism (force a new root composite) be reused to interrupt a mid-action Pal on a personality change, instead of/alongside `AllCancelAction_Logic_HardScript_Reaction`? Good instinct — but the only composite class actually tried so far is `UPalAIActionOtomoDefault` set to FOLLOW mode specifically, which would make ANY Pal that turns friendly start actively walking toward the player immediately — even one that's only 20% through its bonding bar, well before the game's own 50% follow trigger is supposed to fire. Reusing it verbatim for the personality-interrupt case would blur two designed-to-be-separate thresholds together, not a safe direct reuse without picking (or confirming) a different, neutral composite mode first. Left as a real idea worth revisiting, not attempted blind.

Verified with `luaparse` (Trust.lua, Personality.lua — both clean), deployed to the real game install and the `32-PalBonds/mod/` mirror. **Still none of the three original items are confirmed fully working live** — items 2 and 4 have new, more targeted fixes; item 3 is confirmed to engage its new mechanism but its actual behavioral improvement is unconfirmed.

**Test plan for the next session:** (1) repeat a capture that used to visibly wander off — check whether it now captures within a few seconds of the real animation ending instead of always waiting the full 20s; (2) get a fleeing/fighting Pal to cross 20% friendly and check for `[WON-OVER]` followed by a real `[INTERRUPT]` sequence this time (not another "no readable AISensorComponent"), and watch whether its behavior actually changes; (3) watch a followed Pal during a real fight — does it appear to assist, or only follow.

## Hundred-and-ninety-ninth pass (2026-09-06): read the real live log directly (no paste needed) — the sensor-cache fix confirmed 5/5, capture-delay abandoned for a fixed delay after three distinct new failure shapes, passive gain nerfed

Dragón asked a design question about the capture delay, ran another real test, and asked to check the live log directly rather than re-paste it — read `palbonds-live.log` straight from the game install (`Palworld/Pal/Binaries/Win64/ue4ss/Mods/PalBonds/palbonds-live.log`) for this pass instead of waiting for a chat paste.

**Item 4 (interrupt) — CONFIRMED FIXED at the mechanism level, 5/5 real attempts this session.** Every `[WON-OVER]` this session (5 total, including one Pal whose rolled tier was "warlike") was immediately followed by a successful preset swap AND a successful `[INTERRUPT]` sequence (`AllCancelAction_Logic_HardScript_Reaction` + `RequestSightCheckAsync`, both "ok") — zero "has no readable AISensorComponent" failures, a complete reversal from the previous session's 0/2. The sensor-cache fix from the previous pass is confirmed working exactly as designed.

**But Dragón still didn't SEE any visible behavior change** — Pals kept fleeing/attacking after turning "friendly." Since every call in the chain now reports success with no Lua error, this is a new, deeper problem: `AllCancelAction_Logic_HardScript_Reaction` clearing the current action and `RequestSightCheckAsync` re-running the sense check don't necessarily force `SelectResponseBySenses` to re-derive its answer from scratch — the function's own signature takes `CurrentBehavior` as an input parameter, meaning an already-locked-in Escape/Battle state may just persist across the re-check rather than being reset, and/or some other persistent state (a target/aggro lock, possibly the old `HateSystem`/`TargetPlayers` fields flagged as "not it" back in early passes, or something not yet identified) may be what's actually keeping the Pal committed to its old behavior, independent of the preset. Not investigated further this pass — genuinely a new research question, not something to guess a third native call at blind.

**Item 2 (capture delay) — Dragón's own design question turned out to catch a real, unconfirmed risk in the previous pass's fix, and the log backed it up with THREE distinct new failure modes, not just the one being asked about.** He asked directly: doesn't capturing the instant the Feed AI-action changes risk cutting off the Happy reaction (which plays on a separate component, `pal.ActionComponent`, never checked by this signal)? Real, valid concern — and reading this session's 5 real captures showed the identity-change approach is unreliable in ways beyond that too:
- One capture (01:37:08) changed from the real Feed pair-call to a plain `BP_AIAction_WildLife_C` — a legitimate-looking transition, but with zero way to confirm Happy (on the other component) had actually finished playing.
- One capture (01:46:24) changed from `BP_AIAction_CombatPal_C` to a CHILD sub-action of that SAME parent (`...CombatPal_C_2147406593.BP_AIAction_AnimationSideStep_C_...`) — the Pal was still mid-combat, just transitioning to a combat sub-state, and got captured right in the middle of it.
- One capture (01:40:10) never saw the identity change at all in 20 real seconds and just hit the safety cap — the exact failure this same fix was meant to solve.

Three distinct failure shapes in one session, on top of the risk Dragón flagged directly, is conclusive: neither `AIActionComponent` signal (nil-check or identity-change) reliably tracks "did Feed+Happy actually finish." Real fix: abandoned the whole detection scheme and switched to a single flat delay (`CAPTURE_DELAY_FIXED_MS`, 4000ms) after the interaction crosses the capture threshold — honoring Dragón's OWN originally-stated fallback order ("wait for the real animation... falling back to a flat delay only if that isn't achievable") now that (1) has genuinely been tried three separate ways and failed live each time. Same honest pattern already accepted for Play's own Happy follow-up delay (`hook-points.md`'s "Hundred-and-forty-third pass") — no proven duration/completion signal exists for a one-shot reaction like Happy anywhere in this project; a tuned flat delay is the established, working answer for exactly this class of problem, not a new compromise.

**Item 3 (follow) — mechanism confirmed engaging 5/5 again this session, but ALL FIVE Pals that started following also got captured within the same short session**, most within a couple of minutes of the follow trigger (one within ~6 real seconds, per Feed grants stacking quickly). This directly explains BOTH of Dragón's remaining reports: "one Petallia crossed 50% and didn't follow at all" (all 5 real follow triggers this session DID succeed at the mechanism level — the most likely explanation is capture happening so fast afterward that there was no real window to see it move) and "the ones that did follow weren't helping me fight" (same cause — no real time window existed for a fight to happen between follow-start and capture). This isn't a new bug in the follow mechanism itself — it's the same problem driving Dragón's parallel request below.

**Real nerf applied, per Dragón's explicit ask:** `PASSIVE_FRIENDSHIP_PER_TICK` 5 → 2 — directly targets the too-short follow-to-capture window identified above, giving future tests actual time to observe following/combat-assist behavior before a Pal gets captured.

Verified with `luaparse` (Trust.lua), deployed to the real game install and the `32-PalBonds/mod/` mirror.

**Still open, unconfirmed:** whether the interrupt's real behavioral effect (not just its Lua-level success) can be achieved at all without further investigation into what state besides the preset keeps a Pal committed to fleeing/fighting; whether the new flat capture delay is long/short enough in practice (still needs a live look at whether Happy visibly finishes before capture); and whether follow/combat-assist actually look right now that the passive-gain nerf should buy more real observation time.

## Two-hundredth pass (2026-09-06): Dragón's controlled follow test refutes the "no time window" theory — a real, never-checked return value found, the unconfirmed composite pulled back, a real reset function tried for the interrupt

Dragón corrected the previous pass's "no real observation window" theory for the follow reports directly: for one Petallia, he deliberately gave the minimum interactions needed to cross 50% and then watched from a distance — she never followed. For a second, he ran far away on purpose — she despawned, meaning she made essentially zero progress keeping pace. Both are real, controlled negative results, not a timing artifact.

**Real, concrete finding: `Combat.IssueFollowMoveOrder` has NEVER checked the return value of `PalMoveToLocation`, in any pass since this project's very first attempt at following.** The header dump confirms it is not void — it returns `TEnumAsByte<EPathFollowingRequestResult::Type>` (the standard Unreal AIModule enum: 0=Failed, 1=AlreadyAtGoal, 2=RequestSuccessful). If this call has been silently returning `Failed` on every tick this whole time, that alone explains both of Dragón's reports without needing to find some deeper AI-state mystery. Fixed: the return value is now captured and logged every call (`[MOVE-ORDER-RESULT]`) — a plain byte read, no new risk, but the first time this project has ever actually looked at whether this call succeeds.

**The hundred-and-ninety-seventh pass's `SetRootComposite`/`UPalAIActionOtomoDefault` follow attempt is pulled back (commented out, not deleted) for the next test.** It was shipped as "purely additive" on the theory that it runs in parallel with the plain move-order calls without interfering — but `SetRootComposite`'s entire purpose is to REPLACE the AIController's root behavior, which is a real, plausible way it could be silently intercepting or overriding the direct `PalMoveToLocation` calls made on that same controller, rather than coexisting with them as designed. With two unconfirmed mechanisms running together and zero visible following in a controlled test, there's no way to tell which one (or both) is at fault. Disabling the newer one isolates the older, simpler mechanism — now finally instrumented — for a clean next test.

**Interrupt: Dragón asked directly — "can't you just reset their behavior so they stop fighting/running away?"** — leading to a real, concrete candidate already sitting on the same sensor class this project already reads safely: `UPalAISensorComponent::ResetResponsedMaxBiologicalGrade()`, alongside its own field `ResponsedMaxBiologicalGrade` (a plain int32). The name and shape strongly suggest a hysteresis/dedup value — "the strongest threat grade I've already reacted to" — meant to stop a Pal from re-reacting to something weaker than a decision it already committed to. That would explain exactly why the previous pass's swap+cancel+resense combo succeeded at the Lua level 5/5 times with zero visible behavior change: the preset changed, but this separate guard value never did, so the next real decision may have been silently discarded before ever consulting the new preset. Added right alongside the existing cancel+resense calls in `interrupt_and_resense`, matching Dragón's own framing ("reset their behavior") almost literally.

**Capture delay bumped 4000 -> 5000ms per Dragón's ask**, to keep tuning from the first real look at the fixed-delay approach (see the previous pass's writeup for why a fixed delay replaced the abandoned signal-detection attempts).

Verified with `luaparse` (Trust.lua, Personality.lua, Combat.lua — all clean), deployed to the real game install and the `32-PalBonds/mod/` mirror.

**Test plan for the next session:** (1) bond a Pal to 50% again without over-feeding it, watch from a distance, and check the log for `[MOVE-ORDER-RESULT]` — if it's reporting `0` (Failed) on every tick, that's the real, long-standing root cause found at last; (2) get a fleeing/attacking Pal past the 20% friendly trigger and watch closely for any real behavior change this time, checking for the new `ResetResponsedMaxBiologicalGrade` log line succeeding; (3) confirm the 5-second capture delay feels right, or report back how much further to tune it.

## Two-hundred-and-first pass (2026-09-06): balance changes, a real self-correction on Pet's grant, and a solid plan agreed before touching the follow/interrupt/combat-assist work

**Real self-correction, found while implementing Dragón's "bump Pet to 25" ask.** The previous session's claim that "Pet only grants 10" was wrong — traced to a genuine misread. `RegisterHook("...PalIndividualCharacterParameter:AddFriendShip"...)` (Interaction.lua's `[WATCH]` hook) is a single, GLOBAL, unconditional watch on the real native function — it logs literally every real grant in the whole game, for any Pal, for any reason, not just ones tied to this mod's wild-Pal interactions. The recurring `value=10 applyPassiveSkill=true` lines in recent sessions were almost certainly Dragón's own real Otomo party members (Garm etc.) passively gaining friendship in the background at vanilla's own real `FriendshipPoint_AutoIncrementOtomo` rate (confirmed = 10 via the balance-research `[BALANCE-DIAG]` pass) — completely unrelated to Pet. Pet's real, isolated grant for a wild-Pal interaction specifically has never actually been confirmed by a clean, correlated read.

**Fix, rather than another guess:** `do_interaction`'s Pet path (scoped to `actionLabel == "HumanPetting"` and a confirmed wild Pal only) now reads `FriendshipPoint` before the interaction (already had this) and again ~3 seconds after (`PET_GRANT_CHECK_DELAY_MS`), computes the real observed delta, and applies a signed adjustment (`AddFriendShip` with a positive OR negative value — negative grants are already a proven-safe pattern in this project, e.g. Trust.lua's damage/distance penalties) so the net total lands on exactly `PET_FRIENDSHIP_GAIN` (25) regardless of whatever the real vanilla amount turns out to be. This also finally gives a clean, isolated read of Pet's real number, closing a question this project never actually answered.

**Other balance changes, all per Dragón's direct ask:**
- `FEED_FRIENDSHIP_BASE`: 60 -> 50.
- `INTERACTION_FRIENDSHIP_GAIN` (Play's own grant): 10 -> 25.
- Play's key moved off CTRL+J (a two-press combo Dragón found "too annoying" for something used this often) to plain F8 — switched from `RegisterKeyBindAsync`+modifier to the same plain `RegisterKeyBind(Key[...])` pattern F9/F10 already use successfully. Confirmed with Dragón: F9/F10 (Pet/Feed) stay exactly as they are — he doesn't press them directly (uses the real radial menu, which calls the same `do_pet`/`do_feed` functions internally), so there was never a real conflict to resolve on that side.

Verified with `luaparse`, deployed to the real game install and the `32-PalBonds/mod/` mirror.

**The bigger question — why follow and interrupt both look "received but immediately overridden."** Dragón gave the single most useful piece of behavioral evidence this project has had on this topic: watching a FlowerRabbit up close, he saw her briefly look toward him (the move order landing) and then resume her own path a frame later, repeating every ~1.5s tick. This matches — precisely, visually confirmed for the first time — this project's own long-documented weakness: the move-order nudge is a periodic *suggestion* competing against her own continuously-re-deciding wild AI, not a replacement for it, and loses that competition almost every tick.

**Real clarification surfaced: the newer secondary-Otomo mechanism (`SetRootComposite`/`UPalAIActionOtomoDefault`) was NOT active during that observation** — it was deliberately disabled two passes ago to isolate the plain move-order mechanism for testing. Dragón had believed it was the thing being tested and was confused why it "still failed the same way." Real theory raised for why the composite mechanism likely has the SAME failure shape even though it's structurally different: it was only ever called ONCE, at the moment a Pal starts following — never repeated. If her own wild AI re-asserts its own root decision continuously (which the observed behavior strongly suggests), a one-time composite push would get silently reclaimed almost immediately, producing an outcome indistinguishable from what was just observed with the plain move order.

**Agreed plan for the next implementation pass (not yet written):**
1. Re-enable the `SetRootComposite`/`UPalAIActionOtomoDefault` follow mechanism, but call it REPEATEDLY (matching the same ~1.5s cadence as the old move-order tick) instead of once at follow-start.
2. Disable the old `PalMoveToLocation` move-order nudge for this next test, to cleanly isolate whether repeated composite pushes can actually out-compete the wild AI's continuous reassertion, per Dragón's own preference ("ideally we won't need [the old one] if we manage to work for something better").
3. For combat-assist (never implemented in either mechanism — only `SetOtomoFollowAction()` has ever been called, never `SetOtomoCombatAction()`): before writing a trigger blind, re-read the PalFollowerTweaks reference mod's actual `PalFunnelCharacter`/`BP_AIAction_FunnelFollow_C` logic specifically for how IT decides between modes (never checked for this specific question before, per Dragón's fair pushback — "these things have never been made, but the mods may still have hooks/functions we can reuse"), and grep `Pal.hpp` for whatever native code actually calls `SetOtomoCombatAction()`/`SetOtomoBerserker()` for a real Otomo, to find the real trigger condition instead of guessing one.
4. For interrupt: Dragón asked directly whether fixing follow might fix interrupt too. Answered: plausibly related (same "one-shot vs. continuously-reasserting AI" shape), worth applying the same "repeat, don't just fire once" principle to `interrupt_and_resense` as well — but flagged as NOT necessarily the same root cause, since a real, distinct possibility exists: the copied "friendly" preset's `Damaged_Player/Greater/Equal/Smaller` fields (as opposed to the `Discover_*` fields) have never been logged/verified — if a Pal is currently engaged (already took damage), her decision may be driven by that branch instead, and if THAT branch of the source "friendly" CDO preset isn't actually peaceful, no amount of repetition would fix it. Plan includes adding a one-time diagnostic to log the real 8 field values being copied, to either confirm or rule this out before assuming repetition alone is the fix.
5. Confirmed, untested claim to verify live once other pieces are in place: multiple wild Pals should already be able to follow in parallel today — nothing in `BondingState`/`State`/`tick_followers` restricts following to a single Pal at a time.

**Nothing in this plan has been implemented yet** — Dragón explicitly asked to prepare a solid plan and get his questions answered before writing any of this code, following only the balance changes above.

## Two-hundred-and-second pass (2026-09-06): the whole agreed plan implemented — repeated composite follow, a real native combat-assist decision, and the Damaged_* preset diagnostic. None confirmed live yet.

Dragón gave the go-ahead to implement all four remaining plan items in one pass and report back when it's ready to test.

**Step 1/2 — repeated `SetRootComposite`, old nudge disabled for this test.** `Combat.lua`'s one-shot `attempt_real_otomo_follow` (called only once, from `Combat.StartFollowing`) is retired. In its place: `get_or_build_otomo_composite(pal, key)` constructs the `UPalAIActionOtomoDefault` composite exactly ONCE per Pal and caches it (`OtomoCompositeCache`, keyed the same way as everything else in this project, `GetFullName()`) — rebuilt automatically if either the cached `AIActionComponent` or the composite itself ever goes invalid (Pal despawned/GC'd). `Combat.TickRealOtomoFollow(pal, key)` is the new function that actually does the repeating: called every `tick_followers` pass from `Trust.lua` (same ~1.5s cadence the old move-order nudge used), it re-issues `SetRootComposite(composite, priority=Logic)` on the SAME cached object every tick, rather than reconstructing a fresh object each time — repeating the push (what the plan asked for) without also repeating the construction (an unnecessary extra risk on top of the one already being tested). `USE_OLD_MOVE_ORDER_NUDGE = false` now gates `IssueFollowMoveOrder` itself (a one-line no-op check at the top) — same toggle-don't-delete convention as `Trust.lua`'s `EASY_TEST_MODE`, flip back to `true` to restore the old push if this doesn't pan out. `Combat.StopFollowing` now also clears the cached composite entry so a later re-follow builds fresh state, not a stale reference.

**Step 3 — combat-assist, found in Pal.hpp, not guessed.** Re-read the PalFollowerTweaks reference mod's actual `main.lua`/`config.lua` end to end (not just the file/class names already known) — confirmed it has NOTHING to do with real Otomo combat behavior at all: `BP_AIAction_FunnelFollow_C`/`PalFunnelCharacter` is a purely decorative mechanism (formation offsets and a visual scale for excess captured Pals trailing behind the player beyond the 5 active Otomo slots) with zero mode-switching logic to borrow. Grepping the real `Pal.hpp` at `Palworld/Pal/Binaries/Win64/ue4ss/CXXHeaderDump/Pal.hpp` for `SetOtomoCombatAction`/`SetOtomoBerserker` instead paid off directly: both are declared on `UPalAIActionOtomoDefault` itself (the exact class this project already constructs), right next to a THIRD, never-before-noticed function — `bool ShouldSetCombatAction()` — plus `FindNearestAttackTarget(const TArray<AActor*>&)`. `ShouldSetCombatAction()` is the composite's own native decision function for exactly this question. `Combat.TickRealOtomoFollow` now calls it every tick: if it returns true, `SetOtomoCombatAction()` runs instead of `SetOtomoFollowAction()` before the (repeated) `SetRootComposite` call. This means combat-assist mode-switching is driven by the game's own real logic, not a guessed trigger condition — exactly what the plan asked for before writing anything blind. Whether `ShouldSetCombatAction()` actually returns something meaningful on a wild Pal that was never set up as a real Otomo (trainer reference, work-assign state, etc. all normally established through the real capture/join flow) is completely unconfirmed — flagged honestly, first live use of this function anywhere.

**Step 4 — interrupt diagnostic, not a fix yet.** `Personality.lua`'s `apply_forced_preset` now calls a new `log_preset_slots_once(desiredBaseName, cdo)` right after resolving the source CDO, logging all 8 real `PRESET_SLOTS` values (`Discover_Player/Greater/Equal/Smaller`, `Damaged_Player/Greater/Equal/Smaller`) read directly off that preset's own Class Default Object. Throttled to once per `desiredBaseName` ever (not per-Pal, not per-apply) — the CDO is a shared, static, unchanging reference regardless of which Pal receives the copy, so one log line answers the question for good. This directly targets Dragón's flagged concern: whether the "friendly" preset's `Damaged_*` fields are genuinely peaceful, or whether a Pal already mid-combat keeps its old behavior because ITS decision is driven by that branch instead of `Discover_*`. No code changed based on the answer yet — this pass only makes the real values visible in the log for the first time; interrupt itself (`interrupt_and_resense`) is UNCHANGED, still a one-shot call, not yet repeated (the plan flagged this as a distinct, unconfirmed root cause from the follow bug, worth checking before assuming repetition is even the right fix here too).

**Step 5 — multiple Pals following in parallel: still just a code-read claim, not exercised live this pass** (no code needed — `BondingState`/`State`/`tick_followers` already iterate every following Pal independently). Worth confirming in the same test session as everything else, opportunistically, not as a dedicated test.

Verified with `luaparse` (all three files, clean), deployed to the real game install and the `32-PalBonds/mod/` mirror. **Nothing above is confirmed live yet** — this is the implementation the agreed plan called for, ready for Dragón's next test session.

**Plan for that test session:**
1. Bond with a wild Pal to 50%, watch closely for real, sustained following (not just an occasional glance) — check `[REAL-FOLLOW]` lines for `SetRootComposite ok` (logged once per Pal, further ticks silent unless something fails) and, separately, whether `ShouldSetCombatAction()=true` ever fires if a hostile Pal attacks nearby during the follow.
2. Check whether `SetOtomoCombatAction()`/`ShouldSetCombatAction()` calls report `ok` or fail outright — a clean failure here would mean this class's combat logic just isn't usable on a wild (never-really-Otomo) Pal, closing this specific avenue without more guessing.
3. Look for the new `[PRESET-SLOTS]` line in the log (fires once, the first time any preset gets applied) and read whether `Damaged_Player/Greater/Equal/Smaller` on the friendly preset actually look peaceful — this alone may explain why "friendly" doesn't stop an already-fighting Pal.
4. If following still doesn't look right with the old nudge fully disabled, that's real evidence the composite mechanism itself doesn't work on wild Pals at all (not a competing-mechanism problem) — worth deciding then whether to re-enable `USE_OLD_MOVE_ORDER_NUDGE` as the accepted approximation going forward.

## Two-hundred-and-third pass (2026-09-06): live test confirms the composite mechanism does NOT work on wild Pals — reverted to the old approximation, plus a real bug caught while doing it

Dragón ran the test session the previous pass asked for and pasted the full log. Read line by line rather than trusting the summary.

**Result: a clean, repeated negative, not ambiguous.** All 3 Pals that crossed the 50% follow trigger this session got a fully successful composite push — `StaticConstructObject(UPalAIActionOtomoDefault) ok` then `SetRootComposite ok`, logged at the exact moment each one started following, with zero `FAILED` lines anywhere in the log for any of them. Despite that, every one of them wandered off on its own path and broke the 3000-unit leash (`is NNNN units away — losing all trust`) 10-20 seconds later, with no visible movement toward the player in between. This is the OLD nudge fully disabled for the entire session (`USE_OLD_MOVE_ORDER_NUDGE = false`), so there was nothing else that could have been fighting the composite for control — this isolates the result cleanly: the composite mechanism itself does not produce real following behavior on a wild Pal, it just silently succeeds at the Lua call level while doing nothing observable. Since nothing ever followed, combat-assist (`ShouldSetCombatAction`) never got a chance to be exercised either — Dragón correctly flagged this rather than reporting a false negative on that part.

**Real bug caught while implementing the revert, unrelated to the test result itself:** `Combat.Init()`'s startup log line referenced `USE_OLD_MOVE_ORDER_NUDGE` textually BEFORE that local's declaration further down the file (the declaration had been placed right above `IssueFollowMoveOrder`, several dozen lines later). Lua locals don't hoist — this is the exact same failure shape as hook-points.md's own hundred-and-fortieth-pass `hook_describe` bug, now repeated in this same file: the early reference silently resolved to a nil global instead of the real local, so `Combat.Init`'s own log always printed "disabled for this test" regardless of the toggle's actual value. Purely cosmetic — `IssueFollowMoveOrder` itself (declared after the local) always read the correct value, so no behavior was ever affected — but a real instance of a lesson this project has already been burned by once. Fixed by moving both toggle declarations up near the top of the file, before every reference.

**Reverted, given the confirmed result:** `USE_OLD_MOVE_ORDER_NUDGE` flipped back to `true` (restoring the previously-known, weaker-but-nonzero move-order approximation). The composite mechanism is now gated behind a NEW toggle, `USE_REPEATED_OTOMO_COMPOSITE = false`, rather than left running in parallel — the Two-hundredth pass's own unruled-out theory (that `SetRootComposite` might silently swallow direct `PalMoveToLocation` calls on the same controller) means testing both live at once would leave any future result ambiguous. Toggle, not a deletion, same convention as everywhere else in this project — flip back to `true` if a future lead (e.g. wiring the Pal into real Otomo/trainer bookkeeping first) makes the composite worth retrying.

Verified with `luaparse`, deployed to the real game install and the `32-PalBonds/mod/` mirror.

**Separately confirmed this same session, no code changes needed:**
- **The Kinship Peach capture delay (5s fixed) reads fine in practice** — Dragón confirmed it live. This closes out that specific open question from the Hundred-and-ninety-ninth/Two-hundredth passes.
- **Perceived general lag this session, diagnosed but not yet acted on:** `[OTOMO-GETTER-WATCH]` (Interaction.lua, dating to the eighty-fourth pass) fires "only on change" but the underlying `TryGetSpawnedOtomo()` value appears to change almost continuously throughout the entire pasted log — dozens of distinct addresses within single-second windows, far more often than any real Otomo-switching event could explain. Since `Logger.lua` flushes every line to disk immediately (by design, to survive a hard crash), a hook this chatty firing constantly is a real, plausible lag source — but it predates this session's changes entirely (last touched in the eighty-fourth pass) and wasn't investigated further this pass. Worth a dedicated look next time general lag is reported: either the value is genuinely this unstable (worth knowing why) or the "only on change" comparison itself is broken (e.g. comparing wrapper identity instead of the underlying object).
- **A pending-list correction, unrelated to today's code:** the "Fase 1" pending list's item 3 ("VFX del haz de luz al unirse — ya hay un candidato real encontrado: `ABP_ReturnPalEffect_C`") is stale — that exact candidate was already ruled out in Continuación 163/hook-points.md's "Hundred-and-sixty-third pass" (`[PRISM-SPY]` correlated with switching active Otomo, never with capture, in a dedicated test run). The VFX item itself is still open and still worth doing — it just needs a fresh candidate, not a repeat of that ruled-out one.

## Two-hundred-and-fourth pass (2026-09-06): follow research redirected to Funnel/Otomo (Daedream/Dazzi/Floppie), a real post-capture diagnostic bug fixed, the OTOMO-GETTER-WATCH lag culprit fixed, VFX beam clarified

Four separate asks from Dragón this pass, after the previous pass's negative follow result and lag report.

**1. Follow mechanism — both current attempts explicitly left OFF, not reverted to the old nudge.** Dragón's own call: don't fall back to the weakest known option just because it already exists — go looking for something the game itself already uses to make a Pal trail the player without full Otomo bookkeeping. `Combat.lua`: `USE_OLD_MOVE_ORDER_NUDGE = false`, `USE_REPEATED_OTOMO_COMPOSITE = false` — both toggles kept in the file (not deleted), header comment updated to name the new lead.

**2. Daedream/Dazzi/Floppie follow research — ALREADY DONE, hundred-and-thirty-seventh pass (2026-09-03), re-surfaced and reasoned through fully this pass rather than repeated from scratch.** That pass read the PalFollowerTweaks reference mod's real source (not just its file names, which the Two-hundred-and-second pass had already dismissed for the *combat* question specifically) and confirmed:

- **The real mechanism is `PalFunnelCharacter` (native class) + `BP_AIAction_FunnelFollow_C` (the driving Blueprint action).** This is genuinely the Daedream/Dazzi/Floppie-style "walks near the player, doesn't fight or work" secondary-follower behavior — confirmed real, not a guess.
- **Code difference vs. a real active Otomo, now confirmed precisely from `Pal.hpp` this pass (not previously nailed down to class internals):** `UPalAIActionFunnelCharacterDefault : UPalAIActionCompositeBase` exposes exactly two things — `bool ShouldSetSkillAction()` and `void SetSkillAction()`, plus a plain `SetOtomoFollowAction()` inherited/shared with the full Otomo class. That's it — **no `SetOtomoCombatAction()`, no `SetOtomoWorkAction()`, no `SetOtomoBerserker()`, no `SetOtomoBaseCampAction()`** anywhere on the Funnel class. `UPalAIActionOtomoDefault` (the full active-slot class this project already tried) has all of those. So the real difference isn't a different *follow* mechanism at all — both classes share the same `SetOtomoFollowAction()` call this project already tried and confirmed doesn't work on a wild Pal — the Funnel class is simply the Otomo class with the combat/work/berserk modes stripped out. **This means the Funnel system is not a "better" following mechanism to attach instead — it uses the identical follow call already proven not to work.**
- **The real, structural wall (unchanged from pass 137, now directly relevant again):** `character:GetTrainer()` is the confirmed real ownership getter for a Funnel character — becoming one almost certainly requires already being a genuine party member (a real `Trainer` reference set), the exact same gate that blocks the Otomo composite. There is still no known way to attach either system — Funnel or full Otomo — to a Pal that was never actually captured. **Bottom line for the "find something better to attach to a still-wild Pal" ask: neither Funnel nor Otomo is that thing — both are downstream of real ownership, which a bonding-but-uncaptured wild Pal structurally doesn't have.**

**3. The actually-promising lead from that same old pass, revisited: does OUR real capture already make the Pal follow for free, once it's genuinely owned?** `Capture.lua`'s `diagnose_post_capture_slot` was added specifically to answer this back in pass 137, but has failed EVERY time it's ever run, including all 3 real captures in the just-finished test session — always "could not resolve a live handle for the just-captured Pal — skipping check." Found the real bug: it resolved `GetIndividualCharacterHandleByActor(pal)` from `pal` (the actor) AFTER `Capture.TryDirectCapture` already ran — but `Capture.TryDirectCapture`'s own `[EXPERIMENT]` log (from the very same test session) shows the Pal's owner-field struct going from a real value to `nil` right across the `PalCaptureSuccess` call, i.e. the actor is actively being torn down/reassigned into a party data record at that exact moment — never a normal live actor by the time the diagnostic ran. **Fix:** `diagnose_post_capture_slot` now takes an already-resolved `handle` parameter instead of deriving one internally; `Capture.OnTrustMaxed` resolves that handle BEFORE calling `TryDirectCapture`, while `pal` is still an ordinary, fully-live wild actor (the exact same moment `Personality.GetStableId` already reads a stable ID off wild Pals successfully throughout this project) — zero new native-call risk, same function, just called at a point already proven safe elsewhere. **Unconfirmed until the next real capture** — but if this finally reports which slot the Pal landed in, it could close the biggest open question in Follower Pal AI for free (if it's an active slot, real Otomo following/fighting already works with no more code needed at all) or name the exact one remaining safe call needed (`InactivateCurrentOtomo`+`ActivateOtomo`, already confirmed real since Continuación 7, if it landed on the bench instead).

**4. VFX beam preview — recommended NOT writing new code for this.** `ABP_ReturnPalEffect_C` is confirmed (Continuación 163) to fire on `InactivateCurrentOtomo` — i.e. switching your ACTIVE Otomo — not on capture or cage-release. The real capture/cage-release beam Dragón originally saw is still unidentified (that candidate was a red herring). Manually spawning/triggering a Blueprint actor from scratch is a new, bigger risk category than anything else in this file (no known content path for this class, unlike the AIResponsePreset CDO trick) — and isn't needed anyway: the exact same VFX already fires for free, today, with zero mod code, any time Dragón switches his active Otomo through the game's own normal UI. Recommended he just do that once right after a capture to preview it, rather than spend a new native-call risk on a "just curious" ask that a completely safe existing action already answers identically.

**Separately, the lag culprit fixed:** `[OTOMO-GETTER-WATCH]`'s "only log on change" throttle (Interaction.lua, eighty-fourth pass) never actually held — `hook_describe` falls back to `tostring(obj)` (a raw Lua wrapper table address) whenever `GetFullName()` fails, which happens constantly for the common "no valid Otomo resolved" state (this getter fires ~4x/second ambiently, confirmed since the eighty-fourth pass) — and UE4SS hands back a fresh wrapper table per call, so that fallback address differs almost every time even when the real answer never changed, defeating the dedupe and forcing a `Logger.lua` disk flush on nearly every call. Fixed by comparing a normalized key (anything matching the `tostring(obj)` fallback shape collapses to one shared sentinel for comparison purposes only) instead of the raw string — the actual logged text is unchanged, so a genuinely different, named Otomo still logs its real name.

Verified with `luaparse` (Combat.lua, Interaction.lua, Capture.lua — all clean), deployed to the real game install and the `32-PalBonds/mod/` mirror.

**Test plan for next session:** (1) capture any wild Pal for real and check for a `[POST-CAPTURE-SLOT]` line that actually reports slot data this time, instead of "could not resolve"; (2) general play session to confirm `[OTOMO-GETTER-WATCH]` logs meaningfully less now and lag feels reduced; (3) whenever convenient, switch active Otomo right after a capture to see the `ABP_ReturnPalEffect_C` beam for real, no code needed.

## Two-hundred-and-fifth pass (2026-09-06): three real corrections to the record from the previous pass, a genuine capture-completion fix shipped, lag and the real open follow question both still unresolved — session paused here, handed to a different assistant/session at Dragón's request

Dragón tested the previous pass's changes and corrected three separate misunderstandings in this same reply, directly and clearly. This entry exists specifically so the next session (a different AI, per his explicit request) starts from an accurate record, not a repeat of these same mistakes.

**Correction 1 — "does a real-owned Pal follow like a normal Otomo" was never an open question, and framing `diagnose_post_capture_slot`'s fix as answering one was wrong.** Dragón's own words: "there was never a doubt after the pal had already been captured, of course it acts like a real otomo because by that point is already a real otomo or owned pal... this had been one of the first things confirmed way earlier into the project." The previous pass's writeup (both here and in CLAUDE.md) incorrectly treated this as a live open question this fix might answer — it isn't, and never was. **The bug fix itself was still real and worth keeping** (the diagnostic's handle-resolution timing was genuinely broken, now genuinely fixed — see the Two-hundred-and-fourth pass entry above for the technical detail, unchanged) — but it does NOT move the actual open question forward at all. **The real, still-completely-unsolved question remains exactly what it was before the Two-hundred-and-second/-third/-fourth passes: how does a Pal follow the player DURING the bonding phase, while it is still wild and NOT YET owned.** Both attempted mechanisms for that (the plain move-order nudge, the repeated Otomo composite) are confirmed not to work, and Funnel/Otomo both require real ownership per the Hundred-and-thirty-seventh pass's research — reconfirmed, not newly found, by this same chain of passes. **Nothing new was actually unlocked toward pre-capture wild-Pal following by any of the last three passes' work.** Whoever picks this up next should treat "real Otomo follow-behavior confirmed" as long-settled background fact, not a thread to re-pull, and focus entirely on the pre-capture case.

**Correction 2 — the VFX ask was misunderstood, and the fix shipped (Happy+hearts before capture) is a real improvement but does NOT close the ask.** What Dragón is describing, precisely, from watching a normal vanilla cage-rescue: (1) the Pal plays a happy reaction — **this part is now handled**, confirmed good by Dragón ("the happy animation is good"); (2) **a VFX plays of the Pal turning into light and traveling into the player** — this is the part that's still completely missing, and it's the actual jarring part: right now the Pal smiles, then instantly vanishes with nothing in between; (3) an on-screen text confirms the Pal joined — **already handled** (`Capture.NotifyJoined`'s toast, pre-existing).

**The missing piece (2) needs a FRESH investigation, not a reuse of a previously-ruled-out candidate.** `ABP_ReturnPalEffect_C` — this project's one strong lead for exactly this kind of "Pal travels toward the player" transform effect (real fields: `Effect`/`CacheDisappearEffect`/`CacheDisappearBurstEffect` as `UNiagaraSystem`s, `StartLocation`→`ForPlayer` with `LerpStartPos`/`Progress`/`CurveForLerp`) — was already tested in a dedicated real session (Continuación 163/hook-points.md's "Hundred-and-sixty-third pass": one real sphere capture, one real sphere-less capture, one real cage rescue, all in the same session) and **confirmed to correlate ONLY with `InactivateCurrentOtomo` (switching active Otomo), never with any of the three capture/rescue events.** So this specific class is a confirmed dead end for the actual "becomes light, travels into player" moment Dragón is describing, despite structurally looking exactly like what's wanted — the previous pass's suggestion to "just switch Otomo to preview it" was answering the wrong question (that shows what `ABP_ReturnPalEffect_C` looks like, not what a real cage-rescue looks like). **Next step for whoever continues:** find the REAL Blueprint/actor class behind the vanilla cage-rescue/capture light-travel effect — this needs the same real-evidence approach already proven in this project (repak/strings search against the actual game pak for VFX-adjacent names near the cage-unlock/capture-success code path, or a fresh FModel Blueprint-graph read of whatever `UBP_ActionUnlockCagePalLock_C` or the native capture-success path calls) — not another guess, and not reusing `ABP_ReturnPalEffect_C` again.

**Correction 3 — lag is still there, feels worse than the day before, and the `OTOMO-GETTER-WATCH` throttle fix from the Two-hundred-and-fourth pass did NOT resolve it.** Dragón's own words: "lag still feels a lot laggier than yesterday, idk what happened but im sure it was something last added." **This is a genuinely open, unresolved problem** — do not treat the `OTOMO-GETTER-WATCH` fix as having closed it; it was a real, legitimate fix for a real bug (the throttle genuinely wasn't working), but it evidently was not the actual cause of what Dragón is feeling, or wasn't the only cause. Also found and cleaned up this same pass, unrelated to Dragón's report but worth recording: a genuinely hung background shell process (`find.exe`, launched by mistake early in a previous session, searching the entire filesystem for a file that was found another way minutes later) had been running silently for over an hour — killed via PowerShell `Stop-Process` (Windows `taskkill` reported success but the process was still listed afterward; `Get-Process`/`Stop-Process` confirmed it was actually gone). This was NOT the cause of the in-game lag Dragón is describing (it's an unrelated host-machine process, not part of the mod), but is exactly the kind of stray background task worth checking for whenever "something feels off" is reported. **The real in-game lag source is still unfound** — needs fresh profiling next session (which specific action/hook correlates with the lag actually being felt, not an assumption from log volume alone).

**What's actually shipped and worth keeping from the last three passes, despite the above corrections:**
- `Combat.lua`: `USE_OLD_MOVE_ORDER_NUDGE = false`, `USE_REPEATED_OTOMO_COMPOSITE = false` — both real follow attempts confirmed not to work, correctly left off, not reverted to the weaker option.
- `Capture.lua`: `diagnose_post_capture_slot`'s handle-resolution bug is genuinely fixed (real bug, real fix) — just doesn't answer an open question, since there wasn't one there.
- `Capture.lua`: the Happy+hearts join-celebration (`play_join_celebration_then`, ~2s delay) is a real, confirmed-good partial improvement to keep — it just isn't the full fix Dragón asked for (missing piece 2 above).
- `Interaction.lua`: the `OTOMO-GETTER-WATCH` throttle bug fix is a real, legitimate fix — just not confirmed to be THE lag cause Dragón is reporting.

**Session paused here at Dragón's explicit request** — he is moving to a different AI assistant/session from this point, specifically citing repeated misunderstandings in this session as the reason. Whoever picks this up should read this correction section FIRST, before anything else in this file, to avoid re-deriving or re-misunderstanding any of the three points above.

## Two-hundred-and-sixth pass (2026-09-06): a new session's audit — one self-correction, and six real, previously-unidentified lag sources found by reading the live log and removed

Session picked up by a different assistant per the Two-hundred-and-fifth pass's handoff. Read that correction section first, then the full CLAUDE.md, DESIGN.md §12 and the deployed code before changing anything.

**Self-correction first.** The initial audit reported kinship peaches as "fully blocked on real food-item feeding" — read straight out of `DESIGN.md` §12 item 8, a planning document dated three days earlier. That was wrong: peaches are implemented, balanced and live-tested (`Interaction.lua`'s `RequestUseToCharacter` post-hook grants 250 for `AffectionFruit_02` / 500 for `AffectionFruit_01` against the 500-point bar). Dragón caught it and named the real cost precisely — a wrong status line is evidence the whole picture of recent work is stale, not just that one line. `DESIGN.md` §12 now carries a STALENESS WARNING header with four specific corrections (items 3, 4, 5 and 8), since it is demonstrably capable of misleading a fresh session.

**Lag: first evidence-based pass, six real sources removed.** Prior passes reasoned about lag from log volume or from what had been added most recently. This pass analysed the actual live log by tag frequency (2012 lines across a 10-minute session) and then read each implicated code path. The single most important finding is a cost shape this project had not recognised before:

> **A throttle that guards only the log CALL does not reduce cost at all, because Lua evaluates the arguments first.**

That shape appeared twice, in the two heaviest offenders:

1. **`Indicator.lua`, `PalUICharacterHPGaugeBase:SetHPPercent`** — a read-only diagnostic from the fifty-first pass's closed gauge-structure research, never removed. The game calls this continuously for every visible Pal HP gauge. Each call ran `describe_widget(widget)` — a real `GetFullName()` reflection round-trip — plus a `string.format`, and only then handed the finished string to `diagnostic_log`, which discarded it after the first 20. So the log showed 20 lines total while the reflection work ran on every call, all session, scaling directly with on-screen Pal count. That matches the "worse entering a new area" shape exactly. Removed, along with its sibling `SetTargetCharacter` hook (same shape, two describes per call).
2. **`Indicator.lua`, `poll_prism_state()`** — two whole-world `FindAllOf` scans (`BP_CapturePrism_C`, `BP_CapturePrismBullet_C`) plus a reflection per instance, every 2 seconds forever. `seenPrismInstances` and `prism_log`'s cap only ever suppressed lines; the scans themselves always ran. `BP_CapturePrism_C` is the player's own held Palsphere, so it reliably finds instances. Its research thread was closed by the Hundred-and-ninety-third pass. Removed from the tick.

The other four:

3. **`OtomoWatch.Init()` disabled entirely** (`main.lua`). Nothing in the mod calls into this module — it exports `Init()` and nothing else — and every question it was built for is closed. It installed **eleven** hooks, two on genuinely hot functions: `PalAISensorComponent:SelectResponseBySenses` (every Pal's AI sense decision — and a **duplicate** of the hook `Personality.lua` needs there for real enforcement, so the game was crossing into Lua twice per sense) and `PalBattleManager:TargetIsPlayerOrPlayersOtomoPal` (every combat targeting evaluation), both logging unconditionally with reflection describes. Plus a 10s `FindAllOf` class-existence poll whose own comment admits "no further use planned for it right now."
4. **`Personality.lua`, `interrupt_and_resense` removed from the routine enforcement path.** It fired on **43 distinct Pals in 10 minutes**, because it was attached to spawn-time tier enforcement rather than only to the two paths that need it (`MaybeBecomeFriendlyByBar`, `ForceTier`). A freshly-seen Pal has no stale behaviour to interrupt, yet each one was getting `AllCancelAction_Logic_HardScript_Reaction` + `ResetResponsedMaxBiologicalGrade` + `RequestSightCheckAsync` (an async sight trace). Both calls were added on 2026-09-06 (Hundred-and-ninety-seventh and Two-hundredth passes) — matching Dragón's "I'm sure it was something last added." The preset swap itself is untouched.
5. **`Interaction.lua`, the global `[WATCH]` hook on `AddFriendShip` removed.** Its own comment argued a real grant is rare — true of player grants, but it ignored the game's ambient passive friendship, which ticks continuously for every owned Otomo, active Otomo and base worker. It was also the exact hook that produced the wrong "Pet only grants 10" conclusion corrected in the Two-hundred-and-first pass; a global watch cannot tell whose grant it is. The targeted before/after measurement in `do_interaction` already replaced it properly.
6. **`Interaction.lua`, `TryGetSpawnedOtomo`'s idle path made free.** This hook is load-bearing and stays — the substitution inside it is what lets the real vanilla Pet action land on a wild Pal (Hundred-and-fifty-ninth pass). But the getter fires ~4x/second ambiently and the watch ran `hook_get` + `hook_describe` on every one of those calls before any throttle. The Two-hundred-and-fourth pass fixed the repeated lines but left the per-call reflection, which was always the larger cost — which is why Dragón reported the lag surviving that fix. The idle path is now a single boolean test and an immediate return.

**Two smaller ones, same pass:** `Trust.lua`'s `[TICK]` line logged unconditionally every 1.5s (396 lines in 10 minutes) through a logger that flushes to disk per line — now logged once. And `try_enforce_personality` now checks the reactive hook's sensor cache before falling back to `find_sensor_component`, whose index rebuild does a whole-world `FindAllOf("PalAISensorComponent")` plus two reflection calls per component every 5 seconds; the reactive hook already caches a valid sensor for nearly every nearby Pal for free.

All eleven files verified with `luaparse`, deployed to the real install and the `32-PalBonds/mod/` mirror (md5-verified identical).

**Not confirmed live.** These are confirmed real costs by code and log reading, which is not the same as confirmed fixes. The test that matters: play normally, especially entering busy areas, and report whether the lag improved. Also confirm nothing regressed, since live paths were touched — Pet/Feed/Play still working, the trust bar and personality label still appearing, and wild Pals still showing varied tier behaviour.

## Two-hundred-and-seventh pass (2026-09-06): the irregular-friendship root cause found and fixed, F9/F10 removed at Dragón's request, and a genuinely new approach to following/combat-assist

**Root cause of the irregular friendship gains — found, and it is not a tuning problem.**

For a radial-menu Pet on a substituted wild Pal, `closeRadialMenuActionWindow` called `do_pet()`, which routes into `do_interaction()`. That function's FIRST gate is "is the player already mid-action? if so, ignore this press" — an anti-spam guard written for a raw keypress. On the radial path that guard is actively wrong: the entire point of the substitution is that the game's OWN Cuidar action is starting on the player at that exact moment, so the player legitimately IS mid-action, the gate fires, and `do_interaction` returns before reaching either the friendship grant or the `Interaction.OnWildPalPetted(pal)` call at its end.

That call gates everything downstream in Trust.lua: the 20% friendly trigger, the 50% follow trigger, the capture-threshold check, and (via `Trust.HasBondingState`) whether the Pal gets a trust bar at all. So a radial Pet registered fully or not at all depending purely on whether our call won a race against vanilla's animation starting. This also explains the secondary symptoms Dragón reported over several runs: bars appearing late, and several thresholds firing at once the moment an unrelated Feed finally got through. The hundred-and-fifty-ninth pass had already observed the symptom ("6 of 8 real presses were discarded by our own 'player is already mid-action'") but read it as evidence that vanilla was granting independently, rather than as the bug it is.

**Fix:** `grant_wild_interaction(pal, amount, label)` — the bookkeeping half of `do_interaction`, extracted with no busy-gates and no `PlayActionByType`: ownership-guard, read before, `AddFriendShip`, log `[BALANCE-TEST]` with before/after/intended, call `OnWildPalPetted`. The radial path now calls this instead of `do_pet()` (vanilla is already playing the animation — a second one was never wanted). Needed a new `lastRedirectedWildPalActor`, captured on every qualifying redirect and deliberately OUTSIDE the name-change dedup that throttles the log line, so a second "4" press at the same Pal doesn't leave a stale reference.

**Second real bug: Play has always granted zero.** `do_play` relied on the Happy action granting friendship as a side effect — an assumption the hundred-and-fifty-ninth pass DISPROVED with a controlled 9-datapoint test. The explicit `AddFriendShip` existed only in a fallback branch that runs if *scheduling* fails, i.e. essentially never, so Dragón's 10→25 rebalance in the two-hundred-and-first pass was applied to a constant that never executed. Play now grants explicitly through `grant_wild_interaction`.

**F9/F10 removed entirely**, at Dragón's explicit request: "i havent used f9 in a while... all this time i've been using the radial menu, so no, no f9 have been triggered on purpose." The design rule this sets, which should NOT be re-litigated: **Pet and Feed are radial-menu interactions, not hotkeys** — pressing "4" is what the game does and what the player finds intuitive. Play keeps F8 only because it has no radial equivalent yet, and per Dragón it should move into the radial menu once possible. This also removes a standing source of confusion in this project's own diagnosis: several passes reasoned about "F9's grant" as if it were what Dragón was seeing, when he was never pressing it.

**Balance verification mode (Dragón's own test design), currently ON.** `BALANCE_VERIFICATION_MODE` in Interaction.lua sets Pet/Feed/Play all to 100; `LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST` in Trust.lua forces the level multiplier to 1.0 so every Pal's threshold is exactly 500. 5 interactions of any single type should therefore capture any Pal, and a count that isn't 5 identifies which type is wrong. Kinship Peaches are deliberately NOT overridden (already confirmed correct, and leaving them real keeps the one-shot behaviour testable).

**Passive gain forced to 0 during the run, and this is not cosmetic — it would corrupt the test.** At 100 per interaction against a 500 threshold, interaction 3 crosses 50% (300 >= 250) and the Pal starts following, at which point passive gain adds 2 every 1.5s on its own; by interaction 5 the total would already be past 500 from drip alone, so a capture at 5 would prove nothing and a capture at 4 would look like a grant bug that isn't one.

**Following — a genuinely different approach, not another retry.** Every previous mechanism tried to ADD a following behaviour (move order, Otomo composite, Funnel) and lost to the Pal's own AI re-deciding over it; Dragón's FlowerRabbit observation (turns toward him, resumes its own path one frame later, once per tick) is the clearest evidence. The new approach inverts that: **silence the AI instead of out-shouting it.** The AI's entire decision vocabulary is `EPalAIResponseType: Ignore=0, Escape=1, Battle=2, Special=3` — there is no "approach/follow" value, which is a decisive finding in itself and explains why the preset layer alone can never produce following. But setting every player-facing response slot to `Ignore` means the Pal's AI generates no decision about the player at all, leaving nothing to override the move order. `Personality.ApplyCompanionPreset` does exactly that, reusing the private-preset write already proven to work (Warlike Pals really do attack, escape Pals really do flee). Paired with two changes in Combat.lua: the move-order nudge is back ON, and each order is now preceded by `AllCancelAction_Logic_HardScript_Reaction` — the same interrupt confirmed 5/5 on wild Pals, never before paired with movement — called on the controller's AI action component with the actor as argument (the exact shape from `interrupt_and_resense`, not guessed).

**Combat assist**, per Dragón's go-ahead, ships as part of the same companion preset: the three non-player `Discover_*` slots become `Battle` while the player slots stay `Ignore`, so a bonded companion engages other Pals while never turning on the player. Stated limitation: it engages what it notices, not specifically what the player is fighting. Targeting the player's own enemy would need the Hate system (`HateSystem:ChangeHate`, `APalAIController.TargetPlayers`) — real, but only ever dismissed as "not the personality field," which is a different question and does not rule it out here.

The repeated Otomo composite stays OFF — tested cleanly alone in the two-hundred-and-third pass (3/3 Pals broke the leash without approaching once) and dependent on ownership. Nothing learned since changes that.

All 11 files verified with `luaparse`, deployed and md5-verified against the real install. None of this is confirmed live.

## Two-hundred-and-eighth pass (2026-09-06): balance numbers verified from Dragón's live run (+ vanilla's real wild-Pet grant finally measured), the largest frame hitch in the project fixed, and the combat-assist behaviour corrected from three field reports

**Balance verification: PASSED, with one real discovery.** Every single `[BALANCE-TEST]` line in Dragón's run shows a delta of exactly +100 — 25 grants across Pet (radial) and Feed, no exceptions. Feed via the real `RequestUseToCharacter` path granted exactly 100 six times. Following triggered at interaction 3 and capture at interaction 5, exactly as designed.

**But the "before" values exposed something never measured before: vanilla's own petting grant on a WILD Pal is +10.** Trace it in the log — after a Pet lands on 100, the next interaction starts from 110; 210 -> 220; 320 -> 330; 430 -> 440. The drift is always exactly 10, always trails a **Pet**, and never trails a Feed (a Feed after a Pet-at-210 lands on 320 = 210 + 10 + 100). Our own grant is synchronous at menu close; vanilla's arrives a moment later when its Cuidar animation completes.

This is the clean isolated read the two-hundred-and-first pass tried and failed to get, and it corrects a standing assumption: the value is **10, not the 30** that `UPalGameSetting.Petting` reports (that config number evidently does not apply to a substituted wild Pal). **Consequence for the real balance pass: a radial Pet is worth OUR grant + 10.** To land on Dragón's intended 25, `PET_FRIENDSHIP_GAIN` should be 15, not 25 — otherwise Pet is 35 while Feed is exactly its configured number. Recorded here rather than changed now, since verification mode is still on.

**Largest frame hitch in the project, found and fixed.** The `[RADIAL-REDIRECT-PERF]` diagnostic added last pass did its job: `find_targeted_pal` costs **48-74ms per scan**, and it recomputes on a 0.25s throttle for as long as the radial menu is open — roughly 200-300ms of frame-blocking Lua per second of menu time. Root cause inside it: the loop called `GetFullName()` (a string-building reflection round-trip) on EVERY Pal in the loaded world, purely to test whether it was the one actor to exclude. Fixed by doing the cheap geometry first and resolving the exclusion only for the single winning candidate — GetFullName drops from once-per-Pal-per-scan to at most once per scan. The PERF line now only reports scans >= 15ms, so it can confirm the fix without re-adding its own cost.

**Answering Dragón's question directly ("the new things, or the 3 followers?"): both, and separably.** `[MOVE-ORDER-RESULT]` logged 2-3 lines every 1.5s *per follower*, each forced to disk — so that one scaled exactly with follower count. `find_targeted_pal` is independent of followers but fires on every "4" press, which a bonding session does constantly. Also trimmed this pass: `[RADIAL-WATCH]`'s per-hook trace (~8 lines per "4" press, four reflection calls each, building ~250-character strings — more than half of Dragón's pasted log; now behind `VERBOSE_MENU_HOOK_TRACE`, default off) and `[RADIAL-REDIRECT-FIELD]` (8-10 lines per press, now once per menu window).

**`[MOVE-ORDER-RESULT]`'s own question is answered, and the answer is the good news of this run:** across the entire session it returned only 2 (RequestSuccessful) and 1 (AlreadyAtGoal) — **never 0 (Failed)**. "AlreadyAtGoal" dominating means the followers were genuinely reaching and staying with the player. The companion-preset approach worked; the long-standing follow problem is, for the first time, actually behaving. Now logged only on change or failure.

**Combat assist: three field reports, one root cause.** Dragón observed (1) a bonded Petallia attacking his bonded Flopie with no provocation, (2) companions starting fights with random Pals while following, then taking damage and flipping to escape, and (3) three companions that "followed but never attacked, even when they received damage" from a hostile Caprity. Reports 1-2 and report 3 look contradictory but follow from one mistake: **`Discover_*` governs "I noticed something", `Damaged_*` governs "something hurt me", and only the Discover slots were set to Battle.** So companions picked fights with anything they spotted — including each other, since another bonding companion is just another wild Pal to them — while standing there taking hits without retaliating. The escape flips in report 2 were the knock-on: damage runs Trust's follower penalty, which can zero out trust and force the escape tier.

Corrected, and it is the better design anyway: `Discover_*` = Ignore (never start a fight — fixes the friendly fire and the death spiral) and `Damaged_*` = Battle (fight back when actually attacked — fixes the passivity). Also set `state.enforcementApplied = true` when the companion preset is applied, so the periodic 8s personality scan cannot later overwrite it with the Pal's originally-rolled tier — which would have looked exactly like a companion randomly turning hostile mid-bond.

Remaining honest limitation: a companion defends ITSELF, not the player. It joins a fight the player started only once the enemy also turns on it. Attacking the player's own target on sight still needs the Hate system, unexplored for this purpose.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-ninth pass (2026-09-06): Dragón's idle-animation fix for the wander-off, real Hate-based combat assist, a named join toast, and a genuinely new VFX lead

**The wander-off cause was diagnosed by Dragón, not by this project's instrumentation.** His words: "when they approach my location they stand there without anything else to do, so their normal AI triggers again and makes them move to a location x in the distance... i confirmed this by not staying still, when constantly moving and running this never happens, because they never get an idle time enough for their AI to kick again." The log corroborates it exactly — the result value sits at 1 (AlreadyAtGoal) precisely when this happens.

**His fix, implemented as given:** "if they're already at goal, instead of idling, make them do an animation, so they're busy with something and dont wander off." When a follow order returns AlreadyAtGoal AND the Pal's ActionComponent reports empty, we play `ACTION_TYPE_PAL_RANDOM_REST` (77) — the same action Play already uses, so it is proven safe on a wild Pal. **This is better than the alternative that was about to be built** (a faster tick that cancels and re-issues the order 2x/second), and for a concrete reason: cancelling the Pal's current action twice a second would also cancel its attacks, breaking the fight-back behaviour fixed one pass earlier. Occupying an idle Pal cannot interrupt anything, because the `ActionIsEmpty()` gate means it only ever runs when the Pal is doing nothing at all — a Pal that is attacking, being attacked or mid-animation is left completely alone.

**Combat assist, now with real targeting via the Hate system.** Dragón's report was that companions defend themselves but "still dont defend me". The missing piece was never disposition (`Damaged_*` = Battle already works) — it was that a companion had no reason to consider the player's enemy its own. Confirmed real in this build's header dump, not guessed:

```
APalAIController::GetHateSystem() -> UPalHate*
UPalHate::ChangeHate(AActor* Attacker, float PlusHateValue)
UPalHate::FindMostHateTarget() -> AActor*
UPalHate::ForceHateUp_ForActiveAndAttackOtomoPal(AActor* OtomoPal)
```

Driven from the `PalHate:DamageEvent` hook Trust.lua ALREADY installs: whenever the player deals or takes damage, the other actor in that event is by definition the player's current enemy, so `Combat.OnPlayerCombatTarget(enemy)` pushes hate onto every following companion. No polling, no scan, no guessing what the player is fighting — the game hands us the actor. `Combat.FollowerActors` was added alongside `BondingState` (which only recorded *that* a key was following, not the live actor) and is kept in step in StartFollowing/StopFollowing. `[HATE-ASSIST]` logs only on target change, since a real fight fires damage events many times a second.

**Stated uncertainty, to be settled by the next test rather than assumed:** hate gives the companion a TARGET, but whether its AI then chooses to attack may still depend on the response preset, whose `Discover_*` slots are deliberately Ignore so companions stop starting fights. If hate alone proves insufficient, the next step is allowing Battle on discovery only while a player-target is active, rather than permanently. The `[HATE-ASSIST]` lines plus observed behaviour will distinguish these.

**Join toast now names the Pal**, per Dragón: "something like maybe '(palname) likes you and decided to join your party!'". Resolving the real localized name (so it reads "Petallia", the name he sees, not the internal id "FlowerDoll") uses two confirmed-real pieces from the header dump: `UPalMasterDataTablesUtility::GetLocalizedText(WorldContextObject, EPalLocalizeTextCategory, FName TextId)` with `EPalLocalizeTextCategory::PalMonsterName = 4` and the Pal's own CharacterID as the TextId. Every step is pcall-guarded with a two-level fallback (localized name -> raw CharacterID -> the original generic wording): a cosmetic toast must never break a capture that already succeeded.

**JOIN VFX — a genuinely new candidate, and the first real progress on this since `ABP_ReturnPalEffect_C` was ruled out.** Found this pass by searching the header dump rather than reusing an old guess:

```
class APalCapturedCage : public AActor
    void StartCaptureEffect_ServerBP(class APalPlayerCharacter* Player);
class ABP_PalCapturedCage_C : public APalCapturedCage
    class UNiagaraComponent* Niagara;   // 0x0308
    FBP_PalCapturedCage_COnCaptured OnCaptured;
```

This matches exactly what Dragón described watching during a vanilla cage rescue, and it takes the PLAYER as its argument — consistent with an effect that travels toward the player. **Important structural finding: the effect belongs to the CAGE actor, not to the Pal.** So it cannot simply be called on an arbitrary wild Pal; reproducing it means reading the Niagara *asset* off `ABP_PalCapturedCage_C`'s Niagara component and spawning that asset at the bonded Pal's location. That is a real, concrete next step (and a much better position than the previous dead end), but it needs either a live cage in the world to read the asset from, or an FModel read of that Blueprint to get the asset path — not something to guess at. Deliberately NOT implemented blind this pass.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-tenth pass (2026-09-06): the rest-animation fix reverted (my mistake, using a signal this project already knew was unreliable), the toast bug root-caused as a post-capture read, and the cage VFX probe that should have shipped last pass

**The rest animation is REMOVED. It was my error, and an avoidable one.** Dragón's live test found it backfired three separate ways, all real: (1) it interrupted his actual Pet/Feed/Play interaction the moment a Pal crossed 50%; (2) once resting, the Pal counted as busy so the follow order could not move it, leaving Pals stuck standing still instead of following; (3) it did not even work — they still wandered off, so the roam decision either queues behind or overrides a rest action.

The root cause of (1) is the important part: I gated it on `ActionIsEmpty()`, **a signal this project had already documented as unreliable for exactly this purpose.** The hundred-and-ninety-sixth pass established it "se libera casi al instante" — it reports empty in the gaps between the steps of a real multi-part interaction, which is precisely why it fired mid-interaction. Reaching for a signal the project's own notes call untrustworthy was not a defensible choice, and the correct move would have been to check that history before building on it.

**Replacement, attacking the same root cause through the MOVEMENT system instead of the action system**, so it structurally cannot interrupt an animation or block a fight:
- If the Pal has a hate target (`UPalHate::FindMostHateTarget`, the same system combat assist pushes to), the follow logic does nothing at all — a fighting companion is left alone. This also stops the follow order competing with the combat assist added last pass.
- Otherwise, when the order returns AlreadyAtGoal, it is re-issued to a point that slowly orbits the player (`ORBIT_RADIUS` 180, tight 60 acceptance, ~52 degrees per tick) rather than the player's exact position. The Pal therefore always holds a live path request and never gets an idle window — which is exactly the condition Dragón confirmed already works: *"when constantly moving and running this never happens, because they never get an idle time enough for their AI to kick again."* This gives them that same condition while he stands still. Passing the destination as a plain Lua table `{X=,Y=,Z=}` is already proven in this project (Indicator.lua's SetPosition/SetSize calls).

**Join toast bug root-caused, and it is the same bug class this project already fixed once.** The new code DID run — the log's `[NOTIFY] join message:` line is new this pass — but fell through to the generic fallback, meaning BOTH the localized lookup and the raw-CharacterID fallback failed. The cause is ordering, not the name lookup: `NotifyJoined` runs AFTER `TryDirectCapture`, and the same log shows `owner AFTER the call = nil`. The actor is mid-teardown, so its `CharacterParameterComponent` chain no longer resolves and every name route fails at step one. **This is exactly the bug the two-hundred-and-fourth pass fixed in `diagnose_post_capture_slot` (resolving a handle after the capture instead of before) — the same lesson, missed a second time.** Fixed by resolving the display name up-front via a new `resolve_pal_display_name`, called next to `preCaptureHandle` (which exists for precisely this reason) and passed into `NotifyJoined` as a plain string that survives the capture. Standing rule worth remembering: **anything that needs to read from the Pal must read it BEFORE `PalCaptureSuccess` runs.**

**`[CAGE-VFX]` probe added — read-only — and its absence last pass was my omission.** I told Dragón that finding a Pal cage would unblock the join VFX; he went to an enemy settlement and rescued a Pal ("swee") specifically to provide one, but no diagnostic existed to read anything from it, so that trip produced no data. The probe now runs at Init with a bounded retry (12 rounds, 10s apart) and tries two routes for the Niagara asset on `ABP_PalCapturedCage_C`: live instances via `FindAllOf`, then the class default object (which works even with no cage nearby, as long as the class has been loaded once — Dragón's rescue did that). It only resolves objects and reads fields; it never calls `StartCaptureEffect_ServerBP` and never touches a cage. Once the asset's object path is known it can be spawned at a bonded Pal's location with no cage present at all.

**Also confirmed from this run:** `[HATE-ASSIST]` fired zero times — expected, since no companion was ever actually following long enough for a fight to happen, so combat assist remains completely untested rather than disproven. And `find_targeted_pal` is now 42-47ms (was 48-74ms): the GetFullName-per-Pal removal helped, but the remaining `FindAllOf` + per-Pal `K2_GetActorLocation` cost is still a real hitch and still the largest one left.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-eleventh pass (2026-09-06): four bugs found in the log (two of them mine from last pass), the damage rule removed at Dragón's call, and a continuous move-to-ACTOR follow primitive that answers his SetActiveAI question

**1. The toast — the log gave the exact error, which beat the symptom report.** Dragón reported "no text whatsoever", which sounded like a regression. The log said what actually happened:

```
[NOTIFY] resolved display name BEFORE capture = FString: 000001EFCCE1BFC8
[NOTIFY] failed to show join toast: Capture.lua:282: attempt to concatenate a FString value (local 'palName')
```

So the name lookup WORKS — `GetLocalizedText` returned a real FText and `Conv_TextToString` returned a real value. That value is an **FString userdata wrapper, not a Lua string**, and concatenating it raises an error. Last pass's fix (resolve before the capture) was correct and necessary; this was a second, independent bug hiding behind it, which is exactly why the symptom changed from "generic text" to "no text at all" — the error now happens after the message would have been built. Fixed with a `to_lua_string` helper that handles both wrapper and plain string and deliberately refuses `tostring()`'s "FString: 0x..." rather than showing an address to the player.

**2. `[HATE-ASSIST]` fired ZERO times, and the reason is a bug I introduced, not an absence of fights.** Trust.lua has NO file-level `Combat` local — every other call site uses the lazy `pcall(require, "Combat")` pattern. Last pass I wrote `Combat.OnPlayerCombatTarget(enemy)` in the DamageEvent hook as if the module were in scope, so it indexed a nil GLOBAL, raised an error, and `safe_call` swallowed it every single time. **The wrong conclusion was then reported to Dragón** ("no companion followed long enough for a fight") when the call had simply never run. Fixed with the same lazy-require pattern. Combat assist remains entirely unexercised.

**3. The damage rule is removed for third-party attackers — Dragón's call, and the log backs it exactly.** Line-for-line from his run: a bonded FlowerDoll took 21 damage from a wild PinkRabbit, ate the full `-150` penalty, dropped to zero trust, and was force-tiered to "escape" — so it fled instead of fighting back. His reasoning: *"maybe we will need to remove that rule out, and only make them lose friendship if the player themselves hit them (the betrayal effect), since right now, in order for them to enter combat, first need to be hit by something."* Correct, and the rule had become self-defeating: the entire point of `Damaged_*` = Battle is that a companion gets hit and fights back, but the penalty destroyed the bond at exactly that moment. Third-party damage now costs no trust at all. Player betrayal is untouched and still resets the bond — that is a deliberate player choice, not something the world did to them.

**4. The `[CAGE-VFX]` probe had a self-contradictory bug, and it wasted Dragón's trip.** His log:

```
[CAGE-VFX] CDO cage NiagaraComponent=nil Asset=nil
[CAGE-VFX] asset resolved — probe done, will not run again this session
```

Those two lines cannot both be true. The cause: the log line was written as `tostring(obj and obj:GetFullName() or "nil")`, which prints "nil" both when the object is genuinely nil AND when the object exists but GetFullName fails — so the probe may well have HELD the asset and merely failed to print its name, then declared success on a read that produced nothing. Worse, it marked itself done at startup, so when Dragón went to a second settlement specifically to provide a fresh cage, nothing was still watching. Fixed three ways: presence and name are now reported as separate fields, success requires a real NAME STRING (with `GetPathName` as a second route), and the retry runs for ~30 minutes instead of 2 — because a cage only exists in the world once the player physically reaches one.

**5. Following — answering Dragón's SetActiveAI question with a real function, not a variation.** He asked whether something exists like the old `SetActiveAI(false)` (which stopped wandering but made Pals inert enough to stand there dying — the eighteenth pass's incident) but less total. Searching `APalAIController` in this build's dump turned up something better than a suppression switch:

```
void SimpleMoveToActorWithLineTraceGround(const class AActor* GoalActor,
                                          TEnumAsByte<ECollisionChannel> CollisionChannel)
```

**Every follow attempt this project has ever made has been LOCATION based** — the original nudge, the Otomo composite, and last pass's orbit — a one-shot "walk to this point" that completes, after which the Pal has no goal and its own AI takes over. This one takes an **ACTOR** as the goal, which is inherently continuous: the engine keeps steering toward a target that moves, which is what following actually means. It also fits Dragón's newest observation better than the idle theory did — he said the Pals "still managed to idle away somehow", doubting that reaching the goal is what triggers the wander. If the real problem is that a completed point-order simply leaves no goal at all, a target that is never "reached" removes the whole class of problem rather than patching a symptom. Tried first, behind `USE_MOVE_TO_ACTOR_FOLLOW`, with the location order as automatic fallback so a live test attributes any change cleanly. `ECC_Visibility = 3` read from Engine_enums.hpp, not guessed.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-twelfth pass (2026-09-06): hooking the cage rescue MOMENT, so the trip Dragón is about to make actually produces data

Dragón asked directly whether he still needs to rescue a Pal for the next run. **He does**, and this pass exists to make sure that trip is not wasted a third time.

The honest reasoning, since two previous trips produced nothing:
- **The class-default-object route is unlikely to work.** A Blueprint CDO generally does not carry live component references, which matches exactly what his log showed (`comp present=false`). It stays as a free fallback but should not be relied on.
- **The live route genuinely requires a cage actor in the world**, and a cage only exists while the player is physically near one. There is no way around that — the Niagara asset reference lives on the instance, not on the class.
- **The polling probe alone depends on luck**: it only catches a cage if a 10-second poll tick happens to land while he is standing near it.

So the probe is no longer the primary mechanism. A read-only hook is now installed on `/Script/Pal.PalCapturedCage:StartCaptureEffect_ServerBP` — the function that starts the rescue effect itself. It fires at exactly the moment the effect plays, with the live cage handed over as Context, which is the single best possible instant to read the asset. It observes only; it never calls `StartCaptureEffect_ServerBP`, so it cannot trigger or alter the vanilla rescue.

It logs three things, deliberately redundant so one trip answers the question even if an assumption is wrong:
1. The cage actor itself at the rescue moment.
2. The `Niagara` field's component, and its `Asset` by both `GetFullName` and `GetPathName` (presence and name reported separately — the two-hundred-and-eleventh pass's bug was exactly this conflation).
3. **Every** `UNiagaraComponent` on the cage via `K2_GetComponentsByClass`, so that if the effect is NOT the component named `Niagara`, the log still says which one it actually is — without needing yet another trip.

**Also cleaned up this pass:** eight hung background shell tasks on the developer machine, which Dragón spotted. Root cause: `npx --no-install luaparse <file>` with no stdout redirect hangs waiting on stdin. Every one of them had already completed its file edit before hanging, so no work was lost, and each edit had been independently verified afterwards. The working form is `out=$(npx --no-install luaparse "$f" 2>&1 >/dev/null)`, which is what every check in this session's later passes used.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-thirteenth pass (2026-09-06): the join VFX is real at last, combat assist's missing half found, and the name lookup narrowed to one unknown

**THE JOIN VFX IS IMPLEMENTED — the cage trip paid off.** Dragón's rescue let the probe read a real asset:

```
[CAGE-VFX] LIVE cage=BP_PalCapturedCage_C ... | comp present=true | asset present=true |
           asset name=NiagaraSystem /Game/Pal/Effect/Common/Glow/NS_SingleStar.NS_SingleStar
```

That asset is NOT the wanted effect — `Effect/Common/Glow/NS_SingleStar` is the little sparkle marker on the cage itself. **But knowing the asset PATH FORMAT was the actual unlock.** Searching `UE4SS_ObjectDump.txt` (117 MB, sitting in the ue4ss folder the whole time and never used before in this project) for NiagaraSystems under `/Game/Pal/Effect/` turned up a folder built for exactly this moment:

```
/Game/Pal/Effect/Common/PalCatch/NS_PalCatch_Success
/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear   (and 01 / 02)
/Game/Pal/Effect/Common/PalCatch/NS_PalAppear
/Game/Pal/Effect/Common/Return/NS_Return
```

Spawning uses `UNiagaraFunctionLibrary::SpawnSystemAtLocation`, confirmed present in this build's `Niagara.hpp` with the exact signature used. `NS_PalDisappear` is the default (closest match to "the Pal turns into light"), fired at the end of the happy reaction so the sequence reads **happy -> dissolve into light -> vanish -> named toast**. The alternates are listed in the source as a one-line swap, no further research needed if it reads wrong.

**Note the cage hook never fired.** `StartCaptureEffect_ServerBP` is real and the hook installed cleanly, but a cage rescue does not call it — so that function is NOT the rescue effect trigger. The polling probe is what produced the result. Worth recording so nobody re-tries that hook expecting it to fire.

**Combat assist: the hate push works, and the missing half is now identified.** `[HATE-ASSIST]` fired three times, correctly naming the BerryGoat Dragón was fighting — so the two-hundred-and-eleventh pass's nil-global fix was correct and the mechanism runs. But the companions still did not join in, which is **exactly the uncertainty flagged when it shipped**: hate gives the AI a TARGET, but the decision to engage runs through the response preset, and `Discover_*` was pinned to Ignore — so "I notice that BerryGoat" resolved to "do nothing" no matter how much hate it carried.

Fixed the way that pass predicted, not by reverting to permanent aggression (which caused companions to attack each other two passes ago): `Discover_*` is now **conditional** — Battle while the player is actually in a fight, Ignore otherwise. `Combat.OnPlayerCombatTarget` re-applies the companion preset on the transition into combat (once, not per damage event — a real fight fires many events a second), and a 12-second generation-guarded window flips every follower back to peaceful when the fighting stops.

**Name lookup narrowed to a single unknown.** The toast now works and shows `FlowerRabbit`/`FlowerDoll` — the internal ids, not the `Flopie`/`Petallia` Dragón sees in game. So `GetLocalizedText` returned nothing and the CharacterID fallback took over. The category is right (`PalMonsterName = 4`, read from the enum dump); the remaining unknown is the TEXT ID FORMAT. Rather than guess a third time, `[NAME-DIAG]` now tries the plausible formats in order — bare CharacterID, `PAL_NAME_<id>`, `NAME_<id>`, `<id>_NAME` — and logs what each returns, so one run settles it and the winner gets hard-coded. (`FindOrAddFName` is a `UEHelpers` method, not a global; Capture.lua now requires that helper the same way Interaction.lua already did.)

**Also confirmed good this run, from Dragón:** following holds much better with move-to-actor (occasional drift remains, "not as bad as before"), companions fight back without losing friendship now that third-party damage costs nothing, and three simultaneous followers "didn't feel as laggy as that previous time" — the per-follower logging removal held up.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-fourteenth pass (2026-09-06): the Pal name SOLVED, VFX pipeline confirmed but wrong effect, friendly fire root-caused, and four real lag sources cut

**Pal name — SOLVED, and Dragón confirmed it in game.** The `[NAME-DIAG]` probe answered it cleanly on three separate captures:

```
candidate 1 (Monkey_Fire)          -> Monkey_Fire     <- the id echoed straight back
candidate 3 (PAL_NAME_Monkey_Fire) -> Tanzee Ignis    <- the real name
```

The localisation key is `"PAL_NAME_" .. CharacterID`. Note WHY the earlier attempts looked like they half-worked: the bare CharacterID does not fail, it returns itself, so the code happily accepted "FlowerDoll" as a successful lookup. Hard-coded now and the candidate loop removed — it cost three `GetLocalizedText` round-trips per capture to re-derive a settled answer. **This item is closed.**

**Join VFX — the pipeline is CONFIRMED working, the asset was just wrong.** The log shows `spawned ... component=true` on all four captures and Dragón saw an effect play, so `SpawnSystemAtLocation`, the asset resolution and the timing are all correct. He described "something that looked like a vanish sphere animation but it wasn't fitting", which is exactly what `NS_PalDisappear` is — the recall-into-sphere effect.

Rather than spend one whole test run per candidate, the seven candidates are now a list cyclable in-game with **CTRL+V**, which plays the next one on the aimed Pal and logs its index. All of them can be judged in a single session; then `JOIN_VFX_INDEX` gets set and the key goes away. Default moved to `NS_PalCatch_Success` (index 1) as the most likely fit now that the recall-vanish is ruled out.

**Friendly fire, root-caused from Dragón's report.** His words: *"one of my followers accidentally hit another of my followers and they ended up fighting among everyone, it was chaos... they all died except one"*. This is the direct cost of `Discover_* = Battle` during the combat window — to a companion, another companion is just another Pal it noticed, so one stray hit starts a war. Fixed at the source: if BOTH sides of a damage event are Pals we are bonding with, `Combat.ClearMutualHate` pushes a large NEGATIVE hate each way so neither keeps the other as its most-hated target. (`UPalHate::ResetHateAll` exists but belongs to the Arena classes, not this one — checked in the dump rather than assumed — so negative `ChangeHate` is the available route.)

**Lag — four real sources cut, measured from the log rather than guessed:**
1. **430 startup lines of hook-retry failures** (282 `[WORKER-WATCH]` + 170 `[RADIAL-WATCH]`) — the same handful of dead function names failing once per retry round, each flushed to disk. Now each failing name logs ONCE; successes still always log.
2. **`find_targeted_pal` still costs 42-70ms per scan**, with 126 scans over 15ms in one run. The GetFullName-per-Pal waste was already removed and the remainder (FindAllOf + a location read per Pal) has no cheaper route, so the recompute interval went 0.25s -> 0.5s. The menu is only open a second or two and the player aims before opening it, so this halves the worst hitch in the mod with no behavioural change.
3. **`[INTERRUPT]` produced 222 lines for 37 real calls** (six each, all flushed). The before/after pattern earned its keep during the crash-hunting era, but these three calls are long proven safe — now behind `INTERRUPT_VERBOSE`, off by default, with failures still always logged.
4. Combined, the three above account for well over half of a 2379-line session.

**Still open, and honestly stated:** companions fought the enemy Pal but did not defend Dragón, and drifted off again. His own observation is the most useful lead — *"i could make noise nearby to make them focus on me again... probably what makes them drift away is that they forget im there"* — which points at the sensor/sight system losing track of the player rather than at the movement order. `RequestSightCheckAsync` is already used in `interrupt_and_resense` and would be the natural thing to re-trigger periodically on followers. Not implemented this pass; recorded as the next concrete lead rather than guessed at.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-fifteenth pass (2026-09-06): the VFX settled, Dragón's targeted-attack idea implemented with a real function, and his "re-discover" theory turned into code

**Join VFX — SETTLED.** Dragón cycled all seven with CTRL+V and picked the first: candidate 1 is `/Game/Pal/Effect/Common/PalCatch/NS_PalCatch_Success`. `JOIN_VFX_INDEX` was already 1, so real captures have been using it since the previous pass — nothing to change, just confirmed. **This item is closed.**

**Combat — Dragón's question produced a better design than what was in place.** His words: *"isnt it possible to just issue a command of, if im being attacked, make the pals following attack that pal in specific? instead of becoming agro on everything?"*

He is right, and the function for it exists:

```
UPalAIActionCombatBase::SetTargetAndNextAction(class AActor* Target)
```

That is the combat action's own "this is who you are fighting" setter. The previous approach relied entirely on broad aggression (`Discover_* = Battle`) to make a companion pick *something* and hoped it picked correctly — which is precisely why his run turned into companions fighting each other. Now, on every player-damage event, each following companion's current AI action is fetched and pointed directly at the player's enemy. Running it per damage event rather than only on entering combat means a companion that latches onto the wrong target gets corrected within a fraction of a second instead of staying locked on it. Type-checking is done by letting the pcall fail harmlessly on non-combat actions, rather than trying to enumerate every subclass.

This is a genuine improvement over the broad-aggression approach and came from Dragón, not from this project's own analysis. The aggression window stays for now (it is still what gets them to engage at all), but the retarget is what should make the engagement *correct*.

**Fleeing — Dragón's "re-discover" theory implemented.** He has now observed twice that *"i could make noise nearby to make them focus on me again... probably what makes them drift away is that they 'forget' that im there"*, and reported more running away this run. The log agrees on the mechanism: **7 leash breaks and 6 resulting forced escapes** — so they drift beyond the leash, lose all trust, and get force-tiered to escape. The drift is the cause; the fleeing is downstream.

His theory points at the SIGHT/SENSOR layer losing track of the player, which is a different subsystem from everything the movement work has been touching — and would explain why none of the move-order fixes addressed it. `RequestSightCheckAsync` is exactly a "look for things now" call and is already proven safe on wild Pals (`interrupt_and_resense` has used it for many passes). `Personality.RefreshSightOn` now re-triggers it on each follower every 3 follow ticks (~4.5s) — the software equivalent of him making noise. Throttled deliberately: it is an async sight trace, and one per follower per 1.5s is exactly the cost shape that caused the earlier interrupt-related lag.

**Lag confirmed improving:** the session dropped from 2379 to 1955 lines even though this run included Dragón cycling seven VFX previews, so the previous pass's four cuts held.

**Friendly fire, honest status:** `[FRIENDLY-FIRE]` fired 20 times, so the detection and hate-clearing both work — but the chaos still happened, because clearing the grudge does not stop `Discover_* = Battle` from re-aggroing them a moment later. The retarget above is the real fix for that; the hate-clearing stays as a complement. If the next run still shows companions fighting each other, the conclusion is that broad aggression has to go entirely and engagement must come from the retarget alone.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-sixteenth pass (2026-09-06): kill_all swapped into the roll, and Dragón's per-event edge case caught a real timer leak

**Personality roll: `warlike_without_player` -> `kill_all`**, at Dragón's request. His report was that the old tier "seems to not be reacting at all as it should", and what he actually wanted was a Pal that attacks anyone on sight — behaviour he had seen in vanilla but could not name. That is `BP_AIResponsePreset_Kill_All_C`, already confirmed real (one of the 11 found via repak against the vanilla pak, and already referenced in `EXCLUDED_FROM_ROLLING`).

Worth stating because it looks contradictory at a glance: the two mechanisms do NOT conflict, exactly as with NotInterested. `EXCLUDED_FROM_ROLLING` keeps Pals whose SPECIES preset is already Kill_All out of the roll; the new tier entry makes "kill_all" an outcome the roll can assign to any OTHER Pal. `warlike_without_player` stays defined in `TIER_TO_DONOR_PRESET_CLASS`, `DISPOSITIONS` and the label map so `ForceTier` can still reach it and old labels stay readable — it is simply no longer rolled. New distribution: normal 35 / friendly 30 / escape 10 / notinterested 10 / warlike 5 / warlike_anyway 5 / **kill_all 5**.

**Dragón's per-event edge case — he was right, and it was worse than log flooding.** His warning, from having watched other assistants make this mistake: *"when including a 'run per event' it usually ends up flooding the console... ideally you should only activate that IF there are pals following, otherwise you dont need to check everytime i get hit."*

Checked rather than assumed, and the real cost was not the log. With ZERO followers, `Combat.OnPlayerCombatTarget` still resolved the enemy actor, walked `BondingState`, set `playerCombatActive`, bumped the window generation, and **scheduled a fresh `ExecuteInGameThreadWithDelay` timer** — on every single damage event involving the player. One fight against one enemy is dozens of hits, so that is dozens of pending 12-second timers queued to do nothing, in an empty field, with nothing bonded. That is a genuine leak, not just noise, and it would have shipped unnoticed because it produces no visible symptom until it accumulates.

Fixed at both levels:
- `Combat.OnPlayerCombatTarget` early-returns on a plain `BondingState` scan before touching anything.
- `Combat.HasAnyFollower()` added (pure table scan, zero engine calls) and used one level up in Trust.lua's `PalHate:DamageEvent` hook, which fires for **every damage event in the world** — it previously did a `FindFirstOf` plus a `GetFullName` on the player before it could even decide whether the event was relevant. Now none of that runs unless something is actually following.

This is the second time Dragón's operational instinct has caught a real cost that the code review did not: the earlier one was spotting eight hung background shell tasks. Worth taking his "this pattern usually goes wrong" flags at face value and actually verifying them.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-seventeenth pass (2026-09-06): the native LEASH system found — a categorically different answer to following, and RETARGET confirmed dead

**Dragón asked whether we are running low on options and whether stripping the AI (`SetActiveAI`) has to come back. We are not, and it does not.** Palworld has a complete native leash system that this project had never looked at:

```
class APalAILeashActor : public APalAILeashActorBase
    APalAILeashActor* SpawnLeash(APalAIController* InInstigatorController,
                                 float InLeashInnerRadius, float InLeashOuterRadius,
                                 float InInvokerExtentRadius, bool bInAutoActivateLeash)
class APalAILeashActorBase : public AActor
    void SetLeashLocation(const FVector& NewLeashLocation)
    void ActivateLeash() / DeactivateLeash() / IsActiveLeash()
    float LeashInnerRadius / LeashOuterRadius
    delegate OnCharacterOutOfLeashRange(...)
```

**Why this is categorically different from the six mechanisms already tried.** Every previous attempt — the move-order nudge, the orbit, the Otomo composite, Funnel, move-to-actor — issued a COMMAND that the wild AI could out-vote on its very next decision. That is precisely the behaviour Dragón keeps describing: *"its like they follow for a few seconds then their IA make them ignore me, even if the tick nudge makes them look at me."* A leash is not a command the AI competes with; it is a **constraint the AI already obeys** when deciding where to wander. So instead of repeatedly telling the Pal to come back, we move the boundary it is already staying inside, and its own wandering keeps it near the player.

It is also exactly the "something like SetActiveAI but less total" he asked for two passes ago, and it disables nothing — the Pal keeps sensing, reacting and fighting normally, just inside a region that travels with the player. Implemented as `ensure_leash_for` / `update_leash_anchor` (called every follow tick with the player's location) / `release_leash` on stop. Inner 400, outer 900.

**Stated plainly as unverified:** `SpawnLeash` is declared on `APalAILeashActor` and is called here through that class's default object — the same route this project already uses for `PalUtility`, `NiagaraFunctionLibrary` and `KismetTextLibrary`. Whether it accepts being driven this way for a wild Pal is exactly what the next run tests. Every step is pcall-guarded and the existing move-to-actor follow is deliberately left running underneath, so a total failure is a no-op rather than a regression.

**`[RETARGET]` fired ZERO times — the previous pass's combat fix does not work.** `SetTargetAndNextAction` is real and on `UPalAIActionCombatBase`, but `GetCurrentAction_BP()` evidently does not hand back an object that accepts it (most likely it returns the composite/base action rather than the combat action itself). This matches Dragón's report exactly — *"havent seen them attack the pal attacking me unless they get hit"* — and it also means his Petallia moment was almost certainly retaliation, not protection, since the retarget never ran once. Recorded as a confirmed negative rather than left ambiguous; not chased further this pass because he asked to focus on following first.

**Log evidence this run:** 7 follow starts, 7 ends, 5 leash breaks and 5 forced escapes — so most follows still end by drifting out of range. `[FOLLOW-ACTOR]` confirms `SimpleMoveToActorWithLineTraceGround` is being accepted, so move-to-actor IS active and is still being out-voted; that is the strongest evidence yet that no command-based approach will hold, and the reason the leash is worth trying. `[HATE-ASSIST]` dropped to 3 (from 8) confirming the no-followers gate works. `[FRIENDLY-FIRE]` 11, unchanged in mechanism.

All 11 files verified with `luaparse`, deployed and md5-verified. Not confirmed live.

## Two-hundred-and-eighteenth pass (2026-09-06): the leash caused a real actor leak — my bug, turned off and capped

**Dragón's report was accurate and the cause is mine.** His words: *"the lag felt much more this time, in fact it felt like the longer the run the more that the lag was increasing."* That shape — worsening with session length — is a leak, and the previous pass introduced one.

**What happened.** `SpawnLeash` returned something the validity check rejected, so `ensure_leash_for` never cached anything. Because it is called from the follow tick, it **retried the spawn every 1.5 seconds, for every follower** — roughly two hundred attempts in a nine-minute session. `SpawnLeash` is a SPAWN function: whether or not the returned handle validated in Lua, the engine very likely created a leash actor in the world on each call. Hundreds of orphaned actors accumulating is exactly the reported symptom.

**The log hid it almost perfectly**, which is the part worth learning from. `[LEASH]` appears exactly ONCE in the whole 1112-line log, because the failure message was throttled by `loggedLeashOnce`. One quiet line, two hundred spawn attempts behind it. No log-volume analysis would ever have found this.

**Three distinct mistakes, named so they are not repeated:**
1. A failing operation was retried forever with no attempt cap.
2. The retried call was a SPAWN — the one category where a failed retry accumulates side effects in the world rather than merely burning time. Retry logic that is harmless for a read is dangerous for a spawn, and that distinction was not considered.
3. The throttled log made a loud problem look like a single quiet line. **This is the third time this project has hit "the throttle hides the cost, not the cost itself"** — the same shape as the `SetHPPercent` diagnostic hook and the prism poll, both found earlier in this same session. The pattern is now unmistakable: throttling output is not throttling work.

**Fixed:** `USE_NATIVE_LEASH_FOLLOW = false`, plus hard rails so it can never loop again even if re-enabled — one spawn attempt per Pal ever (`LEASH_MAX_ATTEMPTS_PER_PAL`), the whole mechanism self-disabling after 3 failures (`LEASH_MAX_TOTAL_FAILURES`), and the CDO lookup cached (it too was resolving on every call). **Dragón should restart the game** — orphaned actors from the last session only clear on restart.

**The leash idea itself is not dead, and the API is real.** But the route was wrong: creating a new leash per Pal is the wrong shape. If revisited, it should be by finding a Pal's EXISTING leash actor — wild Pals plausibly already have one anchoring them to their spawn area, which would explain both why they return to a fixed region and why every command-based follow gets out-voted — and simply moving that, rather than spawning anything.

**On Dragón's question "how come we didn't find this before":** honest answer, search vocabulary. Every previous hunt used follow/move/otomo/wander/composite terms. "Leash" was never searched against the game's API — despite this project using that exact word for its OWN distance check for many passes (`MAX_FOLLOW_DISTANCE`, described in comments as "approximates a leash break"). The concept was in our vocabulary and never turned into a query.

All 11 files verified with `luaparse`, deployed and md5-verified.
