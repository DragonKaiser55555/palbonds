--[[
    Interaction.lua — DESIGN.md §3.2

    NINETY-FIRST PASS (2026-09-03) — Dragón supplied the actual missing
    insight, from direct in-game observation: "i cannot choose which menu
    to open, i can just press 4, the menu itself opens depending on what i
    target, if its a base pal it opens the worker menu, if not then its
    the other one." That reframes everything from the eighty-eighth
    through ninetieth passes: the Worker Menu was never gated on wild-vs-
    owned — it's gated on whether the aimed Pal is assigned as a BASE
    WORKER. A wild Pal can never trigger it no matter how correct the
    OnClose/IndividualHandle fix is, because the game decides which menu
    to even construct before any of that code runs. Dragón's own framing
    of the next step: "we need to find that [decision] and trigger it too
    for wild pals so it can open the worker menu as well" — find the real
    eligibility check and make it treat an aimed wild Pal as eligible too.

    Found a strong, concrete candidate in the SDK dump:
    `UPalCharacterParameterComponent` (the same component
    get_individual_parameter/get_individual_handle already read from)
    has a plain field, `WorkAssignId` (`FPalWorkAssignHandleId{FGuid
    WorkId; int32 LocationIndex; EPalWorkAssignType AssignType}`), plus a
    getter `GetWorkAssign()` — exactly the kind of "is this Pal a
    registered base worker" state the menu-choice logic would plausibly
    read. Added a READ-ONLY diagnostic (`[WORKASSIGN-DIAG]`, a plain field/
    getter read, same safe pattern as every other component read in this
    file) that logs this for whatever's aimed at on every real "4" press,
    so the next live test — pressing 4 on both a real base worker AND a
    wild Pal — gives real evidence on whether this field is really the
    differentiator, BEFORE attempting to override anything (overriding a
    Pal's actual work-assignment state blind would risk corrupting real
    base-management bookkeeping, a MUCH bigger blast radius than anything
    touched so far — this project's hard-learned rule, per the eighteenth
    and eighty-second pass incidents, is real evidence first, always).

    NINETIETH PASS (2026-09-03) — REAL BREAKTHROUGH: the Worker Menu
    finally opened live (Dragón pressed "4" repeatedly aiming at different
    things), giving a full confirmed real sequence in the log:
    Construct→OnSetup→CreateContent(x5)→SetupContents→OnAnyUIPushed→
    OnClosed→OnSelectedEvent(index=5=Pet)→Destruct. But the eighty-ninth
    pass's diagnostic showed the eighty-eighth pass's hook point
    (`PushWidgetStackableUI`/`PalHUDService:Push`) had ZERO calls anywhere
    near that timestamp — proving those two functions are NOT how this
    menu's dispatch Parameter is delivered, despite matching the SDK's
    documented signature. `OnSetup` fired with every argument nil, meaning
    it takes no meaningful parameters — so the Parameter almost certainly
    isn't passed as an argument to ANY function at all; it's a plain
    Blueprint variable set directly on the widget (matching the
    `Parameter` name from `PushWidgetStackableUI`'s own signature).

    New real hook: `WBP_WorkerRadialMenu_Overlay_C:OnSetup`, reading
    `self.Parameter` directly off the widget instance handed to us via
    Context — no function argument needed. Given its own retry loop (same
    as every other Worker Menu Blueprint hook — the class isn't loaded at
    Init() time). The actual field-rewrite logic (find the aimed wild Pal,
    gate on Capture.IsAlreadyOwned, set IndividualHandle, bind OnClose) was
    extracted into `apply_wild_fix_to_worker_parameter()` so both this new
    hook and the old (likely dead, kept as a free diagnostic fallback)
    Push-based one can share it. This is the first attempt with a hook
    point actually PROVEN to fire during a real Worker Menu open — the
    eighty-eighth pass's logic was sound, it just needed the right door.

    EIGHTY-NINTH PASS (2026-09-03) — DIAGNOSTIC ADDED after three real
    live tests of the eighty-eighth pass's fix all came back with ZERO
    [WORKER-BIND-FIX] fires. Dragón tested carefully (clean ground, no
    nearby logs/stones, close range, direct aim, repeated "4" presses on a
    wild Lamball) and confirmed directly: "the radial menu that popped up
    was always the one from the active pal." `WORKER-WATCH` also still
    gives up after all 8 rounds every session — `WBP_WorkerRadialMenu_C`
    genuinely never loads at all in current play, on any target. That
    means the eighty-eighth pass's fix never got a chance to run, and
    raises a bigger open question: does `PushWidgetStackableUI` /
    `PalHUDService:Push` even fire AT ALL during a "4" press (for the
    Player Menu or anything), or is EVERY radial menu actually dispatched
    through some other, still-unidentified function? Added an unconditional
    (deduped-on-change) diagnostic log, `[WORKER-BIND-FIX-DIAG]`, that
    prints the class of literally every widget pushed through either
    hooked function — the next live "4" press will show directly whether
    this hook point sees ANY radial-menu traffic at all, which is the
    fact needed before deciding whether to keep pursuing this hook point
    or look elsewhere entirely.

    EIGHTY-EIGHTH PASS (2026-09-03) — THE FIRST REAL FIX ATTEMPT for "the
    real vanilla Worker Radial Menu ('4' wheel — Pet/Feed/Move to
    box/etc.) does nothing when aimed at a wild Pal." This had been an
    open question since the seventy-eighth pass.

    Root cause, found by comparing two real Live-View JSON dumps of
    PalHUDDispatchParameter_WorkerRadialMenu (one from pressing 4 on the
    real owned Otomo, one from pressing 4 on a wild Foxparks):

        owned: IndividualHandle = PalIndividualCharacterHandle_2147480691
               OnClose          = (BP_Kitsunebi_C_2147425992.OnSelectedOrderWorkerRadialMenu)
        wild:  IndividualHandle = PalIndividualCharacterHandle_2147480691  <- SAME object
               OnClose          = ()                                      <- empty

    Two things are broken for the wild case: OnClose (a single/dynamic
    delegate) is never bound to anything, AND IndividualHandle is the
    exact same shared handle in both dumps — never actually re-pointed at
    whatever Pal you're aiming at.

    Fix: a new RegisterHook on `/Script/Pal.PalHUDInGame:PushWidgetStackableUI`
    (and its likely-equivalent `/Script/Pal.PalHUDService:Push`) — both
    confirmed real in the SDK dump, both take
    (TSubclassOf<UPalUserWidgetStackableUI> WidgetClass,
    UPalHUDDispatchParameterBase* Parameter). This fires right as the
    already-built Parameter object is handed off to actually open a
    widget — late enough that every field is already set, early enough
    that nothing has read them yet. The hook bails out immediately unless
    the Parameter's class name contains "WorkerRadialMenu" (every other
    UI push in the game — chest, inventory, dialogs — is a no-op here).
    When it IS a WorkerRadialMenu Parameter, and find_targeted_pal (the
    same proven look-based targeting F9/F10 use) finds a wild Pal
    (Capture.IsAlreadyOwned gate) being aimed at, it rewrites BOTH fields:
    `Parameter.IndividualHandle` gets that wild Pal's own real handle
    (read via a new get_individual_handle() field-read helper, same
    pattern as get_individual_parameter), and `Parameter.OnClose` gets
    bound to that wild Pal's own `OnSelectedOrderWorkerRadialMenu`
    (confirmed on APalMonsterCharacter — the base class of every Pal
    actor, wild or owned, so this exact function already exists on it).

    STILL UNCONFIRMED, first live attempt: the exact UE4SS Lua syntax for
    binding a delegate property — used `Parameter.OnClose:Bind(wildPal,
    "OnSelectedOrderWorkerRadialMenu")` as the best-evidenced guess. Both
    the IndividualHandle write and the OnClose bind are wrapped in pcall
    and log their own ok/FAILED result separately, tagged
    [WORKER-BIND-FIX], so a live test immediately shows which of the two
    (if either) actually worked, and any error text from a wrong method
    name/signature comes straight into the log to iterate from. Owned-Pal
    behavior is untouched either way — the isWild gate means this hook
    does nothing at all unless the aimed Pal is confirmed wild.

    TWELFTH PASS (2026-09-01) — added Feed, and a first attempt at "don't
    run away afterward":

    1. FEED (F10). Same shape as pet, refactored into one shared
       do_interaction() function instead of duplicating targeting/busy-
       gating/logging twice. The only real difference is the PLAYER's own
       "reach out" action type: HumanFeeding (49, from Pal_enums.hpp)
       instead of HumanPetting (55). The TARGET's reaction is still Happy
       (38) — same proven-safe, single-grant mechanism from the eleventh
       pass, not the untested Eat (6) action type. This is a deliberate,
       documented approximation: real vanilla feeding lets you pick a
       specific food item from your inventory first (there's a whole
       SelectedFeedingItem(ItemSlotId, Num) call for that elsewhere in the
       SDK dump), and different foods likely grant different amounts. This
       mod doesn't touch inventory/item-selection at all yet — F10 just
       plays the feeding gesture and grants the same Happy-triggered +10
       as a pet does. Good enough to prove wild Pals CAN be fed at all;
       real food-item wiring is a separate future step if wanted.

    2. "CALM DOWN" ATTEMPT (try_calm_target). Dragón asked: once an
       interaction succeeds, can the Pal be made to not run away
       afterward (like Daedream, which just watches curiously instead of
       fleeing)? The real per-species "disposition" field DESIGN.md's Q1
       asks about is STILL not confirmed — Pal_enums.hpp has promising
       enum names (EWildPalAIMoveMode, EWarningPalAIMoveType,
       EWildPalAIRestType) but their individual VALUES have no names in
       the dump (they're not UENUM-exposed with display metadata), and
       none of the three are referenced anywhere in Pal.hpp as an actual
       field type — meaning they're Blueprint-graph-only, not something
       the static C++ SDK dump can show us. Rather than guess at a value,
       this pass does two things:

       a. A best-effort, HONEST first attempt at the observable symptom,
          using fields that ARE confirmed real (Pal.hpp, APalAIController):
          TargetPlayers / TargetNPCs (TArray<AActor*> — who the AI is
          currently tracking) get cleared, and HateSystem:ChangeHate() is
          pushed hard negative. This is the aggression/target-tracking
          system, not necessarily the same thing as a skittish species'
          flee trigger — it may or may not actually stop a Pal from
          running off. Treat it as an experiment, not a fix. Same
          "field access safe, whole-struct-by-value calls risky" pattern
          from the eighth pass — everything here is a direct field read
          or a plain void function with simple params, wrapped in pcall.

       b. A read-only, filtered property dump (dump_interesting_properties)
          modeled on the bundled ConsoleCommandsMod/dump_object.lua
          pattern: Class:ForEachProperty() walking up GetSuperStruct(),
          which — unlike Pal.hpp — also surfaces Blueprint-ADDED variables
          on the specific species Blueprint (e.g. whatever BP_Daedream_C
          adds on top of APalCharacter). Filtered to property names
          containing keywords like "warning", "escape", "flee", "hate",
          "personality", etc., logged once per successful interaction.
          Purely diagnostic — reads scalar values only, changes nothing —
          so a handful of real play sessions (ideally one on a Pal known
          to flee and one on a Daedream, which doesn't) should hand us
          real field names/values to close Q1 with, instead of guessing.

    ---- Eleventh-pass notes (two real bugs found via tenth-pass instrumentation) ----

    1. THE MOD HAD BEEN PETTING THE PLAYER'S OWN CHARACTER. A live session
       showed `targeted BP_Player_Female_C` repeatedly, always at the
       exact same 264 units / 18.7 degrees — the fixed third-person
       camera offset to the player's own body. `PalPlayerCharacter` is
       itself a `PalCharacter` subclass, so `FindAllOf("PalCharacter")`
       legitimately includes the player — and the `pal ~= excludeActor`
       check meant to filter that out doesn't reliably work: two separate
       UE4SS Lua wrappers for the SAME underlying UObject aren't
       guaranteed `~=`-comparable. This explains basically every
       confusing observation from that testing session: "petting the air"
       with nothing nearby (it silently hit the player instead, every
       time — 0 "not looking at any Pal" results across 51 presses in
       one session), and friendship climbing to unexpectedly high values
       (a single persistent target — the player — instead of many
       different wild Pals). Fixed by comparing `GetFullName()` strings
       instead of Lua object identity in `find_targeted_pal()`.

    2. DOUBLE FRIENDSHIP GRANT. The AddFriendShip watcher added last pass
       caught it directly: every successful pet fired TWO real
       AddFriendShip calls — ours (value=10, applyPassiveSkill=false)
       immediately, then a SECOND one (value=10, applyPassiveSkill=true)
       ~2-3 seconds later that this mod never made. That second call is a
       side effect of the target's Happy animation itself completing (its
       own internal logic, independent of what triggered Happy) —
       confirmed across every species tested, boss included, 100% of the
       time. So every pet was granting 20 friendship, not 10. Fixed by
       removing our own explicit AddFriendShip call entirely — triggering
       Happy already produces the correct single grant on its own, and it
       even matches the real vanilla shape exactly (value=10,
       applyPassiveSkill=true, same as the original Spy.lua observation
       of the actual in-game Pet/Feed menu).

    Both fixes confirmed live afterward — see hook-points.md.

    ---- Tenth-pass notes (readable log identity + AddFriendShip watcher) ----

    Live-tested the ninth pass: worked, no crash, but two open questions
    came out of reading the log: (a) the raw FName/pointer logging made it
    impossible to tell whether repeat presses hit the same Pal or
    different ones, and (b) friendship sometimes jumped by MORE than
    PET_FRIENDSHIP_GAIN between two of our own presses. Added a permanent
    RegisterHook watcher directly on the real AddFriendShip function (see
    Interaction.Init(), same safe pattern as Spy.lua) so we can SEE every
    real grant fire, by anyone. Also switched species/actor logging from a
    raw FName pointer to `:ToString()`/`:GetFullName()` (confirmed
    available via grepping bundled mods) so individual Pals are now
    actually identifiable in the log.

    ---- Ninth-pass notes (CONFIRMED WORKING: pet a wild Pal, no crash) ----
    This is the milestone Dragón asked for. Full log analysis in
    hook-points.md.

    1. Cleanup: find_targeted_pal used to log every single
       FindAllOf(PalCharacter) candidate (up to 20/press) via Logger.log,
       which flushes to disk on every call — that's what caused a
       framerate dip while spamming F9. Trimmed back down to just a count
       + result line.

    2. Real interaction, not spammable: added the player's OWN "reach
       out" gesture — self-directed PlayActionByType(pal, HumanPetting=55)
       on the PLAYER's ActionComponent, targeting the Pal. Spam
       prevention is structural rather than a cooldown timer: do_pet()
       checks the PLAYER's OWN ActionComponent:ActionIsEmpty() FIRST — a
       second F9 press while the reach-out/reaction animations are still
       playing is simply ignored. The target-busy check (added sixth
       pass) is also checked BEFORE granting anything, not just before
       the reaction animation.

       NOT yet attempted: the full synced `BP_ActionPairBehavior_Petting`
       cinematic Dragón originally described (camera cut, a distinct
       "being petted" pose on the target rather than reusing Happy,
       automatic camera/player/Pal reset once it's over). That's real
       Blueprint-graph pair-action machinery this project has deliberately
       avoided calling directly since crash #1 — worth revisiting later,
       but it's a bigger, separate research step (reading
       BP_AIActionPairCall_Petting's OnStartPair / the Camera field setup
       via FModel's Blueprint export), not something to bolt on blind.
       What ships is a solid approximation: player reaches out, Pal reacts
       with Happy, both sides gated so nothing can be spammed or
       interrupted mid-animation.

    ---- Eighth-pass notes (root cause found) ----
    GetSaveParameter() copies an 880-byte struct by value across the Lua
    boundary. See hook-points.md, "Crash #3 root cause" for the full
    writeup. Removed the call; read `param.SaveParameter.OwnerPlayerUId`
    directly off the object instead (same data, no function call, no
    whole-struct copy). This function had been present in every single
    crash-triggering version since the third pass.

    ---- Seventh-pass notes (instrumentation added, found the crash site) ----
    Added a Logger.log() call before and after literally every single
    native/engine call in do_pet() and find_targeted_pal(), so a crash
    would have an exact last-known-good line in palbonds-live.log
    immediately before it. This is what actually found the real bug.

    ---- Sixth-pass notes (busy/sleeping guard, superseded above) ----
    Added a check on the TARGET's ActionComponent:ActionIsEmpty() before
    calling PlayActionByType on it. The check itself is still good
    practice (matches vanilla, costs nothing) so it's kept.

    ---- Third-pass targeting fix (kept, still believed correct) ----
    Replaced "closest PalCharacter anywhere in the loaded world" with real
    look-based targeting: camera location + control rotation build a
    forward vector, and only a Pal within both PET_RANGE and
    PET_MAX_ANGLE_DEG of that vector qualifies, picking the most centered
    match.

    PET_KEY is F9, FEED_KEY is F10 (not 'P'/'F', which open game menus;
    not accented/layout-dependent keys, not guaranteed to exist the same
    way in UE4SS's Key table across setups).
]]

local Logger = require("Logger")
local Trust = require("Trust")
local Capture = require("Capture")
local Personality = require("Personality")

local Interaction = {}

-- Tunable — adjust once we can see real distances/feedback in-game.
local PET_KEY = "F9"
local FEED_KEY = "F10"
-- THIRTY-EIGHTH PASS (2026-09-02): a dedicated, deliberately separate key
-- for Capture.TryDirectCapture — the project's first genuinely
-- experimental live call. See Capture.lua's own comment for the full
-- risk breakdown. Kept off F9/F10's shared do_interaction() path on
-- purpose: this is a manual, one-off test action, not part of normal
-- pet/feed play.
--
-- FORTY-FIRST PASS (2026-09-02) FIX: originally bound to plain F11.
-- Dragón reported it was actually toggling Palworld's fullscreen mode
-- instead (F12, considered for the now-removed rank-table dump key, has
-- the same problem — it's the Steam screenshot key). Plain F-keys past
-- F10 collide with OS/platform/engine-level bindings that fire
-- independently of whatever UE4SS's RegisterKeyBind does — UE4SS gets
-- the keypress too, but so does everything else listening for that raw
-- key. Fixed by switching to a CONTROL+letter combo instead (the same
-- pattern UE4SS's own bundled Keybinds mod uses for its tools, e.g.
-- CONTROL+J, CONTROL+H) via RegisterKeyBindAsync — a modifier
-- combination is far less likely to already mean something to either
-- Palworld or the OS. Picked K (not otherwise used in this project or,
-- as far as tested, by Palworld/Windows).
local TEST_CAPTURE_KEY = Key.K
local TEST_CAPTURE_MODIFIERS = {ModifierKey.CONTROL}
-- Hundred-and-thirty-eighth pass (2026-09-04): CTRL+J, repurposed. Used
-- to be TEST_FEED_ITEM_KEY (the real-food-item test) — that thread is
-- confirmed dead-end for wild Pals (hundred-and-nineteenth pass:
-- RequestUseToCharacter only works on the player's own active Otomo) and
-- item 7 on the saved priority list is shelved because of it. Per
-- Dragón's own standing rule ("if you need to add a new one, remove or
-- swap for one already used in the project"), this physical key is
-- reused for the new Play interaction instead of adding a fifth bind.
local PLAY_KEY = Key.J
local PLAY_MODIFIERS = {ModifierKey.CONTROL}
local PET_RANGE = 500.0       -- Unreal units (cm). ~5 meters.
local PET_MAX_ANGLE_DEG = 25  -- how far off-center the camera can be and still count as "looking at" a Pal.
local INTERACTION_FRIENDSHIP_GAIN = 10 -- matches the real Pet/Feed grant observed via Spy.lua/the AddFriendShip watch hook (documentation only, see note near the Happy call below).

-- EPalActionType values, from Pal_enums.hpp.
-- HumanPetting/HumanFeeding: the PLAYER's own "reach out" gesture,
-- self-targeted on the player's own ActionComponent, aimed at the Pal.
local ACTION_TYPE_HUMAN_PETTING = 55
local ACTION_TYPE_HUMAN_FEEDING = 49
-- Happy: confirmed via Spy.lua/the [WATCH] hook to be exactly what the
-- target Pal's own ActionComponent plays, self-targeted, after every real
-- AddFriendShip call during a vanilla Pet/Feed interaction, and to itself
-- reliably trigger exactly one AddFriendShip(10, true) call as a side
-- effect (see eleventh-pass notes). Reused for both pet and feed so both
-- interactions share the one proven-safe reaction/grant mechanism.
local ACTION_TYPE_HAPPY = 38
-- Hundred-and-thirty-eighth pass (2026-09-04): PalRandomRest, confirmed
-- real in Pal_enums.hpp (value 77) — the same simple int enum every
-- other reaction in this file already plays through PlayActionByType.
-- Used for the new Play interaction's Pal-idle half: no new calling
-- mechanism needed, just a different EPalActionType value than Happy.
local ACTION_TYPE_PAL_RANDOM_REST = 77
-- Hundred-and-forty-third pass (2026-09-04): how long to wait after the
-- Pal-idle animation before sequencing the Happy follow-up (the hearts
-- VFX, confirmed baked into BP_ActionHappy's own graph — see hook-points.
-- md). PalRandomRest picks one of several montages at random per species
-- (FPalRandomRestInfo, different LoopNum_Min/Max per entry), so there is
-- no single real duration to read back yet — this is an honest fixed
-- approximation (same category as Feed's item-selection gap), not a
-- precise sync. Adjust based on real observation if it feels off.
-- Hundred-and-forty-eighth pass (2026-09-04): Dragón's real test — 3s cut
-- some idle animations off before they'd finished playing properly.
-- Bumped to 6s per his direct request.
local PLAY_HAPPY_FOLLOWUP_DELAY_MS = 6000

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil, result
end

local function vec_sub(a, b)
    return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function vec_length(v)
    return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

local function vec_normalize(v)
    local len = vec_length(v)
    if len < 1e-6 then
        return { X = 0, Y = 0, Z = 0 }
    end
    return { X = v.X / len, Y = v.Y / len, Z = v.Z / len }
end

local function vec_dot(a, b)
    return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

-- Builds a forward unit vector from an FRotator (Pitch/Yaw in degrees).
local function rotator_to_forward(rot)
    local yaw = math.rad(rot.Yaw)
    local pitch = math.rad(rot.Pitch)
    return {
        X = math.cos(pitch) * math.cos(yaw),
        Y = math.cos(pitch) * math.sin(yaw),
        Z = math.sin(pitch),
    }
end

-- Finds the PalCharacter the player is actually looking at: within
-- PET_RANGE of originLoc AND within PET_MAX_ANGLE_DEG of forwardVec.
-- Among qualifying candidates, picks the most centered one (smallest
-- angle), not just the nearest.
--
-- BUG FOUND (2026-09-01, tenth-pass log, fixed eleventh pass):
-- FindAllOf("PalCharacter") also returns the PLAYER's own actor
-- (PalPlayerCharacter is itself a PalCharacter subclass). The old
-- `pal ~= excludeActor` check was meant to filter it out, but Lua
-- reference equality on two separately-obtained UE4SS object wrappers
-- for the SAME underlying UObject isn't reliable here. Fixed by
-- comparing `GetFullName()` strings instead, which reliably identifies
-- the same actual game object regardless of which Lua wrapper instance
-- is holding it. Confirmed fixed live (zero self-targeting occurrences
-- across a full follow-up session).
--
-- KNOWN LIMITATION (not yet fixed): large bosses (e.g. Mammorest) can be
-- effectively untargetable — this does a single-point distance/angle
-- check against pal:K2_GetActorLocation() (the actor's root/pivot),
-- which for a boss-scale creature can sit far from wherever the player
-- is visually aiming at its bulk. Confirmed via ~44s of "not looking at
-- any Pal" while clearly looking at a Mammorest. Future fix: scale
-- tolerance by actor bounding size, or check mesh/capsule extent instead
-- of a single origin point. Not urgent — normal-sized wild Pals work
-- correctly.
local function find_targeted_pal(originLoc, forwardVec, excludeActor)
    local pals = FindAllOf("PalCharacter")
    if not pals then
        return nil, nil, nil
    end

    local excludeName = safe_call(function() return excludeActor and excludeActor:GetFullName() end)

    local best, bestAngle, bestDist = nil, nil, nil
    for _, pal in ipairs(pals) do
        local validOk, isValid = pcall(function() return pal ~= nil and pal:IsValid() end)
        local isExcluded = false
        if validOk and isValid and excludeName then
            local palName = safe_call(function() return pal:GetFullName() end)
            isExcluded = (palName ~= nil and palName == excludeName)
        end
        if validOk and isValid and not isExcluded then
            local loc = safe_call(function() return pal:K2_GetActorLocation() end)
            if loc then
                local toTarget = vec_sub(loc, originLoc)
                local dist = vec_length(toTarget)
                if dist <= PET_RANGE and dist > 1e-3 then
                    local dir = vec_normalize(toTarget)
                    local dot = math.max(-1.0, math.min(1.0, vec_dot(dir, forwardVec)))
                    local angle = math.deg(math.acos(dot))
                    if angle <= PET_MAX_ANGLE_DEG then
                        if not bestAngle or angle < bestAngle then
                            best, bestAngle, bestDist = pal, angle, dist
                        end
                    end
                end
            end
        end
    end

    return best, bestDist, bestAngle
end

local function get_individual_parameter(pal)
    local comp = pal.CharacterParameterComponent
    if not comp or not comp:IsValid() then
        return nil
    end
    return safe_call(function() return comp:GetIndividualParameter() end)
end

-- Eighty-eighth pass (2026-09-03): companion to get_individual_parameter,
-- for the OnClose-binding fix below. UPalCharacterParameterComponent has a
-- plain `IndividualHandle` FIELD right next to `IndividualParameter` in the
-- SDK dump (Pal.hpp) — not a by-value struct, just a pointer, so a direct
-- field read is safe by this project's established rule (field access
-- safe, whole-struct-by-value calls risky). This is what lets us get the
-- SAME kind of handle object the real vanilla WorkerRadialMenu dispatch
-- parameter expects in its own `IndividualHandle` field, for ANY Pal actor
-- (wild or owned) — not just the current Otomo.
local function get_individual_handle(pal)
    local comp = pal.CharacterParameterComponent
    if not comp or not comp:IsValid() then
        return nil
    end
    return safe_call(function() return comp.IndividualHandle end)
end

-- ---------------------------------------------------------------------
-- Hundred-and-twenty-first pass (2026-09-03): correcting a candidate the
-- hundred-and-twentieth pass proposed, and testing a better one instead.
--
-- CORRECTION: that pass's leading candidate for "the deeper ownership
-- gate real Feed checks", `TArray<FPalInstanceID> OtomoIndividualIdList`,
-- is real in Pal.hpp — but re-checking exactly which struct declares it
-- shows it's a field of `FPalArenaPlayerInitializeParameter` (every
-- sibling field on that struct is Arena-prefixed: ArenaRank, bIsNpc,
-- OtomoPicks, bPartySelected). This project already made and corrected
-- this exact mistake once before (twenty-first pass: `GetOtomoHolder
-- (PlayerState)` looked generically useful but "turned out to belong to
-- an Arena/PvP-test-only class"). Same shape of error, same fix: this
-- field is very unlikely to be read during ordinary wild-Pal Feed play,
-- and isn't worth Dragón spending a test on.
--
-- BETTER CANDIDATE, found by searching Pal.hpp for every non-Arena
-- TArray<FPalInstanceID>/TArray<UPalIndividualCharacterHandle*> field or
-- getter: `class UPalPlayerPartyPalHolder : public UObject` — the same
-- real, non-Arena class this project already confirmed back in the
-- sixth continuación (FirstOtomoPal/SecondOtomoPal/BenchMember, the
-- "two simultaneous Otomo slots" finding that explained Daedream/Dazzi/
-- Flopie following as secondaries). It also has, undocumented until now:
-- `void GetPartyMember(TArray<UPalIndividualCharacterHandle*>&
-- OutPartyMember)` (a real membership query) and — the strongest
-- candidate this project has found for this question so far —
-- `bool PawnOtmoIsPartyOtomo(bool SecondPal, UPalIndividualCharacterHandle*
-- IDHandle)`. That name and shape (bool return, takes a handle directly
-- as a parameter) reads exactly like "is this specific handle actually
-- my registered party Otomo" — the real question this whole thread has
-- been trying to answer since the hundred-and-twentieth pass.
--
-- No getter anywhere else in Pal.hpp exposes a `UPalPlayerPartyPalHolder*`
-- by name (grepped the whole file) — meaning either it's reached through
-- a generically-typed field the dump doesn't tag, or the safest way to
-- find a live instance is the same technique already proven repeatedly
-- in this project for exactly this situation (`WBP_PalNPCHPGauge_C`,
-- fiftieth pass): `FindAllOf` the class name directly and see what's
-- really alive, rather than assume a wiring path from static reflection
-- alone.
--
-- This is a ONE-SHOT diagnostic (called once per newly-aimed wild Pal,
-- from inside the existing dedup gate below — never per-tick, per this
-- project's own hard-learned lag lesson from the thirty-third/eightieth/
-- hundred-and-second passes) — not a permanent watch, and it calls
-- nothing that mutates anything: `FindAllOf` (read), plain field reads
-- (FirstOtomoPal/SecondOtomoPal/BenchMember — pointers, same safe
-- pattern as every other field access in this file), and
-- `PawnOtmoIsPartyOtomo` (a bool-returning query, structurally the same
-- risk class as `TargetIsPlayerOrPlayersOtomoPal`, already called safely
-- elsewhere in this project). No write of any kind. If this comes back
-- `false` for the substituted wild Pal (expected) while the real Otomo's
-- own handle reads `true` on the SAME holder instance, that's real
-- confirmation this is the actual gate — and a safe, well-evidenced
-- function to test calling FOR REAL on a wild Pal's handle in a future
-- pass, once Dragón is ready to consider that (this pass only ever reads
-- its result, never acts on it).
local function diagnose_party_membership(wildPal, wildHandle)
    -- Self-contained describe helper (not the shared hook_describe — that
    -- one is declared further down in this file, after this function, so
    -- referencing it here would resolve as an undefined global, not the
    -- local — same "field access safe, whole-struct calls risky" pattern
    -- as everywhere else, just describing an object rather than reading
    -- SaveParameter).
    local function describe(obj)
        if obj == nil then return "nil" end
        local ok, name = pcall(function() return obj:GetFullName() end)
        if ok and name then return name end
        return tostring(obj)
    end
    local ok, err = pcall(function()
        local holders = FindAllOf("PalPlayerPartyPalHolder") or {}
        Logger.log(string.format(
            "[PalBonds/Interaction] [PARTY-DIAG] FindAllOf(PalPlayerPartyPalHolder) found %d live instance(s)",
            #holders
        ))
        for i, holder in ipairs(holders) do
            local validOk, isValid = pcall(function() return holder ~= nil and holder:IsValid() end)
            if validOk and isValid then
                local first = safe_call(function() return holder.FirstOtomoPal end)
                local second = safe_call(function() return holder.SecondOtomoPal end)
                local benchCount = safe_call(function()
                    local bench = holder.BenchMember
                    return bench and bench:GetArrayNum()
                end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] [PARTY-DIAG] holder[%d]: FirstOtomoPal=%s SecondOtomoPal=%s BenchMember count=%s",
                    i, describe(first), describe(second), tostring(benchCount)
                ))
                if wildHandle then
                    local firstOk, firstResult = pcall(function() return holder:PawnOtmoIsPartyOtomo(false, wildHandle) end)
                    local secondOk, secondResult = pcall(function() return holder:PawnOtmoIsPartyOtomo(true, wildHandle) end)
                    Logger.log(string.format(
                        "[PalBonds/Interaction] [PARTY-DIAG] holder[%d]:PawnOtmoIsPartyOtomo(false, wild %s) = %s | (true, ...) = %s",
                        i, describe(wildPal),
                        firstOk and tostring(firstResult) or ("CALL FAILED: " .. tostring(firstResult)),
                        secondOk and tostring(secondResult) or ("CALL FAILED: " .. tostring(secondResult))
                    ))
                end
            end
        end
    end)
    if not ok then
        Logger.log("[PalBonds/Interaction] [PARTY-DIAG] scan failed (non-fatal, caught): " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------
-- HUNDRED-AND-THIRD PASS (2026-09-03): first research step toward real
-- food-item feeding. Dragón's actual ask: F10/the wild-Pal Feed action
-- should consume a real food item from the player's inventory (and open
-- the real inventory to pick one), instead of the twelfth pass's
-- approximation (just plays the feeding gesture, no item involved).
--
-- SDK dump findings (Pal.hpp / Pal_enums.hpp), all real, none guessed:
--   - `APalMonsterCharacter:SelectedFeedingItem(FPalItemSlotId, int64
--     Num)` — same base class as OnSelectedOrderWorkerRadialMenu (every
--     Pal actor, wild or owned) — looks like THE function that actually
--     delivers a chosen food item to a Pal.
--   - `FPalItemSlotId { FPalContainerId ContainerId; int32 SlotIndex }`
--     — what SelectedFeedingItem needs. We don't have a proven way to
--     build one for an arbitrary food item yet (needs the player's own
--     inventory container ID + the slot index actually holding that
--     item) — that's the next research step, not done this pass.
--   - `UPalItemUtility` (a BlueprintFunctionLibrary, same CDO-call
--     pattern already proven in Capture.lua/Personality.lua for
--     UPalUtility) has `CollectLocalPlayerControllableItemInfos_ByTypeB`
--     — lets us ask "what food/friendship items does the player
--     actually have" WITHOUT needing any UI. Its `OutItemInfos` is an
--     out-param array, and this project has no proven UE4SS Lua pattern
--     yet for reading one back — first live test below, unconfirmed.
--   - `EPalItemTypeB` (Pal_enums.hpp) has real, separate values for
--     general Pal food (FoodMeat=47, FoodVegetable=48, FoodFish=49,
--     FoodDishMeat=50, FoodDishVegetable=51, FoodDishFish=52,
--     FoodProcessed=53) AND a DEDICATED friendship-treat category,
--     ConsumePalGainFriendshipPoint=45 — likely what Dragón meant by
--     "kinship peaches." `UPalStaticConsumeItemData` (the base food-item
--     class) only carries RestoreHP/SP/Satiety/Sanity fields — no
--     visible per-item friendship amount — so vanilla feeding's
--     friendship gain may come from the interaction itself (same fixed
--     amount regardless of food), same as this mod's current approach,
--     not from the item. Unconfirmed either way.
--
-- This pass ships READ-ONLY diagnostics only, per this project's own
-- rule (never write real inventory/item state before confirming via
-- read-only checks first) — nothing about existing Pet/Feed behavior
-- changes. Two additions: (1) a passive watch-hook on
-- SelectedFeedingItem, to see if/when it fires naturally; (2) an F10-
-- triggered dump of what real food/friendship items the player is
-- currently carrying, to prove out (or correct) the CollectLocal-
-- PlayerControllableItemInfos_ByTypeB calling convention with real
-- data before anything tries to act on it.

local PalItemUtilityCDO = nil
local function get_pal_item_utility()
    if PalItemUtilityCDO then return PalItemUtilityCDO end
    PalItemUtilityCDO = safe_call(function()
        return StaticFindObject("/Script/Pal.Default__PalItemUtility")
    end)
    return PalItemUtilityCDO
end

-- EPalItemTypeB values that plausibly count as "feed this to a Pal":
-- general food (satiety) plus the dedicated friendship-treat category.
local FOOD_ITEM_TYPE_B_VALUES = {
    45, -- ConsumePalGainFriendshipPoint ("kinship peach"-style treats)
    47, -- FoodMeat
    48, -- FoodVegetable
    49, -- FoodFish
    50, -- FoodDishMeat
    51, -- FoodDishVegetable
    52, -- FoodDishFish
    53, -- FoodProcessed
}

-- [FOOD-DIAG] First live attempt at reading the player's real food
-- inventory via UPalItemUtility. Everything here is a GUESS about UE4SS
-- Lua's exact calling convention for a BlueprintFunctionLibrary function
-- with a TArray<enum> in-param and a TArray<struct> OUT-param — wrapped
-- pcall-per-step so the log shows exactly which step (if any) fails,
-- same iterate-from-the-error approach used for the Worker Menu's
-- OnClose:Bind() discovery. Does not write anything — CollectLocal-
-- PlayerControllableItemInfos_ByTypeB is a pure query in the SDK dump.
-- Hundred-and-eighth pass: the hundred-and-seventh pass's fix worked —
-- the out-param table now comes back with real entries (2 items, both
-- live tests). Each entry is a wrapped FPalStaticItemIdAndNum struct
-- (`StaticItemId` FName + `Num` int32, confirmed in the SDK dump) — a
-- plain field read, the same proven-safe pattern this whole file
-- already uses everywhere else (never GetSaveParameter()-style
-- whole-struct-by-value calls). Reading the actual fields now instead
-- of just logging the opaque handle.
-- Hundred-and-ninth pass: the hundred-and-eighth pass's field reads
-- (entry.StaticItemId, entry.Num) came back nil on every one of 6 real
-- entries in a live test — no crash, just nil, exactly the kind of
-- silent failure safe_call() is built to hide the reason for. Switched
-- to explicit pcall-per-step here (not safe_call) so the log shows the
-- REAL error text if the field access itself is throwing, rather than
-- just "nil" with no way to tell a genuine null field apart from a
-- wrong access pattern on this "LocalUnrealParam"-wrapped struct type
-- (a kind of entry this project hasn't read fields from before — every
-- prior struct field read in this file has been on a direct component/
-- object field, not an entry pulled out of a TArray-of-structs
-- returned through an out-param).
local function log_food_result(label, result)
    Logger.log(string.format("[PalBonds/Interaction] [FOOD-DIAG] %s returned (raw): %s", label, tostring(result)))
    local okIter, iterErr = pcall(function()
        if type(result) == "table" then
            for i, entry in ipairs(result) do
                local okId, itemIdOrErr = pcall(function() return entry.StaticItemId end)
                local idFieldStr = okId and tostring(itemIdOrErr) or ("FIELD-READ-FAILED: " .. tostring(itemIdOrErr))
                local idToStringStr = "n/a"
                if okId and itemIdOrErr ~= nil then
                    local okToStr, toStrOrErr = pcall(function() return itemIdOrErr:ToString() end)
                    idToStringStr = okToStr and tostring(toStrOrErr) or (":ToString() FAILED: " .. tostring(toStrOrErr))
                end
                local okNum, numOrErr = pcall(function() return entry.Num end)
                local numStr = okNum and tostring(numOrErr) or ("FIELD-READ-FAILED: " .. tostring(numOrErr))
                Logger.log(string.format(
                    "[PalBonds/Interaction] [FOOD-DIAG] %s item[%d]: StaticItemId(raw field)=%s StaticItemId:ToString()=%s Num=%s (entry=%s)",
                    label, i, idFieldStr, idToStringStr, numStr, tostring(entry)
                ))
            end
        end
    end)
    if not okIter then
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] could not iterate " .. label .. " result table: " .. tostring(iterErr))
    end
end

-- Hundred-and-seventh pass: the hundred-and-sixth pass's live test settled
-- both open questions about this call's shape. Attempt B (omitting the
-- out-param) FAILED outright with a real, precise UE4SS error —
-- "UFunction expected 4 parameters, received 3" — hard confirmation
-- that the SDK dump's 4-parameter signature is exactly right and must
-- be called with all 4 arguments; that guess is now dead, not
-- resurrected. Attempt A (4 args, `{}` placeholder for the out-param)
-- ran with no arity error and no crash, but its RETURN value was nil —
-- expected once you account for `CollectLocalPlayerControllableItemInfos_ByTypeB`
-- being declared `void` in the header dump: a void UFunction has no
-- return value to capture, so `local result = obj:Fn(...)` was always
-- going to be nil regardless of whether the call did anything useful.
-- The real data (if this call worked at all) would have to have been
-- written INTO the table passed as the out-param argument — UE4SS's
-- Lua bindings mutate TArray-typed arguments in place rather than
-- returning them. Fixed by keeping a named local table, passing THAT
-- same variable in, and reading it back afterward instead of the
-- call's (necessarily empty, for a void function) return value.
-- Hundred-and-eleventh pass: Dragón correctly called out that the field
-- reads coming back clean-nil (no error) meant the array-of-structs
-- approach was genuinely stuck, and asked to go investigate the game's
-- own files directly instead of guessing at Lua syntax further — this
-- project's own established fallback (repak) already used successfully
-- in the seventy-third/seventy-eighth/ninety-third/ninety-fifth passes.
-- Extracted `Pal/Content/Pal/DataTable/Item/DT_ItemDataTable_Common.uasset`
-- from the real game .pak with repak and read its embedded name table
-- with `strings` (the .uexp holds only packed binary row DATA — no
-- readable text; the .uasset holds the package's Name Table, which is
-- where every FName string referenced by the table's rows actually
-- lives). Found real, plausible row names: "BerryRed", "MeatRaw",
-- "MeatMarbledRaw", "Milk", "Honey", "Egg" (ordinary food) and, notably,
-- "AffectionFruit_01"/"AffectionFruit_02" — "Affection" strongly matches
-- EPalItemTypeB.ConsumePalGainFriendshipPoint (the dedicated friendship-
-- treat category found in the hundred-and-fourth pass's SDK research)
-- and is very likely the real item(s) behind Dragón's "kinship peach"
-- idea. These are asset/visual-model-adjacent names, not confirmed
-- as the EXACT StaticItemId strings the game's inventory system uses
-- internally — a real possibility, not yet proven.
--
-- Rather than keep fighting the broken struct-array read, this pass
-- tries a completely different, much simpler function instead:
-- `CountLocalPlayerInventoryItemNum64(WorldContextObject, StaticItemId)`
-- returns a plain int64 — no TArray, no out-param, no struct wrapping
-- at all — for each of these real candidate names. If even one comes
-- back non-zero and matching what Dragón is actually carrying, that
-- both confirms the exact string format the game expects AND gives a
-- confirmed-working, much simpler path forward for Stage 2 than the
-- array approach ever was.
local FOOD_CANDIDATE_ITEM_IDS = {
    "BerryRed", "MeatRaw", "MeatMarbledRaw", "Milk", "Honey", "Egg",
    "AffectionFruit_01", "AffectionFruit_02",
}

-- !!! DO NOT CALL THIS FUNCTION LIVE !!! (as of the hundred-and-twelfth
-- pass, 2026-09-03). One of the two calls inside it — most likely the
-- CountLocalPlayerInventoryItemNum64 loop below, passing a plain Lua
-- string where the native function wants an FName — caused a REAL,
-- reproducible (2/2) game crash (EXCEPTION_ACCESS_VIOLATION, near-null
-- read). This is left here only as a record of what was tried and why
-- it's dangerous. Disconnected from do_feed() — see that function's own
-- comment and DESIGN.md's "Crash #4" writeup before ever re-enabling
-- any part of this.
local function log_available_food_items(player)
    local utility = get_pal_item_utility()
    if not utility then
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] could not resolve PalItemUtility CDO — skipping food inventory dump")
        return
    end

    -- Keep running the hundred-and-seventh-pass array call too — it
    -- still proves entries exist even though we can't read their
    -- fields, and costs nothing extra to keep logging for comparison.
    local outItemInfos = {}
    local ok, err = pcall(function()
        utility:CollectLocalPlayerControllableItemInfos_ByTypeB(
            player, FOOD_ITEM_TYPE_B_VALUES, outItemInfos, 0 -- EPalItemInfoCollectType.InventoryOnly = 0
        )
    end)
    if ok then
        log_food_result("out-param table after call", outItemInfos)
    else
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] CollectLocalPlayerControllableItemInfos_ByTypeB call FAILED: " .. tostring(err))
    end

    -- New this pass: the simpler, named-item count check.
    for _, itemId in ipairs(FOOD_CANDIDATE_ITEM_IDS) do
        local okCount, countOrErr = pcall(function()
            return utility:CountLocalPlayerInventoryItemNum64(player, itemId)
        end)
        if okCount then
            Logger.log(string.format(
                "[PalBonds/Interaction] [FOOD-DIAG] CountLocalPlayerInventoryItemNum64(\"%s\") = %s",
                itemId, tostring(countOrErr)
            ))
        else
            Logger.log(string.format(
                "[PalBonds/Interaction] [FOOD-DIAG] CountLocalPlayerInventoryItemNum64(\"%s\") FAILED: %s",
                itemId, tostring(countOrErr)
            ))
        end
    end
end

-- ---------------------------------------------------------------------
-- Twelfth-pass additions: "calm down" attempt + diagnostic property dump.
-- See file header for the full reasoning. Both are best-effort/read-only
-- respectively, and both are wrapped in pcall at every native call.
-- ---------------------------------------------------------------------

local INTERESTING_KEYWORDS = {
    "warning", "alert", "escape", "flee", "run", "curious", "timid",
    "skittish", "personality", "temper", "nature", "disposition",
    "caution", "notice", "aware", "hate", "target", "mood",
}

local function name_looks_interesting(name)
    local lower = name:lower()
    for _, kw in ipairs(INTERESTING_KEYWORDS) do
        if lower:find(kw, 1, true) then
            return true
        end
    end
    return false
end

-- Read-only. Walks Class:ForEachProperty() up the GetSuperStruct() chain
-- (same technique ConsoleCommandsMod/dump_object.lua uses), which
-- surfaces Blueprint-ADDED variables too — not just what's in the static
-- Pal.hpp SDK dump. Filtered to names that look relevant to AI mood/
-- reaction-to-player so the log doesn't get flooded with the hundreds of
-- unrelated properties every Actor/Pawn/Character has. Only scalar types
-- (bool/byte/int/float/name/enum) have their VALUE read; anything else
-- just logs its name+type so we at least know it exists.
local function dump_interesting_properties(obj, label)
    local ok, err = pcall(function()
        if obj == nil or not obj:IsValid() then
            return
        end
        local class = obj:GetClass()
        local seen = {}
        while class ~= nil and class:IsValid() do
            class:ForEachProperty(function(prop)
                local propOk, propName = pcall(function() return prop:GetFName():ToString() end)
                if propOk and propName and not seen[propName] and name_looks_interesting(propName) then
                    seen[propName] = true
                    local typeOk, typeName = pcall(function() return prop:GetClass():GetFName():ToString() end)
                    local valueStr = "(not read — non-scalar type)"
                    if typeOk then
                        local readOk, value = pcall(function()
                            if typeName == "BoolProperty" or typeName == "ByteProperty"
                                or typeName == "IntProperty" or typeName == "FloatProperty" then
                                return obj[propName]
                            elseif typeName == "NameProperty" then
                                local v = obj[propName]
                                return v and v:ToString()
                            elseif typeName == "EnumProperty" then
                                local v = obj[propName]
                                local enumOk, enumName = pcall(function()
                                    return prop:GetEnum():GetNameByValue(v):ToString()
                                end)
                                if enumOk then
                                    return string.format("%s(%s)", enumName, tostring(v))
                                end
                                return v
                            end
                            return nil
                        end)
                        if readOk and value ~= nil then
                            valueStr = tostring(value)
                        end
                    end
                    Logger.log(string.format(
                        "[PalBonds/Interaction] [DIAG] %s.%s (%s) = %s",
                        label, propName, tostring(typeName), valueStr
                    ))
                end
            end)
            class = safe_call(function() return class:GetSuperStruct() end)
        end
    end)
    if not ok then
        Logger.log("[PalBonds/Interaction] [DIAG] property scan failed (non-fatal, caught): " .. tostring(err))
    end
end

-- Best-effort attempt to stop the target from treating the player as
-- something to react to (flee from / fight) right after a successful
-- interaction. Uses REAL fields confirmed in Pal.hpp on APalAIController:
-- TargetPlayers / TargetNPCs (TArray<AActor*>, direct field access — same
-- safe pattern as SaveParameter, not a value-returning function call) and
-- HateSystem:ChangeHate(Attacker, PlusHateValue) (plain void function,
-- simple pointer+float params). NOT confirmed to be the actual
-- flee/curious "disposition" switch DESIGN.md's Q1 asks about — that's
-- still open, see dump_interesting_properties above. Treat this as an
-- experiment to test live, not a proven fix.
local function try_calm_target(pal, player)
    local ok, err = pcall(function()
        local controller = pal.Controller
        if controller == nil or not controller:IsValid() then
            Logger.log("[PalBonds/Interaction] calm-down: target has no valid Controller, skipping")
            return
        end

        local targetPlayers = controller.TargetPlayers
        if targetPlayers ~= nil then
            local okNum, n = pcall(function() return targetPlayers:GetArrayNum() end)
            if okNum and n and n > 0 then
                local okClear = pcall(function() targetPlayers:Clear() end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] calm-down: TargetPlayers had %d entr%s, Clear() %s",
                    n, (n == 1) and "y" or "ies", okClear and "succeeded" or "FAILED (method may not exist on this TArray wrapper)"
                ))
            end
        end

        local targetNPCs = controller.TargetNPCs
        if targetNPCs ~= nil then
            local okNum, n = pcall(function() return targetNPCs:GetArrayNum() end)
            if okNum and n and n > 0 then
                local okClear = pcall(function() targetNPCs:Clear() end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] calm-down: TargetNPCs had %d entr%s, Clear() %s",
                    n, (n == 1) and "y" or "ies", okClear and "succeeded" or "FAILED (method may not exist on this TArray wrapper)"
                ))
            end
        end

        local hate = controller.HateSystem
        if hate ~= nil and hate:IsValid() and player ~= nil then
            local okHate = pcall(function() hate:ChangeHate(player, -999999.0) end)
            Logger.log("[PalBonds/Interaction] calm-down: HateSystem:ChangeHate toward player " .. (okHate and "called" or "FAILED"))
        end
    end)
    if not ok then
        Logger.log("[PalBonds/Interaction] calm-down attempt failed (non-fatal, caught): " .. tostring(err))
    end
end

-- Shared body for both F9 (pet) and F10 (feed) — twelfth pass folds what
-- used to be a single do_pet() into this, parameterized on the PLAYER's
-- own "reach out" action type and a label for the log. Targeting, both
-- busy-gates, the target's Happy reaction (and the friendship grant that
-- comes from it), the calm-down attempt, and the diagnostic dump are all
-- identical between pet and feed.
local function do_interaction(playerActionType, actionLabel, keyName)
    Logger.log(string.format("[PalBonds/Interaction] %s pressed — starting %s", keyName, actionLabel))

    local player = FindFirstOf("PalPlayerCharacter")
    if not player or not player:IsValid() then
        Logger.log("[PalBonds/Interaction] no local PalPlayerCharacter found — are you in-world?")
        return
    end

    -- Gate on the PLAYER's own action state FIRST, before anything else.
    -- This is what makes F9/F10 non-spammable: a second press while the
    -- reach-out/reaction animations are still playing is just ignored.
    local playerActionComp = player.ActionComponent
    if playerActionComp and playerActionComp:IsValid() then
        local playerIdle = safe_call(function() return playerActionComp:ActionIsEmpty() end)
        if playerIdle == false then
            Logger.log("[PalBonds/Interaction] player is already mid-action — ignoring press")
            return
        end
    end

    -- Prefer the actual camera's location for the look-origin (over-the-
    -- shoulder cameras are offset from the character root); fall back to
    -- the player actor's own location if that component isn't reachable.
    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
    if not originLoc then
        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
    end
    if not originLoc then
        Logger.log("[PalBonds/Interaction] could not read player/camera location")
        return
    end

    local controlRot = safe_call(function() return player:GetControlRotation() end)
    if not controlRot then
        Logger.log("[PalBonds/Interaction] could not read player control rotation")
        return
    end
    local forward = rotator_to_forward(controlRot)

    local pal, dist, angle = find_targeted_pal(originLoc, forward, player)
    if not pal then
        Logger.log(string.format(
            "[PalBonds/Interaction] not looking at any Pal (need within %.0f units and %.0f degrees of center)",
            PET_RANGE, PET_MAX_ANGLE_DEG
        ))
        return
    end

    -- Fifteenth pass: a Pal that already lost all its bonded trust
    -- (Capture.OnTrustLost — damage or distance, see Trust.lua) is done.
    -- Refuse the whole interaction rather than let it quietly re-earn
    -- trust as if nothing happened.
    if Capture.HasPermanentlyFled(pal) then
        Logger.log("[PalBonds/Interaction] this Pal already lost all its trust and fled permanently — refusing interaction")
        return
    end

    -- Gate on the TARGET's action state too, and do it BEFORE granting
    -- anything at all — matches vanilla: a busy/sleeping Pal skips the
    -- whole interaction, not just the reaction clip.
    local actionComp = pal.ActionComponent
    local targetIdle = nil
    if actionComp and actionComp:IsValid() then
        targetIdle = safe_call(function() return actionComp:ActionIsEmpty() end)
    end
    if targetIdle ~= true then
        Logger.log("[PalBonds/Interaction] target is busy or its action state couldn't be read — skipping entire interaction (matches vanilla: can't pet/feed a busy/sleeping Pal)")
        return
    end

    local param = get_individual_parameter(pal)
    if not param or not param:IsValid() then
        Logger.log("[PalBonds/Interaction] targeted Pal has no IndividualParameter — can't read/modify friendship")
        return
    end

    local speciesId = safe_call(function() return param:GetCharacterID() end)
    local speciesName = safe_call(function() return speciesId and speciesId:ToString() end)
    local actorName = safe_call(function() return pal:GetFullName() end)
    local before = safe_call(function() return param:GetFriendshipPoint() end)
    -- NOTE: deliberately NOT calling param:GetSaveParameter() here. That
    -- function returns the ENTIRE FPalIndividualCharacterSaveParameter
    -- struct BY VALUE (0x370 = 880 bytes, embeds dynamic arrays/strings).
    -- Copying a struct like that across the Lua/native boundary was the
    -- actual cause of all three crashes this project had (see
    -- hook-points.md, "Crash #3 root cause"). `SaveParameter` is a plain
    -- field directly on `param` itself.
    local ownerId = safe_call(function()
        return param.SaveParameter and param.SaveParameter.OwnerPlayerUId
    end)

    Logger.log(string.format(
        "[PalBonds/Interaction] targeted %s (species=%s) at %.0f units (%.1f deg off-center), owner GUID: %s, Friendship=%s",
        tostring(actorName), tostring(speciesName), dist, angle, tostring(ownerId), tostring(before)
    ))

    -- Player's own "reach out" gesture. Self-directed on the PLAYER's own
    -- ActionComponent, targeting the Pal.
    if playerActionComp and playerActionComp:IsValid() then
        Logger.log(string.format("[PalBonds/Interaction] player reaching out: PlayActionByType(pal, %s=%d) NOW", actionLabel, playerActionType))
        local pOk, pErr = safe_call(function()
            playerActionComp:PlayActionByType(pal, playerActionType)
        end)
        Logger.log(string.format("[PalBonds/Interaction] player %s call returned — result=%s", actionLabel, tostring(pErr or "ok")))
    end

    -- NOTE: deliberately NOT calling param:AddFriendShip() here. See
    -- eleventh-pass notes in the file header — Happy's own internal logic
    -- already fires exactly one real AddFriendShip(10, true) as a side
    -- effect, and that's the correct, vanilla-accurate amount.

    -- Target's own reaction. THIS is what actually grants friendship now
    -- (via Happy's own internal side effect), not an explicit call.
    --
    -- BUG FOUND (2026-09-01, thirteenth pass): this used to go through
    -- safe_call(), which on SUCCESS returns the wrapped function's own
    -- return value as its first result — and PlayActionByType's call site
    -- here returns nothing, so `okAction` was always nil (falsy) whether
    -- the call succeeded or failed. That silently skipped try_calm_target()
    -- and dump_interesting_properties() on every single interaction this
    -- whole pass, which is exactly why a full test session (skittish Pal,
    -- Chikipi, Cattiva) showed zero "calm-down:"/"[DIAG]" log lines at
    -- all — not the game ignoring the attempt, our own code never
    -- attempting it. Fixed by calling pcall() directly here so `actionOk`
    -- is pcall's own real success boolean, not a re-wrapped return value.
    Logger.log(string.format("[PalBonds/Interaction] target reacting: PlayActionByType(pal, Happy=%d) NOW", ACTION_TYPE_HAPPY))
    local actionOk, actionErr = pcall(function()
        actionComp:PlayActionByType(pal, ACTION_TYPE_HAPPY)
    end)
    Logger.log(string.format("[PalBonds/Interaction] target Happy call returned — result=%s (the [WATCH] hook will log the real friendship grant a couple seconds from now)", actionOk and "ok" or tostring(actionErr)))

    if actionOk then
        try_calm_target(pal, player)
        dump_interesting_properties(pal, tostring(actorName))
        local controller = safe_call(function() return pal.Controller end)
        if controller then
            dump_interesting_properties(controller, tostring(actorName) .. ".Controller")
        end
    end

    if Interaction.OnWildPalPetted then
        Interaction.OnWildPalPetted(pal)
    end
end

local function do_pet()
    do_interaction(ACTION_TYPE_HUMAN_PETTING, "HumanPetting", PET_KEY)
end

-- Hundred-and-thirty-eighth pass (2026-09-04): Play — item 1 on the
-- saved priority TODO list, a third bonding interaction alongside
-- Pet/Feed. Dragón's own framing: a real player emote (Dance/Beckon)
-- played together with a random Pal idle animation. Split by explicit
-- decision (see hook-points.md/CLAUDE.md, same-day continuation) into
-- two halves: this ships ONLY the Pal-idle half now, using
-- PlayActionByType(pal, PalRandomRest) — the exact same safe call shape
-- as Happy above, just a different EPalActionType value, zero new risk.
-- The player-emote half goes through a DIFFERENT, unproven mechanism
-- (ActionComponent:PlayAction(ActionTarget, actionClass), confirmed real
-- in Pal.hpp as a sibling overload of PlayActionByType — see the new
-- [EMOTE-DIAG] read-only class scan in Interaction.Init()) and is
-- deliberately deferred to its own future pass rather than guessed at
-- here, given this project's crash history with unproven native calls.
--
-- Trust: Dragón asked for Play to grant trust, same amount as Pet/Feed.
-- Unlike do_interaction(), PalRandomRest has no Happy-style automatic
-- friendship side effect to piggyback on, so this calls
-- param:AddFriendShip() directly — the same call already used
-- explicitly elsewhere in this project (Trust.lua), just not previously
-- needed in this file. Exactly ONE call fires per press, so this can't
-- reintroduce the eleventh-pass double-grant bug (that was specifically
-- about TWO calls firing for the same press).
local function do_play()
    Logger.log(string.format("[PalBonds/Interaction] %s pressed — starting Play", PLAY_KEY))

    local player = FindFirstOf("PalPlayerCharacter")
    if not player or not player:IsValid() then
        Logger.log("[PalBonds/Interaction] no local PalPlayerCharacter found — are you in-world?")
        return
    end

    local playerActionComp = player.ActionComponent
    if playerActionComp and playerActionComp:IsValid() then
        local playerIdle = safe_call(function() return playerActionComp:ActionIsEmpty() end)
        if playerIdle == false then
            Logger.log("[PalBonds/Interaction] player is already mid-action — ignoring Play press")
            return
        end
    end

    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
    if not originLoc then
        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
    end
    if not originLoc then
        Logger.log("[PalBonds/Interaction] could not read player/camera location")
        return
    end

    local controlRot = safe_call(function() return player:GetControlRotation() end)
    if not controlRot then
        Logger.log("[PalBonds/Interaction] could not read player control rotation")
        return
    end
    local forward = rotator_to_forward(controlRot)

    local pal, dist, angle = find_targeted_pal(originLoc, forward, player)
    if not pal then
        Logger.log(string.format(
            "[PalBonds/Interaction] not looking at any Pal (need within %.0f units and %.0f degrees of center)",
            PET_RANGE, PET_MAX_ANGLE_DEG
        ))
        return
    end

    if Capture.HasPermanentlyFled(pal) then
        Logger.log("[PalBonds/Interaction] this Pal already lost all its trust and fled permanently — refusing Play")
        return
    end

    local actionComp = pal.ActionComponent
    local targetIdle = nil
    if actionComp and actionComp:IsValid() then
        targetIdle = safe_call(function() return actionComp:ActionIsEmpty() end)
    end
    if targetIdle ~= true then
        Logger.log("[PalBonds/Interaction] target is busy or its action state couldn't be read — skipping Play")
        return
    end

    local param = get_individual_parameter(pal)
    if not param or not param:IsValid() then
        Logger.log("[PalBonds/Interaction] targeted Pal has no IndividualParameter — can't grant trust")
        return
    end

    local actorName = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format(
        "[PalBonds/Interaction] Play targeting %s at %.0f units (%.1f deg off-center)",
        tostring(actorName), dist, angle
    ))

    -- Hundred-and-forty-first pass (2026-09-04): Dragón reported the
    -- Pal-idle animation sometimes looking like the Feed gesture and
    -- asked whether PalRandomRest rolls among only idle animations or
    -- among all of the Pal's animations. Real evidence, not a guess:
    -- APalCharacter has a plain field, StaticCharacterParameterComponent
    -- (confirmed in Pal.hpp, same safe direct-field-read pattern as
    -- ActionComponent/CharacterParameterComponent above), which carries
    -- `RandomRestMontageInfos` (TArray<FPalRandomRestInfo> — each entry a
    -- plain struct: RandomRestMontage, Weight, LoopNum_Min/Max,
    -- AfterIdleTime). This IS a curated, per-species "rest" pool by
    -- design, not "every animation the Pal has" — logging it here proves
    -- (or disproves) whether this specific Pal's authored pool already
    -- includes something that looks feeding-like (plausible for
    -- herbivore-type Pals with a grazing/foraging idle pose), rather
    -- than assuming either way. Per the hundred-and-fortieth pass's fresh
    -- crash lesson, this NEVER calls a method on the RandomRestMontage
    -- asset reference — only tostring() on it, same as the fix above.
    -- Hundred-and-forty-second pass (2026-09-04) FIX: the previous
    -- version guessed `restInfos:Get(idx)` to pull elements out of this
    -- native TArray field — wrong method name, so every entry silently
    -- came back nil (safe_call swallowed the error) and not a single
    -- [REST-POOL-DIAG] entry line ever printed, only the top-level count.
    -- This project already has a PROVEN pattern for iterating a native
    -- TArray field, used successfully in Indicator.lua's own property
    -- dumper: `:ForEach(function(index, elem) ... end)`, with each
    -- element needing `:get()` to unwrap before reading its fields.
    -- Reused verbatim instead of guessing a second time.
    local staticParam = safe_call(function() return pal.StaticCharacterParameterComponent end)
    if staticParam and staticParam:IsValid() then
        local restInfos = safe_call(function() return staticParam.RandomRestMontageInfos end)
        local restCount = safe_call(function() return restInfos and restInfos:GetArrayNum() end)
        Logger.log(string.format("[PalBonds/Interaction] [REST-POOL-DIAG] %s: RandomRestMontageInfos has %s real entr%s", tostring(actorName), tostring(restCount), (restCount == 1) and "y" or "ies"))
        if restInfos and restCount and restCount > 0 then
            pcall(function()
                restInfos:ForEach(function(index, elemParam)
                    local eOk, entry = pcall(function() return elemParam:get() end)
                    if eOk and entry then
                        local montage = safe_call(function() return entry.RandomRestMontage end)
                        local weight = safe_call(function() return entry.Weight end)
                        Logger.log(string.format("[PalBonds/Interaction] [REST-POOL-DIAG] entry[%s]: RandomRestMontage=%s Weight=%s", tostring(index), tostring(montage), tostring(weight)))
                    else
                        Logger.log(string.format("[PalBonds/Interaction] [REST-POOL-DIAG] entry[%s]: could not unwrap (:get() failed)", tostring(index)))
                    end
                end)
            end)
        end
    else
        Logger.log(string.format("[PalBonds/Interaction] [REST-POOL-DIAG] %s: no valid StaticCharacterParameterComponent — could not read its rest pool", tostring(actorName)))
    end

    -- Hundred-and-forty-fifth pass (2026-09-04) REMOVED: the player-Cheer
    -- attempt (PlayAction + :GetClass() on a CDO) that lived here across
    -- the hundred-and-forty-first through hundred-and-forty-fourth
    -- passes. Dragón's real test showed do_play() was dying silently
    -- right after this point every single time — no idle animation, no
    -- Happy follow-up, nothing — meaning something in this block was
    -- throwing an uncaught error that killed the rest of the function
    -- (swallowed by the outer safe_call(do_play) in the keybind handler,
    -- which explains why nothing crashed but Play also did nothing at
    -- all). The leading suspect: `:GetClass()` on a CDO obtained via
    -- StaticFindObject is likely a second instance of the same danger
    -- class as the fortieth pass's real crash (a method call on an
    -- object gotten through an unusual channel, not proven safe just
    -- because a DIFFERENT method — GetClass() — works fine on ordinary
    -- live actors elsewhere in this file). Rather than keep pushing on
    -- an increasingly risky mechanism that was actively breaking the
    -- two things that DO work, pulled it out entirely. The player-emote
    -- half goes back to being deferred to its own separate, later
    -- investigation (matching the original hundred-and-thirty-eighth
    -- pass decision, before this thread's real dump made it look closer
    -- than it turned out to be) — the read-only [EMOTE-DIAG] scan and
    -- the [EMOTE-WATCH] live hooks in Interaction.Init() are left
    -- running (harmless, read-only/hook-registration only) for whenever
    -- that research resumes.
    Logger.log(string.format("[PalBonds/Interaction] target playing: PlayActionByType(pal, PalRandomRest=%d) NOW", ACTION_TYPE_PAL_RANDOM_REST))
    local actionOk, actionErr = pcall(function()
        actionComp:PlayActionByType(pal, ACTION_TYPE_PAL_RANDOM_REST)
    end)
    Logger.log(string.format("[PalBonds/Interaction] target PalRandomRest call returned — result=%s", actionOk and "ok" or tostring(actionErr)))

    -- Hundred-and-forty-third pass (2026-09-04): Dragón's request — some
    -- idle poses don't read as visibly "happy," so sequence the real
    -- Happy reaction right after the idle animation, purely for its
    -- hearts VFX (confirmed baked into BP_ActionHappy's own graph, not
    -- separable — see hook-points.md). PalRandomRest and Happy are
    -- mutually exclusive on the same ActionComponent, so this can't be
    -- simultaneous — first timed-sequencing attempt in this project,
    -- approximated with a fixed delay (PLAY_HAPPY_FOLLOWUP_DELAY_MS; no
    -- proven way yet to read back which specific montage/duration
    -- PalRandomRest actually picked). Trust now comes ENTIRELY from
    -- Happy's own automatic side effect (same mechanism Pet/Feed already
    -- rely on) — the explicit AddFriendShip() call this function used to
    -- make was removed, since keeping it would double-grant once Happy
    -- also fires its own real AddFriendShip (the exact eleventh-pass bug
    -- this project already fixed once). Re-validates pal/actionComp with
    -- :IsValid() before touching them again after the delay, since a
    -- live actor held across a multi-second timer is a genuinely new
    -- category for this project (a wild Pal could in principle despawn
    -- or die in that window) — every other delayed callback in this file
    -- only re-checks CLASSES, never holds a live actor reference.
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(PLAY_HAPPY_FOLLOWUP_DELAY_MS, function()
            safe_call(function()
                local palStillValid = pal ~= nil and pal:IsValid()
                local actionCompStillValid = actionComp ~= nil and actionComp:IsValid()
                if not (palStillValid and actionCompStillValid) then
                    Logger.log("[PalBonds/Interaction] Play: target no longer valid when Happy follow-up was due — skipping")
                    return
                end
                -- Hundred-and-forty-fourth pass (2026-09-04) FIX: Dragón's
                -- real test showed the busy-gate check above meant Happy
                -- never fired at all — some species' random-rest montages
                -- run 20+ real seconds (well past the 3s follow-up delay),
                -- so `ActionIsEmpty()` was still false every single time
                -- and this always hit the "skipping" branch. Dragón's own
                -- fix, exactly as asked: after the delay, cut the idle
                -- animation short and force Happy regardless of busy
                -- state, so the trust grant/hearts are never silently
                -- lost to a long-running idle.
                --
                -- Hundred-and-forty-sixth pass (2026-09-04) FIX: just
                -- calling PlayActionByType(Happy) without a real cancel
                -- first didn't actually interrupt anything — confirmed in
                -- the log: the call returned "ok" every time (no Lua
                -- error), but ZERO real AddFriendShip fires happened
                -- anywhere in that whole test session, meaning the engine
                -- silently no-op's a new PlayActionByType call while the
                -- target is still mid-action, rather than auto-
                -- interrupting it — matching Dragón's own direct report
                -- (no visible cut, no hearts). The busy-gate elsewhere in
                -- this file isn't just cosmetic politeness, it reflects a
                -- real engine-level restriction. Found the actual fix in
                -- Pal.hpp: `CancelActionByType(EPalActionType Type)`,
                -- right next to PlayActionByType/PlayAction on the same
                -- ActionComponent, same simple enum-parameter shape
                -- already proven safe everywhere in this file — cancel
                -- the idle animation for real before starting Happy.
                Logger.log(string.format("[PalBonds/Interaction] Play: cancelling PalRandomRest=%d on target NOW", ACTION_TYPE_PAL_RANDOM_REST))
                local cancelOk, cancelErr = pcall(function()
                    actionComp:CancelActionByType(ACTION_TYPE_PAL_RANDOM_REST)
                end)
                Logger.log(string.format("[PalBonds/Interaction] Play: CancelActionByType call returned — result=%s", cancelOk and "ok" or tostring(cancelErr)))

                Logger.log("[PalBonds/Interaction] Play: target playing Happy follow-up (hearts) NOW")
                local happyOk, happyErr = pcall(function()
                    actionComp:PlayActionByType(pal, ACTION_TYPE_HAPPY)
                end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] Play: Happy follow-up call returned — result=%s (the [WATCH] AddFriendShip hook will log the real grant a couple seconds from now)",
                    happyOk and "ok" or tostring(happyErr)
                ))
                if Interaction.OnWildPalPetted then
                    Interaction.OnWildPalPetted(pal)
                end
            end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Interaction] Play: could not schedule the Happy follow-up (ExecuteInGameThreadWithDelay failed) — granting trust immediately as a fallback so the interaction isn't silently lost")
        local grantOk, grantErr = pcall(function()
            param:AddFriendShip(INTERACTION_FRIENDSHIP_GAIN, true)
        end)
        Logger.log(string.format("[PalBonds/Interaction] Play fallback AddFriendShip(%d, true) call returned — result=%s", INTERACTION_FRIENDSHIP_GAIN, grantOk and "ok" or tostring(grantErr)))
        if Interaction.OnWildPalPetted then
            Interaction.OnWildPalPetted(pal)
        end
    end
end

local function do_feed()
    do_interaction(ACTION_TYPE_HUMAN_FEEDING, "HumanFeeding", FEED_KEY)
    -- HUNDRED-AND-TWELFTH PASS (2026-09-03): REMOVED — real game crash.
    -- The hundred-and-fifth-through-hundred-and-eleventh passes' call
    -- into log_available_food_items() (specifically the hundred-and-
    -- eleventh pass's new CountLocalPlayerInventoryItemNum64 loop, most
    -- likely — though the CollectLocalPlayerControllableItemInfos_ByTypeB
    -- call before it is not cleared either) caused a REAL, hard game
    -- crash (EXCEPTION_ACCESS_VIOLATION reading address 0x70 — a
    -- near-null pointer dereference inside native code) on Dragón's very
    -- next live feed, reproduced twice. This is a fundamentally
    -- different, more dangerous category of bug than anything else
    -- found in this project: pcall/safe_call can only catch Lua-level
    -- errors — a hard access violation inside a native function call
    -- crashes the whole game process regardless of how the Lua call site
    -- is wrapped. Every earlier "unconfirmed guess" in this file (the
    -- Worker Menu's OnClose:Bind, the various field reads) was safe to
    -- try live because a wrong guess just produced a catchable Lua
    -- error; this one was not, and should never have been shipped for a
    -- live test without a much higher bar of confidence given it's a
    -- native BlueprintFunctionLibrary call with FName-typed parameters
    -- (a type this project had not previously passed FROM Lua INTO a
    -- native call by constructing it from a plain string — every prior
    -- FName use in this file has been READING one off an existing live
    -- object, never constructing one to pass as an argument).
    --
    -- Disconnected entirely from the live hot path. log_available_food_
    -- items() and its two calls (the array-of-structs read and the new
    -- named-item count loop) are left defined below for reference/future
    -- investigation, but MUST NOT be called again without first
    -- confirming — via something safer than a live game session, if at
    -- all possible — that passing a Lua string as an FName argument to a
    -- native UFunction is actually safe in this UE4SS build. See
    -- DESIGN.md's "Crash #4" writeup and hook-points.md's hundred-and-
    -- twelfth pass for the full incident report.
end

-- THIRTY-EIGHTH PASS (2026-09-02): F11, the direct-capture experiment.
-- Reuses the same look-based targeting as pet/feed (find_targeted_pal)
-- but does NOT reuse do_interaction() — no busy-gating, no Happy
-- reaction, no friendship math. Just: find what you're looking at, hand
-- it to Capture.TryDirectCapture, done. See Capture.lua for the actual
-- risky call and its full reasoning.
local function do_test_capture()
    Logger.log("[PalBonds/Interaction] CTRL+K pressed — starting Capture.TryDirectCapture experiment")

    local player = FindFirstOf("PalPlayerCharacter")
    if not player or not player:IsValid() then
        Logger.log("[PalBonds/Interaction] no local PalPlayerCharacter found — are you in-world?")
        return
    end

    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
    if not originLoc then
        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
    end
    if not originLoc then
        Logger.log("[PalBonds/Interaction] could not read player/camera location")
        return
    end

    local controlRot = safe_call(function() return player:GetControlRotation() end)
    if not controlRot then
        Logger.log("[PalBonds/Interaction] could not read player control rotation")
        return
    end
    local forward = rotator_to_forward(controlRot)

    local pal = find_targeted_pal(originLoc, forward, player)
    if not pal then
        Logger.log(string.format(
            "[PalBonds/Interaction] %s: not looking at any Pal (need within %.0f units and %.0f degrees of center)",
            "CTRL+K", PET_RANGE, PET_MAX_ANGLE_DEG
        ))
        return
    end

    Capture.TryDirectCapture(pal, player)
end

-- Hundred-and-fifty-ninth pass (2026-09-04): direct SelectedFeedingItem
-- call experiment — CTRL+H, a brand-new isolated test key. IMPORTANT:
-- this is NOT the same dead end the "RETIRED" note below describes.
-- That note is about `RequestUseToCharacter` (called ON an item slot,
-- confirmed gated to the player's own active Otomo only) combined with
-- Ghidra's finding that the OTOMO menu's real eligibility check is an
-- unreachable raw vtable call. `SelectedFeedingItem` is a DIFFERENT
-- real function — the WORKER-menu path's own consumption call
-- (confirmed live, hundred-and-fifth/sixth passes: fires cleanly for
-- real base-worker Pals, never for an active Otomo) — and Ghidra found
-- NO ownership check anywhere inside its own body (hundred-and-
-- thirty-fourth pass). This calls it DIRECTLY on whatever Pal is
-- targeted, skipping the Worker Menu's own WorkAssignId eligibility
-- gate entirely (that gate lives in the UI that decides which menu to
-- open, not in this function) — genuinely untried territory, not a
-- retry of something already ruled out.
--
-- The one new risk: FPalItemSlotId isn't a field that exists ready-made
-- anywhere on a live object — UPalItemSlot stores ContainerId and
-- SlotIndex as two SEPARATE fields (confirmed hundred-and-thirteenth
-- pass) — so the struct has to be built fresh as a plain Lua table.
-- Per real, confirmed UE4SS documentation (checked this pass, not
-- guessed — RE-UE4SS's own docs/examples), struct arguments convert
-- automatically from plain Lua tables, including NESTED structs (their
-- own example: a Transform table with nested Rotation/Translation/
-- Scale3D sub-tables) — the same shape complexity as FPalItemSlotId
-- {ContainerId: {ID: FGuid}, SlotIndex}. This is a fundamentally
-- different, safer category than Crash #4: that crash built an FName
-- (an interned string-table lookup), not plain data. To keep the risk
-- as low as possible anyway, ContainerId below is the REAL live struct
-- value read straight off the found slot — never decomposed into raw
-- GUID ints and rebuilt — only the outer FPalItemSlotId wrapper table
-- is actually new, since nothing already holds one pre-combined.
local TEST_SELECTED_FEEDING_KEY = Key.H
local TEST_SELECTED_FEEDING_MODIFIERS = {ModifierKey.CONTROL}
local TEST_FOOD_ITEM_STATIC_ID = "Berries" -- same confirmed-real item name already proven end-to-end for CTRL+J (hundred-and-seventeenth/eighteenth passes)

-- Same proven technique as the old CTRL+J test (hundred-and-seventeenth
-- pass): scan every live PalItemSlot in the world and pick the ONE
-- matching candidate with the highest StackCount — confirmed live to
-- reliably pick the player's own real stash over small amounts other
-- nearby Pals happen to be carrying.
local function find_best_food_slot(itemStaticId)
    local best, bestCount = nil, -1
    local slots = FindAllOf("PalItemSlot")
    if not slots then return nil, nil end
    for _, slot in ipairs(slots) do
        safe_call(function()
            if not slot or not slot:IsValid() then return end
            local sidObj = slot.ItemId and slot.ItemId.StaticId
            local sidStr = sidObj and sidObj:ToString()
            if sidStr ~= itemStaticId then return end
            local count = slot.StackCount
            if count and count > bestCount then
                bestCount = count
                best = slot
            end
        end)
    end
    return best, bestCount
end

local function do_test_selected_feeding_item()
    Logger.log("[PalBonds/Interaction] CTRL+H pressed — starting SelectedFeedingItem direct-call experiment")

    local player = FindFirstOf("PalPlayerCharacter")
    if not player or not player:IsValid() then
        Logger.log("[PalBonds/Interaction] no local PalPlayerCharacter found — are you in-world?")
        return
    end

    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
    if not originLoc then
        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
    end
    if not originLoc then
        Logger.log("[PalBonds/Interaction] could not read player/camera location")
        return
    end

    local controlRot = safe_call(function() return player:GetControlRotation() end)
    if not controlRot then
        Logger.log("[PalBonds/Interaction] could not read player control rotation")
        return
    end
    local forward = rotator_to_forward(controlRot)

    local pal, dist, angle = find_targeted_pal(originLoc, forward, player)
    if not pal then
        Logger.log(string.format(
            "[PalBonds/Interaction] [FEED-CALL-TEST] not looking at any Pal (need within %.0f units and %.0f degrees of center)",
            PET_RANGE, PET_MAX_ANGLE_DEG
        ))
        return
    end

    local actorName = safe_call(function() return pal:GetFullName() end)
    local ownedAlready = safe_call(function() return Capture.IsAlreadyOwned(pal) end)
    Logger.log(string.format(
        "[PalBonds/Interaction] [FEED-CALL-TEST] targeting %s at %.0f units (%.1f deg off-center) — already owned=%s",
        tostring(actorName), dist, angle, tostring(ownedAlready)
    ))

    local slot, stackCount = find_best_food_slot(TEST_FOOD_ITEM_STATIC_ID)
    if not slot then
        Logger.log(string.format("[PalBonds/Interaction] [FEED-CALL-TEST] no live PalItemSlot found holding \"%s\" — do you have any in your inventory?", TEST_FOOD_ITEM_STATIC_ID))
        return
    end

    local containerId = safe_call(function() return slot.ContainerId end)
    local slotIndex = safe_call(function() return slot.SlotIndex end)
    if containerId == nil or slotIndex == nil then
        Logger.log("[PalBonds/Interaction] [FEED-CALL-TEST] could not read ContainerId/SlotIndex off the found slot — aborting")
        return
    end

    Logger.log(string.format(
        "[PalBonds/Interaction] [FEED-CALL-TEST] found slot: SlotIndex=%s StackCount=%s (before)",
        tostring(slotIndex), tostring(stackCount)
    ))

    local itemSlotId = {ContainerId = containerId, SlotIndex = slotIndex}

    -- Hundred-and-sixtieth pass (2026-09-04) — DISABLED, CONFIRMED REAL
    -- CRASH. Dragón's very first live test never printed the line below
    -- this comment — the unconditional post-call log that a `pcall` can
    -- never skip on any normal return, Lua error included. A real crash
    -- dump appeared in ue4ss/ at the exact same second
    -- (`crash_2026_09_04_23_01_39.1693134.dmp`), and after this call
    -- fired, this session's own log shows ZERO further key-press lines
    -- of ANY kind — not just CTRL+H/CTRL+J, but InputSpy's raw WASD
    -- listener too, which has nothing to do with this code path. That
    -- means this single call didn't just fail — it wedged the entire
    -- Lua/input layer for the rest of the session, worse than any prior
    -- crash in this project (Crashes #1-4 all either errored cleanly in
    -- Lua or killed the whole process outright; this one left the game
    -- LOOKING alive while nothing downstream of it could run anymore).
    --
    -- Likely cause: unlike every other native call this project has
    -- ever made, `SelectedFeedingItem` was only ever observed firing as
    -- part of an already-established internal call sequence (the real
    -- Worker Menu's own UI flow sets something up first — see the
    -- hundred-and-fourteenth pass's confirmed real Blueprint graph for
    -- the sibling Otomo path). Calling it cold, with no such context
    -- ever established, most plausibly dereferenced something the real
    -- flow always guarantees is already valid — and it may also be a
    -- LATENT function (one that doesn't complete synchronously, instead
    -- resolving later via a delegate the real UI flow listens for) —
    -- which would separately explain "never returns" even without a
    -- hard crash. Both explanations point the same direction: this
    -- function is not safe to call directly outside its real context,
    -- full stop.
    --
    -- The call itself is removed, not just commented past — this stays
    -- a confirmed-dangerous dead end for the direct-call idea, same
    -- status as `RequestUseToCharacter` (Otomo-gated) and `SelectedFeed`
    -- (vtable-gated). Everything above this comment (finding the real
    -- slot, reading its real ContainerId/SlotIndex, building the
    -- itemSlotId table) is still safe, still runs, and is left in place
    -- as proven groundwork in case a SAFER way to reach this function
    -- (e.g. actually getting the Worker Menu's own UI to open on a wild
    -- Pal first, so this fires through its real, expected call chain)
    -- is found later.
    Logger.log("[PalBonds/Interaction] [FEED-CALL-TEST] DISABLED — the direct SelectedFeedingItem() call is a confirmed real crash (see hook-points.md, hundred-and-sixtieth pass). Stopping here; itemSlotId was built successfully but nothing is called with it.")
end

-- Hundred-and-twenty-seventh pass (2026-09-03): Dragón hit a real practical
-- wall trying to test Skittish→Curious — he can't tell which wild Pals
-- actually rolled "skittish" just by watching them, because ENFORCEMENT
-- (making the rolled tier show up in real AI behavior) is still
-- unconfirmed: a Pal that looks like it's fleeing might just be doing
-- ordinary wild-AI wandering/disengaging, unrelated to our tracked tier.
-- Confirmed directly this session: he petted 5 Pals that visibly ran off
-- Hundred-and-thirty-first pass (2026-09-03): tried `holder:ActivatePalByHandle`
-- (found real/working via the "MultiPals" reference mod) on a targeted wild
-- Pal's handle via a dedicated CTRL+O key. Hundred-and-thirty-second pass
-- confirmed a clean negative result: the call ran without error every time
-- but had zero visible effect on the wild Pal — the same pattern already
-- seen with RequestUseToCharacter. Key removed (continuación 106, at
-- Dragón's request to stop letting keybinds accumulate); the finding and
-- full experiment writeup stay in hook-points.md if this lead is revisited.

-- RETIRED (hundred-and-thirty-eighth pass, 2026-09-04): the
-- hundred-and-seventeenth-through-hundred-and-nineteenth passes' CTRL+J
-- test proved `UPalItemSlot:RequestUseToCharacter` really does consume a
-- real item and feed a Pal — but ONLY when the target resolves to the
-- player's own active Otomo, never an arbitrary wild Pal's
-- FPalInstanceID (confirmed: 0/N fires against a wild BP_ChickenPal_C,
-- consistent success against the player's real Otomo). Combined with
-- Ghidra's earlier finding that the actual vanilla feeding-eligibility
-- check is an unreachable raw C++ vtable call, real food-item feeding
-- for WILD Pals is a confirmed dead end from two independent angles —
-- item 7 on the saved priority list, shelved, do not reopen without new
-- evidence. Full writeup in hook-points.md. CTRL+J itself is reused
-- below for the new Play interaction rather than left dead.

-- Small helpers for reading RegisterHook callback args, same pattern as
-- Spy.lua (params arrive wrapped and need :get(); objects are described
-- via :GetFullName() with a tostring() fallback).
local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end

local function hook_describe(obj)
    if obj == nil then return "nil" end
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and name then return name end
    return tostring(obj)
end

-- Eighty-first pass (2026-09-03): remembers whatever
-- `PalInteractComponent:StartTriggerInteract` last saw as
-- `TargetInteractiveObject` for a real ActionType=4 press (confirmed,
-- seventy-fourth/seventy-seventh passes, to mean "aiming at a specific
-- Pal's own interactable sphere" — the exact case that opens
-- WBP_WorkerRadialMenu). Read by the real (non-watch-only) selection hook
-- below to know WHICH Pal a Worker-menu Pet/Feed selection was actually
-- for. Only ever meaningful for the aimed-Pal case — the "press 4 with no
-- aim target" Player-menu path never fires StartTriggerInteract at all
-- (confirmed seventy-sixth pass), so there's no cross-contamination risk
-- between the two menu systems sharing this one variable.
local lastAimedInteractTarget = nil

-- Eighty-fifth pass (2026-09-03): brackets the short window during which
-- the no-aim WBP_PlayerRadialMenu_C is actually open, so the
-- TryGetSpawnedOtomo redirect below only ever substitutes a wild Pal
-- during that narrow window — never during the ~4/sec ambient calls the
-- eighty-fourth pass proved happen the rest of the time (indicator UI, AI,
-- whatever else reads this getter). `radialMenuWindowGeneration` guards
-- the safety-timeout auto-clear against a stale timer clearing a NEWER
-- open window if menus open/close faster than the timeout.
-- `radialMenuRedirectedThisWindow` (stale note removed hundredth pass —
-- see that pass's comment below where it's actually set for its current,
-- real meaning: "was a wild Pal genuinely substituted this window").
local radialMenuActionWindowOpen = false
local radialMenuWindowGeneration = 0
local radialMenuRedirectedThisWindow = false
-- Ninety-sixth pass: tracks the aimed Pal's name for the dedup described
-- above, reset each time a new window opens so a new "4" press always
-- re-announces even if you happen to aim at the same Pal as last time.
local lastRedirectedWildPalName = nil

-- Hundredth pass (2026-09-03) FIX: this was 1500ms, and Dragón's live test
-- proved that's too short — real decision events (OnDecidedInstructionCare/
-- Feed) kept firing 3-4 real seconds after the menu opened, well past this
-- safety-timeout, so `radialMenuActionWindowOpen` had already gone false by
-- the time the player actually clicked, silently dropping the ninety-ninth
-- pass's new wild-action wiring (the substitution itself also stops the
-- moment this flag goes false, so a late aim/decision loses the redirect
-- too). CloseMenu itself has now fired reliably in every single test this
-- project has run — it's the real signal this timeout only exists to guard
-- against NEVER firing — so it's safe to make this timeout much more
-- generous without weakening that safety net in practice. 15s covers any
-- realistic amount of time a player might spend aiming/deciding inside the
-- menu; CloseMenu still closes the window immediately the moment it fires.
local RADIAL_ACTION_WINDOW_TIMEOUT_MS = 15000

-- Ninety-ninth pass (2026-09-03): the real "wire it up" step, now that the
-- ninety-eighth pass's live test proved (1) the grey-out is gone and (2)
-- OnDecidedInstructionCare/OnDecidedInstructionFeed genuinely fire on the
-- substituted wild Pal right after a real click. Deliberately NOT trying
-- to decode arg1's exact boolean meaning (the one sample we have — Care
-- fired with arg1=false on a real, confirmed Pet click — doesn't cleanly
-- support a "true=selected" guess either way, and guessing wrong here is
-- exactly the kind of thing this project's discipline says not to do
-- without a real diagnostic). Instead: just remember WHICH named event
-- fired most recently during this window (ignore the argument entirely),
-- and act on it at CloseMenu — a single, always-real, always-once-per-
-- window event, same one already used to end the redirect window itself.
-- `radialMenuRedirectedThisWindow` (already tracked above) is reused as
-- the hard gate for "was a wild Pal actually substituted this window" —
-- this must NEVER fire for the player's own real Otomo, which already has
-- its own working vanilla Pet/Feed path; double-firing our own
-- do_pet()/do_feed() on top of that would reintroduce exactly the kind of
-- double-grant bug fixed early in this project, just for a different
-- system.
local lastDecidedInstruction = nil

-- Hundred-and-second pass (2026-09-03): Dragón reported a real, felt
-- hitch every time the radial menu opens on a wild Pal, and asked to
-- chase it rather than let it sit. `find_targeted_pal` (below, inside the
-- TryGetSpawnedOtomo redirect) calls `FindAllOf("PalCharacter")` — a
-- full scan of every loaded Pal actor — plus one `GetFullName()` and one
-- location read PER pal, every single time it runs. The redirect calls
-- it on every qualifying `TryGetSpawnedOtomo` hook fire while the menu is
-- open, which per the eighty-fourth pass is roughly 4 times a second —
-- and, since the hundredth pass extended the window to 15 real seconds,
-- that's now up to ~60 full actor scans per single "4" press, on a base
-- or in an area where a dozen-plus Pals can easily be loaded at once.
-- That's a real, plausible, and self-inflicted cost, not a guess. Cheap,
-- safe fix: cache the aimed-Pal result for a short window and only
-- re-scan after it expires — a player's aim doesn't meaningfully change
-- within 250ms, so this can't make the feature less responsive, only
-- cheaper. Only caches a REAL found Pal (a "not aiming at anything"
-- result always re-scans next call, which is fine — that's already the
-- less common, less expensive case).
local cachedRedirectWildPal = nil
local lastRedirectComputeClock = nil
local REDIRECT_RECOMPUTE_INTERVAL_S = 0.25

-- Hundred-and-twenty-third pass (2026-09-03): remembers the actual live
-- WBP_PlayerRadialMenu_C widget instance for the currently-open window —
-- the same `self_` `CanOpenPlayerActionMenu`'s hook already receives on
-- every fire, just never kept before. Needed for the new field-write
-- attempt below (see the TryGetSpawnedOtomo redirect's own comment for
-- the full reasoning): the hundred-and-twenty-second pass's live test
-- showed `OpenOtomoFeedInventory` firing identically for both the real
-- Otomo and a substituted wild Pal, while `SelectedFeed` only ever fires
-- for the real one — meaning whatever gates real item selection reads
-- something OTHER than a fresh `TryGetSpawnedOtomo()` call, most likely
-- this exact widget's own cached `SpawnedOtomo` variable (confirmed real
-- via the `RemoteAccessEverything` string dump, sixty-fifth pass).
local lastOpenMenuWidget = nil

local function openRadialMenuActionWindow(widget)
    radialMenuWindowGeneration = radialMenuWindowGeneration + 1
    local myGen = radialMenuWindowGeneration
    radialMenuActionWindowOpen = true
    radialMenuRedirectedThisWindow = false
    lastRedirectedWildPalName = nil
    lastDecidedInstruction = nil
    cachedRedirectWildPal = nil
    lastRedirectComputeClock = nil
    lastOpenMenuWidget = widget
    pcall(function()
        ExecuteInGameThreadWithDelay(RADIAL_ACTION_WINDOW_TIMEOUT_MS, function()
            if radialMenuWindowGeneration == myGen then
                radialMenuActionWindowOpen = false
            end
        end)
    end)
end

-- do_pet/do_feed are declared earlier in this same file (the F9/F10
-- shared do_interaction() body) so they're already valid upvalues here —
-- no forward declaration needed. Reusing them wholesale means this new
-- path gets do_interaction's own real-time targeting (re-aims from
-- scratch, doesn't trust anything cached from earlier in the window),
-- its busy-gate (a call while an animation is still playing just no-ops,
-- so an accidental double-fire here is harmless), and the Trust.lua
-- ownership guard already sitting at the end of that call chain
-- (Capture.IsAlreadyOwned, added after the eighty-second pass's
-- incident) — the exact three protections that make this safe to wire up
-- now where it wasn't yet in the eighty-first pass.
local function closeRadialMenuActionWindow()
    if radialMenuRedirectedThisWindow and lastDecidedInstruction then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] window closing with a substituted wild Pal and a decided instruction=" .. tostring(lastDecidedInstruction) .. " — firing the real action now")
        if lastDecidedInstruction == "care" then
            safe_call(do_pet)
        elseif lastDecidedInstruction == "feed" then
            safe_call(do_feed)
        end
    end
    radialMenuActionWindowOpen = false
    lastDecidedInstruction = nil
end

-- Hundred-and-thirty-eighth pass (2026-09-04): [EMOTE-DIAG]. Read-only,
-- one-shot at Init() — resolves each of the 9 real emote action classes
-- Dragón's own Live-View dump showed live (BP_Action_Emote_0_C through
-- _8_C, all children of BP_Action_Emote_Base_C, confirmed real earlier
-- this pass) via their class default objects, and reads the inherited
-- `EmoteAnimation` field — a plain ObjectProperty pointing at a
-- UAnimMontage, the same safe direct-field-read pattern used everywhere
-- else in this file, never a function call. Purpose: find which
-- numbered class is real Cheer (Dragón confirmed this is what he calls
-- "Beckon" in-game) so do_play() can call the real
-- PlayAction(ActionTarget, actionClass) overload (confirmed real in
-- Pal.hpp, a sibling of PlayActionByType already used everywhere in this
-- file) on the CORRECT class next pass, instead of guessing an index
-- blind. Nothing here calls PlayAction or touches a live Pal/player —
-- purely a static CDO field read, zero risk.
local EMOTE_ACTION_CLASS_PATHS = {}
for i = 0, 8 do
    EMOTE_ACTION_CLASS_PATHS[i] = string.format(
        "/Game/Pal/Blueprint/Action/Palmi/Emote/BP_Action_Emote_%d.Default__BP_Action_Emote_%d_C", i, i
    )
end

-- Hundred-and-forty-first pass (2026-09-04): CONFIRMED via Dragón's own
-- object dump (a live BP_Action_Emote_0_C instance, dumped straight from
-- the game's IndividualObjectDumps folder) — index 0 IS real Cheer:
-- EmoteAnimation = ".../AM_Player_Female_Emote_Cheer", EmoteIndex="0".
-- No more guessing needed for either diagnostic method above. Also
-- notable from that same dump: the real DynamicParameter shows
-- ActionTarget=None for a real Cheer cast — it isn't targeted at
-- anything, so do_play() below passes no target, matching real observed
-- behavior instead of guessing `pal` as the target.
--
-- PlayAction's `actionClass` parameter needs the CLASS itself
-- (TSubclassOf<UPalActionBase>), not the CDO instance the EMOTE-DIAG
-- path above resolves. First attempt used a separate bare-class path
-- (no "Default__") — that silently failed every real test (see
-- hundred-and-forty-second pass fix, do_play() below): the class is
-- now derived from the already-proven CDO via `:GetClass()` instead.

-- Dragón's direct question when this shipped: "if it had failed before
-- why not add the expected fix now?" — this project has hit the exact
-- "Blueprint class isn't loaded yet at mod Init()" problem repeatedly
-- (WBP_PlayerRadialMenu_C, the Worker Menu classes, the Indicator
-- classes — all documented above in Interaction.Init()), always fixed
-- the same way: a bounded retry over time instead of a single one-shot
-- check. Applying that same already-proven fix here rather than waiting
-- to see this fail first. Capped at 20 rounds / 100s (not the 60-round/
-- 5-minute budget used for lazily-constructed UI widgets above) — these
-- are asset CDOs, not widgets only built on first menu-open, so if they
-- don't resolve quickly they likely aren't going to.
local EMOTE_DIAG_MAX_ROUNDS = 20
local EMOTE_DIAG_RETRY_MS = 5000
local EMOTE_DIAG_RESOLVED = {}

local function run_emote_index_mapping(round)
    local allResolved = true
    for i = 0, 8 do
        if not EMOTE_DIAG_RESOLVED[i] then
            Logger.log(string.format("[PalBonds/Interaction] [CRASH-DIAG] [EMOTE-DIAG] round %d: about to StaticFindObject(%s) NOW", round, EMOTE_ACTION_CLASS_PATHS[i]))
            local cdo = safe_call(function() return StaticFindObject(EMOTE_ACTION_CLASS_PATHS[i]) end)
            Logger.log(string.format("[PalBonds/Interaction] [CRASH-DIAG] [EMOTE-DIAG] round %d: StaticFindObject(index %d) returned — still alive, result=%s", round, i, cdo and "resolved" or "nil"))
            if not cdo then
                allResolved = false
            else
                EMOTE_DIAG_RESOLVED[i] = true
                Logger.log(string.format("[PalBonds/Interaction] [CRASH-DIAG] [EMOTE-DIAG] round %d: about to read index %d's EmoteAnimation field NOW", round, i))
                local anim = safe_call(function() return cdo.EmoteAnimation end)
                Logger.log(string.format("[PalBonds/Interaction] [CRASH-DIAG] [EMOTE-DIAG] round %d: EmoteAnimation field read returned — still alive, result=%s", round, anim and "non-nil" or "nil"))
                -- Hundred-and-fortieth pass (2026-09-04) FIX, REAL CRASH
                -- FOUND: the previous version called `anim:GetFName():
                -- ToString()` here — a METHOD call on a UAnimMontage
                -- reference read straight off a Blueprint CDO field. That
                -- reproduced a real crash (confirmed via [CRASH-DIAG]:
                -- the field read itself logged fine, "still alive", but
                -- the very next line — about to call GetFName() — never
                -- got its "returned" counterpart). This is a NEW category
                -- of danger for this project, distinct from the
                -- known "whole-struct-by-value call" crash (#1-4): every
                -- other GetFName()/GetFullName() call in this file is on
                -- a live actor/component/widget object; this was the
                -- first attempt at calling a method on an ASSET reference
                -- (an animation asset, not a runtime actor/component)
                -- pulled directly off a class default object's field —
                -- and it isn't safe the same way. Fixed by never calling
                -- any method on `anim` at all: `tostring(anim)` is pure
                -- Lua-side stringification of whatever wraps it, touches
                -- no native code, and is all this diagnostic actually
                -- needs (the wrapper's own tostring already includes the
                -- asset's path/name in UE4SS, same as every other UObject
                -- printed via plain tostring() elsewhere in this file
                -- when :GetFullName() isn't available).
                local animName = anim and tostring(anim) or "nil"
                Logger.log(string.format("[PalBonds/Interaction] [EMOTE-DIAG] round %d: BP_Action_Emote_%d_C.EmoteAnimation = %s", round, i, animName))
            end
        end
    end
    if allResolved then
        Logger.log("[PalBonds/Interaction] [EMOTE-DIAG] all 9 classes resolved — stopping retry loop")
        return
    end
    if round >= EMOTE_DIAG_MAX_ROUNDS then
        Logger.log("[PalBonds/Interaction] [EMOTE-DIAG] giving up after " .. round .. " rounds — some classes never resolved (see lines above for which ones did)")
        return
    end
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(EMOTE_DIAG_RETRY_MS, function()
            safe_call(function() run_emote_index_mapping(round + 1) end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Interaction] [EMOTE-DIAG] could not schedule a retry round — stopping after round " .. round)
    end
end

local function log_emote_index_mapping()
    run_emote_index_mapping(1)
end

function Interaction.Init()
    Logger.log(string.format(
        "[PalBonds/Interaction] real hooks active (pet=%s, feed=%s, both non-spammable) — look at a Pal and press one",
        PET_KEY, FEED_KEY
    ))
    Logger.log("[PalBonds/Interaction] [EXPERIMENT] CTRL+K = direct-capture test (Capture.TryDirectCapture) — see Capture.lua for the full risk breakdown before using this")
    Logger.log(string.format("[PalBonds/Interaction] %s = Play — random Pal idle animation + trust grant, same range/gating as Pet/Feed", PLAY_KEY))
    Logger.log("[PalBonds/Interaction] [DISABLED] CTRL+H = SelectedFeedingItem direct-call test — the actual call is disabled after a confirmed real crash (hook-points.md, hundred-and-sixtieth pass); only the safe slot-finding diagnostics still run")

    RegisterKeyBind(Key[PET_KEY], function()
        safe_call(do_pet)
    end)
    RegisterKeyBind(Key[FEED_KEY], function()
        safe_call(do_feed)
    end)
    RegisterKeyBindAsync(TEST_CAPTURE_KEY, TEST_CAPTURE_MODIFIERS, function()
        safe_call(do_test_capture)
    end)
    RegisterKeyBindAsync(TEST_SELECTED_FEEDING_KEY, TEST_SELECTED_FEEDING_MODIFIERS, function()
        safe_call(do_test_selected_feeding_item)
    end)
    -- Hundred-and-thirty-ninth pass (2026-09-04): a real crash happened
    -- right after Init() logged the "Play" line above and before any
    -- further log output — meaning it happened somewhere in this new
    -- code, but the crash-resistant log gave no more detail than that.
    -- Per this project's own seventh-pass playbook (a real crash was
    -- only ever actually found by logging immediately before AND after
    -- every single new native call, never by guessing), bracketing every
    -- new addition from this pass with its own before/after log line.
    Logger.log(string.format("[PalBonds/Interaction] [CRASH-DIAG] about to RegisterKeyBindAsync(PLAY_KEY=%s) NOW", tostring(PLAY_KEY)))
    RegisterKeyBindAsync(PLAY_KEY, PLAY_MODIFIERS, function()
        safe_call(do_play)
    end)
    Logger.log("[PalBonds/Interaction] [CRASH-DIAG] RegisterKeyBindAsync(PLAY_KEY) returned — still alive")

    Logger.log("[PalBonds/Interaction] [CRASH-DIAG] about to run log_emote_index_mapping (static EMOTE-DIAG scan) NOW")
    safe_call(log_emote_index_mapping)
    Logger.log("[PalBonds/Interaction] [CRASH-DIAG] log_emote_index_mapping round 1 returned — still alive")

    -- Permanent, read-only watcher on the REAL AddFriendShip function —
    -- fires for every actual grant in the game, ours included, regardless
    -- of who calls it. Only watches ONE function (a real grant is a much
    -- rarer event than every PlayActionByType call across every Pal in
    -- the world), so it should NOT reintroduce the log-spam/framerate
    -- issue from the eighth pass — safe to leave running permanently.
    local okWatch = pcall(function()
        RegisterHook("/Script/Pal.PalIndividualCharacterParameter:AddFriendShip", function(Context, Value, ApplyPassiveSkill)
            local self_ = hook_get(Context)
            local value = hook_get(Value)
            local applyPassive = hook_get(ApplyPassiveSkill)
            Logger.log(string.format(
                "[PalBonds/Interaction] [WATCH] real AddFriendShip fired — param=%s value=%s applyPassiveSkill=%s",
                hook_describe(self_), tostring(value), tostring(applyPassive)
            ))
        end)
    end)
    if not okWatch then
        Logger.log("[PalBonds/Interaction] could not install AddFriendShip watch hook (name may need adjusting)")
    end

    -- Hundred-and-third pass: permanent, read-only watcher on the REAL
    -- SelectedFeedingItem function (APalMonsterCharacter) — see the
    -- [FOOD-DIAG] research notes above get_pal_item_utility(). Fires (if
    -- at all) whenever ANY real feeding-with-an-item happens in the
    -- game, ours included once wired — right now nothing calls this, so
    -- this is purely to find out whether/when vanilla itself calls it
    -- (e.g. feeding an owned Otomo through whatever real menu path
    -- exists), and what real ItemSlotId/Num values look like. Same
    -- single-function, low-frequency watch pattern as AddFriendShip
    -- above — safe to leave running permanently.
    local okWatchFeed = pcall(function()
        RegisterHook("/Script/Pal.PalMonsterCharacter:SelectedFeedingItem", function(Context, ItemSlotId, Num)
            local self_ = hook_get(Context)
            local slot = hook_get(ItemSlotId)
            local num = hook_get(Num)
            local containerGuid = safe_call(function() return slot and slot.ContainerId and tostring(slot.ContainerId.ID) end)
            local slotIndex = safe_call(function() return slot and slot.SlotIndex end)
            Logger.log(string.format(
                "[PalBonds/Interaction] [FOOD-DIAG] real SelectedFeedingItem fired — pal=%s ContainerId=%s SlotIndex=%s Num=%s",
                hook_describe(self_), tostring(containerGuid), tostring(slotIndex), tostring(num)
            ))
        end)
    end)
    if not okWatchFeed then
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] could not install SelectedFeedingItem watch hook (name may need adjusting)")
    end

    -- Hundred-and-fifteenth pass (2026-09-03): the hundred-and-third
    -- pass's SelectedFeedingItem watch just went through three confirmed
    -- real Otomo feeds (via the vanilla radial menu, read straight out of
    -- Dragón's own UE4SS.log) without firing ONCE — a clean negative
    -- result. Reading Dragón's own Live View dumps from that same session
    -- instead revealed the real mechanism: a full Blueprint AI-action
    -- pairing (BP_ActionPairStandby_FeedItem_C /
    -- BP_ActionPairBehavior_FeedItem_C / BP_AIActionPairCall_FeedItem_C)
    -- carrying the real FeedItemSlotId/FeedItemNum as plain fields —
    -- too much machinery (animation montages, camera work, a whole
    -- PawnAction-based AI queue) to safely replicate for a wild Pal. See
    -- hook-points.md's hundred-and-fourteenth pass for the full writeup.
    --
    -- But UPalItemSlot itself — the object those FeedItemSlotId values
    -- point AT — has its own native method, found in the same SDK dump
    -- that found UPalItemSlot in the first place (hundred-and-thirteenth
    -- pass): `RequestUseToCharacter(FPalIndividualCharacterHandle
    -- TargetCharacterID, int32 UseNum)`. If vanilla actually calls THIS
    -- to consume the item — plausible, since it's a method ON the slot
    -- holding the item, named exactly for "use this on a character" —
    -- it would be a much simpler, much safer path for us: find the live
    -- slot object holding the food (FindAllOf, the same proven-safe
    -- pattern used everywhere else in this file), read the target
    -- handle directly off an already-live Pal exactly like
    -- get_individual_handle() already does, and call this method ON THE
    -- OBJECT WE FOUND — never constructing a new FPalItemSlotId struct
    -- from scratch, which is the exact pattern that caused Crash #4.
    -- WATCH ONLY for now, same zero-risk discipline as every hook in
    -- this file: confirm it's real and see its real argument shapes
    -- before ever calling it ourselves. Test plan: feed the Otomo again
    -- through the normal radial menu (no new keybind needed) and check
    -- the log for a [SLOT-USE-DIAG] line.
    --
    -- HUNDRED-AND-SIXTEENTH PASS (2026-09-03) FIX: Dragón's very first
    -- test came back with a real, clean hit — THREE TIMES, in fact — and
    -- proved this really is the live consumption call: StackCount read
    -- 65, then 64, then 63 on three separate real fires, each with
    -- UseNum=1, a perfect one-for-one decrement. That's the confirmation
    -- this whole diagnostic existed to get. The only problem was
    -- cosmetic: plain tostring() on an FGuid or FName field in UE4SS Lua
    -- just prints its userdata address ("UScriptStruct: 0x...",
    -- "FNameUserdata: 0x..."), not the human-readable value — both
    -- FGuid and FName support a real :ToString() method that does what
    -- we actually want (confirmed by the earlier Live View JSON dumps
    -- rendering ContainerId as "(ID=<32-hex>)" and ItemId.StaticId as a
    -- plain string). Added a small `readable()` helper that tries
    -- `:ToString()` first and only falls back to plain tostring() if
    -- that fails — a method call on a value we already safely read off
    -- a live object, not a new native call with constructed arguments,
    -- so this carries the same zero risk as the rest of this watch.
    local function readable(value)
        if value == nil then return "nil" end
        local ok, str = pcall(function() return value:ToString() end)
        if ok and str ~= nil then return str end
        return tostring(value)
    end

    local okWatchUseSlot = pcall(function()
        RegisterHook("/Script/Pal.PalItemSlot:RequestUseToCharacter", function(Context, TargetCharacterID, UseNum)
            local slot = hook_get(Context)
            local target = hook_get(TargetCharacterID)
            local useNum = hook_get(UseNum)
            local containerGuid = safe_call(function() return slot and slot.ContainerId and readable(slot.ContainerId.ID) end)
            local slotIndex = safe_call(function() return slot and slot.SlotIndex end)
            local itemStaticId = safe_call(function() return slot and slot.ItemId and readable(slot.ItemId.StaticId) end)
            local stackCountBefore = safe_call(function() return slot and slot.StackCount end)
            Logger.log(string.format(
                "[PalBonds/Interaction] [SLOT-USE-DIAG] real PalItemSlot:RequestUseToCharacter fired — ContainerId=%s SlotIndex=%s ItemId.StaticId=%s StackCount(at fire time)=%s UseNum=%s target=%s (target-ToString=%s)",
                tostring(containerGuid), tostring(slotIndex), tostring(itemStaticId), tostring(stackCountBefore), tostring(useNum), hook_describe(target), readable(target)
            ))
        end)
    end)
    if not okWatchUseSlot then
        Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] could not install PalItemSlot:RequestUseToCharacter watch hook (name may need adjusting)")
    end

    -- ---------------------------------------------------------------
    -- Thirteenth-pass addition: watch the REAL native interact menu
    -- system, in response to Dragón asking to move Pet/Feed into the
    -- game's own radial menu instead of the F9/F10 hotkeys.
    --
    -- Found in the SDK dump: `UPalInteractComponent` (lives on the
    -- player) is the actual native system behind every "hold to
    -- interact" prompt in the game — talking to NPCs, opening chests,
    -- AND petting/feeding an owned Pal all go through it. Key pieces:
    --   - `TargetInteractiveObject` — a field holding whatever the
    --     player is currently looking at that CAN be interacted with.
    --     This is the game's own real equivalent of this file's
    --     hand-rolled find_targeted_pal().
    --   - `StartTriggerInteract(ActionType, IsToggle)` /
    --     `EndTriggerInteract(ActionType)` — actually starts/ends one
    --     interaction.
    --   - `EPalInteractiveObjectActionType` — the enum passed in. Its
    --     values are generic SLOT NAMES (Interact1..Interact4), not
    --     "Pet"/"Feed" — which slot means what is decided per object
    --     type (a Pal's own Blueprint implementation of
    --     `GetIndicatorInfo` from `IPalInteractiveObjectComponentInterface`
    --     picks what each of its 4 slots does). So we don't yet know
    --     which Interact# number is Pet vs Feed for a Pal, or whether
    --     `TargetInteractiveObject` ever gets set to a WILD (unowned)
    --     Pal at all — that ownership gate could live anywhere upstream
    --     of this component.
    --
    -- Rather than guess and call StartTriggerInteract blind — this is
    -- exactly the kind of Blueprint-adjacent pair-action machinery this
    -- project has been burned by before (see crash #1/#2/#3 history) —
    -- this only WATCHES, read-only, same proven pattern as the
    -- AddFriendShip hook above. Test plan for next session: hold the
    -- interact key on an OWNED Pal and do a real Pet, then a real Feed,
    -- via the vanilla menu — the log will show which ActionType number
    -- fired for each, and what species TargetInteractiveObject pointed
    -- at. Then try just looking at / holding interact near a WILD Pal to
    -- see whether this component reacts to it AT ALL. That data is what
    -- decides whether wild-Pal Pet/Feed can hook in at this level (real
    -- menu, real animations/camera work already wired by the game) or
    -- needs the ownership gate found and patched further upstream first.
    -- Ninety-first pass (2026-09-03): Dragón made the actual insight this
    -- whole thread has been missing — he watched it happen live and told
    -- us directly: "if its a base pal it opens the worker menu, if not
    -- then its the other one." That's the REAL eligibility rule, not
    -- wild-vs-owned. `UPalCharacterParameterComponent` (the same component
    -- get_individual_parameter/get_individual_handle already read) has a
    -- plain field for exactly this, confirmed in the SDK dump:
    -- `WorkAssignId` (a `FPalWorkAssignHandleId { FGuid WorkId; int32
    -- LocationIndex; EPalWorkAssignType AssignType }`) plus a getter,
    -- `GetWorkAssign()`. A Pal actually assigned as a base worker should
    -- show a real WorkId/LocationIndex; a wild (or owned-but-unassigned)
    -- Pal should show an empty/invalid one. This is a read-only field/
    -- getter read — same safe pattern as every other component field this
    -- file already uses — logged here for every real ActionType=4 "4"
    -- press so it can be directly correlated against whichever menu
    -- actually opens right after (RADIAL-WATCH vs WORKER-WATCH), giving
    -- real evidence for or against the theory before touching anything.
    local function describe_work_assign(pal)
        if not pal then return "no aimed Pal" end
        local comp = safe_call(function() return pal.CharacterParameterComponent end)
        if not comp or not comp:IsValid() then
            return "no CharacterParameterComponent"
        end
        local workId = safe_call(function() return comp.WorkAssignId end)
        local guidStr = safe_call(function() return workId and tostring(workId.WorkId) end)
        local locIndex = safe_call(function() return workId and workId.LocationIndex end)
        local assignType = safe_call(function() return workId and workId.AssignType end)
        local workAssignObj = safe_call(function() return comp:GetWorkAssign() end)
        return string.format(
            "WorkAssignId.WorkId=%s LocationIndex=%s AssignType=%s GetWorkAssign()=%s",
            tostring(guidStr), tostring(locIndex), tostring(assignType), hook_describe(workAssignObj)
        )
    end

    local okWatchInteract = pcall(function()
        RegisterHook("/Script/Pal.PalInteractComponent:StartTriggerInteract", function(Context, ActionType, IsToggle)
            local self_ = hook_get(Context)
            local actionType = hook_get(ActionType)
            local isToggle = hook_get(IsToggle)
            local target = safe_call(function() return self_ and self_.TargetInteractiveObject end)
            Logger.log(string.format(
                "[PalBonds/Interaction] [MENU-WATCH] StartTriggerInteract — component=%s ActionType=%s IsToggle=%s TargetInteractiveObject=%s",
                hook_describe(self_), tostring(actionType), tostring(isToggle), hook_describe(target)
            ))
            -- Eighty-first pass: remember this target ONLY for ActionType=4
            -- (confirmed the "aiming at a Pal" case) so the real Worker-menu
            -- selection hook below knows which Pal a later Pet/Feed pick
            -- was actually for.
            if tostring(actionType) == "4" and target ~= nil then
                lastAimedInteractTarget = target
            end
            -- Ninety-first pass diagnostic: on every real ActionType=4
            -- press, resolve whatever's being aimed at (same look-based
            -- targeting as everywhere else in this file) and log its
            -- WorkAssignId/GetWorkAssign() state.
            if tostring(actionType) == "4" then
                safe_call(function()
                    local player = FindFirstOf("PalPlayerCharacter")
                    if not player or not player:IsValid() then return end
                    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
                        or safe_call(function() return player:K2_GetActorLocation() end)
                    if not originLoc then return end
                    local controlRot = safe_call(function() return player:GetControlRotation() end)
                    if not controlRot then return end
                    local forward = rotator_to_forward(controlRot)
                    local aimedPal = find_targeted_pal(originLoc, forward, player)
                    local aimedName = aimedPal and safe_call(function() return aimedPal:GetFullName() end)
                    Logger.log(string.format(
                        "[PalBonds/Interaction] [WORKASSIGN-DIAG] aimed=%s %s",
                        tostring(aimedName), describe_work_assign(aimedPal)
                    ))
                end)
            end
        end)
        RegisterHook("/Script/Pal.PalInteractComponent:EndTriggerInteract", function(Context, ActionType)
            local self_ = hook_get(Context)
            local actionType = hook_get(ActionType)
            Logger.log(string.format(
                "[PalBonds/Interaction] [MENU-WATCH] EndTriggerInteract — component=%s ActionType=%s",
                hook_describe(self_), tostring(actionType)
            ))
        end)
    end)
    if not okWatchInteract then
        Logger.log("[PalBonds/Interaction] could not install PalInteractComponent watch hooks (name may need adjusting)")
    end

    -- ---------------------------------------------------------------
    -- Forty-second pass (2026-09-03): the REAL radial-menu ("4" key)
    -- Pet/Feed system, prompted by Dragón asking to move off F9/F10 and
    -- onto the game's own UI ("its already kind of annoying to try and
    -- find a key that's usually not in the game like f9 and f10, im just
    -- used to pet and feed pals with the radial menu"). The thirteenth-
    -- pass MENU-WATCH hooks above (native PalInteractComponent) turned
    -- out NOT to be it — a full log review showed ActionType=1 always has
    -- real Start+End pairs but only against non-Pal objects (PalBox,
    -- storage, fast-travel towers); ActionType=2/3/4 only ever appear as
    -- orphaned EndTriggerInteract calls every few seconds regardless of
    -- player action — an unrelated periodic background reset, not a real
    -- radial-menu selection.
    --
    -- Real lead instead, found by reading this project's OWN actual game
    -- file directly rather than guessing: `Pal-Windows.pak` (the real,
    -- unencrypted 40GB main asset archive already sitting on disk) opened
    -- with `repak` (same tool already used on reference mods) revealed
    -- the real radial-menu widget assets:
    --   /Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu
    --   /Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu_MenuContent
    -- Reading their compiled string tables (`strings`, same technique
    -- proven in the sixty-fifth pass's BindFromHandle fix) surfaced real
    -- function names: CreatePlayerActionMenu / OpenPlayerActionMenu /
    -- "Can Open Player Action Menu" (the eligibility gate) /
    -- OnDecidedPlayerActionMenu / "On Decided Instruction Care" /
    -- OnDecidedInstruction_Feed. The path FORMAT below
    -- (<package path>.<ClassName>:<FunctionName>) is the same
    -- confirmed-correct shape the sixty-fifth pass already proved works
    -- for Blueprint targets — this is the first time this project points
    -- that proven shape at a NEW class, using a real path instead of a
    -- guess.
    --
    -- IMPORTANT CAVEAT, found in the same string dump: this whole system
    -- is built around the player's OWN ACTIVE OTOMO
    -- (GetOtomoHolderComponent, TryGetSpawnedOtomo, SpawnedOtomo,
    -- IsOtomoActivated...) — not a generic "whatever Pal you're looking
    -- at" system. It may simply have no concept of a wild, unowned target
    -- at all. That is exactly the open question these hooks exist to
    -- answer — WATCH ONLY, zero side effects, same discipline as the
    -- thirteenth-pass hooks above, before deciding whether wild Pals can
    -- hook in here or need a different (possibly custom-built) UI. Also
    -- worth noting: EPalOtomoPalOrderType (the enum behind
    -- RequestSetOtomoOrder/SetOtomoOrder_ToServer, watched below too) only
    -- has 3 values — Default/Warlike/NotCombat, a combat-STANCE toggle,
    -- NOT Care/Feed/Attack/Assist/Escape as the message-ID names
    -- (PAL_INSTRUCTION_CARE etc., also found in the same string dump)
    -- previously suggested — those are just UI text labels. The real
    -- per-instruction trigger functions are the Blueprint ones below.
    --
    -- Test plan for next session: press "4" near your own active Otomo
    -- and actually pick Care, then Feed, from the wheel — the log should
    -- show which of these fire, in what order, with what args. Then try
    -- the same while looking at a WILD Pal (no Otomo targeted) to see
    -- whether ANY of this fires at all — that answers the ownership-gate
    -- question directly instead of guessing, and decides the next step
    -- toward removing F9/F10.
    -- CORRECTION made while writing this pass, before ever deploying:
    -- re-running `strings` specifically on WBP_PlayerRadialMenu_MenuContent
    -- alone (not the combined dump) shows it only contains generic
    -- container/text-block strings (PalRetainerBox, BP_PalTextBlock) — no
    -- Care/Feed/Otomo/instruction strings at all. Every interesting name
    -- above (OnDecidedPlayerActionMenu, "On Decided Instruction Care",
    -- OnDecidedInstruction_Feed, DecideMenuAction) actually came from the
    -- OUTER WBP_PlayerRadialMenu.uasset/.uexp pair, not from MenuContent.
    -- MenuContent looks like a generic, reusable "content slot" container
    -- the outer wheel pushes whichever child widget into (construction
    -- list, Otomo swap icons, instruction icons, etc.), not where the
    -- decision logic itself lives. So every candidate below now targets
    -- the one real class, WBP_PlayerRadialMenu_C.
    -- FORTY-THIRD PASS (2026-09-03) RESULT + FIX: Dragón's test came back
    -- with two real findings.
    --
    -- (1) Dragón corrected a wrong assumption in the comment above: the
    -- radial menu is NOT limited to your one active/following Otomo. He
    -- petted a Lamball with it (active Otomo), then took a Tanzee out at
    -- his base to roam, aimed at IT specifically, and petted it the same
    -- way. The live [MENU-WATCH] log (native PalInteractComponent, already
    -- hooked since the thirteenth pass) proves this directly — it shows a
    -- real ActionType=4 Start+End pair firing repeatedly, with a REAL
    -- TargetInteractiveObject: a "PalInteractableSphereComponentNative" on
    -- the targeted Pal actor. This directly contradicts this project's own
    -- earlier read of ActionType=2/3/4 as "unrelated periodic background
    -- calls" — that read was wrong, or at least incomplete: ActionType=4
    -- clearly IS the real per-Pal radial-interact trigger, gated by AIMING
    -- (a Pal exposes its own interactable sphere; the interact system
    -- finds whichever one you're looking at), not by "is this my current
    -- active Otomo." That's good news for wild Pals — the gate is more
    -- likely an ownership check somewhere upstream, not a hard "must be
    -- the one active Otomo" restriction.
    --
    -- (2) EVERY ONE of the 8 Blueprint hook candidates below FAILED with
    -- "no UFunction with the specified name was found" — the path FORMAT
    -- is confirmed correct (same shape as the working BindFromHandle fix),
    -- so this points at the NAMES themselves. Re-examining the string dump:
    -- `strings` can't tell a real callable FName apart from a cosmetic
    -- "DisplayName" — and Unreal auto-generates a spaced-out DisplayName
    -- from a PascalCase FName for the editor UI (e.g. real name
    -- `CanOpenPlayerActionMenu` displays as "Can Open Player Action Menu").
    -- The strings dump's OWN pin name `CallFunc_Can_Open_Player_Action_
    -- Menu_Result` is strong evidence for this: it's Unreal's auto-derived
    -- pin name for a call to `CanOpenPlayerActionMenu`, splitting the real
    -- PascalCase FName at capitals and joining with underscores — which
    -- only produces that exact pin name if the real FName has NO spaces.
    -- So the spaced strings seen earlier were very likely just cosmetic
    -- display text, not the real hookable name. Fixed by trying the
    -- no-space PascalCase form FIRST, keeping the originally-observed
    -- spaced form as a fallback candidate in case this guess is wrong.
    --
    -- Also added: a bounded retry over time (same discipline as
    -- Indicator.lua's register_bind_hook_once/MAX_BIND_HOOK_ATTEMPTS) in
    -- case the REAL problem is that this widget class simply isn't loaded
    -- yet this early (mod Init() runs at game boot, likely before the
    -- radial menu widget is ever constructed) rather than a naming issue —
    -- covers both possibilities without guessing which one it is.
    local RADIAL_MENU_CLASS = "/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu.WBP_PlayerRadialMenu_C"

    -- Ninety-seventh pass (2026-09-03) FIX: the 12:05-12:08 test session's
    -- log proved this budget was the real problem, not the ninety-sixth
    -- pass's redirect-window fix. `RADIAL-REDIRECT` fired ZERO times that
    -- session despite 7 real "4" presses — because EVERY hook on
    -- WBP_PlayerRadialMenu_C (including "Can Open Player Action Menu",
    -- the exact hook that arms the redirect window) failed all 8 rounds
    -- and gave up at ~12:06:07, roughly 37s after mod load — but Dragón's
    -- first "4" press wasn't until 12:07:39, ~90s AFTER the retry loop had
    -- already quit. Same simultaneous "giving up" failure hit
    -- INDICATOR-WATCH (x2), WORKER-WATCH (x2), and WORKER-BIND-FIX in the
    -- same few seconds — strong evidence this is a general "these
    -- Blueprint UI widget classes just aren't loaded into memory yet this
    -- early" timing issue (they likely only load on first real
    -- construction, i.e. the player's first actual menu-open), not a
    -- per-class naming problem — the names above are mostly already
    -- confirmed real across many past sessions (pass 77's comment above).
    --
    -- Fix: extend the shared retry budget from 8 rounds (40s total) to 60
    -- rounds (5 minutes total) at the same 5s cadence. Kept it a bounded
    -- number rather than infinite retry — a couple of candidates in these
    -- target lists (ChangeMode/DecideMenuAction) are still unconfirmed
    -- guesses, and this project has hit real lag bugs from unbounded
    -- per-round logging twice before (ninety-third/ninety-fifth passes) —
    -- so an eventual stop still exists, just far enough out to plausibly
    -- cover a normal player's actual pre-first-"4"-press delay.
    local MAX_RADIAL_HOOK_ROUNDS = 60
    local RADIAL_HOOK_RETRY_MS = 5000

    -- Seventy-ninth pass (2026-09-03) cleanup: Dragón saw a burst of
    -- repeated failure lines fire in quick succession and asked to trim
    -- out whatever's already confirmed dead, to cut the noise. Two kinds
    -- of trims applied here, both backed by real log evidence from full
    -- prior sessions (not guesses):
    --   1. REMOVED outright — RegisterHook itself failed for these on
    --      EVERY one of 8 rounds in a session where sibling candidates on
    --      this exact same class succeeded (proving the class WAS loaded
    --      and reachable): SelectMapObjectId, SelectPageByMapObject,
    --      SelectPageAndIndex, IsOpened. These names conclusively don't
    --      exist on WBP_PlayerRadialMenu_C under any form tried.
    --   2. SIMPLIFIED to one candidate — CanOpenPlayerActionMenu and
    --      OnDecidedInstructionCare both confirmed live (seventy-sixth
    --      pass) to be the SPACED form only; the no-space PascalCase guess
    --      always failed first. Dropped the dead guess, kept the real name.
    -- Left `ChangeMode`/`DecideMenuAction` alone — no direct evidence
    -- either way (they simply never appeared in a "confirmed working" list,
    -- which could mean the names are wrong OR just that Dragón's test never
    -- triggered whatever they correspond to). Also left the
    -- OpenSetup/CloseSetup/SetupEvent/OpenMenu/CloseMenu/IsAnyMenuOpened
    -- dual-candidate entries alone — pass 77 confirmed these six DO work,
    -- but the live log that would show WHICH of the two name forms
    -- actually fired no longer exists (Logger.lua truncates per session),
    -- so trimming the "wrong" one blind risks deleting the real one.
    local radialHookTargets = {
        { tag = "OpenPlayerActionMenu", candidates = {"OpenPlayerActionMenu"} },
        -- Eighty-fifth pass: this is the earliest confirmed-real signal
        -- that a "4"-press's no-aim menu is opening (fires first, every
        -- cycle, per the eighty-fourth pass's live log) — used to open the
        -- narrow TryGetSpawnedOtomo redirect window below, nothing else.
        { tag = "CanOpenPlayerActionMenu", candidates = {"Can Open Player Action Menu"}, onFire = openRadialMenuActionWindow },
        { tag = "CreatePlayerActionMenu", candidates = {"CreatePlayerActionMenu"} },
        { tag = "ChangeMode", candidates = {"ChangeMode", "Change Mode"} },
        { tag = "OnDecidedPlayerActionMenu", candidates = {"OnDecidedPlayerActionMenu"} },
        -- Ninety-ninth pass: these two now also record which instruction
        -- was last decided during the CURRENT window (see
        -- lastDecidedInstruction above) — deliberately ignoring the
        -- event's own arg1, whose exact meaning isn't confirmed yet (see
        -- the comment above lastDecidedInstruction's declaration). The
        -- actual real-world effect only happens later, at CloseMenu, and
        -- only if radialMenuRedirectedThisWindow is also true.
        { tag = "OnDecidedInstructionCare", candidates = {"On Decided Instruction Care"}, onFire = function()
            if radialMenuActionWindowOpen then
                lastDecidedInstruction = "care"
            end
        end },
        { tag = "OnDecidedInstructionFeed", candidates = {"OnDecidedInstruction_Feed"}, onFire = function()
            if radialMenuActionWindowOpen then
                lastDecidedInstruction = "feed"
            end
        end },
        { tag = "DecideMenuAction", candidates = {"DecideMenuAction", "Decide Menu Action"} },
        { tag = "OpenSetup", candidates = {"OpenSetup", "Open Setup"} },
        { tag = "CloseSetup", candidates = {"CloseSetup", "Close Setup"} },
        { tag = "SetupEvent", candidates = {"SetupEvent", "Setup Event"} },
        { tag = "OpenMenu", candidates = {"OpenMenu", "Open Menu"} },
        -- Eighty-fifth pass: confirmed-real close signal — closes the
        -- redirect window the moment the menu closes, so the substitution
        -- can never linger past the actual "4" interaction.
        { tag = "CloseMenu", candidates = {"CloseMenu", "Close Menu"}, onFire = closeRadialMenuActionWindow },
        { tag = "IsAnyMenuOpened", candidates = {"IsAnyMenuOpened", "Is Any Menu Opened"} },
        { tag = "OnOtomoChangedActivated", candidates = {"OnOtomoChanged_Activated"} },
        { tag = "OnOtomoChangedInactivated", candidates = {"OnOtomoChanged_Inactivated"} },
    }

    -- Seventy-seventh pass (2026-09-03): generalized the round-runner
    -- below (originally written just for RADIAL_MENU_CLASS) into a small
    -- factory, so the same bounded-retry/candidate-name machinery can be
    -- pointed at MULTIPLE classes. Needed because the seventy-sixth pass's
    -- live test proved conclusively that aiming "4" at a specific Pal
    -- fires NONE of the WBP_PlayerRadialMenu_C hooks above — five separate
    -- real presses on his base Tanzee (confirmed via the native MENU-WATCH
    -- ActionType=4 hook on that exact Pal's interactable sphere) produced
    -- zero hits on any of the 18 candidates tried. That's not a naming
    -- miss — it means the aimed-at-a-Pal case is a genuinely different
    -- Blueprint system.
    --
    -- Went back to the game's own real pak for the answer instead of
    -- guessing further: grepped the full file listing for interact-
    -- indicator-shaped names and found `WBP_PalInteractiveObjectIndicatorUI`
    -- and `WBP_PalInteractiveObjectIndicatorCanvas`. Reading their string
    -- tables is a real breakthrough — it directly answers a question this
    -- project has had open since the TWENTIETH pass ("find the Blueprint
    -- that implements GetIndicatorInfo for Pal characters"): `Canvas`
    -- literally has `GetIndicatorInfo`, `CreateIndicatorUI`,
    -- `ShowIndicator(s)`, `HideIndicators`, and — the strongest lead of
    -- all — `OnUpdateTargetInteractiveObject`, a delegate that sounds
    -- exactly like "fires when the player's aimed target changes." It ALSO
    -- has a separate, parallel `ShowOtomoIndicator(s)`/
    -- `OtomoIndicatorActionInfo` pair, implying Otomo Pals get an
    -- additional/different indicator on top of the generic one — real,
    -- concrete evidence that aiming at a Pal (Otomo or not) goes through
    -- THIS system, not `WBP_PlayerRadialMenu_C`. The per-slot companion
    -- widget, `WBP_PalInteractiveObjectIndicatorUI_C`, has its own
    -- `SetActionInfo`/`SetInteractable`/`Activate`/`Deactivate` functions.
    local INDICATOR_CANVAS_CLASS = "/Game/Pal/Blueprint/UI/WBP_PalInteractiveObjectIndicatorCanvas.WBP_PalInteractiveObjectIndicatorCanvas_C"
    local INDICATOR_UI_CLASS = "/Game/Pal/Blueprint/UI/WBP_PalInteractiveObjectIndicatorUI.WBP_PalInteractiveObjectIndicatorUI_C"

    -- Eightieth pass (2026-09-03) FIX: `UpdateInteractTargetName` removed
    -- entirely. Dragón's real test (7 real worker-menu opens: pet/feed
    -- Tanzee, view status, add to party, pet again, pet/feed Petallia)
    -- also came with felt lag — and the log proves why. This one hook
    -- fired **2375 times** in a 137-second session (arg1 was ALWAYS nil,
    -- so it wasn't even giving useful data) — clearly a per-tick/per-frame
    -- UI text refresh, not a discrete event, the exact same class of bug
    -- as the ninth-pass find_targeted_pal spam (Logger.log does a
    -- synchronous flushed disk write per call — see Logger.lua — so a few
    -- thousand calls in two minutes is a real, feel-able cost). Everything
    -- else on this class fired at sane, clearly-discrete-event volumes in
    -- the same session (66, 124, 264, etc.) and is kept. No functionality
    -- is lost: `OnUpdateTargetInteractiveObject` already gives the same
    -- "what changed" information at 1/36th the volume, WITH a real,
    -- resolvable target object (confirmed live: fired with `BP_InteractableCapsule_C`
    -- for a PalBox and, more importantly, `PalInteractableSphereComponentNative`
    -- on an actual `BP_Monkey_C` Pal actor — direct proof this hook sees
    -- Pals specifically, at a perfectly reasonable rate).
    local indicatorCanvasTargets = {
        { tag = "GetIndicatorInfo", candidates = {"GetIndicatorInfo"} },
        { tag = "CreateIndicatorUI", candidates = {"CreateIndicatorUI"} },
        { tag = "ShowIndicator", candidates = {"ShowIndicator"} },
        { tag = "ShowIndicators", candidates = {"ShowIndicators"} },
        { tag = "HideIndicators", candidates = {"HideIndicators"} },
        { tag = "ShowOtomoIndicator", candidates = {"ShowOtomoIndicator"} },
        { tag = "ShowOtomoIndicators", candidates = {"ShowOtomoIndicators"} },
        { tag = "OnUpdateTargetInteractiveObject", candidates = {"OnUpdateTargetInteractiveObject"} },
        { tag = "GetInteractTargetName", candidates = {"GetInteractTargetName"} },
        { tag = "SetupIndicatorCanvas", candidates = {"Setup"} },
        { tag = "SetupAfterCreatePlayer", candidates = {"SetupAfterCreatePlayer"} },
        { tag = "OnChangeOtomo", candidates = {"OnChangeOtomo"} },
    }

    local indicatorUITargets = {
        { tag = "SetActionInfo", candidates = {"SetActionInfo"} },
        { tag = "SetActionType", candidates = {"SetActionType", "Set Action Type"} },
        { tag = "SetInteractable", candidates = {"SetInteractable"} },
        { tag = "SetIsValidInteract", candidates = {"SetIsValidInteract"} },
        { tag = "IndicatorActivate", candidates = {"Activate"} },
        { tag = "IndicatorDeactivate", candidates = {"Deactivate"} },
        { tag = "PressInteractButton", candidates = {"PressInteractButton"} },
        { tag = "ReleaseInteractButton", candidates = {"ReleaseInteractButton"} },
    }

    -- Seventy-eighth pass (2026-09-03): Dragón spotted a THIRD radial-menu
    -- family while browsing the pak himself and sent screenshots —
    -- `WBP_WorkerRadialMenu` / `WBP_WorkerRadialMenu_Overlay` /
    -- `WBP_WorkerRadialMenuContent`, under
    -- /Game/Pal/Blueprint/UI/WorkerRadialMenu/. "Worker" is the game's own
    -- term for a base Pal (his Tanzee, put down at his base to roam) — so
    -- this is a strong candidate for the still-unexplained "aim '4' at a
    -- specific Pal" code path the seventy-sixth/seventy-seventh passes
    -- proved does NOT go through WBP_PlayerRadialMenu_C at all.
    --
    -- Extracted via repak and read with `strings`, same as every class
    -- above. Real, concrete evidence this is the right family: the content
    -- widget's string table literally contains `MsgID_Pet` and
    -- `MsgID_Feed` (plus `MsgID_MoveToBox`, `MsgID_MoveToOtomo`,
    -- `MsgID_ShowStatus`) — this menu's own options are Pet/Feed/Move to
    -- box/Move to Otomo/Show status — and a dedicated result enum,
    -- `EPalWorkerRadialMenuResult`, which is a much cleaner selection
    -- signal than WBP_PlayerRadialMenu_C's raw OnDecidedPlayerActionMenu
    -- index ever was.
    --
    -- Two real classes here, same split as the Player menu had (an outer
    -- "Overlay" controller that owns opening/closing/input-binding, and
    -- the menu widget itself that owns content/selection):
    --   WBP_WorkerRadialMenu_Overlay_C — Open/Close/Construct/Destruct,
    --     DecideMenuAction, CancelEvent, Interact, OnSetup,
    --     OnSelectedEvent/OnSelectedMenu, RegisterActionBinding,
    --     ListenForInputAction, SetDisableWeaponForUI,
    --     OnAnyUIPushed/OnPushedStackableUI (this last pair takes a
    --     `PalHUDDispatchParameter_WorkerRadialMenu` struct — likely where
    --     the target Pal handle itself is carried in).
    --   WBP_WorkerRadialMenu_C — Construct, CreateContent, SetupContents,
    --     ClearSelectedIndex, CalculateRadialMenuArea, OnInitialized,
    --     OnClosed, OnSelectedMenu/OnSelectedMenu_Internal,
    --     OnDecideIndex_forBP (a delegate — tried as a plain hookable name
    --     too, in case it's also a real event, though delegate signatures
    --     often aren't directly hookable).
    -- Left out anything that showed up only as a `CallFunc_*_ReturnValue`
    -- pin name (IsDead, IsSameWidget, TryGetIndividualActor, GetHUDService,
    -- GetPalmi, GetParam, GetComponentByClass) — those are Blueprint call
    -- sites INTO other classes' functions, not functions defined on either
    -- Worker menu class itself, so hooking them here would just always
    -- fail on the wrong owner.
    --
    -- WATCH ONLY, same discipline as every hook in this file. Test plan:
    -- aim "4" at a base/worker Pal (owned or, ideally, wild once we get
    -- there) and check the log for any [WORKER-WATCH] line — especially
    -- Open, OnSetup, OnSelectedMenu, and OnAnyUIPushed/OnPushedStackableUI
    -- (whose struct arg might reveal the target Pal handle even before we
    -- know the exact selection function).
    local WORKER_MENU_CLASS = "/Game/Pal/Blueprint/UI/WorkerRadialMenu/WBP_WorkerRadialMenu.WBP_WorkerRadialMenu_C"
    local WORKER_MENU_OVERLAY_CLASS = "/Game/Pal/Blueprint/UI/WorkerRadialMenu/WBP_WorkerRadialMenu_Overlay.WBP_WorkerRadialMenu_Overlay_C"

    local workerMenuTargets = {
        { tag = "Construct", candidates = {"Construct"} },
        { tag = "CreateContent", candidates = {"CreateContent"} },
        { tag = "SetupContents", candidates = {"SetupContents", "Setup Contents"} },
        { tag = "ClearSelectedIndex", candidates = {"ClearSelectedIndex", "Clear Selected Index"} },
        { tag = "CalculateRadialMenuArea", candidates = {"CalculateRadialMenuArea", "Calculate Radial Menu Area"} },
        { tag = "OnInitialized", candidates = {"OnInitialized"} },
        { tag = "OnClosed", candidates = {"OnClosed"} },
        { tag = "OnSelectedMenu", candidates = {"OnSelectedMenu"} },
        -- NOTE: `OnSelectedMenu_Internal` deliberately NOT in this
        -- watch-only list anymore (eighty-first pass) — it now has its own
        -- dedicated, REAL functional hook below (register_worker_selected_hook),
        -- which also logs its own fire. Keeping both would just double-log
        -- every selection.
        { tag = "OnDecideIndexForBP", candidates = {"OnDecideIndex_forBP"} },
    }

    local workerMenuOverlayTargets = {
        { tag = "Open", candidates = {"Open"} },
        { tag = "Close", candidates = {"Close"} },
        { tag = "Construct", candidates = {"Construct"} },
        { tag = "Destruct", candidates = {"Destruct"} },
        { tag = "DecideMenuAction", candidates = {"DecideMenuAction", "Decide Menu Action"} },
        { tag = "CancelEvent", candidates = {"CancelEvent", "Cancel Event"} },
        { tag = "Interact", candidates = {"Interact"} },
        { tag = "OnSetup", candidates = {"OnSetup"} },
        { tag = "OnSelectedEvent", candidates = {"OnSelectedEvent"} },
        { tag = "OnSelectedMenu", candidates = {"OnSelectedMenu"} },
        { tag = "RegisterActionBinding", candidates = {"RegisterActionBinding", "Register Action Binding"} },
        { tag = "ListenForInputAction", candidates = {"ListenForInputAction", "Listen For Input Action"} },
        { tag = "SetDisableWeaponForUI", candidates = {"SetDisableWeaponForUI", "Set Disable Weapon For UI"} },
        { tag = "OnAnyUIPushed", candidates = {"OnAnyUIPushed"} },
        { tag = "OnPushedStackableUI", candidates = {"OnPushedStackableUI"} },
    }

    local function make_hook_handler(logTag, tag, onFire)
        return function(Context, A, B, C)
            local self_ = hook_get(Context)
            if onFire then
                -- Hundred-and-twenty-third pass: now passes self_ through
                -- (the live widget instance) — openRadialMenuActionWindow
                -- is the only current onFire that uses it; every other
                -- onFire in radialHookTargets/workerMenuTargets ignores
                -- extra arguments harmlessly (closeRadialMenuActionWindow
                -- and the two lastDecidedInstruction closures all take
                -- zero declared params already).
                safe_call(function() onFire(self_) end)
            end
            Logger.log(string.format(
                "[PalBonds/Interaction] [%s] %s fired — self=%s arg1=%s arg2=%s arg3=%s",
                logTag, tag, hook_describe(self_), hook_describe(hook_get(A)), hook_describe(hook_get(B)), hook_describe(hook_get(C))
            ))
        end
    end

    -- Ninety-eighth pass (2026-09-03) FIX: the ninety-seventh pass's live
    -- test confirmed the extended budget WORKED (RADIAL-REDIRECT fired,
    -- Pet/Feed lit up) but Dragón also reported it "felt terribly
    -- laggy" — worse than before. Root cause, found in the log: each
    -- FAILED RegisterHook error's `tostring(err)` embeds a full ~10-line
    -- stack traceback (always the same one — the call site never
    -- changes, so it adds no diagnostic value), and a handful of
    -- candidate names (ChangeMode/DecideMenuAction on the radial class;
    -- several on the worker classes; several on the indicator class)
    -- are genuinely dead — real evidence, not a guess: their sibling
    -- targets on the SAME class resolved within a couple of rounds,
    -- proving the class loads fine, while these specific names kept
    -- failing through round 19 (the whole log was cut off there —
    -- would have kept failing, with a full traceback each, every 5s
    -- out to the new round-60/5-minute cap). Two fixes, both cheap:
    --   1. Log only the first line of the error (the actual message),
    --      not the embedded traceback — cuts every failure line from
    --      ~10 lines to 1 without losing any real information.
    --   2. Track the round a class FIRST proves loaded (any one of its
    --      targets hooks successfully). Once proven, give the remaining
    --      unresolved targets a few more rounds (they might just be
    --      slightly slower) but then stop — a name still unresolved
    --      long after a sibling on the same class succeeded is a wrong
    --      name, not a loading-timing issue, and no amount of extra
    --      waiting fixes that.
    -- Same discipline proven in the seventy-fourth/seventy-fifth passes,
    -- extended in the ninety-seventh pass, tightened here.
    local EARLY_EXIT_ROUNDS_AFTER_PROOF = 3

    local function make_hook_round_runner(className, targets, logTag)
        local round = 0
        local provenLoadedAtRound = nil
        local runner
        runner = function()
            round = round + 1
            local allDone = true
            local anyHookedThisGroup = false
            for _, target in ipairs(targets) do
                if not target.hooked then
                    for _, funcName in ipairs(target.candidates) do
                        local path = className .. ":" .. funcName
                        local ok, err = pcall(function()
                            RegisterHook(path, make_hook_handler(logTag, target.tag, target.onFire))
                        end)
                        local errFirstLine
                        if not ok then
                            errFirstLine = tostring(err):match("^[^\n]*") or tostring(err)
                        end
                        Logger.log(string.format(
                            "[PalBonds/Interaction] [%s] round %d: RegisterHook(%s) = %s",
                            logTag, round, path, ok and "OK" or ("FAILED: " .. errFirstLine)
                        ))
                        if ok then
                            target.hooked = true
                            break
                        end
                    end
                    if not target.hooked then
                        allDone = false
                    else
                        anyHookedThisGroup = true
                    end
                else
                    anyHookedThisGroup = true
                end
            end

            if anyHookedThisGroup and provenLoadedAtRound == nil then
                provenLoadedAtRound = round
            end

            if allDone then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] all candidate hooks registered — stopping retry loop")
                return
            end
            if provenLoadedAtRound and (round - provenLoadedAtRound) >= EARLY_EXIT_ROUNDS_AFTER_PROOF then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] stopping early — class proven loaded at round " .. provenLoadedAtRound .. " (a sibling hook succeeded), remaining unresolved names are very likely just wrong, not a timing issue (see FAILED lines above for exact names tried)")
                return
            end
            if round >= MAX_RADIAL_HOOK_ROUNDS then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] giving up after " .. round .. " rounds — class never proved loaded (no sibling ever hooked) — some functions never resolved (see FAILED lines above for exact names tried)")
                return
            end
            local rescheduleOk = pcall(function()
                ExecuteInGameThreadWithDelay(RADIAL_HOOK_RETRY_MS, function()
                    safe_call(runner)
                end)
            end)
            if not rescheduleOk then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] could not schedule a retry round (ExecuteInGameThreadWithDelay failed) — stopping after round " .. round)
            end
        end
        return runner
    end

    make_hook_round_runner(RADIAL_MENU_CLASS, radialHookTargets, "RADIAL-WATCH")()
    -- Hundred-and-thirty-sixth pass (2026-09-03) FIX, REAL LAG SOURCE FOUND:
    -- these two watches fire on the game's generic "interactable object"
    -- prompt — which triggers for EVERY interactable in the world (berries,
    -- logs, stones, the PalBox, not just Pals) every time it appears/
    -- disappears as the player looks around. Dragón reported still feeling
    -- lag after the personality fix; breaking the log down by volume (not
    -- just checking the tags already suspected) showed 1529 of 4630 lines
    -- in one ~6-minute session — a full third of the whole log — came from
    -- here. The research question these were added for (how does aiming
    -- "4" at a specific Pal work) was fully answered back in the
    -- seventy-ninth/eightieth passes (WBP_WorkerRadialMenu) — nobody ever
    -- came back to turn these off. Commented out, not deleted, same
    -- convention as SelectResponseBySenses in OtomoWatch.lua — the
    -- candidate-name research (which real UFunction names exist on these
    -- two classes) stays valuable documentation even with the hooks off.
    -- make_hook_round_runner(INDICATOR_CANVAS_CLASS, indicatorCanvasTargets, "INDICATOR-WATCH")()
    -- make_hook_round_runner(INDICATOR_UI_CLASS, indicatorUITargets, "INDICATOR-WATCH")()
    make_hook_round_runner(WORKER_MENU_CLASS, workerMenuTargets, "WORKER-WATCH")()

    -- Hundred-and-thirty-eighth pass (2026-09-04) addendum, REMOVED
    -- hundred-and-fifty-eighth pass: this watched for Dragón's real Cheer
    -- emote to confirm which of the 9 numbered classes it was — but the
    -- player-Cheer feature itself was abandoned two passes later (do_play
    -- crashed twice trying to call PlayAction, pulled out entirely — see
    -- hook-points.md, hundred-and-forty-fifth pass) and nobody ever
    -- turned this watch off. Confirmed dead with real numbers, not a
    -- guess: 405 log lines across a later session, ZERO successes, ever
    -- — "OnBeginAction" never resolved on any of the 9 classes in any
    -- round. Dragón caught this directly asking whether console failures
    -- were "still needed or just trash that accumulated" — this was
    -- exactly that. Removed rather than left retrying forever for a
    -- feature this project isn't using. If Cheer's player-emote half
    -- ever gets a real, separate investigation later, the real class
    -- (BP_Action_Emote_0_C, confirmed via Dragón's own object dump) and
    -- the emote-index diagnostic above are still there to build on — this
    -- specific OnBeginAction hook attempt just never worked and doesn't
    -- need to keep trying.
    make_hook_round_runner(WORKER_MENU_OVERLAY_CLASS, workerMenuOverlayTargets, "WORKER-WATCH")()

    -- ---------------------------------------------------------------
    -- Eighty-first pass (2026-09-03): REVERTED to watch-only in the
    -- eighty-second pass — see that pass's notes below and in
    -- Trust.lua/Capture.lua for the full incident.
    --
    -- What this originally did: on a Pet(4)/Feed(3) selection through the
    -- real vanilla worker wheel, resolve the target Pal and call
    -- `Interaction.OnWildPalPetted(pal)` directly — the same call F9/F10
    -- make. That exposed a pre-existing, unrelated bug in Trust.lua (no
    -- ownership check before the capture-threshold logic) and caused a
    -- REAL, unwanted re-capture of Dragón's own already-owned base Pals
    -- (a boss-tier Petallia got auto-added to his party and dropped
    -- capture-reward loot; a second Pal was also silently re-captured).
    --
    -- Trust.lua/Capture.lua now have a hard ownership guard
    -- (Capture.IsAlreadyOwned, fails safe toward "treat as owned") that
    -- makes this specific failure impossible even if this hook (or
    -- F9/F10, or anything else) calls OnWildPalPetted on an owned Pal —
    -- but Dragón was right to call the DIRECTION itself premature: wiring
    -- automatic real behavior into a UI action that fires constantly
    -- during completely normal play (petting/feeding your own base Pals)
    -- is a much bigger blast radius than F9/F10 ever was, and deserves
    -- more caution than one guard fixed in the same session it broke.
    -- Reverted to logging only — same as every other confirmed-real hook
    -- in this file — until this is revisited deliberately, not as a side
    -- effect of chasing the next research question.
    local ok81, err81 = pcall(function()
        RegisterHook(WORKER_MENU_CLASS .. ":OnSelectedMenu_Internal", function(Context, IndexParam)
            local index = hook_get(IndexParam)
            Logger.log("[PalBonds/Interaction] [WORKER-WATCH] OnSelectedMenu_Internal fired — index=" .. tostring(index) .. " (watch-only, see eighty-second pass — no longer calls OnWildPalPetted)")
        end)
    end)
    if not ok81 then
        Logger.log("[PalBonds/Interaction] [WORKER-WATCH] could not re-install the watch-only OnSelectedMenu_Internal hook: " .. tostring(err81))
    end

    -- Native companion hook (not a Blueprint-path guess — a real function
    -- confirmed straight in Pal.hpp, UPalOtomoHolderComponentBase). Not
    -- believed to be the actual Care/Feed trigger (see caveat above — its
    -- enum is a combat-stance toggle) but essentially free to watch for
    -- direct confirmation either way.
    local okOtomoOrder = pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:RequestSetOtomoOrder", function(Context, OrderType)
            local self_ = hook_get(Context)
            local orderType = hook_get(OrderType)
            Logger.log(string.format(
                "[PalBonds/Interaction] [RADIAL-WATCH] RequestSetOtomoOrder fired — holder=%s OrderType=%s",
                hook_describe(self_), tostring(orderType)
            ))
        end)
    end)
    if not okOtomoOrder then
        Logger.log("[PalBonds/Interaction] [RADIAL-WATCH] could not install RequestSetOtomoOrder watch hook")
    end

    -- ---------------------------------------------------------------
    -- Hundred-and-twenty-first pass (2026-09-03): two genuinely new, never-
    -- hooked native functions found via `repak`+`strings` on the
    -- RemoteAccessEverything reference mod's own re-packaged copy of
    -- WBP_PlayerRadialMenu (a lead first noted back around the sixty-fifth
    -- pass as "Otomo/companion-feed-inventory specific, not yet tested or
    -- hooked", then never followed up on until now that the hundred-and-
    -- twentieth pass's food-feeding thread actually needs it). Both are
    -- declared on the NATIVE base class `UPalUIPlayerRadialMenuBase`
    -- (confirmed in Pal.hpp — not Blueprint-only, so no retry-loop is
    -- needed; native classes are loaded from game boot same as
    -- PalOtomoHolderComponentBase above):
    --   `void OpenOtomoFeedInventory();` — no args, no return. Real
    --   candidate for the exact moment the real Feed action opens the
    --   actual food-picker inventory UI.
    --   `void SelectedFeed(const FPalItemSlotId& ItemSlotId, const int64
    --   itemNum);` — same shape as the already-watched
    --   `APalMonsterCharacter:SelectedFeedingItem` (hundred-and-third
    --   pass), but on the WIDGET class instead of the Pal actor — a
    --   plausible "player picked this exact food item in the UI" event
    --   that fires BEFORE SelectedFeedingItem does, on the Otomo-specific
    --   path SelectedFeedingItem itself never covers (confirmed
    --   hundred-and-sixth pass: base-worker and active-Otomo feeding are
    --   two different real functions, and SelectedFeedingItem is the
    --   worker one).
    -- WATCH ONLY, same zero-side-effect discipline as every hook in this
    -- file. Purpose: get an AUTOMATIC, permanent log signal for exactly
    -- what the hundred-and-twentieth pass had to check by eye via manual
    -- Live View dumps — does either of these fire during a real Otomo
    -- feed, and (the real open question) does either ever fire during a
    -- substituted-wild-Pal Feed attempt through the "4" menu.
    local okOpenFeedInv = pcall(function()
        RegisterHook("/Script/Pal.PalUIPlayerRadialMenuBase:OpenOtomoFeedInventory", function(Context)
            local self_ = hook_get(Context)
            Logger.log(string.format(
                "[PalBonds/Interaction] [FOOD-DIAG] OpenOtomoFeedInventory fired — widget=%s",
                hook_describe(self_)
            ))
        end)
    end)
    if not okOpenFeedInv then
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] could not install OpenOtomoFeedInventory watch hook (name may need adjusting)")
    end

    local okSelectedFeed = pcall(function()
        RegisterHook("/Script/Pal.PalUIPlayerRadialMenuBase:SelectedFeed", function(Context, ItemSlotId, itemNum)
            local self_ = hook_get(Context)
            local slotId = hook_get(ItemSlotId)
            local num = hook_get(itemNum)
            local containerGuid = safe_call(function() return slotId and slotId.ContainerId and tostring(slotId.ContainerId.ID) end)
            local slotIndex = safe_call(function() return slotId and slotId.SlotIndex end)
            Logger.log(string.format(
                "[PalBonds/Interaction] [FOOD-DIAG] SelectedFeed fired — widget=%s ContainerId=%s SlotIndex=%s itemNum=%s",
                hook_describe(self_), tostring(containerGuid), tostring(slotIndex), tostring(num)
            ))
        end)
    end)
    if not okSelectedFeed then
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] could not install SelectedFeed watch hook (name may need adjusting)")
    end

    -- Hundred-and-twenty-sixth pass (2026-09-03): two more real function
    -- paths, confirmed via Dragón's own Live View "Dump as Function"
    -- captures (saved under ue4ss/IndividualObjectDumps/) rather than
    -- guessed. Both watch-only, same zero-side-effect discipline as
    -- everything else in this file.
    --
    -- `ReadPlayerFeedItemTo` — real, confirmed native path:
    -- /Script/Pal.PalPlayerUtility:ReadPlayerFeedItemTo (a
    -- BlueprintFunctionLibrary-style utility class, same category as the
    -- already-trusted PalUtility/PalItemUtility). First seen as an
    -- unidentified temp-variable name inside BP_ActionPairBehavior_FeedItem_C's
    -- own compiled graph (hundred-and-twenty-fifth pass) — this confirms
    -- its real declaring class. Likely the function that resolves which
    -- item a player picked to feed a given target; exact parameter shapes
    -- unknown, so this hook logs generically (self + first 3 args
    -- described the same way every other native watch in this file does)
    -- rather than assuming a signature. Since it's native, no Blueprint
    -- retry-loop is needed — same as RequestSetOtomoOrder above.
    local okReadFeedItem = pcall(function()
        RegisterHook("/Script/Pal.PalPlayerUtility:ReadPlayerFeedItemTo", function(Context, A, B, C)
            Logger.log(string.format(
                "[PalBonds/Interaction] [FOOD-DIAG] ReadPlayerFeedItemTo fired — arg1=%s arg2=%s arg3=%s",
                hook_describe(hook_get(A)), hook_describe(hook_get(B)), hook_describe(hook_get(C))
            ))
        end)
    end)
    if not okReadFeedItem then
        Logger.log("[PalBonds/Interaction] [FOOD-DIAG] could not install ReadPlayerFeedItemTo watch hook (name may need adjusting)")
    end

    -- "On Trigger Open Inventory Menu" — real, confirmed Blueprint path:
    -- /Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener.WBP_PalHUD_InGame_InputListener_C
    -- (the game's main HUD input-listener widget — likely the top-level
    -- trigger for opening ANY inventory-flavored menu, possibly one level
    -- above OpenOtomoFeedInventory in the real call chain). Blueprint, so
    -- uses the same bounded round-runner as every other UI class in this
    -- file, in case it isn't loaded yet at Init() time (though its own
    -- dump showed RF_WasLoaded, suggesting it's core HUD and loads early).
    local INVENTORY_LISTENER_CLASS = "/Game/Pal/Blueprint/UI/WBP_PalHUD_InGame_InputListener.WBP_PalHUD_InGame_InputListener_C"
    local inventoryListenerTargets = {
        { tag = "OnTriggerOpenInventoryMenu", candidates = {"On Trigger Open Inventory Menu"} },
    }
    make_hook_round_runner(INVENTORY_LISTENER_CLASS, inventoryListenerTargets, "INVENTORY-WATCH")()

    -- ---------------------------------------------------------------
    -- Eighty-third pass (2026-09-03): research step toward Dragón's
    -- preferred direction — make the REAL vanilla radial menu act on the
    -- wild Pal you're aiming at, instead of building a custom menu from
    -- scratch (which would need real icon art/animations/sound this
    -- project has no way to produce well) or forcing the menu open on an
    -- unsupported target (the same risky category that caused the
    -- eighty-second pass's incident).
    --
    -- The idea: the "press 4 with no aim target" wheel must internally
    -- ask SOME function "who is my target Otomo" before it opens. Found a
    -- strong, real candidate in the SDK dump: `TryGetSpawnedOtomo()` on
    -- `UPalOtomoHolderComponentBase` — a plain, no-argument, NATIVE
    -- getter (not a Blueprint-only function) returning the player's
    -- current active Otomo actor. If the menu really reads this (or
    -- something equivalent) to decide its target, and if UE4SS hooks can
    -- override a native function's RETURN value here (confirmed possible
    -- in principle — `BPML_GenericFunctions`'s bundled
    -- `ConstructPersistentObject` custom event uses `OutParam:set(...)`
    -- to write a value back through a hook — but not yet confirmed for
    -- overriding an ordinary function's return specifically), we could
    -- redirect the ENTIRE existing, fully-polished Pet/Feed pipeline onto
    -- a wild Pal by substituting just this one value, with ZERO new UI
    -- work and no need to touch Trust/Capture at all.
    --
    -- Eighty-fourth pass (2026-09-03): the eighty-third pass's no-op
    -- `ReturnValue:set()` test already proved the override mechanism works
    -- (474/474 calls succeeded in one ~2min session) — no need to keep
    -- re-testing that every single call. That same session showed
    -- TryGetSpawnedOtomo firing ~4x/second even with no menu open at all
    -- (clearly read by other systems too — indicator UI, AI, who knows),
    -- which is the same "per-tick spam" shape as the eightieth pass's
    -- UpdateInteractTargetName lag bug. So this pass dedupes: only log
    -- when the described return value actually CHANGES from the last
    -- call. That session also surfaced a real anomaly worth watching for:
    -- for a stretch, the return's GetFullName() call started throwing
    -- (hook_describe falls back to the bare `UObject: 0x...` tostring),
    -- with a DIFFERENT address every ~3 seconds — consistent with UE4SS's
    -- wrapper for a null/invalid pointer, i.e. TryGetSpawnedOtomo can and
    -- does return nothing while the Otomo is between states.
    --
    -- Bigger finding from that same session: WORKER-WATCH gave up after 8
    -- rounds with EVERY candidate failing to register — WBP_WorkerRadialMenu
    -- never loaded into memory at all, meaning the aim-based Worker Menu
    -- never actually opened once, on the party Pal OR the wild Pal Dragón
    -- tested against. Every one of that session's 7 "4" presses instead
    -- went through the no-aim WBP_PlayerRadialMenu_C (RADIAL-WATCH's
    -- IsAnyMenuOpened fired right on cue), which is hardcoded to act on
    -- TryGetSpawnedOtomo's Otomo — fully explaining why the wild Pal was
    -- ignored both times, with no override ever having been attempted.
    --
    -- Eighty-fifth pass (2026-09-03): Dragón's next test (aimed "4" at a
    -- wild Pal — no menu-visible effect — then summoned his Otomo and pet
    -- it for real) gave two clean, comparable `OnDecidedInstructionCare`
    -- fires: arg1=false while TryGetSpawnedOtomo was returning an
    -- unresolvable/likely-null object (Otomo not out yet), and arg1=true
    -- once TryGetSpawnedOtomo had just returned a real, resolvable Otomo
    -- (`BP_SheepBall_C`) a moment before. That strongly says this
    -- function's bool argument is an OUTPUT reporting whether a valid
    -- target was found — not an input we could redirect — and the
    -- function itself takes no Pal reference as a parameter at all. So the
    -- eighty-fourth pass's plan (hook `OnDecidedInstructionCare` directly)
    -- is a dead end: by the time it fires, the target has already been
    -- resolved elsewhere, almost certainly via TryGetSpawnedOtomo itself
    -- or an equivalent internal call.
    --
    -- That puts the redirect back on TryGetSpawnedOtomo after all — but
    -- SCOPED, not global, to avoid the exact risk that ruled it out last
    -- pass. `radialMenuActionWindowOpen` (declared near the top of this
    -- file) is only ever true for the few hundred milliseconds between the
    -- confirmed-real `Can Open Player Action Menu` and `CloseMenu` fires —
    -- i.e. only while a "4"-press's menu is actually open — with a 1.5s
    -- safety timeout in case `CloseMenu` somehow doesn't fire. Outside
    -- that window (the ~4/sec ambient calls from whatever else reads this
    -- getter), behavior is 100% untouched — this is the same
    -- non-negotiable lesson from the eighty-second pass incident: never
    -- change a shared function's behavior for more callers than intended.
    --
    -- Inside the window, substitution only happens if `find_targeted_pal`
    -- (the exact same look-based targeting F9/F10 already use safely)
    -- finds a Pal you're aiming at that ISN'T the real Otomo, AND
    -- `Capture.IsAlreadyOwned` confirms it's genuinely wild.
    --
    -- NINETY-SIXTH PASS (2026-09-03) FIX: this used to cap the actual
    -- substitution to ONE attempt per window (`radialMenuRedirectedThisWindow`).
    -- Dragón reported Pet/Feed showing up grayed-out/unclickable every time
    -- he tried this on a wild Pal. Re-reading the log showed WHY that
    -- one-shot cap is a real problem, not just noise-reduction: within the
    -- same ~1.5s window, TryGetSpawnedOtomo gets called MULTIPLE times
    -- (this getter fires ~4x/second per the eighty-fourth pass) — our
    -- redirect only ever caught the FIRST of those calls. Whatever later
    -- decides the buttons' enabled/grayed state very plausibly reads a
    -- LATER call that we deliberately left un-redirected, meaning the real
    -- Otomo (or nothing) was still what fed the button-enable check the
    -- whole time — this may have nothing to do with a deeper "is this a
    -- real party member" wall at all, just our own once-only cap missing
    -- the call that mattered. Removed the cap: substitution now applies to
    -- EVERY qualifying call for as long as the window stays open (still
    -- fully gated by `radialMenuActionWindowOpen`, still wild-Pal-only,
    -- still excludes the player) — cheap and idempotent, since it just
    -- re-runs the same aim check and returns the same wild Pal each time
    -- your aim hasn't changed. Only the "EXPERIMENTAL: substituting..."
    -- log line itself is still deduped (see lastRedirectedWildPalName
    -- below) so this doesn't turn into another repeat-log spam source.
    --
    -- THIS IS THE FIRST LIVE ATTEMPT AT AN ACTUAL SUBSTITUTION, not just a
    -- no-op test. It is still an open question whether the game's own
    -- Pet/Feed logic, once handed a non-Otomo Pal here, will actually
    -- treat it correctly — that function doesn't receive a Pal reference
    -- as a parameter, so whatever runs the actual petting animation almost
    -- certainly re-reads this SAME getter rather than being passed a
    -- value, which is the whole bet this pass is making. If it goes wrong,
    -- the blast radius is contained: no Trust/Capture code is touched by
    -- this substitution at all, and the window auto-closes within 1.5s
    -- either way.
    local lastLoggedOtomo = nil
    local okOtomoGetter = pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:TryGetSpawnedOtomo", function(Context) end, function(Context, ReturnValue)
            local returned = hook_get(ReturnValue)
            local desc = hook_describe(returned)
            if desc ~= lastLoggedOtomo then
                lastLoggedOtomo = desc
                Logger.log(string.format(
                    "[PalBonds/Interaction] [OTOMO-GETTER-WATCH] TryGetSpawnedOtomo now returning %s (only logged on change — see eighty-fourth pass)",
                    desc
                ))
            end

            if radialMenuActionWindowOpen then
                local ok, err = pcall(function()
                    local player = FindFirstOf("PalPlayerCharacter")
                    if not player or not player:IsValid() then return end
                    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
                    if not originLoc then
                        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
                    end
                    if not originLoc then return end
                    local controlRot = safe_call(function() return player:GetControlRotation() end)
                    if not controlRot then return end
                    local forward = rotator_to_forward(controlRot)

                    -- Eighty-seventh pass (2026-09-03) FIX, REAL INCIDENT
                    -- FOUND: the eighty-fifth pass excluded only the
                    -- current Otomo (`returned`) from `find_targeted_pal`,
                    -- not the player. Dragón's live log showed it twice
                    -- substituting `BP_Player_Female_C` — his OWN character
                    -- — in place of the Otomo, because APalPlayerCharacter
                    -- apparently satisfies the same "PalCharacter" scan
                    -- this function uses, and `Capture.IsAlreadyOwned`
                    -- read an all-zero owner GUID off the player's own
                    -- shared character-parameter component and wrongly
                    -- called that "wild". No harm reached the player this
                    -- time — the real `AddFriendShip` both times landed on
                    -- the real Otomo's parameter, meaning whatever actually
                    -- runs the pet animation does NOT re-read this getter
                    -- (the eighty-fifth pass's open question is answered:
                    -- it doesn't) — but this was luck, not a guarantee, and
                    -- is exactly the kind of gap this project has been
                    -- burned by before (eighty-second pass). Fixed at the
                    -- source: exclude the PLAYER from candidates (the same
                    -- proven-safe exclusion do_pet/do_feed already use),
                    -- not the Otomo — and added an explicit belt-and-
                    -- suspenders re-check afterward in case any future
                    -- exclusion-by-name edge case slips through.
                    --
                    -- Hundred-and-second pass: throttled per-call cost —
                    -- reuse the last real find, IsValid()-rechecked, if
                    -- it's still fresh; otherwise pay for a real scan.
                    local wildPal = nil
                    local now = safe_call(function() return os.clock() end)
                    if cachedRedirectWildPal and lastRedirectComputeClock and now
                        and (now - lastRedirectComputeClock) < REDIRECT_RECOMPUTE_INTERVAL_S then
                        local stillValid = safe_call(function() return cachedRedirectWildPal:IsValid() end)
                        if stillValid then
                            wildPal = cachedRedirectWildPal
                        end
                    end
                    if not wildPal then
                        local scanStart = now
                        wildPal = find_targeted_pal(originLoc, forward, player)
                        local scanEnd = safe_call(function() return os.clock() end)
                        if scanStart and scanEnd then
                            -- Real evidence, not a guess: this is throttled
                            -- to at most ~4/sec (the recompute interval
                            -- above) rather than the raw hook-fire rate, so
                            -- logging every real scan stays cheap and gives
                            -- Dragón's next test concrete ms numbers to
                            -- confirm or rule out this as the hitch source.
                            Logger.log(string.format(
                                "[PalBonds/Interaction] [RADIAL-REDIRECT-PERF] find_targeted_pal scan took %.2fms",
                                (scanEnd - scanStart) * 1000
                            ))
                        end
                        cachedRedirectWildPal = wildPal
                        lastRedirectComputeClock = now
                    end
                    if not wildPal or not wildPal:IsValid() then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] menu window open but not aiming at any Pal — leaving the real Otomo in place")
                        return
                    end

                    local playerName = safe_call(function() return player:GetFullName() end)
                    local wildPalName = safe_call(function() return wildPal:GetFullName() end)
                    if playerName and wildPalName and playerName == wildPalName then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] SAFETY: find_targeted_pal returned the player itself — refusing to substitute, leaving the real Otomo in place")
                        return
                    end

                    local returnedName = safe_call(function() return returned and returned:GetFullName() end)
                    if returnedName and wildPalName and returnedName == wildPalName then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] aimed Pal is already the current Otomo — nothing to substitute")
                        return
                    end

                    local isWild = Capture.IsAlreadyOwned and (not Capture.IsAlreadyOwned(wildPal))
                    if not isWild then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] the aimed Pal is already owned — leaving the real Otomo in place (this system is for wild Pals only)")
                        return
                    end

                    -- NINETY-SIXTH PASS: dedupe just the announcement, not
                    -- the actual substitution below — with the once-only
                    -- cap removed, this branch can now run several times a
                    -- second for as long as you keep aiming at the same
                    -- wild Pal within the window; only log again if the
                    -- aimed Pal itself changes.
                    if lastRedirectedWildPalName ~= wildPalName then
                        lastRedirectedWildPalName = wildPalName
                        Logger.log(string.format(
                            "[PalBonds/Interaction] [RADIAL-REDIRECT] EXPERIMENTAL: substituting wild %s in place of the Otomo for this menu action (every qualifying call now, not just the first — see ninety-sixth pass) — watch closely",
                            hook_describe(wildPal)
                        ))
                        -- Hundred-and-twenty-first pass: one-shot per newly-
                        -- aimed wild Pal (same dedup gate as the log line
                        -- above, never per-tick) — tests the corrected
                        -- party-membership candidate (UPalPlayerPartyPalHolder,
                        -- see diagnose_party_membership's own comment) against
                        -- THIS specific substitution, read-only.
                        diagnose_party_membership(wildPal, get_individual_handle(wildPal))
                    end
                    -- Hundredth pass (2026-09-03) FIX: this is now the ONLY
                    -- place `radialMenuRedirectedThisWindow` is set true —
                    -- it used to be set unconditionally the moment the
                    -- window was open, before any of the checks above ran,
                    -- which meant it was ALSO true for the player's own
                    -- real Otomo (aimed-at-your-own-Pal case never reaches
                    -- here — every branch above returns early first). That
                    -- was harmless while the flag was "visibility only"
                    -- (ninety-sixth pass), but the ninety-ninth pass turned
                    -- it into the hard gate for actually firing do_pet()/
                    -- do_feed() — so it needs to mean what its name says:
                    -- true only when a wild Pal is genuinely substituted
                    -- this window, never for the player's real Otomo.
                    radialMenuRedirectedThisWindow = true
                    local setOk, setErr = pcall(function()
                        ReturnValue:set(wildPal)
                    end)
                    if not setOk then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] substitution failed: " .. tostring(setErr))
                    end

                    -- Hundred-and-twenty-third pass (2026-09-03): the
                    -- actual next experiment, per the hundred-and-twenty-
                    -- second pass's finding — `OpenOtomoFeedInventory`
                    -- fires identically whether or not the getter above is
                    -- overridden, but `SelectedFeed` (a real item actually
                    -- getting picked) never does for a substituted wild
                    -- Pal. That means whatever gates real selection reads
                    -- something OTHER than a fresh `TryGetSpawnedOtomo()`
                    -- call — the leading candidate is this exact menu
                    -- widget's OWN cached `SpawnedOtomo` variable (real,
                    -- confirmed via the RemoteAccessEverything string dump,
                    -- sixty-fifth pass), set once early in the menu's own
                    -- open sequence rather than re-read from the getter
                    -- each time. `lastOpenMenuWidget` (captured off
                    -- `CanOpenPlayerActionMenu`'s own Context, hundred-and-
                    -- twenty-third pass) is this project's live reference
                    -- to that exact widget instance.
                    --
                    -- This is a NEW category of write for this project —
                    -- not overriding a function's return value through the
                    -- hook mechanism (already done above, and via
                    -- IndividualHandle/OnClose for the Worker Menu), but
                    -- writing a plain Blueprint variable directly on a live
                    -- UI widget. Risk is still low relative to everything
                    -- this project has been cautious about before: it's a
                    -- transient UI widget's own display state, not save
                    -- data, not a native gameplay function call, and it
                    -- only ever runs in the same narrow, already-gated
                    -- window as the getter override (genuinely wild Pal
                    -- confirmed, real Otomo excluded, once per newly-aimed
                    -- Pal). Wrapped in its own pcall, logged independently
                    -- of the getter-override result so a live test shows
                    -- clearly whether the field even exists under this
                    -- name/type on this build.
                    if lastOpenMenuWidget then
                        local widgetValid = safe_call(function() return lastOpenMenuWidget:IsValid() end)
                        if widgetValid then
                            local fieldSetOk, fieldSetErr = pcall(function()
                                lastOpenMenuWidget.SpawnedOtomo = wildPal
                            end)
                            Logger.log(string.format(
                                "[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] widget.SpawnedOtomo = wild %s -> %s",
                                hook_describe(wildPal),
                                fieldSetOk and "ok" or ("FAILED: " .. tostring(fieldSetErr))
                            ))
                        else
                            Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] lastOpenMenuWidget is no longer valid — skipping field write")
                        end
                    else
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] no lastOpenMenuWidget captured yet this window — skipping field write")
                    end
                end)
                if not ok then
                    Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] error while attempting redirect: " .. tostring(err))
                end
            end
        end)
    end)
    if not okOtomoGetter then
        Logger.log("[PalBonds/Interaction] [OTOMO-GETTER-WATCH] could not install TryGetSpawnedOtomo watch hook (name or pre+post signature may need adjusting)")
    end

    -- ---------------------------------------------------------------
    -- Eighty-eighth pass (2026-09-03) — THE ACTUAL FIX ATTEMPT for "the
    -- real vanilla Worker Radial Menu (Pet/Feed/etc, the '4' wheel) does
    -- nothing when aimed at a WILD Pal."
    --
    -- Root cause, confirmed by comparing two real live JSON dumps of
    -- PalHUDDispatchParameter_WorkerRadialMenu (one from pressing 4 on the
    -- real owned Kitsunebi partner, one from pressing 4 on a wild Foxparks,
    -- both captured via Live View's "Dump as JSON"):
    --
    --   owned: IndividualHandle = PalIndividualCharacterHandle_2147480691
    --          OnClose          = (BP_Kitsunebi_C_2147425992.OnSelectedOrderWorkerRadialMenu)
    --   wild:  IndividualHandle = PalIndividualCharacterHandle_2147480691   <- SAME OBJECT
    --          OnClose          = ()                                       <- EMPTY
    --
    -- Two things are wrong for the wild case, not just one:
    --   1. OnClose (a single/dynamic delegate, DECLARE_DYNAMIC_DELEGATE
    --      style — hence the "(Object.Function)" single-target format, not
    --      a multicast list) is never bound to anything, so selecting a
    --      menu option has no completion callback to run at all.
    --   2. IndividualHandle is IDENTICAL in both dumps — the exact same
    --      handle object, not just the same handle by coincidence. That
    --      means even if OnClose were bound, the handler would still act
    --      on whatever Pal that ONE shared/stale handle actually points
    --      to (almost certainly the real Otomo, or some other cached
    --      handle) — never the wild Pal actually being aimed at.
    --
    -- The fix: intercept the dispatch parameter right before it's used, and
    -- rewrite BOTH fields to point at the aimed wild Pal specifically.
    --
    -- Hook point: APalHUDInGame:PushWidgetStackableUI(WidgetClass,
    -- Parameter) — a real, confirmed-in-SDK native function (Pal.hpp /
    -- shared Lua type stubs both show it taking exactly
    -- (TSubclassOf<UPalUserWidgetStackableUI>, UPalHUDDispatchParameterBase*)
    -- and returning an FGuid). This is the moment the ALREADY-CONSTRUCTED
    -- Parameter object is handed off to actually open the widget — late
    -- enough that every field the menu will read is already set by
    -- whatever built it, early enough that nothing has READ those fields
    -- yet. UPalHUDService:Push has the identical signature and is very
    -- likely just a thin wrapper around the same call, so it's hooked too
    -- (whichever one the real code path actually uses will fire; hooking
    -- both is harmless since each bails out immediately for every Parameter
    -- that isn't a WorkerRadialMenu one — every other UI in the game, chest,
    -- inventory, dialogs, etc., all go through this same function and must
    -- be left completely untouched).
    --
    -- Unlike the eighty-fifth pass's TryGetSpawnedOtomo redirect, this does
    -- NOT need the radialMenuActionWindowOpen scoping hack — that was only
    -- needed because TryGetSpawnedOtomo fires ~4x/second ambiently for
    -- unrelated systems. PushWidgetStackableUI only fires when a stackable
    -- UI widget is actually being pushed, i.e. exactly when a menu is
    -- opening. Much more surgical on its own.
    --
    -- Safety gates, same discipline as every real-effect hook in this file:
    --   - Early-out unless the Parameter's own class name contains
    --     "WorkerRadialMenu" (checked via GetFullName(), which always
    --     starts with the class name) — every other UI push is a no-op.
    --   - Uses find_targeted_pal (the exact same proven look-based
    --     targeting F9/F10 and the RADIAL-REDIRECT hack already use) to
    --     find what's actually being aimed at, excluding the player.
    --   - Capture.IsAlreadyOwned gates to WILD Pals only — if the aimed Pal
    --     (or nothing) resolves as already-owned/unclear, this leaves the
    --     Parameter's fields completely untouched, so the existing, already
    --     -working owned-Pal case (real Otomo, OnClose already correctly
    --     bound by the game itself) is never interfered with.
    --   - Every native call/write is wrapped in pcall; a failure here logs
    --     and gives up on that one menu-open, it never propagates.
    --
    -- STILL UNCONFIRMED, first live attempt: the exact UE4SS Lua API for
    -- binding a single/dynamic delegate property. Best-evidenced guess,
    -- consistent with how UE4SS exposes FScriptDelegate-style properties:
    --   Parameter.OnClose:Bind(wildPal, "OnSelectedOrderWorkerRadialMenu")
    -- `OnSelectedOrderWorkerRadialMenu` is confirmed real and universal —
    -- declared on APalMonsterCharacter (Pal.hpp), the base class for EVERY
    -- Pal actor, wild or owned, so the exact function this call needs
    -- already exists on the wild Pal itself. If `:Bind(...)` isn't the
    -- right method name/signature, the pcall around it will catch the
    -- error and log the exact Lua error message, which should say either
    -- "attempt to call a nil value" (wrong method name — OnClose isn't a
    -- table with a Bind key) or a specific argument-count/type complaint
    -- (right method, wrong call shape) — real evidence to iterate from,
    -- same trial-and-error discipline as every other native call in this
    -- project.
    -- Eighty-ninth pass (2026-09-03) DIAGNOSTIC addition: three real test
    -- sessions in a row (spamming "4" at a clean-ground wild Lamball,
    -- close range, nothing else nearby) all showed ZERO [WORKER-BIND-FIX]
    -- fires AND WORKER-WATCH still giving up after all 8 rounds — the
    -- WBP_WorkerRadialMenu_C Blueprint class never loads at all this
    -- session, on ANY target, wild or owned. Every single "4" press opens
    -- the no-aim Player Menu instead, confirmed directly by Dragón ("the
    -- radial menu that popped up was always the one from the active
    -- pal"). That raises a real open question this diagnostic exists to
    -- answer: does `PushWidgetStackableUI`/`PalHUDService:Push` even fire
    -- AT ALL for the Player Menu (or anything) during a "4" press, or is
    -- EVERY radial menu (Player and Worker alike) actually dispatched
    -- through some other, still-unidentified function — which would mean
    -- this whole hook point is watching the wrong door entirely,
    -- regardless of aim precision. This logs the class of literally every
    -- widget pushed through either hooked function (deduped to only log
    -- on change, same discipline as OTOMO-GETTER-WATCH, since some UI
    -- panels may push repeatedly) — cheap, and answers the question
    -- directly from the very next test.
    local lastLoggedPushedClass = nil
    -- Ninetieth pass (2026-09-03): extracted the actual field-rewrite logic
    -- out of try_fix_worker_menu_parameter so it can be reused from a
    -- SECOND, real interception point found this pass (see below) — the
    -- eighty-eighth/eighty-ninth passes' PushWidgetStackableUI/
    -- PalHUDService:Push hooks are proven (via the diagnostic) to never
    -- carry WorkerRadialMenu traffic at all, even though the Worker Menu
    -- genuinely did open for the first time this session (full
    -- Construct/OnSetup/OnAnyUIPushed/OnSelectedEvent/Destruct sequence,
    -- WORKER-WATCH confirmed) — meaning this menu is NOT dispatched through
    -- either hooked function. Kept as a no-cost diagnostic fallback.
    local function apply_wild_fix_to_worker_parameter(parameter, hookLabel)
        local paramDesc = hook_describe(parameter)
        Logger.log(string.format(
            "[PalBonds/Interaction] [WORKER-BIND-FIX] %s saw a WorkerRadialMenu Parameter: %s",
            hookLabel, paramDesc
        ))

        local ok, err = pcall(function()
            local player = FindFirstOf("PalPlayerCharacter")
            if not player or not player:IsValid() then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] no local player — skipping")
                return
            end
            local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
            if not originLoc then
                originLoc = safe_call(function() return player:K2_GetActorLocation() end)
            end
            if not originLoc then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not read player/camera location — skipping")
                return
            end
            local controlRot = safe_call(function() return player:GetControlRotation() end)
            if not controlRot then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not read control rotation — skipping")
                return
            end
            local forward = rotator_to_forward(controlRot)

            local aimedPal = find_targeted_pal(originLoc, forward, player)
            if not aimedPal or not aimedPal:IsValid() then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] menu opening but not aiming at any Pal — leaving Parameter untouched")
                return
            end

            local playerName = safe_call(function() return player:GetFullName() end)
            local aimedName = safe_call(function() return aimedPal:GetFullName() end)
            if playerName and aimedName and playerName == aimedName then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] SAFETY: find_targeted_pal returned the player itself — refusing to touch Parameter")
                return
            end

            local isWild = Capture.IsAlreadyOwned and (not Capture.IsAlreadyOwned(aimedPal))
            if not isWild then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] aimed Pal (" .. tostring(aimedName) .. ") is already owned — leaving Parameter untouched, this fix is for wild Pals only")
                return
            end

            local wildHandle = get_individual_handle(aimedPal)
            if not wildHandle or not wildHandle:IsValid() then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] wild " .. tostring(aimedName) .. " has no readable IndividualHandle — cannot safely redirect, leaving Parameter untouched")
                return
            end

            Logger.log(string.format(
                "[PalBonds/Interaction] [WORKER-BIND-FIX] EXPERIMENTAL: redirecting WorkerRadialMenu Parameter onto wild %s — setting IndividualHandle and binding OnClose",
                tostring(aimedName)
            ))

            local setHandleOk, setHandleErr = pcall(function()
                parameter.IndividualHandle = wildHandle
            end)
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] IndividualHandle write: " .. (setHandleOk and "ok" or ("FAILED: " .. tostring(setHandleErr))))

            local bindOk, bindErr = pcall(function()
                parameter.OnClose:Bind(aimedPal, "OnSelectedOrderWorkerRadialMenu")
            end)
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] OnClose:Bind() call: " .. (bindOk and "ok" or ("FAILED: " .. tostring(bindErr))))
        end)
        if not ok then
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] error while attempting redirect: " .. tostring(err))
        end
    end

    local function try_fix_worker_menu_parameter(hookLabel, Context, WidgetClassParam, ParameterParam)
        local parameter = hook_get(ParameterParam)
        local paramDesc = hook_describe(parameter)

        local diagKey = hookLabel .. ":" .. paramDesc
        if diagKey ~= lastLoggedPushedClass then
            lastLoggedPushedClass = diagKey
            Logger.log(string.format(
                "[PalBonds/Interaction] [WORKER-BIND-FIX-DIAG] %s pushed a widget with Parameter: %s",
                hookLabel, paramDesc
            ))
        end

        if not parameter then return end
        if not paramDesc:find("WorkerRadialMenu", 1, true) then
            return -- not our menu — some other UI entirely, leave it alone
        end

        apply_wild_fix_to_worker_parameter(parameter, hookLabel)
    end

    -- Ninetieth pass (2026-09-03): THE REAL INTERCEPTION POINT, found from
    -- this session's own log. `WBP_WorkerRadialMenu_Overlay_C:OnSetup`
    -- fired for real (WORKER-WATCH, confirmed) but with EVERY argument
    -- nil — meaning it takes no meaningful arguments, and (per this
    -- Blueprint family's pattern of exposing a plain `Parameter` variable,
    -- matching PushWidgetStackableUI's own parameter name) the dispatch
    -- Parameter is very likely stored as a plain Blueprint variable on the
    -- widget itself: `self.Parameter`, readable directly off the `self`
    -- object OnSetup already hands us via Context — not passed as a
    -- function argument at all, which is exactly why neither the eighty-
    -- eighth pass's hook nor this pass's diagnostic ever saw it. `OnSetup`
    -- fires as part of the SAME confirmed-real sequence
    -- (Construct→OnSetup→OnAnyUIPushed→...→OnClosed→Destruct) that WORKER-
    -- WATCH already proved happens on every real Worker Menu open, so if
    -- `self.Parameter` resolves here, this is a hook point PROVEN to fire,
    -- unlike the abandoned Push-based one. Needs its own retry loop, same
    -- as every other Worker Menu Blueprint hook in this file — the class
    -- isn't loaded at Init() time.
    local workerOnSetupRound = 0
    local function install_worker_onsetup_fix_hook()
        local path = WORKER_MENU_OVERLAY_CLASS .. ":OnSetup"
        local ok = pcall(function()
            RegisterHook(path, function(Context)
                local self_ = hook_get(Context)
                if not self_ then return end
                local parameter = safe_call(function() return self_.Parameter end)
                local paramDesc = hook_describe(parameter)
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] OnSetup self.Parameter = " .. paramDesc)
                if not parameter then return end
                if not paramDesc:find("WorkerRadialMenu", 1, true) then return end
                apply_wild_fix_to_worker_parameter(parameter, "WBP_WorkerRadialMenu_Overlay_C:OnSetup")
            end)
        end)
        return ok
    end
    local function worker_onsetup_retry_runner()
        workerOnSetupRound = workerOnSetupRound + 1
        if install_worker_onsetup_fix_hook() then
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] OnSetup fix hook installed on round " .. workerOnSetupRound)
            return
        end
        if workerOnSetupRound >= MAX_RADIAL_HOOK_ROUNDS then
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] giving up installing the OnSetup fix hook after " .. workerOnSetupRound .. " rounds")
            return
        end
        pcall(function()
            ExecuteInGameThreadWithDelay(RADIAL_HOOK_RETRY_MS, function()
                safe_call(worker_onsetup_retry_runner)
            end)
        end)
    end
    worker_onsetup_retry_runner()

    local okPushWidget = pcall(function()
        RegisterHook("/Script/Pal.PalHUDInGame:PushWidgetStackableUI", function(Context, WidgetClassParam, ParameterParam)
            try_fix_worker_menu_parameter("PalHUDInGame:PushWidgetStackableUI", Context, WidgetClassParam, ParameterParam)
        end)
    end)
    if not okPushWidget then
        Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not install PushWidgetStackableUI hook")
    end

    local okServicePush = pcall(function()
        RegisterHook("/Script/Pal.PalHUDService:Push", function(Context, WidgetClassParam, ParameterParam)
            try_fix_worker_menu_parameter("PalHUDService:Push", Context, WidgetClassParam, ParameterParam)
        end)
    end)
    if not okServicePush then
        Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not install PalHUDService:Push hook")
    end
end

-- Called once a pet OR feed successfully lands on any Pal (wild or
-- owned). REAL as of the sixteenth pass (2026-09-01): forwards to
-- Trust.lua, which reads the real FriendshipRank and handles the
-- follow-at-5-interactions / capture-at-rank-1 thresholds. Fires for ANY
-- Pal, owned or not — harmless for an owned one (it just accumulates
-- interaction-count state Trust.lua never acts on, since an owned Pal is
-- already captured).
function Interaction.OnWildPalPetted(palActor)
    Trust.OnInteractionSucceeded(palActor)

    -- Thirty-fourth pass (2026-09-02): first real, live use of
    -- Personality.lua's new helpers. Deliberately called here — a
    -- successful pet/feed is already a rare, gated event (never per-tick)
    -- — rather than as a new standalone hook, per the lesson from the
    -- thirty-third pass's frame-rate incident. Logs once per interaction,
    -- not per-tick, so this is safe to leave on permanently.
    local palId = Personality.GetOrInitState(palActor)
    if palId then
        local state = Personality.GetState(palId)
        Logger.log(string.format(
            "[PalBonds/Personality] resolved state for id=%s — disposition=%s (species default=%s, preset=%s)",
            palId,
            tostring(state and state.disposition),
            tostring(state and state.speciesDefault),
            tostring(state and state.presetClassName)
        ))

        -- Hundred-and-twenty-fifth pass (2026-09-03): Dragón's "skittish
        -- Pal warms up to you" idea. A real, successful interaction (this
        -- event) is exactly the trigger — see Personality.lua's own
        -- comment on OnSuccessfulInteraction for the full reasoning.
        Personality.OnSuccessfulInteraction(palId, palActor)
    else
        Logger.log("[PalBonds/Personality] could not resolve a stable ID for this Pal (handle/ID lookup failed) — see Personality.lua")
    end
end

return Interaction
