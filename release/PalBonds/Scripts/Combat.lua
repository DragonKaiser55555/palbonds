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
-- Two-hundred-and-fifty-third pass: Trust needs to know whether a fight is
-- happening, so it can tell a deliberate punch from a follower catching a stray
-- hit in a brawl. Read-only accessor over the window this file already keeps.
function Combat.IsPlayerInCombat()
    return playerCombatActive == true
end

function Combat.HasAnyFollower()
    for _, isFollowing in pairs(BondingState) do
        if isFollowing then return true end
    end
    return false
end

-- ===================================================================
-- HATE RELEASE (two-hundred-and-thirty-fourth pass, 2026-09-07)
-- ===================================================================
-- Dragón's report, and his own suspicion about the cause, which was correct:
--
--   "after a follower pal exits the combat, they once more start behaving like
--    a wild pal, wandering around, sometimes they follow but its similar to the
--    old nudge, very unreliable ... but i did notice them drift away after
--    combat, happened with all the pals ... i also suspect it could be one of
--    the old codes we implemented when we were tackling the combat mechanic,
--    maybe something from before its breaking now the behavior"
--
-- It is. The combat assist pushes +1000 hate onto every companion for every
-- damage event of a fight, and until now NOTHING EVER TOOK IT BACK. Closing the
-- combat window only flipped the response preset back to peaceful; the hate
-- entries survived. So after the fight each companion still has a live hate
-- target, its own AI keeps running search/combat behaviour ABOVE our follow
-- action's Logic priority, and the Pal wanders off hunting a target that is
-- usually already dead. Our follow action sits underneath the whole time with a
-- perfectly good Destination and never gets a turn — which is exactly why it
-- looked "similar to the old nudge, very unreliable" rather than simply broken.
--
-- The log confirms the mechanism cleanly: hate was pushed four separate times
-- across two fights, and there is not one line anywhere taking any of it back.
--
-- UPalHate (checked in Pal.hpp, not guessed) exposes ChangeHate, DamageEvent,
-- AttackSuccessEvent and FindMostHateTarget — there is no reset on this class,
-- so a large negative ChangeHate is the available route. That is the same shape
-- ClearMutualHate has been using safely for several passes.
local assistHateTargets = {}

local function release_assist_hate()
    local anyTarget = next(assistHateTargets) ~= nil
    if not anyTarget then return end

    -- Every follower, against every enemy this window aimed them at, plus every
    -- OTHER follower. The second half matters because a fight is exactly when
    -- companions hurt each other, and a grudge picked up mid-fight would
    -- otherwise outlive the fight the same way the assist hate did.
    local followers = {}
    for key, isFollowing in pairs(BondingState) do
        if isFollowing then
            local pal = FollowerActors[key]
            if pal ~= nil and safe_call(function() return pal:IsValid() end) then
                followers[key] = pal
            end
        end
    end

    local cleared, pairsCleared = 0, 0
    for _, pal in pairs(followers) do
        safe_call(function()
            local controller = pal.Controller
            if not (controller and controller:IsValid()) then return end
            local hate = controller:GetHateSystem()
            if not (hate and hate:IsValid()) then return end

            for _, enemyActor in pairs(assistHateTargets) do
                if enemyActor ~= nil and safe_call(function() return enemyActor:IsValid() end) then
                    -- Ten times what was pushed, the same margin ClearMutualHate
                    -- already uses, so repeated pushes across a long fight are
                    -- comfortably covered rather than only the last one.
                    pcall(function() hate:ChangeHate(enemyActor, -COMBAT_ASSIST_HATE_AMOUNT * 10) end)
                    cleared = cleared + 1
                end
            end

            for otherKey, otherPal in pairs(followers) do
                if otherPal ~= pal then
                    pcall(function() hate:ChangeHate(otherPal, -COMBAT_ASSIST_HATE_AMOUNT * 10) end)
                    pairsCleared = pairsCleared + 1
                end
            end
        end)
    end

    assistHateTargets = {}
    Logger.log(string.format(
        "[PalBonds/Combat] [HATE-RELEASE] combat over — took back the assist hate (%d enemy entries) and cleared %d companion-to-companion grudges, so followers stop hunting and go back to following",
        cleared, pairsCleared
    ))
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

    -- Two-hundred-and-thirty-fourth pass (2026-09-07) — FRIENDLY-FIRE
    -- AMPLIFIER, and it explains why the chaos kept coming back even after the
    -- pairwise grudge-clearing in Trust.lua was added.
    --
    -- Trust.lua decides the "enemy" as: whoever the PLAYER damaged. If one of
    -- the player's own attacks splashes onto a bonded companion, that companion
    -- becomes the enemy — and this function then pushes +1000 hate toward it
    -- onto EVERY OTHER COMPANION at once. One stray hit from the player turns
    -- the whole group on one of its own, deliberately, by design, and the
    -- existing per-damage-event clearing then has to fight a grudge that this
    -- code is actively re-creating.
    --
    -- The existing guard below (key ~= enemyName) only stops a Pal being aimed
    -- at ITSELF. It has never stopped a Pal being aimed at its companions.
    --
    -- Dragón's run, twice now: "they managed to kill the hostile pal, but then
    -- ended up attacking themselves because their attacks landed on each other,
    -- thus i had to capture them to save them".
    if enemyName ~= nil and BondingState[enemyName] then
        Logger.log("[PalBonds/Combat] [HATE-ASSIST] the damaged actor is one of our own companions — refusing to aim the others at it (logged so friendly fire is visible rather than silent)")
        return
    end

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
    -- Remember every enemy this combat window aimed companions at, so the hate
    -- can actually be taken back when the window closes. Keyed by name so a
    -- long fight against the same enemy does not grow the table.
    if enemyName ~= nil then assistHateTargets[enemyName] = enemyActor end

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
            release_assist_hate()
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
-- Raised from 1 for the rebuild-after-combat fix above. This is a backstop, not
-- an expected count: a follower normally uses one install, plus one more each
-- time a fight destroys its action.
local FOLLOW_ACTION_MAX_PER_PAL = 25
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
-- Two-hundred-and-thirty-second pass: the re-assert now runs on its own fast
-- loop instead of only on the 1500ms follower tick. Dragón saw a wild Pal follow
-- and defend him, but only "for a moment" — expected, because the action can
-- clear Trainer far more often than once every second and a half, so the two
-- were racing and the action won most of the time.
--
-- 100ms is 15x tighter while still being a very cheap thing to do: for each Pal
-- with a live follow action it writes one pointer field. It does NOT search for
-- the player (the actor is cached from the follower tick, which already receives
-- it), and it returns immediately when no Pal has a follow action at all — which
-- is the normal state of the game and the case that has to cost nothing. That is
-- Dragón's own standing rule about per-event work, in his words: "ideally you
-- should only activate that IF there are pals following".
-- ===================================================================
-- FOLLOW POSITIONING (two-hundred-and-thirty-third pass, 2026-09-07)
-- ===================================================================
-- Dragón identified a real design problem that only became visible once
-- following actually worked, and he is right about it:
--
--   "otomo pals following is impossible to chase ... they always try to stay on
--    screen where the player is looking and always at a distance, that makes
--    approaching them impossible, since if you try to go near them they continue
--    running forward keeping the distance ... for a real otomo pal that's no
--    problem since the radial menu is fixed on them, but with wild pals that
--    cannot be possible, since they need to be near to interact with them"
--
-- That is a genuine blocker, not a nuisance: this mod's entire interaction layer
-- is aim-based (PET_RANGE 500 units, 25 degrees off-centre). A follower that
-- deliberately keeps itself ahead of the player and out of reach cannot be
-- petted, fed or played with — so making following work perfectly would have
-- made the mod unusable.
--
-- He proposed letting the follow deliberately fail now and then so he could
-- catch up. His OTHER idea is strictly better and makes that unnecessary:
--
--   "cant we try to see if they could act like funnel pals too? ... usually a
--    otomo pal moves where the player is looking at, so they're always on
--    screen while staying near a range close to the player, funnel pals on the
--    other hand move behind the player, following it closely, but rarely
--    staying in front"
--
-- And the field dump from the previous run already contained the answer, on
-- every single Pal, without needing the funnel class at all:
--
--   TargetLocationDistanceForward = 800.0
--   TargetLocationDistanceRight   = 300.0
--
-- The Pal is aiming for a point EIGHT METRES IN FRONT of the player and three to
-- the right. That is precisely the behaviour Dragón described, it is not
-- emergent, and both are plain settable floats on BP_AIAction_OtomoFollow_C.
-- Making Forward negative puts the follower BEHIND the player — funnel-style —
-- with no new class, no new mechanism and no deliberate failure.
--
-- Why this is better than making the follow fail on purpose: an intermittent
-- follow is exactly the broken-looking behaviour of the last several runs, and
-- it would be indistinguishable from a bug both to Dragón and to a future
-- session reading the log. Putting them behind him solves the same problem by
-- design instead of by defect.
--
-- The per-follower spread is not cosmetic either. Dragón's three bonded
-- Petallias killed a hostile Pal and then hurt each other with their own splash
-- ("they managed to kill the hostile pal, but then ended up attacking themselves
-- because their attacks landed on each other"). Three followers all converging
-- on ONE point is what puts them inside each other's area attacks; giving each a
-- different lateral offset spreads them into a line and reduces the overlap. It
-- does not replace ClearMutualHate, it removes some of the occasions for it.
--
-- Values are a gameplay-feel decision and therefore Dragón's, not mine. These
-- are starting points chosen to be conservative: just behind him, close enough
-- that turning around puts them within the 500-unit interaction range.
local FOLLOW_OFFSET_FORWARD = -220.0
local FOLLOW_OFFSET_RIGHT_SLOTS = { 0.0, -260.0, 260.0, -520.0, 520.0 }
local followSlotIndex = {}
local followSlotNext = 0

-- Returns this Pal's lateral offset, stable for the life of the Pal so it does
-- not jitter between slots on every refresh.
local function get_follow_right_offset(key)
    if key == nil then return FOLLOW_OFFSET_RIGHT_SLOTS[1] end
    local idx = followSlotIndex[key]
    if idx == nil then
        idx = (followSlotNext % #FOLLOW_OFFSET_RIGHT_SLOTS) + 1
        followSlotNext = followSlotNext + 1
        followSlotIndex[key] = idx
    end
    return FOLLOW_OFFSET_RIGHT_SLOTS[idx]
end

-- Writes the positioning offsets onto a live follow action. Called wherever the
-- Trainer is written, because anything the action re-derives for itself can be
-- overwritten the same way Trainer was.
local function apply_follow_offsets(action, key)
    pcall(function()
        action.TargetLocationDistanceForward = FOLLOW_OFFSET_FORWARD
        action.TargetLocationDistanceRight = get_follow_right_offset(key)
    end)
end

-- ===================================================================
-- AIM FREEZE (two-hundred-and-thirty-fourth pass, 2026-09-07)
-- ===================================================================
-- Dragón raised the same problem twice, and the second time with the reason:
--
--   "since petallias are faster than the player it was indeed easier to catch
--    her to pet her than before, but it was still a bit tricky ... i would
--    imagine a much faster pal would probably be hard to catch even close,
--    since whenever the player turns to look at them they move again to stay
--    behind"
--
-- Moving them behind him fixed the chasing, but not this: the follow position is
-- relative to where he FACES, so the moment he turns to interact, the Pal
-- re-positions behind him again. A Pal faster than the player can keep that up
-- indefinitely, and this mod's entire interaction layer needs the Pal to sit
-- still inside a 500-unit, 25-degree cone.
--
-- He suggested letting the follow randomly fail. This is the same idea aimed
-- precisely: instead of failing at random, the follower holds position EXACTLY
-- WHEN HE IS LOOKING AT IT, and follows normally the rest of the time. Invisible
-- when not wanted, reliable when it is, and nothing about it looks like a bug in
-- a log.
--
-- HOW THE FREEZE WORKS, and why it is safe. FolowEndDistance (sic, the game's
-- own spelling) is the action's "close enough, stop moving" radius — 100 units
-- by default. Raising it enormously makes the action consider itself already
-- arrived, so it stops of its own accord using its own logic. Nothing is
-- cancelled, nothing is destroyed, Trainer keeps being re-asserted throughout,
-- and Destination keeps updating. Lowering it back restores normal following on
-- the very next tick. This is a reversible one-field nudge, not an interrupt —
-- which is the direct answer to Dragón's question, "doesnt that break anything?
-- do they will still follow and act acordingly after an interaction?"
--
-- It also cannot fight the combat system: the freeze only touches this action's
-- own stopping radius, and any combat action outranks it at a higher priority
-- regardless. A Pal attacked while frozen still defends itself.
--
-- The range and angle deliberately MIRROR Interaction.lua's PET_RANGE (500) and
-- PET_MAX_ANGLE_DEG (25). If those ever change, these must change with them, or
-- there will be a band where the Pal freezes but cannot be interacted with, or
-- worse, can be interacted with but does not freeze.
local USE_AIM_FREEZE = true
local AIM_FREEZE_RANGE = 520.0        -- slightly wider than PET_RANGE (500) so the freeze lands BEFORE the Pal is in reach
local AIM_FREEZE_ANGLE_DEG = 30.0     -- slightly wider than PET_MAX_ANGLE_DEG (25), same reason
local FOLLOW_END_DISTANCE_NORMAL = 100.0
local FOLLOW_END_DISTANCE_FROZEN = 1000000.0

local aimFrozen = {}

local function rotator_forward(rot)
    local yaw = math.rad(rot.Yaw)
    local pitch = math.rad(rot.Pitch)
    return {
        X = math.cos(pitch) * math.cos(yaw),
        Y = math.cos(pitch) * math.sin(yaw),
        Z = math.sin(pitch),
    }
end

-- Reads the player's eye position and facing once per loop pass. Deliberately
-- NOT once per Pal: these are engine calls, and this runs ten times a second.
local function read_player_aim(player)
    local origin = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
    if origin == nil then
        origin = safe_call(function() return player:K2_GetActorLocation() end)
    end
    if origin == nil then return nil, nil end
    local rot = safe_call(function() return player:GetControlRotation() end)
    if rot == nil then return nil, nil end
    return origin, rotator_forward(rot)
end

-- True when the player is looking at this Pal closely enough to interact with
-- it. Pure arithmetic plus one location read — no world scan. Interaction.lua's
-- own find_targeted_pal costs 36-74ms because it walks every Pal in the level;
-- that would be unusable at this cadence, and it is unnecessary here because we
-- already know exactly which actors we care about.
local function player_is_aiming_at(pal, originLoc, forward)
    if originLoc == nil or forward == nil then return false end
    local loc = safe_call(function() return pal:K2_GetActorLocation() end)
    if loc == nil then return false end

    local dx = safe_call(function() return loc.X end)
    local dy = safe_call(function() return loc.Y end)
    local dz = safe_call(function() return loc.Z end)
    local ox = safe_call(function() return originLoc.X end)
    local oy = safe_call(function() return originLoc.Y end)
    local oz = safe_call(function() return originLoc.Z end)
    if dx == nil or ox == nil then return false end

    local vx, vy, vz = dx - ox, dy - oy, dz - oz
    local dist = math.sqrt(vx * vx + vy * vy + vz * vz)
    if dist > AIM_FREEZE_RANGE or dist <= 0.001 then return false end

    local dot = (vx * forward.X + vy * forward.Y + vz * forward.Z) / dist
    if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
    return math.deg(math.acos(dot)) <= AIM_FREEZE_ANGLE_DEG
end

-- Applies or lifts the hold. Writes only on a CHANGE of state, so a follower
-- that is simply being looked at is not written to ten times a second.
local function update_aim_freeze(action, key, pal, originLoc, forward)
    if not USE_AIM_FREEZE then return end
    local shouldFreeze = player_is_aiming_at(pal, originLoc, forward)
    if shouldFreeze == (aimFrozen[key] or false) then return end
    aimFrozen[key] = shouldFreeze
    pcall(function()
        action.FolowEndDistance = shouldFreeze and FOLLOW_END_DISTANCE_FROZEN or FOLLOW_END_DISTANCE_NORMAL
    end)
    Logger.log(string.format(
        "[PalBonds/Combat] [AIM-FREEZE] %s — %s (FolowEndDistance -> %.0f)",
        tostring(key),
        shouldFreeze and "player is looking at it, holding position so it can be interacted with"
                      or "player looked away, following resumes",
        shouldFreeze and FOLLOW_END_DISTANCE_FROZEN or FOLLOW_END_DISTANCE_NORMAL
    ))
end

-- ===================================================================
-- COMPANION TRUCE + COMBAT RECALL (two-hundred-and-thirty-fifth pass, 2026-09-07)
-- ===================================================================
-- Two problems from Dragón's run, and the previous pass fixed neither, because
-- both of its fixes ran at the WRONG TIME rather than being wrong.
--
-- 1. THE TRUCE. His request is explicit and it is the right design:
--
--      "isnt there a way for the bonded pals to not be able to target or
--       discover other bonded pals? simply ignore each other so they cant
--       attack themselves"
--
--    Checked whether the AI preset can express that, and it cannot. The only
--    discovery slots that exist are Discover_Player / Discover_Greater /
--    Discover_Equal / Discover_Smaller — categories by relative SIZE, with no
--    per-actor dimension anywhere. So "Battle" during a fight necessarily means
--    "attack any Pal I notice of that size", and two bonded Petallias are the
--    same size as each other. There is no preset-level way to carve companions
--    out; the only per-actor lever in the game is the hate system.
--
--    So the truce is enforced there, continuously, WHILE the fight is happening,
--    instead of once at the end. The previous pass cleared companion grudges
--    only when the combat window closed — twelve seconds after the last hit.
--    The log shows it working exactly as written and being useless anyway:
--    "cleared 12 companion-to-companion grudges" for a fight in which two dogs
--    were already dead and two had fled.
--
-- 2. THE RECALL. Dragón: "the combat still made them drift off, in fact 2 of the
--    petallias escaped." A companion that chases a fleeing enemy keeps going
--    until it crosses the 3000-unit bond-break and is lost for good. Hate is
--    what holds it out there, so hate is what has to let go — and waiting for
--    the combat window is far too late, since by then it is already gone.
--
--    UPalHate::FindMostHateTarget() (confirmed in Pal.hpp, not guessed) returns
--    whatever the Pal is currently fixated on, whether we pushed it or the game
--    did. Past a recall distance, that target gets a large negative hate push
--    until the Pal disengages and its follow action — which is installed and
--    tracking the player the entire time — gets its turn back.
--
-- COST. Both run on the existing fast loop, throttled to every fifth pass
-- (~500ms), and only while at least one Pal is actually following. The truce
-- additionally only runs during a live combat window. With the usual handful of
-- followers that is a few dozen cheap native calls a second during a fight and
-- nothing at all the rest of the time.
local COMPANION_TRUCE_EVERY_N_PASSES = 5
local COMBAT_RECALL_DISTANCE = 1800.0
local truceCounter = 0
local recallActive = {}

-- Pushes companion-to-companion hate down, both directions, for every pair of
-- followers. This is the closest thing to "they cannot target each other" that
-- the game actually exposes.
local function enforce_companion_truce(followers)
    for _, pal in pairs(followers) do
        safe_call(function()
            local controller = pal.Controller
            if not (controller and controller:IsValid()) then return end
            local hate = controller:GetHateSystem()
            if not (hate and hate:IsValid()) then return end
            for _, other in pairs(followers) do
                if other ~= pal then
                    pcall(function() hate:ChangeHate(other, -COMBAT_ASSIST_HATE_AMOUNT * 10) end)
                end
            end
        end)
    end
end

-- Drops whatever a strayed follower is fixated on, so it stops chasing and the
-- follow action can take over again before it crosses the bond-break distance.
local function recall_strayed_followers(followers, originLoc)
    if originLoc == nil then return end
    local ox = safe_call(function() return originLoc.X end)
    local oy = safe_call(function() return originLoc.Y end)
    local oz = safe_call(function() return originLoc.Z end)
    if ox == nil then return end

    for key, pal in pairs(followers) do
        safe_call(function()
            local loc = pal:K2_GetActorLocation()
            if loc == nil then return end
            local vx = (safe_call(function() return loc.X end) or ox) - ox
            local vy = (safe_call(function() return loc.Y end) or oy) - oy
            local vz = (safe_call(function() return loc.Z end) or oz) - oz
            local dist = math.sqrt(vx * vx + vy * vy + vz * vz)

            if dist <= COMBAT_RECALL_DISTANCE then
                recallActive[key] = nil
                return
            end

            local controller = pal.Controller
            if not (controller and controller:IsValid()) then return end
            local hate = controller:GetHateSystem()
            if not (hate and hate:IsValid()) then return end

            local target = safe_call(function() return hate:FindMostHateTarget() end)
            if target == nil or not safe_call(function() return target:IsValid() end) then
                recallActive[key] = nil
                return
            end

            pcall(function() hate:ChangeHate(target, -COMBAT_ASSIST_HATE_AMOUNT * 10) end)
            if not recallActive[key] then
                recallActive[key] = true
                Logger.log(string.format(
                    "[PalBonds/Combat] [RECALL] %s strayed %.0f units chasing something (limit %.0f) — dropping its target so it comes back instead of running past the %s-unit bond break",
                    tostring(key), dist, COMBAT_RECALL_DISTANCE, "3000"
                ))
            end
        end)
    end
end

local TRAINER_REASSERT_INTERVAL_MS = 100
-- What the loop costs when nothing is bonding, which is nearly all the time.
local TRAINER_REASSERT_IDLE_INTERVAL_MS = 1000
local TRAINER_REASSERT_MAX_TOTAL = 60000
local TRAINER_REASSERT_LOG_EVERY = 100

local followActionObjects = {}
local trainerReassertTotal = 0
local trainerReassertDisabled = false
local trainerReassertFailures = 0
local trainerReassertCounter = {}
-- How many times we found Trainer already cleared at the moment we went to write
-- it. This is the number that says whether the action clobbers it constantly or
-- only at certain transitions — which decides whether 100ms is enough or whether
-- the real answer is hooking TryGetTrainer itself.
local trainerClearedCount = {}
local stuckZeroStreak = {}
local stuckWarned = {}
-- Cached from the follower tick, which already receives the player actor. The
-- fast loop must never call FindFirstOf: at 10 times a second that would be a
-- real cost, and it is the exact shape of the performance problems this project
-- has already had to hunt down twice.
local lastKnownPlayerActor = nil
-- Two-hundred-and-sixty-seventh pass (2026-09-07) — CRASH ON RESPAWN.
--
-- Dragon died, respawned, and the game crashed with EXCEPTION_ACCESS_VIOLATION
-- reading address 0x10 -- a null pointer plus a small field offset -- and a call
-- stack of THIRTY-ONE consecutive UE4SS frames. That is not the game falling
-- over on its own; that is Lua, which means it is this mod.
--
-- The cache above is the obvious suspect and the timing fits exactly. When the
-- player dies their actor is destroyed and a new one is created on respawn. This
-- pointer is refreshed only by the follower tick, once every 1500ms, so for up
-- to a second and a half after death the fast loop is holding a DEAD player
-- actor -- and using it ten times a second. The aim-freeze reads
-- player.FollowCamera off it, so a destroyed actor gives a null component and a
-- read at a small offset: precisely 0x10.
--
-- IsValid() does not save this, and neither does safe_call: pcall catches Lua
-- errors, not native access violations inside the engine call. This project
-- already learned that with the screen-projection probe.
--
-- Fix: the cache now expires. If the follower tick has not refreshed it very
-- recently the fast loop refuses to use it at all, which covers death, respawn,
-- fast travel, loading screens and anything else that swaps the player actor
-- without telling us. Three seconds is two follower ticks -- long enough never
-- to false-trigger in normal play, short enough that a dead pointer is only
-- reachable for a fraction of the window it was before.
--
-- Stated honestly: this is not proven to be the crash. There is no dump, and the
-- log ends without an error because a native access violation kills the process
-- before anything can be written. But it is the only place this mod repeatedly
-- touches a cached engine actor at high frequency, the fault address and the
-- trigger both match, and expiring the cache costs nothing.
-- Two-hundred-and-sixty-eighth pass (2026-09-07) — the expiry above was right in
-- intent and wrong in implementation, and it broke following within one run.
--
-- It used os.clock(), which in Lua is CPU TIME, not wall-clock time. It advances
-- at a rate that has nothing to do with seconds elapsed in the game, so a "3
-- second" window expired almost immediately. The fast loop then bailed out every
-- pass, the Trainer was never re-asserted, and the follow action froze on a
-- stale destination -- visible in Dragon's log as re-assert #801 and #901,
-- eleven seconds apart, reporting the SAME destination to eight decimal places.
-- The Pal stood still, he walked away, and the bond broke as "abandoned".
--
-- Counting loop passes instead removes the dependency on what os.clock means.
-- This loop runs every 100ms and the follower tick that refreshes the cache runs
-- every 1500ms, so the cache is renewed roughly every 15 passes. Allowing 40
-- gives a comfortable margin -- about four seconds of real time -- while still
-- rejecting a pointer left dangling by death or a loading screen long before the
-- old code would have.
local playerCacheAgePasses = 9999
local PLAYER_CACHE_MAX_AGE_PASSES = 40

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

    -- Read before writing, so we can count how often the action has already
    -- wiped it. Cheap (one pointer read plus one validity check) and it is the
    -- measurement that tells us whether this cadence is sufficient.
    local existing = safe_call(function() return action.Trainer end)
    local hadTrainer = existing ~= nil and safe_call(function() return existing:IsValid() end) and true or false
    if not hadTrainer then
        trainerClearedCount[key] = (trainerClearedCount[key] or 0) + 1
    end

    local ok = pcall(function() action.Trainer = playerActor end)
    apply_follow_offsets(action, key)
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
    -- Stuck watchdog. Dragón had exactly one Pal freeze this run — "a petallia
    -- got frozen or stuck, until i petted her, then she started acting like a
    -- wild pal again". One occurrence is not enough to guess a cause from, so
    -- this does not try to fix it; it detects it and says so, once, loudly, with
    -- the state at that moment. A frozen Pal with our action installed and a
    -- zero Destination looks identical from outside to the failure mode we just
    -- fixed, and the two must not be confused in the next log.
    local n = (trainerReassertCounter[key] or 0) + 1
    trainerReassertCounter[key] = n

    if n % 10 == 0 and not stuckWarned[key] then
        local d = safe_call(function() return action.Destination end)
        local dxs = d and safe_call(function() return d.X end)
        if dxs ~= nil and dxs == 0.0 then
            stuckZeroStreak[key] = (stuckZeroStreak[key] or 0) + 1
            -- 10 consecutive zero readings, sampled every 10th re-assert at
            -- 100ms, is roughly ten seconds of a live action with nowhere to go.
            if stuckZeroStreak[key] >= 10 then
                stuckWarned[key] = true
                Logger.log(string.format(
                    "[PalBonds/Combat] [FOLLOW-STUCK] %s — the follow action has been alive with Destination (0,0,0) for ~10s while Trainer is being re-asserted. FollowState=%s IsMoveMode=%s. This is the frozen-Pal case Dragón reported; reported once per Pal.",
                    tostring(key),
                    tostring(safe_call(function() return action.FollowState end)),
                    tostring(safe_call(function() return action.IsMoveMode end))
                ))
            end
        else
            stuckZeroStreak[key] = 0
        end
    end
    if n % TRAINER_REASSERT_LOG_EVERY == 1 then
        local dest = safe_call(function() return action.Destination end)
        local dx = dest and safe_call(function() return dest.X end)
        local dy = dest and safe_call(function() return dest.Y end)
        local moveMode = safe_call(function() return action.IsMoveMode end)
        local followState = safe_call(function() return action.FollowState end)
        Logger.log(string.format(
            "[PalBonds/Combat] [TRAINER-REASSERT] %s — re-assert #%d: Destination=(%s, %s) IsMoveMode=%s FollowState=%s | times Trainer was found ALREADY CLEARED: %d of %d  <-- a non-zero Destination means this worked; the cleared count says how hard the action is fighting us",
            tostring(key), n, tostring(dx), tostring(dy), tostring(moveMode), tostring(followState),
            trainerClearedCount[key] or 0, n
        ))
    end
end

-- The fast loop. ONE self-rescheduling chain for the whole session, started
-- once from main.lua after Combat.Init() — deliberately not a timer per Pal or
-- per event, which is the shape that produced this project's leash-actor leak
-- and its per-event timer leak. It reschedules itself even when it does nothing,
-- so the chain cannot die and silently stop the mechanism.
-- ===================================================================
-- FREEZE A BETRAYED PAL (two-hundred-and-sixty-third pass, 2026-09-07)
-- ===================================================================
-- Dragon, calling it: "remove its ai, make it inert, its better that the scarred
-- pal stays stills forever than still follow the person that betrayed it".
--
-- Agreed, and the evidence supports it over everything else tried. Six attempts
-- went into removing our follow action; the POST-BOND-DUMP then showed the
-- action GONE and the Pal still walking after him, so the action was never what
-- kept it there. What is left driving it is the Pal's own wild AI, which will
-- not re-derive its attitude to the player no matter what preset we write --
-- a problem this project already hit once and never solved.
--
-- So stop trying to change its mind and take away its turn instead. The one
-- thing this session proved beyond doubt is that AN ACTION THAT DOES NOTHING
-- STILL OCCUPIES ITS SLOT: that was the accidental discovery when a neutralised
-- follow action left a Pal standing in place rather than fleeing. That was a bug
-- then. It is exactly the tool now.
--
-- PawnAction_Wait, pushed at Ultimate (13), outranks every tier the wild AI
-- decides at -- Logic, HardScript and Reaction all sit below it. The Pal holds
-- still, permanently, which is precisely what Dragon asked for.
--
-- Re-pushed on the existing fast loop rather than once, because the wild AI gets
-- to decide again constantly and a single push has already been shown not to
-- stick. Bounded hard: every ~2s, at most INERT_MAX_PUSHES times per Pal, then
-- the entry is dropped forever. Two minutes is far longer than a betrayed Pal
-- stays loaded, and the cap means a Pal that somehow survives cannot leave a
-- timer running for the rest of the session.
local INERT_PRIORITY = 13          -- EAIRequestPriority::Ultimate
local INERT_REPUSH_EVERY_N_PASSES = 20   -- the loop runs at 100ms, so ~2s
local INERT_MAX_PUSHES = 60        -- ~2 minutes, then give up on this Pal
local frozenPals = {}
local inertCounter = 0

-- Dragon drew the distinction that mattered: "what you're saying to do is not
-- removing its ai, its telling it to wait, thats different". He is exactly
-- right. Pushing PawnAction_Wait leaves the AI running and deciding underneath
-- while we out-rank it every two seconds -- that is suppression, and it has to
-- be maintained forever or the Pal wakes up.
--
-- APalAIController::SetActiveAI(false) is the real thing: it switches the AI
-- off rather than talking over it.
--
-- And this project already knows precisely what it does, from the worst bug it
-- ever had. The archive records SetActiveAI being tried once on FOLLOWING Pals
-- and being the one change that left them "standing still and dying" -- a
-- catastrophe then, because those were Pals that needed to behave. Applied to a
-- Pal that has just been beaten badly enough to never trust the player again,
-- standing still is the entire point. Same call, same effect, right target.
local function push_inert_action(pal, key)
    local ok = safe_call(function()
        if pal == nil or not pal:IsValid() then return false end
        local controller = pal.Controller
        if not (controller and controller:IsValid()) then return false end
        controller:SetActiveAI(false)
        return true
    end)
    return ok == true
end

-- Called when a bond ends badly. Freezes the Pal where it stands.
-- Read-only. Five seconds after a bond breaks, report what the Pal is actually
-- DOING -- which action is running, at which category, under which controller.
--
-- This is the question that should have been asked seven attempts ago. The
-- POST-BOND-DUMP already proved our follow action is gone by this point and the
-- Pal still walks after the player, so something else is driving it and nobody
-- has looked at what. Three outcomes, each pointing somewhere completely
-- different:
--   * a BP_AIAction_OtomoFollow_C again -> something is REBUILDING our action
--     after the bond ends, and the bug is in our own cleanup.
--   * some other Otomo/companion action -> the companion preset applied during
--     bonding is still in force and is what makes it follow, not our action.
--   * an ordinary wild action (wander, encounter, warning) -> the Pal is not
--     following at all; it is just near the player, and there was never a
--     mechanism to remove.
function Combat.DiagnoseAfterBondLoss(pal, reason)
    pcall(function()
        ExecuteInGameThreadWithDelay(5000, function()
            safe_call(function()
                if pal == nil or not pal:IsValid() then
                    Logger.log("[PalBonds/Combat] [AFTER-BOND] the Pal is gone 5s after the bond broke")
                    return
                end
                local controller = pal.Controller
                local ctrlName = controller and safe_call(function() return controller:GetClass():GetFullName() end)
                local actionName, category
                if controller and safe_call(function() return controller:IsValid() end) then
                    local ac = safe_call(function() return controller:GetAIActionComponent() end)
                    if ac and safe_call(function() return ac:IsValid() end) then
                        category = safe_call(function() return ac:GetCurrentAIActionCategory() end)
                        local cur = safe_call(function() return ac:GetCurrentAction_BP() end)
                        actionName = cur and safe_call(function() return cur:GetFullName() end)
                    end
                end
                Logger.log(string.format(
                    "[PalBonds/Combat] [AFTER-BOND] %s (%s) 5s later: controller=%s | AIcategory=%s | RUNNING ACTION = %s",
                    tostring(safe_call(function() return pal:GetFullName() end)),
                    tostring(reason), tostring(ctrlName), tostring(category), tostring(actionName)
                ))
            end)
        end)
    end)
end

function Combat.FreezeBetrayedPal(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil or frozenPals[key] ~= nil then return end
    frozenPals[key] = { pal = pal, pushes = 0 }
    local first = push_inert_action(pal, key)
    Logger.log("[PalBonds/Combat] [INERT] " .. tostring(key) ..
        " — SetActiveAI(false): its AI is switched off, not talked over (call " ..
        (first and "ok" or "FAILED") ..
        "). Re-applied every ~2s up to " .. INERT_MAX_PUSHES .. " times purely as insurance in case something turns it back on.")
end

local trainerReassertLoopStarted = false

function Combat.StartTrainerReassertLoop()
    if trainerReassertLoopStarted or not USE_TRAINER_REASSERT then return end
    trainerReassertLoopStarted = true
    Logger.log(string.format(
        "[PalBonds/Combat] [TRAINER-REASSERT] fast re-assert loop starting at %dms (idle and free until a Pal actually has a follow action)",
        TRAINER_REASSERT_INTERVAL_MS
    ))

    local function step()
        local didWork = false
        safe_call(function()
            -- The cheap early-out, checked first and before anything else is
            -- read: no bonding Pal has a follow action, so there is nothing to
            -- do and this costs a single table lookup.
            if trainerReassertDisabled then return end

            -- Frozen Pals are maintained here too, so this needs to run whenever
            -- EITHER table has something in it.
            if next(frozenPals) ~= nil then
                inertCounter = inertCounter + 1
                if inertCounter % INERT_REPUSH_EVERY_N_PASSES == 0 then
                    for fkey, entry in pairs(frozenPals) do
                        local fp = entry.pal
                        if fp == nil or not safe_call(function() return fp:IsValid() end)
                           or entry.pushes >= INERT_MAX_PUSHES then
                            frozenPals[fkey] = nil
                        else
                            entry.pushes = entry.pushes + 1
                            push_inert_action(fp, fkey)
                            if entry.pushes == INERT_MAX_PUSHES then
                                Logger.log("[PalBonds/Combat] [INERT] " .. tostring(fkey) ..
                                    " — reached the re-push cap, letting it go")
                            end
                        end
                    end
                end
            end

            if next(followActionObjects) == nil then return end

            -- Age check FIRST: an actor destroyed by death or a loading screen
            -- can still answer IsValid() truthfully enough to get us killed on
            -- the next field read, so freshness is the real guard here and
            -- validity is only the second line.
            playerCacheAgePasses = playerCacheAgePasses + 1
            local player = lastKnownPlayerActor
            if player == nil or playerCacheAgePasses > PLAYER_CACHE_MAX_AGE_PASSES then
                lastKnownPlayerActor = nil
                return
            end
            if not safe_call(function() return player:IsValid() end) then
                lastKnownPlayerActor = nil
                return
            end

            didWork = true

            -- Read the player's eye/facing ONCE for the whole pass, then reuse
            -- it for every follower.
            local originLoc, forward = read_player_aim(player)

            -- Truce and recall, every fifth pass (~500ms). Both need the set of
            -- live followers, so it is built once here rather than per check.
            truceCounter = truceCounter + 1
            if truceCounter % COMPANION_TRUCE_EVERY_N_PASSES == 0 then
                local followers = {}
                local n = 0
                for key, isFollowing in pairs(BondingState) do
                    if isFollowing then
                        local fp = FollowerActors[key]
                        if fp ~= nil and safe_call(function() return fp:IsValid() end) then
                            followers[key] = fp
                            n = n + 1
                        end
                    end
                end
                -- The truce only matters when they can actually be provoked into
                -- fighting, i.e. during a live combat window, and only when there
                -- is more than one of them to fall out with.
                if playerCombatActive and n > 1 then
                    safe_call(function() enforce_companion_truce(followers) end)
                end
                if n > 0 then
                    safe_call(function() recall_strayed_followers(followers, originLoc) end)
                end
            end

            for key, action in pairs(followActionObjects) do
                reassert_follow_trainer(nil, key, player)
                -- reassert may have dropped a dead action; re-read before use.
                local live = followActionObjects[key]
                local palActor = FollowerActors[key]
                if live ~= nil and palActor ~= nil and safe_call(function() return palActor:IsValid() end) then
                    safe_call(function() update_aim_freeze(live, key, palActor, originLoc, forward) end)
                end
            end
        end)

        -- Idle backoff. Scheduling itself is not free, and lag has been a real,
        -- repeatedly-reported problem in this project, so the loop only runs at
        -- the fast cadence while a Pal actually has a follow action. The rest of
        -- the time — which is nearly all of it — it wakes ten times less often
        -- and does a single table lookup. It never stops entirely, because a
        -- loop that has to be restarted is a loop that will one day silently
        -- fail to restart.
        local nextDelay = didWork and TRAINER_REASSERT_INTERVAL_MS or TRAINER_REASSERT_IDLE_INTERVAL_MS

        -- Reschedule unconditionally, including after an error above, so one bad
        -- frame cannot silently end the loop for the rest of the session.
        pcall(function()
            ExecuteInGameThreadWithDelay(nextDelay, step)
        end)
    end

    pcall(function() ExecuteInGameThreadWithDelay(TRAINER_REASSERT_IDLE_INTERVAL_MS, step) end)
end

local followActionAttempts = {}
local followActionCapLogged = {}
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

    -- Two-hundred-and-forty-first pass (2026-09-07) — this is why followers never
    -- came back after a fight, and the log says it plainly. Dragón's Petallia
    -- re-asserted its Trainer 801 times in a row, every 100ms, right up to
    -- 14:41:14. Combat started at 14:41:18. There is not one re-assert line for
    -- her after that, ever — and the only path that stops those lines is the
    -- action going invalid, which drops it from followActionObjects.
    --
    -- So a combat action does not merely outrank our follow action at Logic
    -- priority; it DESTROYS it. And because installation was capped at one
    -- attempt per Pal for the entire session, nothing ever rebuilt it. The Pal
    -- kept the bond, kept the companion preset, and had no follow behaviour left
    -- at all — which is exactly what Dragón described: "my petallia defended me
    -- and together we won, but then my petallia started drifting away".
    --
    -- The one-shot cap was right when this mechanism was unproven and a retry
    -- loop could have leaked objects the way the leash spawn did. It is wrong now
    -- that the mechanism is confirmed working and its lifetime is known to be
    -- shorter than the bond's.
    --
    -- What keeps it safe is the check BELOW rather than the cap: an install only
    -- happens when there is no live action for this Pal. A healthy follower never
    -- reaches the counter at all, so in normal play this costs one install per
    -- Pal plus one per fight it survives. The per-Pal cap stays as a backstop
    -- against a Pal whose action is destroyed instantly and repeatedly, and the
    -- whole thing is still driven by the 1.5s follower tick, so even the
    -- pathological case is bounded to well under one attempt a second.
    local existing = followActionObjects[key]
    if existing ~= nil and safe_call(function() return existing:IsValid() end) then
        return
    end

    local attempts = followActionAttempts[key] or 0
    if attempts >= FOLLOW_ACTION_MAX_PER_PAL then
        if not followActionCapLogged[key] then
            followActionCapLogged[key] = true
            Logger.log(string.format(
                "[PalBonds/Combat] [FOLLOW-ACTION] %s has hit the per-Pal install cap (%d) — its follow action keeps being destroyed faster than it can be rebuilt, so following is given up for this Pal",
                tostring(key), FOLLOW_ACTION_MAX_PER_PAL
            ))
        end
        return
    end
    if attempts > 0 then
        Logger.log(string.format(
            "[PalBonds/Combat] [FOLLOW-ACTION] %s — its follow action is gone (destroyed by combat, most likely); REBUILDING it, attempt %d of %d",
            tostring(key), attempts + 1, FOLLOW_ACTION_MAX_PER_PAL
        ))
    end
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

    -- Position the follower BEHIND the player from the very first tick, rather
    -- than letting it run 8 metres ahead once and then be corrected.
    apply_follow_offsets(action, key)
    Logger.log(string.format(
        "[PalBonds/Combat] [FOLLOW-POS] %s — follow offsets set: forward=%.0f right=%.0f (negative forward = behind the player, so it stays reachable for petting)",
        tostring(key), FOLLOW_OFFSET_FORWARD, get_follow_right_offset(key)
    ))

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
        -- Two-hundred-and-fifty-fifth pass (2026-09-07). Dragon, insisting after
        -- the previous fix: "the chikipi never stopped following even with 0
        -- trust". He is right to push, because cancelling the action is not
        -- sufficient on its own and I shipped it as if it were.
        --
        -- AllCancelAction_Logic_HardScript_Reaction (added last pass, further
        -- down) cancels whatever is RUNNING. It does not UNINSTALL anything: our
        -- follow action is still sitting in the component at priority 10, so the
        -- moment the Pal next picks an action it can simply choose ours again
        -- and walk right back to the player it just fled from. HasAction would
        -- still return true afterwards.
        --
        -- So the action is neutralised as well as cancelled, using the trick the
        -- aim-freeze already proves works: FolowEndDistance is the action's own
        -- "close enough, stop moving" radius, and setting it enormous makes the
        -- action consider itself permanently arrived. Even if the AI picks it
        -- again, it stands still. That is a plain float write on an object this
        -- mod constructed itself -- nothing engine-owned is touched.
        --
        -- Done FIRST, before the table clears below, because they drop the very
        -- reference this needs.
        -- Two-hundred-and-fifty-eighth pass (2026-09-07). Dragon, after the
        -- previous attempt: "the scarred pal still follows me around, never
        -- running away". The interaction block works now; the behaviour does
        -- not, and my last fix is the likely reason.
        --
        -- I set FolowEndDistance enormous to make the action think it had
        -- arrived. That reading of the field may well be backwards: it is
        -- equally consistent with "the distance at which following ENDS", in
        -- which case an enormous value means NEVER STOP FOLLOWING -- which is
        -- exactly the behaviour he is describing. I had no evidence either way
        -- and shipped the guess.
        --
        -- Dropped, in favour of a function that says what it does:
        --     UPalAIActionComponent::TerminateCurrentActionByClass(actionClass)
        -- found in Pal.hpp alongside SetAction and HasAction. Unlike
        -- AllCancelAction_Logic_HardScript_Reaction, which cancels whatever
        -- happens to be RUNNING and leaves ours installed to be picked again,
        -- this names the class to terminate. That is the removal this needed all
        -- along -- and with the slot genuinely free, the escape preset forced by
        -- the betrayal finally has somewhere to run.
        --
        -- The field is also restored to its normal value on the way out, so if
        -- the action does survive in some form it is at least not left in the
        -- state I may have been misusing.
        local dyingAction = followActionObjects[key]
        if dyingAction ~= nil and safe_call(function() return dyingAction:IsValid() end) then
            pcall(function() dyingAction.FolowEndDistance = FOLLOW_END_DISTANCE_NORMAL end)
        end
        safe_call(function()
            if pal == nil or not pal:IsValid() then return end
            local controller = pal.Controller
            if not (controller and controller:IsValid()) then return end
            local actionComp = controller:GetAIActionComponent()
            if not (actionComp and actionComp:IsValid()) then return end
            local cls = get_follow_action_class()
            if cls == nil then return end

            -- Two-hundred-and-fifty-ninth pass (2026-09-07). The previous
            -- attempt answered its own question and the answer was no:
            --   TerminateCurrentActionByClass(follow) call=ok
            --   | still installed at priority 10 afterwards = TRUE
            -- It terminates the RUNNING action; it does not uninstall it. Third
            -- removal attempt to fail, so this pass does two things rather than
            -- one, and stops betting everything on removal working.
            --
            -- ATTEMPT 0, and it is Dragon's idea (two-hundred-and-sixty-first
            -- pass): "what if you try to swap it again by a wild ai? like on
            -- previous runs?"
            --
            -- He is pointing at the one route never tried. Terminate and cancel
            -- both ask the occupant to STOP; neither EVICTS it. But a priority
            -- slot holds one action, so putting a different action in should
            -- displace ours -- which is also exactly how combat has been
            -- destroying it all along, something this project observed and then
            -- failed to draw the obvious conclusion from.
            --
            -- PawnAction_Wait is the candidate the game itself supplies: the
            -- FOLLOW-DIFF probe caught a REAL Otomo running one, so it is a
            -- stock engine do-nothing action that Palworld's own AI uses. Pushed
            -- at the same priority, it takes the slot, and a Wait that finishes
            -- leaves the slot genuinely empty rather than occupied by an inert
            -- follow action -- which is the difference between "stands there"
            -- and "free to flee".
            local waitCls = safe_call(function() return StaticFindObject("/Script/AIModule.PawnAction_Wait") end)
            if waitCls ~= nil then
                local waitAction = safe_call(function() return StaticConstructObject(waitCls, actionComp) end)
                if waitAction ~= nil and safe_call(function() return waitAction:IsValid() end) then
                    local okSwap = pcall(function() actionComp:SetAction(waitAction, FOLLOW_ACTION_PRIORITY, pal) end)
                    local stillSwap = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
                    Logger.log("[PalBonds/Combat] " .. tostring(key) ..
                        " — SWAP: pushed PawnAction_Wait into the follow slot, call=" .. (okSwap and "ok" or "FAILED") ..
                        " | our follow action still installed afterwards = " .. tostring(stillSwap) ..
                        "  <-- false means the swap evicted it and the Pal is free")
                    if stillSwap == false then return end
                end
            else
                Logger.log("[PalBonds/Combat] " .. tostring(key) .. " — SWAP: could not resolve PawnAction_Wait, falling through to the other attempts")
            end

            -- ATTEMPT: AllCancelPushedAction(Instigator). Genuinely different
            -- from the two already tried -- it targets actions that were PUSHED
            -- by a given instigator, which is exactly what ours is: we install
            -- it with SetAction(action, 10, pal), so `pal` is the instigator to
            -- name here.
            local okPushed = pcall(function() actionComp:AllCancelPushedAction(pal) end)
            local stillPushed = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
            Logger.log("[PalBonds/Combat] " .. tostring(key) ..
                " — AllCancelPushedAction(instigator=pal) call=" .. (okPushed and "ok" or "FAILED") ..
                " | still installed afterwards = " .. tostring(stillPushed))

            local ok = pcall(function() actionComp:TerminateCurrentActionByClass(cls) end)
            local still = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
            Logger.log("[PalBonds/Combat] " .. tostring(key) ..
                " — TerminateCurrentActionByClass(follow) call=" .. (ok and "ok" or "FAILED") ..
                " | still installed at priority " .. FOLLOW_ACTION_PRIORITY .. " afterwards = " .. tostring(still))

            -- FALLBACK, applied whenever the action survives every removal
            -- attempt. If it cannot be taken out of the slot, then it stays --
            -- but it does not have to keep pointing at the player.
            --
            -- Trainer is the field the whole mechanism reads to decide where to
            -- go, and it is the one thing about this action that is reliably
            -- ours to write; the entire follow feature was built on discovering
            -- that. Pointing it at the Pal ITSELF means the action computes a
            -- destination of "where I already am" and the Pal stops chasing the
            -- player. That is not fleeing -- an occupied Logic slot still leaves
            -- no room for the escape behaviour -- but "stands there ignoring
            -- you" is a far better failure than "keeps following the person who
            -- just beat it", and it is guaranteed to work because it uses the
            -- exact write this mod has been doing successfully all along.
            if still ~= false then
                local dying = followActionObjects[key]
                if dying ~= nil and safe_call(function() return dying:IsValid() end) then
                    local okSelf = pcall(function() dying.Trainer = pal end)
                    Logger.log("[PalBonds/Combat] " .. tostring(key) ..
                        " — the follow action could not be removed, so it now follows ITSELF instead of the player (" ..
                        (okSelf and "ok" or "write failed") .. ") — it will stop chasing even if it cannot flee")

                    -- Two-hundred-and-sixtieth pass (2026-09-07). Everything
                    -- above reported success and the Pal still follows, so this
                    -- stops fixing and starts LOOKING. Five test runs have gone
                    -- into theories about fields and functions I had not
                    -- measured; the one time this project got unstuck was by
                    -- dumping the object's real state instead, which is what
                    -- found the Trainer clobber in the first place.
                    --
                    -- Read-only, five seconds after the bond breaks -- late
                    -- enough that the action has ticked many times with our new
                    -- values, so what it reports is what it settled on rather
                    -- than what we just wrote. Three outcomes, all decisive:
                    --
                    --   Trainer is the PLAYER again -> the action re-derives it
                    --     via TryGetTrainer and our self-write is being undone,
                    --     exactly as it was during the original follow work.
                    --   Trainer is the PAL and Destination tracks the player ->
                    --     the destination does not come from Trainer at all, and
                    --     every assumption this feature rests on is wrong.
                    --   Trainer is null and Destination is frozen -> our action
                    --     is inert and something ELSE entirely is moving the
                    --     Pal, which would be a completely different search.
                    pcall(function()
                        ExecuteInGameThreadWithDelay(5000, function()
                            safe_call(function()
                                if dying == nil or not dying:IsValid() then
                                    Logger.log("[PalBonds/Combat] [POST-BOND-DUMP] " .. tostring(key) ..
                                        " — the action object is gone 5s after the bond broke, so it is NOT what is moving this Pal")
                                    return
                                end
                                local function nm(v)
                                    if v == nil then return "nil" end
                                    if not safe_call(function() return v:IsValid() end) then return "invalid" end
                                    return tostring(safe_call(function() return v:GetFullName() end))
                                end
                                local d = safe_call(function() return dying.Destination end)
                                Logger.log(string.format(
                                    "[PalBonds/Combat] [POST-BOND-DUMP] %s 5s after the bond broke: Trainer=%s | Destination=(%s, %s) | FollowState=%s | IsMoveMode=%s | FolowEndDistance=%s",
                                    tostring(key),
                                    nm(safe_call(function() return dying.Trainer end)),
                                    tostring(d and safe_call(function() return d.X end)),
                                    tostring(d and safe_call(function() return d.Y end)),
                                    tostring(safe_call(function() return dying.FollowState end)),
                                    tostring(safe_call(function() return dying.IsMoveMode end)),
                                    tostring(safe_call(function() return dying.FolowEndDistance end))
                                ))
                            end)
                        end)
                    end)
                end
            end
        end)

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
        followActionAttempts[key] = nil
        followActionCapLogged[key] = nil
        trainerReassertCounter[key] = nil
        trainerClearedCount[key] = nil
        stuckZeroStreak[key] = nil
        stuckWarned[key] = nil
        followSlotIndex[key] = nil
        aimFrozen[key] = nil
        recallActive[key] = nil
    end
    -- Two-hundred-and-fifty-fourth pass: Dragon reported a betrayed Pal "continued
    -- following me", and the log agrees it should not have -- "no longer
    -- following" fired correctly at the moment of betrayal.
    --
    -- The bookkeeping stopped; the BEHAVIOUR did not. Everything above clears
    -- our own tables, but the BP_AIAction_OtomoFollow_C we pushed onto the Pal's
    -- action component is still installed and still holding a valid Trainer
    -- pointer. Dropping followActionObjects only stops us RE-asserting that
    -- pointer -- it does not take the action back -- so the Pal kept walking
    -- after the player it had just fled from.
    --
    -- AllCancelAction_Logic_HardScript_Reaction clears the Logic tier, which is
    -- exactly where the follow action sits (priority 10). Confirmed working 5/5
    -- on wild Pals earlier in this project. Letting the wild AI take back over is
    -- precisely what a Pal that just lost its trust should do.
    safe_call(function()
        if pal == nil or not pal:IsValid() then return end
        local controller = pal.Controller
        if not (controller and controller:IsValid()) then return end
        local actionComp = controller:GetAIActionComponent()
        if not (actionComp and actionComp:IsValid()) then return end
        local ok = pcall(function() actionComp:AllCancelAction_Logic_HardScript_Reaction(pal) end)
        Logger.log("[PalBonds/Combat] " .. tostring(key) .. " — cancelling its follow action so it actually stops following (" ..
            (ok and "ok" or "call failed") .. ")")
    end)

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
    -- Cache for the fast loop, which must not go looking for the player itself.
    if playerActor ~= nil then
        lastKnownPlayerActor = playerActor
        playerCacheAgePasses = 0
    end
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
