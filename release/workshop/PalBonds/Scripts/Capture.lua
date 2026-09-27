local Logger = require("Logger")
local Combat = require("Combat")

local Personality = require("Personality")

local UEHelpers = require("UEHelpers")

local PAL_LOCALIZE_CATEGORY_MONSTER_NAME = 4
local Capture = {}
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local PalUtilityCDO = nil
local function get_pal_utility()
    if PalUtilityCDO then return PalUtilityCDO end
    PalUtilityCDO = safe_call(function()
        return StaticFindObject("/Script/Pal.Default__PalUtility")
    end)
    return PalUtilityCDO
end

local function we_are_a_guest()
    local ok, Session = pcall(require, "Session")
    if not (ok and Session and Session.IsGuest) then return false end
    local okAsk, guest = pcall(Session.IsGuest)
    return okAsk and guest == true
end

function Capture.TryDirectCapture(pal, player)
    if we_are_a_guest() then
        Logger.log("[PalBonds/Capture] [GUEST] this world belongs to somebody else — the join is the server's to make, refusing (see Session.lua)")
        return false
    end
    local palName = safe_call(function() return pal:GetFullName() end)
    if pal == nil or not pal:IsValid() then
        return
    end
    if player == nil or not player:IsValid() then
        return
    end
    local utility = get_pal_utility()
    if utility == nil then
        return
    end

    local callOk, callErr = pcall(function()
        utility:PalCaptureSuccess(player, pal)
    end)
end

local function resolve_toast_widget_class(manager)
    local classMap = safe_call(function() return manager.OverrideClassMap end)
    if classMap == nil then return nil end
    local chosen = nil
    pcall(function()
        classMap:ForEach(function(_, valueParam)
            pcall(function()
                local okGet, value = pcall(function() return valueParam:get() end)
                if not okGet then value = valueParam end
                if value ~= nil then
                    local fullName = safe_call(function() return value:GetFullName() end)
                    if type(fullName) == "string" and fullName:find("BlinkedLog", 1, true) then
                        chosen = value
                    end
                end
            end)
        end)
    end)
    return chosen
end

local function to_lua_string(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local s = safe_call(function() return v:ToString() end)
    if type(s) == "string" then return s end

    return nil
end

local function reject_if_key_echo(asString, id)
    if asString == nil or asString == "" then return nil end
    if asString == id then return nil end
    if asString:find("^PAL_NAME_") ~= nil then return nil end
    return asString
end

local function lookup_localized_name(player, textLibrary, masterData, id)
    local key = safe_call(function() return UEHelpers.FindOrAddFName("PAL_NAME_" .. id) end)
    if key == nil then return nil end
    local localized = safe_call(function()
        return masterData:GetLocalizedText(player, PAL_LOCALIZE_CATEGORY_MONSTER_NAME, key)
    end)
    local asString = to_lua_string(localized and safe_call(function()
        return textLibrary:Conv_TextToString(localized)
    end))
    return reject_if_key_echo(asString, id)
end

local function name_lookup_candidates(rawId)
    local candidates = { rawId }
    local current = rawId
    for _ = 1, 3 do
        local rest = current:match("^[A-Z][A-Z0-9]*_(.+)$")
        if rest == nil or rest == "" then break end
        candidates[#candidates + 1] = rest
        current = rest
    end
    return candidates
end

local function prettify_raw_id(rawId)
    local base = rawId
    for _ = 1, 3 do
        local rest = base:match("^[A-Z][A-Z0-9]*_(.+)$")
        if rest == nil or rest == "" then break end
        base = rest
    end
    base = base:gsub("_", " ")
    local spaced = base:gsub("(%l)(%u)", "%1 %2")
    return spaced
end

local charIdByName = {}

local function localized_name_for_id(rawId, player)
    if type(rawId) ~= "string" or rawId == "" then return nil end
    local textLibrary = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
    local masterData = safe_call(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
    if textLibrary ~= nil and masterData ~= nil then
        for _, candidate in ipairs(name_lookup_candidates(rawId)) do
            local found = lookup_localized_name(player, textLibrary, masterData, candidate)
            if found ~= nil then return found end
        end
    end
    return prettify_raw_id(rawId)
end

local function resolve_pal_display_name(pal, player)
    local palName = nil
    safe_call(function()
        if pal == nil then return end
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return end
        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return end
        local charId = param:GetCharacterID()
        if charId == nil then return end
        local textLibrary = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
        local masterData = safe_call(function() return StaticFindObject("/Script/Pal.Default__PalMasterDataTablesUtility") end)
        if textLibrary ~= nil and masterData ~= nil then

            local rawId = to_lua_string(safe_call(function() return charId:ToString() end))
            if rawId then
                for _, candidate in ipairs(name_lookup_candidates(rawId)) do
                    local found = lookup_localized_name(player, textLibrary, masterData, candidate)
                    if found ~= nil then
                        if candidate ~= rawId then
                            Logger.log("[PalBonds/Capture] [NOTIFY] '" .. rawId ..
                                "' has no name entry of its own — resolved via base species '" ..
                                candidate .. "'")
                        end
                        palName = found
                        charIdByName[found] = rawId
                        return
                    end
                end
            end
        end

        local raw = to_lua_string(safe_call(function() return charId:ToString() end))
        if raw ~= nil and raw ~= "" then
            palName = prettify_raw_id(raw)
            charIdByName[palName] = raw
            Logger.log("[PalBonds/Capture] [NOTIFY] no localised name for '" .. raw ..
                "' under any candidate id — using the prettified id '" .. tostring(palName) .. "'")
        end
    end)
    Logger.log("[PalBonds/Capture] [NOTIFY] resolved display name BEFORE capture = " .. tostring(palName))
    return palName
end

local toastFailuresLogged = {}
local function toast_failed(why)
    if not toastFailuresLogged[why] then
        toastFailuresLogged[why] = true
        Logger.log("[PalBonds/Capture] [NOTIFY] the message could not be shown: " .. why ..
            " (logged once per reason per session)")
    end
    return false
end

local function show_log(player, message, tone, key, name, female)
    if player == nil or not safe_call(function() return player:IsValid() end) then return false end
    local okRef, PlayerRef = pcall(require, "PlayerRef")
    if okRef and PlayerRef and PlayerRef.IsRemote and PlayerRef.IsRemote(player) then
        local okNet, Net = pcall(require, "Net")
        if okNet and Net and Net.SendToPlayer then
            if key ~= nil then
                return Net.SendToPlayer(player, "MSG", tostring(tone), key, name or "",
                    female and "1" or "0", (name and charIdByName[name]) or "") == true
            end
            return Net.SendToPlayer(player, "TOAST", tostring(tone), tostring(message)) == true
        end
        return false
    end

    local utility = get_pal_utility()
    if utility == nil then return toast_failed("no PalUtility") end
    local manager = safe_call(function() return utility:GetLogManager(player) end)
    if manager == nil then return toast_failed("GetLogManager gave nothing for this player") end
    local widgetClass = resolve_toast_widget_class(manager)
    if widgetClass == nil then return toast_failed("the toast widget class could not be resolved") end
    local textLibrary = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
    if textLibrary == nil then return toast_failed("no KismetTextLibrary") end
    local text = safe_call(function() return textLibrary:Conv_StringToText(tostring(message)) end)
    if text == nil then return toast_failed("the message could not be converted to text") end
    local shown = pcall(function()
        manager:AddLog(1, text, { OverrideWidgetClass = widgetClass, LogToneType = tone })
    end)
    if not shown then return toast_failed("AddLog itself failed") end
    return true
end

Capture.ShowLogFor = show_log

function Capture.NotifyJoined(pal, player, preResolvedName, preResolvedFemale)
    local ok, err = pcall(function()

        local palName = preResolvedName
        local Locale = require("Locale")
        local message
        if palName then
            message = Locale.T("joined", { name = palName, female = preResolvedFemale })
        else
            message = Locale.T("joined_unnamed")
        end
        Logger.log("[PalBonds/Capture] [NOTIFY] join message: " .. message)
        show_log(player, message, 2, palName and "joined" or "joined_unnamed", palName, preResolvedFemale == true)
    end)
    if ok then
        Logger.log("[PalBonds/Capture] [NOTIFY] join toast shown")
    else
        Logger.log("[PalBonds/Capture] [NOTIFY] failed to show join toast (non-fatal, caught): " .. tostring(err))
    end
end

local function guid_is_zero(g)
    if g == nil then return true end
    return (g.A == 0) and (g.B == 0) and (g.C == 0) and (g.D == 0)
end
function Capture.IsAlreadyOwned(pal)
    local ok, result = pcall(function()
        if pal == nil or not pal:IsValid() then return true end
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return true end

        local isOtomoOk, isOtomo = pcall(function() return comp:IsOtomo() end)
        if isOtomoOk and isOtomo == true then return true end

        local campOk, campId = pcall(function() return comp:GetBaseCampId() end)
        if campOk and not guid_is_zero(campId) then return true end
        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return true end
        local ownerId = param.SaveParameter and param.SaveParameter.OwnerPlayerUId
        if ownerId == nil then return true end
        return not guid_is_zero(ownerId)
    end)
    if ok then return result end
    return true
end

local PermanentlyFled = {}

local JOIN_VFX_CANDIDATES = {
    "/Game/Pal/Effect/Common/PalCatch/NS_PalCatch_Success.NS_PalCatch_Success",
    "/Game/Pal/Effect/Common/Return/NS_Return.NS_Return",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalAppear.NS_PalAppear",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear01.NS_PalDisappear01",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear02.NS_PalDisappear02",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalCatch.NS_PalCatch",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear.NS_PalDisappear",
}

local JOIN_VFX_INDEX = 1
local JOIN_VFX_ASSET_PATH = JOIN_VFX_CANDIDATES[JOIN_VFX_INDEX]

local loggedJoinVfxOnce = false
local function spawn_niagara_at(pal, assetPath)
    safe_call(function()
        if pal == nil or not pal:IsValid() then return end
        local system = StaticFindObject(assetPath)
        if system == nil then
            if not loggedJoinVfxOnce then
                loggedJoinVfxOnce = true
                Logger.log("[PalBonds/Capture] [JOIN-VFX] could not resolve " .. assetPath ..
                    " — the asset may not be loaded yet (it loads when the game first plays it). Try again after a normal sphere capture, or switch to one of the alternates listed in the source.")
            end
            return
        end
        local niagaraLib = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
        if niagaraLib == nil then
            Logger.log("[PalBonds/Capture] [JOIN-VFX] could not resolve NiagaraFunctionLibrary — no effect played")
            return
        end
        local loc = safe_call(function() return pal:K2_GetActorLocation() end)
        if loc == nil then return end
        local comp = safe_call(function()
            return niagaraLib:SpawnSystemAtLocation(
                pal,
                system,
                loc,
                {Pitch = 0.0, Yaw = 0.0, Roll = 0.0},
                {X = 1.0, Y = 1.0, Z = 1.0},
                true,
                true,
                0,
                true
            )
        end)
        Logger.log("[PalBonds/Capture] [JOIN-VFX] spawned " .. assetPath ..
            " at the joining Pal — component=" .. tostring(comp ~= nil))
    end)
end

function Capture.RenderHostMessage(fields, player)
    local tone = tonumber(fields[1])
    if tone ~= 1 and tone ~= 2 then tone = 1 end
    local key = fields[2]
    if key == nil or key == "" then return nil end
    local Locale = require("Locale")
    local name = safe_call(function() return localized_name_for_id(fields[5], player) end)
    if name == nil and fields[3] ~= nil and fields[3] ~= "" then name = fields[3] end
    return tone, Locale.T(key, { name = name or Locale.T("a_pal"), female = fields[4] == "1" })
end

local play_join_light_for_host

function Capture.Init()

    local okNet, Net = pcall(require, "Net")
    if okNet and Net and Net.OnClient then
        Net.OnClient("JOINFX", function(fields) play_join_light_for_host(fields[1]) end)

        Net.OnClient("MSG", function(fields)
            local player = safe_call(function() return require("PlayerRef").Get() end)
            local tone, message = Capture.RenderHostMessage(fields, player)
            if message == nil then return end
            if show_log(player, message, tone) then
                Logger.log("[PalBonds/Capture] [NOTIFY] from the host: " .. tostring(message))
            end
        end)
        Net.OnClient("TOAST", function(fields)
            local tone = tonumber(fields[1])
            if tone ~= 1 and tone ~= 2 then tone = 1 end
            local message = fields[2]
            if message == nil or message == "" then return end
            local player = safe_call(function() return require("PlayerRef").Get() end)
            if show_log(player, message, tone) then
                Logger.log("[PalBonds/Capture] [NOTIFY] from the host: " .. tostring(message))
            end
        end)
    end

    Logger.log("[PalBonds/Capture] real trigger points wired (via Trust.lua) — sphere-less capture is now REAL (thirty-ninth pass), calls Capture.TryDirectCapture for real on OnTrustMaxed")
end

local JOIN_CELEBRATION_DELAY_MS = 2000

local function show_join_light_to_remote_owner(pal)
    local okRef, PlayerRef = pcall(require, "PlayerRef")
    if not okRef or PlayerRef == nil then return end
    local player = safe_call(function() return PlayerRef.Get() end)
    if player == nil or not (PlayerRef.IsRemote and PlayerRef.IsRemote(player)) then return end
    local palId = safe_call(function() return require("Personality").GetStableId(pal) end)
    if palId == nil then return end
    safe_call(function() require("Net").SendToPlayer(player, "JOINFX", palId) end)
end

play_join_light_for_host = function(palId)
    if palId == nil or palId == "" then return end
    local player = safe_call(function() return require("PlayerRef").Get() end)
    local origin = player and safe_call(function() return player:K2_GetActorLocation() end)
    if origin == nil then return end
    local pals = safe_call(function() return FindAllOf("PalCharacter") end)
    if not pals then return end
    for _, pal in ipairs(pals) do
        if safe_call(function() return pal:IsValid() end) then
            local loc = safe_call(function() return pal:K2_GetActorLocation() end)
            if loc then
                local dx, dy, dz = loc.X - origin.X, loc.Y - origin.Y, loc.Z - origin.Z
                if (dx * dx + dy * dy + dz * dz) <= 3000 * 3000 and
                   safe_call(function() return require("Personality").GetStableId(pal) end) == palId then
                    spawn_niagara_at(pal, JOIN_VFX_ASSET_PATH)
                    return
                end
            end
        end
    end
    Logger.log("[PalBonds/Capture] [JOIN-VFX] the host asked for the join light, but that Pal is no longer here")
end

local function play_join_celebration_then(pal, continueFn)
    local actionComp = safe_call(function() return pal.ActionComponent end)
    local actionCompValid = actionComp ~= nil and safe_call(function() return actionComp:IsValid() end)
    if actionCompValid then
        Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] playing Happy(38) on the newly-bonded Pal before the real capture NOW")
        local ok, err = pcall(function() actionComp:PlayActionByType(pal, 38) end)
        Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] Happy call returned — result=" .. (ok and "ok" or tostring(err)))
    else
        Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] no usable ActionComponent on the Pal — skipping the celebration reaction, capturing on the normal schedule")
        continueFn()
        return
    end

    local scheduled = pcall(function()
        ExecuteInGameThreadWithDelay(JOIN_CELEBRATION_DELAY_MS, function()
            spawn_niagara_at(pal, JOIN_VFX_ASSET_PATH)
            show_join_light_to_remote_owner(pal)
            continueFn()
        end)
    end)
    if not scheduled then
        Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] could not schedule the celebration delay — capturing immediately instead")
        continueFn()
    end
end

local JOIN_FRIENDSHIP_POINT_GRANT = require("Settings").Get("JoinBonus")

pcall(function()
    require("Settings").OnChange(function(key)
        if key ~= "JoinBonus" then return end
        JOIN_FRIENDSHIP_POINT_GRANT = require("Settings").Get("JoinBonus")
    end)
end)

local function is_boss_actor(pal)
    local full = safe_call(function() return pal:GetFullName() end)
    if type(full) ~= "string" then return false end
    local cls = (full:match("^(%S+)") or ""):upper()
    return cls:find("_BOSS", 1, true) ~= nil or cls:find("_GYM", 1, true) ~= nil or cls:find("_RAID", 1, true) ~= nil
end

local function register_player_hit_on_boss(pal, player)
    if not is_boss_actor(pal) then return false end
    local drc = safe_call(function() return pal.DamageReactionComponent end)
    if drc == nil or not safe_call(function() return drc:IsValid() end) then
        Logger.log("[PalBonds/Capture] [BOSS-CREDIT] the boss has no damage reaction component — the defeat will not be recorded")
        return false
    end
    local ok, err = pcall(function() drc:ForceDamageDelegateForCaptureBall(player) end)
    Logger.log("[PalBonds/Capture] [BOSS-CREDIT] told the game the player hit this boss, as a capture sphere does — " ..
        (ok and "ok" or ("FAILED: " .. tostring(err))))
    return ok
end
Capture.RegisterPlayerHitOnBoss = register_player_hit_on_boss

function Capture.OnTrustMaxed(pal)
    if we_are_a_guest() then return end
    local name = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format("[PalBonds/Capture] %s reached full trust — capturing for real (sphere-less)", tostring(name)))
    local player = safe_call(function() return require("PlayerRef").Get() end)
    if not player or not (safe_call(function() return player:IsValid() end)) then
        Logger.log("[PalBonds/Capture] no valid local player found — cannot capture, leaving Pal as a bonding-follower for now")
        return
    end

    local preResolvedDisplayName = resolve_pal_display_name(pal, player)

    local joinedId = safe_call(function() return Personality.GetStableId(pal) end)
    local joinedAddr = safe_call(function() return pal:GetAddress() end)
    local preResolvedFemale = Capture.IsFemale(pal)

    safe_call(function()
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return end
        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return end
        local before = safe_call(function() return param:GetFriendshipPoint() end)
        local ok = pcall(function() param:AddFriendShip(JOIN_FRIENDSHIP_POINT_GRANT, false) end)
        local after = safe_call(function() return param:GetFriendshipPoint() end)
        Logger.log(string.format(
            "[PalBonds/Capture] [JOIN-BONUS] joining Pal granted +%d friendship for bonding — %s -> %s (call=%s)",
            JOIN_FRIENDSHIP_POINT_GRANT, tostring(before), tostring(after), ok and "ok" or "FAILED"
        ))
    end)
    play_join_celebration_then(pal, function()
        local stillValid = safe_call(function() return pal:IsValid() end)
        if not stillValid then
            Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] Pal went invalid during the celebration delay — aborting the capture entirely")
            return
        end
        safe_call(function() register_player_hit_on_boss(pal, player) end)
        Capture.TryDirectCapture(pal, player)

        Capture.NotifyJoined(pal, player, preResolvedDisplayName, preResolvedFemale)

        Combat.StopFollowing(pal)

        safe_call(function()
            local okT, TrustMod = pcall(require, "Trust")
            if okT and TrustMod and TrustMod.ForgetBonding then TrustMod.ForgetBonding(pal) end
        end)
        local forgot = 0
        forgot = forgot + (safe_call(function() return Personality.ForgetJoinedPal(joinedId, name) end) or 0)
        forgot = forgot + (safe_call(function() return require("Indicator").ForgetJoinedPal(joinedId, joinedAddr) end) or 0)
        forgot = forgot + (safe_call(function() return require("Interaction").ForgetJoinedPal(joinedAddr) end) or 0)
        Logger.log(string.format("[PalBonds/Capture] [JOIN-CLEANUP] %s joined — dropped %d leftover reference(s) to its wild actor",
            tostring(name), forgot))
    end)
end

local function notify_bond_lost(pal, reason, knownName, knownFemale)
    pcall(function()
        local player = safe_call(function() return require("PlayerRef").Get() end)
        if player == nil or not safe_call(function() return player:IsValid() end) then return end
        local palName = knownName or resolve_pal_display_name(pal, player)
        local Locale = require("Locale")
        local who = palName or Locale.T("a_pal")
        local g = { name = who, female = (knownFemale == nil) and Capture.IsFemale(pal) or knownFemale }
        local message
        if reason == "betrayed" then
            message = Locale.T("betrayed", g)

        elseif reason == "died" then
            message = Locale.T("fell", g)
        else
            message = Locale.T("abandoned", g)
        end
        local key = (reason == "betrayed" and "betrayed") or (reason == "died" and "fell") or "abandoned"
        show_log(player, message, 1, key, palName, g.female == true)
        Logger.log("[PalBonds/Capture] [NOTIFY] bond-lost message: " .. message)
    end)
end

function Capture.ShowToast(message, key)
    pcall(function()
        local player = safe_call(function() return require("PlayerRef").Get() end)
        if player == nil or not safe_call(function() return player:IsValid() end) then return end
        show_log(player, message, 1, key)
        Logger.log("[PalBonds/Capture] [NOTIFY] " .. tostring(message))
    end)
end

function Capture.NotifyStartedFollowing(name, female)
    pcall(function()
        local player = safe_call(function() return require("PlayerRef").Get() end)
        if player == nil or not safe_call(function() return player:IsValid() end) then return end
        local Locale = require("Locale")
        local message = Locale.T("following", { name = name or Locale.T("a_pal"), female = female == true })
        show_log(player, message, 2, "following", name, female == true)
        Logger.log("[PalBonds/Capture] [NOTIFY] following message: " .. message)
    end)
end

function Capture.NotifyTrustShaken(pal)
    pcall(function()
        local player = safe_call(function() return require("PlayerRef").Get() end)
        if player == nil or not safe_call(function() return player:IsValid() end) then return end
        local palName = resolve_pal_display_name(pal, player)
        local Locale = require("Locale")
        local message = Locale.T("shaken", { name = palName or Locale.T("a_pal"), female = Capture.IsFemale(pal) })
        show_log(player, message, 1, "shaken", palName, Capture.IsFemale(pal))
        Logger.log("[PalBonds/Capture] [NOTIFY] trust-shaken message: " .. message)
    end)
end

function Capture.IsFemale(pal)
    if pal == nil then return false end
    return safe_call(function()
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return false end
        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return false end
        return tonumber(param:GetGenderType()) == 2
    end) == true
end

function Capture.ResolveDisplayName(pal)
    local player = safe_call(function() return require("PlayerRef").Get() end)
    return safe_call(function() return resolve_pal_display_name(pal, player) end)
end

function Capture.NotifyBondLostByName(name, reason, female)
    notify_bond_lost(nil, reason, name, female == true)
end

function Capture.OnTrustLost(pal, reason)
    notify_bond_lost(pal, reason)

    local function resense_after_flee()
        safe_call(function()
            local okP, PersonalityMod = pcall(require, "Personality")
            if okP and PersonalityMod and PersonalityMod.RefreshSightOn then
                PersonalityMod.RefreshSightOn(pal)
                Logger.log("[PalBonds/Capture] forced a sight re-check so the escape preset actually takes hold and the Pal runs")
            end
        end)
    end
    local name = safe_call(function() return pal:GetFullName() end)

    Logger.log(string.format("[PalBonds/Capture] %s lost all trust (%s) — fleeing permanently", tostring(name), tostring(reason)))
    if name then
        PermanentlyFled[name] = reason or true
    end

    if reason == "died" then
        return
    end

    local palId = safe_call(function() return Personality.GetOrInitState(pal) end)
    if palId then
        local tier = (reason == "abandoned") and "escape" or "warlike_anyway"
        Logger.log("[PalBonds/Capture] bond ended (" .. tostring(reason) ..
            ") — forcing tier '" .. tier .. "'" ..
            (tier == "warlike_anyway" and " so it turns on the player; the resulting combat is also what finally evicts our follow action" or ""))
        Personality.ForceTier(palId, pal, tier)

        resense_after_flee()
    else
        Logger.log("[PalBonds/Capture] could not resolve a personality state for this Pal — real flee behavior skipped, permanent-flag/interaction-block above still applies")
    end
end

local function guest_view()
    local ok, HostView = pcall(require, "HostView")
    if not ok or HostView == nil or not HostView.IsGuest() then return nil end
    return HostView
end

function Capture.GetFledReason(pal)
    local view = guest_view()
    if view then return view.FledReason(pal) end
    local name = safe_call(function() return pal:GetFullName() end)
    if name == nil then return nil end
    local v = PermanentlyFled[name]
    if type(v) == "string" then return v end
    return nil
end

function Capture.ResetForNewWorld()
    local n = 0
    for _ in pairs(PermanentlyFled) do n = n + 1 end
    PermanentlyFled = {}
    Logger.log("[PalBonds/Capture] [WORLD-RESET] dropped " .. n .. " permanently-fled record(s) from the old world")
end
function Capture.HasPermanentlyFled(pal)
    local view = guest_view()
    if view then return view.FledReason(pal) ~= nil end
    local name = safe_call(function() return pal:GetFullName() end)
    return name ~= nil and PermanentlyFled[name] ~= nil
end
return Capture
