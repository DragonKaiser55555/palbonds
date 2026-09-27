local Logger = require("Logger")
local Trust = require("Trust")
local Settings = require("Settings")
local Capture = require("Capture")
local Personality = require("Personality")
local UEHelpers = require("UEHelpers")
local Interaction = {}

local PLAY_KEY = Settings.Get("KeyPlay")
local TAGS_KEY = Settings.Get("KeyTags")
local PASSIVE_KEY = Settings.Get("KeyPassiveGain")

local CHEER_EMOTE_INDEX = 0
local play_player_emote

local CAPSULE_COARSE_MARGIN = 600.0

local capsuleReported = {}

local PET_RANGE = 900.0
local PET_MAX_ANGLE_DEG = 25

local FEED_FRIENDSHIP_BASE = Settings.Get("FeedBase")
local FEED_RARITY_BONUS = {
    [0] = Settings.Get("FeedBonusCommon"),
    [1] = Settings.Get("FeedBonusUncommon"),
    [2] = Settings.Get("FeedBonusRare"),
    [3] = Settings.Get("FeedBonusEpic"),
    [4] = Settings.Get("FeedBonusLegendary"),
}

local PET_FRIENDSHIP_GAIN = Settings.Get("Pet")

local KINSHIP_PEACH_LESSER_FRIENDSHIP_BASE = Settings.Get("KinshipPeachLesser")
local KINSHIP_PEACH_FULL_FRIENDSHIP_BASE = Settings.Get("KinshipPeach")
local PLAY_FRIENDSHIP_GAIN = Settings.Get("Play")

local grant_wild_interaction = nil

local ACTION_TYPE_HAPPY = 38

local ACTION_TYPE_PAL_RANDOM_REST = 77

local PLAY_HAPPY_FOLLOWUP_DELAY_MS = 5000
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil, result
end

local function claimed_by_another_player(pal)
    local okC, CombatMod = pcall(require, "Combat")
    if not (okC and CombatMod and CombatMod.ClaimedByAnotherPlayer) then return false end
    local ok, claimed = pcall(CombatMod.ClaimedByAnotherPlayer, pal)
    return ok and claimed == true
end

local playerRefForGate = nil

local function we_are_a_guest()
    local ok, Session = pcall(require, "Session")
    if not (ok and Session and Session.IsGuest) then return false end
    local okAsk, guest = pcall(Session.IsGuest)
    return okAsk and guest == true
end

local function on_dedicated_server()
    local ok, Session = pcall(require, "Session")
    if not (ok and Session and Session.IsDedicated) then return false end
    local okAsk, yes = pcall(Session.IsDedicated)
    return okAsk and yes == true
end

local function guest_blocks_input()
    if not we_are_a_guest() then return false end
    local ok, Session = pcall(require, "Session")
    if ok and Session and Session.GuestInputAllowed then
        local okAsk, allowed = pcall(Session.GuestInputAllowed)
        if okAsk and allowed == true then return false end
    end
    return true
end

local function world_is_closing()
    if playerRefForGate == nil then
        local okReq, M = pcall(require, "PlayerRef")
        if not okReq or M == nil or M.IsWorldClosing == nil then return false end
        playerRefForGate = M
    end
    local ok, closing = pcall(playerRefForGate.IsWorldClosing)
    return ok and closing == true
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

local function rotator_to_forward(rot)
    local yaw = math.rad(rot.Yaw)
    local pitch = math.rad(rot.Pitch)
    return {
        X = math.cos(pitch) * math.cos(yaw),
        Y = math.cos(pitch) * math.sin(yaw),
        Z = math.sin(pitch),
    }
end

local palScanCache = nil
local palScanCacheAge = 0
local PAL_SCAN_CACHE_MAX_AGE = 4

local lastRedirectIdleReason = nil
local function redirect_idle_log(reason, msg)
    if lastRedirectIdleReason == reason then return end
    lastRedirectIdleReason = reason
    Logger.log(msg .. "  (logged once until this changes)")
end
local function find_targeted_pal(originLoc, forwardVec, excludeActor)
    local pals = palScanCache
    if pals == nil or palScanCacheAge >= PAL_SCAN_CACHE_MAX_AGE then
        pals = FindAllOf("PalCharacter")
        palScanCache = pals
        palScanCacheAge = 0
    else
        palScanCacheAge = palScanCacheAge + 1
    end
    if not pals then
        return nil, nil, nil
    end

    local best, bestAngle, bestDist = nil, nil, nil
    for _, pal in ipairs(pals) do
        local validOk, isValid = pcall(function() return pal ~= nil and pal:IsValid() end)
        if validOk and isValid then
            local loc = safe_call(function() return pal:K2_GetActorLocation() end)
            if loc then
                local toTarget = vec_sub(loc, originLoc)
                local dist = vec_length(toTarget)

                local radius, halfHeight = 0.0, 0.0
                if dist <= PET_RANGE + CAPSULE_COARSE_MARGIN then
                    local capsule = safe_call(function() return pal.CapsuleComponent end)
                    if capsule and safe_call(function() return capsule:IsValid() end) then
                        radius = safe_call(function() return capsule:GetScaledCapsuleRadius() end) or 0.0
                        halfHeight = safe_call(function() return capsule:GetScaledCapsuleHalfHeight() end) or 0.0
                    end
                end
                if radius > 0.0 or halfHeight > 0.0 then
                    local centre = { X = loc.X, Y = loc.Y, Z = loc.Z + halfHeight }
                    toTarget = vec_sub(centre, originLoc)
                    dist = vec_length(toTarget)
                end

                if radius > 0.0 or halfHeight > 0.0 or dist <= PET_RANGE then
                    local speciesKey = safe_call(function()
                        local comp = pal.CharacterParameterComponent
                        if comp == nil or not comp:IsValid() then return nil end
                        local p = comp:GetIndividualParameter()
                        if p == nil or not p:IsValid() then return nil end
                        local cid = p:GetCharacterID()
                        return cid and cid:ToString()
                    end)
                    local sk = tostring(speciesKey)
                    if not capsuleReported[sk] then
                        capsuleReported[sk] = true

                        local boundsDesc = "unreadable"
                        safe_call(function()
                            local o, e = pal:GetActorBounds(false)
                            if e ~= nil and e.X ~= nil then
                                boundsDesc = string.format("extent=(%.0f, %.0f, %.0f)", e.X or 0, e.Y or 0, e.Z or 0)
                            elseif o ~= nil then
                                boundsDesc = "returned something, but not a readable extent: " .. tostring(o)
                            end
                        end)
                        Logger.log("[PalBonds/Interaction] [AIM] " .. sk ..
                            " GetActorBounds probe -> " .. boundsDesc)
                        Logger.log(string.format(
                            "[PalBonds/Interaction] [AIM] %s capsule radius=%.0f halfHeight=%.0f | root dist=%.0f -> body dist=%.0f (limit %.0f)%s",
                            sk, radius, halfHeight, vec_length(vec_sub(loc, originLoc)),
                            math.max(0.0, dist - radius), PET_RANGE,
                            (radius == 0.0 and halfHeight == 0.0)
                                and "  <-- ZEROS: capsule unreadable, aiming fell back to the old root-point behaviour"
                                or ""
                        ))
                    end
                end

                local surfaceDist = math.max(0.0, dist - radius)
                if surfaceDist <= PET_RANGE and dist > 1e-3 then
                    local dir = vec_normalize(toTarget)
                    local dot = math.max(-1.0, math.min(1.0, vec_dot(dir, forwardVec)))
                    local angle = math.deg(math.acos(dot))

                    local angularRadius = 0.0
                    if radius > 0.0 and dist > radius then
                        angularRadius = math.deg(math.asin(math.min(1.0, radius / dist)))
                    elseif radius > 0.0 then
                        angularRadius = 90.0
                    end
                    angle = math.max(0.0, angle - angularRadius)

                    dist = surfaceDist
                    if angle <= PET_MAX_ANGLE_DEG then

                        local fled = false
                        if Capture and Capture.HasPermanentlyFled then
                            fled = safe_call(function() return Capture.HasPermanentlyFled(pal) end) and true or false
                        end
                        if not fled and (not bestAngle or angle < bestAngle) then
                            best, bestAngle, bestDist = pal, angle, dist
                        end
                    end
                end
            end
        end
    end

    if best ~= nil and excludeActor ~= nil then
        local excludeName = safe_call(function() return excludeActor:GetFullName() end)
        if excludeName then
            local bestName = safe_call(function() return best:GetFullName() end)
            if bestName ~= nil and bestName == excludeName then
                return nil, nil, nil
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

local function get_individual_handle(pal)
    local comp = pal.CharacterParameterComponent
    if not comp or not comp:IsValid() then
        return nil
    end
    return safe_call(function() return comp.IndividualHandle end)
end

local function stop_player_cheer(player)
    if player == nil then return false end
    return safe_call(function()
        if not player:IsValid() then return false end
        local ac = player.ActionComponent
        if ac == nil or not ac:IsValid() then return false end
        local cur = ac:GetCurrentAction()
        if cur == nil or not cur:IsValid() then return false end
        local name = tostring(cur:GetFullName())
        if name:find("BP_Action_Emote_", 1, true) == nil then return false end
        ac:CancelAction(cur)
        return true
    end) == true
end
Interaction.StopPlayerCheer = stop_player_cheer

function Interaction.PlayPlayerEmote(n)
    return play_player_emote(n)
end

local function play_refusal(pal, actionComp)
    local targetIdle = nil
    if actionComp and safe_call(function() return actionComp:IsValid() end) then
        targetIdle = safe_call(function() return actionComp:ActionIsEmpty() end)
    end
    if targetIdle ~= true then return "target is busy or its action state couldn't be read" end
    local param = get_individual_parameter(pal)
    if not param or not safe_call(function() return param:IsValid() end) then
        return "targeted Pal has no IndividualParameter — can't grant trust"
    end
    return nil
end

local function play_pal_half(pal, actionComp, player, stopCheerHere)
    Logger.log(string.format("[PalBonds/Interaction] target playing: PlayActionByType(pal, PalRandomRest=%d) NOW", ACTION_TYPE_PAL_RANDOM_REST))
    local actionOk, actionErr = pcall(function()
        actionComp:PlayActionByType(pal, ACTION_TYPE_PAL_RANDOM_REST)
    end)
    Logger.log(string.format("[PalBonds/Interaction] target PalRandomRest call returned — result=%s", actionOk and "ok" or tostring(actionErr)))

    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(PLAY_HAPPY_FOLLOWUP_DELAY_MS, function()

            if stopCheerHere then safe_call(function() stop_player_cheer(player) end) end
            safe_call(function()
                local palStillValid = pal ~= nil and pal:IsValid()
                local actionCompStillValid = actionComp ~= nil and actionComp:IsValid()
                if not (palStillValid and actionCompStillValid) then
                    Logger.log("[PalBonds/Interaction] Play: target no longer valid when Happy follow-up was due — skipping")
                    return
                end

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
                    "[PalBonds/Interaction] Play: Happy follow-up call returned — result=%s",
                    happyOk and "ok" or tostring(happyErr)
                ))

                safe_call(function()
                    grant_wild_interaction(pal, PLAY_FRIENDSHIP_GAIN, "Play")
                end)
            end)
        end)
    end)
    if not rescheduleOk then

        Logger.log("[PalBonds/Interaction] Play: could not schedule the Happy follow-up (ExecuteInGameThreadWithDelay failed) — granting trust immediately as a fallback so the interaction isn't silently lost")
        safe_call(function() grant_wild_interaction(pal, PLAY_FRIENDSHIP_GAIN, "Play (fallback)") end)
    end

end

local function do_play()
    Logger.log(string.format("[PalBonds/Interaction] %s pressed — starting Play", PLAY_KEY))
    local player = require("PlayerRef").Get()
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

    if Trust.PersonalityMayBond and not Trust.PersonalityMayBond(pal) then
        Logger.log("[PalBonds/Interaction] this Pal's personality is switched off for bonding — refusing Play")
        return
    end

    local actionComp = pal.ActionComponent
    if not we_are_a_guest() then
        local refusal = play_refusal(pal, actionComp)
        if refusal ~= nil then
            Logger.log("[PalBonds/Interaction] " .. refusal .. " — skipping Play")
            return
        end
    end

    if claimed_by_another_player(pal) then
        Logger.log("[PalBonds/Interaction] [CLAIMED] the targeted Pal is bonding with another player — skipping Play")
        return
    end
    local actorName = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format(
        "[PalBonds/Interaction] Play targeting %s at %.0f units (%.1f deg off-center)",
        tostring(actorName), dist, angle
    ))

    if we_are_a_guest() then
        local palId = safe_call(function() return Personality.GetStableId(pal) end)
        if palId == nil or require("Net").SendToServer("PLAY", palId) ~= true then
            Logger.log("[PalBonds/Interaction] [COOP] Play could not be sent to the host — nothing happens")
            return
        end
        pcall(function()
            ExecuteInGameThreadWithDelay(PLAY_HAPPY_FOLLOWUP_DELAY_MS, function()
                safe_call(function() stop_player_cheer(player) end)
            end)
        end)
    else
        play_pal_half(pal, actionComp, player, true)
    end

    safe_call(function() play_player_emote(CHEER_EMOTE_INDEX) end)
end

local radialMenuActionWindowOpen = false

local pendingWildFeedTarget = nil

local cachedWorkerMenuParameter = nil
local function construct_worker_menu_parameter()
    if cachedWorkerMenuParameter ~= nil
       and safe_call(function() return cachedWorkerMenuParameter:IsValid() end) then
        return cachedWorkerMenuParameter
    end
    local classOk, paramClass = pcall(function() return StaticFindObject("/Script/Pal.PalHUDDispatchParameter_WorkerRadialMenu") end)
    if not classOk or not paramClass or not paramClass:IsValid() then
        Logger.log("[PalBonds/Interaction] [FEED-PARAM] StaticFindObject('/Script/Pal.PalHUDDispatchParameter_WorkerRadialMenu') failed: " .. tostring(paramClass))
        return nil
    end

    local outer = safe_call(function() return UEHelpers.GetGameInstance() end)
    local outerLabel = "GameInstance"
    if outer == nil or not safe_call(function() return outer:IsValid() end) then
        outer = paramClass
        outerLabel = "the parameter class (GameInstance unavailable)"
    end
    local constructOk, newParam = pcall(function()
        return StaticConstructObject(paramClass, outer, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not (constructOk and newParam ~= nil and newParam:IsValid()) then
        Logger.log("[PalBonds/Interaction] [FEED-PARAM] StaticConstructObject(WorkerRadialMenu parameter) FAILED (caught, non-fatal): " .. tostring(newParam))
        return nil
    end
    cachedWorkerMenuParameter = newParam
    Logger.log("[PalBonds/Interaction] [FEED-PARAM] built the WorkerRadialMenu parameter once for this session, outered to " ..
        outerLabel .. " so it outlives a world change like the HUD that stores it")
    return newParam
end
local WORKER_RESULT_FEED = 1

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

local lastAimedInteractTarget = nil

local radialMenuWindowGeneration = 0
local radialMenuRedirectedThisWindow = false

local lastRedirectedWildPalName = nil

local lastRedirectedWildPalActor = nil

local loggedFieldWriteThisWindow = false

local RADIAL_ACTION_WINDOW_TIMEOUT_MS = 15000

local lastDecidedInstruction = nil

local cachedRedirectWildPal = nil
local lastRedirectComputeClock = nil

local REDIRECT_RECOMPUTE_INTERVAL_S = 0.5

local lastOpenMenuWidget = nil
local function openRadialMenuActionWindow(widget)
    radialMenuWindowGeneration = radialMenuWindowGeneration + 1
    local myGen = radialMenuWindowGeneration
    radialMenuActionWindowOpen = true
    radialMenuRedirectedThisWindow = false
    lastRedirectedWildPalName = nil
    lastRedirectedWildPalActor = nil
    loggedFieldWriteThisWindow = false
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

local function do_real_wild_feed_via_worker_menu()
    local wildPal = cachedRedirectWildPal
    if not wildPal or not wildPal:IsValid() then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] no valid cached wild Pal to target — falling back to the approximation")
        return false
    end
    local parameter = construct_worker_menu_parameter()
    if not parameter then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] fresh parameter construction failed — falling back to the approximation")
        return false
    end
    local handle = get_individual_handle(wildPal)
    if handle then
        pcall(function() parameter.IndividualHandle = handle end)
    end
    local setResultOk = pcall(function() parameter.resultType = WORKER_RESULT_FEED end)
    if not setResultOk then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] resultType write failed — falling back to the approximation")
        return false
    end

    pendingWildFeedTarget = wildPal
    Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] calling OnSelectedOrderWorkerRadialMenu(Feed) on the real wild Pal now — the item-picker popup may take a few seconds to actually appear")
    local callOk, callErr = pcall(function() wildPal:OnSelectedOrderWorkerRadialMenu(parameter) end)
    if not callOk then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] call errored: " .. tostring(callErr) .. " — falling back to the approximation")
        return false
    end
    Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] call returned ok")
    return true

end

grant_wild_interaction = function(pal, amount, label)
    if claimed_by_another_player(pal) then
        Logger.log("[PalBonds/Interaction] [CLAIMED] " .. hook_describe(pal) ..
            " is bonding with another player — no trust granted")
        return false
    end

    if pal ~= nil and Trust.MayBond and not Trust.MayBond(pal) then
        Logger.log("[PalBonds/Interaction] [CLAIMED] " .. hook_describe(pal) ..
            " is claimed by another player's bond — no trust granted")
        return false
    end
    if pal == nil then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": no target actor — nothing granted")
        return false
    end
    local valid = safe_call(function() return pal:IsValid() end)
    if not valid then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": target actor no longer valid — nothing granted")
        return false
    end

    local isOwned = safe_call(function() return Capture.IsAlreadyOwned(pal) end)
    if isOwned ~= false then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": target is owned (or ownership unreadable) — refusing to grant, this path is wild-Pal only")
        return false
    end

    if safe_call(function() return Capture.HasPermanentlyFled(pal) end) then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": this Pal already lost all its trust permanently — refusing to grant")
        return false
    end

    local before, after = Trust.AddPoints(pal, amount, label)
    if before == nil then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": no points granted")
        return false
    end

    Logger.log(string.format(
        "[PalBonds/Interaction] [BALANCE-TEST] %s on %s — +%d, trust %d -> %d",
        tostring(label), tostring(safe_call(function() return pal:GetFullName() end)),
        amount, before, after
    ))
    if Interaction.OnWildPalPetted then
        Interaction.OnWildPalPetted(pal)
    end
    return true
end

local PET_VERIFY_POLL_MS = 250
local PET_VERIFY_MAX_SECONDS = 4.0
local PET_ACTION_MARKER = "Petting"

local function current_action(pal)
    local cur = safe_call(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return nil end
        local ac = ctrl:GetAIActionComponent()
        if ac == nil or not ac:IsValid() then return nil end
        local a = ac:GetCurrentAction_BP()
        if a == nil or not a:IsValid() then return nil end
        return a
    end)
    if cur == nil then return nil, nil end
    return safe_call(function() return cur:GetFullName() end), safe_call(function() return cur:GetAddress() end)
end

local paidPetActionByPal = {}

local function player_is_in_pair_behavior()
    local player = safe_call(function() return require("PlayerRef").Get() end)
    if player == nil then return nil end
    local ac = safe_call(function() return player.ActionComponent end)
    if ac == nil or not safe_call(function() return ac:IsValid() end) then return nil end
    local name = safe_call(function()
        local cur = ac:GetCurrentAction()
        if cur == nil or not cur:IsValid() then return "" end
        return tostring(cur:GetFullName())
    end)
    if name == nil then return nil end
    return name:find("BP_ActionPairBehavior", 1, true) ~= nil
end
Interaction.PlayerIsInPairBehavior = player_is_in_pair_behavior

local function is_pet_action(name)
    return name ~= nil and tostring(name):find(PET_ACTION_MARKER, 1, true) ~= nil
end

local function grant_feed(wildTarget, grantAmount, itemId)

    if Trust.MayBond and not Trust.MayBond(wildTarget) then
        Logger.log("[PalBonds/Interaction] [CLAIMED] this Pal is claimed by another player's bond — the feed grants nothing")
        return
    end
    if safe_call(function() return Capture.HasPermanentlyFled(wildTarget) end) then
        Logger.log("[PalBonds/Interaction] [FEED-FRIENDSHIP] this Pal permanently lost its trust — the food is consumed but no friendship is granted")
        return
    end

    local before, after = Trust.AddPoints(wildTarget, grantAmount, "Feed")
    if before == nil then
        Logger.log("[PalBonds/Interaction] [FEED-FRIENDSHIP] no points granted for this feed (item=" .. tostring(itemId) .. ")")
        return
    end
    Logger.log(string.format(
        "[PalBonds/Interaction] [FEED-FRIENDSHIP] wild Feed +%d, trust %d -> %d (item=%s)",
        grantAmount, before, after, tostring(itemId)
    ))
    if Interaction.OnWildPalPetted then
        Interaction.OnWildPalPetted(wildTarget)
    end
end
Interaction.GrantFeed = grant_feed

local function grant_pet_when_it_happens(pal, acceptCurrent)
    if pal == nil then return end
    local actingFor = safe_call(function() return require("PlayerRef").Acting() end)
    local palKey = safe_call(function() return pal:GetFullName() end) or tostring(pal)
    local startedAt = os.clock()
    local lastSeen = nil
    local startName, startAddr = current_action(pal)
    local oldAddr = is_pet_action(startName) and startAddr or nil
    local sawGap = not is_pet_action(startName)
    if acceptCurrent then
        oldAddr = nil
        sawGap = true
    end
    local acceptedNotArrived = false
    local check
    local function run_check()
        if actingFor ~= nil then
            safe_call(function() require("PlayerRef").WithPlayer(actingFor, check) end)
        else
            safe_call(check)
        end
    end
    check = function()
        if not safe_call(function() return pal:IsValid() end) then
            Logger.log("[PalBonds/Interaction] [PET-CHECK] the Pal is gone before the pet happened — nothing granted")
            return
        end
        local name, addr = current_action(pal)
        lastSeen = name or lastSeen
        if is_pet_action(name) then
            local isNew
            if addr ~= nil and (oldAddr ~= nil or not sawGap) then
                isNew = addr ~= oldAddr
            else
                isNew = sawGap
            end
            if isNew and addr ~= nil and paidPetActionByPal[palKey] == addr then isNew = false end

            if isNew and player_is_in_pair_behavior() == false then
                isNew = false
                acceptedNotArrived = true
            end
            if isNew then
                paidPetActionByPal[palKey] = addr
                Logger.log(string.format("[PalBonds/Interaction] [PET-CHECK] pet confirmed after %.2fs — granting", os.clock() - startedAt))
                safe_call(function() grant_wild_interaction(pal, PET_FRIENDSHIP_GAIN, "Pet (radial)") end)
                return
            end
        else
            sawGap = true
        end
        if (os.clock() - startedAt) >= PET_VERIFY_MAX_SECONDS then
            local busy = lastSeen and tostring(lastSeen):match("^(%S+)") or "unknown action"
            if is_pet_action(lastSeen) then busy = busy .. ", still the PREVIOUS pet" end
            if acceptedNotArrived then busy = busy .. ", accepted the pet but never reached you" end
            Logger.log("[PalBonds/Interaction] [PET-CHECK] the pet never happened (Pal was busy: " .. busy .. ") — nothing granted")
            return
        end
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(PET_VERIFY_POLL_MS, run_check)
        end)
        if not ok then
            Logger.log("[PalBonds/Interaction] [PET-CHECK] could not schedule the check — nothing granted")
        end
    end
    run_check()
end

Interaction.GrantPetWhenItHappens = grant_pet_when_it_happens

local COOP_FIND_RADIUS = 2500
local COOP_MAX_FEED_GRANT = 500

local function send_pet_to_host(pal)
    local palId = safe_call(function() return Personality.GetStableId(pal) end)
    if palId == nil then
        Logger.log("[PalBonds/Interaction] [COOP] could not read this Pal's id — the pet is not reported to the host")
        return false
    end
    return require("Net").SendToServer("PET", palId) == true
end

local function guid_hex(g)
    if g == nil then return nil end
    return safe_call(function()

        local function mask32(n) return math.floor((n or 0)) % 4294967296 end
        return string.format("%08X%08X%08X%08X", mask32(g.A), mask32(g.B), mask32(g.C), mask32(g.D))
    end)
end

local function send_feed_to_host(pal, amount, itemId, food)
    local palId = safe_call(function() return Personality.GetStableId(pal) end)
    food = food or {}
    return require("Net").SendToServer("FEED", palId or "", tostring(amount or 0), tostring(itemId or ""),
        food.container or "", tostring(food.slot or ""), tostring(food.num or "")) == true
end

local COOP_MAX_FOOD_USE = 5

local function own_container_ids(pawn)
    local ids = {}
    local info = safe_call(function()
        local state = pawn.PlayerState
        if state == nil or not state:IsValid() then return nil end
        local inv = state.InventoryData
        if inv == nil or not inv:IsValid() then return nil end
        return inv.MyInventoryInfo
    end)
    if info == nil then return ids end
    for _, field in ipairs({ "CommonContainerId", "DropSlotContainerId", "EssentialContainerId",
        "WeaponLoadOutContainerId", "PlayerEquipArmorContainerId", "FoodEquipContainerId" }) do
        local hex = guid_hex(safe_call(function() return info[field].ID end))
        if hex ~= nil then ids[hex] = true end
    end
    return ids
end

local function charge_guest_food(containerHex, slotIndex, itemId, useNum, owned)
    slotIndex = tonumber(slotIndex)
    useNum = math.floor(tonumber(useNum) or 1)
    if useNum < 1 then useNum = 1 end
    if useNum > COOP_MAX_FOOD_USE then useNum = COOP_MAX_FOOD_USE end
    if containerHex == nil or containerHex == "" or slotIndex == nil then return false, "no slot named" end
    if owned ~= nil and not owned[containerHex] then return false, "not that player's own container" end
    local containers = safe_call(function() return FindAllOf("PalItemContainer") end) or {}
    for _, container in ipairs(containers) do
        if safe_call(function() return container:IsValid() end)
            and guid_hex(safe_call(function() return container.ID.ID end)) == containerHex then
            local slot = safe_call(function() return container.ItemSlotArray[slotIndex + 1] end)
            if slot == nil or not safe_call(function() return slot:IsValid() end) then return false, "slot missing" end
            local held = safe_call(function() return slot.ItemId.StaticId:ToString() end)
            if itemId ~= nil and itemId ~= "" and held ~= itemId then
                return false, "slot now holds " .. tostring(held)
            end
            local before = safe_call(function() return slot.StackCount end)
            if type(before) ~= "number" then return false, "count unreadable" end
            local after = before - useNum
            if after < 0 then after = 0 end
            local ok = pcall(function() slot.StackCount = after end)
            return ok, string.format("%d -> %d", before, after)
        end
    end
    return false, "container not found"
end
Interaction.ChargeGuestFood = charge_guest_food

local function find_wild_pal_near(pawn, palId)
    if pawn == nil or palId == nil or palId == "" then return nil end
    local origin = safe_call(function() return pawn:K2_GetActorLocation() end)
    if origin == nil then return nil end
    local pals = safe_call(function() return FindAllOf("PalCharacter") end)
    if not pals then return nil end
    for _, pal in ipairs(pals) do
        if safe_call(function() return pal:IsValid() end) then
            local loc = safe_call(function() return pal:K2_GetActorLocation() end)
            if loc and vec_length(vec_sub(loc, origin)) <= COOP_FIND_RADIUS then
                if safe_call(function() return Personality.GetStableId(pal) end) == palId then
                    return pal
                end
            end
        end
    end
    return nil
end

local function register_coop_handlers()
    local ok, Net = pcall(require, "Net")
    if not ok or Net == nil or Net.OnServer == nil then return end
    local PlayerRef = require("PlayerRef")

    Net.OnServer("PET", function(ctrl, pawn, fields)
        local pal = find_wild_pal_near(pawn, fields[1])
        if pal == nil then
            Logger.log("[PalBonds/Interaction] [COOP] a guest petted a Pal this machine cannot find near them (id " ..
                tostring(fields[1]) .. ") — nothing granted")
            return
        end
        PlayerRef.WithPlayer(pawn, grant_pet_when_it_happens, pal, true)
    end)

    Net.OnServer("PASSIVE", function(ctrl, pawn, fields)
        local nowOn = require("Trust").TogglePassiveFriendshipGain(PlayerRef.OwnerKey(pawn))
        local key = nowOn and "passive_on" or "passive_off"
        Capture.ShowLogFor(pawn, require("Locale").T(key), 1, key)
    end)

    Net.OnServer("PLAY", function(ctrl, pawn, fields)
        local pal = find_wild_pal_near(pawn, fields[1])
        if pal == nil then
            Logger.log("[PalBonds/Interaction] [COOP] a guest played with a Pal this machine cannot find near them (id " ..
                tostring(fields[1]) .. ") — nothing happens")
            return
        end
        PlayerRef.WithPlayer(pawn, function()
            if Capture.HasPermanentlyFled(pal) then
                Logger.log("[PalBonds/Interaction] [COOP] a guest's Play: this Pal fled for good — refused")
                return
            end
            if claimed_by_another_player(pal) then
                Logger.log("[PalBonds/Interaction] [COOP] [CLAIMED] a guest's Play: the Pal is bonding with another player — refused")
                return
            end
            local actionComp = safe_call(function() return pal.ActionComponent end)
            local refusal = play_refusal(pal, actionComp)
            if refusal ~= nil then
                Logger.log("[PalBonds/Interaction] [COOP] a guest's Play: " .. refusal .. " — refused")
                return
            end
            play_pal_half(pal, actionComp, pawn, false)
        end)
    end)

    Net.OnServer("FEED", function(ctrl, pawn, fields)

        if fields[4] ~= nil and fields[4] ~= "" then
            local charged, how = charge_guest_food(fields[4], fields[5], fields[3], fields[6], own_container_ids(pawn))
            Logger.log("[PalBonds/Interaction] [COOP] [FOOD] guest's " .. tostring(fields[3]) ..
                (charged and " charged: " or " NOT charged: ") .. tostring(how))
        end
        local pal = find_wild_pal_near(pawn, fields[1])
        if pal == nil then
            Logger.log("[PalBonds/Interaction] [COOP] a guest fed a Pal this machine cannot find near them (id " ..
                tostring(fields[1]) .. ") — nothing granted")
            return
        end
        local amount = math.floor(tonumber(fields[2]) or 0)
        if amount < 0 then amount = 0 end
        if amount > COOP_MAX_FEED_GRANT then amount = COOP_MAX_FEED_GRANT end
        local itemId = fields[3]
        PlayerRef.WithPlayer(pawn, grant_feed, pal, amount, itemId)
    end)
end

local PAIR_WATCH_POLL_MS = 250
local PAIR_ORPHAN_GRACE_SECONDS = 1.5
local PAIR_NEVER_STARTED_SECONDS = 6.0
local PAIR_STANDBY_MAX_SECONDS = 12.0
local PAIR_BEHAVIOR_MAX_SECONDS = 15.0

local function player_pair_action(player)
    return safe_call(function()
        if not player:IsValid() then return nil end
        local ac = player.ActionComponent
        if ac == nil or not ac:IsValid() then return nil end
        local cur = ac:GetCurrentAction()
        if cur == nil or not cur:IsValid() then return nil end
        local name = tostring(cur:GetFullName())
        if name:find("BP_ActionPair", 1, true) == nil then return nil end
        return { action = cur, name = name, ac = ac }
    end)
end

local POSE_RECHECK_MS = 400
local POSE_EMOTE_CANCEL_MS = 150

local function is_pair_pose(name)
    return type(name) == "string" and (name:find("Petting", 1, true) ~= nil
        or name:find("Feed", 1, true) ~= nil or name:find("Beckon", 1, true) ~= nil)
end

local function active_pose(player)
    return safe_call(function()
        local anim = player.Mesh:GetAnimInstance()
        if anim == nil or not anim:IsValid() then return nil end
        local m = anim:GetCurrentActiveMontage()
        if m == nil or not m:IsValid() then return nil end
        return { anim = anim, montage = m, name = tostring(m:GetFullName()) }
    end)
end

local function player_is_idle(player)
    return safe_call(function()
        local ac = player.ActionComponent
        if ac == nil or not ac:IsValid() then return false end
        local cur = ac:GetCurrentAction()
        return cur == nil or not cur:IsValid()
    end) == true
end

local function later(ms, fn)
    return pcall(function() ExecuteInGameThreadWithDelay(ms, function() safe_call(fn) end) end)
end

local POSE_MAX_CHECKS = 6

local function release_pose_step(player, label, check, stopped, escalated)
    if not safe_call(function() return player:IsValid() end) then return false end
    local pose = active_pose(player)
    if pose == nil then
        if check == 1 then
            Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": no animation left playing on the player")
        elseif stopped then
            Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": the pose is gone")
        end
        return false
    end
    if not is_pair_pose(pose.name) then
        if check >= POSE_MAX_CHECKS then
            Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": stopped watching, the player is playing " .. pose.name)
            return false
        end
        if check == 1 then
            Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": waiting for " .. pose.name .. " to finish first")
        end
        later(POSE_RECHECK_MS, function() release_pose_step(player, label, check + 1, stopped, escalated) end)
        return false
    end
    if not player_is_idle(player) then
        Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": the pose is there but the player is doing something — left alone")
        return false
    end
    if stopped and not escalated then

        Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": the pose is STILL playing (" ..
            pose.name .. ") — giving the player a fresh action, as a roll would")
        safe_call(function() play_player_emote(CHEER_EMOTE_INDEX) end)
        later(POSE_EMOTE_CANCEL_MS, function()
            local cancelled = stop_player_cheer(player)
            later(POSE_RECHECK_MS, function()
                local final = active_pose(player)
                Logger.log(string.format("[PalBonds/Interaction] [PAIR-RELEASE] %s: after the fresh action (emote cancelled: %s) the player plays %s",
                    tostring(label), tostring(cancelled), final and final.name or "no animation"))
            end)
        end)
        return true
    end
    if escalated then
        Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": the pose survived the fresh action too (" .. pose.name .. ")")
        return false
    end
    local okStop = pcall(function() pose.anim:Montage_Stop(0.0, pose.montage) end)
    Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] " .. tostring(label) .. ": stopped the waiting pose " ..
        pose.name .. (okStop and "" or " (Montage_Stop FAILED)"))
    later(POSE_RECHECK_MS, function() release_pose_step(player, label, check + 1, true, false) end)
    return true
end

local function stop_leftover_pose(player, label)
    return release_pose_step(player, label, 1, false, false)
end
Interaction.StopLeftoverPose = stop_leftover_pose

local function pal_in_pair_call(pal)
    if pal == nil or not safe_call(function() return pal:IsValid() end) then return false end
    local name = current_action(pal)
    return type(name) == "string" and name:find("AIActionPairCall", 1, true) ~= nil
end

function Interaction.PairWatchStep(st, player, pal, now)
    if player == nil then return "done" end
    local cur = player_pair_action(player)
    if cur == nil then
        if st.sawPair then

            if st.phase ~= "eating" then
                Logger.log(string.format("[PalBonds/Interaction] [PAIR-RELEASE] %s: ended before the Pal reached the player", tostring(st.label)))
                stop_leftover_pose(player, st.label)
                return "failed"
            end
            return "done"
        end
        if (now - st.startedAt) >= PAIR_NEVER_STARTED_SECONDS then return "done" end
        return "wait"
    end
    st.sawPair = true
    local phase = cur.name:find("Standby", 1, true) and "waiting" or "eating"
    if phase ~= st.phase then
        st.phase = phase
        st.phaseSince = now
    end
    if pal_in_pair_call(pal) then
        st.orphanSince = nil
    elseif st.orphanSince == nil then
        st.orphanSince = now
    end

    local why = nil
    if st.orphanSince ~= nil and (now - st.orphanSince) >= PAIR_ORPHAN_GRACE_SECONDS then
        why = "the Pal stopped coming to you"
    elseif phase == "waiting" and (now - st.phaseSince) >= PAIR_STANDBY_MAX_SECONDS then
        why = string.format("waited %.0fs", PAIR_STANDBY_MAX_SECONDS)
    elseif phase == "eating" and (now - st.phaseSince) >= PAIR_BEHAVIOR_MAX_SECONDS then
        why = string.format("eating pose over %.0fs", PAIR_BEHAVIOR_MAX_SECONDS)
    end
    if why == nil then return "wait" end

    local ok = pcall(function() cur.ac:CancelAction(cur.action) end)
    Logger.log(string.format("[PalBonds/Interaction] [PAIR-RELEASE] %s: released the player from the %s pose (%s) — cancel %s",
        tostring(st.label), phase, why, ok and "ok" or "FAILED"))
    stop_leftover_pose(player, st.label)
    return "released"
end

local pairWatchToken = 0
local pairWatchPalAddr = nil
local function watch_player_pair(pal, label)

    if we_are_a_guest() then return end
    pairWatchToken = pairWatchToken + 1
    pairWatchPalAddr = safe_call(function() return pal:GetAddress() end)
    local token = pairWatchToken
    local st = { startedAt = os.clock(), label = label }
    local function tick()
        if token ~= pairWatchToken then return end
        local player = safe_call(function() return require("PlayerRef").Get() end)
        local result = Interaction.PairWatchStep(st, player, pal, os.clock())
        if result ~= "wait" then return end
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(PAIR_WATCH_POLL_MS, function() safe_call(tick) end)
        end)
        if not ok then
            Logger.log("[PalBonds/Interaction] [PAIR-RELEASE] could not schedule the watchdog — it stops here")
        end
    end
    safe_call(tick)
end
Interaction.WatchPlayerPair = watch_player_pair

function Interaction.ForgetJoinedPal(actorAddr)
    if actorAddr == nil then return 0 end
    local function same(o)
        if o == nil then return false end
        local ok, a = pcall(function() return o:GetAddress() end)
        return ok and a == actorAddr
    end
    local n = 0
    if same(cachedRedirectWildPal) then cachedRedirectWildPal = nil; n = n + 1 end
    if same(lastRedirectedWildPalActor) then lastRedirectedWildPalActor = nil; n = n + 1 end
    if same(pendingWildFeedTarget) then pendingWildFeedTarget = nil; n = n + 1 end
    if pairWatchPalAddr ~= nil and pairWatchPalAddr == actorAddr then
        pairWatchToken = pairWatchToken + 1
        pairWatchPalAddr = nil
        n = n + 1
    end
    return n
end

local function closeRadialMenuActionWindow()
    if radialMenuRedirectedThisWindow and lastDecidedInstruction then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] window closing with a substituted wild Pal and a decided instruction=" .. tostring(lastDecidedInstruction) .. " — firing the real action now")
        if lastDecidedInstruction == "care" then

            local petTarget = lastRedirectedWildPalActor
            if we_are_a_guest() then

                safe_call(function() send_pet_to_host(petTarget) end)
            else
                safe_call(function() grant_pet_when_it_happens(petTarget) end)
                safe_call(function() watch_player_pair(petTarget, "Pet") end)
            end
        elseif lastDecidedInstruction == "feed" then
            local feedTarget = cachedRedirectWildPal
            local realFeedOk = safe_call(do_real_wild_feed_via_worker_menu)
            if realFeedOk then
                safe_call(function() watch_player_pair(feedTarget, "Feed") end)
            end
            if not realFeedOk then

                Logger.log("[PalBonds/Interaction] the wild feed did not go through (the Pal moved away, or the picker never opened) - granting nothing, since no item was spent and no interaction happened")
            end
        end
    end
    radialMenuActionWindowOpen = false
    lastDecidedInstruction = nil

end

local EMOTE_PATH_FMT = "/Game/Pal/Blueprint/Action/Palmi/Emote/BP_Action_Emote_%d.BP_Action_Emote_%d_C"

local function resolve_emote_class(n)
    return safe_call(function()
        return StaticFindObject(string.format(EMOTE_PATH_FMT, n, n))
    end)
end

local function find_player_controller()

    local player = require("PlayerRef").Get()
    if player ~= nil then
        local pc = safe_call(function() return player.Controller end)
        if pc ~= nil and safe_call(function() return pc:IsValid() end) then return pc end
    end
    local list = safe_call(function() return FindAllOf("BP_PalPlayerController_C") end)
    if type(list) ~= "table" then return nil end

    local firstValid = nil
    for _, pc in ipairs(list) do
        if pc ~= nil and safe_call(function() return pc:IsValid() end) then
            if firstValid == nil then firstValid = pc end
            local ok, isLocal = pcall(function() return pc:IsLocalPlayerController() end)
            if ok and isLocal == true then return pc end
        end
    end
    return firstValid
end

play_player_emote = function(n)
    local cls = resolve_emote_class(n)
    if cls == nil or not safe_call(function() return cls:IsValid() end) then
        Logger.log("[PalBonds/Interaction] [EMOTE] emote " .. n .. " does not resolve — skipping")
        return false
    end
    local pc = find_player_controller()
    if pc == nil then
        Logger.log("[PalBonds/Interaction] [EMOTE] no BP_PalPlayerController_C — are you in-world?")
        return false
    end
    local pawn = safe_call(function() return pc.Pawn end)
    if pawn == nil or not safe_call(function() return pawn:IsValid() end) then
        Logger.log("[PalBonds/Interaction] [EMOTE] the player controller has no valid Pawn")
        return false
    end

    local playerActionComp = safe_call(function() return pawn.ActionComponent end)
    if playerActionComp == nil or not safe_call(function() return playerActionComp:IsValid() end) then
        Logger.log("[PalBonds/Interaction] [EMOTE] the player has no readable ActionComponent — skipping the cheer")
        return false
    end
    local ok, err = pcall(function()
        playerActionComp:PlayAction(pawn, cls)
    end)
    Logger.log("[PalBonds/Interaction] [EMOTE] BP_Action_Emote_" .. n ..
        "_C via ActionComponent:PlayAction — " .. (ok and "call ok" or ("FAILED: " .. tostring(err))))
    return ok
end

local itemRarityCache = {}
local function read_item_rarity(itemId, worldContext)
    if type(itemId) ~= "string" or worldContext == nil then return nil end
    local cached = itemRarityCache[itemId]
    if cached ~= nil then return cached end
    local rarity = safe_call(function()
        if not worldContext:IsValid() then return nil end
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if utility == nil or not utility:IsValid() then return nil end
        local manager = utility:GetItemIDManager(worldContext)
        if manager == nil or not manager:IsValid() then return nil end
        local data = manager:GetStaticItemData(UEHelpers.FindOrAddFName(itemId))
        if data == nil or not data:IsValid() then return nil end
        return data.Rarity
    end)
    if type(rarity) == "number" then itemRarityCache[itemId] = rarity end
    return rarity
end

function Interaction.FeedGrantAmount(itemId, worldContext)
    if itemId == "AffectionFruit_02" then
        return KINSHIP_PEACH_LESSER_FRIENDSHIP_BASE, "Kinship Peach (lesser), own amount"
    elseif itemId == "AffectionFruit_01" then
        return KINSHIP_PEACH_FULL_FRIENDSHIP_BASE, "Kinship Peach, own amount"
    end
    local rarity = read_item_rarity(itemId, worldContext)
    if type(rarity) ~= "number" then
        return FEED_FRIENDSHIP_BASE, "rarity UNREADABLE, base amount only"
    end
    local tier = math.max(0, math.min(4, math.floor(rarity)))
    return FEED_FRIENDSHIP_BASE + FEED_RARITY_BONUS[tier], "rarity " .. tostring(rarity)
end

local function run_on_game_thread(fn)
    local direct = pcall(function() ExecuteInGameThread(function() safe_call(fn) end) end)
    if direct then return true end
    local delayed = pcall(function() ExecuteInGameThreadWithDelay(1, function() safe_call(fn) end) end)
    if delayed then return true end

    Logger.log("[PalBonds/Interaction] [KEYBIND] could not reach the game thread — running directly, which is what used to corrupt the next world load")
    safe_call(fn)
    return false
end

local keyOwner = {}
local keyBound = {}
local keyHandler = {}

local function bind_key(action, name, fn)
    if fn ~= nil then keyHandler[action] = fn end

    for k, owner in pairs(keyOwner) do
        if owner == action then keyOwner[k] = nil end
    end
    if type(name) ~= "string" or name == "" then return false end
    local okKey, code = pcall(function() return Key ~= nil and Key[name] or nil end)
    if not okKey or code == nil then
        Logger.log("[PalBonds/Interaction] \"" .. tostring(name) ..
            "\" is not a key UE4SS knows — " .. action .. " has no key until you pick another")
        return false
    end
    keyOwner[name] = action
    if keyBound[name] then return true end

    local ok = pcall(RegisterKeyBind, code, function()
        local owner = keyOwner[name]
        if owner == nil then return end

        local okM, MenuMod = pcall(require, "Menu")
        if okM and MenuMod and MenuMod.WaitingForKey and MenuMod.WaitingForKey() then return end
        local handler = keyHandler[owner]
        if handler ~= nil then handler() end
    end)
    if ok then keyBound[name] = true end
    return ok
end

pcall(function()
Settings.OnChange(function(key)
    if key == "KeyPlay" then
        PLAY_KEY = Settings.Get("KeyPlay")
        bind_key("play", PLAY_KEY)
        Logger.log("[PalBonds/Interaction] Play is now " .. tostring(PLAY_KEY))
        return
    elseif key == "KeyTags" then
        TAGS_KEY = Settings.Get("KeyTags")
        bind_key("tags", TAGS_KEY)
        Logger.log("[PalBonds/Interaction] the tags key is now " .. tostring(TAGS_KEY))
        return
    elseif key == "KeyPassiveGain" then
        PASSIVE_KEY = Settings.Get("KeyPassiveGain")
        bind_key("passive", PASSIVE_KEY)
        Logger.log("[PalBonds/Interaction] the passive-gain key is now " .. tostring(PASSIVE_KEY))
        return
    end
    FEED_FRIENDSHIP_BASE = Settings.Get("FeedBase")
    FEED_RARITY_BONUS[0] = Settings.Get("FeedBonusCommon")
    FEED_RARITY_BONUS[1] = Settings.Get("FeedBonusUncommon")
    FEED_RARITY_BONUS[2] = Settings.Get("FeedBonusRare")
    FEED_RARITY_BONUS[3] = Settings.Get("FeedBonusEpic")
    FEED_RARITY_BONUS[4] = Settings.Get("FeedBonusLegendary")
    KINSHIP_PEACH_LESSER_FRIENDSHIP_BASE = Settings.Get("KinshipPeachLesser")
    KINSHIP_PEACH_FULL_FRIENDSHIP_BASE = Settings.Get("KinshipPeach")
    PET_FRIENDSHIP_GAIN = Settings.Get("Pet")
    PLAY_FRIENDSHIP_GAIN = Settings.Get("Play")
end)
end)

function Interaction.Init()

    safe_call(register_coop_handlers)
    Logger.log(string.format("[PalBonds/Interaction] keys: %s = Play, %s = personality tags, %s = passive gain", PLAY_KEY, TAGS_KEY, PASSIVE_KEY))
    bind_key("play", PLAY_KEY, function()

        if on_dedicated_server() then return end
        run_on_game_thread(do_play)
    end)

    bind_key("tags", TAGS_KEY, function()

        if on_dedicated_server() then return end

        run_on_game_thread(function()
            local okI, IndicatorMod = pcall(require, "Indicator")
            if not (okI and IndicatorMod and IndicatorMod.TogglePersonalityLabels) then
                Logger.log("[PalBonds/Interaction] [TAG-TOGGLE] Indicator.TogglePersonalityLabels is unavailable — nothing toggled")
                return
            end
            local nowVisible = IndicatorMod.TogglePersonalityLabels()
            safe_call(function()
                local okC, CaptureMod = pcall(require, "Capture")
                if okC and CaptureMod and CaptureMod.ShowToast then
                    local Locale = require("Locale")
                    local key = nowVisible and "tags_on" or "tags_off"
                    CaptureMod.ShowToast(Locale.T(key), key)
                end
            end)
        end)
    end)

    bind_key("passive", PASSIVE_KEY, function()
        if on_dedicated_server() then return end

        if we_are_a_guest() then
            run_on_game_thread(function() require("Net").SendToServer("PASSIVE") end)
            return
        end

        run_on_game_thread(function()
            local okT, TrustMod = pcall(require, "Trust")
            if not (okT and TrustMod and TrustMod.TogglePassiveFriendshipGain) then
                Logger.log("[PalBonds/Interaction] [PASSIVE-TOGGLE] Trust.TogglePassiveFriendshipGain is unavailable — nothing toggled")
                return
            end
            local nowOn = TrustMod.TogglePassiveFriendshipGain()
            safe_call(function()
                local okC, CaptureMod = pcall(require, "Capture")
                if okC and CaptureMod and CaptureMod.ShowToast then

                    local Locale = require("Locale")
                    local key = nowOn and "passive_on" or "passive_off"
                    CaptureMod.ShowToast(Locale.T(key), key)
                end
            end)
        end)
    end)

    local function readable(value)
        if value == nil then return "nil" end
        local ok, str = pcall(function() return value:ToString() end)
        if ok and str ~= nil then return str end
        return tostring(value)
    end
    local okWatchUseSlot = pcall(function()
        RegisterHook("/Script/Pal.PalItemSlot:RequestUseToCharacter", function() end,

        function(Context, TargetCharacterID, UseNum)
            local wildTarget = pendingWildFeedTarget
            pendingWildFeedTarget = nil
            if not wildTarget or not wildTarget:IsValid() then return end
            local slot = hook_get(Context)
            local useNum = hook_get(UseNum)
            if not slot or not slot:IsValid() or type(useNum) ~= "number" then
                Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] pending wild feed but slot/useNum unreadable — skipping")
                return
            end

            local guestFeed = we_are_a_guest()
            local beforeCount = safe_call(function() return slot.StackCount end)
            if guestFeed then
                Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] guest: the food is the host's to charge — no local write")
            elseif type(beforeCount) ~= "number" then
                Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] could not read StackCount — skipping")
                return
            else
                local newCount = beforeCount - useNum
                if newCount < 0 then newCount = 0 end
                local writeOk, writeErr = pcall(function() slot.StackCount = newCount end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] wild target confirmed — real decrement never applies for a wild Pal, applying it ourselves: %d -> %d (write %s)",
                    beforeCount, newCount, writeOk and "ok" or ("FAILED: " .. tostring(writeErr))
                ))
            end

            local itemId = safe_call(function() return slot.ItemId and readable(slot.ItemId.StaticId) end)
            local grantAmount, rarityNote = Interaction.FeedGrantAmount(itemId, wildTarget)
            Logger.log(string.format("[PalBonds/Interaction] [FEED-RARITY] %s -> %d friendship (%s)",
                tostring(itemId), grantAmount, tostring(rarityNote)))

            if guestFeed then
                send_feed_to_host(wildTarget, grantAmount, itemId, {
                    container = guid_hex(safe_call(function() return slot.ContainerId.ID end)),
                    slot = safe_call(function() return slot.SlotIndex end),
                    num = useNum,
                })
                return
            end
            grant_feed(wildTarget, grantAmount, itemId)

        end)
    end)
    if not okWatchUseSlot then
        Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] could not install PalItemSlot:RequestUseToCharacter watch hook (name may need adjusting)")
    end

    local RADIAL_MENU_CLASS = "/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu.WBP_PlayerRadialMenu_C"

    local MAX_RADIAL_HOOK_ROUNDS = 60
    local RADIAL_HOOK_RETRY_MS = 5000

    local RADIAL_HOOK_SLOW_RETRY_MS = 15000

    local radialHookTargets = {

        { tag = "CanOpenPlayerActionMenu", candidates = {"Can Open Player Action Menu"}, onFire = openRadialMenuActionWindow },

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

        { tag = "CloseMenu", candidates = {"CloseMenu", "Close Menu"}, onFire = closeRadialMenuActionWindow },
    }
    local loggedHookFailureOnce = {}
    local function make_hook_handler(onFire)
        return function(Context, A, B, C)
            if world_is_closing() or guest_blocks_input() then return end
            local self_ = hook_get(Context)
            if onFire then

                safe_call(function() onFire(self_) end)
            end
        end
    end

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
                            RegisterHook(path, make_hook_handler(target.onFire))
                        end)
                        local errFirstLine
                        if not ok then
                            errFirstLine = tostring(err):match("^[^\n]*") or tostring(err)
                        end

                        if ok or not loggedHookFailureOnce[path] then
                            if not ok then loggedHookFailureOnce[path] = true end
                            Logger.log(string.format(
                                "[PalBonds/Interaction] [%s] round %d: RegisterHook(%s) = %s",
                                logTag, round, path, ok and "OK" or ("FAILED (logged once for this name): " .. errFirstLine)
                            ))
                        end
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

                Logger.log("[PalBonds/Interaction] [HOOKS] " .. logTag ..
                    ": all candidate hooks registered at round " .. round ..
                    " — petting and feeding wild Pals is armed")
                return
            end
            if provenLoadedAtRound and (round - provenLoadedAtRound) >= EARLY_EXIT_ROUNDS_AFTER_PROOF then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] stopping early — class proven loaded at round " .. provenLoadedAtRound .. " (a sibling hook succeeded), remaining unresolved names are very likely just wrong, not a timing issue (see FAILED lines above for exact names tried)")
                return
            end

            local waitingForClass = (provenLoadedAtRound == nil)
            if round >= MAX_RADIAL_HOOK_ROUNDS and not waitingForClass then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] giving up after " .. round .. " rounds — some functions never resolved (see FAILED lines above for exact names tried)")
                return
            end
            local nextDelay = RADIAL_HOOK_RETRY_MS
            if round >= MAX_RADIAL_HOOK_ROUNDS then
                nextDelay = RADIAL_HOOK_SLOW_RETRY_MS

                if round == MAX_RADIAL_HOOK_ROUNDS or (round % 40 == 0) then
                    Logger.log(string.format(
                        "[PalBonds/Interaction] [HOOKS] %s: the radial-menu class is still not loaded after %d rounds — still retrying (petting and feeding wild Pals cannot work until it is)",
                        logTag, round))
                end
            end
            local rescheduleOk = pcall(function()
                ExecuteInGameThreadWithDelay(nextDelay, function()
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

    local okOtomoGetter = pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:TryGetSpawnedOtomo", function(Context) end, function(Context, ReturnValue)
            if world_is_closing() or guest_blocks_input() then return end

            if not radialMenuActionWindowOpen then return end
            local returned = hook_get(ReturnValue)
            do
                local ok, err = pcall(function()
                    local player = require("PlayerRef").Get()
                    if not player or not player:IsValid() then return end
                    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
                    if not originLoc then
                        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
                    end
                    if not originLoc then return end
                    local controlRot = safe_call(function() return player:GetControlRotation() end)
                    if not controlRot then return end
                    local forward = rotator_to_forward(controlRot)

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

                            local scanMs = (scanEnd - scanStart) * 1000
                            if scanMs >= 15.0 then
                                Logger.log(string.format(
                                    "[PalBonds/Interaction] [RADIAL-REDIRECT-PERF] find_targeted_pal scan took %.2fms (only logged when >= 15ms — see two-hundred-and-eighth pass)",
                                    scanMs
                                ))
                            end
                        end
                        cachedRedirectWildPal = wildPal
                        lastRedirectComputeClock = now
                    end
                    if not wildPal or not wildPal:IsValid() then
                        redirect_idle_log("noaim", "[PalBonds/Interaction] [RADIAL-REDIRECT] menu window open but not aiming at any Pal — leaving the real Otomo in place")
                        return
                    end

                    if Trust.PersonalityMayBond and not Trust.PersonalityMayBond(wildPal) then
                        redirect_idle_log("notbondable",
                            "[PalBonds/Interaction] [RADIAL-REDIRECT] this Pal's personality is switched off for bonding — leaving the real Otomo in place")
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
                        redirect_idle_log("isotomo", "[PalBonds/Interaction] [RADIAL-REDIRECT] aimed Pal is already the current Otomo — nothing to substitute")
                        return
                    end
                    local isWild = Capture.IsAlreadyOwned and (not Capture.IsAlreadyOwned(wildPal))
                    if not isWild then
                        redirect_idle_log("owned", "[PalBonds/Interaction] [RADIAL-REDIRECT] the aimed Pal is already owned — leaving the real Otomo in place (this system is for wild Pals only)")
                        return
                    end

                    if claimed_by_another_player(wildPal) then
                        redirect_idle_log("claimed", "[PalBonds/Interaction] [RADIAL-REDIRECT] the aimed Pal is already bonding with another player — leaving the real Otomo in place")
                        return
                    end

                    lastRedirectedWildPalActor = wildPal
                    lastRedirectIdleReason = nil
                    if lastRedirectedWildPalName ~= wildPalName then
                        lastRedirectedWildPalName = wildPalName
                        Logger.log(string.format(
                            "[PalBonds/Interaction] [RADIAL-REDIRECT] EXPERIMENTAL: substituting wild %s in place of the Otomo for this menu action (every qualifying call now, not just the first — see ninety-sixth pass) — watch closely",
                            hook_describe(wildPal)
                        ))

                    end

                    radialMenuRedirectedThisWindow = true
                    local setOk, setErr = pcall(function()
                        ReturnValue:set(wildPal)
                    end)
                    if not setOk then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] substitution failed: " .. tostring(setErr))
                    end

                    if lastOpenMenuWidget then
                        local widgetValid = safe_call(function() return lastOpenMenuWidget:IsValid() end)
                        if widgetValid then
                            local fieldSetOk, fieldSetErr = pcall(function()
                                lastOpenMenuWidget.SpawnedOtomo = wildPal
                            end)

                            if not fieldSetOk or not loggedFieldWriteThisWindow then
                                loggedFieldWriteThisWindow = true
                                Logger.log(string.format(
                                    "[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] widget.SpawnedOtomo = wild %s -> %s (logged once per menu window)",
                                    hook_describe(wildPal),
                                    fieldSetOk and "ok" or ("FAILED: " .. tostring(fieldSetErr))
                                ))
                            end
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

    local function apply_wild_fix_to_worker_parameter(parameter, hookLabel)
        local paramDesc = hook_describe(parameter)
        Logger.log(string.format(
            "[PalBonds/Interaction] [WORKER-BIND-FIX] %s saw a WorkerRadialMenu Parameter: %s",
            hookLabel, paramDesc
        ))
        local ok, err = pcall(function()
            local player = require("PlayerRef").Get()
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
        if not parameter then return end
        if not paramDesc:find("WorkerRadialMenu", 1, true) then
            return
        end
        apply_wild_fix_to_worker_parameter(parameter, hookLabel)
    end

    local workerOnSetupRound = 0

    local WORKER_MENU_OVERLAY_CLASS = "/Game/Pal/Blueprint/UI/WorkerRadialMenu/WBP_WorkerRadialMenu_Overlay.WBP_WorkerRadialMenu_Overlay_C"
    local function install_worker_onsetup_fix_hook()
        local path = WORKER_MENU_OVERLAY_CLASS .. ":OnSetup"
        local ok = pcall(function()
            RegisterHook(path, function(Context)
                if world_is_closing() or guest_blocks_input() then return end
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
            if world_is_closing() or guest_blocks_input() then return end
            try_fix_worker_menu_parameter("PalHUDInGame:PushWidgetStackableUI", Context, WidgetClassParam, ParameterParam)
        end)
    end)
    if not okPushWidget then
        Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not install PushWidgetStackableUI hook")
    end
    local okServicePush = pcall(function()
        RegisterHook("/Script/Pal.PalHUDService:Push", function(Context, WidgetClassParam, ParameterParam)
            if world_is_closing() or guest_blocks_input() then return end
            try_fix_worker_menu_parameter("PalHUDService:Push", Context, WidgetClassParam, ParameterParam)
        end)
    end)
    if not okServicePush then
        Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not install PalHUDService:Push hook")
    end

end

function Interaction.GrantWildInteraction(pal, amount, label)
    return grant_wild_interaction(pal, amount, label)
end

function Interaction.OnWildPalPetted(palActor)
    Trust.OnInteractionSucceeded(palActor)

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
    else
        Logger.log("[PalBonds/Personality] could not resolve a stable ID for this Pal (handle/ID lookup failed) — see Personality.lua")
    end
end

function Interaction.ResetForNewWorld()
    palScanCache = nil
    palScanCacheAge = 0
    pendingWildFeedTarget = nil
    lastAimedInteractTarget = nil
    lastRedirectedWildPalName = nil
    lastRedirectedWildPalActor = nil
    lastDecidedInstruction = nil
    cachedRedirectWildPal = nil
    lastRedirectComputeClock = nil
    lastOpenMenuWidget = nil
    paidPetActionByPal = {}
    capsuleReported = {}
    Logger.log("[PalBonds/Interaction] [WORLD-RESET] dropped the radial-menu, aim and pet-check references from the old world")
end
return Interaction
