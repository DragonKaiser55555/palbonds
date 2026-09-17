local Logger = require("Logger")
local Combat = {}
local FOLLOW_ACCEPTANCE_RADIUS = 200.0 

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
local ORBIT_STEP_RADIANS = 0.9 
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
local ECC_VISIBILITY = 3 
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

-- ===========================================================================
-- SAFER PLAYER LOOKUP (two-hundred-and-ninety-second pass, 2026-09-09)
-- ===========================================================================
-- Dragon crashed on death and respawn, and this one is NOT the world-change
-- crash that was fixed earlier -- different fault address, different stack:
--
--     EXCEPTION_ACCESS_VIOLATION reading address 0x10
--     31 consecutive UE4SS frames, then Palworld
--
-- 0x10 is UObjectBase::ClassPrivate -- his own UE4SS startup log prints exactly
-- that offset. So something read Object->ClassPrivate on a NULL object, deep
-- inside UE4SS itself rather than in game code.
--
-- That is the signature described in UE4SS issue #1328, by the same person who
-- found the out-of-bounds iteration bug:
--
--     "FindFirstOf also derefs Object/Class before validating, while FindAllOf
--      already guards, so that's worth a null check too."
--
-- FindFirstOf calls IsA on whatever the iteration hands back, without checking
-- it first. FindAllOf performs that check. Death is a bad moment to be walking
-- the object array -- the player actor is being destroyed while we look for it.
--
-- This cannot be fixed from Lua, so it is avoided instead: same lookup, via the
-- path that guards. Honest about the limits -- the upstream bug is unfixed and
-- this reduces exposure rather than removing it, and the deep UE4SS recursion
-- in that stack is not something a mod can reach at all.
--
-- 2026-09-15 (profiling): every call here walked the whole object array. The
-- same guarded lookup now lives in PlayerRef.lua, which keeps the reference
-- until it goes invalid instead of searching on every call.
local function find_player()
    return require("PlayerRef").Get()
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
local COMBAT_WINDOW_MS = 12000 

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
local AI_REQUEST_PRIORITY_LOGIC = 10 

-- Two-hundred-and-second pass: key (GetFullName()) -> { actionComp, composite }.
-- The cached composite is rebuilt automatically if either half goes
-- invalid (Pal despawned, GC'd, etc.) — see get_or_build_otomo_composite.
local OtomoCompositeCache = {}
local loggedFollowTickOnce = {}
local USE_REAL_FOLLOW_ACTION = true
local FOLLOW_ACTION_CLASS_PATH = "/Game/Pal/Blueprint/Controller/AIAction/Otomo/BP_AIAction_OtomoFollow.BP_AIAction_OtomoFollow_C"
local FOLLOW_ACTION_PRIORITY = 10
local FOLLOW_ACTION_MAX_PER_PAL = 25

-- ===================================================================
-- PER-PAL INSTALL CAPS ARE RATES TOO (2026-09-12)
-- ===================================================================
-- FOLLOW_ACTION_MAX_PER_PAL and COMBAT_ACTION_MAX_PER_PAL were lifetime
-- counters, reset only when the Pal stopped following. CLAUDE.md's "never
-- budget a retry" rule names this constant as a suspect, and run 33 showed why:
-- one Petallia reached "attempt 8 of 25" follow rebuilds in three fights. A
-- companion kept through a handful more fights would have had following, or
-- fighting, switched off for good, which is exactly how run 29 lost a Flopie.
-- Both caps now count per PER_PAL_INSTALL_WINDOW_SECONDS and recover when the
-- window turns over, so they still stop a runaway loop without ending anything.
local PER_PAL_INSTALL_WINDOW_SECONDS = 60.0

-- ===================================================================
-- THE FOLLOW BUDGET IS A RATE, NOT A LIFETIME ALLOWANCE
-- (three-hundred-and-twenty-seventh pass, 2026-09-12)
-- ===================================================================
-- This was FOLLOW_ACTION_MAX_TOTAL = 40, counted from mod load and never
-- reset, and run 29 shows exactly what that costs:
--
--     13:13:53  [FOLLOW-ACTION] session budget reached (40) - no further attempts
--     13:13:52  Flopie's follow action is gone; REBUILDING it, attempt 3 of 25
--     13:14:19 .. 13:15:09  Flopie walks from 1809 to 4402 units and is lost
--
-- The budget ran out mid-run. followActionDisabled latched true, and from that
-- second onward NO Pal in the session could ever be given a follow action
-- again. Flopie spent her entire drift with no follow action and no possibility
-- of getting one. Dragón stood still and watched her go, which rules out the
-- "she outran the recall" reading completely -- there was simply nothing left
-- holding her.
--
-- CLAUDE.md already carries a section called "Never budget a retry from mod
-- load", written after the tag hooks and the radial hooks were broken by
-- exactly this shape. This budget survived that cleanup because it looked
-- different: it is a leak guard, not a retry limit. It is still the same bug.
-- 40 was a sane number when follow was installed once per Pal; combat now
-- destroys and rebuilds the follow action constantly, so a single busy fight
-- eats the whole session's allowance.
--
-- REMOVED (2026-09-12, run 36): the global rate limit that replaced it
-- (FOLLOW_ACTION_MAX_PER_WINDOW = 40 installs per 60s, shared by every
-- follower). It did not scale with the number of companions: run 36's six
-- companions exhausted it during a fight, and for the next minute NO follower
-- could be given a follow action -- five Pals drifted off and were lost within
-- 12 seconds. Its log line also lied, printing "REBUILDING" before the check
-- that skipped the rebuild. The per-Pal cap (FOLLOW_ACTION_MAX_PER_PAL per
-- PER_PAL_INSTALL_WINDOW_SECONDS) already bounds a runaway loop, Pal by Pal, so
-- the global limit only ever added starvation.
local FOLLOW_ACTION_RECHECK_MS = 6000

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
-- REMOVED (2026-09-12): assistHateTargets and release_assist_hate(). The
-- release subtracted hate, which [HATE-VERIFY] proved does nothing (pass 322),
-- and its only call was already commented out -- but the table it read kept
-- growing all session: every enemy the player fought was stored, with a live
-- actor reference, until the next world change.
-- Seconds before the same enemy is worth re-aiming the companions at; see the
-- debounce inside OnPlayerCombatTarget.
local COMBAT_TARGET_REPUSH_INTERVAL = 1.0
local lastCombatTargetName, lastCombatTargetAt = nil, -99

-- ===================================================================
-- COMBAT ACTION (three-hundredth pass, 2026-09-11)
-- ===================================================================
-- The missing half of combat assist. Everything before this pass told a
-- companion WHO to fight (hate) and gave it permission to fight (the companion
-- preset), but nothing ever gave it a fight to run.
--
-- The proof is in Dragón's 2026-09-11 log: a bonded Cawgnito went
--   FeedItem -> OtomoFollow -> EatDeadBody -> OtomoFollow -> TurnAndEncount
--   -> OtomoFollow -> Death
-- through an entire fight that killed it, without one combat action. The
-- existing [RETARGET] code only ever called SetTargetAndNextAction on the
-- CURRENT action, which is our own follow action and has no such method — so
-- that pcall failed harmlessly every time and [RETARGET] never appeared in any
-- log. It could only redirect a fight the Pal had already started by itself.
--
-- Why a composite was the wrong answer (pass 173 tried it and it reported
-- success while moving nobody): there is no composite class for wild Pals at
-- all. The list is BaseCamp, Worker, Funnel, Otomo and a dummy.
-- UPalAIActionOtomoDefault is what switches an OWNED Pal into combat, via its
-- own ShouldSetCombatAction/FindNearestAttackTarget. A wild Pal has none of
-- that machinery, so installing an Otomo composite on it changes nothing.
--
-- What this does instead is the one mechanism this project has actually got
-- working: construct an action, write its actor fields, push it with SetAction
-- — exactly how following was solved in pass 231. UPalAIActionCombatBase is
-- the structural twin of the follow action:
--     class AActor*        TargetActor;   (follow has Trainer)
--     class APalCharacter* SelfActor;     (follow has SelfActor)
--     void SetTargetAndNextAction(AActor* Target);
--
-- It takes the SAME priority slot as the follow action rather than trying to
-- outrank it, for a deliberate reason: the priority values above Logic are not
-- in any enum dump reachable from here, pass 224 already had to correct a wrong
-- priority constant, and guessing API values is how this project has lost most
-- of its test cycles. Swapping in the same slot needs no new constant — and it
-- matches what the game already does to us, since combat destroys our follow
-- action roughly fifteen times a session anyway.
local ENABLE_COMBAT_ACTION = true
local COMBAT_ACTION_MAX_PER_PAL = 25
local COMBAT_CLASS_SCAN_COOLDOWN = 5.0
local CombatActionClass = nil
local combatActionObjects = {}
-- Per-Pal latch so the "letting it fight" line is logged once per fight, not
-- once per follow tick.
local followSuppressedLogged = {}
-- One-shot latch for the window-extension notice, reset when it finally closes.
local combatWindowExtendLogged = false

-- Actions that mean "this Pal is not in a fight", whatever its hate table says.
-- Matched as substrings against the running action's full name. Deliberately a
-- list of KNOWN-passive actions rather than a test for "is it combat": an
-- unrecognised action is treated as a fight and left alone, which is the safe
-- direction to be wrong in.
local PASSIVE_ACTION_MARKERS = {
    "WildLife", "Sleep", "EatDeadBody", "OtomoFollow", "Death", "Rest", "Eat",

    -- Three-hundred-and-seventeenth pass (2026-09-12): the INTERACTION actions.
    -- Their absence caused a real regression Dragón caught: "they werent
    -- following inmediately after getting bonded, in fact one of the flopies i
    -- feed, managed to run away becoming abandoned without even following me
    -- once - never saw that one happen before".
    --
    -- A Pal that has just been fed is running BP_AIActionPairCall_FeedItem_C.
    -- That was not on this list, and an unrecognised action is deliberately
    -- treated as a fight — so a freshly bonded Pal carrying any hate at all was
    -- classified as "fighting", never received its follow action, wandered off
    -- and was declared abandoned. Bonding is the one moment this Pal is
    -- guaranteed to be mid-interaction, which is why it showed up there first.
    "PairCall", "Petting", "Feed", "Happy",

    -- Warning_PointWalk is the wild "go wander over there" order, not combat
    -- posturing. Dragón corrected an assumption of mine here: the Petallia that
    -- ran it was rolled "curious", so it cannot be a Grumpy behaviour -- "i
    -- would asume the pointwalk, its actually the command that orders the pals
    -- to move somewhere (drift away) when wild idle". Leaving it out of this
    -- list is what let a drifting Pal be mistaken for a fighting one.
    "Warning_PointWalk", "PointWalk",
}
local passiveDespiteHateLogged = {}
-- Latch so the player-target line is logged once per Pal, not once per tick.
local offTargetLogged = {}
local targetDisciplineErrorLogged = false

-- How long a Pal may be left out of the follow system because it "is fighting"
-- before we take it back. Long enough for a real fight, short enough that a
-- stuck Pal is recovered while the player is still nearby.
local MAX_FIGHT_PROTECTION_SECONDS = 25.0
local followProtectedSince = {}
local function palKeyForLog(pal)
    return safe_call(function() return pal:GetFullName() end) or "unknown"
end
local combatActionAttempts = {}
local combatActionAttemptsSince = {}

-- ===================================================================
-- INSTALL TRACING IS NOW FAILURE-ONLY (pass 332, 2026-09-12)
-- ===================================================================
-- Dragón still felt lag and asked whether it was the log. Run 30 answers it
-- with numbers: 37 follow installs and 39 combat installs produced roughly 530
-- of the run's 913 lines, and every one of those lines said "ok" or "true".
-- They were built when installs were genuinely failing and have reported
-- nothing but success for many passes since.
--
-- Worse than the volume, two of them paid for a GetFullName() -- a full path
-- string built purely to be printed -- and they ran in exactly the busy
-- fighting moments where the lag shows up.
--
-- So success is now silent and counted, failure is still logged in full, and a
-- single summary line reports the counts when a fight ends. That keeps every
-- bit of diagnostic value that was actually being used while removing the
-- per-install cost.
local followInstallCount = 0
local combatInstallCount = 0
function Combat.ReportInstallCounts()
    local f, c = followInstallCount, combatInstallCount
    followInstallCount, combatInstallCount = 0, 0
    return f, c
end
local combatActionDisabled = false
local lastCombatClassScanAt = -99
local combatClassScanCount = 0

-- Forward declarations. Lua locals are not hoisted, and OnPlayerCombatTarget
-- below is defined BEFORE these functions are — without this the name would
-- compile as a global lookup and silently resolve to nil at runtime, which is
-- exactly the bug pass 180 found in this same file.
local try_install_combat_action
local combat_action_is_live
local clear_combat_action

-- Also forward-declared, and for the same reason. close_combat_window (far
-- above its definition) calls this, and without the declaration it compiled as
-- a GLOBAL lookup and threw "attempt to call a nil value" every time the combat
-- window tried to close -- which killed the whole close sequence:
-- playerCombatActive was never cleared, assist hate was never released, and the
-- out-of-combat companion preset was never restored.
--
-- It stayed invisible because HOLD_WINDOW_WHILE_FIGHTING was false until the
-- three-hundred-and-twelfth pass, so the branch never ran. This is the third
-- time this file has been bitten by Lua locals not hoisting (see pass 180).
local pal_has_own_fight
local resume_follow_after_combat  -- forward: enforce_target_discipline and the
                                  -- recall both call it from above its definition.
local get_follow_action_class   -- forward: defined far below, used by suspend_follow_for_combat
local followActionObjects       -- forward: same reason. NOTE it is assigned (not re-declared)
                                -- below; a second `local` would shadow it and suspend_follow_for_combat
                                -- would then clear a different table than the rest of the file reads.

-- ===================================================================
-- FOLLOW SUSPENSION DURING COMBAT (three-hundred-and-fourteenth pass, 2026-09-12)
-- ===================================================================
-- The action-change probe settled what five runs of theorising could not. Across
-- a whole session, every transition a bonded Pal made was one of:
--     OtomoFollow <-> Damage      (hit, flinched, straight back to follow)
--     OtomoFollow <-> WildLife
--     OtomoFollow  -> Death
-- and NOT ONE transition into a combat action. They were never being interrupted
-- mid-attack; they never began an attack at all.
--
-- The reason is that "do not REBUILD follow" was never enough. The follow action
-- is already installed at priority 10 and re-asserted every 100ms, so it holds
-- the slot continuously and the Pal's AI never gets an opening to choose combat.
-- Only the game forcing a damage flinch, or death, ever broke through.
--
-- Dragón's model, and it matches how the game itself behaves: "usually when a
-- otomo pal fights it focuses solely on fighting the oponent, even if it has to
-- leave my side for that bit, so dropping follow while they fight sounds like
-- the right choice, the only thing is that once its over, they have to return to
-- my side".
--
-- So during the player's combat the follow action is TERMINATED and not
-- re-installed or re-asserted, leaving the Pal free to fight; when the fight
-- ends it is rebuilt and the Pal comes back. Suspension is capped in time so a
-- Pal can never be left out of the follow system indefinitely, and while it is
-- suspended the distance-based trust loss is paused -- he had to physically
-- chase chasing companions to stop them being declared abandoned, which is not
-- a mistake he should be punished for.
local followSuspendedForCombat = {}

-- Self-defence outside a player fight (2026-09-12) — see Combat.OnFollowerAttacked.
-- The window matches the player's combat window: the fight is over once neither
-- side has hit the other for that long.
local SELF_DEFENCE_ENABLED = true
local SELF_DEFENCE_WINDOW_SECONDS = COMBAT_WINDOW_MS / 1000
local selfDefenceEnemy = {}      -- key -> the actor that attacked this companion
local selfDefenceLastHitAt = {}  -- key -> os.clock() of the last hit either way

-- How far a follower may be from the player before the recall marches it back,
-- and which followers are being marched right now. Declared up here because the
-- fight assignment below must respect both (2026-09-12, runs 35 and 36): sending
-- a Pal at an enemy it can only reach by crossing this distance, or at any
-- enemy while it is being recalled, made the recall and the assist undo each
-- other every 1-3 seconds -- 45 recalls against 51 fight assignments in run 36,
-- and the worst install churn this project has measured.
local COMBAT_RECALL_DISTANCE = 1800.0
-- 2026-09-16, Dragón: a companion defending ITSELF may go further — "1800 is
-- too close, let it be 3000 before they touch the abandoned border". Run 2's
-- Garm dropped both of its self-defence fights against a Lifmunk (a ranged
-- shooter) in the same second as "out of reach". This limit applies only to a
-- self-defence fight outside a player fight; player fights keep 1800. It is
-- the leash distance (Trust MAX_FOLLOW_DISTANCE), and a fighting Pal is
-- protected from the leash, so the fight ends before the bond is at risk.
-- RELEASE SWITCH: held back from 1.1.3 for the next update (Dragón, 2026-09-16).
-- false = self-defence keeps the 1800 limit, as in 1.1.2. A module field so
-- the harness can test both ways.
Combat.SELF_DEFENCE_EXTENDED_REACH = false
local SELF_DEFENCE_EXTENDED_DISTANCE = 3000.0
local function self_defence_limit()
    return Combat.SELF_DEFENCE_EXTENDED_REACH and SELF_DEFENCE_EXTENDED_DISTANCE or COMBAT_RECALL_DISTANCE
end
local recallActive = {}

-- Straight-line distance between two actors, or nil if either location cannot
-- be read. Callers treat nil as "in reach" so an unreadable location never
-- stops a companion from fighting.
local function actor_distance(a, b)
    if a == nil or b == nil then return nil end
    local la = safe_call(function() return a:K2_GetActorLocation() end)
    local lb = safe_call(function() return b:K2_GetActorLocation() end)
    if la == nil or lb == nil then return nil end
    local d = safe_call(function()
        local dx, dy, dz = la.X - lb.X, la.Y - lb.Y, la.Z - lb.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return d
end
local outOfReachLoggedFor = nil

-- The actor the player is currently fighting. Kept so the combat order can be
-- RE-ASSERTED every tick instead of issued once and hoped over -- see the
-- directive block in try_real_follow_action.
local currentPlayerEnemy = nil

-- Player-target denial cadence on the 100ms loop: every 3rd pass ~= 300ms.

local DENY_TARGET_EVERY_N_PASSES = 3
local denyTargetCounter = 0
local MAX_COMBAT_SUSPENSION_SECONDS = 25.0

local function suspension_key(pal)
    return safe_call(function() return pal:GetFullName() end)
end

-- ===================================================================
-- A COMPANION MUST NEVER CARRY HATE FOR ITS OWN TRAINER
-- (three-hundred-and-fifteenth pass, 2026-09-12)
-- ===================================================================
-- The moment following was dropped and companions were finally free to fight,
-- some of them fought DRAGÓN. His words: "it was kind of odd that some of them
-- targeted me even while bonded but at least they attacked?".
--
-- The action trace shows it exactly, and it is the first real combat this
-- project has ever produced:
--     FlowerDoll : LookSideMove -> CombatPal        (hate target: BP_Player_Female)
--     FlowerDoll : CombatPal <-> AnimationSideStep  (attack, reposition, repeat)
--     FlowerDoll : CombatPal -> OtomoFollow         (hate target: none)
-- A complete fight-and-return cycle, aimed at the wrong actor.
--
-- Where the hate comes from: the player's own splash damage. A stray hit on a
-- companion registers as the player attacking it, and that hate sits in its
-- table. While the follow action monopolised the AI slot this never surfaced --
-- the Pal could not act on anything. Freeing it for combat also freed it to act
-- on a grudge against its trainer.
--
-- Note what this proves about the preset: Damaged_Player and Discover_Player
-- are both Ignore, and the Pal attacked him anyway. So the AI response preset
-- governs whether a Pal REACTS to a category, but hate governs WHO it picks
-- once it is already fighting. The preset alone cannot protect the player, and
-- 15 of the trace's hate readings were pointed at him.
--
-- Hate is per-actor, which is the one lever that can express "not this one", so
-- the player is scrubbed from a companion's hate table whenever it is released
-- to fight.
-- REMOVED (three-hundred-and-twenty-second pass, 2026-09-12): clear_player_hate
-- and its [HATE-VERIFY] probe. The probe did its job and returned a definitive
-- answer -- "player was most-hated; after ChangeHate(-999999) the most-hated is
-- now: BP_Player_Female_C" -- so hate SUBTRACTION does not work in this build,
-- and a function that cannot do the one thing it exists for is worse than no
-- function: it was called for every follower on every tick and made the code
-- read as though the problem were handled.
--
-- Target control now goes through enforce_target_discipline, which reads the
-- action's TargetActor instead. The POSITIVE assist push is kept -- adding hate
-- is a different operation and is the one the game itself uses.

-- ===================================================================
-- TARGET DISCIPLINE (three-hundred-and-twenty-second pass, 2026-09-12)
-- ===================================================================
-- One rule, replacing three that each handled a slice of the same problem.
--
-- A companion may fight EXACTLY ONE thing: whatever the player is fighting. Any
-- combat action aimed at anything else -- the player, another companion, a
-- random wild Pal it wandered past -- is cancelled, and follow takes over.
--
-- Why this shape: run 25 proved the hate table cannot be corrected.
-- [HATE-VERIFY] logged the player still most-hated IMMEDIATELY after
-- ChangeHate(-999999), so hate SUBTRACTION does not work in this build, and
-- every fix that steered targets by removing hate was a no-op -- the player
-- hate clearing, the outbid push, Trust's ClearMutualHate truce.
--
-- This needs none of it. TargetActor is a plain field on the running action,
-- and field reads are something this project has always been able to do. Read
-- it, compare it to the player's enemy, and if it does not match, the fight is
-- not ours and it ends.
--
-- It subsumes and replaces: the player-target rule, the companion-duel breakup,
-- and the target half of the passive-action classifier.
local targetDisciplineFires = 0

-- REWRITTEN (three-hundred-and-twenty-third pass, 2026-09-12) after run 27
-- showed the previous version was blind and was cancelling the very fights it
-- was meant to protect.
--
-- THE JOB, NARROWED. A companion must never swing at its own trainer or at
-- another companion. During a fight the player started, it must also stay on
-- that fight. Anything else it picks is left alone, because a companion that is
-- genuinely being attacked has to be able to defend itself.
--
-- WHY IT READS THE HATE TABLE AND NOT TargetActor. The previous version read
-- `cur.TargetActor` off the running combat action. Run 27 shows that read
-- failing on every attempt -- both [TARGET-DISCIPLINE] lines said "was fighting
-- 'nothing'" -- and [COMBAT-ACTION] shows the sibling call
-- SetTargetAndNextAction failing 29 times out of 29 with "attempt to call a
-- TrivialObject value". Neither the field nor the function resolves on
-- BP_AIAction_CombatPal_C in this build, and docs/hook-points.md had already
-- recorded that same negative back in the two-hundred-and-seventeenth pass.
--
-- FindMostHateTarget, by contrast, was read successfully 52 times in the SAME
-- run -- every [ACTION-TRACE] line carries one. The target signal therefore
-- comes from the read that demonstrably works in this build.
--
-- FAIL-SAFE, NOT FAIL-LOUD. The previous version treated "cannot read the
-- target" as "not sanctioned" and cancelled. Since the read never once worked,
-- it cancelled EVERY combat action a companion ever started, including the
-- correct ones -- which is almost certainly the CombatPal -> WildLife ping-pong
-- filling run 27's trace. This version inverts that: an unreadable target means
-- leave the Pal alone. It acts only on a target it has positively identified.
--
-- IT MUST NOT TOUCH THE SUSPENSION SILENTLY. The old version set
-- followSuspendedForCombat[key] = nil directly. That same flag is what tells
-- Trust.lua "this Pal is away fighting, do not call it abandoned", so clearing
-- it silently is what cost Dragon his Petallia: she was mid-fight against his
-- own target and was declared abandoned three seconds later. Cancelling now
-- goes through resume_follow_after_combat, which logs what it did.
local function enforce_target_discipline(pal, key)
    local okTD, errTD = pcall(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return end
        local ac = ctrl:GetAIActionComponent()
        if ac == nil or not ac:IsValid() then return end
        local cur = ac:GetCurrentAction_BP()
        if cur == nil or not cur:IsValid() then return end

        local cname = safe_call(function() return cur:GetFullName() end)
        if cname == nil or tostring(cname):find("Combat") == nil then return end

        local hate = safe_call(function() return ctrl:GetHateSystem() end)
        if hate == nil or not safe_call(function() return hate:IsValid() end) then return end
        local target = safe_call(function() return hate:FindMostHateTarget() end)
        if target == nil or not safe_call(function() return target:IsValid() end) then return end
        local tname = safe_call(function() return target:GetFullName() end)
        if tname == nil then return end
        tname = tostring(tname)

        -- Fighting exactly what the player is fighting. This is the entire
        -- point of the feature; leave it completely alone.
        local enemyName = nil
        if currentPlayerEnemy ~= nil and safe_call(function() return currentPlayerEnemy:IsValid() end) then
            enemyName = safe_call(function() return currentPlayerEnemy:GetFullName() end)
            if enemyName ~= nil and tname == tostring(enemyName) then return end
        end

        local reason = nil
        if tname:find("Player", 1, true) ~= nil then
            -- Matched on "Player" generically at Dragon's own request, so
            -- BP_Player_Female_C, BP_Player_Male_C and every other variant all
            -- read as the trainer rather than only his own pawn class.
            reason = "its own trainer"
        elseif BondingState[tname] == true then
            reason = "another bonded companion"
        elseif playerCombatActive and enemyName ~= nil then
            reason = "a different fight while you were in one"
        end
        if reason == nil then return end

        safe_call(function() ac:TerminateCurrentActionByClass(cur:GetClass()) end)
        if CombatActionClass ~= nil then
            safe_call(function() ac:TerminateCurrentActionByClass(CombatActionClass) end)
        end
        combatActionObjects[key] = nil
        resume_follow_after_combat(key, "target discipline: it was fighting " .. reason)

        targetDisciplineFires = targetDisciplineFires + 1
        local short = tname:match("([^%.]+)$") or tname
        if not offTargetLogged[key or ""] then
            offTargetLogged[key or ""] = true
            Logger.log("[PalBonds/Combat] [TARGET-DISCIPLINE] " .. tostring(key) ..
                " was fighting " .. reason .. " ('" .. short ..
                "') - cancelled, back to follow (first time for this Pal; a running total is reported when the fight ends)")
        end
    end)

    -- Reported rather than swallowed: this function was silently absent for a
    -- whole edit cycle (a span removal took its definition with it) and every
    -- call was a nil global eaten by safe_call. A failure here must be visible.
    if not okTD and not targetDisciplineErrorLogged then
        targetDisciplineErrorLogged = true
        Logger.log("[PalBonds/Combat] [TARGET-DISCIPLINE] FAILED (logged once): " .. tostring(errTD))
    end
end

-- Reported when the combat window closes, so the once-per-Pal line above is
-- never mistaken for "it only happened twice" the way run 27's was.
function Combat.ReportTargetDisciplineFires()
    local n = targetDisciplineFires
    targetDisciplineFires = 0
    return n
end

-- Drops the follow action so the Pal's own AI can take the slot.
local function suspend_follow_for_combat(pal, key)
    if key == nil then return end
    if followSuspendedForCombat[key] ~= nil then return end
    followSuspendedForCombat[key] = os.clock()
    safe_call(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return end
        local ac = ctrl:GetAIActionComponent()
        if ac == nil or not ac:IsValid() then return end
        local followCls = get_follow_action_class()
        if followCls ~= nil then
            ac:TerminateCurrentActionByClass(followCls)
        end
    end)
    followActionObjects[key] = nil

    Logger.log("[PalBonds/Combat] [COMBAT-FREE] " .. tostring(key) ..
        " — follow action dropped for the fight; it is free to choose combat now")
end

resume_follow_after_combat = function(key, why)
    if followSuspendedForCombat[key] == nil then return end
    followSuspendedForCombat[key] = nil
    Logger.log("[PalBonds/Combat] [COMBAT-FREE] " .. tostring(key) ..
        " — fight over (" .. tostring(why) .. "), follow will be rebuilt and it returns to the player")
end

-- Queried by Trust.lua so a Pal that legitimately chased an enemy is not
-- declared abandoned for it.
function Combat.IsSuspendedForCombat(pal)
    local key = suspension_key(pal)
    return key ~= nil and followSuspendedForCombat[key] ~= nil
end

-- Added in the three-hundred-and-twenty-third pass, and the reason it exists is
-- a bug that cost Dragon a Pal.
--
-- Trust.lua asks "is this Pal away fighting?" before it declares a distant
-- follower abandoned, and it used to ask by reading the suspension flag alone.
-- In run 27 target discipline was silently clearing that flag on every tick, so
-- Trust got "no" for a Petallia who was, at that exact second, three lines
-- earlier in the same log, running BP_AIAction_CombatPal_C against Dragon's own
-- target. She was declared abandoned and lost.
--
-- Bookkeeping can go wrong. What the Pal is actually DOING cannot, so this asks
-- the Pal directly and treats the flag as only one of three ways to say yes:
--   * the mod has the follow action suspended for a fight, or
--   * the Pal is running a combat action right now, or
--   * the Pal has a live hate target (it is fixated on something).
-- Any one of those means "do not call this abandoning the player".
--
-- 2026-09-15: also returns WHY (a short reason) and, for a hate target, the
-- target itself, so the [LEASH-SPY] diagnostic in Trust.lua can say what kept a
-- distant follower from being declared abandoned. The first return value is
-- unchanged, so every existing caller behaves exactly as before.
function Combat.IsBusyFighting(pal)
    if pal == nil then return false, "no pal" end
    if Combat.IsSuspendedForCombat(pal) then return true, "follow suspended for a fight" end
    local ok, busy, why, with = pcall(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return false, "no controller" end

        local ac = ctrl:GetAIActionComponent()
        if ac ~= nil and ac:IsValid() then
            local cur = ac:GetCurrentAction_BP()
            if cur ~= nil and cur:IsValid() then
                local cname = safe_call(function() return cur:GetFullName() end)
                if cname ~= nil and tostring(cname):find("Combat") ~= nil then return true, "combat action", cur end
            end
        end

        local hate = ctrl:GetHateSystem()
        if hate ~= nil and hate:IsValid() then
            local target = safe_call(function() return hate:FindMostHateTarget() end)
            if target ~= nil and safe_call(function() return target:IsValid() end) then return true, "hate target", target end
        end
        return false, "not fighting"
    end)
    if not ok then return false, "check failed: " .. tostring(busy) end
    return busy == true, why, with
end

function Combat.OnPlayerCombatTarget(enemyActor, playerActor)
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

    -- ===============================================================
    -- DEBOUNCE (two-hundred-and-ninety-ninth pass, 2026-09-11)
    -- ===============================================================
    -- The early-out above handles "no followers". This handles the other half of
    -- the same warning Dragón gave in the pass above: a run-per-event function
    -- doing redundant work.
    --
    -- This is called once per damage EVENT, and a multi-hit DPS attack is many
    -- events against ONE enemy — his log shows a single throttled line covering
    -- 16 hits in a two-second window. Each of those used to run the whole loop
    -- below for every follower: a companion-preset write plus GetHateSystem,
    -- ChangeHate and SetTargetAndNextAction. Sixteen times, times the number of
    -- followers, all to say the same thing about the same enemy.
    --
    -- That is the hitch he reported, and it is why throttling the LOG line last
    -- pass did not help: the logging was never the expensive part. He was ready
    -- to accept it ("there arent that many attacks that cause multiple hits like
    -- that so its not common") — but the work is redundant by construction, so
    -- there is nothing to accept.
    --
    -- Hate does not need re-applying while it is already set; only
    -- release_assist_hate takes it back, when the combat window closes. A NEW
    -- enemy re-pushes immediately, because that is a real change of target.
    local nowTarget = os.clock()
    if enemyName ~= nil and enemyName == lastCombatTargetName
        and (nowTarget - lastCombatTargetAt) < COMBAT_TARGET_REPUSH_INTERVAL then
        return
    end
    lastCombatTargetName = enemyName
    lastCombatTargetAt = nowTarget

    -- ===============================================================
    -- A COMPANION IS NEVER THE PLAYER'S ENEMY, NOT EVEN FOR AN INSTANT
    -- (three-hundred-and-twenty-fourth pass, 2026-09-12)
    -- ===============================================================
    -- MOVED ABOVE the currentPlayerEnemy assignment, and that ordering is the
    -- whole fix. Run 28 caught it at the exact moment Dragón ran out of arrows
    -- and had to improvise in melee:
    --
    --   12:24:17  [HATE-ASSIST] player's current enemy = BP_BerryGoat_C_2147418096
    --   12:24:18  [HATE-ASSIST] the damaged actor is one of our own companions
    --   12:24:19  the player hit a bonding Pal — trust 81 -> 18
    --   12:24:19  [TARGET-DISCIPLINE] ... was fighting a different fight while
    --             you were in one ('BP_BerryGoat_C_2147418096')
    --
    -- Both companions were cancelled for fighting the very goat the player was
    -- fighting. The refusal branch below already existed and correctly declined
    -- to aim the group at a companion -- but it sat one line too late, so the
    -- assignment had already overwritten currentPlayerEnemy with the companion
    -- the player accidentally hit. Target discipline then compared every real
    -- fight against "Petallia" and cancelled all of them.
    --
    -- So one stray hit on your own Pal disarmed combat assist entirely until
    -- the next clean hit on a real enemy landed. That is the "cancelled 7
    -- off-target attacks" burst in run 28, and almost none of those seven were
    -- actually off-target.
    if enemyName ~= nil and BondingState[enemyName] then
        Logger.log("[PalBonds/Combat] [HATE-ASSIST] the damaged actor is one of our own companions — refusing to aim the others at it, and LEAVING the player's real target untouched (logged so friendly fire is visible rather than silent)")
        return
    end

    currentPlayerEnemy = enemyActor

    -- The player's fight takes over from any companion's own self-defence: from
    -- here every companion is pointed at the player's enemy, and the window
    -- close returns them all to follow.
    selfDefenceEnemy = {}
    selfDefenceLastHitAt = {}

    -- An enemy further from the player than the recall distance cannot be
    -- fought: a companion would be recalled on the way there. Companions keep
    -- following instead of being sent (and recalled, and sent again). The
    -- combat window still opens, so they still engage anything close.
    local reachDist = actor_distance(enemyActor, playerActor)
    local enemyOutOfReach = reachDist ~= nil and reachDist > COMBAT_RECALL_DISTANCE
    if enemyOutOfReach and outOfReachLoggedFor ~= enemyName then
        outOfReachLoggedFor = enemyName
        Logger.log(string.format(
            "[PalBonds/Combat] [HATE-ASSIST] your target is %.0f units from you, past the %.0f companions may go — they keep following instead of chasing it (logged once per target)",
            reachDist, COMBAT_RECALL_DISTANCE))
    end

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
    --
    -- The guard itself now lives above, before currentPlayerEnemy is written.
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
                        if not playerCombatActive then
                            local okP, Personality = pcall(require, "Personality")
                            if okP and Personality and Personality.ApplyCompanionPreset then
                                local palId = Personality.GetOrInitState and Personality.GetOrInitState(pal)
                                if palId then
                                    Personality.ApplyCompanionPreset(palId, pal, ENABLE_COMBAT_ASSIST, true)
                                end
                            end
                        end
                        -- Three-hundredth pass: actually give this companion a
                        -- fight to run. Hate below tells it WHO; without this
                        -- there was never anything telling it to FIGHT.
                        -- Drop follow so its own AI can pick a fight. Without
                        -- this the follow action holds the slot and, as the
                        -- action trace proved, the Pal never reaches combat.
                        -- Not for an unreachable enemy, and not for a Pal the
                        -- recall is marching home (see COMBAT_RECALL_DISTANCE).
                        if enemyOutOfReach or recallActive[key] then return end
                        safe_call(function() suspend_follow_for_combat(pal, key) end)

                        safe_call(function() try_install_combat_action(pal, key, enemyActor) end)

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

    -- Named rather than anonymous so the "a companion is still fighting" branch
    -- below can re-arm the SAME check instead of needing a separate entry point.
    local close_combat_window
    close_combat_window = function()
            if myGen ~= combatWindowGeneration then return end

            -- ===========================================================
            -- DO NOT CLOSE THE WINDOW WHILE A COMPANION IS STILL FIGHTING
            -- (three-hundred-and-fifth pass, 2026-09-11)
            -- ===========================================================
            -- This timer measures the PLAYER's fight: it fires COMBAT_WINDOW_MS
            -- after the last damage event involving him. But what it then does
            -- -- release_assist_hate() -- takes the target away from every
            -- companion, and a companion that is still mid-fight loses the very
            -- thing keeping it in the fight. pal_has_own_fight then reads false
            -- on the next follow tick, and follow is reinstalled straight over
            -- the swing.
            --
            -- This is the cause of the species split Dragón could not explain:
            -- "both petallias failed to enter in combat, despite being different
            -- petallias" while the Ribbunies fought fine. It is not species AI.
            -- It is a RACE. A Ribbuny is quick and lands its hits inside the
            -- twelve-second window; a Petallia is slower to close the distance,
            -- and by the time it arrives the window has expired and its target
            -- has been revoked out from under it. The correlation in his log is
            -- exact -- 23:06:21 release, 23:06:23 rebuild; 23:07:39 release,
            -- 23:07:40 rebuild -- and the last Caprity fight worked because he
            -- kept swinging, which kept renewing the window.
            --
            -- So the window now also stays open while any companion is still
            -- engaged with something alive. The pass-234b reason for releasing
            -- hate at all (companions hunting forever after a fight) is
            -- untouched: this only defers the release until the fighting has
            -- actually stopped, and each deferral is re-checked on the same
            -- timer rather than looping.
            -- BISECT (three-hundred-and-ninth pass): OFF, back to run 9's
            -- behaviour. Set true to re-test holding the window open.
            -- Back ON (three-hundred-and-twelfth pass, 2026-09-12) — next step of
            -- the bisect, and run 15 says it is the right one. The interruptions
            -- Dragón still sees land ~17s after the hate push: the window closes,
            -- release_assist_hate revokes the target, the protection gate then
            -- reads "not fighting", and follow is rebuilt straight over the Pal.
            local HOLD_WINDOW_WHILE_FIGHTING = true
            local someoneStillFighting = false
            if HOLD_WINDOW_WHILE_FIGHTING then
                for key, isFollowing in pairs(BondingState) do
                    if isFollowing then
                        local pal = FollowerActors[key]
                        if pal ~= nil and safe_call(function() return pal:IsValid() end) then
                            if pal_has_own_fight(pal) == true then
                                someoneStillFighting = true
                                break
                            end
                        end
                    end
                end
            end
            if someoneStillFighting and HOLD_WINDOW_WHILE_FIGHTING then
                if not combatWindowExtendLogged then
                    combatWindowExtendLogged = true
                    Logger.log("[PalBonds/Combat] [HATE-ASSIST] the player's fight is over but a companion is still engaged — holding the window open rather than pulling its target away mid-swing")
                end
                pcall(function()
                    ExecuteInGameThreadWithDelay(COMBAT_WINDOW_MS, close_combat_window)
                end)
                return
            end
            combatWindowExtendLogged = false
            playerCombatActive = false
            Logger.log("[PalBonds/Combat] [HATE-ASSIST] player combat window closed — companions return to not starting fights")
            local followInstalls, combatInstalls = Combat.ReportInstallCounts()
            if followInstalls > 0 or combatInstalls > 0 then
                Logger.log("[PalBonds/Combat] [INSTALLS] that fight cost " .. followInstalls ..
                    " follow-action rebuild(s) and " .. combatInstalls ..
                    " combat-action install(s) — this is the churn that shows up as lag")
            end
            local tdFires = Combat.ReportTargetDisciplineFires()
            if tdFires > 0 then
                Logger.log("[PalBonds/Combat] [TARGET-DISCIPLINE] cancelled " .. tdFires ..
                    " off-target companion attack(s) during that fight")
            end
            -- Reported here rather than in Trust so both numbers land together:
            -- how often companions clipped each other, and how often that
            -- turned into a fight this had to break up.
            safe_call(function()
                local okT, TrustMod = pcall(require, "Trust")
                if not (okT and TrustMod and TrustMod.ReportFriendlyFire) then return end
                local ff = TrustMod.ReportFriendlyFire()
                if ff > 0 then
                    Logger.log("[PalBonds/Trust] [FRIENDLY-FIRE] " .. ff ..
                        " companion-on-companion hit(s) during that fight")
                end
            end)

            -- Three-hundredth pass: drop our combat-action handles so the follow
            -- rebuild is allowed to run again. The action object itself is left
            -- to the game; TerminateCurrentActionByClass on a finished fight is
            -- not something this project has any evidence about, and following
            -- is restored either way because HasAction will read false.
            for ckey in pairs(combatActionObjects) do
                clear_combat_action(ckey)
            end

            -- The fight is over: give every companion its follow action back so
            -- it returns to the player, which is the half Dragón asked for --
            -- "the only thing is that once its over, they have to return to my
            -- side".
            currentPlayerEnemy = nil
            offTargetLogged = {}
            for skey in pairs(followSuspendedForCombat) do
                resume_follow_after_combat(skey, "player combat window closed")
            end
            -- DISABLED (pass 322): release_assist_hate subtracts hate, which
            -- [HATE-VERIFY] proved is a no-op. It walked every assist target and
            -- every companion pair on each combat-window close for no effect.
            -- release_assist_hate()
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
    end

    -- Arm the first check. Every later re-arm happens inside
    -- close_combat_window itself, when a companion is still fighting.
    pcall(function()
        ExecuteInGameThreadWithDelay(COMBAT_WINDOW_MS, close_combat_window)
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
        OtomoCompositeCache[key] = nil 
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
-- ===================================================================
-- SELF-DEFENCE OUTSIDE A PLAYER FIGHT (2026-09-12, run 34)
-- ===================================================================
-- Dragón: a bonded Caprity took 12 hits from a wild Pal and did nothing until
-- he attacked too. The companion preset's Damaged_* = Battle was working -- the
-- Caprity picked up hate on its attacker -- but pal_has_own_fight counts
-- OtomoFollow as passive, so follow was kept installed, and the only thing that
-- ever freed the slot for a fight was OnPlayerCombatTarget. Our own follow
-- action was holding the Pal out of every fight the player was not part of.
--
-- So a third-party hit on a companion now does, for that one Pal, what a player
-- fight does for all of them: drop follow, install a combat action aimed at the
-- attacker, push hate. Only the Pal that was hit responds -- Dragón's call:
-- "only the pal attacked should respond".
--
-- Called from Trust.lua's damage hook. The fight ends in the follow tick once
-- neither side has hit the other for SELF_DEFENCE_WINDOW_SECONDS, or the
-- attacker is gone; the 25s suspension ceiling and the recall still apply.
function Combat.OnFollowerAttacked(pal, attacker)
    if not (ENABLE_COMBAT_ASSIST and SELF_DEFENCE_ENABLED) then return end
    -- A player fight already frees and aims every companion.
    if playerCombatActive then return end
    if pal == nil or attacker == nil then return end
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil or BondingState[key] ~= true then return end
    if recallActive[key] then return end
    if safe_call(function() return attacker:IsValid() end) ~= true then return end
    local attackerName = safe_call(function() return attacker:GetFullName() end)
    if attackerName == nil or attackerName == key then return end
    -- Another companion clipping it is friendly fire, never a reason to fight.
    if BondingState[attackerName] then return end
    if tostring(attackerName):find("Player", 1, true) ~= nil then return end

    local now = os.clock()
    selfDefenceLastHitAt[key] = now

    -- Debounce: a multi-hit attack is many events against one attacker, and the
    -- engagement is already running.
    local current = selfDefenceEnemy[key]
    if current ~= nil and followSuspendedForCombat[key] ~= nil
        and safe_call(function() return current:GetFullName() end) == attackerName then
        return
    end

    -- The player's own active party Pal hitting it by accident is not an enemy.
    -- POSITIVE check only. Capture.IsAlreadyOwned answers "owned" whenever it
    -- cannot read a Pal -- right for capture, where that is the safe side -- but
    -- here it would leave a companion standing still against any attacker whose
    -- component is unreadable, which is the very bug this function fixes. The
    -- harness caught exactly that on the first run.
    local attackerIsOtomo = safe_call(function()
        local comp = attacker.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return false end
        return comp:IsOtomo()
    end)
    if attackerIsOtomo == true then return end

    selfDefenceEnemy[key] = attacker
    safe_call(function() suspend_follow_for_combat(pal, key) end)
    safe_call(function() try_install_combat_action(pal, key, attacker) end)
    safe_call(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return end
        local hate = ctrl:GetHateSystem()
        if hate == nil or not hate:IsValid() then return end
        hate:ChangeHate(attacker, COMBAT_ASSIST_HATE_AMOUNT)
    end)
    local shortKey = tostring(key):match("([^%.]+)$") or tostring(key)
    local shortAttacker = tostring(attackerName):match("([^%.]+)$") or tostring(attackerName)
    Logger.log("[PalBonds/Combat] [SELF-DEFENCE] " .. shortKey .. " was attacked by " .. shortAttacker ..
        " while you were not fighting — it fights back (only this Pal responds)")
end

-- A companion landing a hit keeps its own self-defence fight alive. Plain table
-- work only: this is called from the damage hook on every companion hit.
function Combat.NoteFollowerHit(attackerKey)
    if attackerKey ~= nil and selfDefenceEnemy[attackerKey] ~= nil then
        selfDefenceLastHitAt[attackerKey] = os.clock()
    end
end

local function end_self_defence(key, why)
    selfDefenceEnemy[key] = nil
    selfDefenceLastHitAt[key] = nil
    clear_combat_action(key)
    resume_follow_after_combat(key, "self-defence over: " .. tostring(why))
end

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
local LEASH_INNER_RADIUS = 400.0   
local LEASH_OUTER_RADIUS = 900.0   
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
-- Two-hundred-and-ninety-ninth pass (2026-09-11): the lateral spread is BACK ON,
-- and this question is now settled from play — do not flatten it again.
--
-- It was tried as a single file for one run at Dragón's request. His verdict:
-- the Pals "do certainly clip among themselves and that not only hinders combat
-- but also interaction, since smaller pals clip through bigger pals and hide
-- underneath". That last part is the one that matters most and was not on the
-- original list of reasons: a small Pal swallowed inside a big one cannot be
-- aimed at, so stacking followers breaks the interaction layer, not just the
-- look of it.
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
-- Two-hundred-and-ninety-eighth pass (2026-09-11): back ON, and the question is
-- settled — do not disable this again.
--
-- It was turned off for one run to see what the game's own default felt like
-- (TargetLocationDistanceForward = 800, the Pal steering to a point eight
-- metres AHEAD of the player, which is what a real Otomo does). Dragón's
-- verdict: "i now remember why we added them, getting close to otomo type
-- follow is impossible". That is the same conclusion the two-hundred-and-
-- thirty-third pass reached, now confirmed twice from live play — a follower
-- that keeps itself ahead of and away from the player cannot be walked up to,
-- and since every interaction here is aim-based, unreachable means un-pettable.
--
-- The forward offset stays. The LATERAL spread is separately off at his
-- request; see FOLLOW_OFFSET_RIGHT_SLOTS.
local USE_FOLLOW_POSITION_OFFSETS = true

local function apply_follow_offsets(action, key)
    if not USE_FOLLOW_POSITION_OFFSETS then return end
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
local AIM_FREEZE_RANGE = 520.0        
local AIM_FREEZE_ANGLE_DEG = 30.0     
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
-- REWRITTEN (three-hundred-and-twenty-third pass, 2026-09-12).
--
-- WHAT WAS HERE AND WHY IT IS GONE. Two mechanisms, enforce_companion_truce and
-- recall_strayed_followers, both steered behaviour by pushing NEGATIVE hate.
-- Run 25's [HATE-VERIFY] probe proved that does nothing in this build: the
-- player was still the most-hated actor immediately after a ChangeHate of
-- -999999. Run 27 then showed the recall failing in the open --
--     11:36:34  Petallia strayed 2005 units - dropping its target
--     11:36:36  Petallia is 3757 units away - losing all trust
-- it "recalled" her and she covered another 1750 units in two seconds. Both
-- were pure cost on the fast loop. The truce is deleted outright; target
-- discipline now handles a companion aiming at a companion, positively, by
-- cancelling the action instead of asking the hate table nicely.
--
-- WHAT REPLACES THE RECALL. Dragon: "the recall too, should be a bit stronger
-- than just forget your hate", and, on the Petallia that was lost, "petallia
-- was faster than me so there was no way for me to catch her during combat".
-- So the recall no longer asks. It:
--     1. cancels whatever the Pal is running, through
--        AllCancelAction_Logic_HardScript_Reaction -- the interrupt this
--        project has confirmed working 5 times out of 5 on real wild Pals,
--     2. hands the follow slot back by ending the combat suspension, so the
--        follow action is rebuilt on the next tick instead of staying dropped,
--     3. issues a direct move order at the player, every recall pass for as
--        long as the Pal is out there, rather than once and hoping.
--
-- DELIBERATELY NOT A TELEPORT. Repositioning the actor is the only lever that
-- cannot be out-voted by the wild AI, and it was offered; Dragon chose the
-- force-march and no warping, so a Pal can still in principle outrun this.
-- Trust.lua's grace period is the safety net for that case, not a warp.
--
-- COST. One pass in five of the 100ms loop (~500ms), only while at least one
-- Pal is following, and the per-Pal work is skipped entirely for any follower
-- inside the recall distance -- which is all of them, almost all of the time.
-- COMBAT_RECALL_DISTANCE and recallActive are declared near the top of the file
-- (with the self-defence state), because the fight assignment reads them too.
local RECALL_EVERY_N_PASSES = 5
local recallCounter = 0
local marchActorMoveLogged = false
local marchActorMoveFailLogged = false
local marchLocMoveLogged = false

-- Cancel, release, and march. Best-effort at every step: a failure in one part
-- still lets the others run, because the alternative is a Pal walking out of
-- the player's life over a single refused native call.
local function force_march_home(pal, key, playerActor, playerLoc)
    local controller = safe_call(function() return pal.Controller end)
    if controller == nil or not safe_call(function() return controller:IsValid() end) then return end

    safe_call(function()
        local ac = controller:GetAIActionComponent()
        if ac ~= nil and ac:IsValid() then
            ac:AllCancelAction_Logic_HardScript_Reaction(pal)
        end
    end)

    -- Give the follow slot back. Without this the Pal stays suspended for the
    -- fight it was just pulled out of and follow is never rebuilt.
    combatActionObjects[key] = nil
    resume_follow_after_combat(key, "recalled - it strayed too far to keep fighting")

    -- INSTRUMENTED (pass 327). These two calls were wrapped in bare pcalls with
    -- no logging at all, and that is why run 29 could not answer the only
    -- question that mattered about the recall. When Flopie walked away while the
    -- player stood still, was the move order REFUSED, or ACCEPTED and then
    -- ignored by her own AI? Those are different bugs with different fixes, and
    -- the log could not tell them apart -- a silent pcall around a native call
    -- is the exact mistake this project keeps paying for.
    --
    -- Logged once per outcome, so it costs nothing after the first of each.
    if playerActor ~= nil and safe_call(function() return playerActor:IsValid() end) then
        local moveOk, moveErr = pcall(function()
            controller:SimpleMoveToActorWithLineTraceGround(playerActor, ECC_VISIBILITY)
        end)
        if moveOk then
            if not marchActorMoveLogged then
                marchActorMoveLogged = true
                Logger.log("[PalBonds/Combat] [RECALL] SimpleMoveToActorWithLineTraceGround was ACCEPTED for the march (logged once). If a Pal still walks away after this, the order is being out-voted by its own AI rather than refused.")
            end
            return
        end
        if not marchActorMoveFailLogged then
            marchActorMoveFailLogged = true
            Logger.log("[PalBonds/Combat] [RECALL] SimpleMoveToActorWithLineTraceGround REFUSED (logged once): " ..
                tostring(moveErr) .. " - falling back to the location order")
        end
    end
    if playerLoc ~= nil then
        local locOk, locErr = pcall(function()
            controller:PalMoveToLocation(playerLoc, FOLLOW_ACCEPTANCE_RADIUS, false, true, true, true, nil, true)
        end)
        if not marchLocMoveLogged then
            marchLocMoveLogged = true
            Logger.log("[PalBonds/Combat] [RECALL] PalMoveToLocation fallback " ..
                (locOk and "was ACCEPTED" or ("FAILED: " .. tostring(locErr))) .. " (logged once)")
        end
    end
end

local function recall_strayed_followers(followers, originLoc, playerActor)
    if originLoc == nil then return end
    local ox = safe_call(function() return originLoc.X end)
    local oy = safe_call(function() return originLoc.Y end)
    local oz = safe_call(function() return originLoc.Z end)
    if ox == nil or oy == nil or oz == nil then return end
    for key, pal in pairs(followers) do
        safe_call(function()
            local loc = pal:K2_GetActorLocation()
            if loc == nil then return end
            local vx = (safe_call(function() return loc.X end) or ox) - ox
            local vy = (safe_call(function() return loc.Y end) or oy) - oy
            local vz = (safe_call(function() return loc.Z end) or oz) - oz
            local dist = math.sqrt(vx * vx + vy * vy + vz * vz)

            local limit = COMBAT_RECALL_DISTANCE
            if not playerCombatActive and selfDefenceEnemy[key] ~= nil and not recallActive[key] then
                limit = self_defence_limit()
            end
            if dist <= limit then
                if recallActive[key] then
                    recallActive[key] = nil
                    Logger.log(string.format(
                        "[PalBonds/Combat] [RECALL] %s is back within %.0f units - the march worked, it is following again",
                        tostring(key), COMBAT_RECALL_DISTANCE))
                end
                return
            end

            force_march_home(pal, key, playerActor, originLoc)

            if not recallActive[key] then
                recallActive[key] = true
                Logger.log(string.format(
                    "[PalBonds/Combat] [RECALL] %s strayed %.0f units (limit %.0f) - action cancelled and marched back to you; repeating every %.0fms until it is home",
                    tostring(key), dist, limit, RECALL_EVERY_N_PASSES * 100.0))
            end
        end)
    end
end

-- 100ms while any Pal is following, 1000ms when none is.
--
-- This rate is empirical, not a guess: the game's Otomo follow action clears
-- the Trainer field faster than the 1.5s follower tick can restore it, which is
-- the entire reason this loop exists. An attempt to relax it to 250ms while
-- Trainer looked stable was reverted in the two-hundred-and-ninety-third pass --
-- several things in this loop are counted in PASSES rather than time, so
-- changing the interval silently rescaled the companion truce, the follower
-- recall and the player-cache refresh along with it, and combat got worse.
--
-- If this ever needs to be relaxed again, convert those pass counters to
-- accumulated milliseconds FIRST. See the comment at nextDelay.
local TRAINER_REASSERT_INTERVAL_MS = 100

-- What the loop costs when nothing is bonding, which is nearly all the time.
local TRAINER_REASSERT_IDLE_INTERVAL_MS = 1000
local TRAINER_REASSERT_MAX_TOTAL = 60000
local TRAINER_REASSERT_LOG_EVERY = 100
followActionObjects = {}
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

    -- Two-hundred-and-ninety-first pass (2026-09-09) -- BOTH MICRO-OPTIMISATIONS
    -- FROM THE PREVIOUS PASS REVERTED. Dragon: "they have difficulty following
    -- again after combat, its like they lose once more the follow order".
    --
    -- Two things were added here and either could cause that:
    --
    --   1. A skip when Trainer already held the player, compared by address.
    --      It assumed the write is a plain field assignment whose only effect
    --      is the stored value. That is an assumption, not a measurement -- the
    --      entire follow mechanism was discovered by finding that REPEATEDLY
    --      writing this field is what keeps the action alive, so the write
    --      plausibly re-latches something beyond the value itself. Skipping it
    --      when "nothing changed" is exactly the case where that would show up.
    --   2. A validation chain (owner -> controller -> AI action component) that
    --      RETURNED without writing when any link could not be resolved. Right
    --      after combat is precisely when those are least likely to resolve, so
    --      it could refuse to re-assert exactly when re-asserting matters most.
    --
    -- Neither was buying much: the real performance wins in that pass were the
    -- removed world scans, not these. Restoring the original unconditional
    -- write, which is the version that demonstrably worked.
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
local INERT_PRIORITY = 13          
local INERT_REPUSH_EVERY_N_PASSES = 20   
local INERT_MAX_PUSHES = 60        
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

-- ===================================================================
-- SHUTDOWN GUARD (two-hundred-and-seventy-second pass, 2026-09-08)
-- ===================================================================
-- Dragon isolated this cleanly, and the isolation is what made it findable:
-- relaunching the game quickly is FINE with no bonded Pal, across several
-- attempts, and crashes reliably if one Pal was following. That is the exact
-- difference between this loop doing nothing and this loop doing real work.
--
-- With no follower the fast loop early-outs on an empty table. With one, it
-- reads actor fields and writes to the follow action TEN TIMES A SECOND -- and
-- it keeps doing that while the game is shutting down, because nothing here has
-- ever known the difference between a live world and one being torn apart.
--
-- IsValid() does not protect against this. During teardown an object can answer
-- "yes" while its memory is already being reclaimed, and safe_call cannot help
-- either: pcall catches Lua errors, not a native access violation. That is the
-- same lesson the screen-projection probe taught earlier in this project.
--
-- The crash lands on the SECOND launch rather than the first because a process
-- that did not shut down cleanly is still holding on when the next one starts.
-- Dragon's log ends on the quit menu opening, which is precisely where our loops
-- should have stopped and did not.
--
-- Two independent detectors, because one of them depends on an API surface I
-- cannot verify from here and the other cannot fail:
--
--   1. A hook on PalPlayerCharacter:EndPlay -- the player leaving the world is
--      the clearest possible "this is over" signal. Registered in a pcall and
--      logged, so if the name is wrong on this build we find out in one line
--      instead of silently losing the guard.
--   2. A poll. Every tenth pass (about a second) the loop checks whether a
--      player character can still be found at all. Once it cannot, twice in a
--      row, the world is gone. No API guessing, and it catches every path --
--      quit, level change, anything.
--
-- Once set, every loop stops RESCHEDULING rather than merely skipping work, so
-- nothing of ours is left queued against a dying world.
local shuttingDown = false
local lastSeenPlayerName = nil
function Combat.IsShuttingDown()
    return shuttingDown
end
function Combat.MarkShuttingDown(why)
    if shuttingDown then return end
    shuttingDown = true
    Logger.log("[PalBonds/Combat] [SHUTDOWN] the world is going away (" .. tostring(why) ..
        ") — stopping every PalBonds loop so nothing of ours touches actors while they are being destroyed")
end
local trainerReassertLoopStarted = false

-- Registered once at Init. Player leaves the world -> everything stops.
-- The EndPlay hook attempt is gone: Dragon's log answered it outright with
-- "no UFunction with the specified name was found", so that detector never
-- existed. Kept as a note rather than a retry, because guessing at a second
-- name would be the same mistake again. The per-pass player check below does
-- the whole job and cannot fail.
-- ===================================================================
-- WORLD CHANGE RESET (two-hundred-and-seventy-fifth pass, 2026-09-08)
-- ===================================================================
-- Dragon designed the experiment that found this, and it is the one that
-- actually isolates the bug: he bonded a Pal in one save, went back to the
-- menu, and loaded a DIFFERENT save -- without ever closing the game -- and it
-- crashed exactly the same way, same 0x338, same stack.
--
-- So it was never the save file (a different world crashed), and never a
-- relaunch race (nothing relaunched). It is the WORLD CHANGE.
--
-- Every table in this mod outlives a world. When a world unloads, every actor
-- in it is destroyed -- Pals, the player, the follow actions we constructed --
-- but followActionObjects, BondingState, FollowerActors and the rest still hold
-- pointers to all of them, and the 100ms loop is still running on its own timer.
-- Load anything afterwards and that loop starts touching objects belonging to a
-- world that no longer exists.
--
-- This also explains the two crashes I never managed to pin down. Quitting
-- unloads the world. Dying destroys the player actor. Same cause, three
-- symptoms, and my earlier "shutdown guard" missed all of them because it
-- watched for the GAME CLOSING when the real event is the world going away --
-- which happens far more often and far earlier.
--
-- UE4SS hooks LoadMap itself (it is in the startup log as
-- UE4SS.LoadMap.LuaModImpl), so the callback exists. Registered in a pcall and
-- logged either way: the EndPlay attempt earlier tonight failed silently until
-- the log told us the UFunction did not exist, and that is not a mistake worth
-- repeating.
function Combat.ResetForNewWorld(why)
    local followers, actions = 0, 0
    for _ in pairs(BondingState) do followers = followers + 1 end
    for _ in pairs(followActionObjects) do actions = actions + 1 end
    BondingState = {}
    FollowerActors = {}
    OtomoCompositeCache = {}
    loggedFollowTickOnce = {}
    followActionObjects = {}
    followActionAttempts = {}
    followActionCapLogged = {}
    trainerReassertCounter = {}
    trainerClearedCount = {}
    stuckZeroStreak = {}
    stuckWarned = {}
    followSlotIndex = {}
    aimFrozen = {}
    recallActive = {}
    frozenPals = {}
    LeashByKey = {}
    lastKnownPlayerActor = nil
    playerCacheAgePasses = 9999
    playerCombatActive = false
    shuttingDown = false
    -- 2026-09-15: the shared player reference belongs to the old world too.
    pcall(function() require("PlayerRef").Invalidate() end)
    Logger.log(string.format(
        "[PalBonds/Combat] [WORLD-RESET] %s — dropped every reference to the old world (%d follower(s), %d follow action(s)). Nothing of ours points at destroyed actors any more.",
        tostring(why), followers, actions
    ))
    safe_call(function()
        local okT, TrustMod = pcall(require, "Trust")
        if okT and TrustMod and TrustMod.ResetForNewWorld then TrustMod.ResetForNewWorld() end
    end)
    safe_call(function()
        local okC, CaptureMod = pcall(require, "Capture")
        if okC and CaptureMod and CaptureMod.ResetForNewWorld then CaptureMod.ResetForNewWorld() end
    end)
end
function Combat.StartShutdownWatch()
    Logger.log("[PalBonds/Combat] [SHUTDOWN] watch active — the player is re-resolved on every pass, so a destroyed player stops all loops immediately")

    -- Two-hundred-and-seventy-sixth pass: the LoadMap callbacks were my second
    -- guessed API name in one night, and Dragon's log answered it the same way
    -- as the first -- "attempt to call a nil value". They do not exist in this
    -- build.
    --
    -- So this time the names come out of UE4SS.dll itself rather than memory.
    -- RegisterLoadMap*Callback is genuinely absent; these two are present:
    --
    --   RegisterEndPlayPreCallback      -- an actor is leaving the world
    --   RegisterInitGameStatePostCallback -- a new world's game state is up
    --
    -- EndPlay fires for every actor, including routine despawns, so acting on
    -- all of them would reset constantly. The filter is the PLAYER: a player
    -- character only ends play when the world is being torn down or when the
    -- player themselves is destroyed -- and both of those are exactly when our
    -- references go stale. That single filter covers quitting, switching saves
    -- AND dying, which is all three symptoms.
    --
    -- InitGameState is the other end: a new world coming up. Belt and braces,
    -- in case a path reaches a new world without the player ever ending play.
    -- No lifecycle callback is used here, and that is deliberate rather than a
    -- third guess. Two attempts failed with "attempt to call a nil value"
    -- (RegisterLoadMap*, then RegisterEndPlay*/RegisterInitGameState*), and
    -- grepping the UE4SS mods that ship with this build settles it: the only
    -- Lua entry points any of them use are RegisterHook, the key binds,
    -- ExecuteInGameThread* and LoopAsync. This build exposes no world-lifecycle
    -- callbacks to Lua at all -- the names I found in the DLL are C++ symbols.
    --
    -- So the world change is DETECTED instead, from the loop already running,
    -- using only calls known to work here. See the player-identity check in the
    -- fast loop.
    Logger.log("[PalBonds/Combat] [WORLD-RESET] armed via player-identity polling (this UE4SS build exposes no world-lifecycle callbacks to Lua)")
end
-- ===================================================================
-- ACTION-CHANGE PROBE (three-hundred-and-thirteenth pass, 2026-09-12)
-- ===================================================================
-- Dragón asked the right methodological question: "with the log you are not
-- getting the clear picture out, probably because you're checking every x
-- second? ... shouldnt it be better to check whenever it changes so that way
-- you can see the last command that settled?"
--
-- He is correct, and it is the reason the last several diagnoses have been
-- guesses. Every decision this file makes is taken from ONE instantaneous read
-- on a 1.5s follow tick, and most of the log lines are latched to fire once per
-- Pal. So a Pal that goes WildLife -> TurnAndEncount -> Combat -> (our follow
-- lands) -> OtomoFollow inside a single tick appears in the log as a single
-- word, and we have repeatedly drawn conclusions about ordering from a sample
-- that cannot show ordering.
--
-- This is DIAGNOSTIC ONLY. It changes no behaviour: it polls each bonded Pal's
-- current action at 200ms and logs ONLY when the name changes, producing the
-- real sequence of what each Pal actually did and what settled last. It is
-- gated off by default and must be turned off before shipping -- it costs one
-- reflection call per follower per 200ms.
local ACTION_CHANGE_PROBE = false   -- stable build 2026-09-12: off; the best diagnostic this project has, flip on to debug
local ACTION_PROBE_INTERVAL_MS = 200

-- Out of combat the probe polled five times a second forever, and each poll
-- does a GetFullName (a full path-string build) plus a hate lookup per bonded
-- Pal -- the cost profile CLAUDE.md already names as the most expensive thing
-- this mod can do. During a fight the fine resolution earns its keep; outside
-- one, a second is plenty. Flopie's decisive WildLife/PointWalk evidence in run
-- 29 was an out-of-combat transition and would still have been caught at this
-- rate.
local ACTION_PROBE_IDLE_INTERVAL_MS = 1000
local lastSeenAction = {}
local actionProbeStarted = false

function Combat.StartActionChangeProbe()
    if not ACTION_CHANGE_PROBE or actionProbeStarted then return end
    actionProbeStarted = true
    Logger.log("[PalBonds/Combat] [ACTION-TRACE] probe armed — logging every action change on bonded Pals at " ..
        ACTION_PROBE_INTERVAL_MS .. "ms (diagnostic only, no behaviour change)")
    local function tick()
        safe_call(function()
            for key, isFollowing in pairs(BondingState) do
                if isFollowing then
                    local pal = FollowerActors[key]
                    if pal ~= nil and safe_call(function() return pal:IsValid() end) then
                        local name = safe_call(function()
                            local ctrl = pal.Controller
                            if ctrl == nil or not ctrl:IsValid() then return nil end
                            local ac = ctrl:GetAIActionComponent()
                            if ac == nil or not ac:IsValid() then return nil end
                            local cur = ac:GetCurrentAction_BP()
                            if cur == nil or not cur:IsValid() then return "<none>" end
                            local full = cur:GetFullName()
                            return tostring(full):match("([^/%.]+)$") or tostring(full)
                        end)
                        name = name or "<unreadable>"
                        if lastSeenAction[key] ~= name then
                            local shortKey = tostring(key):match("([^%.]+)$") or tostring(key)
                            -- Keep the last 4 digits of the instance id: a
                            -- companion PinkRabbit and an ENEMY PinkRabbit
                            -- printed identically before, which made the hate
                            -- target ambiguous in exactly the case that matters.
                            local hateName = safe_call(function()
                                local ctrl = pal.Controller
                                if ctrl == nil or not ctrl:IsValid() then return nil end
                                local hate = ctrl:GetHateSystem()
                                if hate == nil or not hate:IsValid() then return nil end
                                local t = hate:FindMostHateTarget()
                                if t == nil or not t:IsValid() then return "none" end
                                local full = tostring(t:GetFullName()):match("([^%.]+)$") or "?"
                                return full
                            end)
                            Logger.log(string.format(
                                "[PalBonds/Combat] [ACTION-TRACE] %s : %s -> %s   (hate target: %s)",
                                shortKey, tostring(lastSeenAction[key] or "?"), name, tostring(hateName or "?")))
                            lastSeenAction[key] = name
                        end
                    end
                end
            end
        end)
        pcall(function() ExecuteInGameThreadWithDelay(
            playerCombatActive and ACTION_PROBE_INTERVAL_MS or ACTION_PROBE_IDLE_INTERVAL_MS,
            tick) end)
    end
    pcall(function() ExecuteInGameThreadWithDelay(
            playerCombatActive and ACTION_PROBE_INTERVAL_MS or ACTION_PROBE_IDLE_INTERVAL_MS,
            tick) end)
end

function Combat.StartTrainerReassertLoop()
    if trainerReassertLoopStarted or not USE_TRAINER_REASSERT then return end
    trainerReassertLoopStarted = true
    Logger.log(string.format(
        "[PalBonds/Combat] [TRAINER-REASSERT] fast re-assert loop starting at %dms (idle and free until a Pal actually has a follow action)",
        TRAINER_REASSERT_INTERVAL_MS
    ))
    local playerPollCounter = 0
    local playerMissingStreak = 0
    local function step()

        -- Nothing below is safe once the world is being destroyed, and the
        -- reschedule at the bottom is skipped too, so this chain ends here.
        -- Deliberately NOT latching on shuttingDown any more: halting the loop is
        -- what let the stale references survive. The loop keeps running so it can
        -- notice the world change and RELEASE them.

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

            -- Runs BEFORE the follower early-out on purpose: once a reset has
            -- emptied the tables there would be no followers left to trigger the
            -- next check, and the loop would go blind.
            -- Two-hundred-and-eighty-eighth pass (2026-09-09) -- WORLD WATCH
            -- REMOVED, and it was the single most expensive thing in this mod.
            --
            -- What used to be here ran every 5th pass of a 100ms loop -- twice a
            -- second, forever, follower or not, because it sat ABOVE the
            -- early-out below. Each run did find_player(),
            -- which walks the ENTIRE UObject array (Palworld carries hundreds of
            -- thousands of objects), and then GetFullName() on the result, which
            -- builds a full path string. Two array walks and two path builds per
            -- second, from the moment the mod loaded until the game closed.
            --
            -- It existed to notice a world change and drop stale references,
            -- which was the wrong theory about the crash from start to finish.
            -- The real cause was a dispatch parameter outered to the player
            -- character (see construct_worker_menu_parameter in Interaction.lua),
            -- and it is fixed at the source. Nothing here was ever needed.
            -- ===========================================================
            -- Player-target denial, on the FAST loop (pass 319)
            -- ===========================================================
            -- Runs over FollowerActors, not followActionObjects, because a Pal
            -- suspended for combat has no follow action and would otherwise be
            -- invisible here -- which is exactly the Pal that might be swinging
            -- at the player. Every third pass, so roughly 300ms instead of the
            -- 1.5s follow tick, without paying for it ten times a second.
            denyTargetCounter = denyTargetCounter + 1
            if denyTargetCounter % DENY_TARGET_EVERY_N_PASSES == 0 then
                for key, isFollowing in pairs(BondingState) do
                    if isFollowing then
                        local fp = FollowerActors[key]
                        if fp ~= nil and safe_call(function() return fp:IsValid() end) then
                            enforce_target_discipline(fp, key)
                        end
                    end
                end
                didWork = true
            end

            -- Three-hundred-and-twenty-third pass: this used to read only
            -- `next(followActionObjects) == nil`, and that was wrong in exactly
            -- the case the recall exists for.
            --
            -- A Pal suspended for a fight has its follow action DROPPED --
            -- that is what suspension means -- so it is absent from
            -- followActionObjects for the whole fight. With a single follower
            -- out fighting, this early-out fired and the rest of the pass never
            -- ran, which meant the recall could not see the one Pal in the
            -- world that was running away. It only appeared to work in run 27
            -- because a second, unsuspended companion happened to be holding
            -- the table open.
            --
            -- It is now gated on the real precondition -- is anything bonded
            -- at all -- rather than on a table that empties for the duration of
            -- every fight. Caught by the pass-323 harness, which drives this
            -- loop for real rather than calling the recall directly.
            if next(BondingState) == nil then return end

            -- Age check FIRST: an actor destroyed by death or a loading screen
            -- can still answer IsValid() truthfully enough to get us killed on
            -- the next field read, so freshness is the real guard here and
            -- validity is only the second line.
            playerCacheAgePasses = playerCacheAgePasses + 1

            -- Two-hundred-and-seventy-third pass (2026-09-08) — Dragon's theory,
            -- and it unifies both crashes where mine only explained one:
            --
            --   "its probably related to the player's location - remember when i
            --    told you i died from the scarred pal's vengeance and then at
            --    respawn the game crashed?"
            --
            -- Quitting and dying have the same shape: the player's actor is
            -- DESTROYED while a follower still exists. And the single most
            -- dangerous thing this mod does is one line below --
            --     action.Trainer = playerActor
            -- -- writing a pointer INTO a live UObject field, ten times a second.
            --
            -- If that pointer is stale we are not merely reading freed memory,
            -- we are storing it inside an object the engine still uses. That is
            -- a corruption vector rather than a crash-on-read, which is exactly
            -- why it kills the process later and elsewhere instead of here.
            --
            -- The cache made it worse. It was only re-validated every 40 passes,
            -- so a player destroyed by death or by quitting left up to FOUR
            -- SECONDS of writing a dangling pointer into the follow action.
            --
            -- So the player is resolved FRESH on every pass that writes. One
            -- targeted class lookup per 100ms, and only while a follower exists
            -- at all -- far cheaper than the world sweeps this mod already does,
            -- and the correctness is not negotiable at this cost. If the lookup
            -- comes back empty the world is going away and every loop stops.
            -- Two-hundred-and-eighty-eighth pass: this called FindFirstOf --
            -- another full UObject-array walk -- on EVERY pass, ten times a
            -- second, for as long as any Pal was following. That is the lag
            -- Dragon reported as "unplayable when having a follower", and it is
            -- entirely avoidable: lastKnownPlayerActor and
            -- PLAYER_CACHE_MAX_AGE_PASSES were both already here, and the loop
            -- simply never read them. The cache was written and never used.
            --
            -- Now the array is walked at most once every PLAYER_CACHE_MAX_AGE_PASSES
            -- (40 passes, ~4s) instead of ten times a second, and IsValid() --
            -- a cheap direct call, not a scan -- catches a dead actor in between.
            local player = lastKnownPlayerActor
            if player == nil
               or playerCacheAgePasses > PLAYER_CACHE_MAX_AGE_PASSES
               or not safe_call(function() return player:IsValid() end) then
                player = find_player()
                if player ~= nil then
                    lastKnownPlayerActor = player
                    playerCacheAgePasses = 0
                end
            end

            -- Two-hundred-and-seventy-seventh pass (2026-09-08) — RELEASE, not
            -- merely stop. The previous version halted the loop when the player
            -- vanished, and halting changes nothing: the tables still hold Lua
            -- references to the follow actions we constructed, and a Lua
            -- reference KEEPS A UOBJECT ALIVE. Those objects therefore survive
            -- the world unloading, still bound to the action component of a Pal
            -- that no longer exists, and the engine walks them in the next
            -- world. That is a far better fit for a crash inside game code
            -- reached through UE4SS's Blueprint hooks than anything our Lua does
            -- directly, and it explains why the fault is always the same 0x338.
            --
            -- So the world change is detected by the PLAYER'S IDENTITY, and the
            -- response is to drop every reference so the engine can collect the
            -- objects normally:
            --   player gone      -> the world is unloading
            --   player different -> a different world is up
            if player == nil then
                if next(followActionObjects) ~= nil or next(BondingState) ~= nil then
                    Combat.ResetForNewWorld("the player left the world")
                end
                return
            end
            if not safe_call(function() return player:IsValid() end) then
                if next(followActionObjects) ~= nil or next(BondingState) ~= nil then
                    Combat.ResetForNewWorld("the player actor went invalid")
                end
                return
            end

            -- Two-hundred-and-eighty-eighth pass: a GetFullName() on every
            -- pass -- ten full path-string builds a second -- purely to compare
            -- it against the previous one and notice a world change. Same dead
            -- theory as the world watch above, same cost profile, removed for
            -- the same reason. The cache is maintained by the block above now,
            -- so re-assigning it here would only defeat its max-age refresh.

            didWork = true

            -- Read the player's eye/facing ONCE for the whole pass, then reuse
            -- it for every follower.
            local originLoc, forward = read_player_aim(player)

            -- Recall, every fifth pass (~500ms). The companion truce that used
            -- to share this block is gone (pass 323): it pushed negative hate,
            -- which [HATE-VERIFY] proved is a no-op, and target discipline now
            -- handles a companion aiming at a companion by cancelling the
            -- action outright.
            recallCounter = recallCounter + 1
            if recallCounter % RECALL_EVERY_N_PASSES == 0 then
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
                -- Measured from the PLAYER, not from originLoc. originLoc is
                -- the aim camera's position and read_player_aim returns nil
                -- whenever GetControlRotation fails -- which would silently
                -- switch the recall off and let a Pal be lost because of a
                -- camera read. Distance to the player is also simply the right
                -- number for "how far has it strayed".
                if n > 0 then
                    local playerLoc = safe_call(function() return player:K2_GetActorLocation() end)
                        or originLoc
                    safe_call(function() recall_strayed_followers(followers, playerLoc, player) end)
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
        -- Idle when nothing is following; fast while the game is clearing
        -- Trainer; relaxed once it has held. See the constants at the top.
        -- Two-hundred-and-ninety-third pass (2026-09-09) -- THE RELAXED TIER
        -- IS GONE, back to the two speeds that shipped and worked.
        --
        -- Dragon: combat "feels worse than what we achieved back then" -- Pals
        -- struggling to join a fight, drifting off, sometimes not resuming the
        -- follow afterwards. That is this, and the cause is a detail I did not
        -- account for when I made the cadence adaptive: several things in this
        -- loop are counted in PASSES, not in time.
        --
        --     RECALL_EVERY_N_PASSES = 5             -- 500ms at 100ms/pass
        --     INERT_REPUSH_EVERY_N_PASSES   = 20    -- its own comment says
        --                                           -- "the loop runs at 100ms,
        --                                           -- so ~2s"
        --     PLAYER_CACHE_MAX_AGE_PASSES   = 40
        --
        -- Slowing the loop to 250ms silently stretched every one of those by
        -- 2.5x in real time: the companion truce that stops followers targeting
        -- each other, the strayed-follower recall, the cached player refresh.
        -- Combat is exactly where that shows.
        --
        -- Guarding it with playerCombatActive did not save it either -- that
        -- flag tracks the PLAYER's fight. A follower brawling with a wild Pal
        -- while the player has not been hit does not set it, so the assist ran
        -- slow during precisely the fights it exists to help with.
        --
        -- The cadence was never where the performance came from. That was the
        -- removed world scans: a full UObject-array walk twelve times a second,
        -- and the cage probe's ~360 per session. Those all stay removed.
        local nextDelay
        if not didWork then
            nextDelay = TRAINER_REASSERT_IDLE_INTERVAL_MS
        else

            -- Two-hundred-and-ninety-first pass: combat is when the game
            -- destroys our follow action and clears Trainer, and Dragon's
            -- report was specifically about followers struggling to recover
            -- AFTER a fight. Waiting to observe a clear and then speeding up is
            -- reacting one step too late, so the fast rate is held for the
            -- whole fight and for the COMBAT_WINDOW_MS tail after the last hit.
            nextDelay = TRAINER_REASSERT_INTERVAL_MS
        end

        -- Reschedule unconditionally, including after an error above, so one bad
        -- frame cannot silently end the loop for the rest of the session -- but
        -- NOT once the world is going away, which is the whole point of the
        -- guard. Checked again here because the flag can be set mid-pass.
        -- Deliberately NOT latching on shuttingDown any more: halting the loop is
        -- what let the stale references survive. The loop keeps running so it can
        -- notice the world change and RELEASE them.
        pcall(function()
            ExecuteInGameThreadWithDelay(nextDelay, step)
        end)
    end
    pcall(function() ExecuteInGameThreadWithDelay(TRAINER_REASSERT_IDLE_INTERVAL_MS, step) end)
end
local followActionAttempts = {}
local followActionAttemptsSince = {}
local followActionCapLogged = {}
local followActionDisabled = false
local FollowActionClass = nil
get_follow_action_class = function()
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

-- Resolves the concrete wild-Pal combat action class WITHOUT guessing an asset
-- path. UPalAIActionCombatBase is native, so any live instance in the world --
-- every wild Pal fighting anything, which happens constantly -- gives us the
-- real Blueprint subclass through GetClass(). Cached permanently on success.
--
-- The scan is a world walk, so it is cooled down and capped: with no fight
-- anywhere nearby there is simply nothing to harvest yet, and retrying hard
-- would repeat the mistake the cage-VFX probe was removed for.
-- The real wild-Pal combat action, read straight off Dragón's 2026-09-12 trace:
--     BP_FlowerDoll : TurnAndEncount -> CombatPal
--     BP_PinkRabbit : TurnAndEncount -> CombatPal
-- and the sibling LookSideMove resolved to
--     /Game/Pal/Blueprint/Controller/AIAction/Combat/BP_AIAction_LookSideMove.BP_AIAction_LookSideMove_C
-- so the folder convention is known rather than guessed. The runtime harvest is
-- kept as a fallback in case the path differs on another build.
local COMBAT_PAL_CLASS_PATH =
    "/Game/Pal/Blueprint/Controller/AIAction/Combat/BP_AIAction_CombatPal.BP_AIAction_CombatPal_C"

local function get_combat_action_class()
    if CombatActionClass ~= nil then return CombatActionClass end

    -- Direct path first: it works before any Pal has ever fought, which the
    -- harvest cannot.
    local direct = safe_call(function() return StaticFindObject(COMBAT_PAL_CLASS_PATH) end)
    if direct ~= nil and safe_call(function() return direct:IsValid() end) then
        CombatActionClass = direct
        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] combat action class resolved directly: " .. COMBAT_PAL_CLASS_PATH)
        return CombatActionClass
    end

    local now = os.clock()
    if (now - lastCombatClassScanAt) < COMBAT_CLASS_SCAN_COOLDOWN then return nil end
    lastCombatClassScanAt = now
    combatClassScanCount = combatClassScanCount + 1
    local instances = safe_call(function() return FindAllOf("PalAIActionCombatBase") end)
    if instances == nil then
        if combatClassScanCount == 1 then
            Logger.log("[PalBonds/Combat] [COMBAT-ACTION] no live combat action anywhere yet — cannot harvest the class; will retry when the player is next in a fight")
        end
        return nil
    end
    for _, inst in ipairs(instances) do
        if safe_call(function() return inst:IsValid() end) then
            local cls = safe_call(function() return inst:GetClass() end)
            if cls ~= nil then
                CombatActionClass = cls
                Logger.log("[PalBonds/Combat] [COMBAT-ACTION] harvested the real combat action class from a live instance: " ..
                    tostring(safe_call(function() return cls:GetFullName() end)))
                return CombatActionClass
            end
        end
    end
    return nil
end

-- True when this Pal is running a combat action we installed. Used to keep the
-- follow rebuild from evicting an active fight -- the mirror image of the bug
-- where combat evicts follow.
combat_action_is_live = function(key, pal)
    local action = combatActionObjects[key]
    if action == nil then return false end
    if not safe_call(function() return action:IsValid() end) then
        combatActionObjects[key] = nil
        return false
    end
    if CombatActionClass == nil or pal == nil then return true end
    local controller = safe_call(function() return pal.Controller end)
    local actionComp = controller and safe_call(function() return controller:GetAIActionComponent() end)
    if not (actionComp and safe_call(function() return actionComp:IsValid() end)) then return true end
    local installed = safe_call(function()
        return actionComp:HasAction(CombatActionClass, FOLLOW_ACTION_PRIORITY)
    end)
    if installed == false then
        -- The fight ended and the game took the slot back. Drop our handle so
        -- following can be rebuilt normally.
        combatActionObjects[key] = nil
        return false
    end
    return true
end

clear_combat_action = function(key)
    if combatActionObjects[key] == nil then return end
    combatActionObjects[key] = nil
    Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) .. " — released its combat action; following will be rebuilt")
end

try_install_combat_action = function(pal, key, enemyActor)
    if not ENABLE_COMBAT_ACTION or combatActionDisabled then return false end
    if pal == nil or key == nil or enemyActor == nil then return false end

    -- Already fighting: just re-point it. Cheap, and it means a companion
    -- switches targets with the player instead of finishing its first fight.
    if combat_action_is_live(key, pal) then
        local action = combatActionObjects[key]
        safe_call(function() action.TargetActor = enemyActor end)
        safe_call(function() action:SetTargetAndNextAction(enemyActor) end)
        return true
    end

    local cls = get_combat_action_class()
    if cls == nil then return false end

    local nowPal = os.clock()
    if combatActionAttemptsSince[key] == nil
        or (nowPal - combatActionAttemptsSince[key]) > PER_PAL_INSTALL_WINDOW_SECONDS then
        combatActionAttemptsSince[key] = nowPal
        combatActionAttempts[key] = 0
    end
    local attempts = combatActionAttempts[key] or 0
    if attempts >= COMBAT_ACTION_MAX_PER_PAL then return false end
    combatActionAttempts[key] = attempts + 1

    local controller = safe_call(function() return pal.Controller end)
    if not (controller and safe_call(function() return controller:IsValid() end)) then return false end
    local actionComp = safe_call(function() return controller:GetAIActionComponent() end)
    if not (actionComp and safe_call(function() return actionComp:IsValid() end)) then return false end

    -- Free the slot. The follow action holds it, and this is the same eviction
    -- the game itself performs on us whenever a Pal decides to fight.
    safe_call(function()
        local followCls = get_follow_action_class()
        if followCls ~= nil then actionComp:TerminateCurrentActionByClass(followCls) end
    end)
    followActionObjects[key] = nil

    local action = safe_call(function() return StaticConstructObject(cls, actionComp) end)
    local actionValid = action ~= nil and safe_call(function() return action:IsValid() end)
    if not actionValid then
        combatActionDisabled = true
        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] construction failed — disabling combat actions; following is unaffected")
        return false
    end

    local setOk, setErr = pcall(function()
        action.SelfActor = pal
        action.TargetActor = enemyActor
    end)
    if not setOk then
        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) ..
            " — SelfActor/TargetActor write FAILED: " .. tostring(setErr))
    end

    local pushOk, pushErr = pcall(function()
        actionComp:SetAction(action, FOLLOW_ACTION_PRIORITY, pal)
    end)
    if not pushOk then
        combatActionDisabled = true
        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] SetAction refused the combat action — disabling; following is unaffected")
        return false
    end

    -- REMOVED (pass 332): the SetTargetAndNextAction call that used to sit
    -- here. It is declared on UPalAIActionCombatBase but does not resolve on
    -- BP_AIAction_CombatPal_C in this build, and it has failed on every single
    -- attempt across three instrumented runs -- 29 of 29 in run 27, 39 of 39 in
    -- run 30 -- always with "attempt to call a TrivialObject value".
    --
    -- That was a native call plus a log line per combat install, paid dozens of
    -- times per fight, for something proven not to exist. Keeping it was exactly
    -- the "the more things we try, the more things that stack" problem. The
    -- negative stays recorded in docs/hook-points.md and in CLAUDE.md's
    -- retired-approaches list; this is the code catching up with what we know.
    --
    -- Combat assist does not depend on it: companions engage through the assist
    -- hate push plus the Discover preset, which is what the traces have always
    -- shown actually working.

    combatActionObjects[key] = action
    local stuck = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
    if stuck ~= true then
        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) ..
            " — the combat action did NOT stick (HasAction=false) after a push that reported success")
    end
    combatInstallCount = combatInstallCount + 1
    return true
end

-- Is this Pal in a fight of its own right now?
--
-- A live hate target is the signal, rather than "is it idle". Idleness would be
-- the obvious test, but ActionIsEmpty() is recorded all over this project as an
-- unreliable busy signal -- it reports empty in the gaps between the steps of a
-- single multi-part action, which is exactly the moment an attack would be
-- stolen. A hate target is per-actor, it is set by the game when the Pal picks a
-- fight (and by our own assist), and it clears when the fight is over, so it
-- gives a clean "fighting / not fighting" edge with no polling.
pal_has_own_fight = function(pal)
    return safe_call(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return false end
        local hate = ctrl:GetHateSystem()
        if hate == nil or not hate:IsValid() then return false end
        local target = hate:FindMostHateTarget()
        if target == nil or not target:IsValid() then return false end
        -- ===========================================================
        -- A HATE TARGET IS NOT A FIGHT (three-hundred-and-eleventh pass,
        -- 2026-09-12)
        -- ===========================================================
        -- The gate used to treat "has a hate target" as "is fighting", and that
        -- is wrong in the one direction that hurts: WE push hate onto every
        -- companion when the player takes a swing, so a Pal that never engaged
        -- at all still reads as fighting, and we then refuse to install follow
        -- on it. It wanders off unattended.
        --
        -- Dragón's run 14 log proves it. The Pals we protected reported their
        -- actual running action as:
        --     6x  BP_AIAction_WildLife_C      (wandering)
        --     1x  BP_AIAction_TurnAndEncount_C
        -- and not one combat action among them. One of those wanderers -- a
        -- Ribbuny -- drifted past the 3000-unit limit and was lost as
        -- "abandoned", with [RECALL] firing nine seconds before the bond broke
        -- and being unable to do anything, because this gate was still refusing
        -- to reinstall follow.
        --
        -- So the action is now consulted too. A Pal running a known idle or
        -- passive action is NOT fighting, no matter what its hate table says,
        -- and follow is reinstalled normally. Anything else still counts as a
        -- fight, so this stays conservative: an unfamiliar action is given the
        -- benefit of the doubt rather than being interrupted.
        local currentAction = safe_call(function()
            local ac = ctrl:GetAIActionComponent()
            if ac == nil or not ac:IsValid() then return nil end
            local cur = ac:GetCurrentAction_BP()
            if cur == nil or not cur:IsValid() then return nil end
            return cur:GetFullName()
        end)
        if currentAction ~= nil then
            for _, passive in ipairs(PASSIVE_ACTION_MARKERS) do
                if tostring(currentAction):find(passive, 1, true) ~= nil then
                    if not passiveDespiteHateLogged[palKeyForLog(pal)] then
                        passiveDespiteHateLogged[palKeyForLog(pal)] = true
                        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] has a hate target but is actually running '" ..
                            passive .. "' — treating it as NOT fighting, so follow is reinstalled and it cannot wander off")
                    end
                    return false
                end
            end
        end

        -- (the target itself is no longer inspected here; enforce_target_discipline owns that)

        -- ===========================================================
        -- A PLAYER IS NEVER A TARGET WORTH PROTECTING
        -- (three-hundred-and-seventeenth pass, 2026-09-12)
        -- ===========================================================
        -- Dragón's own proposal, and it is better than only scrubbing the hate:
        -- "cant you force it too when they target the player? not me
        -- specifically because that would settle it at just a distinct type
        -- 'female_player_C' etc, but 'player' overall... or at least if they set
        -- to attack it, forget about it right the next second".
        --
        -- Clearing hate alone left a window — he had to dodge for about five
        -- seconds while a companion worked through attacks it had already
        -- committed to. Treating a player target as "not a fight" closes it: the
        -- hate goes, AND the follow action is reinstalled immediately, which
        -- pulls the Pal back into heeling instead of leaving it loose.
        --
        -- Matched on "Player" generically rather than on his own pawn class, as
        -- he asked — BP_Player_Female_C, BP_Player_Male_C, PalPlayerCharacter
        -- and any other variant all read as a player. Self-defence against
        -- actual enemies is untouched; only the trainer is off-limits.
        -- REMOVED (three-hundred-and-twenty-second pass, 2026-09-12): the
        -- player-target rule and the companion-duel breakup both lived here.
        -- Both steered targets by SUBTRACTING hate -- clear_player_hate and
        -- ClearMutualHate -- and run 25's [HATE-VERIFY] proved subtraction does
        -- not work: the player was still most-hated immediately after a
        -- -999999 push. The duel breakup had also gone silently dead, firing 0
        -- times against 10 friendly-fire events, because this function stopped
        -- being reached once the deny/suspend paths returned earlier.
        --
        -- enforce_target_discipline replaces both, using the action's own
        -- TargetActor field instead of the hate table. Nothing here needs to
        -- classify the target any more; this function is back to its one job,
        -- answering "is this Pal in a fight at all".
        return true
    end)
end

local function try_real_follow_action(pal, key, playerActor)
    if not USE_REAL_FOLLOW_ACTION or followActionDisabled then return end
    if key == nil or pal == nil or playerActor == nil then return end

    -- Three-hundredth pass: never rebuild follow over a live fight. Without this
    -- the rebuild would evict the combat action within ~1.5s, which is precisely
    -- the bug in reverse -- and it is what the fifteen rebuilds a session in
    -- Dragón's logs were doing to the Pal's own combat attempts all along.
    -- Target control happens in enforce_target_discipline below, not through the
    -- hate table. The per-tick clear_player_hate that used to sit here was
    -- removed in the three-hundred-and-twenty-second pass: it ran for every
    -- follower on every tick and, per [HATE-VERIFY], did nothing at all.

    -- Backstop for the fast-loop denial (pass 319). That loop gives ~300ms
    -- response, but it is one scheduled callback and this project has had
    -- scheduled loops stop silently before; a companion swinging at its own
    -- trainer is the one failure that must not depend on a single mechanism.
    enforce_target_discipline(pal, key)

    -- Suspended for a fight: leave the slot alone entirely. Expires on a timer so
    -- a Pal can never be stranded outside the follow system.
    if followSuspendedForCombat[key] ~= nil then
        if (os.clock() - followSuspendedForCombat[key]) > MAX_COMBAT_SUSPENSION_SECONDS then
            resume_follow_after_combat(key, "suspension timed out after " ..
                MAX_COMBAT_SUSPENSION_SECONDS .. "s")
        else
            -- ===========================================================
            -- ASSIGN THE FIGHT, DO NOT HOPE FOR IT
            -- (three-hundred-and-eighteenth pass, 2026-09-12)
            -- ===========================================================
            -- Dragón's model, and the trace is what forced it: "wouldnt it be
            -- better to just force them to attack whatever the player is
            -- attacking? or if the player is not in combat, set them to follow
            -- instead?"
            --
            -- Everything up to now was PERMISSIVE -- drop the follow action and
            -- hope the Pal's own AI picks a fight. His 2026-09-12 run shows how
            -- that actually goes. Two companions, two fights, and in each one
            -- the Pal that did NOT fight had simply chosen to wander:
            --     Ribbuny  : freed 02:51:54 -> WildLife for 29 seconds
            --     Petallia : freed 02:53:12 -> WildLife -> Warning_PointWalk
            -- Neither was blocked by anything. They were un-leashed and went
            -- sightseeing, which is also why one drifted to the abandon limit.
            --
            -- So the order is issued explicitly and RE-ASSERTED every tick for
            -- as long as the player's fight lasts. Re-assertion matters as much
            -- as the order: pass 231's whole lesson was that these actions clear
            -- the fields we set, and a single push gets overwritten.
            local fightTarget = nil
            if currentPlayerEnemy ~= nil
                and safe_call(function() return currentPlayerEnemy:IsValid() end) then
                fightTarget = currentPlayerEnemy
            elseif not playerCombatActive and selfDefenceEnemy[key] ~= nil then
                -- Its own self-defence fight (Combat.OnFollowerAttacked).
                local sdEnemy = selfDefenceEnemy[key]
                local enemyAlive = safe_call(function() return sdEnemy:IsValid() end) == true
                local quietFor = os.clock() - (selfDefenceLastHitAt[key] or 0)
                if not enemyAlive then
                    end_self_defence(key, "its attacker is gone")
                    return
                elseif quietFor > SELF_DEFENCE_WINDOW_SECONDS then
                    end_self_defence(key, string.format("no hits either way for %.0fs", SELF_DEFENCE_WINDOW_SECONDS))
                    return
                end
                fightTarget = sdEnemy
            end
            if fightTarget ~= nil then
                -- Same rule as the assignment: never keep a Pal on a fight it
                -- can only reach past the recall distance, or while recalled.
                local reach = actor_distance(fightTarget, playerActor)
                local reachLimit = COMBAT_RECALL_DISTANCE
                if not playerCombatActive and fightTarget == selfDefenceEnemy[key] then
                    reachLimit = self_defence_limit()
                end
                if recallActive[key] or (reach ~= nil and reach > reachLimit) then
                    clear_combat_action(key)
                    resume_follow_after_combat(key, recallActive[key] and "it is being recalled"
                        or string.format("its target is out of reach: %.0f from the player, limit %.0f",
                            reach or -1, reachLimit))
                    return
                end
                local runningCombat = false
                local cur = safe_call(function()
                    local ctrl = pal.Controller
                    if ctrl == nil or not ctrl:IsValid() then return nil end
                    local ac = ctrl:GetAIActionComponent()
                    if ac == nil or not ac:IsValid() then return nil end
                    local a = ac:GetCurrentAction_BP()
                    if a == nil or not a:IsValid() then return nil end
                    return tostring(a:GetFullName())
                end)
                if cur ~= nil and cur:find("Combat") ~= nil then
                    runningCombat = true
                end
                if not runningCombat then
                    safe_call(function()
                        try_install_combat_action(pal, key, fightTarget)
                    end)
                end
            end
            return
        end
    end

    if combat_action_is_live(key, pal) then return end

    -- ===============================================================
    -- NEVER INSTALL FOLLOW OVER A FIGHT
    -- (three-hundred-and-third pass, 2026-09-11)
    -- ===============================================================
    -- The previous pass put this check inside the "we still hold a valid action
    -- object" branch below, which only covered the REBUILD path. Dragón's run
    -- caught the hole precisely: his bonded Petallia "actually made the
    -- animation to attack but got interrupted and started to follow once more".
    -- The log shows why --
    --     22:29:37  NOT rebuilding follow, letting it fight   (the gate worked)
    --     22:29:39  about to CONSTRUCT the follow action NOW  (two seconds later)
    -- -- and zero FOLLOW-RESTORE lines all session. The rebuild path did stand
    -- down. But once her own AI destroyed the follow action OBJECT, `existing`
    -- became invalid, the branch holding the gate was skipped entirely, and
    -- execution fell through to the FRESH install path, which built a new follow
    -- action straight over her attack.
    --
    -- This is Dragón's own model, and it is the right one: "wouldnt it be better
    -- to simply let them fight? and push the follow action if they become idle?"
    -- Checked here, at the top, it covers every path into this function --
    -- rebuild, fresh install, first install -- instead of one of them.
    if pal_has_own_fight(pal) == true then

        -- ===========================================================
        -- PROTECTION HAS A CEILING (three-hundred-and-twelfth pass, 2026-09-12)
        -- ===========================================================
        -- Dragón: "the grumpy petallia was not following me - was stuck in the
        -- hate mechanic i think, even after hitting her once to try and make her
        -- react, didnt work".
        --
        -- Both halves of that are explained, and both are ours. A hate target
        -- that never resolves means this gate protects the Pal forever, so
        -- follow is never reinstalled and it simply stands there. And hitting it
        -- does nothing on purpose: the companion preset sets Damaged_Player = 0
        -- (Ignore) so a companion can never turn on its trainer, which also
        -- means the player cannot shake it loose.
        --
        -- A Pal left out of the follow system indefinitely is worse than one
        -- whose fight gets cut short, so protection now expires. On expiry the
        -- hate is cleared as well, because a stale target is what got it stuck.
        local nowProt = os.clock()
        if followProtectedSince[key] == nil then followProtectedSince[key] = nowProt end
        if (nowProt - followProtectedSince[key]) > MAX_FIGHT_PROTECTION_SECONDS then
            Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) ..
                " has been protected as 'fighting' for over " .. MAX_FIGHT_PROTECTION_SECONDS ..
                "s without resolving — clearing its stale hate and taking it back into follow")
            safe_call(function()
                local ctrl = pal.Controller
                if ctrl == nil or not ctrl:IsValid() then return end
                local hate = ctrl:GetHateSystem()
                if hate == nil or not hate:IsValid() then return end
                local t = hate:FindMostHateTarget()
                if t ~= nil and t:IsValid() then hate:ChangeHate(t, -999999.0) end
            end)
            followProtectedSince[key] = nil
            followSuppressedLogged[key] = nil
            -- fall through: follow is installed normally below
        else

        if not followSuppressedLogged[key] then
            followSuppressedLogged[key] = true

            -- Harvest the real combat action class while we have a Pal that is
            -- actually fighting (three-hundred-and-tenth pass). This used to
            -- live in the deeper rebuild branch, which pass 303's gate made
            -- unreachable, so the harvest silently stopped happening.
            --
            -- It matters now more than before: the evidence says companions
            -- RETALIATE fine (Damaged_* = Battle demonstrably works, it is why
            -- they fight each other after clipping) but never INITIATE on the
            -- player's enemy. Installing a combat action aimed at that enemy is
            -- the remaining lever, and it needs this class.
            local cur = safe_call(function()
                local ctrl = pal.Controller
                if ctrl == nil or not ctrl:IsValid() then return nil end
                local ac = ctrl:GetAIActionComponent()
                if ac == nil or not ac:IsValid() then return nil end
                return ac:GetCurrentAction_BP()
            end)
            local curName = cur and safe_call(function() return cur:GetFullName() end)
            Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) ..
                " is in a fight of its own — not installing follow at all until it is over. Current action = " ..
                tostring(curName))
            if CombatActionClass == nil and cur ~= nil then
                local cls = safe_call(function() return cur:GetClass() end)
                local clsName = cls and safe_call(function() return cls:GetFullName() end)
                -- Match the CLASS NAME, not the whole path. The first version
                -- searched the full name for "Combat" and duly "harvested"
                -- BP_AIAction_LookSideMove_C, whose asset merely lives in
                -- .../AIAction/Combat/. Every orienting action lives in that
                -- folder, so the filter matched the folder rather than the role.
                local shortName = tostring(clsName):match("([^/%.]+)$") or ""
                if shortName:find("Combat") ~= nil then
                    CombatActionClass = cls
                    Logger.log("[PalBonds/Combat] [COMBAT-ACTION] harvested the real combat action class from a Pal's own fight: " .. tostring(clsName))
                else
                    Logger.log("[PalBonds/Combat] [COMBAT-ACTION] a fighting Pal is running '" .. shortName ..
                        "' — not a combat action class, not harvesting it")
                end
            end
        end
        return
        end
    end
    followProtectedSince[key] = nil

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
        local controller = safe_call(function() return pal.Controller end)
        local actionComp = controller and safe_call(function() return controller:GetAIActionComponent() end)
        local cls = get_follow_action_class()
        if not (actionComp and safe_call(function() return actionComp:IsValid() end) and cls) then
            return
        end
        local installed = safe_call(function()
            return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY)
        end)
        if installed == true then return end
        if installed == nil then
            Logger.log("[PalBonds/Combat] [FOLLOW-RESTORE] could not inspect the follow-action stack for " .. tostring(key) .. " — keeping the current action object to avoid unsafe rebuild retries")
            return
        end
        -- ===========================================================
        -- DO NOT STAMP ON THE PAL'S OWN FIGHT
        -- (three-hundred-and-second pass, 2026-09-11)
        -- ===========================================================
        -- Dragón, after a run where three bonded Pals were attacked and none
        -- fought back: "im not entirely sure but could be that one of my bonded
        -- pals tried to attack but got forced to follow immediately after". He
        -- was right, and the log shows it plainly. At 22:16:45, in the same
        -- second the hate was pushed, three [FOLLOW-RESTORE] lines fire for the
        -- BerryGoat and the PinkRabbit — their follow actions had just been
        -- destroyed, which is what happens when a Pal's own AI takes the slot to
        -- do something, and we rebuilt follow over the top within ~1.5s.
        --
        -- So the companions were not refusing to fight. They were STARTING to,
        -- and being dragged back to heel before anything could come of it. The
        -- fifteen-rebuilds-a-session pattern in every earlier log was this same
        -- thing, misread as combat being hostile to our follow action when it was
        -- our follow action being hostile to combat.
        --
        -- The gate below only covered fights WE installed, which never happened
        -- because the class harvest failed. This covers the case that actually
        -- occurs: the Pal picked its own fight. A hate target is the signal --
        -- it is per-actor, it is what the assist itself pushes, and it clears
        -- when the fight ends, so following resumes on its own afterwards.
        if pal_has_own_fight(pal) == true then
            if not followSuppressedLogged[key] then
                followSuppressedLogged[key] = true

                -- Harvest the class of whatever displaced us. This is what the
                -- FindAllOf("PalAIActionCombatBase") scan was trying to find and
                -- could not; here it is handed to us by the Pal itself.
                local cur = safe_call(function() return actionComp:GetCurrentAction_BP() end)
                local curName = cur and safe_call(function() return cur:GetFullName() end)
                Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) ..
                    " has its own hate target and something else is running in the follow slot — NOT rebuilding follow, letting it fight. Current action = " ..
                    tostring(curName))
                if CombatActionClass == nil and cur ~= nil then
                    local cls = safe_call(function() return cur:GetClass() end)
                    local clsName = cls and safe_call(function() return cls:GetFullName() end)
                    if clsName ~= nil and tostring(clsName):find("Combat") ~= nil then
                        CombatActionClass = cls
                        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] harvested the real combat action class from the Pal's own fight: " .. tostring(clsName))
                    end
                end
            end
            return
        end
        followSuppressedLogged[key] = nil

        followActionObjects[key] = nil
        Logger.log("[PalBonds/Combat] [FOLLOW-RESTORE] " .. tostring(key) .. " still has a valid Lua action object but it is no longer installed after an AI transition — rebuilding follow")
    end
    local nowPal = os.clock()
    if followActionAttemptsSince[key] == nil
        or (nowPal - followActionAttemptsSince[key]) > PER_PAL_INSTALL_WINDOW_SECONDS then
        followActionAttemptsSince[key] = nowPal
        followActionAttempts[key] = 0
        followActionCapLogged[key] = nil
    end
    local attempts = followActionAttempts[key] or 0
    if attempts >= FOLLOW_ACTION_MAX_PER_PAL then
        if not followActionCapLogged[key] then
            followActionCapLogged[key] = true
            Logger.log(string.format(
                "[PalBonds/Combat] [FOLLOW-ACTION] %s hit the per-Pal install cap (%d in %.0fs) — its follow action keeps being destroyed faster than it can be rebuilt; rebuilds pause until the window rolls over",
                tostring(key), FOLLOW_ACTION_MAX_PER_PAL, PER_PAL_INSTALL_WINDOW_SECONDS
            ))
        end
        return
    end
    if attempts > 0 then
        Logger.log(string.format(
            "[PalBonds/Combat] [FOLLOW-ACTION] %s — its follow action is gone (destroyed by combat, most likely); REBUILDING it, attempt %d of %d this minute",
            tostring(key), attempts + 1, FOLLOW_ACTION_MAX_PER_PAL
        ))
    end
    followActionAttempts[key] = attempts + 1
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
    local action = safe_call(function() return StaticConstructObject(cls, actionComp) end)
    local actionValid = action ~= nil and safe_call(function() return action:IsValid() end)
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
    if not setOk then
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) ..
            " — Trainer/SelfActor write FAILED: " .. tostring(setErr))
        return
    end
    local pushOk, pushErr = pcall(function()
        actionComp:SetAction(action, FOLLOW_ACTION_PRIORITY, pal)
    end)
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
    -- The "current action IMMEDIATELY after push" read that used to sit here is
    -- gone (pass 332). It existed to tell "the push was silently dropped" apart
    -- from "installed but queued below the interaction" -- a question answered
    -- long ago -- and it paid for a GetFullName() path build on every install
    -- purely to print it.
    safe_call(function()
        local present = actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY)
        if present ~= true then
            Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) ..
                " — the follow action did NOT stick (HasAction=false) after a push that reported success")
        end
    end)
    followInstallCount = followInstallCount + 1

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
    -- REMOVED (pass 327): the 6s RECHECK and the 14s LATE re-read.
    --
    -- Both were built to answer one question -- does the follow action stay
    -- installed, and does its Destination ever get filled in -- and that
    -- question has been answered for many passes. What they still did was
    -- schedule TWO extra game-thread callbacks per install, each doing a
    -- GetCurrentAction_BP plus a GetFullName (a full path-string build) plus a
    -- whole dump_follow_action_fields pass. Run 29 installed 40 follow actions,
    -- so that is 80 scheduled callbacks and 79 extra log lines, concentrated in
    -- exactly the busy fighting minutes where Dragón reported the lag.
    --
    -- This is the standing rule about diagnostic hooks outliving their question,
    -- applied to this file.
end
function Combat.StartFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key then
        BondingState[key] = true
        FollowerActors[key] = pal 
    end
    Logger.log("[PalBonds/Combat] " .. tostring(key) .. " marked as following (bonding)")

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
        -- (2026-09-16: the companion preset's player slots = Ignore are also
        -- what makes a new follower drop its hate on the player, within ~3 s
        -- in both spy runs. A ChangeHate-based "forgive" tried here the same
        -- day had no effect and was removed.)
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
        OtomoCompositeCache[key] = nil 
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

        -- The fight bookkeeping has to go too (2026-09-12). Without this a Pal
        -- that joined the party mid-fight stayed in followSuspendedForCombat,
        -- and the combat-window close then tried to "rebuild follow" on what was
        -- by then a real party Otomo (run 33, 17:08:47). The rebuild found no
        -- bonding state and did nothing, but a stale key here is also what
        -- Trust's abandonment check reads, so it must not outlive the bond.
        followSuspendedForCombat[key] = nil
        combatActionObjects[key] = nil
        combatActionAttempts[key] = nil
        combatActionAttemptsSince[key] = nil
        followActionAttemptsSince[key] = nil
        selfDefenceEnemy[key] = nil
        selfDefenceLastHitAt[key] = nil
        followProtectedSince[key] = nil
        followSuppressedLogged[key] = nil
        passiveDespiteHateLogged[key] = nil
        offTargetLogged[key] = nil
        lastSeenAction[key] = nil
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
    -- The territory/leash follow this used to call was retired on evidence in
    -- the two-hundred-and-twenty-fifth pass (inner radius 500 caged followers
    -- so they could not reach an attacker and stopped defending themselves).
    -- Its call site outlived the function it called; removed 2026-09-11.
    resenseTickCounter = resenseTickCounter + 1
    if resenseTickCounter % RESENSE_EVERY_N_TICKS == 0 then
        safe_call(function()
            local okP, Personality = pcall(require, "Personality")
            if not (okP and Personality and Personality.RefreshSightOn) then return end
            Personality.RefreshSightOn(pal)
        end)
    end

    -- The movement-order tail that used to live here (the old nudge, the
    -- orbit, move-to-actor, the territory anchor and the periodic sight
    -- re-check) was removed in the three-hundred-and-twenty-third pass. Both
    -- of its gates, USE_OLD_MOVE_ORDER_NUDGE and USE_MOVE_TO_ACTOR_FOLLOW,
    -- have been false since following moved to the real BP_AIAction_OtomoFollow_C
    -- action, so roughly 220 lines sat behind an early return that always
    -- fired. The two calls still worth having, SimpleMoveToActorWithLineTraceGround
    -- and PalMoveToLocation, were moved into force_march_home, which is the
    -- one place that still needs to push a Pal somewhere.
end
return Combat
