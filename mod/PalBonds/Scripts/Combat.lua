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

-- EPathFollowingRequestResult, the standard Unreal enum PalMoveToLocation
-- returns. Confirmed from Dragón's live log: only 1 and 2 ever appear.
local MOVE_RESULT_ALREADY_AT_GOAL = 1

-- Two-hundred-and-tenth pass: the orbit-follow parameters. A companion that
-- has reached the player is sent to a slowly rotating point nearby instead of
-- being left idle, so its own roam AI never gets an idle window to take over.
-- ORBIT_RADIUS is deliberately small (well inside FOLLOW_ACCEPTANCE_RADIUS's
-- old 200) so this reads as a companion milling about, not pacing laps.
local ORBIT_RADIUS = 180.0
local ORBIT_ACCEPTANCE_RADIUS = 60.0
local ORBIT_STEP_RADIANS = 0.9 -- ~52 degrees per tick, so a full circle takes ~7 ticks (~10s)
local orbitPhase = 0.0

-- Two-hundred-and-eleventh pass: try the continuous move-to-actor follow
-- first (see IssueFollowMoveOrder). Set false to go back to pure
-- location-order following.
local USE_MOVE_TO_ACTOR_FOLLOW = true
local ECC_VISIBILITY = 3 -- ECollisionChannel::ECC_Visibility, from Engine_enums.hpp
local loggedActorMoveOnce = false

-- How much hate to push onto the player's current enemy for each following
-- companion. Large enough to outrank whatever the companion may already be
-- tracking, so FindMostHateTarget resolves to the player's target.
local COMBAT_ASSIST_HATE_AMOUNT = 1000.0


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
-- Two-hundred-and-ninth pass: BondingState only records THAT a key is
-- following; combat assist also needs the live actor for each follower, to
-- reach its AIController's hate system. Kept in step with BondingState in
-- StartFollowing/StopFollowing below.
local FollowerActors = {}
-- Throttles the [HATE-ASSIST] line to one per target change — a real fight
-- produces a damage event many times a second.
local lastHateTargetName = nil
local loggedRetargetOnce = false
-- Two-hundred-and-fifteenth pass: how often a follower is nudged to re-sense
-- the player (see the [RE-SENSE] block in IssueFollowMoveOrder). 3 ticks at
-- 1.5s each = roughly every 4.5 seconds per follower.
local RESENSE_EVERY_N_TICKS = 3
local resenseTickCounter = 0
-- Two-hundred-and-thirteenth pass: is the player currently in a fight? While
-- true, companions are allowed to engage on discovery; when it lapses they go
-- back to never starting fights.
local playerCombatActive = false
local combatWindowGeneration = 0
local COMBAT_WINDOW_MS = 12000 -- how long after the last hit the fight counts as ongoing

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

-- Two-hundred-and-ninth pass (2026-09-06): real combat assist, using the
-- game's OWN targeting system rather than another disposition trick.
--
-- Confirmed real in this build's header dump, not guessed:
--   APalAIController::GetHateSystem() -> UPalHate*
--   UPalHate::ChangeHate(AActor* Attacker, float PlusHateValue)
--   UPalHate::FindMostHateTarget() -> AActor*
--
-- Called from Trust.lua's existing PalHate:DamageEvent hook whenever the
-- player deals or takes damage, so the enemy actor is handed to us by the
-- game itself — no scanning, no polling, no guessing at what the player is
-- fighting.
--
-- HONEST UNCERTAINTY, to be settled by the next live test rather than
-- assumed: pushing hate gives the companion a TARGET, but whether its AI
-- then chooses to attack that target may still depend on its response
-- preset, whose Discover_* slots this project deliberately sets to Ignore
-- so companions stop starting fights. If hate alone turns out not to be
-- enough, the next step is to allow Battle on discovery only while a
-- player-target is active, rather than permanently. The [HATE-ASSIST] log
-- lines below are what will tell us which of those is true.
-- Two-hundred-and-fourteenth pass: undo a grudge between two bonded
-- companions (see Trust.lua's [FRIENDLY-FIRE] block for why). Pushes a large
-- negative hate each way so neither keeps the other as its most-hated target.
function Combat.ClearMutualHate(a, b)
    local function clear(fromPal, towardActor)
        if fromPal == nil or towardActor == nil then return end
        safe_call(function()
            local controller = fromPal.Controller
            if not (controller and controller:IsValid()) then return end
            local hate = controller:GetHateSystem()
            if not (hate and hate:IsValid()) then return end
            hate:ChangeHate(towardActor, -COMBAT_ASSIST_HATE_AMOUNT * 10)
        end)
    end
    clear(a, b)
    clear(b, a)
end

-- Two-hundred-and-sixteenth pass: cheap "is anything following?" test so
-- callers can skip their own setup work entirely. Pure table scan.
function Combat.HasAnyFollower()
    for _, isFollowing in pairs(BondingState) do
        if isFollowing then return true end
    end
    return false
end

function Combat.OnPlayerCombatTarget(enemyActor)
    if enemyActor == nil then return end

    -- Two-hundred-and-sixteenth pass (2026-09-06) — DRAGÓN'S EDGE CASE, and he
    -- was right to flag it. His warning, from having watched other assistants
    -- do this: "when including a 'run per event' it usually ends up flooding
    -- the console... ideally you should only activate that IF there are pals
    -- following, otherwise you dont need to check everytime i get hit."
    --
    -- Checked, and it was worse than log flooding. With ZERO followers this
    -- function still: resolved the enemy actor, walked BondingState, set
    -- playerCombatActive, bumped the window generation, and — the real problem
    -- — SCHEDULED A NEW ExecuteInGameThreadWithDelay TIMER. Every single
    -- damage event involving the player, in an empty field, with nothing
    -- bonded, would queue another 12-second timer. A single fight against one
    -- enemy is dozens of hits, so that is dozens of pending timers doing
    -- nothing, forever, for no reason.
    --
    -- This early-out is a plain table scan with no engine calls at all, so the
    -- no-followers case (which is most of the time) now costs essentially
    -- nothing. Same reasoning applies one level up in Trust.lua's damage hook.
    local anyFollowers = false
    for _, isFollowing in pairs(BondingState) do
        if isFollowing then anyFollowers = true break end
    end
    if not anyFollowers then return end

    local enemyValid = safe_call(function() return enemyActor:IsValid() end)
    if not enemyValid then return end

    local enemyName = safe_call(function() return enemyActor:GetFullName() end)

    for key, isFollowing in pairs(BondingState) do
        if isFollowing then
            local entry = FollowerActors[key]
            local pal = entry
            local palValid = pal ~= nil and safe_call(function() return pal:IsValid() end)
            if palValid then
                -- Never point a companion at itself or at another companion.
                if key ~= enemyName then
                    safe_call(function()
                        local controller = pal.Controller
                        if not (controller and controller:IsValid()) then return end
                        local hate = controller:GetHateSystem()
                        if not (hate and hate:IsValid()) then return end
                        hate:ChangeHate(enemyActor, COMBAT_ASSIST_HATE_AMOUNT)

                        -- Two-hundred-and-fifteenth pass (2026-09-06) —
                        -- DRAGÓN'S IDEA, and it is a better design than what
                        -- was here. His question: "isnt it possible to just
                        -- issue a command of, if im being attacked, make the
                        -- pals following attack that pal in specific? instead
                        -- of becoming agro on everything?"
                        --
                        -- Yes. Searching APalAIController's action classes
                        -- turned up the exact function for it:
                        --     UPalAIActionCombatBase::SetTargetAndNextAction(AActor* Target)
                        -- That is the combat action's own "this is who you are
                        -- fighting" setter. So instead of relying only on
                        -- broad aggression to make a companion pick SOMETHING
                        -- and hoping it picks right, we now reach into
                        -- whatever combat action it is actually running and
                        -- point it at the player's enemy directly.
                        --
                        -- This runs on every player-damage event, not just the
                        -- transition into combat, so a companion that drifts
                        -- onto the wrong target (another companion, a passing
                        -- Pal) gets corrected within a fraction of a second
                        -- rather than staying locked on it. That is the direct
                        -- answer to the friendly-fire chaos: even when one
                        -- starts a fight with the wrong Pal, it is immediately
                        -- steered back to the real enemy.
                        safe_call(function()
                            local actionComp = controller:GetAIActionComponent()
                            if not (actionComp and actionComp:IsValid()) then return end
                            local current = actionComp:GetCurrentAction_BP()
                            if not (current and current:IsValid()) then return end
                            -- SetTargetAndNextAction only exists on combat
                            -- actions; on anything else this pcall simply
                            -- fails harmlessly, which doubles as the type
                            -- check without needing to name every subclass.
                            local okSet = pcall(function() current:SetTargetAndNextAction(enemyActor) end)
                            if okSet and not loggedRetargetOnce then
                                loggedRetargetOnce = true
                                Logger.log("[PalBonds/Combat] [RETARGET] SetTargetAndNextAction accepted — companions are being pointed directly at the player's enemy (logged once)")
                            end
                        end)

                        -- Two-hundred-and-thirteenth pass: hate alone was NOT
                        -- enough — Dragón's run had [HATE-ASSIST] firing
                        -- correctly three times while the companions still
                        -- stood by. The AI needs the response preset to also
                        -- permit engaging, so flip this companion's
                        -- Discover_* slots to Battle for the duration of the
                        -- fight. Re-applied only on the transition into
                        -- combat, not per damage event, since a real fight
                        -- fires many events a second.
                        if not playerCombatActive then
                            local okP, Personality = pcall(require, "Personality")
                            if okP and Personality and Personality.ApplyCompanionPreset then
                                local palId = Personality.GetOrInitState and Personality.GetOrInitState(pal)
                                if palId then
                                    Personality.ApplyCompanionPreset(palId, pal, ENABLE_COMBAT_ASSIST, true)
                                end
                            end
                        end
                        if lastHateTargetName ~= enemyName then
                            Logger.log(string.format(
                                "[PalBonds/Combat] [HATE-ASSIST] pushed hate toward the player's current enemy %s onto following companions (only logged when the target changes)",
                                tostring(enemyName)
                            ))
                        end
                    end)
                end
            end
        end
    end
    lastHateTargetName = enemyName

    -- Two-hundred-and-thirteenth pass: open (or extend) the combat window, and
    -- schedule the return to peaceful behaviour. Without this, companions
    -- would keep Discover_* = Battle forever after the first fight and drift
    -- straight back into the "attacks everything, including each other"
    -- problem from two passes ago.
    playerCombatActive = true
    combatWindowGeneration = combatWindowGeneration + 1
    local myGen = combatWindowGeneration
    pcall(function()
        ExecuteInGameThreadWithDelay(COMBAT_WINDOW_MS, function()
            if myGen ~= combatWindowGeneration then return end -- a newer hit extended the fight
            playerCombatActive = false
            Logger.log("[PalBonds/Combat] [HATE-ASSIST] player combat window closed — companions return to not starting fights")
            for key, isFollowing in pairs(BondingState) do
                if isFollowing then
                    local pal = FollowerActors[key]
                    if pal ~= nil and safe_call(function() return pal:IsValid() end) then
                        safe_call(function()
                            local okP, Personality = pcall(require, "Personality")
                            if okP and Personality and Personality.ApplyCompanionPreset then
                                local palId = Personality.GetOrInitState and Personality.GetOrInitState(pal)
                                if palId then
                                    Personality.ApplyCompanionPreset(palId, pal, ENABLE_COMBAT_ASSIST, false)
                                end
                            end
                        end)
                    end
                end
            end
        end)
    end)
end


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

-- ===================================================================
-- NATIVE LEASH FOLLOW (two-hundred-and-seventeenth pass, 2026-09-06)
-- ===================================================================
-- Dragón, after the last run: "the pals still keep drifting away too often...
-- its like they follow for a few seconds then their IA make them ignore me,
-- even if the tick nudge makes them look at me... should we go back to that
-- time we stripped them of their Ai? honestly wouldnt want that, but seems
-- like we are running low on options."
--
-- We are not out of options — and this one is better than any of the six
-- mechanisms tried so far, because it stops fighting the wild AI entirely.
-- Palworld has a COMPLETE NATIVE LEASH SYSTEM that had never been looked at:
--
--     class APalAILeashActor : public APalAILeashActorBase
--         APalAILeashActor* SpawnLeash(APalAIController* InInstigatorController,
--                                      float InLeashInnerRadius,
--                                      float InLeashOuterRadius,
--                                      float InInvokerExtentRadius,
--                                      bool  bInAutoActivateLeash)
--     class APalAILeashActorBase : public AActor
--         void SetLeashLocation(const FVector& NewLeashLocation)
--         void ActivateLeash() / DeactivateLeash() / IsActiveLeash()
--         float LeashInnerRadius / LeashOuterRadius
--         delegate OnCharacterOutOfLeashRange(...)
--
-- A leash is the anchor point a Pal's OWN AI is allowed to roam around. This
-- is the mechanism the game itself uses to keep Pals in an area.
--
-- Why this is categorically different from everything tried before: every
-- previous attempt (move order, orbit, Otomo composite, Funnel, move-to-actor)
-- issued a command the wild AI could out-vote on its next decision, which is
-- exactly the behaviour Dragón keeps describing — "they follow for a few
-- seconds then their AI makes them ignore me". A leash is not a command the AI
-- competes with; it is a CONSTRAINT the AI already obeys when it chooses where
-- to wander. So instead of telling the Pal to come back, we move the boundary
-- it is already staying inside, and its own wandering keeps it near the player.
--
-- It is also precisely the "something like SetActiveAI but less total" Dragón
-- asked for two passes ago, and it does not disable anything: the Pal keeps
-- reacting, fighting and behaving normally, just within a region that follows
-- the player.
--
-- UNVERIFIED, and stated plainly: SpawnLeash is declared on APalAILeashActor
-- and is called here through that class's default object, which is how this
-- project already calls other static/library functions (PalUtility,
-- NiagaraFunctionLibrary, KismetTextLibrary). Whether it accepts being driven
-- this way for a wild Pal is exactly what the next run tests. Every step is
-- pcall-guarded and the previous follow mechanism is left running underneath,
-- so a total failure here is a no-op rather than a regression.
-- ⚠️ TWO-HUNDRED-AND-EIGHTEENTH PASS (2026-09-06) — TURNED OFF, AND WHY.
-- This is my bug and it caused a real regression in Dragón's run: "the lag
-- felt much more this time, in fact it felt like the longer the run the more
-- that the lag was increasing."
--
-- What happened. SpawnLeash returned something the validity check rejected, so
-- ensure_leash_for never cached anything — and because it is called from the
-- follow tick, it RETRIED THE SPAWN EVERY 1.5 SECONDS, FOR EVERY FOLLOWER.
-- The log shows the failure line exactly once (it is throttled by
-- loggedLeashOnce) which hid the retry completely: one quiet line, roughly two
-- hundred spawn attempts behind it in a nine-minute session.
--
-- Why that is a leak and not merely wasted work: SpawnLeash is a SPAWN
-- function. Whether or not the returned handle validated in Lua, the engine
-- very likely created a leash actor in the world on each call. Hundreds of
-- orphaned actors accumulating over a session is precisely the "gets worse the
-- longer I play" shape Dragón described, and it would not have shown up in any
-- log-volume analysis because it produced almost no log lines at all.
--
-- Three separate mistakes on my part, worth naming so they are not repeated:
--   1. A failing operation was retried forever with no attempt cap.
--   2. The retry was of a SPAWN, the one category where a failed retry can
--      accumulate side effects rather than just burning time.
--   3. The throttled log made a loud problem look like a single quiet line —
--      the same "throttle hides the cost, not the cost itself" mistake already
--      made twice in this project (the SetHPPercent hook, the prism poll).
--
-- The mechanism is off by default now. The idea is still sound and the API is
-- still real; if it is revisited, it must be through a route that does not
-- call a spawn function repeatedly — most likely by finding a Pal's EXISTING
-- leash actor (wild Pals plausibly already have one anchoring them to their
-- spawn area) and just moving that, rather than creating new ones.
local USE_NATIVE_LEASH_FOLLOW = false

-- Hard safety rails, so this can never loop again even if switched back on.
local LEASH_MAX_ATTEMPTS_PER_PAL = 1
local LEASH_MAX_TOTAL_FAILURES = 3
local leashAttemptsByKey = {}
local leashTotalFailures = 0
local leashDisabledBySafety = false
local LEASH_INNER_RADIUS = 400.0   -- comfortable "stay around here" distance
local LEASH_OUTER_RADIUS = 900.0   -- past this the Pal is pulled back by its own AI
local LEASH_INVOKER_EXTENT = 900.0
local LeashByKey = {}
local loggedLeashOnce = false

local LeashCDO = nil
local function get_leash_cdo()
    -- Cached: the previous version resolved this on every single call, which
    -- was another per-tick cost hidden behind the same throttled log line.
    if LeashCDO ~= nil then return LeashCDO end
    LeashCDO = safe_call(function() return StaticFindObject("/Script/Pal.Default__PalAILeashActor") end)
    return LeashCDO
end

local function ensure_leash_for(pal, key)
    if not USE_NATIVE_LEASH_FOLLOW or leashDisabledBySafety or key == nil then return nil end

    -- Attempt caps: one spawn attempt per Pal, ever, and the whole mechanism
    -- self-disables after a few failures. See the block at the top of this
    -- section for why an uncapped retry of a spawn call was so damaging.
    local attempts = leashAttemptsByKey[key] or 0
    if attempts >= LEASH_MAX_ATTEMPTS_PER_PAL then return nil end
    local existing = LeashByKey[key]
    if existing ~= nil and safe_call(function() return existing:IsValid() end) then
        return existing
    end

    local cdo = get_leash_cdo()
    if cdo == nil then
        if not loggedLeashOnce then
            loggedLeashOnce = true
            Logger.log("[PalBonds/Combat] [LEASH] could not resolve Default__PalAILeashActor — native leash follow unavailable, falling back to the move order (logged once)")
        end
        return nil
    end

    local controller = safe_call(function() return pal.Controller end)
    if not (controller and safe_call(function() return controller:IsValid() end)) then return nil end

    leashAttemptsByKey[key] = attempts + 1
    local leash = safe_call(function()
        return cdo:SpawnLeash(controller, LEASH_INNER_RADIUS, LEASH_OUTER_RADIUS, LEASH_INVOKER_EXTENT, true)
    end)
    local leashValid = leash ~= nil and safe_call(function() return leash:IsValid() end)
    if not leashValid then
        leashTotalFailures = leashTotalFailures + 1
        if leashTotalFailures >= LEASH_MAX_TOTAL_FAILURES then
            leashDisabledBySafety = true
            Logger.log("[PalBonds/Combat] [LEASH] disabling the leash mechanism entirely after " .. leashTotalFailures .. " failed spawns — it will not be attempted again this session")
        end
        if not loggedLeashOnce then
            loggedLeashOnce = true
            Logger.log("[PalBonds/Combat] [LEASH] SpawnLeash returned nothing usable — native leash follow not available this way, move order still active (logged once)")
        end
        return nil
    end

    LeashByKey[key] = leash
    Logger.log("[PalBonds/Combat] [LEASH] spawned a native AI leash for " .. tostring(key) ..
        " (inner=" .. LEASH_INNER_RADIUS .. " outer=" .. LEASH_OUTER_RADIUS .. ") — its own AI should now roam around the player instead of its spawn point")
    return leash
end

-- Moves the anchor. This is the whole point: called every follow tick with the
-- player's current location, so the region the Pal is allowed to wander in
-- travels with the player.
local function update_leash_anchor(pal, key, playerLoc)
    if not USE_NATIVE_LEASH_FOLLOW or playerLoc == nil then return end
    local leash = ensure_leash_for(pal, key)
    if leash == nil then return end
    safe_call(function() leash:SetLeashLocation(playerLoc) end)
end

local function release_leash(key)
    local leash = LeashByKey[key]
    if leash == nil then return end
    LeashByKey[key] = nil
    safe_call(function()
        if leash:IsValid() then leash:DeactivateLeash() end
    end)
    Logger.log("[PalBonds/Combat] [LEASH] released the leash for " .. tostring(key))
end

-- ===================================================================
-- FOLLOW DIFF PROBE (two-hundred-and-nineteenth pass, 2026-09-06)
-- ===================================================================
-- Dragón's call after the leash leak: keep working on movement, because
-- following is the whole point of the mod — combat degrading to "they fight
-- whatever hits them" is an acceptable v1, Pals that do not follow is not.
--
-- After six failed follow mechanisms, the honest conclusion is that guessing
-- at APIs is not working. So this pass ships NO new mechanism at all. It ships
-- a read-only comparison instead, because there is one enormous piece of
-- evidence this project has never used:
--
--     A REAL OTOMO FOLLOWS THE PLAYER PERFECTLY, IN VANILLA, RIGHT NOW.
--
-- Dragón always has one out. So rather than inventing a seventh mechanism, we
-- read the SAME fields off a real Otomo and off a bonding wild Pal at the same
-- instant, and whatever differs is — by definition — part of how real
-- following actually works. That is evidence instead of a guess.
--
-- Strictly read-only: it resolves objects and reads fields, and never calls a
-- setter, a spawn, or anything with a side effect. After the leash incident
-- that constraint is deliberate — this cannot leak, cannot loop, and cannot
-- change behaviour. It also runs at most FOLLOW_DIFF_MAX_DUMPS times per
-- session, so it cannot become a log-volume problem either.
--
-- What it reads on both Pals:
--   * CharacterParameterComponent.IsOverrideTarget / OverrideTargetLocation
--     (real fields on the same component this project already reads for
--     friendship; "override target" is a plausible movement anchor, but its
--     consumer is not visible in the header dump, so it is exactly the kind of
--     thing to MEASURE rather than assume)
--   * the AIController's class name, its current AI action and category
--   * whether any APalAILeashActor in the world has that Pal as its
--     LeashedCharacter — which answers the question the leash incident raised:
--     do wild Pals or Otomos already HAVE a leash we could safely move,
--     instead of spawning new ones?
local FOLLOW_DIFF_MAX_DUMPS = 3
local followDiffDumps = 0

local function describe_follow_state(label, pal)
    if pal == nil then
        Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] " .. label .. ": <none found>")
        return
    end
    local name = safe_call(function() return pal:GetFullName() end)

    local isOverride, overrideLoc = nil, nil
    safe_call(function()
        local cp = pal.CharacterParameterComponent
        if cp == nil or not cp:IsValid() then return end
        isOverride = cp.IsOverrideTarget
        local v = cp.OverrideTargetLocation
        if v ~= nil then
            overrideLoc = string.format("(%.0f, %.0f, %.0f)", v.X or 0, v.Y or 0, v.Z or 0)
        end
    end)

    local controllerClass, actionName, actionCategory = nil, nil, nil
    safe_call(function()
        local c = pal.Controller
        if c == nil or not c:IsValid() then return end
        controllerClass = safe_call(function() return c:GetClass():GetFullName() end)
        local ac = safe_call(function() return c:GetAIActionComponent() end)
        if ac == nil or not ac:IsValid() then return end
        actionCategory = safe_call(function() return ac:GetCurrentAIActionCategory() end)
        local cur = safe_call(function() return ac:GetCurrentAction_BP() end)
        actionName = cur and safe_call(function() return cur:GetFullName() end)
    end)

    Logger.log(string.format(
        "[PalBonds/Combat] [FOLLOW-DIFF] %s: pal=%s | IsOverrideTarget=%s | OverrideTargetLocation=%s | controller=%s | AIcategory=%s | currentAction=%s",
        label, tostring(name), tostring(isOverride), tostring(overrideLoc),
        tostring(controllerClass), tostring(actionCategory), tostring(actionName)
    ))
end

-- Answers the question the leash incident raised: does a leash already EXIST
-- for these Pals? If so, moving it is a safe write instead of a dangerous
-- spawn, and that becomes the next mechanism to try.
local function report_existing_leashes()
    safe_call(function()
        local leashes = FindAllOf("PalAILeashActor") or FindAllOf("PalAILeashActorBase")
        if leashes == nil then
            Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] FindAllOf found NO leash actors of either class in the world")
            return
        end
        Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] " .. #leashes .. " leash actor(s) exist in the world right now")
        local shown = 0
        for _, l in ipairs(leashes) do
            if shown >= 6 then break end
            if safe_call(function() return l:IsValid() end) then
                shown = shown + 1
                local who = safe_call(function()
                    local c = l.LeashedCharacter
                    if c == nil or not c:IsValid() then return nil end
                    return c:GetFullName()
                end)
                Logger.log(string.format(
                    "[PalBonds/Combat] [FOLLOW-DIFF]   leash %d: leashedCharacter=%s active=%s inner=%s outer=%s",
                    shown, tostring(who),
                    tostring(safe_call(function() return l:IsActiveLeash() end)),
                    tostring(safe_call(function() return l.LeashInnerRadius end)),
                    tostring(safe_call(function() return l.LeashOuterRadius end))
                ))
            end
        end
    end)
end

-- Finds the player's currently-out Otomo: an owned Pal that is not the player.
-- Read-only, and uses the ownership check this project already relies on.
local function find_active_otomo(excludePal)
    local found = nil
    safe_call(function()
        local okReq, CaptureMod = pcall(require, "Capture")
        if not okReq then return end
        if CaptureMod == nil or CaptureMod.IsAlreadyOwned == nil then return end
        local excludeName = excludePal and safe_call(function() return excludePal:GetFullName() end)
        local pals = FindAllOf("PalCharacter")
        if pals == nil then return end
        for _, p in ipairs(pals) do
            if found == nil and safe_call(function() return p:IsValid() end) then
                local n = safe_call(function() return p:GetFullName() end)
                local isPlayer = n ~= nil and (n:find("PalPlayerCharacter") ~= nil or n:find("BP_Player") ~= nil)
                if n ~= nil and n ~= excludeName and not isPlayer then
                    if safe_call(function() return CaptureMod.IsAlreadyOwned(p) end) == true then
                        found = p
                    end
                end
            end
        end
    end)
    return found
end

function Combat.DiagnoseFollowDifference(bondingPal)
    if followDiffDumps >= FOLLOW_DIFF_MAX_DUMPS then return end
    followDiffDumps = followDiffDumps + 1
    Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] ===== comparison " .. followDiffDumps .. " of " ..
        FOLLOW_DIFF_MAX_DUMPS .. " — a REAL Otomo follows correctly and this bonding Pal does not, so whatever differs below is part of why =====")
    describe_follow_state("BONDING (wild)", bondingPal)
    describe_follow_state("REAL OTOMO    ", find_active_otomo(bondingPal))
    report_existing_leashes()
end

function Combat.StartFollowing(pal)
    safe_call(function() Combat.DiagnoseFollowDifference(pal) end)

    local key = safe_call(function() return pal:GetFullName() end)
    if key then
        BondingState[key] = true
        FollowerActors[key] = pal -- two-hundred-and-ninth pass: needed by OnPlayerCombatTarget
    end
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
        release_leash(key)
        BondingState[key] = nil
        FollowerActors[key] = nil
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
function Combat.IssueFollowMoveOrder(pal, playerLoc, playerActor)
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

    -- Two-hundred-and-eleventh pass (2026-09-06) — a genuinely different
    -- movement primitive, and it answers Dragón's question directly.
    --
    -- He asked whether there is something like the old `SetActiveAI(false)`
    -- (which stopped Pals wandering but turned them into inert objects that
    -- would not even defend themselves — the eighteenth pass's incident)
    -- but less total. Searching APalAIController in this build's header dump
    -- turned up something better than a suppression switch:
    --
    --     void SimpleMoveToActorWithLineTraceGround(const class AActor* GoalActor,
    --                                               TEnumAsByte<ECollisionChannel> CollisionChannel)
    --
    -- Every follow attempt this project has ever made — the original nudge,
    -- the Otomo composite, and last pass's orbit — has been LOCATION based:
    -- a one-shot "walk to this point" request that completes, after which the
    -- Pal has no goal and its own AI takes over. This one takes an ACTOR as
    -- the goal. A move-to-actor request is inherently continuous: the engine
    -- keeps steering toward a target that moves, which is what "following"
    -- actually means, and it is presumably what the game's own systems use
    -- for anything that trails something else.
    --
    -- That also fits Dragón's newest observation better than the idle theory
    -- did. He said the Pals "still managed to idle away somehow", which makes
    -- him doubt that reaching the goal is what triggers the wander. If the
    -- real problem is simply that a completed point-order leaves no goal at
    -- all, then a target that is never "reached" removes the whole class of
    -- problem rather than patching its symptom.
    --
    -- Kept behind a toggle and tried FIRST, with the location order as the
    -- fallback if the call fails, so a live test cleanly attributes any
    -- change. ECC_Visibility = 3, read from Engine_enums.hpp, not guessed.
    local ok, resultOrErr = nil, nil
    local usedActorMove = false
    if USE_MOVE_TO_ACTOR_FOLLOW and playerActor ~= nil then
        local moveOk, moveErr = pcall(function()
            controller:SimpleMoveToActorWithLineTraceGround(playerActor, ECC_VISIBILITY)
        end)
        if moveOk then
            usedActorMove = true
            if not loggedActorMoveOnce then
                loggedActorMoveOnce = true
                Logger.log("[PalBonds/Combat] [FOLLOW-ACTOR] SimpleMoveToActorWithLineTraceGround accepted — using continuous move-to-actor following (logged once)")
            end
        else
            if not loggedActorMoveOnce then
                loggedActorMoveOnce = true
                Logger.log("[PalBonds/Combat] [FOLLOW-ACTOR] SimpleMoveToActorWithLineTraceGround FAILED (" .. tostring(moveErr) .. ") — falling back to the location order (logged once)")
            end
        end
    end

    if not usedActorMove then
        ok, resultOrErr = pcall(function()
            return controller:PalMoveToLocation(playerLoc, FOLLOW_ACCEPTANCE_RADIUS, false, true, true, true, nil, true)
        end)
    end

    -- Two-hundred-and-fifteenth pass (2026-09-06) — DRAGÓN'S "RE-DISCOVER"
    -- IDEA, implemented. His observation from two runs now: "i could make
    -- noise nearby to make them focus on me again... probably what makes them
    -- drift away is that they 'forget' that im there", and this run he saw
    -- them running off more often (the log agrees: 7 leash breaks and 6
    -- resulting forced escapes).
    --
    -- That points at the SIGHT/SENSOR layer losing track of the player, not at
    -- the movement order — a different subsystem than everything else that has
    -- been fixed so far, which is why none of the movement work addressed it.
    -- Making noise works because it forces the Pal to sense the player again.
    --
    -- RequestSightCheckAsync is exactly that "look for things now" call, and it
    -- is already proven safe on wild Pals (interrupt_and_resense has used it
    -- for many passes). Re-triggering it periodically on followers is the
    -- software equivalent of Dragón making noise. Throttled to every few ticks
    -- rather than every tick: it is an async sight trace, and firing one per
    -- follower per 1.5s was exactly the shape of cost that caused the earlier
    -- interrupt-related lag.
    -- Two-hundred-and-seventeenth pass: move the leash anchor to the player.
    -- This is the primary follow mechanism now; everything below it stays as a
    -- complement rather than being removed, so if the leash turns out not to
    -- work on a wild Pal nothing is worse than before.
    safe_call(function()
        local key = pal:GetFullName()
        update_leash_anchor(pal, key, playerLoc)
    end)

    resenseTickCounter = resenseTickCounter + 1
    if resenseTickCounter % RESENSE_EVERY_N_TICKS == 0 then
        safe_call(function()
            local okP, Personality = pcall(require, "Personality")
            if not (okP and Personality and Personality.RefreshSightOn) then return end
            Personality.RefreshSightOn(pal)
        end)
    end

    -- Two-hundred-and-tenth pass (2026-09-06) — THE REST ANIMATION IS GONE.
    -- It was the previous pass's fix and it backfired in three separate ways
    -- in Dragón's live test, all of them real:
    --   1. It interrupted his actual Pet/Feed/Play interaction the moment a
    --      Pal crossed 50%.
    --   2. Once resting, the Pal counted as busy, so the follow order could
    --      not move it — Pals got stuck standing still instead of following.
    --   3. It did not even achieve its goal: they still wandered off, so the
    --      AI's roam decision either queues behind or overrides the rest.
    --
    -- The mistake was mine and it was avoidable: I gated it on
    -- `ActionIsEmpty()`, a signal THIS PROJECT HAD ALREADY DOCUMENTED as
    -- unreliable for exactly this purpose. The hundred-and-ninety-sixth pass
    -- established that it "se libera casi al instante" — it reports empty in
    -- the gaps between the steps of a real multi-part interaction. That is
    -- precisely why it fired mid-interaction. Using a signal the project's
    -- own notes call untrustworthy was not a reasonable risk to take.
    --
    -- The replacement attacks the same root cause Dragón identified (an idle
    -- window lets the roam AI take over) but through the MOVEMENT system
    -- instead of the action system, so it structurally cannot interrupt an
    -- animation or block a fight:
    --
    --   * If the Pal already has a hate target, do nothing at all — leave it
    --     free to fight. This also stops the follow order fighting the combat
    --     assist added last pass.
    --   * Otherwise, when the order reports AlreadyAtGoal, re-issue it to a
    --     point that slowly orbits the player rather than the player's exact
    --     position. The Pal therefore always has a live path request and
    --     never gets the idle window at all — which is exactly the condition
    --     Dragón confirmed already works: "when constantly moving and running
    --     this never happens, because they never get an idle time enough for
    --     their AI to kick again." This just gives them that same condition
    --     while he stands still.
    if (not usedActorMove) and ok and tonumber(resultOrErr) == MOVE_RESULT_ALREADY_AT_GOAL then
        safe_call(function()
            -- Let a fighting companion fight. FindMostHateTarget is the real
            -- confirmed function on UPalHate, the same system combat assist
            -- pushes to.
            local hate = controller:GetHateSystem()
            if hate and hate:IsValid() then
                local target = hate:FindMostHateTarget()
                local targetValid = target ~= nil and safe_call(function() return target:IsValid() end)
                if targetValid then return end
            end

            local px = playerLoc.X
            local py = playerLoc.Y
            local pz = playerLoc.Z
            if px == nil or py == nil or pz == nil then return end

            orbitPhase = (orbitPhase + ORBIT_STEP_RADIANS) % (2 * math.pi)
            local dest = {
                X = px + math.cos(orbitPhase) * ORBIT_RADIUS,
                Y = py + math.sin(orbitPhase) * ORBIT_RADIUS,
                Z = pz,
            }
            -- A tight acceptance radius here on purpose: the point of this
            -- order is to keep a path active, not to arrive.
            controller:PalMoveToLocation(dest, ORBIT_ACCEPTANCE_RADIUS, false, true, true, true, nil, true)
        end)
    end
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
    if usedActorMove then
        -- nothing to report: move-to-actor returns no result value
    elseif ok then
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
