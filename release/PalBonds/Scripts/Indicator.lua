local Logger = require("Logger")
local Locale = require("Locale")
local Trust = require("Trust")
local UEHelpers = require("UEHelpers")
local Personality = require("Personality")
local Indicator = {}

local function address_of_obj(o)
    if o == nil then return nil end
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok then return a end
    return nil
end

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local playerRefForGate = nil

local function on_dedicated_server()
    local ok, Session = pcall(require, "Session")
    if not (ok and Session and Session.IsDedicated) then return false end
    local okAsk, yes = pcall(Session.IsDedicated)
    return okAsk and yes == true
end

local function guest_without_host_view()
    local ok, HostView = pcall(require, "HostView")
    if not ok or HostView == nil or not HostView.IsGuest() then return false end
    return not HostView.HostHasPalBonds()
end

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
local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end
local function describe_widget(widget)
    if widget == nil then return "nil" end
    local ok, fullName = pcall(function() return widget:GetFullName() end)
    if ok and fullName then return fullName end
    return "[could not read GetFullName]"
end
local function describe_pal(pal)
    if pal == nil then return "nil" end
    local ok, fullName = pcall(function() return pal:GetFullName() end)
    if ok and fullName then return fullName end
    return "[could not read GetFullName]"
end

local SCAN_INTERVAL_MS = 2000

local hasRegisteredBindHook = false

local pendingGauges = {}

local gaugeBoundAt = {}
local NEW_WORLD_BIND_GRACE_SECONDS = 20.0
local NAMEPLATE_SWEEPS_AFTER_HOOK = 5
local NAMEPLATE_SAFETY_SWEEP_EVERY_N_SCANS = 15
local MAX_BARS_BUILT_PER_SWEEP = 4
local nameplateSweepsSinceHook = 0
local gaugeHandleByKey = {}

local IMMEDIATE_BIND_HOOK_MAX_ROUNDS = 30
local IMMEDIATE_BIND_HOOK_RETRY_MS = 1000
local IMMEDIATE_BIND_HOOK_SLOW_RETRY_MS = 5000
local function register_bind_hook_immediate(round)
    round = round or 1
    if hasRegisteredBindHook then return end
    local hookPath = "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle"
    local hookOk, hookErr = pcall(function()
        RegisterHook(hookPath, function(Context, TargetHandle)

            if world_is_closing() then return end

            Logger.trace("gauge.bind.get")
            local self = hook_get(Context)
            local handle = hook_get(TargetHandle)
            if self == nil or handle == nil then return end
            Logger.trace("gauge.bind.describe")
            local key = describe_widget(self)
            gaugeHandleByKey[key] = handle
            gaugeBoundAt[key] = os.clock()
            pendingGauges[key] = self
            Logger.trace("gauge.bind.done", key)
        end)
    end)
    if hookOk then
        Logger.log(string.format("[PalBonds/Indicator] [TAGS] bind hook INSTALLED (immediate, round %d) — personality tags and trust bars can now resolve their Pal: %s", round, hookPath))
        hasRegisteredBindHook = true
        local unbindPath = hookPath:gsub(":BindFromHandle$", ":Unbind")
        local unbindOk, unbindErr = pcall(function()
            RegisterHook(unbindPath, function(Context)
                if world_is_closing() then return end
                Logger.trace("gauge.unbind.get")
                local self = hook_get(Context)
                if self == nil then return end
                Logger.trace("gauge.unbind.describe")
                local key = describe_widget(self)
                gaugeHandleByKey[key] = nil
                gaugeBoundAt[key] = nil
                pendingGauges[key] = nil
                Logger.trace("gauge.unbind.done", key)
            end)
        end)
        Logger.log("[PalBonds/Indicator] [TAGS] (immediate) RegisterHook(" .. unbindPath .. ") = " .. (unbindOk and "OK" or ("FAILED (non-fatal, BindFromHandle hook still stands): " .. tostring(unbindErr))))
        return
    end
    local errFirstLine = tostring(hookErr):match("^[^\n]*") or tostring(hookErr)

    local isFast = round < IMMEDIATE_BIND_HOOK_MAX_ROUNDS
    local delay = isFast and IMMEDIATE_BIND_HOOK_RETRY_MS or IMMEDIATE_BIND_HOOK_SLOW_RETRY_MS

    if round == 1 or round == IMMEDIATE_BIND_HOOK_MAX_ROUNDS or (round % 60 == 0) then
        Logger.log(string.format(
            "[PalBonds/Indicator] [TAGS] bind hook not installable yet (round %d, %s cadence): %s — still retrying; personality tags and trust bars cannot appear until this succeeds",
            round, isFast and "fast" or "slow", errFirstLine))
    end
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(delay, function()
            safe_call(function() register_bind_hook_immediate(round + 1) end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Indicator] [TAGS] COULD NOT schedule a retry round — personality tags and trust bars will not appear this session. Stopped after round " .. round)
    end
end

local barInstalledForGauge = {}
local trackedBars = {}
local function resolve_pal_actor_from_gauge(gaugeWidget)

    local key = describe_widget(gaugeWidget)
    local hookedHandle = gaugeHandleByKey[key]
    if hookedHandle ~= nil then
        local validOk, valid = pcall(function() return hookedHandle:IsValid() end)
        if validOk and valid then
            local actorOk, actor = pcall(function() return hookedHandle:TryGetIndividualActor() end)
            if actorOk and actor ~= nil then
                local actorValidOk, actorValid = pcall(function() return actor:IsValid() end)
                if actorValidOk and actorValid then return actor, nil end
            end
        end
    end

    local handleOk, handle = pcall(function() return gaugeWidget.bindedHandle end)
    if not (handleOk and handle ~= nil) then
        return nil, "no hooked handle yet, and bindedHandle unreadable: " .. tostring(handle)
    end

    local directOk, actor = pcall(function() return handle:TryGetIndividualActor() end)
    if directOk and actor ~= nil then
        local validOk, valid = pcall(function() return actor:IsValid() end)
        if validOk and valid then return actor, nil end
    end
    local loadOk, resolved = pcall(function() return handle:LoadSynchronous() end)
    if loadOk and resolved ~= nil then
        local actorOk2, actor2 = pcall(function() return resolved:TryGetIndividualActor() end)
        if actorOk2 and actor2 ~= nil then
            local validOk2, valid2 = pcall(function() return actor2:IsValid() end)
            if validOk2 and valid2 then return actor2, nil end
        end
    end
    return nil, "no hooked handle for this gauge yet (bound before the hook was registered), and the stored bindedHandle field doesn't resolve in this build — see DIAG-HANDLE log"
end

local function get_friendship_ratio(actor)
    local ok, ratio = pcall(function() return Trust.GetBarRatio(actor) end)
    if not ok or type(ratio) ~= "number" then
        return nil, "Trust.GetBarRatio failed: " .. tostring(ratio)
    end
    return ratio, nil
end

local USE_PLAYER_FACING_PERSONALITY_NAMES = true

local PERSONALITY_DISPLAY_NAMES = {
    normal = "tag_normal",
    unknown = "tag_normal",
    friendly = "tag_curious",
    escape = "tag_timid",
    notinterested = "tag_aloof",
    warlike = "tag_grumpy",
    warlike_anyway = "tag_hostile",
    kill_all = "tag_feral",

    companion_combat = "tag_bonding",
}
local BOND_LABEL_FRIENDLY_RATIO = 0.2
local BOND_LABEL_BONDING_RATIO = 0.5

local LABEL_GAP_BELOW_BAR = 6
local LABEL_HEIGHT = 18

local loggedLabelStyleOnce = false
local loggedLabelGeometryOnce = false

local NAMED_COLORS = {
    gold   = { R = 1.00, G = 0.84, B = 0.00, A = 1 },
    white  = { R = 1.00, G = 1.00, B = 1.00, A = 1 },
    red    = { R = 0.95, G = 0.18, B = 0.15, A = 1 },
    green  = { R = 0.30, G = 0.90, B = 0.35, A = 1 },
    blue   = { R = 0.25, G = 0.62, B = 1.00, A = 1 },
    purple = { R = 0.72, G = 0.42, B = 1.00, A = 1 },
}
local TAG_SIZE_SCALE = { small = 0.8, normal = 1.0, large = 1.25, huge = 1.5 }

local barColorName = "gold"
local tagColorName = nil
local tagSizeScale = 1.0

local function named_color(name)
    return NAMED_COLORS[name]
end

local function compute_trust_bar_color(ratio)
    return named_color(barColorName) or NAMED_COLORS.gold
end

local function read_appearance_settings()
    local okS, Set = pcall(require, "Settings")
    if not okS then return end
    barColorName = Set.Get("BarColor") or "gold"
    local tag = Set.Get("TagColor")
    tagColorName = (tag ~= nil and tag ~= "name") and tag or nil
    tagSizeScale = TAG_SIZE_SCALE[Set.Get("TagSize")] or 1.0
end

read_appearance_settings()

pcall(function()
    require("Settings").OnChange(function(key)
        local appearance = (key == "BarColor" or key == "TagColor" or key == "TagSize")
        local bondable = type(key) == "string" and key:find("^Bond") ~= nil
        if not (appearance or bondable) then return end
        read_appearance_settings()
        Indicator.RefreshAppearance()
    end)
end)

local function style_personality_label(labelObj, gaugeWidget, sourceText)
    if labelObj == nil then return end

    local scaleOk = pcall(function() labelObj:SetRenderScale({X = 1.0, Y = 1.0}) end)
    local opacityOk = pcall(function() labelObj:SetRenderOpacity(1.0) end)
    local nameText = sourceText
    if nameText == nil then
        pcall(function() nameText = gaugeWidget.WBP_EnemyGauge.Text_Name end)
    end
    local nameValid = nameText ~= nil and pcall(function() return nameText:IsValid() end) and nameText:IsValid()
    local fontOk, colorOk, shadowOk, justifyOk = false, false, false, false
    if nameValid then
        fontOk = pcall(function() labelObj:SetFont(nameText.Font) end)
        colorOk = pcall(function() labelObj:SetColorAndOpacity(nameText.ColorAndOpacity) end)

        local wanted = named_color(tagColorName)
        if wanted ~= nil then
            pcall(function() labelObj:SetColorAndOpacity({ SpecifiedColor = wanted, ColorUseRule = 0 }) end)
        end
        if tagSizeScale ~= 1.0 then
            pcall(function()
                local font = labelObj.Font
                local base = tonumber(font.Size) or 0
                if base > 0 then
                    font.Size = math.max(6, math.floor(base * tagSizeScale + 0.5))
                    labelObj:SetFont(font)
                end
            end)
        end

        shadowOk = pcall(function() labelObj:SetShadowColorAndOpacity(nameText.ShadowColorAndOpacity) end)
        pcall(function() labelObj.ShadowOffset = nameText.ShadowOffset end)
        justifyOk = pcall(function() labelObj:SetJustification(nameText.Justification) end)
    end
    if not loggedLabelStyleOnce then
        loggedLabelStyleOnce = true
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-LABEL] copied style from Text_Name (logged once) — nameFound=%s font=%s color=%s shadow=%s justify=%s | render resets scale=%s opacity=%s",
            tostring(nameValid), tostring(fontOk), tostring(colorOk),
            tostring(shadowOk), tostring(justifyOk), tostring(scaleOk), tostring(opacityOk)
        ))
    end
end

local function dump_label_geometry(gaugeWidget, labelObj)
    if loggedLabelGeometryOnce then return end
    loggedLabelGeometryOnce = true
    local function slotOf(w)
        local sx, sy, sw, sh
        pcall(function()
            local sl = w.Slot
            local pos = sl:GetPosition()
            local size = sl:GetSize()
            sx, sy = pos.X, pos.Y
            sw, sh = size.X, size.Y
        end)
        return string.format("pos=(%s,%s) size=(%s,%s)", tostring(sx), tostring(sy), tostring(sw), tostring(sh))
    end
    pcall(function()
        local eg = gaugeWidget.WBP_EnemyGauge
    end)
    if labelObj ~= nil then
    end
end

local personalityLabelsVisible = (require("Settings").Get("ShowPersonalityTags") ~= 0)

pcall(function()
    require("Settings").OnChange(function(key)
        if key ~= "ShowPersonalityTags" then return end
        personalityLabelsVisible = (require("Settings").Get("ShowPersonalityTags") ~= 0)
        for _, entry in pairs(trackedBars) do
            if type(entry) == "table" then entry.labelLastText = nil end
        end
    end)
end)

function Indicator.RefreshAppearance()
    for _, entry in pairs(trackedBars) do
        if type(entry) == "table" then
            if entry.bar ~= nil then
                pcall(function() entry.bar:SetFillColorAndOpacity(compute_trust_bar_color(0)) end)

                local allowed = true
                pcall(function()
                    local T = require("Trust")
                    if T.PersonalityMayBond then allowed = T.PersonalityMayBond(entry.actor) end
                end)
                pcall(function() entry.bar:SetVisibility(allowed and 0 or 1) end)
            end
            if entry.label ~= nil and entry.gaugeWidget ~= nil then
                pcall(function() style_personality_label(entry.label, entry.gaugeWidget) end)
            end
            entry.labelLastText = nil
        end
    end
end

function Indicator.TogglePersonalityLabels()
    personalityLabelsVisible = not personalityLabelsVisible
    for _, entry in pairs(trackedBars) do
        if type(entry) == "table" then entry.labelLastText = nil end
    end
    Logger.log("[PalBonds/Indicator] [TAG-TOGGLE] personality tags are now " ..
        (personalityLabelsVisible and "VISIBLE" or "HIDDEN") ..
        " (" .. tostring(require("Settings").Get("KeyTags")) .. "; session-only, back to ShowPersonalityTags on the next launch)")

    return personalityLabelsVisible
end

local BROKEN_BOND_LABELS = {
    betrayed = "tag_scarred",
    abandoned = "tag_abandoned",
}

local BROKEN_BOND_FALLBACK = "tag_wary"
local function personality_display_text(actor, disposition, palId)

    local g = { female = palId ~= nil and Personality.IsFemale and Personality.IsFemale(palId) or false }
    if not personalityLabelsVisible then return "" end

    local okCap, CaptureMod = pcall(require, "Capture")
    if okCap and CaptureMod and CaptureMod.IsAlreadyOwned then
        if safe_call(function() return CaptureMod.IsAlreadyOwned(actor) end) then
            return ""
        end
    end

    if okCap and CaptureMod and CaptureMod.HasPermanentlyFled then
        if safe_call(function() return CaptureMod.HasPermanentlyFled(actor) end) then
            local why = CaptureMod.GetFledReason and safe_call(function() return CaptureMod.GetFledReason(actor) end)
            return Locale.T(BROKEN_BOND_LABELS[why] or BROKEN_BOND_FALLBACK, g)
        end
    end

    local okCombat, CombatMod = pcall(require, "Combat")
    if okCombat and CombatMod and CombatMod.ClaimedByAnotherPlayer then
        if safe_call(function() return CombatMod.ClaimedByAnotherPlayer(actor) end) == true then
            return Locale.T("tag_claimed", g)
        end
    end

    if not USE_PLAYER_FACING_PERSONALITY_NAMES then
        return disposition or "?"
    end

    local ratio = get_friendship_ratio(actor)
    if ratio ~= nil then
        if ratio >= BOND_LABEL_BONDING_RATIO then return Locale.T("tag_bonding", g) end
        if ratio >= BOND_LABEL_FRIENDLY_RATIO then return Locale.T("tag_friendly", g) end
    end
    if disposition == nil then return "?" end

    local nameKey = PERSONALITY_DISPLAY_NAMES[disposition]
    if nameKey == nil then return disposition end
    return Locale.T(nameKey, g)
end

local function reparent_existing_bar(entry, newGaugeWidget)
    local hasBar = entry.bar ~= nil
    local barOk, barValid = true, true
    if hasBar then
        barOk, barValid = pcall(function() return entry.bar:IsValid() end)
    end
    if hasBar and not (barOk and barValid) then hasBar = false end
    local hasLabel = entry.label ~= nil
    local labelOk, labelValid = true, true
    if hasLabel then
        labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
    end
    if hasLabel and not (labelOk and labelValid) then hasLabel = false end
    if not hasBar and not hasLabel then return false end
    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = newGaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)
    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
    else
        local innerOk, innerCanvas = pcall(function() return newGaugeWidget.Canvas_Innner end)
        if innerOk and innerCanvas ~= nil and innerCanvas:IsValid() then
            targetPanel = innerCanvas
        else
            return false
        end
    end
    if hasBar then
        pcall(function()
            local oldParent = entry.bar.Slot and entry.bar.Slot.Parent
            if oldParent ~= nil and oldParent:IsValid() then
                oldParent:RemoveChild(entry.bar)
            end
        end)
        local addOk, newSlot = pcall(function() return targetPanel:AddChildToCanvas(entry.bar) end)
        if addOk and newSlot ~= nil and newSlot:IsValid() then
            local newY = (refY or 0) + (refH or 6) + 2
            pcall(function() newSlot:SetPosition({X = refX or 0, Y = newY}) end)
            pcall(function() newSlot:SetSize({X = refW or 80, Y = 6}) end)
        end
    end
    if hasLabel then
        pcall(function()
            local oldLabelParent = entry.label.Slot and entry.label.Slot.Parent
            if oldLabelParent ~= nil and oldLabelParent:IsValid() then
                oldLabelParent:RemoveChild(entry.label)
            end
        end)
        local labelAddOk, labelSlot = pcall(function() return targetPanel:AddChildToCanvas(entry.label) end)
        if labelAddOk and labelSlot ~= nil and labelSlot:IsValid() then
            pcall(function() labelSlot:SetPosition({X = refX or 0, Y = (refY or 0) + (refH or 6) + LABEL_GAP_BELOW_BAR}) end)
            pcall(function() labelSlot:SetSize({X = refW or 80, Y = LABEL_HEIGHT}) end)
            style_personality_label(entry.label, newGaugeWidget)
            dump_label_geometry(newGaugeWidget, entry.label)
        end
    end
    entry.gaugeWidget = newGaugeWidget
    entry.targetPanel = targetPanel
    return true
end

local function try_upgrade_entry_with_bar(entry)
    if entry.bar ~= nil then return end
    if entry.actor == nil or not Trust.HasBondingState(entry.actor) then return end
    local gaugeOk, gaugeValid = pcall(function() return entry.gaugeWidget:IsValid() end)
    if not (gaugeOk and gaugeValid) then return end
    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = entry.gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)
    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
    else
        local innerOk, innerCanvas = pcall(function() return entry.gaugeWidget.Canvas_Innner end)
        if innerOk and innerCanvas ~= nil and innerCanvas:IsValid() then
            targetPanel = innerCanvas
        else
            return
        end
    end
    local classOk, progressBarClass = pcall(function() return StaticFindObject("/Script/UMG.ProgressBar") end)
    if not (classOk and progressBarClass ~= nil and progressBarClass:IsValid()) then return end
    local constructOk, newBar = pcall(function()
        return StaticConstructObject(progressBarClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not (constructOk and newBar ~= nil and newBar:IsValid()) then return end
    pcall(function() newBar:SetPercent(0.0) end)
    pcall(function() newBar:SetFillColorAndOpacity(compute_trust_bar_color(0)) end)
    pcall(function() newBar:SetVisibility(0) end)
    local addOk, slot = pcall(function() return targetPanel:AddChildToCanvas(newBar) end)
    if not (addOk and slot ~= nil and slot:IsValid()) then return end
    if refOk then
        local newY = (refY or 0) + (refH or 6) + 2
        pcall(function() slot:SetPosition({X = refX or 0, Y = newY}) end)
        pcall(function() slot:SetSize({X = refW or 80, Y = 6}) end)
    else
        pcall(function() slot:SetPosition({X = 0, Y = 25}) end)
        pcall(function() slot:SetSize({X = 80, Y = 6}) end)
    end
    local ratio = get_friendship_ratio(entry.actor)
    if ratio then
        pcall(function() newBar:SetPercent(ratio) end)
        pcall(function() newBar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
    end
    entry.bar = newBar
    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] upgraded a label-only entry with a real trust bar (first interaction) for " .. describe_pal(entry.actor))
end

local TRACKED_BAR_UNSEEN_PRUNE_SECONDS = 60.0

local function detach_tracked_widget(w)
    if w == nil then return end
    local okValid, isValid = pcall(function() return w:IsValid() end)
    if not (okValid and isValid) then return end
    pcall(function()
        local parent = w.Slot and w.Slot.Parent
        if parent ~= nil and parent:IsValid() then parent:RemoveChild(w) end
    end)
end

local function release_tracked_entry(entry)
    detach_tracked_widget(entry.bar)
    detach_tracked_widget(entry.label)

    if entry.gaugeKey ~= nil then
        local held = barInstalledForGauge[entry.gaugeKey]
        if held ~= nil and address_of_obj(held) == address_of_obj(entry.gaugeWidget) then
            barInstalledForGauge[entry.gaugeKey] = nil
        end
    end
end

local function install_trust_bar(gaugeWidget)
    Logger.trace("build trust bar")
    local key = describe_widget(gaugeWidget)
    if barInstalledForGauge[key] then return end

    local earlyActor = resolve_pal_actor_from_gauge(gaugeWidget)
    if earlyActor == nil then
        return
    end

    barInstalledForGauge[key] = gaugeWidget

    local hasBonding = Trust.HasBondingState(earlyActor)

    if hasBonding and Trust.PersonalityMayBond and not Trust.PersonalityMayBond(earlyActor) then
        hasBonding = false
    end

    local earlyPalId = safe_call(Personality.GetStableId, earlyActor)
    if earlyPalId and trackedBars[earlyPalId] then
        local entry = trackedBars[earlyPalId]
        local reused = reparent_existing_bar(entry, gaugeWidget)
        if reused then

            entry.gaugeWidget = gaugeWidget
            entry.gaugeKey = key
            entry.lastSeenAt = os.clock()
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] REUSED existing widget(s) for already-tracked Pal " .. describe_pal(earlyActor) .. " on recycled gauge " .. key .. " (no new widgets built)")
            if hasBonding then
                try_upgrade_entry_with_bar(entry)
            end
            return
        end
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] reparent attempt failed for already-tracked Pal " .. describe_pal(earlyActor) .. " — falling back to full construction")
    end
    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] attempting to construct widget(s) for gauge: " .. key)

    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)
    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-CREATE] using ProgressBar_HP's REAL parent panel (%s) — pos=(%s,%s) size=(%s,%s)",
            describe_widget(realParent), tostring(refX), tostring(refY), tostring(refW), tostring(refH)
        ))
    else
        local innerOk, innerCanvas = pcall(function() return gaugeWidget.Canvas_Innner end)
        if not (innerOk and innerCanvas ~= nil and innerCanvas:IsValid()) then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] neither ProgressBar_HP's real parent nor Canvas_Innner is readable — cannot proceed: " .. tostring(refX))
            return
        end
        targetPanel = innerCanvas
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] could not read ProgressBar_HP's real parent (caught, non-fatal) — falling back to Canvas_Innner as a guess: " .. tostring(refX))
    end

    local newLabel = nil
    local labelClassOk, labelClass = pcall(function() return gaugeWidget.WBP_EnemyGauge.Text_WorkName:GetClass() end)
    if labelClassOk and labelClass ~= nil and labelClass:IsValid() then
        local labelConstructOk, labelObj = pcall(function()
            return StaticConstructObject(labelClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
        end)
        if labelConstructOk and labelObj ~= nil and labelObj:IsValid() then
            local labelAddOk, labelSlot = pcall(function() return targetPanel:AddChildToCanvas(labelObj) end)
            if labelAddOk and labelSlot ~= nil and labelSlot:IsValid() then
                if refOk then
                    pcall(function() labelSlot:SetPosition({X = refX or 0, Y = (refY or 0) + (refH or 6) + LABEL_GAP_BELOW_BAR}) end)
                    pcall(function() labelSlot:SetSize({X = refW or 80, Y = LABEL_HEIGHT}) end)
                else
                    pcall(function() labelSlot:SetPosition({X = 0, Y = 32}) end)
                    pcall(function() labelSlot:SetSize({X = 80, Y = LABEL_HEIGHT}) end)
                end
                pcall(function() labelObj:SetVisibility(0) end)
                style_personality_label(labelObj, gaugeWidget)
                dump_label_geometry(gaugeWidget, labelObj)
                local setTextOk, setTextErr = pcall(function() labelObj:SetText_GDKInternal(true, "?") end)
                Logger.log("[PalBonds/Indicator] [DIAG-LABEL] personality label created and positioned — initial text write = " .. (setTextOk and "OK" or ("FAILED: " .. tostring(setTextErr))))
                newLabel = labelObj
            else
                Logger.log("[PalBonds/Indicator] [DIAG-LABEL] AddChildToCanvas FAILED for personality label: " .. tostring(labelSlot))
            end
        else
            Logger.log("[PalBonds/Indicator] [DIAG-LABEL] StaticConstructObject FAILED for personality label: " .. tostring(labelObj))
        end
    else
        Logger.log("[PalBonds/Indicator] [DIAG-LABEL] could not read Text_WorkName's real class FAILED: " .. tostring(labelClass))
    end

    local newBar = nil
    if hasBonding then
        local classOk, progressBarClass = pcall(function() return StaticFindObject("/Script/UMG.ProgressBar") end)
        if not (classOk and progressBarClass ~= nil and progressBarClass:IsValid()) then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] StaticFindObject('/Script/UMG.ProgressBar') failed: " .. tostring(progressBarClass))
        else
            local constructOk, barObj = pcall(function()
                return StaticConstructObject(progressBarClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
            end)
            if not (constructOk and barObj ~= nil and barObj:IsValid()) then
                Logger.log("[PalBonds/Indicator] [DIAG-CREATE] StaticConstructObject FAILED (caught, non-fatal): " .. tostring(barObj))
            else
                pcall(function() barObj:SetPercent(0.0) end)
                pcall(function() barObj:SetFillColorAndOpacity(compute_trust_bar_color(0)) end)
                pcall(function() barObj:SetVisibility(0) end)
                local addOk, slot = pcall(function() return targetPanel:AddChildToCanvas(barObj) end)
                if not (addOk and slot ~= nil and slot:IsValid()) then
                    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] AddChildToCanvas FAILED (caught, non-fatal) — bar exists but is not in the widget tree, so it cannot render: " .. tostring(slot))
                else
                    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] AddChildToCanvas SUCCEEDED — new bar is now a real child of the same panel ProgressBar_HP lives in")
                    if refOk then
                        local newY = (refY or 0) + (refH or 6) + 2
                        pcall(function() slot:SetPosition({X = refX or 0, Y = newY}) end)
                        pcall(function() slot:SetSize({X = refW or 80, Y = 6}) end)
                    else
                        pcall(function() slot:SetPosition({X = 0, Y = 25}) end)
                        pcall(function() slot:SetSize({X = 80, Y = 6}) end)
                    end
                    local ratio = get_friendship_ratio(earlyActor)
                    if ratio then
                        pcall(function() barObj:SetPercent(ratio) end)
                        pcall(function() barObj:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
                    end
                    Logger.log(string.format(
                        "[PalBonds/Indicator] [DIAG-TRUST] built real trust bar for %s — initial ratio=%s",
                        describe_pal(earlyActor), ratio and string.format("%.2f", ratio) or "unreadable"
                    ))
                    newBar = barObj
                end
            end
        end
    end

    local trackKey = earlyPalId or key
    trackedBars[trackKey] = { bar = newBar, gaugeWidget = gaugeWidget, actor = earlyActor, label = newLabel, palId = earlyPalId,
        actorAddr = address_of_obj(earlyActor),

        gaugeKey = key, lastSeenAt = os.clock() }
end

local LABEL_REFRESH_SECONDS = 10.0

local LABEL_STATE_RETRY_SECONDS = 10.0
local function update_trust_bars()

    local promotions = {}
    local now = os.clock()
    local prunedBars = 0
    for key, entry in pairs(trackedBars) do

        Logger.trace("bar.entry", key)

        if entry.lastSeenAt == nil then entry.lastSeenAt = now end
        if entry.gaugeKey ~= nil and gaugeHandleByKey[entry.gaugeKey] ~= nil then
            entry.lastSeenAt = now
        end
        local unseenTooLong = (now - entry.lastSeenAt) > TRACKED_BAR_UNSEEN_PRUNE_SECONDS

        local hasBar = entry.bar ~= nil
        local barOk, barValid = true, true
        if hasBar then
            barOk, barValid = pcall(function() return entry.bar:IsValid() end)
        end
        local gaugeOk, gaugeValid = pcall(function() return entry.gaugeWidget:IsValid() end)
        if unseenTooLong or not gaugeValid or (hasBar and not (barOk and barValid)) then

            if unseenTooLong and gaugeValid then
                safe_call(release_tracked_entry, entry)
                prunedBars = prunedBars + 1
            end
            trackedBars[key] = nil
        else
            if entry.actor == nil then
                local actor = resolve_pal_actor_from_gauge(entry.gaugeWidget)
                if actor then
                    entry.actor = actor
                    entry.actorAddr = address_of_obj(actor)
                    Logger.log("[PalBonds/Indicator] [DIAG-TRUST] resolved a real Pal actor on a retry for a previously-unresolved gauge: " .. describe_pal(actor))

                    if entry.palId == nil then
                        local palId = safe_call(Personality.GetStableId, actor)
                        if palId and palId ~= key and trackedBars[palId] == nil then
                            entry.palId = palId
                            promotions[#promotions + 1] = { oldKey = key, newKey = palId }
                        end
                    end
                end
            end
            if entry.actor ~= nil then
                local actorOk, actorValid = pcall(function() return entry.actor:IsValid() end)
                if not (actorOk and actorValid) then
                    entry.actor = nil
                else

                    if entry.bar == nil then
                        try_upgrade_entry_with_bar(entry)
                    end
                    if entry.bar ~= nil then
                        local ratio = get_friendship_ratio(entry.actor)

                        if ratio and ratio ~= entry.lastRatio then
                            entry.lastRatio = ratio
                            pcall(function() entry.bar:SetPercent(ratio) end)
                            pcall(function() entry.bar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
                        end
                    end

                    if entry.label then
                        local labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
                        if labelOk and labelValid then

                            local nowLabel = os.clock()
                            if entry.labelPalId == nil or entry.labelActor ~= entry.actor then
                                entry.labelPalId = safe_call(Personality.GetStableId, entry.actor)
                                entry.labelActor = entry.actor
                            end
                            local palId = entry.labelPalId
                            local disposition = palId and Personality.GetDisposition(palId)
                            if disposition == nil and palId ~= nil
                                and (nowLabel - (entry.stateTriedAt or -1e9)) >= LABEL_STATE_RETRY_SECONDS then
                                entry.stateTriedAt = nowLabel
                                safe_call(function() Personality.GetOrInitState(entry.actor) end)
                                disposition = Personality.GetDisposition(palId)
                            end
                            local needsText = entry.bar ~= nil
                                or entry.labelLastText == nil
                                or entry.labelLastDisposition ~= disposition
                                or entry.labelLastVisible ~= personalityLabelsVisible
                                or (nowLabel - (entry.labelCheckedAt or -1e9)) >= LABEL_REFRESH_SECONDS
                            local text = entry.labelLastText
                            if needsText then
                                entry.labelCheckedAt = nowLabel
                                entry.labelLastDisposition = disposition
                                entry.labelLastVisible = personalityLabelsVisible
                                text = personality_display_text(entry.actor, disposition, palId)
                            end
                            if entry.labelLastText ~= text then
                                entry.labelLastText = text

                                local setOk, setErr = pcall(function() entry.label:SetText_GDKInternal(true, text) end)
                                if not setOk then
                                    Logger.log("[PalBonds/Indicator] [DIAG-LABEL] text write FAILED for " .. describe_pal(entry.actor) .. ": " .. tostring(setErr))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, promotion in ipairs(promotions) do
        local entry = trackedBars[promotion.oldKey]
        if entry ~= nil then
            trackedBars[promotion.oldKey] = nil
            trackedBars[promotion.newKey] = entry
        end
    end
    if prunedBars > 0 then
        local left = 0
        for _ in pairs(trackedBars) do left = left + 1 end
        Logger.log(string.format(
            "[PalBonds/Indicator] [PRUNE] dropped %d trust-bar entr(ies) for Pals whose nameplate has been gone for %.0fs, %d still tracked",
            prunedBars, TRACKED_BAR_UNSEEN_PRUNE_SECONDS, left))
    end
end

local BOSS_GAUGE_HOOK_PATH = "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_BossEnemyHPGauge.WBP_BossEnemyHPGauge_C:SetTargetCharacter"
local BOSS_BAR_GAP = 2
local BOSS_BAR_MIN_HEIGHT = 6
local BOSS_BAR_MAX_HEIGHT = 10
local BOSS_LABEL_GAP = 1
local BOSS_LABEL_HEIGHT = 22

local BOSS_LABEL_STYLE_FIELDS = { "Text_LvTitle", "Text_BossName" }
local hasRegisteredBossHook = false
local loggedBossHookThrow = false
local pendingBossGauges = {}
local bossEntries = {}

local function is_valid_obj(obj)
    return obj ~= nil and safe_call(function() return obj:IsValid() end) == true
end

local function boss_hp_layout(gaugeWidget)

    local ok, inner, parent, off = pcall(function()
        local innerW = gaugeWidget.WBP_IngameBossHP
        local slot = innerW.BossGaugeHP.Slot
        local pos = slot:GetPosition()
        local size = slot:GetSize()
        return innerW, slot.Parent, { left = pos.X or 0, top = pos.Y or 0, right = size.X or 0, bottom = size.Y or 8 }
    end)
    if not ok or not is_valid_obj(parent) then return nil end
    local ancOk, anc = pcall(function()
        local slot = inner.BossGaugeHP.Slot
        local a = slot:GetAnchors()
        return { minX = a.Minimum.X, minY = a.Minimum.Y, maxX = a.Maximum.X, maxY = a.Maximum.Y }
    end)
    if not ancOk or type(anc) ~= "table" or anc.minX == nil then anc = nil end
    local alOk, al = pcall(function()
        local g = inner.BossGaugeHP.Slot:GetAlignment()
        return { x = g.X, y = g.Y }
    end)
    if not alOk or type(al) ~= "table" then al = { x = 0, y = 0 } end

    local stretchedY = anc ~= nil and anc.minY ~= anc.maxY
    local h = stretchedY and 8 or off.bottom
    local topEdge = off.top - ((al.y or 0) * h)
    return { inner = inner, parent = parent, off = off, anc = anc, al = al,
             h = h, topEdge = topEdge, stretchedY = stretchedY }
end

local function place_under_hp(slot, layout, top, height)
    local a, o = layout.anc, layout.off
    if a ~= nil then
        pcall(function()
            slot:SetAnchors({ Minimum = { X = a.minX, Y = a.minY }, Maximum = { X = a.maxX, Y = a.minY } })
        end)
    end
    pcall(function() slot:SetAlignment({ X = layout.al.x or 0, Y = 0 }) end)
    pcall(function() slot:SetPosition({ X = o.left, Y = top }) end)
    pcall(function() slot:SetSize({ X = o.right, Y = height }) end)
end

local function boss_bar_height(layout)
    local hgt = math.floor((layout.h or 0) * 0.35 + 0.5)
    if hgt < BOSS_BAR_MIN_HEIGHT then hgt = BOSS_BAR_MIN_HEIGHT end
    if hgt > BOSS_BAR_MAX_HEIGHT then hgt = BOSS_BAR_MAX_HEIGHT end
    return hgt
end

local function build_boss_bar(entry, layout)
    local cls = safe_call(function() return StaticFindObject("/Script/UMG.ProgressBar") end)
    if not is_valid_obj(cls) then return end
    local bar = safe_call(function()
        return StaticConstructObject(cls, layout.parent, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not is_valid_obj(bar) then
        Logger.log("[PalBonds/Indicator] [BOSS] could not construct the trust bar for " .. describe_pal(entry.actor))
        return
    end
    pcall(function() bar:SetPercent(0.0) end)
    pcall(function() bar:SetFillColorAndOpacity(compute_trust_bar_color(0)) end)
    pcall(function() bar:SetVisibility(0) end)
    local slot = safe_call(function() return layout.parent:AddChildToCanvas(bar) end)
    if not is_valid_obj(slot) then
        Logger.log("[PalBonds/Indicator] [BOSS] AddChildToCanvas failed for the trust bar — the HP bar's panel may not be a canvas")
        return
    end
    place_under_hp(slot, layout, layout.topEdge + layout.h + BOSS_BAR_GAP, boss_bar_height(layout))
    entry.bar = bar
    entry.lastRatio = nil
    Logger.log("[PalBonds/Indicator] [BOSS] trust bar built under the boss HP bar for " .. describe_pal(entry.actor))
end

local function build_boss_label(entry, layout)
    local nameW = safe_call(function() return layout.inner.Text_BossName end)
    local cls = is_valid_obj(nameW) and safe_call(function() return nameW:GetClass() end)
    if not is_valid_obj(cls) then
        Logger.log("[PalBonds/Indicator] [BOSS] could not read the boss name's text class — no tag")
        return
    end
    local label = safe_call(function()
        return StaticConstructObject(cls, layout.parent, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not is_valid_obj(label) then return end
    local slot = safe_call(function() return layout.parent:AddChildToCanvas(label) end)
    if not is_valid_obj(slot) then
        Logger.log("[PalBonds/Indicator] [BOSS] AddChildToCanvas failed for the tag")
        return
    end
    local y = layout.topEdge + layout.h + BOSS_BAR_GAP + boss_bar_height(layout) + BOSS_LABEL_GAP
    place_under_hp(slot, layout, y, BOSS_LABEL_HEIGHT)
    pcall(function() label:SetVisibility(0) end)
    local source = nil
    for _, field in ipairs(BOSS_LABEL_STYLE_FIELDS) do
        local t = safe_call(function() return layout.inner[field] end)
        if is_valid_obj(t) then source = t break end
    end
    style_personality_label(label, entry.widget, source)
    pcall(function() label:SetText_GDKInternal(true, "") end)
    entry.label = label
end

local function install_boss_display(key, pending)
    local widget = pending.widget
    local actor = safe_call(function() return widget.TargetCharacter end)
    if not is_valid_obj(actor) then actor = pending.actor end
    if not is_valid_obj(actor) then return false end
    local layout = boss_hp_layout(widget)
    if layout == nil then
        Logger.log("[PalBonds/Indicator] [BOSS] boss bar for " .. describe_pal(actor) .. " has no readable BossGaugeHP layout yet — will retry")
        return false
    end

    safe_call(Trust.MarkBossActor, actor)
    local entry = { widget = widget, actor = actor, palId = safe_call(Personality.GetStableId, actor),
        actorAddr = address_of_obj(actor) }
    build_boss_label(entry, layout)
    if Trust.HasBondingState(actor) then build_boss_bar(entry, layout) end
    bossEntries[key] = entry
    Logger.log(string.format("[PalBonds/Indicator] [BOSS] boss bar attached for %s (id %s) — tag=%s bar=%s",
        describe_pal(actor), tostring(entry.palId), tostring(entry.label ~= nil), tostring(entry.bar ~= nil)))
    return true
end

local function update_boss_entry(key, entry)
    if not is_valid_obj(entry.widget) then bossEntries[key] = nil return end
    local actor = safe_call(function() return entry.widget.TargetCharacter end)
    if not is_valid_obj(actor) then actor = entry.actor end
    if not is_valid_obj(actor) then return end

    local addr = safe_call(function() return actor:GetAddress() end)
    if entry.actorAddress == nil then
        entry.actorAddress = safe_call(function() return entry.actor:GetAddress() end)
    end
    if addr ~= nil and addr ~= entry.actorAddress then
        entry.actorAddress = addr
        entry.actor = actor
        entry.palId = safe_call(Personality.GetStableId, actor)
        entry.labelLastText, entry.lastRatio = nil, nil
    end
    if entry.bar == nil and Trust.HasBondingState(actor) then
        local layout = boss_hp_layout(entry.widget)
        if layout then build_boss_bar(entry, layout) end
    end
    if entry.bar ~= nil then
        local ratio = get_friendship_ratio(actor)
        if ratio and ratio ~= entry.lastRatio then
            entry.lastRatio = ratio
            pcall(function() entry.bar:SetPercent(ratio) end)
            pcall(function() entry.bar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
        end
    end
    if entry.label ~= nil and is_valid_obj(entry.label) then
        local disposition = entry.palId and Personality.GetDisposition(entry.palId)
        if disposition == nil and entry.palId ~= nil then
            local now = os.clock()
            if (now - (entry.stateTriedAt or -1e9)) >= LABEL_STATE_RETRY_SECONDS then
                entry.stateTriedAt = now
                safe_call(function() Personality.GetOrInitState(actor) end)
                disposition = Personality.GetDisposition(entry.palId)
            end
        end
        local text = personality_display_text(actor, disposition, entry.palId)
        if text ~= entry.labelLastText then
            entry.labelLastText = text
            local ok, err = pcall(function() entry.label:SetText_GDKInternal(true, text) end)
            if not ok then
                Logger.log("[PalBonds/Indicator] [BOSS] tag text write FAILED for " .. describe_pal(actor) .. ": " .. tostring(err))
            end
        end
    end
end

local function update_boss_displays()
    for key, pending in pairs(pendingBossGauges) do
        if not is_valid_obj(pending.widget) then
            pendingBossGauges[key] = nil
        elseif bossEntries[key] ~= nil or safe_call(install_boss_display, key, pending) then
            pendingBossGauges[key] = nil
        end
    end
    for key, entry in pairs(bossEntries) do
        safe_call(update_boss_entry, key, entry)
    end
end

local function queue_boss_gauge(widget, actor)
    if not is_valid_obj(widget) then return end
    local key = describe_widget(widget)
    if bossEntries[key] ~= nil then

        return
    end
    pendingBossGauges[key] = { widget = widget, actor = actor }
end

local function sweep_existing_boss_gauges()
    local list = safe_call(function() return FindAllOf("WBP_BossEnemyHPGauge_C") end)
    local n = 0
    if type(list) == "table" then
        for _, g in ipairs(list) do
            local name = safe_call(function() return g:GetFullName() end)

            if name and not tostring(name):find("Default__", 1, true) and is_valid_obj(g) then
                queue_boss_gauge(g, nil)
                n = n + 1
            end
        end
    end
    Logger.log("[PalBonds/Indicator] [BOSS] one-time check for boss bars already on screen: " .. n .. " found")
end

local BOSS_HOOK_FAST_ROUNDS = 30
local function register_boss_hook(round)
    round = round or 1
    if hasRegisteredBossHook then return end
    local ok, err = pcall(function()
        RegisterHook(BOSS_GAUGE_HOOK_PATH, function(Context, TargetCharacter)
            if world_is_closing() then return end

            Logger.trace("gauge.boss")
            local ok = pcall(function()
                queue_boss_gauge(hook_get(Context), hook_get(TargetCharacter))
            end)
            if not ok and not loggedBossHookThrow then
                loggedBossHookThrow = true
                Logger.log("[PalBonds/Indicator] [BOSS] the gauge hook's second invocation carries "
                    .. "different parameters and was skipped (logged once -- the bar still attaches "
                    .. "on the first)")
            end
            Logger.trace("gauge.boss.done")
        end)
    end)
    if ok then
        hasRegisteredBossHook = true
        Logger.log(string.format("[PalBonds/Indicator] [BOSS] boss bar hook INSTALLED (round %d): %s", round, BOSS_GAUGE_HOOK_PATH))
        pcall(function()
            ExecuteInGameThreadWithDelay(500, function() safe_call(sweep_existing_boss_gauges) end)
        end)
        return
    end
    local fast = round < BOSS_HOOK_FAST_ROUNDS
    if round == 1 or round == BOSS_HOOK_FAST_ROUNDS or round % 60 == 0 then
        Logger.log(string.format("[PalBonds/Indicator] [BOSS] boss bar hook not installable yet (round %d): %s — still retrying",
            round, tostring(err):match("^[^\n]*") or tostring(err)))
    end
    pcall(function()
        ExecuteInGameThreadWithDelay(fast and IMMEDIATE_BIND_HOOK_RETRY_MS or IMMEDIATE_BIND_HOOK_SLOW_RETRY_MS, function()
            safe_call(function() register_boss_hook(round + 1) end)
        end)
    end)
end

local GAUGE_FLAG_PRUNE_EVERY_N_SCANS = 30
local gaugeFlagScanCount = 0
local function scan_for_gauge_widgets()

    if guest_without_host_view() then return end

    if on_dedicated_server() then return end

    gaugeFlagScanCount = gaugeFlagScanCount + 1
    if gaugeFlagScanCount % GAUGE_FLAG_PRUNE_EVERY_N_SCANS == 0 then
        for k, w in pairs(barInstalledForGauge) do
            if type(w) ~= "userdata" and type(w) ~= "table"
                or not safe_call(function() return w:IsValid() end) then
                barInstalledForGauge[k] = nil
            end
        end
    end

    local okShut, CombatShut = pcall(require, "Combat")
    if okShut and CombatShut and CombatShut.IsShuttingDown and CombatShut.IsShuttingDown() then
        return
    end

    local builtThisSweep = 0
    for key, g in pairs(pendingGauges) do
        if builtThisSweep >= MAX_BARS_BUILT_PER_SWEEP then break end
        builtThisSweep = builtThisSweep + 1
        if not safe_call(function() return g:IsValid() end) then
            pendingGauges[key] = nil
        else
            safe_call(function() install_trust_bar(g) end)
            if barInstalledForGauge[key] then pendingGauges[key] = nil end
        end
    end

    local runWorldSweep
    if not hasRegisteredBindHook then
        runWorldSweep = true
    elseif nameplateSweepsSinceHook < NAMEPLATE_SWEEPS_AFTER_HOOK then
        nameplateSweepsSinceHook = nameplateSweepsSinceHook + 1
        runWorldSweep = true
    else
        runWorldSweep = (gaugeFlagScanCount % NAMEPLATE_SAFETY_SWEEP_EVERY_N_SCANS) == 0
    end
    if runWorldSweep then
        safe_call(function()
            local gauges = FindAllOf("WBP_PalNPCHPGauge_C")
            if gauges == nil then return end
            for _, g in ipairs(gauges) do
                if g ~= nil and safe_call(function() return g:IsValid() end) then
                    safe_call(function() install_trust_bar(g) end)
                end
            end
        end)
    end

    update_trust_bars()

    update_boss_displays()

end

local function scheduleScan()
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(SCAN_INTERVAL_MS, function()
            Logger.trace("nameplate scan start")
            safe_call(scan_for_gauge_widgets)
            Logger.trace("nameplate scan end")
            scheduleScan()
        end)
    end)
    if not ok then
        Logger.log("[PalBonds/Indicator] ExecuteInGameThreadWithDelay failed to schedule the nameplate scan")
    end
end
function Indicator.Init()

    register_bind_hook_immediate()

    register_boss_hook()

    scheduleScan()
end

function Indicator.ForgetJoinedPal(palId, actorAddr)
    local n = 0
    local function matches(key, entry)
        if palId ~= nil and (key == palId or (type(entry) == "table" and entry.palId == palId)) then return true end
        if actorAddr ~= nil and type(entry) == "table" and entry.actorAddr == actorAddr then return true end
        return false
    end
    for _, t in ipairs({ trackedBars, bossEntries, pendingBossGauges }) do
        for key, entry in pairs(t) do
            if matches(key, entry) then t[key] = nil; n = n + 1 end
        end
    end
    return n
end

function Indicator.HeldReferencesFor(palId, actorAddr)
    local n = 0
    for _, t in ipairs({ trackedBars, bossEntries, pendingBossGauges }) do
        for key, entry in pairs(t) do
            if (palId ~= nil and (key == palId or (type(entry) == "table" and entry.palId == palId)))
                or (actorAddr ~= nil and type(entry) == "table" and entry.actorAddr == actorAddr) then
                n = n + 1
            end
        end
    end
    return n
end

local function keep_new_world_binds()
    local now = os.clock()
    local keptHandles, keptBoundAt, keptPending, kept = {}, {}, {}, 0
    for key, handle in pairs(gaugeHandleByKey) do
        local at = gaugeBoundAt[key]
        if at ~= nil and (now - at) <= NEW_WORLD_BIND_GRACE_SECONDS then
            keptHandles[key] = handle
            keptBoundAt[key] = at
            local widget = pendingGauges[key] or barInstalledForGauge[key]
            if widget ~= nil and widget ~= true then keptPending[key] = widget end
            kept = kept + 1
        end
    end
    return keptHandles, keptBoundAt, keptPending, kept
end

function Indicator.BindCounts()
    local h, p, b = 0, 0, 0
    for _ in pairs(gaugeHandleByKey) do h = h + 1 end
    for _ in pairs(pendingGauges) do p = p + 1 end

    for _ in pairs(trackedBars) do b = b + 1 end
    return h, p, b
end

function Indicator.ResetForNewWorld()
    local bars, bosses = 0, 0
    for _ in pairs(trackedBars) do bars = bars + 1 end
    for _ in pairs(bossEntries) do bosses = bosses + 1 end
    local keptHandles, keptBoundAt, keptPending, kept = keep_new_world_binds()
    pendingGauges = keptPending
    gaugeHandleByKey = keptHandles
    gaugeBoundAt = keptBoundAt
    barInstalledForGauge = {}
    trackedBars = {}
    pendingBossGauges = {}
    bossEntries = {}
    nameplateSweepsSinceHook = 0
    Logger.log(string.format(
        "[PalBonds/Indicator] [WORLD-RESET] dropped %d tracked nameplate bar(s) and %d boss bar(s) from the old world; kept %d nameplate bind(s) the new world had already made",
        bars, bosses, kept))
end
return Indicator
