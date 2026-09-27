local Logger = require("Logger")
local Combat = {}
local FOLLOW_ACCEPTANCE_RADIUS = 200.0

local ENABLE_COMBAT_ASSIST = true

local lastMoveOrderResult = nil

local MOVE_RESULT_ALREADY_AT_GOAL = 1

local ORBIT_RADIUS = 180.0
local ORBIT_ACCEPTANCE_RADIUS = 60.0
local ORBIT_STEP_RADIANS = 0.9
local orbitPhase = 0.0

local ECC_VISIBILITY = 3
local loggedActorMoveOnce = false

local COMBAT_ASSIST_HATE_AMOUNT = 1000.0
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local function find_player()
    return require("PlayerRef").Get()
end

local BondingState = {}

local FollowerActors = {}

local loggedRetargetOnce = false

local RESENSE_EVERY_N_TICKS = 3
local resenseTickCounter = 0

local combatActiveBy = {}
local combatWindowGenBy = {}
local lastHateTargetNameBy = {}

local function owner_key_now()
    local ok, P = pcall(require, "PlayerRef")
    if ok and P and P.CurrentOwnerKey then
        local okK, k = pcall(P.CurrentOwnerKey)
        if okK and k ~= nil then return k end
    end
    return "local"
end

local function player_combat_active()
    return combatActiveBy[owner_key_now()] == true
end
local function set_player_combat_active(on)
    combatActiveBy[owner_key_now()] = on and true or nil
end
local function any_player_combat_active()
    return next(combatActiveBy) ~= nil
end

local followerOwnerKey = {}
local followerOwnerCtrl = {}

local function mine(t)
    local k = owner_key_now()
    local out = {}
    for key, v in pairs(t) do
        if (followerOwnerKey[key] or "local") == k then out[key] = v end
    end
    return out
end

local function on_dedicated()
    local ok, Session = pcall(require, "Session")
    if not ok or Session == nil or Session.IsDedicated == nil then return false end
    local okAsk, yes = pcall(Session.IsDedicated)
    return okAsk and yes == true
end

local function for_each_owner(fn, localPlayer)
    local owners = {}
    for key in pairs(BondingState) do
        owners[followerOwnerKey[key] or "local"] = followerOwnerCtrl[key] or false
    end
    for ownerKey, ctrl in pairs(owners) do
        if ownerKey == "local" then
            if localPlayer ~= nil then safe_call(fn, localPlayer) end
        elseif ctrl then
            local pawn = safe_call(function() return ctrl:IsValid() and ctrl.Pawn or nil end)
            if pawn ~= nil and safe_call(function() return pawn:IsValid() end) then
                safe_call(function() require("PlayerRef").WithPlayer(pawn, fn, pawn) end)
            end
        end
    end
end
local COMBAT_WINDOW_MS = 12000

local AI_REQUEST_PRIORITY_LOGIC = 10

local loggedFollowTickOnce = {}
local USE_REAL_FOLLOW_ACTION = true
local FOLLOW_ACTION_CLASS_PATH = "/Game/Pal/Blueprint/Controller/AIAction/Otomo/BP_AIAction_OtomoFollow.BP_AIAction_OtomoFollow_C"
local FOLLOW_ACTION_PRIORITY = 10
local FOLLOW_ACTION_MAX_PER_PAL = 25

local PER_PAL_INSTALL_WINDOW_SECONDS = 60.0

local FOLLOW_ACTION_RECHECK_MS = 6000

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

function Combat.IsPlayerInCombat()
    return player_combat_active()
end
function Combat.HasAnyFollower()
    for _, isFollowing in pairs(BondingState) do
        if isFollowing then return true end
    end
    return false
end

local COMBAT_TARGET_REPUSH_INTERVAL = 1.0
local lastCombatTargetName, lastCombatTargetAt = nil, -99

local ENABLE_COMBAT_ACTION = true
local COMBAT_ACTION_MAX_PER_PAL = 25
local COMBAT_CLASS_SCAN_COOLDOWN = 5.0
local CombatActionClass = nil
local combatActionObjects = {}

local followSuppressedLogged = {}

local combatWindowExtendLogged = false

local PASSIVE_ACTION_MARKERS = {
    "WildLife", "Sleep", "EatDeadBody", "OtomoFollow", "Death", "Rest", "Eat",

    "PairCall", "Petting", "Feed", "Happy",

    "Warning_PointWalk", "PointWalk",
}
local passiveDespiteHateLogged = {}

local offTargetLogged = {}
local targetDisciplineErrorLogged = false

local MAX_FIGHT_PROTECTION_SECONDS = 25.0
local followProtectedSince = {}
local function palKeyForLog(pal)
    return safe_call(function() return pal:GetFullName() end) or "unknown"
end
local combatActionAttempts = {}
local combatActionAttemptsSince = {}

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

local try_install_combat_action
local combat_action_is_live
local clear_combat_action

local pal_has_own_fight
local resume_follow_after_combat

local get_follow_action_class
local followActionObjects

local followSuspendedForCombat = {}

local SELF_DEFENCE_ENABLED = true
local SELF_DEFENCE_WINDOW_SECONDS = COMBAT_WINDOW_MS / 1000
local selfDefenceEnemy = {}
local selfDefenceLastHitAt = {}

local COMBAT_RECALL_DISTANCE = 1800.0

Combat.SELF_DEFENCE_EXTENDED_REACH = false
local SELF_DEFENCE_EXTENDED_DISTANCE = 3000.0
local function self_defence_limit()
    return Combat.SELF_DEFENCE_EXTENDED_REACH and SELF_DEFENCE_EXTENDED_DISTANCE or COMBAT_RECALL_DISTANCE
end
local recallActive = {}

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

local currentPlayerEnemy = nil

local DENY_TARGET_EVERY_N_PASSES = 3
local denyTargetCounter = 0
local MAX_COMBAT_SUSPENSION_SECONDS = 25.0

local function suspension_key(pal)
    return safe_call(function() return pal:GetFullName() end)
end

local targetDisciplineFires = 0

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

        local enemyName = nil
        if currentPlayerEnemy ~= nil and safe_call(function() return currentPlayerEnemy:IsValid() end) then
            enemyName = safe_call(function() return currentPlayerEnemy:GetFullName() end)
            if enemyName ~= nil and tname == tostring(enemyName) then return end
        end

        local reason = nil
        if tname:find("Player", 1, true) ~= nil then

            reason = "its own trainer"
        elseif BondingState[tname] == true then
            reason = "another bonded companion"
        elseif player_combat_active() and enemyName ~= nil then
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

    if not okTD and not targetDisciplineErrorLogged then
        targetDisciplineErrorLogged = true
        Logger.log("[PalBonds/Combat] [TARGET-DISCIPLINE] FAILED (logged once): " .. tostring(errTD))
    end
end

function Combat.ReportTargetDisciplineFires()
    local n = targetDisciplineFires
    targetDisciplineFires = 0
    return n
end

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

function Combat.IsSuspendedForCombat(pal)
    local key = suspension_key(pal)
    return key ~= nil and followSuspendedForCombat[key] ~= nil
end

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

    local anyFollowers = false
    for _, isFollowing in pairs(mine(BondingState)) do
        if isFollowing then anyFollowers = true break end
    end
    if not anyFollowers then return end
    local enemyValid = safe_call(function() return enemyActor:IsValid() end)
    if not enemyValid then return end
    local enemyName = safe_call(function() return enemyActor:GetFullName() end)

    local nowTarget = os.clock()
    if enemyName ~= nil and enemyName == lastCombatTargetName
        and (nowTarget - lastCombatTargetAt) < COMBAT_TARGET_REPUSH_INTERVAL then
        return
    end
    lastCombatTargetName = enemyName
    lastCombatTargetAt = nowTarget

    if enemyName ~= nil and BondingState[enemyName] then
        Logger.log("[PalBonds/Combat] [HATE-ASSIST] the damaged actor is one of our own companions — refusing to aim the others at it, and LEAVING the player's real target untouched (logged so friendly fire is visible rather than silent)")
        return
    end

    currentPlayerEnemy = enemyActor

    selfDefenceEnemy = {}
    selfDefenceLastHitAt = {}

    local reachDist = actor_distance(enemyActor, playerActor)
    local enemyOutOfReach = reachDist ~= nil and reachDist > COMBAT_RECALL_DISTANCE
    if enemyOutOfReach and outOfReachLoggedFor ~= enemyName then
        outOfReachLoggedFor = enemyName
        Logger.log(string.format(
            "[PalBonds/Combat] [HATE-ASSIST] your target is %.0f units from you, past the %.0f companions may go — they keep following instead of chasing it (logged once per target)",
            reachDist, COMBAT_RECALL_DISTANCE))
    end

    for key, isFollowing in pairs(mine(BondingState)) do
        if isFollowing then
            local entry = FollowerActors[key]
            local pal = entry
            local palValid = pal ~= nil and safe_call(function() return pal:IsValid() end)
            if palValid then

                if key ~= enemyName then
                    safe_call(function()
                        local controller = pal.Controller
                        if not (controller and controller:IsValid()) then return end
                        if not player_combat_active() then
                            local okP, Personality = pcall(require, "Personality")
                            if okP and Personality and Personality.ApplyCompanionPreset then
                                local palId = Personality.GetOrInitState and Personality.GetOrInitState(pal)
                                if palId then
                                    Personality.ApplyCompanionPreset(palId, pal, ENABLE_COMBAT_ASSIST, true)
                                end
                            end
                        end

                        if enemyOutOfReach or recallActive[key] then return end
                        safe_call(function() suspend_follow_for_combat(pal, key) end)

                        safe_call(function() try_install_combat_action(pal, key, enemyActor) end)

                        local hate = controller:GetHateSystem()
                        if not (hate and hate:IsValid()) then return end
                        hate:ChangeHate(enemyActor, COMBAT_ASSIST_HATE_AMOUNT)

                        safe_call(function()
                            local actionComp = controller:GetAIActionComponent()
                            if not (actionComp and actionComp:IsValid()) then return end
                            local current = actionComp:GetCurrentAction_BP()
                            if not (current and current:IsValid()) then return end

                            local okSet = pcall(function() current:SetTargetAndNextAction(enemyActor) end)
                            if okSet and not loggedRetargetOnce then
                                loggedRetargetOnce = true
                                Logger.log("[PalBonds/Combat] [RETARGET] SetTargetAndNextAction accepted — companions are being pointed directly at the player's enemy (logged once)")
                            end
                        end)
                        if lastHateTargetNameBy[owner_key_now()] ~= enemyName then
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
    lastHateTargetNameBy[owner_key_now()] = enemyName

    set_player_combat_active(true)
    local ownerKeyForWindow = owner_key_now()
    combatWindowGenBy[ownerKeyForWindow] = (combatWindowGenBy[ownerKeyForWindow] or 0) + 1
    local myGen = combatWindowGenBy[ownerKeyForWindow]

    local close_combat_window
    close_combat_window = function()
            if myGen ~= combatWindowGenBy[ownerKeyForWindow] then return end

            local HOLD_WINDOW_WHILE_FIGHTING = true
            local someoneStillFighting = false
            if HOLD_WINDOW_WHILE_FIGHTING then
                for key, isFollowing in pairs(mine(BondingState)) do
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
            set_player_combat_active(false)
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

            safe_call(function()
                local okT, TrustMod = pcall(require, "Trust")
                if not (okT and TrustMod and TrustMod.ReportFriendlyFire) then return end
                local ff = TrustMod.ReportFriendlyFire()
                if ff > 0 then
                    Logger.log("[PalBonds/Trust] [FRIENDLY-FIRE] " .. ff ..
                        " companion-on-companion hit(s) during that fight")
                end
            end)

            for ckey in pairs(mine(combatActionObjects)) do
                clear_combat_action(ckey)
            end

            currentPlayerEnemy = nil
            offTargetLogged = {}
            for skey in pairs(mine(followSuspendedForCombat)) do
                resume_follow_after_combat(skey, "player combat window closed")
            end

            for key, isFollowing in pairs(mine(BondingState)) do
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

    pcall(function()
        ExecuteInGameThreadWithDelay(COMBAT_WINDOW_MS, close_combat_window)
    end)
end

function Combat.OnFollowerAttacked(pal, attacker)
    if not (ENABLE_COMBAT_ASSIST and SELF_DEFENCE_ENABLED) then return end

    if player_combat_active() then return end
    if pal == nil or attacker == nil then return end
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil or BondingState[key] ~= true then return end
    if recallActive[key] then return end
    if safe_call(function() return attacker:IsValid() end) ~= true then return end
    local attackerName = safe_call(function() return attacker:GetFullName() end)
    if attackerName == nil or attackerName == key then return end

    if BondingState[attackerName] then return end
    if tostring(attackerName):find("Player", 1, true) ~= nil then return end

    local now = os.clock()
    selfDefenceLastHitAt[key] = now

    local current = selfDefenceEnemy[key]
    if current ~= nil and followSuspendedForCombat[key] ~= nil
        and safe_call(function() return current:GetFullName() end) == attackerName then
        return
    end

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

function Combat.Init()
    Logger.log("[PalBonds/Combat] follow logic active")
end

local FOLLOW_ACTION_LATE_DUMP_MS = 14000

local USE_FOLLOW_ACTION_SET_INITIAL_VALUE = true

local USE_TRAINER_REASSERT = true

local FOLLOW_OFFSET_FORWARD = -220.0

local FOLLOW_OFFSET_RIGHT_SLOTS = { 0.0, -260.0, 260.0, -520.0, 520.0 }
local followSlotIndex = {}
local followSlotNext = 0

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

local USE_FOLLOW_POSITION_OFFSETS = true

local function apply_follow_offsets(action, key)
    if not USE_FOLLOW_POSITION_OFFSETS then return end
    pcall(function()
        action.TargetLocationDistanceForward = FOLLOW_OFFSET_FORWARD
        action.TargetLocationDistanceRight = get_follow_right_offset(key)
    end)
end

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

local RECALL_EVERY_N_PASSES = 5
local recallCounter = 0
local marchActorMoveLogged = false
local marchActorMoveFailLogged = false
local marchLocMoveLogged = false

local function force_march_home(pal, key, playerActor, playerLoc)
    local controller = safe_call(function() return pal.Controller end)
    if controller == nil or not safe_call(function() return controller:IsValid() end) then return end

    safe_call(function()
        local ac = controller:GetAIActionComponent()
        if ac ~= nil and ac:IsValid() then
            ac:AllCancelAction_Logic_HardScript_Reaction(pal)
        end
    end)

    combatActionObjects[key] = nil
    resume_follow_after_combat(key, "recalled - it strayed too far to keep fighting")

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
            if not player_combat_active() and selfDefenceEnemy[key] ~= nil and not recallActive[key] then
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

local TRAINER_REASSERT_INTERVAL_MS = 100

local TRAINER_REASSERT_IDLE_INTERVAL_MS = 1000
local TRAINER_REASSERT_MAX_TOTAL = 60000
local TRAINER_REASSERT_LOG_EVERY = 100
followActionObjects = {}
local trainerReassertTotal = 0
local trainerReassertDisabled = false
local trainerReassertFailures = 0
local trainerReassertCounter = {}

local trainerClearedCount = {}
local stuckZeroStreak = {}
local stuckWarned = {}

local lastKnownPlayerActor = nil

local playerCacheAgePasses = 9999
local PLAYER_CACHE_MAX_AGE_PASSES = 40

local WORLD_WATCH_INTERVAL = 10.0
local WORLD_WATCH_AFTER_LOADING_SCREEN = 0.5
local LOADING_SCREEN_TRUST_SECONDS = 60.0
local loadingScreenSeenAt = nil
local worldLoadedAt = nil
local missedPlayerReadings = 0
local WORLD_WATCH_LATCHED_INTERVAL = 2.0
local WORLD_WATCH_QUIT_EXPECTED_INTERVAL = 0.2
local WORLD_CLOSING_CANCEL_SECONDS = 10.0
local lastWorldWatchAt = nil
local worldResetLatched = false
local quitExpectedUntilClock = nil

local function reassert_follow_trainer(pal, key, playerActor)
    if not USE_TRAINER_REASSERT or trainerReassertDisabled then return end
    if key == nil or playerActor == nil then return end
    local action = followActionObjects[key]
    if action == nil then return end
    if not safe_call(function() return action:IsValid() end) then

        followActionObjects[key] = nil
        return
    end
    if trainerReassertTotal >= TRAINER_REASSERT_MAX_TOTAL then
        trainerReassertDisabled = true
        Logger.log("[PalBonds/Combat] [TRAINER-REASSERT] session budget reached (" .. TRAINER_REASSERT_MAX_TOTAL .. ") — no further re-asserts")
        return
    end
    trainerReassertTotal = trainerReassertTotal + 1

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

    local n = (trainerReassertCounter[key] or 0) + 1
    trainerReassertCounter[key] = n
    if n % 10 == 0 and not stuckWarned[key] then
        local d = safe_call(function() return action.Destination end)
        local dxs = d and safe_call(function() return d.X end)
        if dxs ~= nil and dxs == 0.0 then
            stuckZeroStreak[key] = (stuckZeroStreak[key] or 0) + 1

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

local INERT_PRIORITY = 13
local INERT_REPUSH_EVERY_N_PASSES = 20
local INERT_MAX_PUSHES = 60
local frozenPals = {}
local inertCounter = 0

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

local shuttingDown = false
local lastSeenPlayerName = nil

function Combat.IsShuttingDown()
    if shuttingDown then return true end
    local ok, closing = pcall(function() return require("PlayerRef").IsWorldClosing() end)
    return ok and closing == true
end
function Combat.MarkShuttingDown(why)
    if shuttingDown then return end
    shuttingDown = true
    Logger.log("[PalBonds/Combat] [SHUTDOWN] the world is going away (" .. tostring(why) ..
        ") — stopping every PalBonds loop so nothing of ours touches actors while they are being destroyed")
end
local trainerReassertLoopStarted = false

function Combat.ResetForNewWorld(why)
    local followers, actions = 0, 0
    for _ in pairs(BondingState) do followers = followers + 1 end
    for _ in pairs(followActionObjects) do actions = actions + 1 end
    BondingState = {}
    FollowerActors = {}
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
    lastKnownPlayerActor = nil
    playerCacheAgePasses = 9999
    combatActiveBy, combatWindowGenBy, lastHateTargetNameBy = {}, {}, {}
    followerOwnerKey, followerOwnerCtrl = {}, {}
    shuttingDown = false

    pcall(function() require("PlayerRef").Invalidate() end)
    Logger.log(string.format(
        "[PalBonds/Combat] [WORLD-RESET] %s — dropped every reference to the old world (%d follower(s), %d follow action(s)). Nothing of ours points at destroyed actors any more.",
        tostring(why), followers, actions
    ))

    safe_call(function()
        local okS, SessionMod = pcall(require, "Session")
        if okS and SessionMod and SessionMod.Reset then SessionMod.Reset() end
    end)
    safe_call(function()
        local okCl, CombatClaims = pcall(function() return Combat.ForgetClaims end)
        if okCl and CombatClaims then CombatClaims() end
    end)
    safe_call(function()
        local okT, TrustMod = pcall(require, "Trust")
        if okT and TrustMod and TrustMod.ResetForNewWorld then TrustMod.ResetForNewWorld(why) end
    end)
    safe_call(function()
        local okC, CaptureMod = pcall(require, "Capture")
        if okC and CaptureMod and CaptureMod.ResetForNewWorld then CaptureMod.ResetForNewWorld() end
    end)

    safe_call(function()
        local okI, IndicatorMod = pcall(require, "Indicator")
        if okI and IndicatorMod and IndicatorMod.ResetForNewWorld then IndicatorMod.ResetForNewWorld() end
    end)
    safe_call(function()
        local okP, PersonalityMod = pcall(require, "Personality")
        if okP and PersonalityMod and PersonalityMod.ResetForNewWorld then PersonalityMod.ResetForNewWorld() end
    end)
    safe_call(function()
        local okX, InteractionMod = pcall(require, "Interaction")
        if okX and InteractionMod and InteractionMod.ResetForNewWorld then InteractionMod.ResetForNewWorld() end
    end)
    safe_call(function()

        local okH, HostViewMod = pcall(require, "HostView")
        if okH and HostViewMod then
            if HostViewMod.Reset then HostViewMod.Reset() end
            if HostViewMod.ResetSent then HostViewMod.ResetSent() end
        end
    end)
end

local function world_change_watch()

    if on_dedicated() then return end

    local okClosing, closing = pcall(function() return require("PlayerRef").IsWorldClosing() end)
    if okClosing and closing then
        local okProbe, verdict = pcall(function()
            return require("PlayerRef").ProbeForNewPlayer(WORLD_CLOSING_CANCEL_SECONDS)
        end)
        if okProbe and verdict == "new-world" then
            worldResetLatched = false
            quitExpectedUntilClock = nil
            Logger.log("[PalBonds/Combat] [WORLD-RESET] a new world is up — watching from scratch")
        elseif okProbe and verdict == "cancelled" then
            worldResetLatched = false
            quitExpectedUntilClock = nil
            Logger.log("[PalBonds/Combat] [WORLD-RESET] the quit was CANCELLED — the world is still here, and the mod starts this world over (any bond from before the quit prompt is gone)")
        end
        return
    end

    local player = find_player()
    if player ~= nil then
        lastKnownPlayerActor = player
        playerCacheAgePasses = 0
        missedPlayerReadings = 0
    end
    if player == nil then

        local now = os.clock()
        local screenExplainsIt = loadingScreenSeenAt ~= nil
            and (now - loadingScreenSeenAt) <= LOADING_SCREEN_TRUST_SECONDS
        missedPlayerReadings = missedPlayerReadings + 1
        if not (screenExplainsIt or missedPlayerReadings >= 2) then
            return
        end
        if not worldResetLatched then
            worldResetLatched = true
            quitExpectedUntilClock = nil
            Combat.ResetForNewWorld(screenExplainsIt
                and "a loading screen took the world away"
                or "the player left the world")
        end
        return
    end

    if worldResetLatched then
        worldResetLatched = false
        loadingScreenSeenAt = nil
        missedPlayerReadings = 0
        Logger.log("[PalBonds/Combat] [WORLD-RESET] a player is readable again — a new world is up, watching from scratch")

        safe_call(function()
            local okT, TrustMod = pcall(require, "Trust")
            if okT and TrustMod and TrustMod.FlushWorldChangeAbandonments then
                TrustMod.FlushWorldChangeAbandonments()
            end
        end)
    end
end

function Combat.ExpectWorldChange(why)
    quitExpectedUntilClock = os.clock() + 20.0
    pcall(function() require("PlayerRef").ExpectWorldChange(20.0) end)
    Logger.log("[PalBonds/Combat] [WORLD-RESET] " .. tostring(why) ..
        " — watching for the world to go away every pass for the next 20s (nothing dropped yet)")
end

function Combat.NoteLoadingScreen()
    if loadingScreenSeenAt ~= nil and (os.clock() - loadingScreenSeenAt) < 5.0 then return end
    loadingScreenSeenAt = os.clock()
    Logger.log("[PalBonds/Combat] [WORLD-RESET] a loading screen is up — the world is changing")
end

function Combat.NoteWorldLoaded()
    worldLoadedAt = os.clock()
    loadingScreenSeenAt = nil
    missedPlayerReadings = 0
    if not worldResetLatched then
        worldResetLatched = true
        quitExpectedUntilClock = nil
        Combat.ResetForNewWorld("a world finished loading")
    end
end

function Combat.OnQuitConfirmed(why)
    if worldResetLatched then return end
    worldResetLatched = true
    quitExpectedUntilClock = nil
    pcall(function() require("PlayerRef").SetWorldClosing(true) end)
    Combat.ResetForNewWorld(why)
end
function Combat.StartShutdownWatch()
    Logger.log("[PalBonds/Combat] [SHUTDOWN] watch active — the player is re-resolved on every pass, so a destroyed player stops all loops immediately")

    Logger.log("[PalBonds/Combat] [WORLD-RESET] armed via player-identity polling (this UE4SS build exposes no world-lifecycle callbacks to Lua)")

    local QUIT_HOOK_PATHS = {
        { path = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C:ConfirmReturnTitle", release = true },
        { path = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C:OnReturn2Title", release = false },
    }
    local QUIT_HOOK_MAX_ROUNDS = 30
    local QUIT_HOOK_RETRY_MS = 2000
    local quitHooksInstalled = {}
    local function register_quit_hooks(round)
        local remaining = 0
        for _, entry in ipairs(QUIT_HOOK_PATHS) do
            local path, release = entry.path, entry.release
            if not quitHooksInstalled[path] then
                local shortName = path:match("([^:]+)$") or path
                local ok, err = pcall(function()
                    RegisterHook(path, function()
                        if release then
                            Combat.OnQuitConfirmed("the player confirmed leaving the world (" .. shortName .. ")")
                        else
                            Combat.ExpectWorldChange("the player used the ESC menu's " .. shortName)
                        end
                    end)
                end)
                if ok then
                    quitHooksInstalled[path] = true
                    Logger.log("[PalBonds/Combat] [WORLD-RESET] quit hook INSTALLED (round " ..
                        tostring(round) .. "): " .. shortName)
                else
                    remaining = remaining + 1
                    if round >= QUIT_HOOK_MAX_ROUNDS then
                        Logger.log("[PalBonds/Combat] [WORLD-RESET] quit hook gave up on " .. shortName ..
                            " after " .. tostring(round) .. " rounds (" .. tostring(err) ..
                            ") — polling still catches the world change, just up to a second later")
                    end
                end
            end
        end
        if remaining > 0 and round < QUIT_HOOK_MAX_ROUNDS then
            pcall(function()
                ExecuteInGameThreadWithDelay(QUIT_HOOK_RETRY_MS, function()
                    register_quit_hooks(round + 1)
                end)
            end)
        end
    end
    register_quit_hooks(1)

    local LOAD_HOOK_MAX_ROUNDS = 30
    local LOAD_HOOK_RETRY_MS = 2000
    local function register_load_hooks(round)
        local okLoaded = pcall(function()
            RegisterHook("/Script/Pal.PalGameInstance:LoadingFinished", function()
                safe_call(Combat.NoteWorldLoaded)
            end)
        end)
        if okLoaded then
            Logger.log("[PalBonds/Combat] [WORLD-RESET] LoadingFinished hook INSTALLED (round " .. round .. ")")
        end
        local okScreen = pcall(function()
            NotifyOnNewObject("/Script/Pal.PalLoadingScreenWidgetBase", function()
                safe_call(Combat.NoteLoadingScreen)
            end)
        end)
        if okScreen then
            Logger.log("[PalBonds/Combat] [WORLD-RESET] loading-screen watch INSTALLED (round " .. round .. ")")
        end
        if okLoaded and okScreen then return end
        if round >= LOAD_HOOK_MAX_ROUNDS then
            Logger.log("[PalBonds/Combat] [WORLD-RESET] could not install the load events after " ..
                round .. " rounds — the slow player watch is the only detector on this build")
            return
        end
        pcall(function()
            ExecuteInGameThreadWithDelay(LOAD_HOOK_RETRY_MS, function()
                safe_call(function() register_load_hooks(round + 1) end)
            end)
        end)
    end
    register_load_hooks(1)
end

local ACTION_CHANGE_PROBE = false
local ACTION_PROBE_INTERVAL_MS = 200

local ACTION_PROBE_IDLE_INTERVAL_MS = 1000
local lastSeenAction = {}
local actionProbeStarted = false

function Combat.StartActionChangeProbe()
    if not ACTION_CHANGE_PROBE or actionProbeStarted then return end
    actionProbeStarted = true
    Logger.log("[PalBonds/Combat] [ACTION-TRACE] probe armed — logging every action change on bonded Pals at " ..
        ACTION_PROBE_INTERVAL_MS .. "ms (diagnostic only, no behaviour change)")
    local function tick()
        Logger.trace("follower tick (combat)")
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
            any_player_combat_active() and ACTION_PROBE_INTERVAL_MS or ACTION_PROBE_IDLE_INTERVAL_MS,
            tick) end)
    end
    pcall(function() ExecuteInGameThreadWithDelay(
            any_player_combat_active() and ACTION_PROBE_INTERVAL_MS or ACTION_PROBE_IDLE_INTERVAL_MS,
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

        local didWork = false
        safe_call(function()

            if trainerReassertDisabled then return end

            Logger.trace("trainer.step")

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

            denyTargetCounter = denyTargetCounter + 1
            if denyTargetCounter % DENY_TARGET_EVERY_N_PASSES == 0 then

                for_each_owner(function()
                    for key, isFollowing in pairs(mine(BondingState)) do
                        if isFollowing then
                            local fp = FollowerActors[key]
                            if fp ~= nil and safe_call(function() return fp:IsValid() end) then
                                enforce_target_discipline(fp, key)
                            end
                        end
                    end
                end, find_player())
                didWork = true
            end

            local nowWatch = os.clock()
            local watchInterval = WORLD_WATCH_INTERVAL
            if quitExpectedUntilClock ~= nil then
                if nowWatch < quitExpectedUntilClock then
                    watchInterval = WORLD_WATCH_QUIT_EXPECTED_INTERVAL
                else
                    quitExpectedUntilClock = nil
                end
            elseif worldResetLatched then
                watchInterval = WORLD_WATCH_LATCHED_INTERVAL
            elseif loadingScreenSeenAt ~= nil and (nowWatch - loadingScreenSeenAt) <= LOADING_SCREEN_TRUST_SECONDS then
                watchInterval = WORLD_WATCH_AFTER_LOADING_SCREEN
            end
            if lastWorldWatchAt == nil or (nowWatch - lastWorldWatchAt) >= watchInterval then
                lastWorldWatchAt = nowWatch
                world_change_watch()
            end

            if next(BondingState) == nil then return end

            playerCacheAgePasses = playerCacheAgePasses + 1

            local player = nil
            if not on_dedicated() then
            player = lastKnownPlayerActor
            if player == nil
               or playerCacheAgePasses > PLAYER_CACHE_MAX_AGE_PASSES
               or not safe_call(function() return player:IsValid() end) then
                player = find_player()
                if player ~= nil then
                    lastKnownPlayerActor = player
                    playerCacheAgePasses = 0
                end
            end

            if player == nil then
                if not worldResetLatched then
                    worldResetLatched = true
                    Combat.ResetForNewWorld("the player left the world")
                end
                return
            end
            if not safe_call(function() return player:IsValid() end) then
                if not worldResetLatched then
                    worldResetLatched = true
                    Combat.ResetForNewWorld("the player actor went invalid")
                end
                return
            end
            end

            didWork = true

            local function service(player)

            local originLoc, forward = read_player_aim(player)

            recallCounter = recallCounter + 1
            if recallCounter % RECALL_EVERY_N_PASSES == 0 then
                local followers = {}
                local n = 0
                for key, isFollowing in pairs(mine(BondingState)) do
                    if isFollowing then
                        local fp = FollowerActors[key]
                        if fp ~= nil and safe_call(function() return fp:IsValid() end) then
                            followers[key] = fp
                            n = n + 1
                        end
                    end
                end

                if n > 0 then
                    local playerLoc = safe_call(function() return player:K2_GetActorLocation() end)
                        or originLoc
                    safe_call(function() recall_strayed_followers(followers, playerLoc, player) end)
                end
            end
            for key, action in pairs(mine(followActionObjects)) do

                Logger.trace("trainer.follower", key)
                reassert_follow_trainer(nil, key, player)

                local live = followActionObjects[key]
                local palActor = FollowerActors[key]
                if live ~= nil and palActor ~= nil and safe_call(function() return palActor:IsValid() end) then
                    safe_call(function() update_aim_freeze(live, key, palActor, originLoc, forward) end)
                end
            end
            end
            for_each_owner(service, player)
        end)

        local nextDelay
        if not didWork then
            nextDelay = TRAINER_REASSERT_IDLE_INTERVAL_MS
        else

            nextDelay = TRAINER_REASSERT_INTERVAL_MS
        end

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

        FollowActionClass = safe_call(function()
            return StaticFindObject("/Game/Pal/Blueprint/Controller/AIAction/Funnel/BP_AIAction_FunnelFollow.BP_AIAction_FunnelFollow_C")
        end)
        if FollowActionClass ~= nil then
            Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] OtomoFollow class path did not resolve; using the FunnelFollow subclass instead")
        end
    end

    if FollowActionClass ~= nil then
        local resolvedName = safe_call(function() return FollowActionClass:GetFullName() end)
        Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] follow-action class resolved = " .. tostring(resolvedName))
    end
    return FollowActionClass
end

local COMBAT_PAL_CLASS_PATH =
    "/Game/Pal/Blueprint/Controller/AIAction/Combat/BP_AIAction_CombatPal.BP_AIAction_CombatPal_C"

local function get_combat_action_class()
    if CombatActionClass ~= nil then return CombatActionClass end

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

    combatActionObjects[key] = action
    local stuck = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
    if stuck ~= true then
        Logger.log("[PalBonds/Combat] [COMBAT-ACTION] " .. tostring(key) ..
            " — the combat action did NOT stick (HasAction=false) after a push that reported success")
    end
    combatInstallCount = combatInstallCount + 1
    return true
end

pal_has_own_fight = function(pal)
    return safe_call(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return false end
        local hate = ctrl:GetHateSystem()
        if hate == nil or not hate:IsValid() then return false end
        local target = hate:FindMostHateTarget()
        if target == nil or not target:IsValid() then return false end

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

        return true
    end)
end

local function try_real_follow_action(pal, key, playerActor)
    if not USE_REAL_FOLLOW_ACTION or followActionDisabled then return end
    if key == nil or pal == nil or playerActor == nil then return end

    enforce_target_discipline(pal, key)

    if followSuspendedForCombat[key] ~= nil then
        if (os.clock() - followSuspendedForCombat[key]) > MAX_COMBAT_SUSPENSION_SECONDS then
            resume_follow_after_combat(key, "suspension timed out after " ..
                MAX_COMBAT_SUSPENSION_SECONDS .. "s")
        else

            local fightTarget = nil
            if currentPlayerEnemy ~= nil
                and safe_call(function() return currentPlayerEnemy:IsValid() end) then
                fightTarget = currentPlayerEnemy
            elseif not player_combat_active() and selfDefenceEnemy[key] ~= nil then

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

                local reach = actor_distance(fightTarget, playerActor)
                local reachLimit = COMBAT_RECALL_DISTANCE
                if not player_combat_active() and fightTarget == selfDefenceEnemy[key] then
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

    if pal_has_own_fight(pal) == true then

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

        else

        if not followSuppressedLogged[key] then
            followSuppressedLogged[key] = true

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

        if pal_has_own_fight(pal) == true then
            if not followSuppressedLogged[key] then
                followSuppressedLogged[key] = true

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

    safe_call(function()
        local present = actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY)
        if present ~= true then
            Logger.log("[PalBonds/Combat] [FOLLOW-ACTION] " .. tostring(key) ..
                " — the follow action did NOT stick (HasAction=false) after a push that reported success")
        end
    end)
    followInstallCount = followInstallCount + 1

    followActionObjects[key] = action

    apply_follow_offsets(action, key)
    Logger.log(string.format(
        "[PalBonds/Combat] [FOLLOW-POS] %s — follow offsets set: forward=%.0f right=%.0f (negative forward = behind the player, so it stays reachable for petting)",
        tostring(key), FOLLOW_OFFSET_FORWARD, get_follow_right_offset(key)
    ))

    if USE_FOLLOW_ACTION_SET_INITIAL_VALUE then
        Logger.log("[PalBonds/Combat] [FOLLOW-INIT] " .. tostring(key) .. " — about to call SetInitialValue() on the constructed action NOW")
        local initOk, initErr = pcall(function() action:SetInitialValue() end)
        Logger.log("[PalBonds/Combat] [FOLLOW-INIT] " .. tostring(key) .. " — SetInitialValue() returned " ..
            (initOk and "ok" or ("FAILED: " .. tostring(initErr))))
        if initOk then
        end
    end

end

local function we_are_a_guest()
    local ok, Session = pcall(require, "Session")
    if not (ok and Session and Session.IsGuest) then return false end
    local okAsk, guest = pcall(Session.IsGuest)
    return okAsk and guest == true
end

function Combat.StartFollowing(pal)
    if we_are_a_guest() then return end
    local key = safe_call(function() return pal:GetFullName() end)
    if key then
        BondingState[key] = true
        FollowerActors[key] = pal

        followerOwnerKey[key] = owner_key_now()
        local acting = safe_call(function() return require("PlayerRef").Acting() end)
        followerOwnerCtrl[key] = acting and safe_call(function() return acting.Controller end) or nil
    end
    Logger.log("[PalBonds/Combat] " .. tostring(key) .. " marked as following (bonding)")

    safe_call(function()
        local okReq, Personality = pcall(require, "Personality")
        if not (okReq and Personality and Personality.ApplyCompanionPreset) then return end
        local palId = Personality.GetOrInitState and Personality.GetOrInitState(pal)
        if not palId then return end

        Personality.ApplyCompanionPreset(palId, pal, ENABLE_COMBAT_ASSIST)
    end)
end

local function forget_follower_tables(key)
    BondingState[key] = nil
    FollowerActors[key] = nil
    followerOwnerKey[key] = nil
    followerOwnerCtrl[key] = nil
    loggedFollowTickOnce[key] = nil

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

function Combat.ForgetDespawnedFollower(key)
    if key == nil then return end
    forget_follower_tables(key)
    Logger.log("[PalBonds/Combat] " .. tostring(key) .. " despawned while following — its follower references are released")
end

function Combat.StopFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key then

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

            if still ~= false then
                local dying = followActionObjects[key]
                if dying ~= nil and safe_call(function() return dying:IsValid() end) then
                    local okSelf = pcall(function() dying.Trainer = pal end)
                    Logger.log("[PalBonds/Combat] " .. tostring(key) ..
                        " — the follow action could not be removed, so it now follows ITSELF instead of the player (" ..
                        (okSelf and "ok" or "write failed") .. ") — it will stop chasing even if it cannot flee")

                end
            end
        end)
        forget_follower_tables(key)
    end

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

local claimCache = {}
local CLAIM_CACHE_SECONDS = 5.0

local function looks_like_a_player(actor)
    local name = safe_call(function() return actor:GetFullName() end)
    if type(name) ~= "string" then return false end
    return name:find("PalPlayerCharacter") ~= nil or name:find("BP_Player_") ~= nil
end

local function follow_action_on(pal)
    local controller = safe_call(function() return pal.Controller end)
    local actionComp = controller and safe_call(function() return controller:GetAIActionComponent() end)
    local cls = get_follow_action_class()
    if not (actionComp and safe_call(function() return actionComp:IsValid() end) and cls) then return nil, "no action component" end
    local installed = safe_call(function() return actionComp:HasAction(cls, FOLLOW_ACTION_PRIORITY) end)
    if installed ~= true then return nil, "no follow action" end
    for _, getter in ipairs({ "GetCurrentAction_BP", "GetCurrentTopParentAction_BP" }) do
        local action = safe_call(function() return actionComp[getter](actionComp) end)
        if action ~= nil and safe_call(function() return action:IsValid() end) then
            local actionName = safe_call(function() return action:GetFullName() end)
            if type(actionName) == "string" and actionName:find("Follow") ~= nil then
                return action, nil
            end
        end
    end
    return nil, "a follow action is installed but could not be read"
end

local function guest_view()
    local ok, HostView = pcall(require, "HostView")
    if not ok or HostView == nil or not HostView.IsGuest() then return nil end
    return HostView
end

function Combat.ClaimedByAnotherPlayer(pal)
    local view = guest_view()
    if view then return view.ClaimedByOther(pal) end
    if pal == nil or not safe_call(function() return pal:IsValid() end) then return false, "no Pal" end
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil then return false, "no key" end

    if BondingState[key] == true then return false, "ours" end
    local ourAction = followActionObjects[key]
    if ourAction ~= nil and safe_call(function() return ourAction:IsValid() end) then return false, "ours" end

    local now = os.clock()
    local cached = claimCache[key]
    if cached ~= nil and (now - cached.at) < CLAIM_CACHE_SECONDS then
        return cached.claimed, cached.detail
    end

    local claimed, detail = false, nil
    local action, why = follow_action_on(pal)
    if action == nil then
        detail = why
    else
        local trainer = safe_call(function() return action.Trainer end)
        if trainer == nil or not safe_call(function() return trainer:IsValid() end) then
            detail = "a follow action with no readable trainer"
        elseif not looks_like_a_player(trainer) then
            detail = "it follows something that is not a player"
        else
            local me = nil
            local okRef, PlayerRefMod = pcall(require, "PlayerRef")
            if okRef and PlayerRefMod and PlayerRefMod.Get then me = safe_call(PlayerRefMod.Get) end
            local mineAddr = me ~= nil and safe_call(function() return me:GetAddress() end) or nil
            local theirAddr = safe_call(function() return trainer:GetAddress() end)
            if mineAddr ~= nil and theirAddr ~= nil and mineAddr == theirAddr then
                detail = "it follows us"
            elseif me ~= nil and theirAddr == nil then
                detail = "a player trainer we cannot compare (no address)"
            else
                claimed = true
                detail = "it follows " .. tostring(safe_call(function() return trainer:GetFullName() end))
            end
        end
    end

    claimCache[key] = { at = now, claimed = claimed, detail = detail }
    if claimed then
        Logger.log("[PalBonds/Combat] [CLAIMED] " .. tostring(key) .. " belongs to another player — " .. tostring(detail))
    end
    return claimed, detail
end

function Combat.ForgetClaims()
    claimCache = {}
end

function Combat.FollowerOwnerKey(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil or not BondingState[key] then return nil end
    return followerOwnerKey[key] or "local"
end

function Combat.IsFollowing(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    return key ~= nil and BondingState[key] == true
end

function Combat.IssueFollowMoveOrder(pal, playerLoc, playerActor)

    local key = safe_call(function() return pal:GetFullName() end)
    safe_call(function() try_real_follow_action(pal, key, playerActor) end)

    if playerActor ~= nil then
        lastKnownPlayerActor = playerActor
        playerCacheAgePasses = 0
    end
    safe_call(function() reassert_follow_trainer(pal, key, playerActor) end)

    resenseTickCounter = resenseTickCounter + 1
    if resenseTickCounter % RESENSE_EVERY_N_TICKS == 0 then
        safe_call(function()
            local okP, Personality = pcall(require, "Personality")
            if not (okP and Personality and Personality.RefreshSightOn) then return end
            Personality.RefreshSightOn(pal)
        end)
    end

end
return Combat
