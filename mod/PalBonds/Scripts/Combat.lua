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

function Combat.Init()
    Logger.log("[PalBonds/Combat] real (approximate) follow logic active — move-order-based, see file header for what this does and doesn't do yet")
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
end

function Combat.StopFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key then BondingState[key] = nil end
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
function Combat.IssueFollowMoveOrder(pal, playerLoc)
    if not Combat.IsFollowing(pal) then return end
    local controller = safe_call(function() return pal.Controller end)
    if not controller or not controller:IsValid() then return end
    local ok, err = pcall(function()
        controller:PalMoveToLocation(playerLoc, FOLLOW_ACCEPTANCE_RADIUS, false, true, true, true, nil, true)
    end)
    if not ok then
        Logger.log("[PalBonds/Combat] PalMoveToLocation call failed (non-fatal, caught): " .. tostring(err))
    end
end

return Combat
