local Logger = require("Logger")
local Personality = {}

local PersonalityState = {}

local function guest_view()
    local ok, HostView = pcall(require, "HostView")
    if not ok or HostView == nil or not HostView.IsGuest() then return nil end
    return HostView
end

local DISPOSITIONS = {
    "normal",
    "friendly",
    "escape",
    "notinterested",
    "warlike",
    "warlike_anyway",
    "warlike_without_player",
    "kill_all",
}
Personality.DISPOSITIONS = DISPOSITIONS

local SettingsP = require("Settings")
local PERSONALITY_TIERS = {
    { tier = "normal", weight = SettingsP.Get("ChanceNormal") },
    { tier = "friendly", weight = SettingsP.Get("ChanceCurious") },
    { tier = "escape", weight = SettingsP.Get("ChanceTimid") },
    { tier = "notinterested", weight = SettingsP.Get("ChanceAloof") },
    { tier = "warlike", weight = SettingsP.Get("ChanceGrumpy") },
    { tier = "warlike_anyway", weight = SettingsP.Get("ChanceHostile") },

    { tier = "kill_all", weight = SettingsP.Get("ChanceFeral") },
}

local TIER_CHANCE_KEY = {
    normal = "ChanceNormal", friendly = "ChanceCurious", escape = "ChanceTimid",
    notinterested = "ChanceAloof", warlike = "ChanceGrumpy",
    warlike_anyway = "ChanceHostile", kill_all = "ChanceFeral",
}
pcall(function()
    SettingsP.OnChange(function(key)
        if type(key) ~= "string" or not key:find("^Chance") then return end
        for _, entry in ipairs(PERSONALITY_TIERS) do
            local chanceKey = TIER_CHANCE_KEY[entry.tier]
            if chanceKey ~= nil then entry.weight = SettingsP.Get(chanceKey) end
        end
    end)
end)

local ENABLE_PERSONALITY_TIER_ROLL = true

local FORCE_ALL_CURIOUS = false
local function roll_personality_tier()
    if FORCE_ALL_CURIOUS then
        return "friendly"
    end
    local total = 0
    for _, entry in ipairs(PERSONALITY_TIERS) do
        total = total + entry.weight
    end
    local roll = math.random() * total
    local cumulative = 0
    for _, entry in ipairs(PERSONALITY_TIERS) do
        cumulative = cumulative + entry.weight
        if roll < cumulative then
            return entry.tier
        end
    end
    return PERSONALITY_TIERS[1].tier
end

local PRESET_NAME_TO_DISPOSITION = {
    ["BP_AIResponsePreset_friendly_C"] = "friendly",
    ["BP_AIResponsePreset_escape_C"] = "escape",
    ["BP_AIResponsePreset_Escape_to_Battle_C"] = "escape",
    ["BP_AIResponsePreset_NotInterested_C"] = "notinterested",
    ["BP_AIResponsePreset_Warlike_C"] = "warlike",
    ["BP_AIResponsePreset_Warlike_Anyway_C"] = "warlike_anyway",
    ["BP_AIResponsePreset_Warlike_WithoutPlayer_C"] = "warlike_without_player",

    ["BP_AIResponsePreset_Kill_All_C"] = "kill_all",
    ["BP_AIResponsePreset_VillageNPC_C"] = "friendly",
}

local EXCLUDED_FROM_ROLLING = {
    ["BP_AIResponsePreset_VillageNPC_C"] = true,
    ["BP_AIResponsePreset_Kill_All_C"] = true,
    ["BP_AIResponsePreset_Boss_C"] = true,
}

local TIER_TO_DONOR_PRESET_CLASS = {
    friendly = "BP_AIResponsePreset_friendly",
    escape = "BP_AIResponsePreset_escape",
    notinterested = "BP_AIResponsePreset_NotInterested",
    warlike = "BP_AIResponsePreset_Warlike",
    warlike_anyway = "BP_AIResponsePreset_Warlike_Anyway",
    warlike_without_player = "BP_AIResponsePreset_Warlike_WithoutPlayer",
    kill_all = "BP_AIResponsePreset_Kill_All",
}

local PRESET_ASSET_DIR = "/Game/Pal/Blueprint/Controller/AIResponsePreset/"
local NATIVE_PRESET_CLASS_PATH = "/Script/Pal.PalAIResponsePreset"

local PRESET_SLOTS = {
    "Discover_Player", "Discover_Greater", "Discover_Equal", "Discover_Smaller",
    "Damaged_Player", "Damaged_Greater", "Damaged_Equal", "Damaged_Smaller",
}

local PERSONALITY_SCAN_INTERVAL_MS = 8000

local loggedUnknownPresets = {}

local loggedDiagOnce = {}
local function log_diag_once(actorKey, reasonKey, message)
    local key = tostring(actorKey) .. "|" .. reasonKey
    if loggedDiagOnce[key] then return end
    loggedDiagOnce[key] = true
    Logger.log(message)
end
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
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

local PalUtilityCDO = nil
local PalAISensorComponentClass = nil
local NativePresetClass = nil
local presetCDOCache = {}
local function get_pal_utility()
    if PalUtilityCDO then return PalUtilityCDO end
    PalUtilityCDO = safe_call(function()
        return StaticFindObject("/Script/Pal.Default__PalUtility")
    end)
    return PalUtilityCDO
end

local function is_confirmed_pal_monster(palActor)
    local utility = get_pal_utility()
    if utility == nil then return false end
    local isMonster = safe_call(function()
        return utility:IsPalMonster(palActor)
    end)
    return isMonster == true
end

local function get_native_preset_class()
    if NativePresetClass then return NativePresetClass end
    NativePresetClass = safe_call(function()
        return StaticFindObject(NATIVE_PRESET_CLASS_PATH)
    end)
    return NativePresetClass
end

local function find_preset_cdo(baseName)
    if presetCDOCache[baseName] then return presetCDOCache[baseName] end
    local cdo = safe_call(function()
        return StaticFindObject(PRESET_ASSET_DIR .. baseName .. ".Default__" .. baseName .. "_C")
    end)
    local validOk, isValid = pcall(function() return cdo ~= nil and cdo:IsValid() end)
    if not (validOk and isValid) then
        cdo = safe_call(function()
            local cls = StaticFindObject(PRESET_ASSET_DIR .. baseName .. "." .. baseName .. "_C")
            if cls == nil or not cls:IsValid() then return nil end
            return cls:GetCDO()
        end)
        validOk, isValid = pcall(function() return cdo ~= nil and cdo:IsValid() end)
    end
    if validOk and isValid then
        presetCDOCache[baseName] = cdo
        return cdo
    end
    return nil
end
local function get_sensor_component_class()
    if PalAISensorComponentClass then return PalAISensorComponentClass end
    PalAISensorComponentClass = safe_call(function()
        return StaticFindObject("/Script/Pal.PalAISensorComponent")
    end)
    return PalAISensorComponentClass
end

local SENSOR_INDEX_REFRESH_SECONDS = 30
local sensorIndexByOwnerKey = {}
local sensorIndexBuiltAt = nil

local find_cached_sensor_fwd = nil

local loggedIndexBuildOnce = false
local function log_index_build_once(instanceCount, matchedCount)
    if loggedIndexBuildOnce then return end
    loggedIndexBuildOnce = true
    Logger.log(string.format(
        "[PalBonds/Personality] [DIAG] rebuild_sensor_index first run: FindAllOf('PalAISensorComponent') returned %d instance(s), %d resolved to a usable owner key",
        instanceCount, matchedCount
    ))
end
local function rebuild_sensor_index()
    Logger.trace("sensor-index rebuild (FindAllOf PalAISensorComponent)")
    sensorIndexByOwnerKey = {}
    local instances = safe_call(function() return FindAllOf("PalAISensorComponent") end)
    if not instances then
        log_index_build_once(0, 0)
        return
    end
    local matchedCount = 0
    for _, comp in ipairs(instances) do
        local ownerKey = safe_call(function()
            local owner = comp:GetOwner()
            return owner and owner:IsValid() and owner:GetFullName() or nil
        end)
        if ownerKey then
            sensorIndexByOwnerKey[ownerKey] = comp
            matchedCount = matchedCount + 1
        end
    end
    log_index_build_once(#instances, matchedCount)
end

local function find_sensor_component_via_index(palActor)
    local now = safe_call(function() return os.clock() end) or 0
    if not sensorIndexBuiltAt or (now - sensorIndexBuiltAt) > SENSOR_INDEX_REFRESH_SECONDS then
        rebuild_sensor_index()
        sensorIndexBuiltAt = now
    end
    local actorKey = safe_call(function() return palActor:GetFullName() end)
    if not actorKey then return nil end
    local comp = sensorIndexByOwnerKey[actorKey]
    if comp then
        local validOk, isValid = pcall(function() return comp:IsValid() end)
        if validOk and isValid then
            return comp
        end
    end
    return nil
end

function Personality.GetStableId(palActor)
    if palActor == nil then return nil end
    local utility = get_pal_utility()
    if utility == nil then return nil end
    local handle = safe_call(function()
        return utility:GetIndividualCharacterHandleByActor(palActor)
    end)
    if handle == nil then return nil end
    local id = safe_call(function() return handle:GetIndividualID() end)
    if id == nil then return nil end
    local guid = safe_call(function() return id.InstanceId end)
    if guid == nil then return nil end

    return safe_call(function()
        local function mask32(n)
            return math.floor((n or 0)) % 0x100000000
        end
        return string.format("%08X%08X%08X%08X",
            mask32(guid.A), mask32(guid.B), mask32(guid.C), mask32(guid.D))
    end)
end

function Personality.GetPresetClassName(palActor, palId)
    if palActor == nil then return nil end

    local actorKey = safe_call(function() return palActor:GetFullName() end) or tostring(palActor)

    local sensor = palId and find_cached_sensor_fwd and find_cached_sensor_fwd(palId) or nil
    if sensor == nil then
        local sensorClass = get_sensor_component_class()
        if sensorClass == nil then
            log_diag_once(actorKey, "no-sensor-class", "[PalBonds/Personality] [DIAG] GetPresetClassName: could not resolve PalAISensorComponent class via StaticFindObject")
            return nil
        end
        local sensorOk, found = pcall(function()
            return palActor:GetComponentByClass(sensorClass)
        end)
        local sensorValidOk, sensorIsValid = false, false
        if sensorOk and found ~= nil then
            sensorValidOk, sensorIsValid = pcall(function() return found:IsValid() end)
        end
        if sensorOk and found ~= nil and sensorValidOk and sensorIsValid then
            sensor = found
        else

            sensor = find_sensor_component_via_index(palActor)
            if sensor == nil then
                log_diag_once(actorKey, "no-sensor", "[PalBonds/Personality] [DIAG] GetPresetClassName: GetComponentByClass AND the FindAllOf-based fallback both failed for " .. tostring(actorKey))
                return nil
            end
        end
    end
    local presetOk, preset = pcall(function() return sensor.AIResponsePreset end)
    if not presetOk then
        log_diag_once(actorKey, "read-failed", "[PalBonds/Personality] [DIAG] GetPresetClassName: reading sensor.AIResponsePreset FAILED for " .. tostring(actorKey) .. " — " .. tostring(preset))
        return nil
    end
    if preset == nil then
        log_diag_once(actorKey, "preset-nil", "[PalBonds/Personality] [DIAG] GetPresetClassName: sensor.AIResponsePreset is nil for " .. tostring(actorKey) .. " (component found, but no preset assigned?)")
        return nil
    end

    local validOk, isValid = pcall(function() return preset:IsValid() end)
    if validOk and isValid == false then

        log_diag_once(actorKey, "null-preset", "[PalBonds/Personality] [DIAG] GetPresetClassName: sensor.AIResponsePreset is a NULL object reference (preset:IsValid() == false) for " .. tostring(actorKey) .. " — this Pal's preset pointer isn't actually set (yet?), despite the field read succeeding")
        return nil
    end

    local nameOk, fullName = pcall(function() return preset:GetFullName() end)
    if not nameOk or fullName == nil then
        log_diag_once(actorKey, "getfullname-failed", "[PalBonds/Personality] [DIAG] GetPresetClassName: preset:GetFullName() FAILED for " .. tostring(actorKey) .. " — " .. tostring(fullName) .. " (preset:IsValid() check " .. (validOk and tostring(isValid) or ("also failed: " .. tostring(isValid))) .. ")")
        return nil
    end

    return fullName:match("^(%S+)")
end

function Personality.PresetClassNameToDisposition(presetClassName)
    if presetClassName == nil then return "unknown" end
    local mapped = PRESET_NAME_TO_DISPOSITION[presetClassName]
    if mapped then return mapped end
    if not loggedUnknownPresets[presetClassName] then
        loggedUnknownPresets[presetClassName] = true
        Logger.log(string.format(
            "[PalBonds/Personality] unrecognized AIResponsePreset '%s' — defaulting to 'unknown', add it to PRESET_NAME_TO_DISPOSITION when convenient",
            presetClassName
        ))
    end
    return "unknown"
end

function Personality.GetSpeciesDefaultDisposition(palActor)
    local presetClassName = Personality.GetPresetClassName(palActor)
    if presetClassName == nil then return nil end
    return Personality.PresetClassNameToDisposition(presetClassName)
end

function Personality.GetOrInitState(palActor)
    local palId = Personality.GetStableId(palActor)
    if palId == nil then return nil end

    if guest_view() then return palId end
    if PersonalityState[palId] == nil then

        local presetClassName = Personality.GetPresetClassName(palActor, palId)
        local speciesDefault = Personality.PresetClassNameToDisposition(presetClassName)

        local okOwnReq, CaptureForOwnership = pcall(require, "Capture")
        local isOwnedPal = okOwnReq and CaptureForOwnership and CaptureForOwnership.IsAlreadyOwned
            and safe_call(function() return CaptureForOwnership.IsAlreadyOwned(palActor) end)

        local rolledTier
        local isHuman = false
        if isOwnedPal then
            rolledTier = "normal"
        elseif not is_confirmed_pal_monster(palActor) then
            isHuman = true

            rolledTier = "normal"
        elseif EXCLUDED_FROM_ROLLING[presetClassName] then
            rolledTier = "normal"
        elseif ENABLE_PERSONALITY_TIER_ROLL then
            rolledTier = roll_personality_tier()
        else
            rolledTier = "normal"
        end
        local effectiveDisposition = speciesDefault
        if rolledTier ~= "normal" then
            effectiveDisposition = rolledTier
        end

        if isHuman then
            effectiveDisposition = "normal"
        end

        local female = safe_call(function()
            local comp = palActor.CharacterParameterComponent
            if comp == nil or not comp:IsValid() then return false end
            local param = comp:GetIndividualParameter()
            if param == nil or not param:IsValid() then return false end
            return tonumber(param:GetGenderType()) == 2
        end) == true
        PersonalityState[palId] = {
            female = female,
            disposition = effectiveDisposition,
            speciesDefault = speciesDefault,
            presetClassName = presetClassName,
            rolledTier = rolledTier,
            isHuman = isHuman,

            enforcementApplied = false,
        }
        Logger.log(string.format(
            "[PalBonds/Personality] [PERSONALITY-ROLL] new individual %s — rolled tier=%s, species default=%s, effective disposition=%s",
            tostring(palId), tostring(rolledTier), tostring(speciesDefault), tostring(effectiveDisposition)
        ))
    elseif PersonalityState[palId].presetClassName == nil then

        local retryPresetClassName = Personality.GetPresetClassName(palActor)
        if retryPresetClassName ~= nil then
            local state = PersonalityState[palId]
            state.presetClassName = retryPresetClassName
            state.speciesDefault = Personality.PresetClassNameToDisposition(retryPresetClassName)
            local logSuffix
            if state.isHuman then
                logSuffix = " (human NPC, stays Normal)"
            elseif state.rolledTier == "normal" then
                state.disposition = state.speciesDefault
                logSuffix = ", effective disposition now=" .. tostring(state.disposition)
            else
                logSuffix = " (rolled tier=" .. tostring(state.rolledTier) .. " already overrides this)"
            end
            Logger.log(string.format(
                "[PalBonds/Personality] [PERSONALITY-ROLL] %s — species preset resolved on retry (was unreadable at first sight): %s, species default=%s%s",
                tostring(palId), tostring(retryPresetClassName), tostring(state.speciesDefault), logSuffix
            ))
        end
    end
    return palId
end

function Personality.GetRolledTier(palId)
    if palId == nil then return nil end
    local state = PersonalityState[palId]
    return state and state.rolledTier or nil
end
function Personality.SetDisposition(palId, disposition)
    if palId == nil then return end
    PersonalityState[palId] = PersonalityState[palId] or {}
    PersonalityState[palId].disposition = disposition
end

function Personality.IsFemale(palId)
    local view = guest_view()
    if view then return view.Female(palId) end
    local st = palId ~= nil and PersonalityState[palId] or nil
    return st ~= nil and st.female == true
end

function Personality.GetDisposition(palId)
    if palId == nil then return nil end
    local view = guest_view()
    if view then return view.Disposition(palId) end
    local state = PersonalityState[palId]
    return state and state.disposition or nil
end

function Personality.GetState(palId)
    if palId == nil then return nil end
    return PersonalityState[palId]
end

local loggedSensorFailureOnce = false
local function log_sensor_failure_once(reason)
    if loggedSensorFailureOnce then return end
    loggedSensorFailureOnce = true
    Logger.log("[PalBonds/Personality] [DIAG] find_sensor_component's first real failure this session: " .. reason)
end
local function find_sensor_component(palActor)
    if palActor == nil then return nil end
    local sensorClass = get_sensor_component_class()
    if sensorClass ~= nil then
        local ok, sensor = pcall(function() return palActor:GetComponentByClass(sensorClass) end)
        if ok and sensor ~= nil then
            local validOk, isValid = pcall(function() return sensor:IsValid() end)
            if validOk and isValid then
                return sensor
            end
        end
    end

    local viaIndex = find_sensor_component_via_index(palActor)
    if viaIndex ~= nil then
        return viaIndex
    end
    log_sensor_failure_once("GetComponentByClass AND the FindAllOf-based fallback both failed to resolve a valid sensor component")
    return nil
end

local RESPONSE_SPECIAL = 3
local GLOBAL_OVERRIDE_SOURCE_PRESET = "BP_AIResponsePreset_friendly"
local GLOBAL_OVERRIDE_TARGET_PRESETS = {
    "BP_AIResponsePreset_escape",
    "BP_AIResponsePreset_Escape_to_Battle",
    "BP_AIResponsePreset_Warlike",
    "BP_AIResponsePreset_Warlike_Anyway",
    "BP_AIResponsePreset_Warlike_WithoutPlayer",
}
local GLOBAL_CURIOUS_MAX_ROUNDS = 20
local GLOBAL_CURIOUS_RETRY_MS = 5000
local globalCuriousOverrideApplied = false
local function apply_global_curious_preset_override(round)
    if globalCuriousOverrideApplied then return end
    round = round or 1
    local sourceCdo = find_preset_cdo(GLOBAL_OVERRIDE_SOURCE_PRESET)
    local sourceValues = nil
    if sourceCdo then
        local readOk = pcall(function()
            sourceValues = {}
            for _, prop in ipairs(PRESET_SLOTS) do
                sourceValues[prop] = sourceCdo[prop]
            end
        end)
        if not readOk then sourceValues = nil end
    end
    if not sourceValues then
        Logger.log(string.format("[PalBonds/Personality] [GLOBAL-CURIOUS] round %d: source preset (%s) not resolvable yet", round, GLOBAL_OVERRIDE_SOURCE_PRESET))
    else
        local allResolved = true
        for _, presetName in ipairs(GLOBAL_OVERRIDE_TARGET_PRESETS) do
            local targetCdo = find_preset_cdo(presetName)
            if not targetCdo then
                allResolved = false
            else
                local changes = {}
                pcall(function()
                    for _, prop in ipairs(PRESET_SLOTS) do
                        local current = targetCdo[prop]
                        if tonumber(current) ~= RESPONSE_SPECIAL and current ~= sourceValues[prop] then
                            targetCdo[prop] = sourceValues[prop]
                            changes[#changes + 1] = prop
                        end
                    end
                end)
                Logger.log(string.format(
                    "[PalBonds/Personality] [GLOBAL-CURIOUS] round %d: %s — %s",
                    round, presetName, (#changes > 0) and ("changed " .. table.concat(changes, ", ")) or "already matched or Special-preserved, nothing changed"
                ))
            end
        end
        if allResolved then
            globalCuriousOverrideApplied = true
            Logger.log("[PalBonds/Personality] [GLOBAL-CURIOUS] all target presets processed — every wild Pal using them should now behave like the friendly/curious preset, globally, no per-individual lookup needed")
            return
        end
    end
    if round >= GLOBAL_CURIOUS_MAX_ROUNDS then
        Logger.log("[PalBonds/Personality] [GLOBAL-CURIOUS] giving up after " .. round .. " rounds — some presets never resolved")
        return
    end
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(GLOBAL_CURIOUS_RETRY_MS, function()
            safe_call(function() apply_global_curious_preset_override(round + 1) end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Personality] [GLOBAL-CURIOUS] could not schedule a retry round — stopping after round " .. round)
    end
end

local loggedPresetSlotsOnce = {}
local function log_preset_slots_once(desiredBaseName, cdo)
    if loggedPresetSlotsOnce[desiredBaseName] then return end
    loggedPresetSlotsOnce[desiredBaseName] = true
    local parts = {}
    for _, prop in ipairs(PRESET_SLOTS) do
        local value = safe_call(function() return cdo[prop] end)
        parts[#parts + 1] = prop .. "=" .. tostring(value)
    end
    Logger.log("[PalBonds/Personality] [PRESET-SLOTS] " .. desiredBaseName .. " real field values: " .. table.concat(parts, ", "))
end
local function sensor_alive(sensor)
    local ok, valid = pcall(function() return sensor ~= nil and sensor:IsValid() end)
    return ok and valid == true
end

local function apply_forced_preset(sensor, desiredBaseName)

    if not sensor_alive(sensor) then
        return false, "the Pal's sensor is gone (despawned, joined or out of range)"
    end
    local cdo = find_preset_cdo(desiredBaseName)
    if not cdo then
        return false, "could not resolve the default preset object for " .. tostring(desiredBaseName)
    end
    log_preset_slots_once(desiredBaseName, cdo)
    local nativeClass = get_native_preset_class()
    if not nativeClass then
        return false, "could not resolve the native PalAIResponsePreset class"
    end
    Logger.trace("preset build", desiredBaseName)
    local fresh = safe_call(function() return StaticConstructObject(nativeClass, sensor) end)
    local freshValidOk, freshValid = pcall(function() return fresh ~= nil and fresh:IsValid() end)
    if not (freshValidOk and freshValid) then
        return false, "StaticConstructObject failed"
    end
    local copyOk, copyErr = pcall(function()
        for _, prop in ipairs(PRESET_SLOTS) do
            fresh[prop] = cdo[prop]
        end
    end)
    if not copyOk then
        return false, "failed copying preset fields: " .. tostring(copyErr)
    end
    if not sensor_alive(sensor) then
        return false, "the Pal's sensor went away while its preset was being built"
    end
    Logger.trace("preset write", desiredBaseName)
    local setOk, setErr = pcall(function() sensor.AIResponsePreset = fresh end)
    if not setOk then
        return false, "AIResponsePreset write FAILED: " .. tostring(setErr)
    end
    return true, nil
end

local INTERRUPT_VERBOSE = false

local function interrupt_and_resense(palActor, sensor, palId, cancelActions)
    Logger.trace("interrupt and re-sense", palId)
    if cancelActions == nil then cancelActions = true end
    local controller = safe_call(function() return palActor.Controller end)
    local controllerValid = controller ~= nil and safe_call(function() return controller:IsValid() end)
    if controllerValid and cancelActions then
        local actionComp = safe_call(function() return controller:GetAIActionComponent() end)
        local actionCompValid = actionComp ~= nil and safe_call(function() return actionComp:IsValid() end)
        if actionCompValid then
            if INTERRUPT_VERBOSE then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — about to call AllCancelAction_Logic_HardScript_Reaction NOW") end
            local ok, err = pcall(function() actionComp:AllCancelAction_Logic_HardScript_Reaction(palActor) end)
            if INTERRUPT_VERBOSE or not ok then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — AllCancelAction_Logic_HardScript_Reaction returned: " .. (ok and "ok" or ("FAILED: " .. tostring(err)))) end
        else
            Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — no usable AIActionComponent, skipping the action-cancel step (tracked disposition/preset swap still applied)")
        end
    elseif cancelActions then
        Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — no usable Controller, skipping the action-cancel step (tracked disposition/preset swap still applied)")
    end
    if sensor then

        if INTERRUPT_VERBOSE then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — about to call ResetResponsedMaxBiologicalGrade NOW") end
        local ok3, err3 = pcall(function() sensor:ResetResponsedMaxBiologicalGrade() end)
        if INTERRUPT_VERBOSE or not ok3 then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — ResetResponsedMaxBiologicalGrade returned: " .. (ok3 and "ok" or ("FAILED: " .. tostring(err3)))) end
        if INTERRUPT_VERBOSE then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — about to call RequestSightCheckAsync NOW") end
        local ok2, err2 = pcall(function() sensor:RequestSightCheckAsync(true, true, false, 1.0, false) end)
        if INTERRUPT_VERBOSE or not ok2 then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — RequestSightCheckAsync returned: " .. (ok2 and "ok" or ("FAILED: " .. tostring(err2)))) end
    end
end

local function try_enforce_personality_with_sensor(palActor, palId, sensor)
    local state = PersonalityState[palId]
    if not state or state.enforcementApplied then return end
    if state.rolledTier == "normal" then

        state.enforcementApplied = true
        return
    end

    local okReq, Capture = pcall(require, "Capture")
    if not okReq or not Capture or not Capture.IsAlreadyOwned then
        Logger.log("[PalBonds/Personality] [ENFORCE] could not load Capture.IsAlreadyOwned — skipping this attempt for " .. tostring(palId) .. " out of caution (ownership unknown)")
        return
    end
    local isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
    if isOwned ~= false then

        state.enforcementApplied = true
        Logger.log("[PalBonds/Personality] [ENFORCE] " .. tostring(palId) .. " is owned (or ownership unreadable) — leaving its AI untouched, marking done")
        return
    end
    local desiredBaseName = TIER_TO_DONOR_PRESET_CLASS[state.rolledTier]
    if not desiredBaseName then
        state.enforcementApplied = true
        return
    end
    local desiredClassName = desiredBaseName .. "_C"
    if state.presetClassName == desiredClassName then

        Logger.log(string.format(
            "[PalBonds/Personality] [ENFORCE] %s already naturally uses %s (matches rolled tier=%s) — no swap needed",
            tostring(palId), tostring(desiredClassName), tostring(state.rolledTier)
        ))
        state.enforcementApplied = true
        return
    end
    local ok, err = apply_forced_preset(sensor, desiredBaseName)
    if ok then
        state.enforcementApplied = true
        Logger.log(string.format(
            "[PalBonds/Personality] [ENFORCE] SUCCESS — %s (rolled tier=%s) now has its own private preset copied from %s's real defaults",
            tostring(palId), tostring(state.rolledTier), tostring(desiredBaseName)
        ))

    else
        Logger.log("[PalBonds/Personality] [ENFORCE] " .. tostring(palId) .. " — " .. tostring(err) .. ", will retry")
    end
end

local function try_enforce_personality(palActor, palId, cacheOnly)
    local state = PersonalityState[palId]
    if not state or state.enforcementApplied then return end
    if cacheOnly and not (find_cached_sensor_fwd and find_cached_sensor_fwd(palId)) then return end

    local sensor = find_cached_sensor_fwd and find_cached_sensor_fwd(palId)
    if not sensor then
        sensor = find_sensor_component(palActor)
    end
    if not sensor then

        if not state.noSensorLoggedOnce then
            state.noSensorLoggedOnce = true
            Logger.log("[PalBonds/Personality] [ENFORCE] " .. tostring(palId) .. " has no readable AISensorComponent via the proactive scan — cannot enforce this way yet, will keep quietly retrying every scan until it resolves (logged once). The reactive hook below may catch it first.")
        end
        return
    end
    try_enforce_personality_with_sensor(palActor, palId, sensor)
end

local cachedSensorByPalId = {}
local function cache_sensor_for_pal(sensor, pawn)

    Logger.trace("cache.stableid")
    local palId = Personality.GetStableId(pawn)
    if palId then cachedSensorByPalId[palId] = sensor end
    Logger.trace("cache.initstate", palId)
    local stateId = Personality.GetOrInitState(pawn)
    if stateId and stateId ~= palId then cachedSensorByPalId[stateId] = sensor end
    return stateId
end

local function find_cached_sensor(palId)
    if not palId then return nil end
    local sensor = cachedSensorByPalId[palId]
    if not sensor then return nil end
    local validOk, isValid = pcall(function() return sensor:IsValid() end)
    if validOk and isValid then return sensor end
    cachedSensorByPalId[palId] = nil
    return nil
end

find_cached_sensor_fwd = find_cached_sensor
local handledSensorKeys = {}
local handledSensorAddresses = {}

local pawnByPalId = {}

function Personality.RememberPawn(palId, pawn)
    if palId ~= nil and pawn ~= nil then pawnByPalId[palId] = pawn end
end

function Personality.ForEachKnownPal(fn)
    for palId, pawn in pairs(pawnByPalId) do
        local okCall = pcall(fn, palId, pawn, PersonalityState[palId])
        if not okCall then end
    end
end
local senseHookArmed = false

local SENSE_CALLS_PER_SECOND = 25
local senseWindowStart = 0.0
local senseWindowCalls = 0
local senseSkipped = 0
local senseSkipLoggedAt = 0.0

local function on_sensor_select_response(Context)
    local now = os.clock()
    if (now - senseWindowStart) >= 1.0 then
        if senseSkipped > 0 and (now - senseSkipLoggedAt) >= 60.0 then
            senseSkipLoggedAt = now
            Logger.log("[PalBonds/Personality] [ENFORCE] the sense budget skipped " .. senseSkipped ..
                " sense(s) in the last second — they are picked up on their next sense (logged at most once a minute)")
        end
        senseWindowStart = now
        senseWindowCalls = 0
        senseSkipped = 0
    end
    senseWindowCalls = senseWindowCalls + 1
    if senseWindowCalls > SENSE_CALLS_PER_SECOND then
        senseSkipped = senseSkipped + 1
        return
    end

    Logger.trace("sense.get")
    local sensor = safe_call(function() return Context:get() end)
    if not sensor then return end

    Logger.trace("sense.addr")
    local addr = safe_call(function() return sensor:GetAddress() end)
    if addr ~= nil then
        local seenId = handledSensorAddresses[addr]
        if seenId ~= nil then
            local seenState = seenId ~= true and PersonalityState[seenId] or nil
            if seenState then seenState.lastSeenAt = os.clock() end
            return
        end
    end
    Logger.trace("sense.fullname", addr)
    local sensorKey = safe_call(function() return sensor:GetFullName() end)
    if not sensorKey then return end
    Logger.trace("sense.outer", addr)
    local owner = safe_call(function() return sensor:GetOuter() end)
    Logger.trace("sense.pawn", addr)
    local pawn = owner and safe_call(function() return owner.Pawn end)
    Logger.trace("sense.pawnvalid", addr)
    local validOk, isValid = pcall(function() return pawn ~= nil and pawn:IsValid() end)
    if not (validOk and isValid) then return end
    Logger.trace("sense.cache", addr)
    local palId = cache_sensor_for_pal(sensor, pawn)
    if not palId then return end
    pawnByPalId[palId] = pawn
    local resolvedState = PersonalityState[palId]
    if resolvedState then resolvedState.lastSeenAt = os.clock() end
    if handledSensorKeys[sensorKey] then
        if addr ~= nil then handledSensorAddresses[addr] = palId end
        return
    end
    handledSensorKeys[sensorKey] = true

    if addr ~= nil then handledSensorAddresses[addr] = palId end
    Logger.trace("sense.enforce", palId)
    try_enforce_personality_with_sensor(pawn, palId, sensor)
    Logger.trace("sense.done", palId)
end
local SENSOR_HOOK_MAX_ROUNDS = 20
local SENSOR_HOOK_RETRY_MS = 5000
local function register_sensor_sense_hook(round)
    round = round or 1
    local ok, err = pcall(function()
        RegisterHook("/Script/Pal.PalAISensorComponent:SelectResponseBySenses", function(Context)
            if world_is_closing() or we_are_a_guest() then return end
            safe_call(function() on_sensor_select_response(Context) end)
        end)
    end)
    if ok then
        senseHookArmed = true
        Logger.log(string.format("[PalBonds/Personality] [ENFORCE] round %d: SelectResponseBySenses hook registered — reactive enforcement armed", round))
        return
    end
    Logger.log(string.format("[PalBonds/Personality] [ENFORCE] round %d: RegisterHook(SelectResponseBySenses) FAILED: %s", round, tostring(err)))
    if round >= SENSOR_HOOK_MAX_ROUNDS then
        Logger.log("[PalBonds/Personality] [ENFORCE] giving up on the reactive hook after " .. round .. " rounds — falling back to the proactive scan only")
        return
    end
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(SENSOR_HOOK_RETRY_MS, function()
            safe_call(function() register_sensor_sense_hook(round + 1) end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Personality] [ENFORCE] could not schedule a retry for the reactive hook")
    end
end

local function hates_player(palActor)
    local target = safe_call(function()
        local ctrl = palActor.Controller
        if ctrl == nil or not ctrl:IsValid() then return nil end
        local hate = ctrl:GetHateSystem()
        if hate == nil or not hate:IsValid() then return nil end
        return hate:FindMostHateTarget()
    end)
    if target == nil or not safe_call(function() return target:IsValid() end) then return false end
    local okRef, PlayerRef = pcall(require, "PlayerRef")
    local player = okRef and PlayerRef and safe_call(PlayerRef.Get) or nil
    if player ~= nil then
        local a = safe_call(function() return player:GetAddress() end)
        local b = safe_call(function() return target:GetAddress() end)
        if a ~= nil and b ~= nil then return a == b end
    end
    local name = safe_call(function() return target:GetFullName() end)
    return name ~= nil and tostring(name):find("^BP_Player_") ~= nil
end
Personality.HatesPlayer = hates_player

local function become_friendly_wild(palId, palActor, state)
    local desiredBaseName = TIER_TO_DONOR_PRESET_CLASS["friendly"]
    local sensor = find_cached_sensor(palId) or find_sensor_component(palActor)
    if not sensor then
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " — no readable sensor, friendly preset not written")
        return
    end
    local ok, err = apply_forced_preset(sensor, desiredBaseName)
    if ok then
        state.enforcementApplied = true
        state.rolledTier = "friendly"
        interrupt_and_resense(palActor, sensor, palId, false)
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " is a Friendly wild Pal now (friendly preset written, re-sensed)")
    else
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " — friendly preset write FAILED: " .. tostring(err))
    end
end

function Personality.MaybeBecomeFriendlyByBar(palId, palActor)
    if palId == nil then return end
    local state = PersonalityState[palId]
    if not state then return end

    if state.becameFriendlyByBar then return end
    local fromDisposition = state.disposition
    state.becameFriendlyByBar = true

    state.preForgive = {
        disposition = fromDisposition,
        rolledTier = state.rolledTier,
        presetClassName = state.presetClassName,
    }
    state.disposition = "friendly"
    Logger.log(string.format(
        "[PalBonds/Personality] [WON-OVER] %s crossed the friendly-trigger fraction of its bonding bar (was '%s', rolled '%s') — now friendly",
        tostring(palId), tostring(fromDisposition), tostring(state.rolledTier)
    ))
    if not palActor then return end

    if state.isHuman then
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " — human NPC: no reset, its AI is left alone")
        return
    end

    local okReq, Capture = pcall(require, "Capture")
    local isOwned = true
    if okReq and Capture and Capture.IsAlreadyOwned then
        isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
        if isOwned == nil then isOwned = true end
    end
    if isOwned ~= false then
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " — no reset: counted as owned (or ownership unreadable)")
        return
    end

    local okT, Trust = pcall(require, "Trust")
    local started = okT and Trust and Trust.StartBriefFollow and Trust.StartBriefFollow(palActor, hates_player,
        function(calmed, elapsed, stayed)
            if not stayed then
                become_friendly_wild(palId, palActor, state)
            end
        end)
    if not started then
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " — brief follow not started (already following, or no bonding state); friendly preset only")
        become_friendly_wild(palId, palActor, state)
    end
end

function Personality.RevertForgiveness(palId, palActor)
    if palId == nil then return false end
    local state = PersonalityState[palId]
    if not state or not state.preForgive then return false end
    local before = state.preForgive
    state.preForgive = nil
    state.disposition = before.disposition
    state.rolledTier = before.rolledTier
    Logger.log(string.format(
        "[PalBonds/Personality] [FORGIVENESS] %s was hit by the player below 50%% — back to '%s' (its one forgiveness is spent)",
        tostring(palId), tostring(before.disposition)))

    if state.isHuman or palActor == nil then return true end
    local okReq, Capture = pcall(require, "Capture")
    local isOwned = true
    if okReq and Capture and Capture.IsAlreadyOwned then
        isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
        if isOwned == nil then isOwned = true end
    end
    if isOwned ~= false then return true end

    local baseName = nil
    if before.rolledTier ~= nil and before.rolledTier ~= "normal" then
        baseName = TIER_TO_DONOR_PRESET_CLASS[before.rolledTier]
    end
    if baseName == nil and type(before.presetClassName) == "string" then
        baseName = before.presetClassName:match("^(BP_AIResponsePreset_.+)_C$")
    end
    if baseName == nil then
        Logger.log("[PalBonds/Personality] [FORGIVENESS] " .. tostring(palId) .. " — no original preset on record, only the tag was reverted")
        return true
    end
    local sensor = find_cached_sensor(palId) or find_sensor_component(palActor)
    if not sensor then
        Logger.log("[PalBonds/Personality] [FORGIVENESS] " .. tostring(palId) .. " — no readable sensor, only the tag was reverted")
        return true
    end
    local ok, err = apply_forced_preset(sensor, baseName)
    if ok then
        state.enforcementApplied = true

        interrupt_and_resense(palActor, sensor, palId, false)
        Logger.log("[PalBonds/Personality] [FORGIVENESS] " .. tostring(palId) .. " — its original AI is back (" .. baseName .. ")")
    else
        Logger.log("[PalBonds/Personality] [FORGIVENESS] " .. tostring(palId) .. " — restoring its AI FAILED: " .. tostring(err))
    end
    return true
end

local COMPANION_RESPONSE_IGNORE = 0
local COMPANION_RESPONSE_BATTLE = 2

local COMPANION_PLAYER_SLOTS = { "Discover_Player", "Damaged_Player" }

local COMPANION_OTHER_DISCOVER_SLOTS = { "Discover_Greater", "Discover_Equal", "Discover_Smaller" }

local COMPANION_OTHER_DAMAGED_SLOTS = { "Damaged_Greater", "Damaged_Equal", "Damaged_Smaller" }

local QUIET_RETALIATION_DURING_PLAYER_FIGHT = true

local DISCOVER_BATTLE_DURING_PLAYER_FIGHT = true

function Personality.RefreshSightOn(palActor)
    if palActor == nil then return end
    local palId = Personality.GetOrInitState(palActor)
    if not palId then return end
    local sensor = find_cached_sensor(palId) or find_sensor_component(palActor)
    if not sensor then return end
    safe_call(function() sensor:RequestSightCheckAsync(true, true, false, 1.0, false) end)
end
function Personality.ApplyCompanionPreset(palId, palActor, combatAssist, playerInCombat)
    if palId == nil or palActor == nil then return false end
    local okReq, Capture = pcall(require, "Capture")
    local isOwned = true
    if okReq and Capture and Capture.IsAlreadyOwned then
        isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
        if isOwned == nil then isOwned = true end
    end
    if isOwned ~= false then
        return false
    end
    local sensor = find_cached_sensor(palId) or find_sensor_component(palActor)
    if not sensor then
        Logger.log("[PalBonds/Personality] [COMPANION] " .. tostring(palId) .. " — no readable sensor yet, cannot apply the companion preset (will be retried on the next follow tick)")
        return false
    end

    local cdo = find_preset_cdo("BP_AIResponsePreset_friendly")
    local nativeClass = get_native_preset_class()
    if not cdo or not nativeClass then
        Logger.log("[PalBonds/Personality] [COMPANION] could not resolve the friendly CDO or the native preset class — no companion preset applied")
        return false
    end
    local fresh = safe_call(function() return StaticConstructObject(nativeClass, sensor) end)
    local freshOk, freshValid = pcall(function() return fresh ~= nil and fresh:IsValid() end)
    if not (freshOk and freshValid) then
        Logger.log("[PalBonds/Personality] [COMPANION] StaticConstructObject failed — no companion preset applied")
        return false
    end
    local buildOk, buildErr = pcall(function()
        for _, prop in ipairs(PRESET_SLOTS) do
            fresh[prop] = cdo[prop]
        end
        for _, prop in ipairs(COMPANION_PLAYER_SLOTS) do
            fresh[prop] = COMPANION_RESPONSE_IGNORE
        end

        local discoverResponse = COMPANION_RESPONSE_IGNORE
        if combatAssist and playerInCombat and DISCOVER_BATTLE_DURING_PLAYER_FIGHT then
            discoverResponse = COMPANION_RESPONSE_BATTLE
        end
        for _, prop in ipairs(COMPANION_OTHER_DISCOVER_SLOTS) do
            fresh[prop] = discoverResponse
        end
        if combatAssist then

            local damagedResponse = COMPANION_RESPONSE_BATTLE
            if QUIET_RETALIATION_DURING_PLAYER_FIGHT and playerInCombat then
                damagedResponse = COMPANION_RESPONSE_IGNORE
            end
            for _, prop in ipairs(COMPANION_OTHER_DAMAGED_SLOTS) do
                fresh[prop] = damagedResponse
            end
        end
    end)
    if not buildOk then
        Logger.log("[PalBonds/Personality] [COMPANION] failed building the companion preset: " .. tostring(buildErr))
        return false
    end

    if not sensor_alive(sensor) then
        Logger.log("[PalBonds/Personality] [COMPANION] the Pal's sensor went away while its preset was being built — nothing written")
        return false
    end
    Logger.trace("companion preset write", palId)
    local setOk, setErr = pcall(function() sensor.AIResponsePreset = fresh end)
    if not setOk then
        Logger.log("[PalBonds/Personality] [COMPANION] AIResponsePreset write FAILED: " .. tostring(setErr))
        return false
    end

    local wasAlreadyCompanion = false
    if PersonalityState[palId] and type(PersonalityState[palId].disposition) == "string"
        and PersonalityState[palId].disposition:find("^companion") ~= nil then
        wasAlreadyCompanion = true
    end

    local st = PersonalityState[palId]
    if st then
        st.disposition = (combatAssist and playerInCombat) and "companion_fighting" or (combatAssist and "companion_combat" or "companion")

        st.enforcementApplied = true
    end

    if not wasAlreadyCompanion then
        Logger.log(string.format(
            "[PalBonds/Personality] [COMPANION] %s now has a companion preset (player slots=Ignore) — its own AI should no longer generate decisions about the player",
            tostring(palId)
        ))
    end

    local SKIP_INTERRUPT_FOR_COMPANIONS = false
    local doCancel = true
    if SKIP_INTERRUPT_FOR_COMPANIONS and wasAlreadyCompanion then doCancel = false end
    interrupt_and_resense(palActor, sensor, palId, doCancel)
    if wasAlreadyCompanion and not doCancel then
        Logger.log("[PalBonds/Personality] [COMPANION] " .. tostring(palId) ..
            " was already a companion — preset re-sensed WITHOUT cancelling its current action")
    end
    return true
end
function Personality.ForceTier(palId, palActor, tier)
    if palId == nil then return end
    local state = PersonalityState[palId]
    if not state then return end
    state.rolledTier = tier
    state.disposition = tier
    state.enforcementApplied = false
    Logger.log(string.format(
        "[PalBonds/Personality] [FORCE-TIER] %s tracked tier/disposition forced to '%s'",
        tostring(palId), tostring(tier)
    ))
    if not palActor then return end
    local okReq, Capture = pcall(require, "Capture")
    local isOwned = true
    if okReq and Capture and Capture.IsAlreadyOwned then
        isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
        if isOwned == nil then isOwned = true end
    end
    if isOwned ~= false then
        return
    end
    local desiredBaseName = TIER_TO_DONOR_PRESET_CLASS[tier]
    if not desiredBaseName then
        Logger.log("[PalBonds/Personality] [FORCE-TIER] no donor preset defined for tier '" .. tostring(tier) .. "' — tracked state updated, no AI swap")
        return
    end
    local desiredClassName = desiredBaseName .. "_C"
    if state.presetClassName == desiredClassName then
        return
    end
    local sensor = find_cached_sensor(palId) or find_sensor_component(palActor)
    if not sensor then
        Logger.log("[PalBonds/Personality] [FORCE-TIER] " .. tostring(palId) .. " has no readable AISensorComponent right now (neither cached nor found via scan) — cannot swap its real AI immediately, tracked state still updated (the periodic scan will keep retrying)")
        return
    end
    local ok, err = apply_forced_preset(sensor, desiredBaseName)
    if ok then
        state.enforcementApplied = true
        Logger.log(string.format(
            "[PalBonds/Personality] [FORCE-TIER] %s real AIResponsePreset ALSO swapped to '%s' (private preset)",
            tostring(palId), tostring(tier)
        ))
        interrupt_and_resense(palActor, sensor, palId)
    else
        Logger.log("[PalBonds/Personality] [FORCE-TIER] " .. tostring(palId) .. " — " .. tostring(err) .. " (tracked state still updated, periodic scan will retry)")
    end
end

local PERSONALITY_PRUNE_EVERY_N_SCANS = 75
local PERSONALITY_UNSEEN_PRUNE_SECONDS = 600.0

local PERSONALITY_SAFETY_SCAN_EVERY_N_SCANS = 8
local personalityScanCount = 0
local function scan_nearby_wild_pals_for_personality()

    if we_are_a_guest() then return end

    personalityScanCount = personalityScanCount + 1
    local now = os.clock()

    local worldScan = (not senseHookArmed)
        or (personalityScanCount % PERSONALITY_SAFETY_SCAN_EVERY_N_SCANS == 0)
    if worldScan then
        local pals = safe_call(function() return FindAllOf("PalCharacter") end)
        if pals then
            local okRef, PlayerRef = pcall(require, "PlayerRef")
            local playerName = okRef and PlayerRef and safe_call(PlayerRef.Name) or nil
            for _, palActor in ipairs(pals) do
                safe_call(function()
                    local validOk, isValid = pcall(function() return palActor ~= nil and palActor:IsValid() end)
                    if not (validOk and isValid) then return end
                    local actorName = safe_call(function() return palActor:GetFullName() end)
                    if actorName and playerName and actorName == playerName then
                        return
                    end
                    local palId = Personality.GetOrInitState(palActor)
                    if palId == nil then return end
                    pawnByPalId[palId] = palActor
                    local st = PersonalityState[palId]
                    if st then st.lastSeenAt = now end
                    try_enforce_personality(palActor, palId)
                end)
            end
        end
    else
        for palId, pawn in pairs(pawnByPalId) do
            safe_call(function()
                if not safe_call(function() return pawn:IsValid() end) then
                    pawnByPalId[palId] = nil
                    return
                end
                local st = PersonalityState[palId]
                if st and st.enforcementApplied then return end
                local id = palId
                if st == nil then id = Personality.GetOrInitState(pawn) end
                if id == nil then return end
                try_enforce_personality(pawn, id, true)
            end)
        end
    end

    if personalityScanCount % PERSONALITY_PRUNE_EVERY_N_SCANS == 0 then
        local pruned, kept = 0, 0
        for palId, st in pairs(PersonalityState) do
            if st.lastSeenAt == nil then
                st.lastSeenAt = now
                kept = kept + 1
            elseif (now - st.lastSeenAt) > PERSONALITY_UNSEEN_PRUNE_SECONDS then
                PersonalityState[palId] = nil
                cachedSensorByPalId[palId] = nil
                pawnByPalId[palId] = nil
                pruned = pruned + 1
            else
                kept = kept + 1
            end
        end
        handledSensorKeys = {}
        handledSensorAddresses = {}
        Logger.log(string.format(
            "[PalBonds/Personality] [PRUNE] dropped %d personality record(s) for Pals unseen for %.0fs, %d kept",
            pruned, PERSONALITY_UNSEEN_PRUNE_SECONDS, kept))
    end
end
local function schedule_personality_scan()
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(PERSONALITY_SCAN_INTERVAL_MS, function()
            Logger.trace("personality-scan start")
            safe_call(scan_nearby_wild_pals_for_personality)
            Logger.trace("personality-scan end")
            schedule_personality_scan()
        end)
    end)
    if not ok then
        Logger.log("[PalBonds/Personality] [ENFORCE] could not schedule the personality scan — ExecuteInGameThreadWithDelay itself failed, enforcement will never run this session")
    end
end
function Personality.Init()

    pcall(function() math.randomseed(os.time()) end)
    Logger.log("[PalBonds/Personality] real read-only helpers active (GetStableId, GetSpeciesDefaultDisposition) — no per-tick hooks, on-demand only, see file header")
    if ENABLE_PERSONALITY_TIER_ROLL and FORCE_ALL_CURIOUS then
        Logger.log("[PalBonds/Personality] [PERSONALITY-ROLL] FORCE_ALL_CURIOUS active — every wild Pal gets tier=friendly, weighted roll bypassed (hundred-and-forty-sixth pass, Dragón's request)")
    elseif ENABLE_PERSONALITY_TIER_ROLL then
        Logger.log("[PalBonds/Personality] [PERSONALITY-ROLL] weighted personality-tier assignment active (35% normal / 30% friendly / 10% escape / 10% notinterested / 5% warlike / 5% warlike_anyway / 5% warlike_without_player)")
    else
        Logger.log("[PalBonds/Personality] [PERSONALITY-ROLL] tier roll DISABLED (hundred-and-twenty-eighth pass, temporary) — every Pal's tracked disposition is its real species default, no override")
    end

    schedule_personality_scan()
    Logger.log("[PalBonds/Personality] [ENFORCE] recurring personality-enforcement scan scheduled, every " .. tostring(PERSONALITY_SCAN_INTERVAL_MS) .. "ms — proactive fallback path, still blocked by the sensor-component bug on its own")

    register_sensor_sense_hook(1)

    if FORCE_ALL_CURIOUS then
        Logger.log("[PalBonds/Personality] [GLOBAL-CURIOUS] starting global preset override (rewrites shared AIResponsePreset objects directly — affects every wild Pal using them, no per-individual lookup)")
        safe_call(function() apply_global_curious_preset_override(1) end)
    end
end

function Personality.ForgetJoinedPal(palId, actorKey)
    local n = 0
    if palId ~= nil then
        for _, t in ipairs({ PersonalityState, cachedSensorByPalId, pawnByPalId }) do
            if t[palId] ~= nil then t[palId] = nil; n = n + 1 end
        end
        for addr, id in pairs(handledSensorAddresses) do
            if id == palId then handledSensorAddresses[addr] = nil; n = n + 1 end
        end
    end
    if actorKey ~= nil and sensorIndexByOwnerKey[actorKey] ~= nil then
        sensorIndexByOwnerKey[actorKey] = nil
        n = n + 1
    end
    return n
end

function Personality.HeldReferencesFor(palId, actorKey)
    local n = 0
    for _, t in ipairs({ PersonalityState, cachedSensorByPalId, pawnByPalId }) do
        if palId ~= nil and t[palId] ~= nil then n = n + 1 end
    end
    for _, id in pairs(handledSensorAddresses) do
        if palId ~= nil and id == palId then n = n + 1 end
    end
    if actorKey ~= nil and sensorIndexByOwnerKey[actorKey] ~= nil then n = n + 1 end
    return n
end

function Personality.ResetForNewWorld()
    local n = 0
    for _ in pairs(PersonalityState) do n = n + 1 end
    PersonalityState = {}
    sensorIndexByOwnerKey = {}
    cachedSensorByPalId = {}
    handledSensorKeys = {}
    handledSensorAddresses = {}
    pawnByPalId = {}
    Logger.log("[PalBonds/Personality] [WORLD-RESET] dropped " .. n ..
        " personality record(s) and every sensor/pawn reference from the old world")
end
return Personality
