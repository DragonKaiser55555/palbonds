--[[
    OtomoWatch.lua — temporary research tool, NOT a real subsystem (no
    DESIGN.md section of its own). Twenty-second pass (2026-09-01).

    Purpose: the twenty-first pass (see hook-points.md) found a plausible
    real API for turning a wild Pal into a true party Otomo — but it was
    a HYPOTHESIS built from matching function signatures, not a confirmed
    sequence. Same fix as every previous uncertainty in this project:
    don't guess, WATCH the real game do it first (the same technique that
    already answered the real pet/feed shape via Spy.lua). This file
    installs READ-ONLY pre-hooks (RegisterHook) and logs arguments —
    including, for any handle argument, whether it already has a live
    actor in the world AT THE MOMENT the real game calls that function. A
    pre-hook fires right before the real function runs and does not call
    anything itself, so this cannot cause the kind of crash a direct
    experimental call could — safe to leave running.

    TWENTY-THIRD PASS (2026-09-01) result: NONE of the base native-class
    hooks (AddOtomoHandleToFreeSlot/ActivatePalByHandle/ActivateCurrentOtomo/
    ChangePalSlot/SpawnCharacterByHandle) ever fired for the PLAYER across
    a full session of swapping party Pals — the only hit all session was
    one AddOtomoHandleToFreeSlot call on an NPC's own holder component,
    revealing the real class name `BP_OtomoPalHolderComponentForNPC_C` — a
    BLUEPRINT subclass of the native base built specifically for NPCs.
    Tried hooking the sibling player-facing class documented by
    pwmodding.wiki, `BP_OtomoPalHolderComponent_C:ActivateOtomo` — that
    hook FAILED TO ATTACH at all ("could not hook").

    TWENTY-FOURTH PASS (2026-09-02): confirmed via FModel + the native SDK
    dump that `ActivateOtomo` (and several other very promising functions)
    really do exist on `UBP_OtomoPalHolderComponent_C` — see
    `CXXHeaderDump/BP_OtomoPalHolderComponent.hpp`, generated fresh, full
    class body read directly. So the function is real; the hook attempt
    itself was the problem. Most likely cause: unlike a native class
    (always loaded, reflection-registered at game startup), a BLUEPRINT
    class's UFunction only exists in memory once something actually
    references/loads that Blueprint asset — and this mod's Init() runs at
    game/mod load, before the player's save (and their actual
    OtomoPalHolderComponent instance) exists yet. Fix this pass: retry
    hook registration on a timer (same safe, already-proven
    ExecuteInGameThreadWithDelay pattern used by Trust.lua's follow tick)
    until it succeeds or a generous attempt cap is hit, instead of trying
    once at startup and giving up. Applied to every Blueprint-path hook
    below; the native-class hooks from the twenty-second pass didn't need
    this (they attached immediately, every time) and are left as one-shot.

    Also expanded which functions on the REAL class are watched, now that
    its full real signature list is known (several are much more directly
    relevant than the base class's, e.g. a plain `ActivatedHandle` field
    holding the current active Pal's handle right on the object, and
    `RemovePalFromParty`/`SpawnOtomo`/`SetSelectOtomoID_Internal` as
    likely-simpler real entry points alongside `ActivateOtomo` itself).

    What Dragón should do with this active, to get real data: same as
    before — swap the active party Pal via the normal menu, switch which
    Pal holds the second-Otomo slot if applicable, box/unbox a Pal, send
    one to base and recall it. Nothing touching a wild Pal yet.

    TWENTY-EIGHTH PASS (2026-09-02): Dragón asked, fairly, why we keep
    hooking specific named functions one at a time instead of just logging
    everything the game does and mining that log for the right names. Real
    answer, checked against UE4SS's own docs (docs.ue4ss.com), not assumed:
    the Lua API has NO wildcard/global hook. RegisterHook needs one exact
    UFunction path every time, and even the engine-level ProcessEvent hook
    that UE4SS itself uses internally (UE4SS-settings.ini's
    HookUObjectProcessEvent) is what POWERS RegisterHook for script/BP
    functions under the hood — it's not separately exposed to Lua as a
    firehose we could tap. So "log literally everything" isn't available
    from Lua; it would need a UE4SS C++ change, and even then the volume
    (every UFunction call in the whole engine, every frame) would be its
    own haystack.

    BUT the spirit of the question was right, and applying it to something
    we already had — the static CXXHeaderDump/Pal.hpp text — paid off
    immediately: instead of hypothesizing a class name first and checking
    if it has the function we want, grepped the ENTIRE header dump for
    "Capture" and "Handle" and read every match's surrounding class. That
    surfaced two much stronger candidates for the still-open "how does a
    captured Pal's handle reach a party slot" question than anything found
    by narrow guessing:
      - `UPalUtility::PalCaptureSuccess(APalPlayerCharacter* AttackerPlayer,
        APalCharacter* Monster)` — a global static (same trusted shape as
        GetIndividualCharacterHandleByActor), plausibly THE single call
        site for "a capture just succeeded."
      - `APalCaptureJudgeObject::OnCaptureSuccess(const APalCharacter*
        Character, FCaptureResult Result)` — the sphere's own judge object
        confirming success, likely fired even earlier in the sequence.
    Neither was on our radar before because neither name matches the
    "Otomo"/"Party" vocabulary we'd been searching for — exactly the kind
    of miss a broader sweep catches and a narrow one doesn't. Both added
    below as new read-only watches. If either fires on a real capture,
    logging its arguments (which player, which monster) should show us
    what happens immediately after — including, hopefully, finally
    explaining why AddOtomoHandleToFreeSlot never fires for the player.

    THIRTIETH PASS (2026-09-02): Dragón's own idea — settlements/enemy
    camps sometimes hold a captive Pal in a small cage; opening it adds
    that Pal straight to the party/box with NO Palsphere involved at all.
    That's a real, existing, dev-built "sphere-less capture" path already
    in the game — a much better precedent to study than trying to call
    PalCaptureSuccess out of context (twenty-ninth pass's open concern).
    Grepped the header dump for it and found the real class immediately:
    `class APalCapturedCage : public AActor` — native, always loaded, no
    retry needed. Has exactly the right shape: `bIsEnemyCamp` flag,
    `SpawnPal`/`LotteryAndSpawnPal` (populates the cage), `OpenDoor_ToAll`/
    `OpenDoor_BP`/`SetDoorOpened` (the interaction), `OnSuccessOpenDoor_Client`,
    `StartCaptureEffect_ServerBP`, and — the one we actually want —
    `CapturePal_ServerInternal(APalPlayerCharacter* Player)`. All added as
    read-only watches below. Plan: Dragón finds a real enemy-camp/
    settlement cage and opens it normally; whichever of these fire, and in
    what order, should show the real "no sphere" hand-off path directly —
    hopefully a much safer, better-precedented model to reuse than
    anything found so far.

    THIRTY-SECOND PASS (2026-09-02): Dragón downloaded a third-party mod
    ("PassiveWildPals", makes wild Pals never aggro) from Nexus Mods and
    asked us to see how it's built. It's a raw Unreal .pak overriding one
    Blueprint asset (BP_AIAction_WildLife) — not reusable technique-wise
    (needs the actual Unreal Editor + cooking pipeline, not UE4SS Lua) —
    but reading its strings (no execution, just text — see hook-points.md
    "Thirty-second pass" for the full breakdown) named several real native
    classes/functions this project didn't know about, all confirmed
    against the actual SDK header dump:
      - `UPalAISensorComponent` (native UActorComponent, always loaded) —
        `SelectResponseBySenses(CurrentBehavior, FindCharacters, IsDamaged,
        &OutTargetCharacter)`, the real function that decides how a wild
        Pal reacts to what it senses. Also has a plain `AIResponsePreset`
        field pointing at a `UPalAIResponsePreset` — a real per-species
        disposition table (Discover_Player/Greater/Equal/Smaller,
        Damaged_Player/Greater/Equal/Smaller) — this answers DESIGN.md
        Question 1, which had been open since pass one.
      - `UPalBattleManager` (a world subsystem, reached via the already-
        trusted `UPalUtility.GetBattleManager(world)`) —
        `TargetIsPlayerOrPlayersOtomoPal(Actor)`, a ready-made "is this
        the player or their Otomo" check — answers Question 2.
    Both added below as new read-only watches. Native, always-loaded,
    same easy category as everything else hooked in this file — no retry
    wrapper needed.

    THIRTY-SIXTH PASS (2026-09-02): after the big multi-scenario test
    session, went digging in the header dump again for a cleaner "add an
    arbitrary wild Pal's handle to the party" entry point than reusing
    APalCapturedCage's cage-bound CapturePal_ServerInternal. Mapped the
    surrounding class structure much better (UPalOtomoHolderComponentBase
    = the active-battle-slot holder; UPalPlayerPartyPalHolder = a simpler
    2-active-slot+bench struct; UPalIndividualCharacterContainer = the
    actual slot array, native container of UPalIndividualCharacterSlot
    objects, each just holding a plain `Handle` field) — but found NO
    exposed UFUNCTION anywhere that looks like "AddMember"/"SetHandle"/
    "AddBenchMember". Also checked the fishing minigame's own capture path
    (`FPalGrantCharacterRequestData`, `UPalFishingSystem`) — same
    IndividualHandle-based shape, but it's fishing-specific plumbing for a
    freshly-created catch, not reusable for handing over an ALREADY-
    EXISTING wild Pal's handle.

    Honest conclusion: a header dump only lists *reflected* (UFUNCTION-
    marked) functions — if the actual "write this handle into the slot"
    step is a plain, non-reflected C++ function call (very plausible for
    something this performance-sensitive/internal), it will never appear
    here and can never be hooked from Lua at all, no matter how much more
    grepping we do. Static research on this specific question may be at
    its ceiling. Added two more read-only watches below that come as
    close as headers allow to observing the moment itself: `OnUpdateSlot`
    (a real UFunction that looks like a direct "this slot's handle just
    changed" notification) and `FindEmptySlot` (fires when the game looks
    for a free slot, plausibly right before assigning one) — both native,
    both call-once-per-real-event shaped like everything else in this
    file, not per-tick. Whether either actually fires during a real
    capture is still an open, empirical question for the next test.

    Once we've seen enough real activations to answer the open questions,
    delete/disable this file — like Spy.lua, it's diagnostic only.
]]

local Logger = require("Logger")

local OtomoWatch = {}

local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- Describes a handle: its stable ID and, critically, whether it already
-- has a live actor in the world RIGHT NOW.
local function describe_handle(handle)
    if handle == nil then return "nil" end
    local id = safe_call(function() return handle:GetIndividualID() end)
    local actor = safe_call(function() return handle:TryGetIndividualActor() end)
    local actorDesc = "no live actor yet"
    if actor and safe_call(function() return actor:IsValid() end) then
        actorDesc = safe_call(function() return actor:GetFullName() end) or "valid but unnamed actor"
    end
    return string.format("id=%s actor=[%s]", tostring(id), actorDesc)
end

local function describe(obj)
    if obj == nil then return "nil" end
    return safe_call(function() return obj:GetFullName() end) or tostring(obj)
end

-- Reads the holder's own ActivatedHandle field (real field on
-- UBP_OtomoPalHolderComponent_C, found twenty-fourth pass) for extra
-- context on every log line — "what was active right when this fired".
local function describe_activated(holder)
    if holder == nil then return "n/a" end
    local activated = safe_call(function() return holder.ActivatedHandle end)
    if activated == nil then return "none" end
    return describe_handle(activated)
end

-- Attempts RegisterHook once immediately; if it fails (likely because a
-- Blueprint class isn't loaded into memory yet), retries on a timer via
-- the same safe, already-proven ExecuteInGameThreadWithDelay pattern
-- Trust.lua uses for its follow tick. Gives up after maxAttempts with a
-- clear log line either way. Read-only hooks only — never used to make
-- any real call.
local function hook_with_retry(label, path, callback, attemptsLeft)
    attemptsLeft = attemptsLeft or 20 -- ~20 * 3s = 60s of retrying before giving up
    local ok = pcall(function()
        RegisterHook(path, callback)
    end)
    if ok then
        Logger.log(string.format("[PalBonds/OtomoWatch] hooked %s (attached)", label))
        return
    end

    if attemptsLeft <= 1 then
        Logger.log(string.format("[PalBonds/OtomoWatch] could not hook %s after retrying — giving up (path/name may be wrong, or this really never gets called)", label))
        return
    end

    local scheduled = pcall(function()
        ExecuteInGameThreadWithDelay(3000, function()
            hook_with_retry(label, path, callback, attemptsLeft - 1)
        end)
    end)
    if not scheduled then
        Logger.log(string.format("[PalBonds/OtomoWatch] could not hook %s and could not schedule a retry either — giving up", label))
    end
end

-- Thirty-seventh pass (2026-09-03): Dragón is about to test something this
-- file hasn't covered yet — freeing a CAGED Pal at a settlement, which he
-- reports ALSO shows the same "beam" as a sphere capture, with NO sphere
-- involved at all. That's a genuinely useful test design: if the same
-- hook fires for both a sphere capture AND a cage release, it can't be
-- Indicator.lua's BP_CapturePrism/BP_CapturePrismBullet (those are the
-- throwable sphere weapon specifically, never involved in a cage release)
-- — it has to be something shared by both paths.
--
-- Grepped the WHOLE header dump (not a narrow guess) for
-- "Beam|Cage|Captive|Prisoner|Slave|Rescue|JoinParty|AddParty|JoinPal|
-- CaptureEffect|CaptureVFX|CaptureSuccess|Pillar|LightRay|SummonEffect|
-- SpawnEffect" and read every real match. Strongest new candidate by far:
-- `ABP_ReturnPalEffect_C : AActor` (`BP_ReturnPalEffect.hpp`) — a real
-- actor whose whole job is a VFX (`UNiagaraComponent* Effect`,
-- `CacheDisappearBurstEffect`/`CacheDisappearEffect`, both
-- `UNiagaraSystem*`) that moves a Pal from `StartLocation` to `ForPlayer`
-- over time (`LerpStartPos`, `Progress`, `CurveForLerp`) — this is
-- structurally exactly "a beam/trail effect showing a Pal traveling to
-- become the player's". Its own name ("Return Pal Effect") suggests it's
-- normally used for recalling an Otomo, but nothing about its shape is
-- otomo-specific — a strong candidate for the SAME effect firing whenever
-- a Pal becomes the player's, sphere or cage.
--
-- Also found: `ABP_PalCaptureJudgeObject_C : APalCaptureJudgeObject` (a
-- Blueprint SUBCLASS of the native class this file already hooks at
-- twenty-eighth pass, which never fired in testing so far) overriding
-- `OnCaptureSuccess`/`OnFailedByMP`/`OnFailedByTest`/`OnFailedFinish`/
-- `OnSuccessFinish` — worth hooking the Blueprint override directly in
-- case the native path's silence was a declaring-class issue (the same
-- kind of gap Indicator.lua's sixty-first pass found for BindFromHandle).
-- Also `UBP_ActionUnlockCagePalLock_C` (the literal cage-lock-unlock
-- interaction — a precise timing anchor for exactly the action Dragón is
-- about to perform) and `ABP_CaptureWire_C` (another real capture-related
-- actor, purpose unconfirmed — has `Setup(TargetPal)`/`CaptureEffect
-- (FPalDeadInfo)` — included for completeness per Dragón's own "don't
-- discard, analyze everything" standing instruction, not because its role
-- is understood yet).
--
-- All four are Blueprint classes, so none has a knowable literal asset
-- path from the header dump alone (unlike native /Script/ classes) — same
-- problem this file already solved once for BP_OtomoPalHolderComponent
-- (hardcoded literal path from an external wiki). No external reference
-- gives real paths for these four.
--
-- Thirty-eighth pass (2026-09-03): Dragón's live test showed this
-- ORIGINAL approach — FindAllOf("BlueprintGeneratedClass"), searching
-- among ALL loaded Blueprint CLASS OBJECTS for a name match — failing
-- outright every single time ("FindAllOf(BlueprintGeneratedClass) failed
-- or returned nothing: nil"), the same dead-end Indicator.lua's own
-- sixty-second pass hit with "WidgetBlueprintGeneratedClass". Querying
-- for the META-class of a Blueprint class via FindAllOf just doesn't work
-- in this UE4SS build, whichever "GeneratedClass" flavor is used.
--
-- Separately, and just as real a problem: even if it HAD worked, all four
-- of these hooks only ever got ~60 seconds total to resolve (20 retries x
-- 3s), all spent right at mod init — but none of these actors exist
-- persistently. They only spawn when a player actually does the specific
-- thing (unlocks a cage, captures with a sphere) — which could easily be
-- minutes into a real session, long after that window closed.
--
-- Thirty-ninth pass (2026-09-03): the follow-up fix (instance:GetClass():
-- GetPathName() on a FindAllOf-found instance, instead of the meta-class
-- scan) did NOT work either — Dragón's own console showed Indicator.lua's
-- identical version of this call hit the same "TrivialObject" error, and
-- worse, was spamming the console every ~2s doing it (its failure log
-- wasn't throttled). That's now THREE separate Lua-reflection techniques
-- confirmed dead for getting a Blueprint class's real asset path in this
-- UE4SS build — the meta-class scan (twice, two "GeneratedClass" flavors)
-- and instance:GetClass() (twice, a hook-Context object and a
-- FindAllOf-returned instance). A web search for a published literal path
-- (the way BindFromHandle's and BP_OtomoPalHolderComponent's were found)
-- turned up nothing for these four classes either.
--
-- Real fix: give up on RegisterHook here entirely — there is no known
-- literal path for any of these four, and every way to derive one from
-- Lua reflection is exhausted. Pivot to what's worked everywhere else
-- without one: read fields/existence directly off live instances
-- FindAllOf hands us, no path or :GetClass() call needed at all. This
-- can't catch a specific FUNCTION firing, but a NEW instance appearing at
-- all is itself real, useful timing data — especially for
-- ABP_ReturnPalEffect_C, which should only exist briefly around an
-- actual "Pal becomes the player's" moment, sphere or cage.
local seenPrismSpyInstances = {} -- fullName -> true, one log per instance ever seen

local MAX_PRISMSPY_LOGS = 80
local prismSpyLogCount = 0
local function prismspy_log(msg)
    if prismSpyLogCount >= MAX_PRISMSPY_LOGS then return end
    prismSpyLogCount = prismSpyLogCount + 1
    Logger.log(msg)
    if prismSpyLogCount == MAX_PRISMSPY_LOGS then
        Logger.log("[PalBonds/OtomoWatch] [PRISM-SPY] reached the log cap (" .. MAX_PRISMSPY_LOGS .. ") — going quiet")
    end
end

-- Polls one concrete class name for live instances; logs each NEW one
-- once (by full name), optionally with a caller-supplied extra field
-- summary for context (e.g. ABP_ReturnPalEffect_C's ForPlayer).
local function poll_class_existence(classLabel, className, describeExtra)
    local instances = safe_call(function() return FindAllOf(className) end)
    if not instances then return end

    for _, inst in ipairs(instances) do
        local validOk, isValid = pcall(function() return inst:IsValid() end)
        if validOk and isValid then
            local fullName = describe(inst)
            if not seenPrismSpyInstances[fullName] then
                seenPrismSpyInstances[fullName] = true
                local extra = describeExtra and (" — " .. describeExtra(inst)) or ""
                prismspy_log("[PalBonds/OtomoWatch] [PRISM-SPY] new live " .. classLabel .. " instance: " .. fullName .. extra)
            end
        end
    end
end

-- Recurring poll (10s spacing — these are rare, event-spawned actors, no
-- need for Indicator.lua's tighter 2s scan cadence) for all four classes,
-- for the rest of the session. Cheap: FindAllOf on a specific concrete
-- class name typically matches zero or a handful of real objects, not a
-- scan of the whole game's Blueprint class list.
local function poll_prismspy_once()
    poll_class_existence("ABP_ReturnPalEffect_C", "BP_ReturnPalEffect_C", function(inst)
        local playerOk, player = pcall(function() return inst.ForPlayer end)
        return "ForPlayer=" .. ((playerOk and player ~= nil and describe(player)) or "nil")
    end)
    poll_class_existence("ABP_PalCaptureJudgeObject_C", "BP_PalCaptureJudgeObject_C", nil)
    poll_class_existence("UBP_ActionUnlockCagePalLock_C", "BP_ActionUnlockCagePalLock_C", nil)
    poll_class_existence("ABP_CaptureWire_C", "BP_CaptureWire_C", function(inst)
        local targetOk, target = pcall(function() return inst.TargetMonster end)
        return "TargetMonster=" .. ((targetOk and target ~= nil and describe(target)) or "nil")
    end)
end

local function schedule_prismspy_poll()
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(10000, function()
            safe_call(poll_prismspy_once)
            schedule_prismspy_poll()
        end)
    end)
    if not ok then
        Logger.log("[PalBonds/OtomoWatch] [PRISM-SPY] could not schedule the existence poll — ExecuteInGameThreadWithDelay itself failed")
    end
end

function OtomoWatch.Init()
    Logger.log("[PalBonds/OtomoWatch] installing read-only watch hooks on the real Otomo-holder API (no calls made, safe) — see file header")

    -- Native base class (UPalOtomoHolderComponentBase) — always loaded,
    -- these attach immediately, no retry needed. Twenty-third pass: none
    -- of these ever fired for the player in a full test session (only
    -- once, for an NPC's own holder) — left running anyway since they're
    -- free and it's still useful negative data.
    pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:AddOtomoHandleToFreeSlot", function(Context, Handle)
            local self = hook_get(Context)
            local handle = hook_get(Handle)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [ADD] AddOtomoHandleToFreeSlot called — holder=%s handle=%s",
                describe(self), describe_handle(handle)
            ))
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:ActivatePalByHandle", function(Context, OtomoHandle, Location, Rotation, bKeepActigvateOtomoId)
            local self = hook_get(Context)
            local handle = hook_get(OtomoHandle)
            local loc = hook_get(Location)
            local keep = hook_get(bKeepActigvateOtomoId)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [ACTIVATE-BY-HANDLE] called — holder=%s handle=%s (BEFORE state, see actor=) location=%s keep=%s",
                describe(self), describe_handle(handle), tostring(loc), tostring(keep)
            ))
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:ActivateCurrentOtomo", function(Context, SpawnTransform)
            local self = hook_get(Context)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [ACTIVATE-CURRENT] ActivateCurrentOtomo called — holder=%s",
                describe(self)
            ))
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerPartyPalHolder:ChangePalSlot", function(Context, SecondPal)
            local self = hook_get(Context)
            local secondPal = hook_get(SecondPal)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [SLOT-SWITCH] ChangePalSlot called — holder=%s secondPal=%s",
                describe(self), tostring(secondPal)
            ))
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalCharacterManager:SpawnCharacterByHandle", function(Context, Handle)
            local self = hook_get(Context)
            local handle = hook_get(Handle)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [SPAWN-BY-HANDLE] SpawnCharacterByHandle called — manager=%s handle=%s",
                describe(self), describe_handle(handle)
            ))
        end)
    end)

    -- Twenty-fourth pass: the REAL player-facing Blueprint class,
    -- UBP_OtomoPalHolderComponent_C (confirmed via fresh CXXHeaderDump).
    -- These need the retry-until-loaded wrapper since the class won't
    -- exist in memory until the player's own holder component has been
    -- created (some time after mod init, once a save is loaded).
    local BP_PATH = "/Game/Pal/Blueprint/Component/OtomoHolder/BP_OtomoPalHolderComponent.BP_OtomoPalHolderComponent_C"

    hook_with_retry("BP_OtomoPalHolderComponent:ActivateOtomo", BP_PATH .. ":ActivateOtomo", function(Context, SlotId, StartTransform, IsSuccess)
        local self = hook_get(Context)
        local slot = hook_get(SlotId)
        Logger.log(string.format(
            "[PalBonds/OtomoWatch] [ACTIVATE-OTOMO] ActivateOtomo called — holder=%s slotID=%s currentActivated=%s",
            describe(self), tostring(slot), describe_activated(self)
        ))
    end)

    hook_with_retry("BP_OtomoPalHolderComponent:SpawnOtomo", BP_PATH .. ":SpawnOtomo", function(Context, SlotId)
        local self = hook_get(Context)
        local slot = hook_get(SlotId)
        Logger.log(string.format(
            "[PalBonds/OtomoWatch] [SPAWN-OTOMO] SpawnOtomo called — holder=%s slotID=%s currentActivated=%s",
            describe(self), tostring(slot), describe_activated(self)
        ))
    end)

    hook_with_retry("BP_OtomoPalHolderComponent:RemovePalFromParty", BP_PATH .. ":RemovePalFromParty", function(Context, RemoveHandle)
        local self = hook_get(Context)
        local handle = hook_get(RemoveHandle)
        Logger.log(string.format(
            "[PalBonds/OtomoWatch] [REMOVE-FROM-PARTY] RemovePalFromParty called — holder=%s handle=%s",
            describe(self), describe_handle(handle)
        ))
    end)

    hook_with_retry("BP_OtomoPalHolderComponent:InactivateCurrentOtomo", BP_PATH .. ":InactivateCurrentOtomo", function(Context)
        local self = hook_get(Context)
        Logger.log(string.format(
            "[PalBonds/OtomoWatch] [INACTIVATE-CURRENT] InactivateCurrentOtomo called — holder=%s currentActivated(before)=%s",
            describe(self), describe_activated(self)
        ))
    end)

    hook_with_retry("BP_OtomoPalHolderComponent:SetSelectOtomoID_Internal", BP_PATH .. ":SetSelectOtomoID_Internal", function(Context, Index)
        local self = hook_get(Context)
        local index = hook_get(Index)
        Logger.log(string.format(
            "[PalBonds/OtomoWatch] [SET-SELECT-ID] SetSelectOtomoID_Internal called — holder=%s index=%s",
            describe(self), tostring(index)
        ))
    end)

    -- Twenty-eighth pass: broad-grep-across-the-header finds, not narrow
    -- guesses. Both native, both global/always-loaded shapes we've
    -- already trusted before (UPalUtility statics, a plain AActor class)
    -- — no retry wrapper needed, should attach immediately like the
    -- native hooks above.
    pcall(function()
        RegisterHook("/Script/Pal.PalUtility:PalCaptureSuccess", function(Context, AttackerPlayer, Monster)
            local attacker = hook_get(AttackerPlayer)
            local monster = hook_get(Monster)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAPTURE-SUCCESS-UTIL] UPalUtility.PalCaptureSuccess called — attacker=%s monster=%s",
                describe(attacker), describe(monster)
            ))
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalCaptureJudgeObject:OnCaptureSuccess", function(Context, Character, Result)
            local self = hook_get(Context)
            local character = hook_get(Character)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAPTURE-JUDGE] APalCaptureJudgeObject.OnCaptureSuccess called — judge=%s character=%s",
                describe(self), describe(character)
            ))
        end)
    end)

    -- Thirtieth pass: the real captured-Pal cage class (settlements/enemy
    -- camps that hold a Pal captive — open the door, Pal goes straight to
    -- party/box, no sphere). Native AActor subclass, always loaded.
    local CAGE = "/Script/Pal.PalCapturedCage"

    pcall(function()
        RegisterHook(CAGE .. ":OpenDoor_ToAll", function(Context)
            local self = hook_get(Context)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-OPEN-DOOR] OpenDoor_ToAll called — cage=%s",
                describe(self)
            ))
        end)
    end)

    pcall(function()
        RegisterHook(CAGE .. ":SetDoorOpened", function(Context, bIsOpend)
            local self = hook_get(Context)
            local opened = hook_get(bIsOpend)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-SET-DOOR] SetDoorOpened called — cage=%s opened=%s",
                describe(self), tostring(opened)
            ))
        end)
    end)

    pcall(function()
        RegisterHook(CAGE .. ":OnSuccessOpenDoor_Client", function(Context, Player)
            local self = hook_get(Context)
            local player = hook_get(Player)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-DOOR-SUCCESS] OnSuccessOpenDoor_Client called — cage=%s player=%s",
                describe(self), describe(player)
            ))
        end)
    end)

    pcall(function()
        RegisterHook(CAGE .. ":StartCaptureEffect_ServerBP", function(Context, Player)
            local self = hook_get(Context)
            local player = hook_get(Player)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-CAPTURE-EFFECT] StartCaptureEffect_ServerBP called — cage=%s player=%s",
                describe(self), describe(player)
            ))
        end)
    end)

    pcall(function()
        RegisterHook(CAGE .. ":CapturePal_ServerInternal", function(Context, Player)
            local self = hook_get(Context)
            local player = hook_get(Player)
            local spawned = safe_call(function() return Context:get().SpawnedPalHandle end)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-CAPTURE-PAL] *** CapturePal_ServerInternal called *** cage=%s player=%s spawnedHandle=%s",
                describe(self), describe(player), describe_handle(spawned)
            ))
        end)
    end)

    pcall(function()
        RegisterHook(CAGE .. ":OnCreateHandle", function(Context, ID)
            local self = hook_get(Context)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-CREATE-HANDLE] OnCreateHandle called — cage=%s",
                describe(self)
            ))
        end)
    end)

    pcall(function()
        RegisterHook(CAGE .. ":LotteryAndSpawnPal", function(Context)
            local self = hook_get(Context)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [CAGE-LOTTERY-SPAWN] LotteryAndSpawnPal called — cage=%s",
                describe(self)
            ))
        end)
    end)

    -- Thirty-second pass: leads found by reading a third-party mod's
    -- asset strings (see file header + hook-points.md), then confirmed
    -- against our own native SDK dump. Both native, always-loaded.
    --
    -- THIRTY-THIRD PASS (2026-09-02) — DISABLED, real mistake: unlike
    -- every other hook in this file (rare events — swaps, captures,
    -- cage opens), SelectResponseBySenses turned out to fire on EVERY
    -- wild Pal's sensor component continuously (6706 calls logged in
    -- roughly one second with a few dozen Pals in view) — this is part
    -- of the game's own per-tick AI sensing loop, not a discrete event.
    -- Each call did a string.format + a flushed file write, so this
    -- produced a genuine log-flood and a real, noticeable frame-rate
    -- drop for Dragón — a real operational cost, not just noise. Should
    -- have anticipated this: it's a per-tick decision function, not an
    -- event notification, and this file's logging pattern (log every
    -- single call, unthrottled) is only safe for things that fire
    -- rarely. Commented out rather than left running. We already got
    -- what we needed from the one real test before it was disabled: it
    -- fires (confirms the function is real and reachable), and its
    -- `AIResponsePreset` field resolved to real, readable preset names —
    -- `BP_AIResponsePreset_Escape_to_Battle_C` (skittish/fight-if-cornered
    -- species), `BP_AIResponsePreset_friendly_C` (Lamball/Chikipi-type,
    -- never hostile), `BP_AIResponsePreset_VillageNPC_C` (human NPCs) —
    -- confirming UPalAIResponsePreset is real and populated exactly as
    -- hypothesized. If this needs watching again, add a dedup/throttle
    -- (log only the first time each unique sensor is seen, or sample
    -- 1-in-N) instead of logging every call.
    --[[
    pcall(function()
        RegisterHook("/Script/Pal.PalAISensorComponent:SelectResponseBySenses", function(Context, CurrentBehavior, FindCharacters, IsDamaged, OutTargetCharacter)
            local self = hook_get(Context)
            local current = hook_get(CurrentBehavior)
            local damaged = hook_get(IsDamaged)
            local preset = safe_call(function() return Context:get().AIResponsePreset end)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [SENSOR-RESPONSE] SelectResponseBySenses called — sensor=%s currentBehavior=%s isDamaged=%s preset=%s",
                describe(self), tostring(current), tostring(damaged), describe(preset)
            ))
        end)
    end)
    ]]

    pcall(function()
        RegisterHook("/Script/Pal.PalBattleManager:TargetIsPlayerOrPlayersOtomoPal", function(Context, TargetCharacter)
            local self = hook_get(Context)
            local target = hook_get(TargetCharacter)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [BATTLE-IS-OTOMO] TargetIsPlayerOrPlayersOtomoPal called — battleManager=%s target=%s",
                describe(self), describe(target)
            ))
        end)
    end)

    -- Thirty-sixth pass: as close as the reflected header dump gets to
    -- watching the actual "handle lands in a party slot" moment (see file
    -- header). Both native, both event-shaped (called once per real
    -- slot-related action, not per-tick) — safe to log unconditionally.
    pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:OnUpdateSlot", function(Context, Slot, LastHandle)
            local self = hook_get(Context)
            local lastHandle = hook_get(LastHandle)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [SLOT-UPDATED] OnUpdateSlot called — holder=%s lastHandle=%s",
                describe(self), describe_handle(lastHandle)
            ))
        end)
    end)

    pcall(function()
        RegisterHook("/Script/Pal.PalIndividualCharacterContainer:FindEmptySlot", function(Context)
            local self = hook_get(Context)
            Logger.log(string.format(
                "[PalBonds/OtomoWatch] [FIND-EMPTY-SLOT] FindEmptySlot called — container=%s",
                describe(self)
            ))
        end)
    end)

    -- Thirty-seventh/thirty-ninth pass: the "prism"/beam spy (see big
    -- comment above). RegisterHook is abandoned for these four classes —
    -- no literal path is known and every Lua-reflection technique to
    -- derive one is exhausted. Existence/field polling instead, no path
    -- needed at all.
    schedule_prismspy_poll()

    Logger.log("[PalBonds/OtomoWatch] hook installation attempts complete (Blueprint-path hooks may still be retrying — watch for individual 'hooked X (attached)' lines)")
end

return OtomoWatch
