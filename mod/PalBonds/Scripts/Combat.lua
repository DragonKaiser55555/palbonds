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
-- Two-hundred-and-twenty-seventh pass (2026-09-07) — OFF, at Dragón's request
-- and for exactly the right reason: "wouldnt it be better to remove the old
-- nudge for now? just so we can check if the new follow intalls? (if it
-- follows we will know for sure its that and if it not follows then we can
-- make sure it didnt install or it doesnt work)". That is clean single-variable
-- isolation, and it is the discipline this project should have applied to the
-- follow work several passes ago instead of stacking mechanisms.
--
-- His second point is recorded as the standing fallback decision: if the follow
-- action fails, we go back to the TIGHT LEASH, not to this nudge. His words:
-- "the old nudge is not as good as the tight leash, so i would say if we ever
-- go back, we will go back to the tight leash instead, the old nudge failed
-- way too often." The evidence agrees — the tight leash held Pals reliably and
-- only failed by caging them, while the nudge never reliably held anything.
local USE_OLD_MOVE_ORDER_NUDGE = false
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
-- Two-hundred-and-twenty-third pass: see the block in IssueFollowMoveOrder.
local USE_ORBIT_WHEN_AT_GOAL = false

-- Two-hundred-and-eleventh pass: try the continuous move-to-actor follow
-- first (see IssueFollowMoveOrder). Set false to go back to pure
-- location-order following.
-- Two-hundred-and-twenty-seventh pass: also off, for the same isolation. This
-- is what produced the "following but fighting her own AI" movement Dragón
-- described, so leaving it on would make any movement next run ambiguous.
local USE_MOVE_TO_ACTOR_FOLLOW = false
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
local AI_REQUEST_PRIORITY_LOGIC = 10 -- two-hundred-and-twenty-fifth pass: was 3, which is not a valid EAIRequestPriority; Logic is 10

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

-- Two-hundred-and-twenty-first pass (2026-09-06) — Dragón is bringing a
-- Daedream, a Flopie AND a Dazzi at once, specifically so we can see whether
-- all three secondary-followers share one mechanism or each solves it
-- differently. That is a better experiment than the single-funnel row from the
-- previous pass, so this reports EVERY funnel follower rather than the first.
--
-- Why funnel Pals are the most relevant comparison of the three rows: they
-- follow the player while NOT being the active Otomo, which is exactly the
-- situation a bonding wild Pal is in. The header dump already shows they have
-- their own controller class (BP_FunnelCharacterAIController) distinct from
-- both BP_MonsterAIController_Wild_C and BP_MonsterAIController_Otomo_C, so
-- there are three different follow implementations in this game and we are
-- about to see all three side by side.
--
-- Also dumped per funnel, all read-only:
--   * GetTrainer() — the project's long-standing assumption is that funnel
--     following requires real ownership. This says so directly.
--   * AssistOwnerPal / OwnerCharacterId — what a funnel is anchored TO.
--   * SetLocationNearTrainer exists on this class as a real function; not
--     called here, but noted because it is the most direct "put yourself next
--     to the player" call found anywhere in this project so far.
local function report_funnel_followers()
    safe_call(function()
        local list = FindAllOf("PalFunnelCharacter")
        if list == nil or #list == 0 then
            Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] FUNNEL: no PalFunnelCharacter found — is a Daedream/Dazzi/Flopie actually out?")
            return
        end
        Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] FUNNEL: " .. #list .. " funnel follower(s) present")
        local shown = 0
        for _, f in ipairs(list) do
            if shown >= 5 then break end
            if safe_call(function() return f:IsValid() end) then
                shown = shown + 1
                local name = safe_call(function() return f:GetFullName() end)
                local charId = safe_call(function()
                    local c = f:GetCharacterID()
                    return c and c:ToString() or nil
                end)
                local trainer = safe_call(function()
                    local t = f:GetTrainer()
                    if t == nil or not t:IsValid() then return nil end
                    return t:GetFullName()
                end)
                local ownerPal = safe_call(function()
                    local o = f:GetOwnerPal()
                    if o == nil or not o:IsValid() then return nil end
                    return o:GetFullName()
                end)
                local controllerClass = safe_call(function()
                    local c = f.Controller
                    if c == nil or not c:IsValid() then return nil end
                    return c:GetClass():GetFullName()
                end)
                local actionName, actionCategory = nil, nil
                safe_call(function()
                    local c = f.Controller
                    if c == nil or not c:IsValid() then return end
                    local ac = c:GetAIActionComponent()
                    if ac == nil or not ac:IsValid() then return end
                    actionCategory = safe_call(function() return ac:GetCurrentAIActionCategory() end)
                    local cur = safe_call(function() return ac:GetCurrentAction_BP() end)
                    actionName = cur and safe_call(function() return cur:GetFullName() end)
                end)
                Logger.log(string.format(
                    "[PalBonds/Combat] [FOLLOW-DIFF]   funnel %d (%s): controller=%s | trainer=%s | ownerPal=%s | AIcategory=%s | currentAction=%s | actor=%s",
                    shown, tostring(charId), tostring(controllerClass), tostring(trainer),
                    tostring(ownerPal), tostring(actionCategory), tostring(actionName), tostring(name)
                ))
            end
        end
    end)
end

function Combat.DiagnoseFollowDifference(bondingPal)
    if followDiffDumps >= FOLLOW_DIFF_MAX_DUMPS then return end
    followDiffDumps = followDiffDumps + 1
    Logger.log("[PalBonds/Combat] [FOLLOW-DIFF] ===== comparison " .. followDiffDumps .. " of " ..
        FOLLOW_DIFF_MAX_DUMPS .. " — a REAL Otomo follows correctly and this bonding Pal does not, so whatever differs below is part of why =====")
    describe_follow_state("BONDING (wild)", bondingPal)
    describe_follow_state("REAL OTOMO    ", find_active_otomo(bondingPal))
    -- Two-hundred-and-twentieth pass: Dragón's suggestion, and a better data
    -- point than the Otomo row. A Daedream/Dazzi/Flopie "funnel" Pal follows
    -- the player while NOT being the active Otomo — which is much closer to a
    -- bonding wild Pal's situation than a real Otomo is. If its controller
    -- class differs from both rows above, that is the closest available model
    -- for what a wild follower should look like.
    report_funnel_followers()
    report_existing_leashes()
end

-- ===================================================================
-- TERRITORY FOLLOW (two-hundred-and-twentieth pass, 2026-09-06)
-- ===================================================================
-- The FOLLOW-DIFF probe answered the question this project has been guessing
-- at for seven attempts. From Dragón's run, the same fields on both Pals:
--
--   BONDING (wild): controller = BP_MonsterAIController_Wild_C
--   REAL OTOMO    : controller = BP_MonsterAIController_Otomo_C
--
-- Following is not a command, a flag, or an order. It is an ENTIRELY
-- DIFFERENT AI CONTROLLER CLASS. That single line explains every failure so
-- far: every mechanism tried was shouting orders at the Wild controller, whose
-- whole job is to keep the Pal near its own territory.
--
-- Two more results from the same probe, both valuable:
--   * IsOverrideTarget was FALSE on both the Otomo and the wild Pal, so that
--     field is NOT the follow mechanism. Ruled out without a test run.
--   * FindAllOf found ZERO leash actors in the world. The leash-actor route
--     from the previous pass is definitively dead — not "the spawn failed",
--     but "the game is not using that system here at all".
--
-- Reading BP_MonsterAIController_Wild_C then produced the actual opening:
--
--   void SetupLeash(ELeashType LeashType, FVector LeashLocation,
--                   double LeashInnerRange, double LeashOuterRange)
--   void ReturnToTerritory()
--   void "Set Spawnd Info"(FVector SpawnerLoc, double ReturnRadius, ...)
--
-- The wild controller keeps its own territory anchor, and exposes a setter for
-- it. So rather than fighting the Wild controller, we tell it that the player
-- IS the territory. Its own AI then keeps the Pal nearby, using the exact
-- system that has been out-voting us all along.
--
-- SAFETY, written deliberately after the leash-spawn leak of the previous
-- pass. SetupLeash MIGHT create something internally, and this is called
-- periodically, which is the exact shape that leaked before. So this version
-- polices itself:
--   * It counts leash actors in the world before the first call and again
--     after, and logs both.
--   * If that count ever grows beyond TERRITORY_LEASH_ACTOR_CEILING, the whole
--     mechanism disables itself immediately and says so loudly.
--   * There is a hard global call budget as well.
-- A repeat of the previous leak is therefore self-limiting rather than
-- something Dragón has to notice in his framerate.
--
-- UNKNOWN, stated plainly: ELeashType's values are unnamed in this build's
-- enum dump (NewEnumerator0/1/2), so the type argument is a guess. If type 0
-- misbehaves the other two are one constant away, and the log says which was
-- used.
-- Two-hundred-and-twenty-fifth pass (2026-09-07) — OFF, and the reason is a
-- confirmed structural result rather than a guess. Dragón ran both ends of the
-- tuning range and the log agrees with him exactly:
--   tight (inner 500):  no drifting, but caged — could not reach an attacker
--   loose (inner 1100): fought back (4 real damage events), but 4 leash breaks
--                       and 2 forced escapes; both Petallias got away
-- So the leash cannot do both. It is a fence, not following: a radius small
-- enough to keep them is small enough to trap them. That is structural, so
-- further tuning is not worth another run.
-- Two-hundred-and-twenty-eighth pass: RESTORED. The real follow action was
-- proven to install and still not move the Pal (see its block below), so the
-- fallback Dragón pre-committed to applies. This is his call, made in advance
-- and in his own words: go back to the tight leash, not the nudge.
-- Two-hundred-and-twenty-ninth pass: OFF again for the duration of the F9
-- test, so any following observed is attributable to the follow action alone.
-- The tight radii below (500/1200) stay as they are — this is a toggle, and
-- flipping it back is the whole fallback.
local USE_TERRITORY_FOLLOW = false
local TERRITORY_LEASH_TYPE = 0
-- Two-hundred-and-twenty-fourth pass (2026-09-07) — WIDENED, and this is the
-- change being tested. Dragón's two symptoms from the last run point at the
-- same cause, and it is this:
--
--   1. "they still managed to push me... its simply that they try to get as
--      close as me as posible" — every follower is anchored to the SAME point
--      with a 500-unit inner radius, so they all converge on the player and
--      shove. Removing the orbit did not fix it because the orbit was not the
--      cause; the leash is.
--   2. "now they dont fight back, not even after being hit by an attack, seems
--      the following mechanic is now too strong" — a Pal that wants to chase
--      its attacker cannot, because the leash pulls it back inside 500 units
--      of the player. It is not that they refuse to fight; they are physically
--      tethered too tightly to reach anything.
--
-- His own framing is exactly right: "funny how we went from too soft so they
-- could escape, to too strong that they cant do anything but follow now."
-- The leash was tuned to stop drifting and overshot into a cage.
--
-- Inner 500 -> 1100 and outer 1200 -> 2800 gives room to close on an attacker
-- and fight, while still being far inside the 3000-unit leash-break distance
-- that ends a bond. Per-follower stagger (below) additionally stops them all
-- wanting the identical spot.
-- Two-hundred-and-twenty-eighth pass: back to the TIGHT radii (500/1200).
-- These are the values that actually held Pals — the run that used them was
-- the one Dragón described as following "much better", with no drifting and
-- five followers at once. Their known cost is the cage: at 500 units a Pal
-- cannot reach an attacker, so it stops fighting back.
--
-- Worth stating plainly rather than quietly re-testing: the two leash runs
-- differed in TWO ways, not one. The tight run (500/1200) had no per-follower
-- stagger; the loose run (1100/2800) added it. So a middle radius WITH the
-- stagger has never actually been tried, and that combination is the one place
-- left in this space where "holds them" and "can still fight" might coexist.
-- Not changed unilaterally — flagged for Dragón, since it is a gameplay-feel
-- decision rather than a technical one.
local TERRITORY_INNER_RANGE = 500.0
local TERRITORY_OUTER_RANGE = 1200.0
-- Each follower gets its own slightly different inner radius, so three of them
-- do not all target the same distance from the player and fight over it. Keyed
-- off a per-Pal counter rather than anything random, so a given Pal keeps a
-- consistent spot instead of jittering between refreshes.
local TERRITORY_STAGGER_PER_PAL = 260.0
local territoryStaggerIndex = {}
local territoryStaggerNext = 0
local TERRITORY_EVERY_N_TICKS = 3          -- ~4.5s, same cadence as the re-sense
local TERRITORY_MAX_TOTAL_CALLS = 400      -- hard budget for a whole session
local TERRITORY_LEASH_ACTOR_CEILING = 8    -- if leash actors ever exceed this, stop

local territoryTickCounter = 0
local territoryTotalCalls = 0
local territoryDisabled = false
local territoryBaselineLeashCount = nil
local loggedTerritoryOnce = false

local function count_leash_actors()
    local n = safe_call(function()
        local l = FindAllOf("PalAILeashActor")
        return l and #l or 0
    end)
    return n or 0
end

-- Points a wild Pal's own territory at the player. Called on the follow tick.
local function update_territory_anchor(pal, playerLoc)
    if not USE_TERRITORY_FOLLOW or territoryDisabled or playerLoc == nil then return end

    territoryTickCounter = territoryTickCounter + 1
    if territoryTickCounter % TERRITORY_EVERY_N_TICKS ~= 0 then return end

    if territoryTotalCalls >= TERRITORY_MAX_TOTAL_CALLS then
        if not territoryDisabled then
            territoryDisabled = true
            Logger.log("[PalBonds/Combat] [TERRITORY] hit the session call budget (" .. TERRITORY_MAX_TOTAL_CALLS .. ") — disabling to stay safe")
        end
        return
    end

    if territoryBaselineLeashCount == nil then
        territoryBaselineLeashCount = count_leash_actors()
        Logger.log("[PalBonds/Combat] [TERRITORY] leash actors in world BEFORE the first SetupLeash call: " .. territoryBaselineLeashCount)
    end

    local controller = safe_call(function() return pal.Controller end)
    if not (controller and safe_call(function() return controller:IsValid() end)) then return end

    territoryTotalCalls = territoryTotalCalls + 1

    -- Per-follower spacing: give each Pal its own inner radius so they spread
    -- out instead of all crowding the same point (see the constants above).
    local key = safe_call(function() return pal:GetFullName() end)
    if key ~= nil and territoryStaggerIndex[key] == nil then
        territoryStaggerIndex[key] = territoryStaggerNext
        territoryStaggerNext = (territoryStaggerNext + 1) % 4
    end
    local inner = TERRITORY_INNER_RANGE + ((territoryStaggerIndex[key] or 0) * TERRITORY_STAGGER_PER_PAL)
    local outer = TERRITORY_OUTER_RANGE

    local ok = pcall(function()
        controller:SetupLeash(TERRITORY_LEASH_TYPE, playerLoc, inner, outer)
    end)

    if not loggedTerritoryOnce then
        loggedTerritoryOnce = true
        local after = count_leash_actors()
        Logger.log(string.format(
            "[PalBonds/Combat] [TERRITORY] first SetupLeash(type=%d, inner=%.0f, outer=%.0f) call returned %s — leash actors before=%s after=%s",
            TERRITORY_LEASH_TYPE, TERRITORY_INNER_RANGE, TERRITORY_OUTER_RANGE,
            ok and "ok" or "FAILED", tostring(territoryBaselineLeashCount), tostring(after)
        ))
        if not ok then
            territoryDisabled = true
            Logger.log("[PalBonds/Combat] [TERRITORY] SetupLeash is not callable this way — disabling territory follow, move-to-actor still active")
        end
    end

    -- Self-policing: if actors start accumulating, stop before it becomes the
    -- previous pass's leak.
    if territoryTotalCalls % 10 == 0 then
        local now = count_leash_actors()
        if now > (territoryBaselineLeashCount or 0) + TERRITORY_LEASH_ACTOR_CEILING then
            territoryDisabled = true
            Logger.log("[PalBonds/Combat] [TERRITORY] LEASH ACTORS ARE ACCUMULATING (" ..
                tostring(territoryBaselineLeashCount) .. " -> " .. tostring(now) ..
                ") — disabling territory follow immediately to prevent a leak")
        end
    end
end

-- ===================================================================
-- REAL FOLLOW ACTION (two-hundred-and-twenty-second pass, 2026-09-07)
-- ===================================================================
-- This is the eighth follow mechanism, but the first one built on measured
-- evidence rather than a plausible-looking API. Dragón's three-funnel test
-- produced the chain:
--
--   BP_AIAction_FunnelFollow_C : public BP_AIAction_OtomoFollow_C
--   BP_AIAction_OtomoFollow_C  : public UPalAIActionBase
--       class APalCharacter* Trainer;   -- 0x0140, a PLAIN FIELD
--       class APawn*         SelfActor; -- 0x0148
--
-- Funnel following and Otomo following are the SAME action class, and the
-- thing it follows is an ordinary settable field on the action object — not an
-- ownership query, not GetTrainer() on the Pal.
--
-- That overturns this project's assumption since the hundred-and-thirty-
-- seventh pass, which was that follow behaviour requires real party
-- membership. It does not. It requires a Trainer POINTER, and whoever creates
-- the action fills that in.
--
-- Why this differs from the two-hundred-and-second pass's failed attempt: that
-- one pushed UPalAIActionOtomoDefault, a COMPOSITE, via SetRootComposite. The
-- composite is not the thing that does the following; BP_AIAction_OtomoFollow_C
-- is. Different object, different call.
--
-- SAFETY. Dragón gave an explicit go-ahead knowing this is the same category
-- as the SetActiveAI incident (the one change that ever left his Pals standing
-- still and dying), and a restore tag exists: checkpoint-before-follow-action.
-- Discipline applied here, learned from the leash leak:
--   * ONE construct+push attempt per Pal, ever. Never per tick.
--   * A hard session budget across all Pals.
--   * Self-disable after repeated failures.
--   * Every step pcall-guarded and logged before and after, so a hard crash
--     still leaves a trail on disk (Logger flushes per line).
--   * The existing follow mechanisms stay running underneath, so a failure
--     here is a no-op rather than a regression.
-- Two-hundred-and-twenty-fourth pass (2026-09-07) — TURNED OFF, to isolate.
-- Answering Dragón's question ("what did you find on the new follow you were
-- trying?") honestly: it never became the running action. The readback showed
-- the component still on BP_AIActionPairCall_Petting_C right after every push,
-- and following works identically with the orbit removed, so nothing observed
-- so far is attributable to it.
--
-- Worse, a real error was found in it this pass. It pushed at priority 3, and
-- 3 IS NOT A VALID EAIRequestPriority VALUE. The real enum, from this build's
-- AIModule_enums.hpp:
--     SoftScript = 0, SoftScriptInterrupt = 1, Logic = 10,
--     HardScript = 11, Reaction = 12, Ultimate = 13
-- The project's own AI_REQUEST_PRIORITY_LOGIC = 3 constant, inherited from the
-- two-hundred-and-second pass and never checked, claimed 3 meant "Logic". It
-- does not; Logic is 10. So every composite/action push this project has made
-- went in at an undefined priority slot.
--
-- It is switched off rather than corrected, deliberately: Dragón is now
-- reporting that followers cannot fight at all, and changing two things at
-- once would make that untestable. This pass changes exactly one thing (the
-- leash radii below). If the fighting comes back, this was innocent and can be
-- retried at a real priority; if it does not, this was never the cause either.
-- ===================================================================
-- TWO-HUNDRED-AND-TWENTY-EIGHTH PASS (2026-09-07) — THE ISOLATED TEST RAN,
-- AND IT ANSWERED THE QUESTION. SWITCHED OFF AS A RESULT.
-- ===================================================================
-- Dragón's run with every other mechanism disabled produced the first
-- unambiguous measurement this feature has ever had. From palbonds-live.log,
-- one bonding Petallia (BP_FlowerDoll_C_2147437680):
--
--   construct returned valid=true
--   Trainer/SelfActor write ok
--   SetAction returned ok
--   HasAction(followClass, priority 10) = true
--   RECHECK after 6s: still present at priority 10 = true
--
-- So the push is NOT dropped. The action is genuinely constructed, accepted,
-- and still resident at Logic six seconds later. Eight mechanisms in, this is
-- the first one confirmed to actually install.
--
-- And it still did not follow. Dragón's own description is the other half of
-- the measurement, and it is more informative than the log alone:
--
--   "i did see her stay still... waited to see if she would move or react,
--    even making noise around her, but she was simply non-moving... then i
--    moved far to see if escape would make her move again and that made her
--    move"
--
-- A wild Pal left alone wanders, grazes and reacts. This one did nothing at
-- all until an Escape reaction fired. That is not "our action lost" — that is
-- our action WINNING the Logic slot, holding it, and being INERT: it suppresses
-- the wild AI's own decisions (which live at Logic) while producing no movement
-- of its own. Higher-priority tiers still pre-empt it, which is exactly why
-- Escape (Reaction, 12) could still move her, and why the interactions kept
-- working.
--
-- That rules out the obvious next guess. Raising the priority to HardScript or
-- Reaction cannot help: the action is already not losing. The action is not
-- FUNCTIONING. Trainer + SelfActor are evidently not sufficient state for
-- BP_AIAction_OtomoFollow_C to compute where to go — a StaticConstructObject'd
-- Blueprint action never went through whatever normal initialisation the Otomo
-- controller does, so it holds the slot without a destination.
--
-- A mechanism that freezes a Pal in place is strictly worse than no mechanism,
-- and freezing Pals is precisely the failure mode of the SetActiveAI incident
-- Dragón was warned about before approving this. So it goes off now, on the
-- evidence, rather than being tuned.
--
-- Per Dragón's standing instruction, recorded verbatim before this run:
--   "the old nudge is not as good as the tight leash, so i would say if we
--    ever go back, we will go back to the tight leash instead, the old nudge
--    failed way too often"
-- The territory leash below is therefore restored to its TIGHT values, and the
-- nudge stays off.
-- Two-hundred-and-twenty-ninth pass: BACK ON for Dragon's F9 test. It was
-- switched off last pass on the reading that it installs but is inert; his
-- petting observation reopened that, because a stuck high-priority petting
-- action explains the frozen Petallia just as well and would have been
-- invisible in every earlier run (every previous mechanism bypassed the action
-- stack entirely). F9 grants the bar with no interaction played, so this run
-- finally tests the follow action with the confound removed.
-- ONE variable changed: still BP_AIAction_OtomoFollow_C, still priority 10.
-- The FunnelFollow subclass is the next thing to try, deliberately NOT
-- combined with this one.
local USE_REAL_FOLLOW_ACTION = true
local FOLLOW_ACTION_CLASS_PATH = "/Game/Pal/Blueprint/Controller/AIAction/Otomo/BP_AIAction_OtomoFollow.BP_AIAction_OtomoFollow_C"
-- EAIRequestPriority: Ultimate=3 is what this project already used for the
-- composite attempt (AI_REQUEST_PRIORITY_LOGIC=3). Same value kept for
-- consistency; the log records it either way.
-- Two-hundred-and-twenty-fifth pass: corrected from 3, which is not a valid
-- EAIRequestPriority at all. Real values from AIModule_enums.hpp:
--   SoftScript=0, SoftScriptInterrupt=1, Logic=10, HardScript=11,
--   Reaction=12, Ultimate=13
-- Logic (10) is chosen deliberately, not just because it is valid: it makes
-- following the Pal's default behaviour while leaving HardScript (11) and
-- Reaction (12) ABOVE it, so combat and damage reactions can still pre-empt
-- following. That is exactly the balance the leash could never strike — the
-- previous run proved a fence cannot both hold them and let them fight, but a
-- priority ordering can.
local FOLLOW_ACTION_PRIORITY = 10
local FOLLOW_ACTION_MAX_PER_PAL = 1
local FOLLOW_ACTION_MAX_TOTAL = 40
-- How long after the push to re-read, so the check lands when the Pal is idle
-- rather than mid-interaction. See the readback block for why this matters.
local FOLLOW_ACTION_RECHECK_MS = 6000
-- A second, later read. Two timers per Pal only, both one-shot, both bounded by
-- the same per-Pal attempt cap — deliberately not a polling loop, after the
-- per-event timer leak Dragón predicted and the leash-spawn leak before it.
local FOLLOW_ACTION_LATE_DUMP_MS = 14000
-- Two-hundred-and-thirtieth pass: call the action's own initialiser after
-- constructing it. From BP_AIAction_OtomoFollow.hpp:
--
--   void SetInitialValue();
--
-- The class carries fields that plainly have to be populated before it can move
-- anything -- Movement (a UPalCharacterMovementComponent*), DefaultMaxSpeed,
-- ConstMaxSpeedRateVsPlayer, FolowEndDistance -- and StaticConstructObject only
-- allocates the object, it does not run whatever the game normally runs to fill
-- them in. A hand-built action with a null Movement and a zero DefaultMaxSpeed
-- would behave exactly as observed: it becomes the running action and moves
-- nobody.
--
-- Called ONCE per Pal, immediately after the push, bracketed by the field dump
-- on both sides so its effect is measured rather than assumed. Dragón approved
-- this specific write knowing it is the same category as the SetActiveAI
-- incident; the restore tag checkpoint-before-follow-action still stands, the
-- call is pcall-guarded, and it targets an object this mod created itself
-- rather than anything belonging to the Pal.
local USE_FOLLOW_ACTION_SET_INITIAL_VALUE = true

-- ===================================================================
-- TRAINER RE-ASSERT (two-hundred-and-thirty-first pass, 2026-09-07)
-- ===================================================================
-- The field dump found the actual failure, and it is not "the action is inert".
-- Identical on all three Pals of Dragón's run, no exceptions:
--
--   at push .............. Trainer = BP_Player_Female_C   (correct)
--   after SetInitialValue  Trainer = BP_Player_Female_C   (still correct)
--   at 6s ................ Trainer = INVALID
--   at 14s ............... Trainer = INVALID
--
-- The Trainer pointer we write is being NULLED within six seconds, every time,
-- while our action is confirmed to be the running one. And the class dump names
-- the mechanism: BP_AIAction_OtomoFollow_C has its own
--
--   void TryGetTrainer(class APalCharacter*& Trainer);
--
-- The action does not trust the field — it re-derives the trainer for itself,
-- and on a wild Pal (which has no owner) that lookup yields nothing and
-- overwrites what we wrote. With no trainer there is no destination, which is
-- exactly what the rest of the dump shows: Destination stays (0,0,0),
-- IsMoveMode stays false, FollowState stays 0, and the Pal stands still.
--
-- The decisive supporting evidence, and the reason this is worth one more pass
-- rather than a retirement: DelayedDestination was (0,0,0) before
-- SetInitialValue and became a REAL world coordinate immediately after it,
-- while Trainer was still valid — e.g. (-214012.05, 159727.16, 220.40). The
-- action can and does compute real follow positions. It only stops once its
-- trainer is gone. SetInitialValue also demonstrably worked: DefaultMaxSpeed
-- went 0 -> 245 and CurrentSpeedVsPlayer 0 -> 2.
--
-- So the fix to try is not another mechanism — it is to keep the field
-- populated. This re-writes Trainer on every follow tick for any Pal whose
-- follow action is still alive, and logs Destination alongside it so the effect
-- is measured rather than assumed: if Destination ever becomes non-zero, this is
-- the right track.
--
-- SAFETY. This is a per-tick write, the shape that produced the leash-actor leak
-- and the per-event timer leak. It is deliberately the cheapest possible kind:
-- it writes one pointer field on an object this mod constructed itself. It
-- allocates nothing, spawns nothing and schedules nothing. It is additionally
-- bounded by a hard session budget and self-disables on repeated failure, and
-- its logging is throttled to once every N re-asserts rather than every tick,
-- with the Destination read done ONLY on the ticks that actually log — a log
-- guard that still evaluates its arguments has cost this project real
-- performance three separate times.
local USE_TRAINER_REASSERT = true
local TRAINER_REASSERT_MAX_TOTAL = 4000
local TRAINER_REASSERT_LOG_EVERY = 20

local followActionObjects = {}
local trainerReassertTotal = 0
local trainerReassertDisabled = false
local trainerReassertFailures = 0
local trainerReassertCounter = {}

-- Re-writes Trainer on this Pal's live follow action. Called from the follow
-- tick; a no-op for any Pal that never got a follow action installed.
local function reassert_follow_trainer(pal, key, playerActor)
    if not USE_TRAINER_REASSERT or trainerReassertDisabled then return end
    if key == nil or playerActor == nil then return end

    local action = followActionObjects[key]
    if action == nil then return end
    if not safe_call(function() return action:IsValid() end) then
        -- The action was destroyed (cancelled, or the Pal despawned). Drop the
        -- reference so this stops being retried for a Pal that no longer has one.
        followActionObjects[key] = nil
        return
    end

    if trainerReassertTotal >= TRAINER_REASSERT_MAX_TOTAL then
        trainerReassertDisabled = true
        Logger.log("[PalBonds/Combat] [TRAINER-REASSERT] session budget reached (" .. TRAINER_REASSERT_MAX_TOTAL .. ") — no further re-asserts")
        return
    end
    trainerReassertTotal = trainerReassertTotal + 1

    local ok = pcall(function() action.Trainer = playerActor end)
    if not ok then
        trainerReassertFailures = trainerReassertFailures + 1
        if trainerReassertFailures >= 5 then
            trainerReassertDisabled = true
            Logger.log("[PalBonds/Combat] [TRAINER-REASSERT] the Trainer write failed 5 times — disabling; nothing else is affected")
        end
        return
    end

    -- Throttled reporting. The Destination read lives INSIDE this branch on
    -- purpose: Lua evaluates arguments before the call, so a throttle that only
    -- guards the log call saves nothing at all.
    local n = (trainerReassertCounter[key] or 0) + 1
    trainerReassertCounter[key] = n
    if n % TRAINER_REASSERT_LOG_EVERY == 1 then
        local dest = safe_call(function() return action.Destination end)
        local dx = dest and safe_call(function() return dest.X end)
        local dy = dest and safe_call(function() return dest.Y end)
        local moveMode = safe_call(function() return action.IsMoveMode end)
        local followState = safe_call(function() return action.FollowState end)
        Logger.log(string.format(
            "[PalBonds/Combat] [TRAINER-REASSERT] %s — re-assert #%d: Destination=(%s, %s) IsMoveMode=%s FollowState=%s  <-- a non-zero Destination means this worked",
            tostring(key), n, tostring(dx), tostring(dy), tostring(moveMode), tostring(followState)
        ))
    end
end

local followActionAttempts = {}
local followActionTotal = 0
local followActionDisabled = false
local FollowActionClass = nil

local function get_follow_action_class()
    if FollowActionClass ~= nil then return FollowActionClass end
    FollowActionClass = safe_call(function() return StaticFindObject(FOLLOW_ACTION_CLASS_PATH) end)
    if FollowActionClass == nil then
        -- Fall back to the funnel subclass, which is confirmed live in the
        -- world whenever Dragón has a Daedream out, so it is certainly loaded.
        FollowActionClass = safe_call(function()
            return StaticFindObject("/Game/Pal/Blueprint/Controller/AIAction/Funnel/BP_AIAction_FunnelFollow.BP_AIAction_FunnelFollow_C")
        end)
        if FollowActionClass ~= nil then
            Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] OtomoFollow class path did not resolve; using the FunnelFollow subclass instead")
        end
    end
    -- Two-hundred-and-twenty-ninth pass: log WHICH class was actually resolved,
    -- always. Dragón asked a fair question the log could not answer directly
    -- ("weren't we trying the funnel follow?") — it had to be inferred from the
    -- ABSENCE of the fallback line above, which is a terrible way to establish a
    -- fact. The two classes are a parent and its subclass and may well behave
    -- differently, so which one ran is a primary result, not a footnote.
    if FollowActionClass ~= nil then
        local resolvedName = safe_call(function() return FollowActionClass:GetFullName() end)
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] follow-action class resolved = " .. tostring(resolvedName))
    end
    return FollowActionClass
end

-- ===================================================================
-- FOLLOW-ACTION FIELD DUMP (two-hundred-and-thirtieth pass, 2026-09-07)
-- ===================================================================
-- Read-only. Nothing here writes anything.
--
-- The previous run finally produced an unambiguous result: in 2 of 4 Pals,
-- GetCurrentAction_BP() named AIAction_OtomoFollow as the RUNNING action while
-- the Pal stood completely still. The other 2 moved normally, and in both cases
-- our action was not the one running (one was cancelled outright, the other was
-- outranked by combat — that is Dragón's Petallia that "somehow managed to move
-- and attacked a hostile pal"). The correlation is exact: our action running
-- means frozen, anything else running means a normal Pal. So the action really
-- does execute and really does produce no movement.
--
-- The real class dump (ue4ss/CXXHeaderDump/BP_AIAction_OtomoFollow.hpp) says why
-- that is even possible, and it overturns the assumption this mechanism was
-- built on:
--
--   void GetFollowSpeedFromController(double& FollowSpeed);
--   void GetFollowInterpolatedPosFromController(FVector& FollowInterpolatedPos);
--
-- The action does NOT derive where to go from the Trainer field. It asks its
-- CONTROLLER. We set Trainer correctly and Trainer was never the input that
-- mattered. A wild Pal's controller is BP_MonsterAIController_Wild_C, which has
-- no reason to answer either question — so the action ticks, asks, gets nothing,
-- and stands there.
--
-- The same dump also lists the fields that decide whether it can move at all,
-- plus an explicit initialiser we never called:
--
--   class UPalCharacterMovementComponent* Movement;   // 0x0178
--   FVector Destination;                              // 0x0158
--   bool    IsMoveMode;                               // 0x0150
--   double  DefaultMaxSpeed;                          // 0x01B0
--   TEnumAsByte<EOtomoFollowState::Type> FollowState;  // 0x0188
--   void SetInitialValue();
--
-- Constructing the object by hand skipped whatever normally populates those.
-- This dump reads them at three moments so the answer is not inferred:
--   * right after the push (before anything has ticked),
--   * at the 6s recheck (when it was observed to be the RUNNING action),
--   * again at 14s (has Destination ever been populated, or is it stuck at
--     zero forever?).
--
-- What each outcome means, written down BEFORE the run so the result cannot be
-- rationalised afterwards:
--   * Movement nil or DefaultMaxSpeed 0  -> initialisation was skipped;
--     SetInitialValue() is a one-call fix and worth trying.
--   * Movement/DefaultMaxSpeed fine but Destination stays (0,0,0) -> the
--     controller dependency above is confirmed structural, this action cannot
--     work on a wild controller, and the honest recommendation becomes the
--     tight leash rather than a ninth mechanism.
local function dump_follow_action_fields(action, key, whenLabel)
    if action == nil then return end
    safe_call(function()
        if not action:IsValid() then
            Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS] " .. tostring(key) .. " (" .. tostring(whenLabel) ..
                "): the action object is no longer valid — it was destroyed")
            return
        end

        local function objName(v)
            if v == nil then return "nil" end
            local ok = safe_call(function() return v:IsValid() end)
            if not ok then return "invalid" end
            return tostring(safe_call(function() return v:GetFullName() end))
        end
        local function vec(v)
            if v == nil then return "nil" end
            local x = safe_call(function() return v.X end)
            local y = safe_call(function() return v.Y end)
            local z = safe_call(function() return v.Z end)
            return string.format("(%s, %s, %s)", tostring(x), tostring(y), tostring(z))
        end
        local function raw(name)
            return tostring(safe_call(function() return action[name] end))
        end

        -- Split across several lines rather than one very long one: the logger
        -- flushes per line, so a crash mid-dump still leaves everything read up
        -- to that point on disk.
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS] " .. tostring(key) .. " (" .. tostring(whenLabel) .. "):")
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   Trainer  = " .. objName(safe_call(function() return action.Trainer end)))
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   SelfActor= " .. objName(safe_call(function() return action.SelfActor end)))
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   Movement = " .. objName(safe_call(function() return action.Movement end)) ..
            "   <-- nil here means SetInitialValue() never ran")
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   Destination = " .. vec(safe_call(function() return action.Destination end)) ..
            "   <-- (0,0,0) while running means the controller never answered")
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   DelayedDestination = " .. vec(safe_call(function() return action.DelayedDestination end)))
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   IsMoveMode=" .. raw("IsMoveMode") ..
            " IsTurnMode=" .. raw("IsTurnMode") ..
            " IsForceFitGoal=" .. raw("IsForceFitGoal") ..
            " FollowState=" .. raw("FollowState"))
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   DefaultMaxSpeed=" .. raw("DefaultMaxSpeed") ..
            " CurrentMoveSpeedRate=" .. raw("CurrentMoveSpeedRate") ..
            " CurrentSpeedVsPlayer=" .. raw("CurrentSpeedVsPlayer") ..
            " ConstMaxSpeedRateVsPlayer=" .. raw("ConstMaxSpeedRateVsPlayer"))
        Logger.log("[PalBonds/Combat] [FOLLOW-FIELDS]   FolowEndDistance=" .. raw("FolowEndDistance") ..
            " TargetLocationDistanceForward=" .. raw("TargetLocationDistanceForward") ..
            " TargetLocationDistanceRight=" .. raw("TargetLocationDistanceRight"))
    end)
end

-- Builds a real follow action for this Pal, points it at the player, and hands
-- it to the Pal's own AI action component. One shot per Pal.
local function try_real_follow_action(pal, key, playerActor)
    if not USE_REAL_FOLLOW_ACTION or followActionDisabled then return end
    if key == nil or pal == nil or playerActor == nil then return end

    local attempts = followActionAttempts[key] or 0
    if attempts >= FOLLOW_ACTION_MAX_PER_PAL then return end
    if followActionTotal >= FOLLOW_ACTION_MAX_TOTAL then
        followActionDisabled = true
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] session budget reached (" .. FOLLOW_ACTION_MAX_TOTAL .. ") — no further attempts")
        return
    end
    followActionAttempts[key] = attempts + 1
    followActionTotal = followActionTotal + 1

    local cls = get_follow_action_class()
    if cls == nil then
        followActionDisabled = true
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] neither follow-action class could be resolved — disabling; the class path may differ on this build")
        return
    end

    local controller = safe_call(function() return pal.Controller end)
    if not (controller and safe_call(function() return controller:IsValid() end)) then return end
    local actionComp = safe_call(function() return controller:GetAIActionComponent() end)
    if not (actionComp and safe_call(function() return actionComp:IsValid() end)) then
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) .. " has no usable AIActionComponent — skipping")
        return
    end

    Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) .. " — about to CONSTRUCT the follow action NOW")
    local action = safe_call(function() return StaticConstructObject(cls, actionComp) end)
    local actionValid = action ~= nil and safe_call(function() return action:IsValid() end)
    Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) .. " — construct returned valid=" .. tostring(actionValid))
    if not actionValid then
        followActionDisabled = true
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] construction failed — disabling so this is not retried")
        return
    end

    -- The whole point: tell the action who to follow. Trainer and SelfActor are
    -- plain object fields, the same category of write this project already does
    -- safely on AI response presets.
    local setOk, setErr = pcall(function()
        action.Trainer = playerActor
        action.SelfActor = pal
    end)
    Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) .. " — Trainer/SelfActor write " ..
        (setOk and "ok" or ("FAILED: " .. tostring(setErr))))
    if not setOk then return end

    Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) .. " — about to SetAction (priority " .. FOLLOW_ACTION_PRIORITY .. ") NOW")
    local pushOk, pushErr = pcall(function()
        actionComp:SetAction(action, FOLLOW_ACTION_PRIORITY, pal)
    end)
    Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) .. " — SetAction returned " ..
        (pushOk and "ok" or ("FAILED: " .. tostring(pushErr))))
    if not pushOk then
        followActionDisabled = true
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] SetAction is not callable this way — disabling; other follow mechanisms remain active")
        return
    end

    -- Two-hundred-and-twenty-sixth pass (2026-09-07) — THE READBACK WAS
    -- MEASURED AT THE WORST POSSIBLE MOMENT, and that is my error, not a
    -- property of the mechanism.
    --
    -- The immediate readback below has now reported "BP_AIActionPairCall_
    -- Petting_C" twice, at priority 3 and again at priority 10, and both times
    -- it was taken microseconds after the push — which is necessarily DURING
    -- the pet/feed interaction, because the 50% follow trigger fires from the
    -- interaction path itself. An interaction action sitting on top at that
    -- instant says nothing about whether the follow action is installed
    -- underneath it at Logic priority. I have twice been on the verge of
    -- declaring the mechanism dead on a measurement that could not have shown
    -- success even if it had worked perfectly.
    --
    -- Two better checks, both read-only:
    --   1. HasAction(class, priority) — asks the component directly whether
    --      our action is PRESENT at Logic, regardless of what is currently on
    --      top. This distinguishes "the push was silently dropped" from
    --      "it is installed but queued below the interaction".
    --   2. A delayed re-read several seconds later, once the interaction has
    --      finished and the Pal is idle — the only moment at which a follow
    --      action could legitimately be the current one.
    safe_call(function()
        local cur = actionComp:GetCurrentAction_BP()
        local curName = cur and safe_call(function() return cur:GetFullName() end)
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) ..
            " — current action IMMEDIATELY after push (expected to be the interaction) = " .. tostring(curName))
    end)

    safe_call(function()
        local present = actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY)
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) ..
            " — HasAction(followClass, priority " .. FOLLOW_ACTION_PRIORITY .. ") = " .. tostring(present) ..
            "  <-- this is the line that says whether the push actually stuck")
    end)

    -- Kept so the follow tick can re-assert Trainer on it. One entry per Pal,
    -- cleared as soon as the action stops being valid.
    followActionObjects[key] = action

    dump_follow_action_fields(action, key, "immediately after push, before anything ticked")

    -- The candidate fix. If the dump above showed Movement=nil / DefaultMaxSpeed=0
    -- and the dump below shows them populated, this was the missing step and the
    -- Pal should start moving. If both dumps look identical, the initialiser is
    -- not the problem and the controller dependency is.
    if USE_FOLLOW_ACTION_SET_INITIAL_VALUE then
        Logger.log("[PalBonds/Combat] [FOLLOW-INIT] " .. tostring(key) .. " — about to call SetInitialValue() on the constructed action NOW")
        local initOk, initErr = pcall(function() action:SetInitialValue() end)
        Logger.log("[PalBonds/Combat] [FOLLOW-INIT] " .. tostring(key) .. " — SetInitialValue() returned " ..
            (initOk and "ok" or ("FAILED: " .. tostring(initErr))))
        if initOk then
            dump_follow_action_fields(action, key, "AFTER SetInitialValue()")
        end
    end

    pcall(function()
        ExecuteInGameThreadWithDelay(FOLLOW_ACTION_RECHECK_MS, function()
            safe_call(function()
                if not (pal and pal:IsValid() and actionComp and actionComp:IsValid()) then return end
                local cur2 = actionComp:GetCurrentAction_BP()
                local cur2Name = cur2 and safe_call(function() return cur2:GetFullName() end)
                local still = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
                Logger.log(string.format(
                    "[PalBonds/Combat] [FOLLOW-ACTION] %s — RECHECK after %.0fs: current action = %s | still present at priority %d = %s",
                    tostring(key), FOLLOW_ACTION_RECHECK_MS / 1000, tostring(cur2Name),
                    FOLLOW_ACTION_PRIORITY, tostring(still)
                ))
                dump_follow_action_fields(action, key, "at the 6s recheck")
            end)
        end)
    end)

    -- One more read, late enough that the action has had many ticks to ask its
    -- controller for a destination. If Destination is STILL (0,0,0) here while
    -- the action is the running one, that is the structural answer.
    pcall(function()
        ExecuteInGameThreadWithDelay(FOLLOW_ACTION_LATE_DUMP_MS, function()
            safe_call(function()
                if not (pal and pal:IsValid() and actionComp and actionComp:IsValid()) then return end
                local cur3 = actionComp:GetCurrentAction_BP()
                local cur3Name = cur3 and safe_call(function() return cur3:GetFullName() end)
                Logger.log(string.format(
                    "[PalBonds/Combat] [FOLLOW-ACTION] %s — LATE re-read after %.0fs: current action = %s",
                    tostring(key), FOLLOW_ACTION_LATE_DUMP_MS / 1000, tostring(cur3Name)
                ))
                dump_follow_action_fields(action, key, "at the 14s late read")
            end)
        end)
    end)
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
        -- Two-hundred-and-thirty-first pass: drop the follow-action reference and
        -- its re-assert counter. This matters most on CAPTURE, which is the
        -- normal way following ends: the Pal becomes a real Otomo with its own
        -- controller and its own follow behaviour, and a hand-pushed action of
        -- ours still holding a re-asserted Trainer would be competing with it.
        -- It also stops these two tables growing by one dead entry per Pal for
        -- the whole session.
        followActionObjects[key] = nil
        trainerReassertCounter[key] = nil
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
    -- Two-hundred-and-twenty-seventh pass (2026-09-07) — REORDERED, and this
    -- restructure had to happen before Dragón's requested test could even be
    -- valid. He asked to switch the old nudge off so the follow action can be
    -- tested in isolation, which is exactly the right experiment — but the
    -- nudge's early-return sat ABOVE the follow-action install, so simply
    -- flipping that toggle would have silently prevented the follow action
    -- from ever being installed, and killed the re-sense too. The test would
    -- have "proved" the follow action does nothing, for entirely the wrong
    -- reason.
    --
    -- The install, the territory anchor and the re-sense are therefore hoisted
    -- above the gate. The gate now controls ONLY the movement orders, which is
    -- what it was always meant to mean.
    -- Hoisted out of the safe_call below: it used to be a local INSIDE that
    -- closure, which meant the re-assert call underneath was reading a nil
    -- global and silently doing nothing on every tick. Exactly the shape of
    -- failure this project keeps paying for — no error, no log, just a
    -- mechanism that never runs and a test run that "proves" it does not work.
    local key = safe_call(function() return pal:GetFullName() end)

    safe_call(function() try_real_follow_action(pal, key, playerActor) end)
    safe_call(function() reassert_follow_trainer(pal, key, playerActor) end)
    safe_call(function() update_territory_anchor(pal, playerLoc) end)

    resenseTickCounter = resenseTickCounter + 1
    if resenseTickCounter % RESENSE_EVERY_N_TICKS == 0 then
        safe_call(function()
            local okP, Personality = pcall(require, "Personality")
            if not (okP and Personality and Personality.RefreshSightOn) then return end
            Personality.RefreshSightOn(pal)
        end)
    end

    -- Everything below this line is the old movement-order approach.
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
    -- Two-hundred-and-twenty-third pass (2026-09-07) — ORBIT TURNED OFF, at
    -- Dragón's observation. He noticed it still firing and asked whether it is
    -- still needed: "having multiple followers makes them tend to sort of like
    -- push the player over and over trying to take its spot... i can see it
    -- being a problem with several pals following."
    --
    -- He is right, and it is the direct cause. The orbit sent every follower to
    -- a rotating point 180 units from the player with a tight 60-unit
    -- acceptance radius — literally "chase a spot right next to me, forever".
    -- With one follower that reads as milling about; with several they all
    -- converge on nearly the same spot and shove each other, and the player,
    -- out of the way.
    --
    -- It was only ever a workaround for the idle window that let the wild AI
    -- take over, and following is now holding without needing it. Turning it
    -- off is also a clean single-variable test of exactly that claim: if
    -- following stays good, the orbit was doing nothing except the crowding.
    -- The move order itself is untouched and still runs.
    if USE_ORBIT_WHEN_AT_GOAL and (not usedActorMove) and ok and tonumber(resultOrErr) == MOVE_RESULT_ALREADY_AT_GOAL then
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
