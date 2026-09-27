local Logger = require("Logger")
local Trust = {}

local EASY_TEST_MODE = false

local FOLLOW_TRIGGER_RATIO = 0.5
local FRIENDLY_TRIGGER_RATIO = 0.2

local TICK_INTERVAL_MS = 1500

local LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST = false

local passiveGainOffBy = {}

local function read_passive_default()
    local on = true
    pcall(function() on = require("Settings").Get("PassiveGainEnabled") ~= 0 end)
    if on then passiveGainOffBy["local"] = nil else passiveGainOffBy["local"] = true end
end

read_passive_default()

pcall(function()
    require("Settings").OnChange(function(key)
        if key ~= "PassiveGainEnabled" then return end
        read_passive_default()
    end)
end)
local REAL_PASSIVE_FRIENDSHIP_PER_TICK = require("Settings").Get("PassivePerTick")
local PASSIVE_FRIENDSHIP_PER_TICK = LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST and 0 or REAL_PASSIVE_FRIENDSHIP_PER_TICK

pcall(function()
    require("Settings").OnChange(function(key)
        if key ~= "PassivePerTick" then return end
        REAL_PASSIVE_FRIENDSHIP_PER_TICK = require("Settings").Get("PassivePerTick")
        PASSIVE_FRIENDSHIP_PER_TICK = LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST and 0 or REAL_PASSIVE_FRIENDSHIP_PER_TICK
    end)
end)

local THIRD_PARTY_DAMAGE_LOG_INTERVAL = 2.0

local EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS = false

local MAX_FOLLOW_DISTANCE = 3500.0

local DRIFT_GRACE_SECONDS = 3.0
local driftingSince = {}

local friendlyFireEvents = 0
local friendlyFirePairLogged = {}
function Trust.ReportFriendlyFire()
    local n = friendlyFireEvents
    friendlyFireEvents = 0
    friendlyFirePairLogged = {}
    return n
end

local BONDING_TRIGGER_THRESHOLD_BASE = 500

local TRIGGER_OFF_FLOOR = math.floor(BONDING_TRIGGER_THRESHOLD_BASE * 0.05)

local function trigger_enabled(kind)
    local setting = (kind == "abandoned") and "AbandonmentEnabled" or "BetrayalEnabled"
    local on = true
    pcall(function() on = require("Settings").Get(setting) ~= 0 end)
    return on
end

local PLAYER_HIT_PENALTY_FRACTION = 0.5

local State = {}

local briefFollow = {}

local trackedAddresses = {}
local trackedAddressesAt = -99
local addressGateUsable = true
local TRACKED_ADDRESS_REFRESH_SECONDS = 1.0
local find_player

local function address_of(actor)
    if actor == nil then return nil end
    local ok, addr = pcall(function() return actor:GetAddress() end)
    if ok then return addr end
    return nil
end

local function refresh_tracked_addresses()
    local now = os.clock()
    if (now - trackedAddressesAt) < TRACKED_ADDRESS_REFRESH_SECONDS then return end
    trackedAddressesAt = now
    local fresh = {}
    for _, st in pairs(State) do
        if st and st.pal then
            local addr = address_of(st.pal)
            if addr ~= nil then fresh[addr] = true end
        end
    end

    local player = find_player and find_player()
    if player ~= nil then
        local paddr = address_of(player)
        if paddr ~= nil then fresh[paddr] = true end
    end

    for _, st in pairs(State) do
        if st and st.ownerPawn ~= nil and st.ownerKey ~= "local" then
            local oaddr = address_of(st.ownerPawn)
            if oaddr ~= nil then fresh[oaddr] = true end
        end
    end

    trackedAddresses = fresh

    if next(fresh) == nil and next(State) ~= nil then
        if addressGateUsable then
            addressGateUsable = false
            Logger.log("[PalBonds/Trust] [DAMAGE-GATE] GetAddress() resolved nothing for any tracked Pal — the cheap damage-event filter cannot work on this build, so it is now OFF and every event is processed as before (logged once). Slower, but nothing is silently skipped.")
        end
    elseif not addressGateUsable then
        addressGateUsable = true
        Logger.log("[PalBonds/Trust] [DAMAGE-GATE] address filtering is working again")
    end
end

local function damage_event_is_ours(defender, attacker)
    refresh_tracked_addresses()
    if not addressGateUsable then return true end
    if next(trackedAddresses) == nil then return false end
    local d = address_of(defender)
    if d ~= nil and trackedAddresses[d] then return true end
    local a = address_of(attacker)
    if a ~= nil and trackedAddresses[a] then return true end
    return false
end
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local playerRefForGate = nil

local function we_are_a_guest()
    local ok, Session = pcall(require, "Session")
    if not (ok and Session and Session.IsGuest) then return false end
    local okAsk, guest = pcall(Session.IsGuest)
    return okAsk and guest == true
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

local PlayerRef = require("PlayerRef")
find_player = function()
    return PlayerRef.Get()
end
local function find_player_name()
    return PlayerRef.Name()
end

local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end

local remote_owner_pawn, owner_player, as_owner, find_fighter, as_player

local function get_key(pal)
    return safe_call(function() return pal:GetFullName() end)
end
local function get_state(pal)
    local key = get_key(pal)
    if not key then return nil, nil end
    local st = State[key]
    if not st then
        st = { interactionCount = 0, isFollowing = false, points = 0, pal = pal, tickCount = 0, captureTriggered = false }
        State[key] = st
    else
        st.pal = pal
    end
    return st, key
end

local function guest_view()
    local ok, HostView = pcall(require, "HostView")
    if not ok or HostView == nil or not HostView.IsGuest() then return nil end
    return HostView
end

function Trust.HasBondingState(palActor)
    local view = guest_view()
    if view then return view.HasBond(palActor) end
    local key = get_key(palActor)
    return key ~= nil and State[key] ~= nil
end
local function get_individual_parameter(pal)
    local comp = safe_call(function() return pal.CharacterParameterComponent end)
    if not comp or not comp:IsValid() then return nil end
    return safe_call(function() return comp:GetIndividualParameter() end)
end

local EASY_TEST_SPEEDUP = 10

local LevelMultiplierCache = {}

local BossActorsSeen = {}
function Trust.MarkBossActor(palActor)
    local key = safe_call(function() return palActor:GetFullName() end)
    if key == nil or BossActorsSeen[key] then return end
    BossActorsSeen[key] = true

    LevelMultiplierCache[key] = nil
end

local BOSS_ID_PREFIXES = { "BOSS_", "GYM_", "RAID_" }
local BOSS_CLASS_MARKERS = { "_BOSS", "_GYM", "_RAID" }
local function is_boss_pal(palActor, charIdText, fullName)
    if type(charIdText) == "string" then
        local up = charIdText:upper()
        for _, prefix in ipairs(BOSS_ID_PREFIXES) do
            if up:sub(1, #prefix) == prefix then return true end
        end
    end
    if type(fullName) == "string" then
        if BossActorsSeen[fullName] then return true end
        local cls = (fullName:match("^(%S+)") or ""):upper()
        for _, marker in ipairs(BOSS_CLASS_MARKERS) do
            if cls:find(marker, 1, true) then return true end
        end
    end
    return false
end

function Trust.ComputeLevelMultiplier(palActor)

    if LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST then
        return 1.0
    end
    if EASY_TEST_MODE then
        return 1 / EASY_TEST_SPEEDUP
    end
    local cacheKey = safe_call(function() return palActor:GetFullName() end)
    if cacheKey and LevelMultiplierCache[cacheKey] ~= nil then
        return LevelMultiplierCache[cacheKey]
    end
    local palParam = get_individual_parameter(palActor)
    local palLevel = palParam and safe_call(function() return palParam.SaveParameter.Level end)
    local player = find_player()
    local playerParam = player and get_individual_parameter(player)
    local playerLevel = playerParam and safe_call(function() return playerParam.SaveParameter.Level end)
    if palLevel == nil or playerLevel == nil then
        Logger.log(string.format(
            "[PalBonds/Trust] [LEVEL-MULT] could not read pal/player level (pal=%s player=%s) — defaulting to x1 (not cached, will retry next call)",
            tostring(palLevel), tostring(playerLevel)
        ))
        return 1.0
    end

    local gap = palLevel - playerLevel
    local multiplier
    if gap >= 20 then
        multiplier = 4.0
    elseif gap >= 10 then
        multiplier = 2.0
    elseif gap >= 5 then
        multiplier = 1.5
    elseif gap <= -20 then
        multiplier = 0.25
    elseif gap <= -10 then
        multiplier = 0.5
    elseif gap <= -5 then
        multiplier = 0.75
    else
        multiplier = 1.0
    end

    local BOSS_BAR_MULTIPLIER = 2.0
    local charIdText = safe_call(function()
        local cid = palParam:GetCharacterID()
        if cid == nil then return nil end
        local okS, s = pcall(function() return cid:ToString() end)
        if okS and type(s) == "string" then return s end
        return tostring(cid)
    end)
    local isBoss = is_boss_pal(palActor, charIdText, cacheKey)
    if isBoss then multiplier = multiplier * BOSS_BAR_MULTIPLIER end

    if cacheKey then LevelMultiplierCache[cacheKey] = multiplier end
    Logger.log(string.format(

        "[PalBonds/Trust] [LEVEL-MULT] pal level=%d player level=%d gap=%d id=%s%s -> multiplier=%.2fx (bonding bar = %.0f)",
        palLevel, playerLevel, gap, tostring(charIdText), isBoss and " (BOSS: bar x2)" or "",
        multiplier, BONDING_TRIGGER_THRESHOLD_BASE * multiplier
    ))
    return multiplier
end

local function get_bonding_threshold(pal)
    local multiplier = Trust.ComputeLevelMultiplier(pal)
    if multiplier == nil or multiplier <= 0 then multiplier = 1.0 end
    return BONDING_TRIGGER_THRESHOLD_BASE * multiplier
end

local CAPTURE_DELAY_FIXED_MS = 5000
local function finish_capture_now(pal, key, point)

    local okReq, Capture = pcall(require, "Capture")
    if okReq and Capture.OnTrustMaxed then

        local st = key ~= nil and State[key] or nil
        local owner = st and st.owner
        if owner ~= nil and safe_call(function() return owner:IsValid() end) then
            PlayerRef.WithPlayer(owner, Capture.OnTrustMaxed, pal)
        else
            Capture.OnTrustMaxed(pal)
        end
    end
end
local function wait_for_animation_then_capture(pal, key, point)
    Logger.log(string.format(
        "[PalBonds/Trust] %s — waiting a flat %.1fs for the real Feed/Happy animation sequence before capturing (see hundred-and-ninety-ninth pass for why this is a fixed delay, not a detected signal)",
        tostring(key), CAPTURE_DELAY_FIXED_MS / 1000
    ))
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(CAPTURE_DELAY_FIXED_MS, function()
            local stillValid = safe_call(function() return pal:IsValid() end)
            if not stillValid then
                Logger.log("[PalBonds/Trust] " .. tostring(key) .. " went invalid while waiting for its animation to finish before capture — aborting the delayed capture entirely")
                return
            end
            finish_capture_now(pal, key, point)
        end)
    end)
    if not ok then
        Logger.log("[PalBonds/Trust] ExecuteInGameThreadWithDelay failed while waiting to capture " .. tostring(key) .. " — capturing immediately instead")
        finish_capture_now(pal, key, point)
    end
end
local function maybe_trigger_capture(pal, st, key, point)
    if st.captureTriggered then return end
    local threshold = get_bonding_threshold(pal)
    if point == nil or point < threshold then return end

    local okReqGuard, CaptureGuard = pcall(require, "Capture")
    if okReqGuard and CaptureGuard.IsAlreadyOwned and CaptureGuard.IsAlreadyOwned(pal) then
        Logger.log(string.format(
            "[PalBonds/Trust] %s: friendship threshold reached but this Pal already has a real owner — refusing to fire the capture call",
            tostring(key)
        ))
        st.captureTriggered = true
        return
    end
    st.captureTriggered = true
    st.isFollowing = false
    Logger.log(string.format(
        "[PalBonds/Trust] %s reached %s friendship (bonding threshold %.1f) — trust threshold for sphere-less capture met, waiting for its current animation to finish before capturing",
        tostring(key), tostring(point), threshold
    ))
    wait_for_animation_then_capture(pal, key, point)
end

function Trust.OnInteractionSucceeded(pal)
    local okReqGuard, CaptureGuard = pcall(require, "Capture")
    if okReqGuard and CaptureGuard.IsAlreadyOwned and CaptureGuard.IsAlreadyOwned(pal) then
        Logger.log("[PalBonds/Trust] this Pal already has a real owner — skipping ALL trust/capture bookkeeping (this system is for wild Pals only)")
        return
    end
    local st, key = get_state(pal)
    if not st then
        Logger.log("[PalBonds/Trust] could not get a stable key for this Pal — skipping trust bookkeeping")
        return
    end
    local point = st.points or 0
    st.interactionCount = st.interactionCount + 1

    local threshold = get_bonding_threshold(pal)
    local ratio = (threshold and threshold > 0) and (point / threshold) or nil
    Logger.log(string.format(
        "[PalBonds/Trust] %s: interaction #%d recorded (trust %d / %s = %s)",
        key, st.interactionCount, point, tostring(threshold),
        ratio and string.format("%.0f%%", ratio * 100) or "unknown"
    ))

    if not st.isFollowing and not st.captureTriggered and ratio ~= nil and ratio >= FOLLOW_TRIGGER_RATIO then

        local joinsNow = not st.captureTriggered and ratio >= 1
        Trust.StartFollowing(pal, st, ratio, joinsNow)
    end

    if ratio ~= nil and ratio >= FRIENDLY_TRIGGER_RATIO and not st.isFollowing then
        local okPersonality, Personality = pcall(require, "Personality")
        if okPersonality and Personality.MaybeBecomeFriendlyByBar then
            local palId = safe_call(Personality.GetStableId, pal)
            Personality.MaybeBecomeFriendlyByBar(palId, pal)
        end
    end
    maybe_trigger_capture(pal, st, key, point)
end

function Trust.ForgetBonding(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil or State[key] == nil then return end
    State[key] = nil
    LevelMultiplierCache[key] = nil
    Logger.log("[PalBonds/Trust] " .. tostring(key) .. " joined the party — dropping its bonding state so the follower tick stops tracking it")
end

local pendingAbandoned = {}

function Trust.ResetForNewWorld(why)
    local quitting = type(why) == "string" and (why:find("Title") ~= nil or why:find("title") ~= nil)
    local n, following = 0, 0
    for _, st in pairs(State) do
        n = n + 1
        if st.isFollowing and not quitting and (st.ownerKey == nil or st.ownerKey == "local") then
            following = following + 1
            pendingAbandoned[#pendingAbandoned + 1] = { name = st.displayName, female = st.displayFemale }
        end
    end
    if quitting then pendingAbandoned = {} end
    State = {}
    LevelMultiplierCache = {}
    BossActorsSeen = {}
    briefFollow = {}
    Logger.log("[PalBonds/Trust] [WORLD-RESET] dropped " .. n .. " bonding record(s) from the old world" ..
        (following > 0 and (" — " .. following .. " of them were following and are left behind (told when the world is back)") or ""))
end

function Trust.FlushWorldChangeAbandonments()
    local list = pendingAbandoned
    pendingAbandoned = {}
    if #list == 0 then return 0 end
    if not trigger_enabled("abandoned") then
        Logger.log("[PalBonds/Trust] [WORLD-RESET] abandonment is switched off — " .. #list ..
            " follower(s) were left behind and the player is not told")
        return 0
    end
    local okCap, Capture = pcall(require, "Capture")
    if not (okCap and Capture and Capture.NotifyBondLostByName) then return 0 end
    for _, e in ipairs(list) do
        safe_call(Capture.NotifyBondLostByName, e.name, "abandoned", e.female)
    end
    Logger.log("[PalBonds/Trust] [WORLD-RESET] told the player about " .. #list ..
        " follower(s) left behind by the loading screen")
    return #list
end

function Trust.TogglePassiveFriendshipGain(ownerKey)
    ownerKey = ownerKey or "local"
    if passiveGainOffBy[ownerKey] then passiveGainOffBy[ownerKey] = nil else passiveGainOffBy[ownerKey] = true end
    local nowOn = not passiveGainOffBy[ownerKey]
    Logger.log("[PalBonds/Trust] [PASSIVE-TOGGLE] passive friendship gain is now " ..
        (nowOn and "ON" or "OFF") .. " for " .. (ownerKey == "local" and "this player" or "a remote player") ..
        " (" .. tostring(require("Settings").Get("KeyPassiveGain")) ..
        "; session-only, back to your setting on the next launch)")
    return nowOn
end
function Trust.IsPassiveGainEnabled(ownerKey)
    return not passiveGainOffBy[ownerKey or "local"]
end
function Trust.GetFollowingSnapshot()
    local snapshot = {}
    for _, st in pairs(State) do
        if st.isFollowing and st.pal then
            local point = st.points or 0

            local threshold = get_bonding_threshold(st.pal)
            local ratio = point / threshold
            if ratio < 0 then ratio = 0 end
            if ratio > 1 then ratio = 1 end
            snapshot[#snapshot + 1] = {
                pal = st.pal,
                ratio = ratio,
                point = point,
                threshold = threshold,
            }
        end
    end
    return snapshot
end

remote_owner_pawn = function(st)
    if st == nil or st.ownerKey == nil or st.ownerKey == "local" then return nil end
    local ctrl = st.ownerCtrl
    if ctrl ~= nil then
        if not safe_call(function() return ctrl:IsValid() end) then return nil, "gone" end
        local pawn = safe_call(function() return ctrl.Pawn end)
        if pawn ~= nil and safe_call(function() return pawn:IsValid() end) then
            st.ownerPawn = pawn
            return pawn
        end
        return nil, "away"
    end
    local pawn = st.ownerPawn
    if pawn ~= nil and safe_call(function() return pawn:IsValid() end) then return pawn end
    return nil, "gone"
end

owner_player = function(st)
    if st ~= nil and st.ownerKey ~= nil and st.ownerKey ~= "local" then
        return (remote_owner_pawn(st))
    end
    return find_player and find_player() or nil
end

as_owner = function(st, fn)
    local pawn = remote_owner_pawn(st)
    if pawn ~= nil then return PlayerRef.WithPlayer(pawn, fn) end
    return fn()
end

function Trust.GetOwner(palActor)
    local key = get_key(palActor)
    local st = key ~= nil and State[key] or nil
    return (remote_owner_pawn(st))
end

function Trust.GetOwnerKey(palActor)
    local key = get_key(palActor)
    local st = key ~= nil and State[key] or nil
    return st and st.ownerKey or nil
end

local TIER_BOND_SETTING = {
    normal = "BondNormal", friendly = "BondCurious", escape = "BondTimid",
    notinterested = "BondAloof", warlike = "BondGrumpy",
    warlike_anyway = "BondHostile", kill_all = "BondFeral",
}

function Trust.PersonalityMayBond(palActor)
    if palActor == nil then return true end
    local okP, Personality = pcall(require, "Personality")
    if not (okP and Personality and Personality.GetStableId and Personality.GetDisposition) then return true end
    local palId = safe_call(Personality.GetStableId, palActor)
    if palId == nil then return true end
    local disposition = safe_call(Personality.GetDisposition, palId)
    local setting = disposition ~= nil and TIER_BOND_SETTING[disposition] or nil
    if setting == nil then return true end
    local on = true
    pcall(function() on = require("Settings").Get(setting) ~= 0 end)
    return on
end

function Trust.MayBond(palActor)
    if not Trust.PersonalityMayBond(palActor) then return false end
    local key = get_key(palActor)
    local st = key ~= nil and State[key] or nil
    if st == nil or st.ownerKey == nil then return true end
    return st.ownerKey == (PlayerRef.CurrentOwnerKey and PlayerRef.CurrentOwnerKey() or "local")
end

function Trust.GetPoints(palActor)
    local key = get_key(palActor)
    local st = key ~= nil and State[key] or nil
    return st and st.points or 0
end

function Trust.AddPoints(palActor, amount, label)
    if palActor == nil or type(amount) ~= "number" then return nil end
    local okReqGuard, CaptureGuard = pcall(require, "Capture")
    if okReqGuard and CaptureGuard.IsAlreadyOwned and CaptureGuard.IsAlreadyOwned(palActor) then
        Logger.log("[PalBonds/Trust] [POINTS] " .. tostring(label) .. ": this Pal already has a real owner — no points")
        return nil
    end

    if not Trust.PersonalityMayBond(palActor) then
        Logger.log("[PalBonds/Trust] [POINTS] " .. tostring(label) ..
            ": this Pal's personality is switched off for bonding — no points")
        return nil
    end
    local st, key = get_state(palActor)
    if not st then return nil end

    if st.ownerKey == nil and amount > 0 then
        local acting = PlayerRef.Acting and PlayerRef.Acting() or nil
        st.ownerKey = PlayerRef.OwnerKey and PlayerRef.OwnerKey(acting) or "local"
        if acting ~= nil then
            st.ownerPawn = acting
            st.ownerCtrl = safe_call(function() return acting.Controller end)
        end
    end
    local before = st.points or 0
    local after = before + amount
    if after < 0 then after = 0 end
    st.points = after

    if after <= 0 then
        st.ownerKey, st.ownerPawn, st.ownerCtrl = nil, nil, nil
    end
    return before, after
end

function Trust.GetBarRatio(palActor)
    local view = guest_view()
    if view then return view.Ratio(palActor) end
    local key = get_key(palActor)
    local st = key ~= nil and State[key] or nil
    if st == nil then return 0 end
    local threshold = get_bonding_threshold(palActor)
    if threshold == nil or threshold <= 0 then return 0 end
    local ratio = (st.points or 0) / threshold
    if ratio > 1 then ratio = 1 end
    if ratio < 0 then ratio = 0 end
    return ratio
end

local function on_became_bonded(pal, st, quiet)
    local okCapName, CaptureName = pcall(require, "Capture")
    if not (okCapName and CaptureName) then return end
    if CaptureName.ResolveDisplayName then
        st.displayName = safe_call(CaptureName.ResolveDisplayName, pal)
        st.displayFemale = CaptureName.IsFemale and safe_call(CaptureName.IsFemale, pal) == true
    end
    if not quiet and CaptureName.NotifyStartedFollowing then
        safe_call(CaptureName.NotifyStartedFollowing, st.displayName, st.displayFemale)
    end
end

function Trust.StartFollowing(pal, st, ratio, quiet)
    st = st or (select(1, get_state(pal)))
    if not st or st.isFollowing then return end
    st.isFollowing = true
    on_became_bonded(pal, st, quiet)
    Logger.log(string.format(
        "[PalBonds/Trust] bonding bar crossed %.0f%% (ratio=%s) — this Pal should now start following the player",
        FOLLOW_TRIGGER_RATIO * 100, ratio and string.format("%.2f", ratio) or "unknown"
    ))
    local okReq, Combat = pcall(require, "Combat")
    if okReq and Combat.StartFollowing then
        Combat.StartFollowing(pal)
    end
end

function Trust.StopFollowing(pal, reason)
    local st = select(1, get_state(pal))
    if st then st.isFollowing = false end
    Logger.log("[PalBonds/Trust] follow stopped: " .. tostring(reason))
    local okReq, Combat = pcall(require, "Combat")
    if okReq and Combat.StopFollowing then
        Combat.StopFollowing(pal)
    end
end

local BRIEF_FOLLOW_MIN_SECONDS = 3.0
local BRIEF_FOLLOW_MAX_SECONDS = 15.0
local BRIEF_FOLLOW_POLL_MS = 500

function Trust.IsBriefFollowing(pal)
    local key = get_key(pal)
    return key ~= nil and briefFollow[key] ~= nil
end

function Trust.StartBriefFollow(pal, hatesPlayer, onDone)
    local st, key = get_state(pal)
    if not st or st.isFollowing then return false end
    st.isFollowing = true
    local token = {}
    briefFollow[key] = token
    Logger.log("[PalBonds/Trust] [BRIEF-FOLLOW] " .. tostring(key) .. " reached Friendly — following briefly so it lets go of its anger")
    local okReq, Combat = pcall(require, "Combat")
    if okReq and Combat.StartFollowing then
        Combat.StartFollowing(pal)
    end
    local startedAt = os.clock()
    local function finish(calmed, elapsed, stayed)
        if onDone then safe_call(onDone, calmed, elapsed, stayed) end
    end
    local function check()
        if briefFollow[key] ~= token then return end
        if State[key] == nil or not safe_call(function() return pal:IsValid() end) then
            briefFollow[key] = nil
            return
        end
        if not st.isFollowing then

            briefFollow[key] = nil
            return
        end
        local elapsed = os.clock() - startedAt
        local calmed = not (hatesPlayer and safe_call(hatesPlayer, pal))
        if (calmed and elapsed >= BRIEF_FOLLOW_MIN_SECONDS) or elapsed >= BRIEF_FOLLOW_MAX_SECONDS then
            briefFollow[key] = nil
            local point = st.points or 0
            local threshold = get_bonding_threshold(pal)
            local ratio = (threshold and threshold > 0) and (point / threshold) or nil
            if ratio ~= nil and ratio >= FOLLOW_TRIGGER_RATIO then
                Logger.log(string.format("[PalBonds/Trust] [BRIEF-FOLLOW] %s — bar is at %.0f%% now, so it keeps following (calm=%s after %.1fs)",
                    tostring(key), ratio * 100, tostring(calmed), elapsed))
                on_became_bonded(pal, st)
                finish(calmed, elapsed, true)
                return
            end
            Logger.log(string.format("[PalBonds/Trust] [BRIEF-FOLLOW] %s — released after %.1fs, %s",
                tostring(key), elapsed, calmed and "NO LONGER angry at the player" or "STILL angry at the player (time limit)"))
            Trust.StopFollowing(pal, "brief Friendly follow over")
            finish(calmed, elapsed, false)
            return
        end
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(BRIEF_FOLLOW_POLL_MS, function() safe_call(check) end)
        end)
        if not ok then briefFollow[key] = nil end
    end
    check()
    return true
end

local function on_follower_lost_all_trust(pal, reason)
    local kindNow = (type(reason) == "string" and reason:find("far")) and "abandoned" or "betrayed"
    if not trigger_enabled(kindNow) then
        local st = get_state(pal)
        if st ~= nil and (st.points or 0) < TRIGGER_OFF_FLOOR then
            st.points = TRIGGER_OFF_FLOOR
        end
        Logger.log("[PalBonds/Trust] " .. kindNow ..
            " is switched off in the settings — the bond survives (" .. tostring(reason) .. ")")
        return
    end
    Trust.StopFollowing(pal, reason)
    local okReq, Capture = pcall(require, "Capture")
    if okReq and Capture.OnTrustLost then

        local kind = (type(reason) == "string" and reason:find("far")) and "abandoned" or "betrayed"
        Capture.OnTrustLost(pal, kind)
    end
end

local UNBONDED_HIT_DEDUPE_SECONDS = 1.0
local function on_unbonded_pal_hit_by_player(pal, st, key)
    local now = os.clock()
    if st.lastUnbondedHitAt ~= nil and (now - st.lastUnbondedHitAt) < UNBONDED_HIT_DEDUPE_SECONDS then return end
    st.lastUnbondedHitAt = now

    if briefFollow[key] ~= nil then

        briefFollow[key] = nil
        Trust.StopFollowing(pal, "hit by the player during its calm-down")
    end

    local point = st.points or 0
    st.points = 0
    Logger.log(string.format(
        "[PalBonds/Trust] [UNBONDED-HIT] the player hit %s below 50%% — trust %d -> 0 (no bond, so no betrayal)",
        tostring(key), point))

    local okP, Personality = pcall(require, "Personality")
    if okP and Personality and Personality.RevertForgiveness then
        local palId = safe_call(Personality.GetStableId, pal)
        safe_call(Personality.RevertForgiveness, palId, pal)
    end
end

function Trust.OnFollowerDamaged(pal, attackerIsPlayer)
    local key = safe_call(function() return pal:GetFullName() end)
    local st = key ~= nil and State[key] or nil
    if not st then return end

    if attackerIsPlayer and not trigger_enabled("betrayed") then return end

    if st.captureTriggered then return end

    local okCapFled, CaptureFled = pcall(require, "Capture")
    if okCapFled and CaptureFled and CaptureFled.HasPermanentlyFled
        and safe_call(function() return CaptureFled.HasPermanentlyFled(pal) end) then
        return
    end

    if attackerIsPlayer and (not st.isFollowing or briefFollow[key] ~= nil) then
        on_unbonded_pal_hit_by_player(pal, st, key)
        return
    end
    if not st.isFollowing or not attackerIsPlayer then return end
    do

        local point = st.points or 0
        local threshold = get_bonding_threshold(pal) or BONDING_TRIGGER_THRESHOLD_BASE
        local penalty = math.ceil(threshold * PLAYER_HIT_PENALTY_FRACTION)
        if point - penalty > 0 then
            st.points = point - penalty
            Logger.log(string.format(
                "[PalBonds/Trust] the player hit a bonding Pal — trust %d -> %d (-%d, %.0f%% of its %d bar). The bond survives, for now.",
                point, point - penalty, penalty, PLAYER_HIT_PENALTY_FRACTION * 100, threshold
            ))

            local nowShaken = os.clock()
            if (nowShaken - (st.lastShakenToastAt or -99)) > 4.0 then
                st.lastShakenToastAt = nowShaken
                local okCap, CaptureMod = pcall(require, "Capture")
                if okCap and CaptureMod and CaptureMod.NotifyTrustShaken then
                    safe_call(function() CaptureMod.NotifyTrustShaken(pal) end)
                end
            end
            return
        end
        Logger.log(string.format("[PalBonds/Trust] BETRAYAL — the player hit this bonding Pal once too often (had %d points, penalty %d) — trust is gone", point, penalty))
        st.points = 0
        on_follower_lost_all_trust(pal, "hit by the player directly (betrayal)")
    end
end

local function forget_despawned_pals()
    for key, st in pairs(State) do
        local alive = st.pal ~= nil and safe_call(function() return st.pal:IsValid() end) == true
        if not alive then
            local wasBonded = st.isFollowing and briefFollow[key] == nil
            if st.isFollowing then
                local okC, CombatD = pcall(require, "Combat")
                if okC and CombatD and CombatD.ForgetDespawnedFollower then
                    safe_call(CombatD.ForgetDespawnedFollower, key)
                end
            end
            State[key] = nil
            LevelMultiplierCache[key] = nil
            driftingSince[key] = nil
            briefFollow[key] = nil
            Logger.log("[PalBonds/Trust] [DESPAWN] " .. tostring(key) .. " left the world" ..
                (wasBonded and " while following" or "") .. " — its record (" ..
                tostring(st.points or 0) .. " points) is forgotten")
            if wasBonded and trigger_enabled("abandoned") then
                local okCap, CaptureD = pcall(require, "Capture")
                if okCap and CaptureD and CaptureD.NotifyBondLostByName then
                    safe_call(CaptureD.NotifyBondLostByName, st.displayName, "abandoned", st.displayFemale)
                end
            end
        end
    end
end

local tick_follower_group

local function release_bonds_of_departed_players()
    for key, st in pairs(State) do
        if st.ownerKey ~= nil and st.ownerKey ~= "local" then
            local pawn, why = remote_owner_pawn(st)
            if pawn == nil and why == "gone" then
                Logger.log("[PalBonds/Trust] [COOP] " .. tostring(key) ..
                    " — its player left the world: bond released, the Pal is free again")
                if st.isFollowing and st.pal and safe_call(function() return st.pal:IsValid() end) then
                    safe_call(function() Trust.StopFollowing(st.pal, "its player left the world") end)
                end
                st.isFollowing = false
                st.points = 0
                st.ownerKey, st.ownerPawn, st.ownerCtrl = nil, nil, nil
            end
        end
    end
end

local function tick_followers()

    if we_are_a_guest() then return end

    local okShut, CombatShut = pcall(require, "Combat")
    if okShut and CombatShut and CombatShut.IsShuttingDown and CombatShut.IsShuttingDown() then
        return
    end
    forget_despawned_pals()
    release_bonds_of_departed_players()

    local groups = {}
    for _, st in pairs(State) do
        if st.isFollowing and st.pal then groups[st.ownerKey or "local"] = st end
    end
    for groupKey, sample in pairs(groups) do
        if groupKey == "local" then
            safe_call(tick_follower_group, "local")
        else
            local pawn = remote_owner_pawn(sample)
            if pawn ~= nil then
                safe_call(function() PlayerRef.WithPlayer(pawn, tick_follower_group, groupKey) end)
            end
        end
    end
end

tick_follower_group = function(groupKey)
    local player = find_player()
    local playerLoc = player and safe_call(function() return player:K2_GetActorLocation() end)
    local okReq, Combat = pcall(require, "Combat")
    for key, st in pairs(State) do
        if st.isFollowing and st.pal and (st.ownerKey or "local") == groupKey then
            local stillValid = safe_call(function() return st.pal:IsValid() end)
            if stillValid then
                st.tickCount = st.tickCount + 1

                local palIsDead = safe_call(function()
                    local comp = st.pal.CharacterParameterComponent
                    if comp == nil or not comp:IsValid() then return nil end
                    local dead = safe_call(function() return comp:IsDead() end)
                    if dead == true then return true end
                    local dying = safe_call(function() return comp:IsDying() end)
                    if dying == true then return true end
                    return false
                end)
                local endedThisPass = false
                if palIsDead == true and not st.deathHandled then
                    st.deathHandled = true
                    endedThisPass = true
                    Logger.log("[PalBonds/Trust] " .. tostring(key) ..
                        " died while bonded — ending the bond as a death, not as a drift")
                    Trust.StopFollowing(st.pal, "died")
                    local okCap, CaptureMod = pcall(require, "Capture")
                    if okCap and CaptureMod and CaptureMod.OnTrustLost then
                        CaptureMod.OnTrustLost(st.pal, "died")
                    end
                end

                do
                    local rate = safe_call(function()
                        local comp = st.pal.CharacterParameterComponent
                        if comp == nil or not comp:IsValid() then return nil end
                        return comp:GetHPRate()
                    end)
                    if type(rate) == "number" then
                        local prev = st.lastHPRate
                        st.lastHPRate = rate

                        if prev ~= nil and rate < prev - 0.01 then

                        end
                    end
                end
                local lostAllTrust = false
                if playerLoc and not endedThisPass then
                    local palLoc = safe_call(function() return st.pal:K2_GetActorLocation() end)
                    if palLoc then
                        local dx, dy, dz = palLoc.X - playerLoc.X, palLoc.Y - playerLoc.Y, palLoc.Z - playerLoc.Z
                        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                        local fightingNow = false
                        local fightingWhy, fightingWith = nil, nil
                        if okReq and Combat and Combat.IsBusyFighting then
                            local okBusy, busy, why, with = pcall(Combat.IsBusyFighting, st.pal)
                            fightingNow = okBusy and busy == true
                            fightingWhy = okBusy and why or ("check failed: " .. tostring(busy))
                            fightingWith = okBusy and with or nil
                        elseif okReq and Combat and Combat.IsSuspendedForCombat then
                            fightingNow = safe_call(function()
                                return Combat.IsSuspendedForCombat(st.pal)
                            end) == true
                            fightingWhy = "follow suspended for a fight"
                        end

                        local pastLeash = dist > MAX_FOLLOW_DISTANCE
                        if not pastLeash then
                            if driftingSince[key] ~= nil then
                                driftingSince[key] = nil
                                Logger.log(string.format(
                                    "[PalBonds/Trust] %s made it back inside the leash (%.0f units) — the bond is safe",
                                    key, dist))
                            end
                        end

                        if pastLeash and fightingNow then
                            driftingSince[key] = nil
                            Logger.log(string.format(
                                "[PalBonds/Trust] %s is %.0f units away (limit %.0f) but is away FIGHTING — trust untouched until the fight ends",
                                key, dist, MAX_FOLLOW_DISTANCE
                            ))
                        elseif pastLeash and driftingSince[key] == nil then

                            driftingSince[key] = os.clock()
                            Logger.log(string.format(
                                "[PalBonds/Trust] %s is %.0f units away (limit %.0f) — being marched back; it has %.0fs to return before the bond breaks",
                                key, dist, MAX_FOLLOW_DISTANCE, DRIFT_GRACE_SECONDS
                            ))
                        elseif pastLeash and (os.clock() - driftingSince[key]) < DRIFT_GRACE_SECONDS then

                        elseif pastLeash then
                            driftingSince[key] = nil
                            Logger.log(string.format(
                                "[PalBonds/Trust] %s is %.0f units away (limit %.0f) and did not come back within %.0fs — losing all trust",
                                key, dist, MAX_FOLLOW_DISTANCE, DRIFT_GRACE_SECONDS
                            ))

                            if EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS then
                                Logger.log("[PalBonds/Trust] drift recorded but trust NOT wiped — experimental follow mode (see the two-hundred-and-twenty-fifth pass)")
                            else
                                st.points = 0
                            end
                            lostAllTrust = true

                        end

                        if (not lostAllTrust) and okReq and st.isFollowing then

                            if Combat.IssueFollowMoveOrder then
                                Combat.IssueFollowMoveOrder(st.pal, playerLoc, player)
                            end
                        end
                    end
                end
                if lostAllTrust then
                    on_follower_lost_all_trust(st.pal, "too far from player")
                elseif passiveGainOffBy[groupKey or "local"] then

                elseif briefFollow[key] ~= nil then

                else

                    st.points = (st.points or 0) + PASSIVE_FRIENDSHIP_PER_TICK

                    maybe_trigger_capture(st.pal, st, key, st.points)
                end
            end
        end
    end
end

find_fighter = function(anyFollowing, attackerName, defenderName, attacker, defender)
    if not anyFollowing then return nil, nil end
    local function is_player(name)
        if name == nil then return nil end
        local lp = find_player()
        if lp ~= nil and find_player_name() == name then return lp end
        for _, st in pairs(State) do
            if st.ownerKey ~= nil and st.ownerKey ~= "local" then
                local op = remote_owner_pawn(st)
                if op ~= nil and safe_call(function() return op:GetFullName() end) == name then return op end
            end
        end
        return nil
    end
    local a = is_player(attackerName)
    if a ~= nil then return a, defender end
    local d = is_player(defenderName)
    if d ~= nil then return d, attacker end
    return nil, nil
end

as_player = function(player, fn, ...)
    if PlayerRef.IsRemote and PlayerRef.IsRemote(player) then
        return PlayerRef.WithPlayer(player, fn, ...)
    end
    return fn(...)
end

function Trust.Init()
    Logger.log("[PalBonds/Trust] real hooks active — tracking interaction counts, follow state and PalBonds' own trust points")

    local okDamageWatch = pcall(function()

        local lastBetrayalKey, lastBetrayalAt = nil, 0
        local loggedBetrayalHookFired = false

        local okBetray, errBetray = pcall(function()
            RegisterHook("/Script/Pal.PalDamageReactionComponent:OnProcessedActualDamageDelegate__DelegateSignature", function(Context, Attacker, Defender, ActualDamage)
                if world_is_closing() or we_are_a_guest() then return end
                Logger.trace("dmg.reaction")

                if next(State) == nil then return end
                safe_call(function()
                    local victim = hook_get(Defender)
                    if victim == nil or not victim:IsValid() then return end
                    local key = safe_call(function() return victim:GetFullName() end)
                    if key == nil or State[key] == nil then return end

                    local hitter = hook_get(Attacker)
                    if hitter == nil or not hitter:IsValid() then return end

                    local owner = owner_player(State[key])
                    local playerName = owner and safe_call(function() return owner:GetFullName() end)
                    local hitterName = safe_call(function() return hitter:GetFullName() end)
                    if playerName == nil or hitterName ~= playerName then return end
                    if not loggedBetrayalHookFired then
                        loggedBetrayalHookFired = true
                        Logger.log("[PalBonds/Trust] [BETRAYAL-HOOK] this hook FIRES on this build — the delegate route works (logged once)")
                    end

                    local now = os.clock()
                    if key == lastBetrayalKey and (now - lastBetrayalAt) < 0.5 then return end
                    lastBetrayalKey, lastBetrayalAt = key, now
                    Logger.log("[PalBonds/Trust] [BETRAYAL-HOOK] the player damaged a Pal that is bonding with them — " .. tostring(key))
                    as_owner(State[key], function() Trust.OnFollowerDamaged(victim, true) end)
                end)
            end)
        end)
        Logger.log("[PalBonds/Trust] [BETRAYAL-HOOK] RegisterHook(PalDamageReactionComponent:OnProcessedActualDamageDelegate) = " ..
            (okBetray and "OK" or ("FAILED: " .. tostring(errBetray) .. " — betrayal falls back to the hate hook, which misses followers whose Damaged_Player slot is Ignore")))
        RegisterHook("/Script/Pal.PalHate:DamageEvent", function(Context, DamageResult)
            if world_is_closing() or we_are_a_guest() then return end
            Logger.trace("dmg.hate")
            local result = hook_get(DamageResult)
            if result == nil then return end

            if next(State) == nil then
                local okEarly, CombatEarly = pcall(require, "Combat")
                local anyFollower = okEarly and CombatEarly and CombatEarly.HasAnyFollower
                    and CombatEarly.HasAnyFollower()
                if not anyFollower then return end
            end

            local defender = safe_call(function() return result.Defender end)
            local attacker = safe_call(function() return result.Attacker end)

            if not damage_event_is_ours(defender, attacker) then return end

            local damage = safe_call(function() return result.Damage end)
            local defenderName = safe_call(function() return defender and defender:GetFullName() end)
            local attackerName = safe_call(function() return attacker and attacker:GetFullName() end)

            do
                local aIsFollower = attackerName ~= nil and State[attackerName] ~= nil and State[attackerName].isFollowing
                local dIsFollower = defenderName ~= nil and State[defenderName] ~= nil and State[defenderName].isFollowing
                if aIsFollower and not dIsFollower then

                    local okSD, CombatSD = pcall(require, "Combat")
                    if okSD and CombatSD and CombatSD.NoteFollowerHit then
                        CombatSD.NoteFollowerHit(attackerName)
                    end
                end
                if aIsFollower and dIsFollower and attackerName ~= defenderName then
                    friendlyFireEvents = friendlyFireEvents + 1
                    local a = tostring(attackerName):match("([^%.]+)$") or tostring(attackerName)
                    local d = tostring(defenderName):match("([^%.]+)$") or tostring(defenderName)
                    if not friendlyFirePairLogged[a .. ">" .. d] then
                        friendlyFirePairLogged[a .. ">" .. d] = true
                        Logger.log("[PalBonds/Trust] [FRIENDLY-FIRE] " .. a .. " hit " .. d ..
                            " (first time for this pair; the per-fight total is reported when the fight ends)")
                    end
                end
            end
            do

                local okHas, CombatCheck = pcall(require, "Combat")

                local anyBonding = next(State) ~= nil
                local anyFollowing = anyBonding or (okHas and CombatCheck and CombatCheck.HasAnyFollower and CombatCheck.HasAnyFollower())

                local player, enemy = find_fighter(anyFollowing, attackerName, defenderName, attacker, defender)
                if player then
                    if enemy ~= nil then

                        local okCombatReq, CombatMod = pcall(require, "Combat")
                        if okCombatReq and CombatMod and CombatMod.OnPlayerCombatTarget then
                            safe_call(function() as_player(player, CombatMod.OnPlayerCombatTarget, enemy, player) end)
                        end
                    end
                end
            end

            if defenderName and State[defenderName] then
                local defenderIsFollowing = State[defenderName].isFollowing

                local defSt = State[defenderName]
                local owner = owner_player(defSt)
                local playerName = owner and safe_call(function() return owner:GetFullName() end)
                local attackerIsPlayer = (attackerName ~= nil and playerName ~= nil and attackerName == playerName)

                if attackerIsPlayer then
                    as_owner(defSt, function() Trust.OnFollowerDamaged(defSt.pal, true) end)
                elseif defenderIsFollowing then

                    local okSD, CombatSD = pcall(require, "Combat")
                    if okSD and CombatSD and CombatSD.OnFollowerAttacked then
                        safe_call(function() as_owner(defSt, function() CombatSD.OnFollowerAttacked(defSt.pal, attacker) end) end)
                    end

                    local st = State[defenderName]
                    st.thirdPartyHits = (st.thirdPartyHits or 0) + 1
                    local nowHit = os.clock()
                    if (nowHit - (st.lastThirdPartyLogAt or -99)) > THIRD_PARTY_DAMAGE_LOG_INTERVAL then
                        Logger.log(string.format(
                            "[PalBonds/Trust] following Pal was damaged by something other than the player — no trust penalty (%d hit(s) since the last line; a companion getting hit is expected now that it fights back)",
                            st.thirdPartyHits
                        ))
                        st.lastThirdPartyLogAt = nowHit
                        st.thirdPartyHits = 0
                    end
                end
            end
        end)
    end)
    if not okDamageWatch then
        Logger.log("[PalBonds/Trust] could not install DamageEvent watch hook (name may need adjusting)")
    end

    local tickEverLogged = false
    local function scheduleTick()
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(TICK_INTERVAL_MS, function()
                Logger.trace("follower tick (trust)")

                if not tickEverLogged then
                    tickEverLogged = true
                    Logger.log("[PalBonds/Trust] [TICK] game-thread tick fired (logged once — the tick is alive; further ticks stay silent unless a Pal is actually following)")
                end
                safe_call(tick_followers)
                scheduleTick()
            end)
        end)
        if not ok then
            Logger.log("[PalBonds/Trust] ExecuteInGameThreadWithDelay failed to schedule the follower tick")
        end
    end
    scheduleTick()
end
return Trust
