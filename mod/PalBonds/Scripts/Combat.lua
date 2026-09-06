--[[
    Combat.lua — DESIGN.md §3.4

    FIRST REAL ATTEMPT (2026-09-01) at making a bonding wild Pal follow
    the player, replacing the stub. Full owned-Pal Otomo party membership
    (hook-points.md question 6) is still unsolved — entering a Pal into
    that system without breaking party UI/bookkeeping needs more research
    than this pass had time for (DESIGN.md flagged this exact risk: "a
    wrong guess could visibly break party UI/bookkeeping that assumes a
    Pal is actually captured").

    Instead, this APPROXIMATES following using a real, confirmed-safe
    movement command already found in the SDK dump, on the Pal's own
    AIController:

        APalAIController:PalMoveToLocation(Dest, AcceptanceRadius,
            bStopOnOverlap, bUsePathfinding, bProjectDestinationToNavigation,
            bCanStrafe, FilterClass, bAllowPartialPaths)

    Called every few seconds (from Trust.lua's tick_followers) with the
    player's current location as Dest. This is a real pathfinding request
    the game's own navmesh system executes — not new AI, just repeatedly
    telling the Pal's EXISTING move system "go here". It is NOT the same
    as real Otomo following: no combat-assist, no formation, no smart
    speed-matching, and it's re-issued on top of whatever the Pal's own
    wild AI (wander/flee/etc.) is otherwise trying to do, since the Pal
    isn't actually in a "following" AI state — it's closer to "gently
    nudged toward the player every tick." Good enough to test whether
    trust-based following reads as intended in-game; not the real thing.

    NOT implemented this pass: "if the player attacks an enemy, the
    following Pal should help" (Dragón's spec). Needs separate research
    into how Otomo Pals actually decide to engage a target — deferred
    until basic following itself is confirmed working live.

    SEVENTEENTH PASS (2026-09-01) — reliability fix attempt #1, prompted
    by Dragón's report of irregular following. Two changes were made:
    (1) Trust.lua's tick interval dropped from 5s to 1.5s so the move
    order refreshes more often against the Pal's own wild AI, and
    (2) `APalAIController:SetActiveAI(false)` while bonding / `(true)` on
    stop, to try to suppress that wild AI outright.

    EIGHTEENTH PASS (2026-09-01, same day, next test) — #2 was WRONG,
    REVERTED. Live log evidence from the very next session:

      - Every `PlayActionByType` call for pet/feed still logged
        `result=ok` for a Pal that had `SetActiveAI(false)` active, on
        every single interaction after it started following — but
        Dragón directly observed the pet/feed reaction animation itself
        stopped playing (only the separate "Happy" reaction, a different
        call, kept visibly working). `result=ok` only means the Lua call
        didn't error; it says nothing about whether the game's own
        action system actually ran it, and apparently `PlayActionByType`
        needs the AI controller active to actually execute, even though
        it doesn't error when it can't.
      - Worse: `SetActiveAI(false)` appears to disable the Pal's ENTIRE
        AI decision layer, not just wander/graze/flee targeting. Dragón
        reported a following Pal that got jumped by a hostile Pal "just
        stood there taking hits, doing nothing" (no counter-attack, no
        flee, no reaction at all) and another that died the same way.
        This is a much bigger hammer than intended — it also may be why
        the one Pal that DID lose all its trust to damage this same
        session (see the nineteenth-pass section below) never actually
        looked like it fled: its AI was only restored at the exact
        instant it hit rank 0, too late to react during the fight itself.

    Net result: `SetActiveAI` is REMOVED from this file as of this pass.
    Fix #1 (the faster 1.5s tick, still in Trust.lua) stays — nothing in
    this session's log evidence implicates it, and it's a strict
    improvement in move-order responsiveness on its own, even though
    following the Pal's own wild AI can still fight it between ticks
    (the original, already-documented "approximation" limitation, not a
    new regression). A real fix for that competition — if one exists —
    needs something more targeted than a global AI kill switch; not
    attempted again this pass.
]]

local Logger = require("Logger")

local Combat = {}

local FOLLOW_ACCEPTANCE_RADIUS = 200.0 -- how close the move order tries to bring the Pal (Unreal units)

-- Two-hundred-and-third pass (2026-09-06): both toggles below MUST be
-- declared here, before Combat.Init references USE_OLD_MOVE_ORDER_NUDGE in
-- its own startup log line — the Two-hundred-and-second pass had declared
-- this same local much further down the file (right before
-- IssueFollowMoveOrder), and Combat.Init's earlier reference to it silently
-- resolved to a nil global instead of the real local (Lua locals don't
-- hoist — this project's own hook-points.md hundred-and-fortieth-pass bug,
-- repeated). Purely cosmetic (Init's log line always printed "disabled for
-- this test" regardless of the real value; the actual gating in
-- IssueFollowMoveOrder was unaffected since it's declared after this point
-- either way) — fixed by moving the declaration up here, before every use.
--
-- Real test result (2026-09-06): Dragón ran a live session with the old
-- nudge fully off — the composite mechanism reported `SetRootComposite ok`
-- for all 3 Pals that reached the 50% follow trigger, every relevant tick,
-- with zero logged failures. All 3 nonetheless wandered off and broke the
-- 3000-unit leash 10-20 seconds later, never visibly moving toward the
-- player. A clean, repeated negative result — not a competing-mechanism
-- problem (nothing else was pushing this session), a confirmed "this
-- doesn't work on a wild Pal" result.
--
-- Two-hundred-and-fourth pass (2026-09-06): Dragón's explicit call after
-- seeing that result — keep the old move-order nudge in the file as a
-- known, real fallback, but do NOT turn it back on yet either. Both
-- mechanisms tried so far (the plain move order, and the repeated Otomo
-- composite) are confirmed weak-to-nonexistent on a wild Pal — the next
-- real attempt should look for something the game itself already uses to
-- make a Pal trail the player without full Otomo/combat bookkeeping,
-- rather than defaulting back to the weakest option just because it's
-- already built. Leading candidate not yet actually tried as a follow
-- mechanism: `UPalAIActionFunnelCharacterDefault`/`BP_AIAction_FunnelFollow_C`
-- — the real, native class behind a captured-but-inactive Pal trailing the
-- player around (the "Funnel" system PalFollowerTweaks only ever
-- reconfigures cosmetically, never actually used for THIS project's
-- purpose before). See CLAUDE.md's Daedream/Dazzi/Floppie research note for
-- the live investigation into whether/how that's reachable for a Pal that
-- was never captured at all.
-- Two-hundred-and-seventh pass (2026-09-06): the move-order nudge is back
-- ON, but it is NOT the same nudge that was switched off in the
-- two-hundred-and-third pass. Two things changed around it, both built from
-- calls already proven to work on wild Pals:
--
--   1. Personality.ApplyCompanionPreset (called from StartFollowing) sets
--      the Pal's own "what do I do about the player" responses to Ignore,
--      so its AI stops generating the competing decisions that were
--      overriding the order. The old nudge failed because it was fighting
--      that AI; now there is nothing to fight.
--   2. Each order is preceded by AllCancelAction_Logic_HardScript_Reaction
--      (see IssueFollowMoveOrder), the same interrupt confirmed to succeed
--      5/5 on wild Pals, so whatever action is currently occupying the Pal
--      is dropped immediately before the order lands rather than continuing
--      to run over it.
--
-- The repeated Otomo composite stays OFF: it was tested cleanly on its own
-- in the two-hundred-and-third pass (3/3 Pals broke the leash without
-- moving toward the player once) and depends on ownership this Pal doesn't
-- have. Nothing learned since changes that assessment.
local USE_OLD_MOVE_ORDER_NUDGE = true
local USE_REPEATED_OTOMO_COMPOSITE = false

-- Combat assist, per Dragón's explicit go-ahead this pass. Applied as part
-- of the same companion preset: a following Pal's Discover responses to
-- OTHER Pals become Battle, while its responses to the player stay Ignore.
-- This reuses the exact mechanism already confirmed working (a Warlike
-- preset really does make a wild Pal attack) rather than inventing a new
-- targeting system. Known limitation, stated honestly: this makes the
-- companion engage what it notices, not specifically what the player is
-- fighting. Targeting the player's own current enemy would need the Hate
-- system (HateSystem:ChangeHate / APalAIController.TargetPlayers), which is
-- real but has never been explored for this purpose.
local ENABLE_COMBAT_ASSIST = true

-- Throttle state for [MOVE-ORDER-RESULT] — see IssueFollowMoveOrder.
local lastMoveOrderResult = nil

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

-- BondingState[key] = true while the Pal is actively following under
-- positive trust (not yet captured). Keyed by GetFullName(), same as
-- Trust.lua — see that file's header for why FPalInstanceID isn't used
-- yet.
local BondingState = {}

-- Hundred-and-ninety-seventh pass (2026-09-05): Dragón asked to reopen the
-- real-follow question directly, reusing the SDK lead this file already
-- found and left untested (the eighty-sixth pass's FOLLOW-DIAG, below in
-- StartFollowing) plus the Otomo/FunnelCharacter composite-action classes
-- read from the PalFollowerTweaks reference-mod research (hook-points.md's
-- hundred-and-thirty-seventh pass, PalFunnelCharacter/Daedream-style
-- secondary followers). Real functions confirmed directly in Pal.hpp this
-- pass:
--   - `UPalAIActionComponent:SetRootComposite(NewCompositeAction, Priority)`
--   - `UPalAIActionOtomoDefault : UPalAIActionCompositeBase`, exposing
--     `SetOtomoFollowAction()`/`SetOtomoCombatAction()`/etc — the literal
--     decision layer a REAL Otomo Pal uses to choose follow/combat/work.
--
-- `EAIRequestPriority::Type` is a native, non-Palworld-specific Unreal
-- engine enum (the classic Pawn Actions/AIModule system) — its standard
-- order is SoftScript=0, HardScript=1, Reaction=2, Logic=3, Ultimate=4.
-- "Logic" (3) is used here — the tier ordinary AI-decided behavior (not
-- player-scripted, not a reaction) runs at, matching what a real Otomo's
-- own default follow/combat layer would use. This specific value is NOT
-- confirmed against Palworld's own build — flagged as an assumption, easy
-- to try a different tier if this doesn't behave as expected live.
--
-- Two-hundred-and-second pass (2026-09-06): REWRITTEN from a one-shot
-- attempt (called once, at follow-start) into a repeated, per-tick push —
-- Dragón's own real observation (a FlowerRabbit glancing at the player
-- then resuming her own path a frame later, every ~1.5s) plus the
-- two-hundredth/two-hundred-and-first passes' analysis both point at the
-- same mechanism: a wild Pal's own AI continuously RE-DECIDES its root
-- action, so a composite pushed only once gets silently reclaimed almost
-- immediately. Calling SetRootComposite on the same cadence as the old
-- move-order nudge (TICK_INTERVAL_MS in Trust.lua, ~1.5s) is the direct,
-- agreed-on test of whether repetition alone lets the composite actually
-- win that ongoing competition.
--
-- Deliberately reuses ONE composite object per Pal (built once, cached
-- below) rather than calling StaticConstructObject fresh every tick
-- forever — repeating the SetRootComposite call achieves the "keep
-- reasserting" goal without also repeating the actual object
-- construction, which would be an unnecessary, unproven risk on top of
-- the one this pass is already testing.
--
-- Per the agreed plan's combat-assist step: Pal.hpp confirms
-- UPalAIActionOtomoDefault exposes its OWN native decision function for
-- exactly this question — `ShouldSetCombatAction()` — alongside
-- `FindNearestAttackTarget()`. This is the real logic a genuine Otomo
-- uses to decide follow vs. fight; asking the composite itself each tick
-- is more solid than guessing a trigger condition ourselves (and the
-- PalFollowerTweaks reference mod turned out to have nothing usable here
-- — it's a decorative "Funnel" follower/formation mod, unrelated to real
-- Otomo combat behavior, confirmed by re-reading its actual main.lua/
-- config.lua this pass, not just its file names).
--
-- Genuinely bigger risk category than anything else in this file
-- (constructing and attaching a real AI action object, not just reading a
-- field or issuing a movement command) — every native call here is
-- bracketed with its own before/after log line, per this project's
-- standing crash-diagnosis discipline. Success logging is throttled to
-- once per Pal (see loggedFollowTickOnce) so a healthy tick loop doesn't
-- spam the log forever — failures always log, every time.
--
-- Declared here, BEFORE Combat.StartFollowing calls anything that uses
-- it — Lua locals don't hoist (this project already got burned by exactly
-- this once before, hook-points.md's hundred-and-fortieth pass's
-- hook_describe bug: a local referenced before its own textual
-- declaration silently resolves as a nil global instead of the intended
-- upvalue, and the failure gets swallowed by whatever pcall/safe_call
-- wraps the call site).
local AI_REQUEST_PRIORITY_LOGIC = 3

-- Two-hundred-and-second pass: key (GetFullName()) -> { actionComp, composite }.
-- The cached composite is rebuilt automatically if either half goes
-- invalid (Pal despawned, GC'd, etc.) — see get_or_build_otomo_composite.
local OtomoCompositeCache = {}
local loggedFollowTickOnce = {}

local function get_or_build_otomo_composite(pal, key)
    local cached = OtomoCompositeCache[key]
    if cached then
        local actionCompValid = safe_call(function() return cached.actionComp:IsValid() end)
        local compositeValid = safe_call(function() return cached.composite:IsValid() end)
        if actionCompValid and compositeValid then
            return cached.actionComp, cached.composite
        end
        OtomoCompositeCache[key] = nil -- went invalid, rebuild fresh below
    end

    local controller = safe_call(function() return pal.Controller end)
    local controllerValid = controller ~= nil and safe_call(function() return controller:IsValid() end)
    if not controllerValid then
        Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — no usable Controller, cannot build the real Otomo composite (move-order nudge, if enabled, stays as the only mechanism)")
        return nil, nil
    end

    local actionComp = safe_call(function() return controller:GetAIActionComponent() end)
    local actionCompValid = actionComp ~= nil and safe_call(function() return actionComp:IsValid() end)
    if not actionCompValid then
        Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — no usable AIActionComponent (matches the eighty-sixth pass's open question — this wild Pal's AI likely runs a separate path), cannot build the real Otomo composite")
        return nil, nil
    end

    local nativeClass = safe_call(function() return StaticFindObject("/Script/Pal.PalAIActionOtomoDefault") end)
    local classValid = nativeClass ~= nil and safe_call(function() return nativeClass:IsValid() end)
    if not classValid then
        Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — could not resolve the UPalAIActionOtomoDefault class via StaticFindObject, aborting")
        return nil, nil
    end

    local fresh = safe_call(function() return StaticConstructObject(nativeClass, actionComp) end)
    local freshValid = fresh ~= nil and safe_call(function() return fresh:IsValid() end)
    Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — StaticConstructObject(UPalAIActionOtomoDefault) " .. (freshValid and "ok (built once, reused every tick from here)" or "FAILED"))
    if not freshValid then return nil, nil end

    OtomoCompositeCache[key] = { actionComp = actionComp, composite = fresh }
    return actionComp, fresh
end

-- Called every tick_followers pass (Trust.lua), same cadence the old
-- move-order nudge already used. See the file-header comment above this
-- section for the full reasoning.
function Combat.TickRealOtomoFollow(pal, key)
    if not USE_REPEATED_OTOMO_COMPOSITE then return end
    if not Combat.IsFollowing(pal) then return end
    local actionComp, composite = get_or_build_otomo_composite(pal, key)
    if not actionComp or not composite then return end

    local wantsCombat = safe_call(function() return composite:ShouldSetCombatAction() end)
    local modeOk, modeErr
    if wantsCombat then
        modeOk, modeErr = pcall(function() composite:SetOtomoCombatAction() end)
        if modeOk then
            Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — ShouldSetCombatAction()=true, switched to SetOtomoCombatAction()")
        else
            Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — ShouldSetCombatAction()=true but SetOtomoCombatAction() FAILED: " .. tostring(modeErr))
        end
    else
        modeOk, modeErr = pcall(function() composite:SetOtomoFollowAction() end)
        if not modeOk then
            Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — SetOtomoFollowAction() FAILED: " .. tostring(modeErr))
        end
    end

    local rootOk, rootErr = pcall(function() actionComp:SetRootComposite(composite, AI_REQUEST_PRIORITY_LOGIC) end)
    if rootOk then
        if not loggedFollowTickOnce[key] then
            loggedFollowTickOnce[key] = true
            Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — SetRootComposite ok, now being repeated every tick (further successes not logged individually to avoid spam)")
        end
    else
        Logger.log("[PalBonds/Combat] [REAL-FOLLOW] " .. tostring(key) .. " — SetRootComposite (repeated) FAILED: " .. tostring(rootErr))
    end
end

function Combat.Init()
    Logger.log(string.format(
        "[PalBonds/Combat] follow logic active — old move-order nudge %s, repeated real-Otomo-composite mechanism %s (see file header, Two-hundred-and-third pass)",
        USE_OLD_MOVE_ORDER_NUDGE and "ENABLED" or "disabled",
        USE_REPEATED_OTOMO_COMPOSITE and "ENABLED" or "disabled (confirmed not working live, 3/3 real follow-trigger events)"
    ))
end

function Combat.StartFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key then BondingState[key] = true end
    Logger.log("[PalBonds/Combat] " .. tostring(key) .. " marked as following (bonding)")

    -- Eighty-sixth pass (2026-09-03) DIAGNOSTIC, read-only. Dragón asked
    -- directly whether something more solid than this file's periodic-
    -- MoveTo approximation exists. Real lead found in the SDK header dump:
    -- `APalAIController:GetAIActionComponent()` returns a
    -- `UPalAIActionComponent` (a `UPawnActionsComponent` subclass) whose
    -- composite action classes include `UPalAIActionOtomoDefault`, which
    -- has `SetOtomoFollowAction()` / `SetOtomoCombatAction()` /
    -- `SetOtomoWorkAction()` / `SetOtomoBaseCampAction()` /
    -- `SetOtomoBerserker()` — the literal decision layer a REAL Otomo Pal
    -- uses to enter genuine follow behavior, not an external nudge fighting
    -- its own AI. That would be a much more solid fix than this file's
    -- approach. But there is no "Wild"-named composite class anywhere in
    -- the whole dump, which raises the real open question this log entry
    -- exists to answer: does a WILD Pal's AIController even have this
    -- component active at all, or does wild AI run a completely different
    -- path with no such hook point? This ONLY reads (GetAIActionComponent,
    -- GetCurrentAIActionCategory, GetCurrentAction_BP, GetFullName) —
    -- nothing is set, pushed, or changed. Fires once per follow-start, not
    -- per tick, so there's no spam risk. Getting real evidence here before
    -- touching anything is exactly the discipline that would have caught
    -- the eighteenth pass's `SetActiveAI(false)` mistake earlier.
    safe_call(function()
        local controller = pal.Controller
        if controller and controller:IsValid() then
            local actionComp = safe_call(function() return controller:GetAIActionComponent() end)
            if actionComp and actionComp:IsValid() then
                local category = safe_call(function() return actionComp:GetCurrentAIActionCategory() end)
                local currentAction = safe_call(function() return actionComp:GetCurrentAction_BP() end)
                local currentActionDesc = "nil"
                if currentAction then
                    currentActionDesc = safe_call(function() return currentAction:GetFullName() end) or tostring(currentAction)
                end
                Logger.log(string.format(
                    "[PalBonds/Combat] [FOLLOW-DIAG] %s HAS an AIActionComponent while wild — category=%s currentAction=%s (read-only check, see eighty-sixth pass)",
                    tostring(key), tostring(category), tostring(currentActionDesc)
                ))
            else
                Logger.log("[PalBonds/Combat] [FOLLOW-DIAG] " .. tostring(key) .. " has NO usable AIActionComponent while wild — the real Otomo follow system may not run on wild Pals at all (see eighty-sixth pass)")
            end
        end
    end)

    -- Two-hundred-and-second pass: the real composite is no longer built
    -- (or pushed) here as a one-shot — see TickRealOtomoFollow above.
    -- Trust.lua's tick_followers calls that function every tick from here
    -- on, which lazily builds the cached composite on its first real call.

    -- Two-hundred-and-seventh pass (2026-09-06): apply the companion preset
    -- the moment a Pal starts following. See Personality.ApplyCompanionPreset
    -- for the full reasoning — in short, this silences the Pal's own AI
    -- decisions ABOUT THE PLAYER (setting them to Ignore) so they stop
    -- overriding the move order below, which is the specific failure Dragón
    -- observed directly (a Pal turning toward him, then resuming its own
    -- path a frame later, once per tick).
    --
    -- Also switches on combat assist, per Dragón's explicit go-ahead: the
    -- three non-player Discover slots become Battle, so a bonded companion
    -- engages other Pals it notices while never turning on the player.
    safe_call(function()
        local okReq, Personality = pcall(require, "Personality")
        if not (okReq and Personality and Personality.ApplyCompanionPreset) then return end
        local palId = Personality.GetOrInitState and Personality.GetOrInitState(pal)
        if not palId then return end
        Personality.ApplyCompanionPreset(palId, pal, ENABLE_COMBAT_ASSIST)
    end)
end

function Combat.StopFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key then
        BondingState[key] = nil
        OtomoCompositeCache[key] = nil -- Two-hundred-and-second pass: drop the cached composite so a later re-follow builds fresh, not a stale reference
        loggedFollowTickOnce[key] = nil
    end
    Logger.log("[PalBonds/Combat] " .. tostring(key) .. " no longer following")
end

function Combat.IsFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    return key ~= nil and BondingState[key] == true
end

-- Called once per tick_followers pass (Trust.lua) for each currently-
-- following Pal. Issues a fresh move-to-player order via the Pal's own
-- AIController — a real, confirmed-safe native call (simple params, no
-- struct-by-value return), just not the real Otomo follow system.
--
-- Hundred-and-ninety-ninth pass (2026-09-06): Dragón ran a real controlled
-- test (deliberately stopped interacting right after crossing the 50%
-- follow trigger, then watched from a distance) and found a Pal that
-- simply never followed at all — a second one ran far enough that it
-- despawned, meaning it made essentially zero progress keeping up. This
-- function has ALWAYS called `PalMoveToLocation` without ever reading its
-- return value — and the header dump confirms it's not void, it returns a
-- real `TEnumAsByte<EPathFollowingRequestResult::Type>` (the standard
-- Unreal AIModule enum: 0=Failed, 1=AlreadyAtGoal, 2=RequestSuccessful).
-- If this call has been silently returning Failed every single tick since
-- this project's very first pass at following, that alone would explain
-- both of Dragón's reports without needing any deeper AI-state mystery.
-- Now captured and logged (a plain byte read, no new risk) so the next
-- real test finally shows whether this call is actually being accepted by
-- the engine at all.
function Combat.IssueFollowMoveOrder(pal, playerLoc)
    if not USE_OLD_MOVE_ORDER_NUDGE then return end
    if not Combat.IsFollowing(pal) then return end
    local controller = safe_call(function() return pal.Controller end)
    if not controller or not controller:IsValid() then return end

    -- Two-hundred-and-seventh pass: cancel whatever the Pal is currently
    -- doing IMMEDIATELY before issuing the order. This is the same
    -- AllCancelAction_Logic_HardScript_Reaction that the personality
    -- interrupt uses and that was confirmed to succeed on 5 of 5 real wild
    -- Pals — it has simply never been paired with movement before, only
    -- with preset swaps. Without it, the Pal's in-progress wander/graze
    -- action keeps running and the move order is effectively queued behind
    -- something that never yields, which matches the observed "turns toward
    -- the player, then carries on with what it was doing" behaviour.
    -- Best-effort: a failure here still lets the order below be issued.
    safe_call(function()
        local actionComp = controller:GetAIActionComponent()
        if actionComp and actionComp:IsValid() then
            -- Exact call shape copied from Personality.interrupt_and_resense,
            -- which is the version confirmed working live: it is the
            -- controller's AI action component (NOT the Pal's own
            -- ActionComponent), and it takes the actor as an argument.
            actionComp:AllCancelAction_Logic_HardScript_Reaction(pal)
        end
    end)

    local ok, resultOrErr = pcall(function()
        return controller:PalMoveToLocation(playerLoc, FOLLOW_ACCEPTANCE_RADIUS, false, true, true, true, nil, true)
    end)
    -- Two-hundred-and-eighth pass (2026-09-06): this used to log every
    -- single order — 2-3 lines every 1.5s PER FOLLOWER, each forced to disk
    -- by Logger's flush-per-line design, so the cost scaled directly with
    -- how many Pals were following. That is a real part of the extra lag
    -- Dragón felt while running three followers at once.
    --
    -- The question it was added for (two-hundredth pass: "is
    -- PalMoveToLocation silently returning Failed all this time?") is now
    -- ANSWERED, and the answer is good: across Dragón's whole run it
    -- returned only 2 (RequestSuccessful) and 1 (AlreadyAtGoal), never 0
    -- (Failed). "AlreadyAtGoal" dominating is the strongest evidence yet
    -- that the companion-preset fix worked — the Pals are genuinely
    -- reaching and staying with the player rather than drifting off.
    --
    -- So: only log a real FAILURE, or a change in the result value. Steady
    -- successful following is now silent.
    if ok then
        local resultNum = tonumber(resultOrErr)
        if resultNum == 0 or resultOrErr ~= lastMoveOrderResult then
            lastMoveOrderResult = resultOrErr
            Logger.log("[PalBonds/Combat] [MOVE-ORDER-RESULT] PalMoveToLocation now returning: " .. tostring(resultOrErr) .. " (0=Failed, 1=AlreadyAtGoal, 2=RequestSuccessful; only logged on change or on failure)")
        end
    else
        Logger.log("[PalBonds/Combat] PalMoveToLocation call failed (non-fatal, caught): " .. tostring(resultOrErr))
    end
end

return Combat
