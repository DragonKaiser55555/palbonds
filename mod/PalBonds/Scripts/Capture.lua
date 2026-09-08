--[[
    Capture.lua — DESIGN.md §3.5 and §3.6

    Two threshold events land here, now wired from the real Trust.lua
    (2026-09-01) instead of being dead stubs:
      - Rank hits CAPTURE_AT_RANK (Trust.lua, currently rank 1) ->
        sphere-less guaranteed capture into the party.
      - Rank drops to 0 after having bonded (damage or leaving the
        player too far behind, per Dragón's spec) -> Pal is done: stops
        following and is permanently flagged as no longer bondable, same
        as DESIGN.md §3.6 originally described.

    The capture side has direct precedent: "Human Mercy Bypass", "Catch
    Gun", and "Capture the Uncapturables" on Nexus all already perform
    sphere-less guaranteed captures. STILL A STUB as of this pass — the
    actual capture UFunction (hook-points.md question 4) hasn't been
    found/tried yet. OnTrustMaxed below fires and logs clearly when the
    real threshold is met, but doesn't yet capture anything. That's the
    next concrete piece of work once Trust.lua's rank-tracking is
    confirmed working live.

    THIRTY-EIGHTH PASS (2026-09-02): Dragón asked directly to keep moving
    toward finishing the mod rather than researching indefinitely. Static
    research on Question 4 hit its ceiling last pass (see hook-points.md,
    thirty-seventh pass) — no cleaner candidate than
    `UPalUtility.PalCaptureSuccess(Player, Monster)` exists in the
    reflected header dump, and it's the single most-reliably-observed
    function in the whole project (fired correctly on all three real
    sphere captures tested). `Capture.TryDirectCapture` below is the
    actual experiment: call it directly on a wild Pal that never went
    through a real sphere throw, and see what happens. See the function's
    own comment for the full risk breakdown — bound to its own dedicated
    key (F11 in Interaction.lua), deliberately NOT wired into the
    automatic OnTrustMaxed flow yet, so one bad result stays contained to
    a single manual test.

    THIRTY-NINTH PASS (2026-09-02): CONFIRMED LIVE. Dragón tested F11 on
    three different wild Pals (Sheepball, Cattiva, and a Mammorest —
    large/boss-tier) — all three joined his real party, no sphere, no
    crash. DESIGN.md Question 4 is answered. OnTrustMaxed below now calls
    Capture.TryDirectCapture for real instead of just logging "would
    capture here". Only cosmetic gap noticed: no capture VFX/light-beam
    animation played (the one that plays when freeing a Pal from a cage)
    — not a functional problem, a possible future polish item if wanted.
]]

local Logger = require("Logger")
local Combat = require("Combat")
-- Hundred-and-fifty-sixth pass (2026-09-04): for real fleeing on trust
-- loss (Personality.ForceTier below) — safe top-level require, no cycle:
-- Personality.lua only ever requires Capture lazily, inside function
-- bodies (pcall(require, "Capture")), never at file-load time, and
-- main.lua's own require order already loads Personality before Capture.
local Personality = require("Personality")
-- Two-hundred-and-thirteenth pass: FindOrAddFName, to build real FNames for
-- the localisation-id candidates in resolve_pal_display_name. Same bundled
-- helper Interaction.lua already uses for exactly this reason.
local UEHelpers = require("UEHelpers")

-- EPalLocalizeTextCategory::PalMonsterName, read from this build's own
-- Pal_enums.hpp dump (two-hundred-and-ninth pass) — used for the join toast.
local PAL_LOCALIZE_CATEGORY_MONSTER_NAME = 4

local Capture = {}

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

-- Cached CDO lookup, same pattern as Personality.lua's get_pal_utility().
local PalUtilityCDO = nil
local function get_pal_utility()
    if PalUtilityCDO then return PalUtilityCDO end
    PalUtilityCDO = safe_call(function()
        return StaticFindObject("/Script/Pal.Default__PalUtility")
    end)
    return PalUtilityCDO
end

-- Reads the real OwnerPlayerUId off a live Pal actor, same field access
-- pattern already proven safe in Interaction.lua (a plain field read, NOT
-- the whole-struct-by-value GetSaveParameter() call that caused this
-- project's three earlier crashes). nil if anything along the chain
-- fails or the Pal has no owner yet (wild).
local function read_owner_id(pal)
    return safe_call(function()
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return nil end
        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return nil end
        return param.SaveParameter and param.SaveParameter.OwnerPlayerUId
    end)
end

-- THIRTY-EIGHTH PASS (2026-09-02) — the project's first genuinely
-- experimental (not just cautious-but-safe) live call. Calls the real
-- `UPalUtility.PalCaptureSuccess(Player, Monster)` directly on a wild Pal
-- that never went through an actual sphere throw, to find out once and
-- for all whether this is the real sphere-less "hand this Pal to the
-- player" mechanism DESIGN.md's Question 4 has been looking for since
-- the project started.
--
-- WHAT WE ALREADY KNOW (strong evidence, not a guess): this exact
-- function, with exactly these two arguments, fires 100% of the time on
-- every real sphere capture tested (three separate captures, three
-- separate species, see hook-points.md's twenty-ninth/thirty-sixth
-- passes) — the single most reliable observation in the whole project.
--
-- WHAT WE DON'T KNOW, and this call is designed to find out:
--   - Best case: the Pal actually joins the party/palbox. This would be
--     the answer to Question 4, full stop.
--   - Middle case: nothing real happens (maybe a UI popup or particle
--     effect fires, but no actual ownership change) — a clean, safe
--     negative result. Rules this function out without having risked
--     anything except one wild Pal's normal behavior for a moment.
--   - A pcall-caught Lua error — also a clean, safe negative result,
--     fully contained.
--   - WORST CASE, which cannot be fully ruled out from Lua: this
--     function may assume some earlier step a real sphere throw performs
--     (state we can't see from a header dump) already happened, and
--     calling it without that could misbehave more seriously — up to and
--     including a hard native engine crash, which pcall CANNOT catch
--     (pcall only catches Lua-level errors). This is why it's bound to
--     its own dedicated key, not wired into automatic play, and why
--     Dragón should save the game first and pick a common, low-value
--     wild Pal to test on — see Interaction.lua's F11 binding and the
--     instructions given alongside this pass.
--
-- Every log line here is written and flushed BEFORE the risky call
-- itself (see Logger.lua) specifically so that even a hard crash still
-- leaves a clear "here's the last thing that happened" trail on disk.
function Capture.TryDirectCapture(pal, player)
    local palName = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format("[PalBonds/Capture] [EXPERIMENT] TryDirectCapture starting on %s", tostring(palName)))

    if pal == nil or not pal:IsValid() then
        Logger.log("[PalBonds/Capture] [EXPERIMENT] target Pal is not valid — aborting, nothing risky called")
        return
    end
    if player == nil or not player:IsValid() then
        Logger.log("[PalBonds/Capture] [EXPERIMENT] no valid player — aborting, nothing risky called")
        return
    end

    local ownerBefore = read_owner_id(pal)
    Logger.log(string.format("[PalBonds/Capture] [EXPERIMENT] owner BEFORE the call = %s (this line is flushed to disk before the risky call below runs)", tostring(ownerBefore)))

    local utility = get_pal_utility()
    if utility == nil then
        Logger.log("[PalBonds/Capture] [EXPERIMENT] could not resolve PalUtility — aborting, nothing risky called")
        return
    end

    -- THE RISKY CALL. Everything above this line is read-only and safe.
    local callOk, callErr = pcall(function()
        utility:PalCaptureSuccess(player, pal)
    end)
    Logger.log(string.format("[PalBonds/Capture] [EXPERIMENT] PalCaptureSuccess call returned — result=%s", callOk and "ok (no Lua-level error — doesn't yet mean it worked, just that nothing threw)" or ("Lua ERROR: " .. tostring(callErr))))

    local stillValid = safe_call(function() return pal:IsValid() end)
    Logger.log(string.format("[PalBonds/Capture] [EXPERIMENT] target actor still valid immediately after = %s", tostring(stillValid)))

    if stillValid then
        local ownerAfter = read_owner_id(pal)
        Logger.log(string.format(
            "[PalBonds/Capture] [EXPERIMENT] owner AFTER the call = %s (compare to BEFORE=%s — a real change here would be strong evidence this actually worked)",
            tostring(ownerAfter), tostring(ownerBefore)
        ))
    end

    Logger.log("[PalBonds/Capture] [EXPERIMENT] TryDirectCapture finished — the real answer is what you see in-game: did this Pal vanish from the world AND show up in your party or Palbox? Check both.")
end

-- Hundred-and-thirtieth pass (2026-09-03): real in-game toast notification,
-- confirmed via a third reference mod Dragón provided ("QuickConsumableSlots"),
-- which uses this exact mechanism for its own on-screen messages. Real
-- chain, all native/existing objects, nothing constructed from scratch:
-- `PalUtility:GetLogManager(player)` returns a real per-player log/toast
-- manager; its `OverrideClassMap` field holds a set of real UClass
-- references, one of which (found by its name containing "BlinkedLog") is
-- the actual toast widget class used for on-screen messages;
-- `KismetTextLibrary:Conv_StringToText(message)` converts a plain Lua
-- string into a real FText; `manager:AddLog(1, text, {OverrideWidgetClass
-- = widgetClass, LogToneType = tone})` is what actually shows it on
-- screen. This directly answers DESIGN.md's "in-game join text" backlog
-- item — a real, already-proven mechanism from a working mod, not a guess
-- at an unverified function.
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

-- Shows a real on-screen toast to `player`. Every step is wrapped so a
-- failure here (e.g. this game build's log manager shape differs) can
-- never interrupt the actual capture — worst case, no message appears.
-- `tone`: 0/1/2 observed in the reference mod (0 used for a plain "used
-- item" message, 1 for errors, 2 for a positive "registered" confirmation)
-- — 2 is used below since a Pal joining is good news.
-- Two-hundred-and-eleventh pass (2026-09-06) — THE ACTUAL TOAST BUG.
--
-- Dragón's log gave the exact error, which is far more useful than his
-- symptom report ("no text at all"):
--     Capture.lua:282: attempt to concatenate a FString value (local 'palName')
--
-- So the name lookup WORKED. `GetLocalizedText` returned a real FText and
-- `Conv_TextToString` returned a real value — but that value is an FString
-- USERDATA wrapper, not a Lua string, and concatenating it raises an error.
-- The previous pass's fix (resolving before the capture) was also correct and
-- necessary; this was a second, independent bug sitting behind it, which is
-- why the toast went from "generic text" to "no text at all" — the error now
-- happens after the message would have been built, so nothing is shown.
--
-- UE4SS FString/FName wrappers expose :ToString(); a plain Lua string does
-- not, so this handles both and never assumes which it got.
local function to_lua_string(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local s = safe_call(function() return v:ToString() end)
    if type(s) == "string" then return s end
    -- Last resort: tostring() gives "FString: 0x..." which is useless as a
    -- display name, so reject it rather than showing an address to the player.
    return nil
end

-- Two-hundred-and-tenth pass (2026-09-06) — split out of NotifyJoined, and
-- this split IS the bug fix.
--
-- Dragón reported the new named toast never appeared. The log proves the new
-- code ran (the "[NOTIFY] join message:" line is new this pass) but fell all
-- the way through to the generic fallback, meaning BOTH the localized lookup
-- AND the raw-CharacterID fallback failed. The reason is ordering, not the
-- name lookup itself: NotifyJoined is called AFTER TryDirectCapture, and by
-- then the Pal has already been handed to the player — the same log line
-- shows "owner AFTER the call = nil". The actor is mid-teardown, so its
-- CharacterParameterComponent chain no longer resolves and every name route
-- fails at the first step.
--
-- This is the exact bug class the two-hundred-and-fourth pass already fixed
-- once in diagnose_post_capture_slot (resolving a handle after the capture
-- instead of before). Same lesson, missed a second time: ANYTHING that needs
-- to read from the Pal must read it BEFORE PalCaptureSuccess runs.
--
-- So the name is now resolved up-front, next to preCaptureHandle (which
-- exists for precisely this reason), and passed in as a plain string that
-- survives the capture.
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
            -- Two-hundred-and-fourteenth pass (2026-09-06) — SOLVED, format
            -- confirmed from Dragón's run. The [NAME-DIAG] probe answered it
            -- cleanly on three separate captures:
            --     candidate 1 (Monkey_Fire)          -> Monkey_Fire      (the id echoed back)
            --     candidate 3 (PAL_NAME_Monkey_Fire) -> Tanzee Ignis     (the real name)
            -- So the localisation key is "PAL_NAME_" .. CharacterID, and the
            -- bare CharacterID returns itself rather than failing, which is
            -- why the earlier attempts looked like they "worked" while
            -- printing internal ids.
            --
            -- Hard-coded now and the candidate loop removed: it cost three
            -- GetLocalizedText round-trips per capture to re-derive a settled
            -- answer every time.
            local rawId = to_lua_string(safe_call(function() return charId:ToString() end))
            if rawId then
                local key = safe_call(function() return UEHelpers.FindOrAddFName("PAL_NAME_" .. rawId) end)
                if key ~= nil then
                    local localized = safe_call(function()
                        return masterData:GetLocalizedText(player, PAL_LOCALIZE_CATEGORY_MONSTER_NAME, key)
                    end)
                    local asString = to_lua_string(localized and safe_call(function() return textLibrary:Conv_TextToString(localized) end))
                    if asString ~= nil and asString ~= "" and asString ~= rawId then
                        palName = asString
                        return
                    end
                end
            end
        end

        -- Fallback: the raw internal id, still better than "A wild Pal".
        local raw = to_lua_string(safe_call(function() return charId:ToString() end))
        if raw ~= nil and raw ~= "" then palName = raw end
    end)
    Logger.log("[PalBonds/Capture] [NOTIFY] resolved display name BEFORE capture = " .. tostring(palName))
    return palName
end

function Capture.NotifyJoined(pal, player, preResolvedName)
    local ok, err = pcall(function()
        local utility = get_pal_utility()
        if utility == nil then return end
        local manager = safe_call(function() return utility:GetLogManager(player) end)
        if manager == nil then return end
        local widgetClass = resolve_toast_widget_class(manager)
        if widgetClass == nil then return end
        local textLibrary = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
        if textLibrary == nil then return end
        -- Two-hundred-and-tenth pass: the name is resolved BEFORE the
        -- capture (see resolve_pal_display_name above for why) and handed in
        -- here, so this function never touches the mid-teardown Pal actor.
        -- Two-hundred-and-forty-fifth pass (2026-09-07). Reworded, and lengthened
        -- to sit alongside the two bond-lost messages rather than beside them —
        -- all three are now two short sentences, so the good news and the bad
        -- news read as the same kind of event rather than one feeling like an
        -- afterthought.
        --
        --   join       "X has chosen to go with you. It trusts you completely."
        --   betrayed   "X no longer trusts you. It will not bond with you again."
        --   abandoned  "X was left behind and gave up on you."
        --
        -- "chosen to go with you" replaces "decided to join your party": party is
        -- interface vocabulary, and the point of this mod is that the Pal made a
        -- choice rather than that a roster slot was filled.
        local palName = preResolvedName
        local message
        if palName then
            message = palName .. " has chosen to go with you. It trusts you completely."
        else
            message = "A wild Pal has chosen to go with you."
        end
        Logger.log("[PalBonds/Capture] [NOTIFY] join message: " .. message)

        local text = safe_call(function() return textLibrary:Conv_StringToText(message) end)
        if text == nil then return end
        manager:AddLog(1, text, { OverrideWidgetClass = widgetClass, LogToneType = 2 })
    end)
    if ok then
        Logger.log("[PalBonds/Capture] [NOTIFY] join toast shown")
    else
        Logger.log("[PalBonds/Capture] [NOTIFY] failed to show join toast (non-fatal, caught): " .. tostring(err))
    end
end

-- Eighty-second pass (2026-09-03) CRITICAL FIX: shared ownership check so
-- Trust.lua can bail out BEFORE any interaction-count/capture-threshold
-- logic runs on a Pal that's already owned. Full incident writeup in
-- Trust.lua's OnInteractionSucceeded comment and docs/hook-points.md's
-- eighty-second pass — short version: Trust.lua had ZERO ownership check,
-- so the first time a frequently-used real path (the eighty-first pass's
-- vanilla worker-menu hook) started calling it on Dragón's own base
-- Pals, their real (already sky-high) FriendshipPoint instantly crossed
-- the capture threshold and this project's real PalCaptureSuccess call
-- fired on Pals that were already his — one (a boss-tier Petallia) got
-- auto-added to his party and dropped capture-reward loot; a second,
-- lower-friendship Pal was also re-captured.
--
-- Reads the same OwnerPlayerUId field `read_owner_id` above already uses
-- (a plain nested-field read, not the whole-struct `GetSaveParameter()`
-- call that caused this project's three earlier crashes), then checks
-- its four raw components (FGuid = {A,B,C,D}, all int32 — confirmed in
-- CoreUObject.hpp) against all-zero: Unreal's own convention for "never
-- assigned" on a default-constructed FGuid, which is what a genuinely
-- wild Pal's OwnerPlayerUId reads as (the field always exists as a class
-- member on every Pal; it's simply never been written for one that's
-- never been captured).
--
-- FAILS SAFE ON PURPOSE: if anything here can't be read, for any reason,
-- this returns true (treat as owned -> caller skips) rather than false
-- (treat as wild -> caller proceeds). A false negative here just means
-- normal trust bookkeeping silently doesn't run for one Pal on one
-- interaction — a minor, invisible miss. A false positive is exactly
-- what caused the real incident above. The asymmetry is deliberate.
-- Two-hundred-and-forty-first pass (2026-09-07) — REAL BUG, caught by Dragón:
-- one of his own BASE WORKERS was petted and then captured by this mod.
--
-- From the log, unmistakable: `BP_Monkey_Fire_C` ("Tanzee Ignis"), running
-- `BP_AIAction_BaseCampWorker_Approach_C`, at real friendship rank 3 with 21000
-- points, was granted +30 by a radial Pet and captured seconds later.
--
-- The guard below was checking exactly one thing: SaveParameter.OwnerPlayerUId.
-- That is correct for a Pal in the player's own party or Palbox, and WRONG for a
-- base-camp worker, which belongs to the BASE (and, through it, the guild)
-- rather than to a player UId — so its OwnerPlayerUId is a zero GUID and this
-- function cheerfully reported "wild".
--
-- Two things then compounded it into a capture rather than a harmless pet. The
-- Pal's real vanilla friendship (21000) is measured against this mod's own
-- bonding threshold, which is 500 scaled by the level gap — and at pal level 12
-- versus player level 52 the multiplier was 0.2x, giving a threshold of 125.
-- 21000 against 125 is a ratio of 168, so the bar was not merely crossed, it was
-- never in play. That scale collision is only safe as long as owned Pals never
-- reach this code at all, which is precisely what this guard is for.
--
-- Two extra tests, both real functions on UPalCharacterParameterComponent (the
-- component this file already reads), confirmed in the SDK header rather than
-- guessed:
--   * IsOtomo()        — true for an active companion
--   * GetBaseCampId()  — a non-zero GUID for anything assigned to a base camp
--
-- Each is evaluated in its own pcall so that an older or newer build missing one
-- of them degrades to the remaining checks instead of failing the whole guard.
-- Every ambiguous outcome still resolves to "owned", which is the safe direction
-- here: refusing to bond with a wild Pal is a disappointment, capturing someone's
-- base worker is data loss.
local function guid_is_zero(g)
    if g == nil then return true end
    return (g.A == 0) and (g.B == 0) and (g.C == 0) and (g.D == 0)
end

function Capture.IsAlreadyOwned(pal)
    local ok, result = pcall(function()
        if pal == nil or not pal:IsValid() then return true end
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return true end

        -- An active companion. Cheapest test, so it goes first.
        local isOtomoOk, isOtomo = pcall(function() return comp:IsOtomo() end)
        if isOtomoOk and isOtomo == true then return true end

        -- Assigned to a base camp: the case that produced the bug.
        local campOk, campId = pcall(function() return comp:GetBaseCampId() end)
        if campOk and not guid_is_zero(campId) then return true end

        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return true end
        local ownerId = param.SaveParameter and param.SaveParameter.OwnerPlayerUId
        if ownerId == nil then return true end
        return not guid_is_zero(ownerId)
    end)
    if ok then return result end
    return true -- pcall itself failed -> safe default: treat as owned
end

-- Pals that hit 0 trust after bonding and can never be interacted with
-- again outside of a normal forced capture. Keyed by GetFullName(), same
-- as Trust.lua/Combat.lua this pass (see Trust.lua's header for why
-- FPalInstanceID isn't used yet).
local PermanentlyFled = {}

-- Two-hundred-and-tenth pass (2026-09-06) — CAGE VFX PROBE, read-only.
--
-- This should have shipped last pass. I told Dragón that finding a Pal cage
-- would unblock the join VFX, and he went to an enemy settlement and rescued
-- a Pal ("swee") specifically to provide one — but no diagnostic existed to
-- read anything from it, so that trip produced no data. My omission.
--
-- What this reads, all confirmed present in this build's header dump:
--   class APalCapturedCage : public AActor
--       void StartCaptureEffect_ServerBP(class APalPlayerCharacter* Player)
--   class ABP_PalCapturedCage_C : public APalCapturedCage
--       class UNiagaraComponent* Niagara;   // 0x0308
--
-- The goal is the Niagara ASSET the cage plays when a Pal is freed — the
-- "Pal turns into light and travels into the player" effect Dragón wants at
-- capture. Once we have its object path, it can be spawned at a bonded Pal's
-- location without needing a cage present at all.
--
-- Strictly read-only: it resolves objects and reads fields. It never calls
-- StartCaptureEffect_ServerBP, never touches a cage, and cannot affect
-- gameplay. Two routes, because either may work:
--   1. Live instances via FindAllOf — best, reflects real in-world state.
--   2. The class default object — works even with no cage nearby, as long as
--      the class has been loaded at least once (Dragón's rescue did that).
local cageProbeDone = false
local CAGE_PROBE_MAX_ROUNDS = 180 -- ~30 minutes at 10s: a cage only appears when the player reaches one
local CAGE_PROBE_RETRY_MS = 10000

local function probe_cage_vfx(round)
    if cageProbeDone then return end
    round = round or 1

    local found = false
    safe_call(function()
        local cages = FindAllOf("BP_PalCapturedCage_C") or FindAllOf("PalCapturedCage")
        if cages then
            for _, cage in ipairs(cages) do
                local valid = safe_call(function() return cage:IsValid() end)
                if valid then
                    local comp = safe_call(function() return cage.Niagara end)
                    local compValid = comp ~= nil and safe_call(function() return comp:IsValid() end)
                    local assetName, assetPresent = nil, false
                    if compValid then
                        local asset = safe_call(function() return comp.Asset end)
                        assetPresent = (asset ~= nil)
                        if asset ~= nil then
                            assetName = safe_call(function() return asset:GetFullName() end)
                                     or safe_call(function() return asset:GetPathName() end)
                        end
                    end
                    Logger.log(string.format(
                        "[PalBonds/Capture] [CAGE-VFX] LIVE cage=%s | comp present=%s | asset present=%s | asset name=%s",
                        tostring(safe_call(function() return cage:GetFullName() end)),
                        tostring(comp ~= nil), tostring(assetPresent), tostring(assetName)
                    ))
                    if assetName then found = true end
                end
            end
        end
    end)

    if not found then
        safe_call(function()
            local cdo = StaticFindObject("/Game/Pal/Blueprint/MapObject/Cage/BP_PalCapturedCage.Default__BP_PalCapturedCage_C")
            if cdo == nil then
                Logger.log("[PalBonds/Capture] [CAGE-VFX] round " .. round .. ": no live cage and the CDO path did not resolve — will retry")
                return
            end
            -- Two-hundred-and-eleventh pass FIX: the previous version's log
            -- line conflated "the object is nil" with "GetFullName failed on
            -- it", printing "nil" for both — and then declared the probe done
            -- anyway. Dragón's log shows exactly that: "NiagaraComponent=nil
            -- Asset=nil" immediately followed by "asset resolved — probe
            -- done", which is self-contradictory and meant the probe stopped
            -- without ever having read anything. Presence and name are now
            -- reported separately, and success requires a real NAME STRING.
            local comp = safe_call(function() return cdo.Niagara end)
            local asset = comp and safe_call(function() return comp.Asset end)
            local assetName = nil
            if asset ~= nil then
                assetName = safe_call(function() return asset:GetFullName() end)
                         or safe_call(function() return asset:GetPathName() end)
            end
            Logger.log(string.format(
                "[PalBonds/Capture] [CAGE-VFX] CDO cage | comp present=%s | asset present=%s | asset name=%s",
                tostring(comp ~= nil), tostring(asset ~= nil), tostring(assetName)
            ))
            if assetName then found = true end
        end)
    end

    if found then
        cageProbeDone = true
        Logger.log("[PalBonds/Capture] [CAGE-VFX] a real asset NAME was read — probe done, will not run again this session")
        return
    end
    -- Two-hundred-and-eleventh pass: keep polling far longer, and never stop
    -- on a failed read. The previous version ran once at startup, misread its
    -- own result as success, and stopped — so when Dragón went out of his way
    -- to rescue a Pal from a real cage, nothing was still watching for it.
    -- A cage only exists in the world once the player is near one, so this
    -- has to stay alive across the whole session, not just the first seconds.
    if round >= CAGE_PROBE_MAX_ROUNDS then
        Logger.log("[PalBonds/Capture] [CAGE-VFX] no cage seen after " .. round .. " rounds — stopping. Nothing was read; this is NOT a result.")
        return
    end
    pcall(function()
        ExecuteInGameThreadWithDelay(CAGE_PROBE_RETRY_MS, function()
            safe_call(function() probe_cage_vfx(round + 1) end)
        end)
    end)
end

-- Two-hundred-and-twelfth pass (2026-09-06) — hook the rescue MOMENT itself.
--
-- Dragón asked whether he still needs to rescue a Pal for the next run. He
-- does, and this is what makes that trip actually pay off instead of being
-- wasted a third time. Reasoning, stated plainly:
--
--   * The class-default-object route is unlikely to work. A Blueprint CDO
--     usually does not carry live component references, which matches what
--     his log showed. It is kept as a free fallback, not relied on.
--   * The live route needs a real cage actor, and a cage only exists in the
--     world while the player is physically near one. There is no way around
--     that: the asset reference lives on the instance.
--
-- The polling probe alone only catches a cage if a poll tick happens to land
-- while he is near it. This hook removes that luck entirely: it fires exactly
-- when the rescue effect starts, with the live cage handed to us as Context —
-- the single best possible moment to read the Niagara asset.
--
-- Strictly read-only. It is a POST hook that observes and never calls
-- StartCaptureEffect_ServerBP itself, so it cannot trigger or alter the
-- vanilla rescue in any way.
-- Two-hundred-and-thirteenth pass (2026-09-06) — THE JOIN VFX, finally real.
--
-- Dragón's cage rescue produced the breakthrough. The probe read the cage's
-- Niagara asset:
--     NiagaraSystem /Game/Pal/Effect/Common/Glow/NS_SingleStar.NS_SingleStar
-- That is NOT the effect he wants — "Glow/NS_SingleStar" is the little
-- sparkle marker on the cage itself. But knowing the asset PATH FORMAT was
-- enough: searching UE4SS_ObjectDump.txt for NiagaraSystems under
-- /Game/Pal/Effect/ turned up a whole folder built for exactly this moment:
--
--     /Game/Pal/Effect/Common/PalCatch/NS_PalCatch_Success
--     /Game/Pal/Effect/Common/PalCatch/NS_PalDisappear   (and 01 / 02)
--     /Game/Pal/Effect/Common/PalCatch/NS_PalAppear
--     /Game/Pal/Effect/Common/Return/NS_Return
--
-- What Dragón described is "a VFX of the Pal turning into light and
-- travelling into the player", so NS_PalDisappear is the closest single
-- match: the Pal dissolving into light at its own position. The others are
-- listed above deliberately — if this one looks wrong in game, switching is a
-- one-line change, no new research needed.
--
-- Spawning uses UNiagaraFunctionLibrary::SpawnSystemAtLocation, confirmed
-- present in this build's Niagara.hpp with this exact signature:
--     SpawnSystemAtLocation(WorldContextObject, SystemTemplate, Location,
--                           Rotation, Scale, bAutoDestroy, bAutoActivate,
--                           PoolingMethod, bPreCullCheck)
--
-- Fired from play_join_celebration_then, at the Pal's own location, right
-- before the real capture — so the sequence becomes: happy reaction ->
-- dissolve into light -> vanish -> named toast. That closes the "smiles then
-- instantly disappears with nothing in between" gap Dragón has been
-- describing for many passes.
--
-- Fully pcall-guarded and purely cosmetic: if any step fails the capture
-- itself is completely unaffected.
-- Two-hundred-and-fourteenth pass (2026-09-06): the pipeline is CONFIRMED
-- working — Dragón's log shows "spawned ... component=true" on all four
-- captures, and he saw an effect play. It was just the wrong one: he
-- described "something that looked like a vanish sphere animation but it
-- wasn't fitting", which fits NS_PalDisappear exactly (that is the recall-
-- into-sphere effect).
--
-- Rather than burn one whole test run per candidate, the list below is now
-- cyclable in-game with CTRL+V (see Interaction.lua). Each press plays the
-- next one on the Pal being aimed at and logs which index it was, so all of
-- them can be judged in a single session. Once Dragón says which index looks
-- right, JOIN_VFX_INDEX gets set to it and the key goes away.
local JOIN_VFX_CANDIDATES = {
    "/Game/Pal/Effect/Common/PalCatch/NS_PalCatch_Success.NS_PalCatch_Success",
    "/Game/Pal/Effect/Common/Return/NS_Return.NS_Return",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalAppear.NS_PalAppear",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear01.NS_PalDisappear01",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear02.NS_PalDisappear02",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalCatch.NS_PalCatch",
    "/Game/Pal/Effect/Common/PalCatch/NS_PalDisappear.NS_PalDisappear", -- the one already rejected, kept last for comparison
}
-- Which candidate the real capture uses. 1 = NS_PalCatch_Success, the most
-- likely fit for "the Pal joined you" now that the recall-vanish is ruled out.
local JOIN_VFX_INDEX = 1
local JOIN_VFX_ASSET_PATH = JOIN_VFX_CANDIDATES[JOIN_VFX_INDEX]
-- Alternatives, if the above reads wrong in game (swap the path, nothing else):
--   /Game/Pal/Effect/Common/PalCatch/NS_PalCatch_Success.NS_PalCatch_Success
--   /Game/Pal/Effect/Common/Return/NS_Return.NS_Return
--   /Game/Pal/Effect/Common/PalCatch/NS_PalDisappear01.NS_PalDisappear01
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
                pal,                              -- WorldContextObject
                system,                           -- SystemTemplate
                loc,                              -- Location
                {Pitch = 0.0, Yaw = 0.0, Roll = 0.0},
                {X = 1.0, Y = 1.0, Z = 1.0},
                true,                             -- bAutoDestroy
                true,                             -- bAutoActivate
                0,                                -- ENCPoolMethod::None
                true                              -- bPreCullCheck
            )
        end)
        Logger.log("[PalBonds/Capture] [JOIN-VFX] spawned " .. assetPath ..
            " at the joining Pal — component=" .. tostring(comp ~= nil))
    end)
end

-- Two-hundred-and-fourteenth pass: CTRL+V preview. Plays the next candidate
-- effect on a given Pal and says which index it was, so Dragón can judge every
-- option in one session instead of one per test run. Temporary, and already on
-- the release-cleanup list.
local vfxPreviewIndex = 0
function Capture.PreviewNextJoinVfx(pal)
    if pal == nil or not pal:IsValid() then
        Logger.log("[PalBonds/Capture] [VFX-PREVIEW] no Pal aimed at — point at a Pal and press again")
        return
    end
    vfxPreviewIndex = (vfxPreviewIndex % #JOIN_VFX_CANDIDATES) + 1
    local path = JOIN_VFX_CANDIDATES[vfxPreviewIndex]
    Logger.log(string.format("[PalBonds/Capture] [VFX-PREVIEW] playing candidate %d of %d: %s",
        vfxPreviewIndex, #JOIN_VFX_CANDIDATES, path))
    spawn_niagara_at(pal, path)
end

local function install_cage_effect_hook()
    local ok, err = pcall(function()
        RegisterHook("/Script/Pal.PalCapturedCage:StartCaptureEffect_ServerBP", function(Context, PlayerParam)
            safe_call(function()
                local cage = Context and Context:get()
                if cage == nil then
                    Logger.log("[PalBonds/Capture] [CAGE-VFX] StartCaptureEffect_ServerBP fired but the cage Context could not be read")
                    return
                end
                Logger.log("[PalBonds/Capture] [CAGE-VFX] *** RESCUE MOMENT *** StartCaptureEffect_ServerBP fired on cage=" ..
                    tostring(safe_call(function() return cage:GetFullName() end)))

                local comp = safe_call(function() return cage.Niagara end)
                Logger.log("[PalBonds/Capture] [CAGE-VFX] rescue: Niagara component present=" .. tostring(comp ~= nil) ..
                    " name=" .. tostring(comp and safe_call(function() return comp:GetFullName() end)))

                if comp ~= nil then
                    local asset = safe_call(function() return comp.Asset end)
                    Logger.log("[PalBonds/Capture] [CAGE-VFX] rescue: Niagara ASSET present=" .. tostring(asset ~= nil) ..
                        " fullname=" .. tostring(asset and safe_call(function() return asset:GetFullName() end)) ..
                        " pathname=" .. tostring(asset and safe_call(function() return asset:GetPathName() end)))
                end

                -- Also enumerate every component on the cage: if the effect
                -- turns out NOT to be the field named "Niagara", this is what
                -- will say which component it actually is, without needing
                -- another trip.
                local comps = safe_call(function() return cage:K2_GetComponentsByClass(StaticFindObject("/Script/Niagara.NiagaraComponent")) end)
                if comps then
                    for i, c in ipairs(comps) do
                        local a = safe_call(function() return c.Asset end)
                        Logger.log(string.format(
                            "[PalBonds/Capture] [CAGE-VFX] rescue: NiagaraComponent[%d]=%s asset=%s",
                            i, tostring(safe_call(function() return c:GetFullName() end)),
                            tostring(a and (safe_call(function() return a:GetPathName() end) or safe_call(function() return a:GetFullName() end)))
                        ))
                    end
                end
            end)
        end)
    end)
    if ok then
        Logger.log("[PalBonds/Capture] [CAGE-VFX] rescue-moment hook installed on PalCapturedCage:StartCaptureEffect_ServerBP (read-only)")
    else
        Logger.log("[PalBonds/Capture] [CAGE-VFX] could NOT install the rescue-moment hook: " .. tostring(err))
    end
end

function Capture.Init()
    safe_call(function() probe_cage_vfx(1) end)
    safe_call(install_cage_effect_hook)
    Logger.log("[PalBonds/Capture] real trigger points wired (via Trust.lua) — sphere-less capture is now REAL (thirty-ninth pass), calls Capture.TryDirectCapture for real on OnTrustMaxed")
end

-- DESIGN.md §3.5. `pal` is the actor (UE4SS PalCharacter object), not a
-- string ID.
--
-- THIRTY-NINTH PASS (2026-09-02): wired for real. Dragón confirmed live
-- (F11 manual test, thirty-eighth pass) that Capture.TryDirectCapture
-- actually works — three different wild species (Sheepball, Cattiva, and
-- a Mammorest, a large boss-tier Pal) all joined his real party, no
-- sphere, no crash. This is DESIGN.md Question 4, answered for real.
-- OnTrustMaxed now calls it for real instead of just logging "would
-- capture here", and stops the bonding-follow state afterward since the
-- Pal is a genuine party member from this point on, not just our own
-- approximated follow state.

-- Hundred-and-thirty-seventh pass (2026-09-03): the single biggest open
-- question in this whole project — does a real-captured wild Pal actually
-- FOLLOW like a genuine Otomo afterward, or does it just sit in the party
-- roster (bench) until the player manually opens the party menu and
-- selects it? Nobody has ever explicitly checked this — every prior real
-- capture (thirty-ninth/hundred-and-eighteenth passes) was only confirmed
-- via "showed up in the party screen", never "kept following afterward
-- using the game's own systems". `Combat.StopFollowing` already turns off
-- OUR approximated follow the instant this fires, on the ASSUMPTION the
-- game takes over — this diagnostic finally checks whether that
-- assumption is true.
--
-- Entirely read-only, reusing the exact same proven-safe pattern already
-- used in Interaction.lua's `diagnose_party_membership` (hundred-and-
-- thirty-third-ish pass): `FindAllOf("PalPlayerPartyPalHolder")` (a
-- real, non-Arena class confirmed since the sixth continuación), plain
-- field reads (`FirstOtomoPal`/`SecondOtomoPal`/`BenchMember`), and the
-- bool-returning query `PawnOtmoIsPartyOtomo` — nothing here writes or
-- calls a state-mutating function.
-- Two-hundred-and-fourth pass (2026-09-06): this used to resolve `handle`
-- from `pal` (the actor) INSIDE this function, called AFTER
-- `Capture.TryDirectCapture` already ran — but every real test since this
-- diagnostic was written (hundred-and-thirty-seventh pass) hit "could not
-- resolve a live handle for the just-captured Pal", including all 3 real
-- captures in the session that just confirmed the composite-follow
-- negative result. Root cause, found by re-reading `Capture.TryDirectCapture`'s
-- own log right above this: it logs the Pal's owner-field struct going
-- from a real value to `nil` right across the `PalCaptureSuccess` call —
-- i.e. the capture process is actively tearing down/reassigning the very
-- actor state this function's handle lookup depends on, in the same
-- instant. Resolving `GetIndividualCharacterHandleByActor(pal)` at that
-- point was never going to work reliably — `pal` is mid-transition from
-- "wild actor" to "party data record," not a normal live actor anymore.
--
-- Real fix: resolve the handle BEFORE the capture call instead, while
-- `pal` is still an ordinary, fully-live wild actor (the exact same
-- moment `Personality.GetStableId` already reads a stable ID off wild
-- Pals successfully, throughout this whole project) — then thread that
-- already-resolved handle through to this function instead of re-deriving
-- it from a (by then reassigned) actor reference. Zero new native-call
-- risk: same function (`GetIndividualCharacterHandleByActor`), just called
-- at a point already proven safe elsewhere in this project.
local function diagnose_post_capture_slot(handle)
    local ok = pcall(function()
        if not handle or not handle:IsValid() then
            Logger.log("[PalBonds/Capture] [POST-CAPTURE-SLOT] no usable pre-capture handle was resolved — skipping check")
            return
        end

        local function describe(obj)
            if obj == nil then return "nil" end
            local dOk, name = pcall(function() return obj:GetFullName() end)
            if dOk and name then return name end
            return tostring(obj)
        end

        local holders = FindAllOf("PalPlayerPartyPalHolder") or {}
        Logger.log(string.format("[PalBonds/Capture] [POST-CAPTURE-SLOT] FindAllOf(PalPlayerPartyPalHolder) found %d live instance(s)", #holders))
        for i, holder in ipairs(holders) do
            local validOk, isValid = pcall(function() return holder ~= nil and holder:IsValid() end)
            if validOk and isValid then
                local first = safe_call(function() return holder.FirstOtomoPal end)
                local second = safe_call(function() return holder.SecondOtomoPal end)
                local benchCount = safe_call(function()
                    local bench = holder.BenchMember
                    return bench and bench:GetArrayNum()
                end)
                local isFirst = safe_call(function() return holder:PawnOtmoIsPartyOtomo(false, handle) end)
                local isSecond = safe_call(function() return holder:PawnOtmoIsPartyOtomo(true, handle) end)
                Logger.log(string.format(
                    "[PalBonds/Capture] [POST-CAPTURE-SLOT] holder[%d]: FirstOtomoPal=%s SecondOtomoPal=%s BenchMember count=%s | is-this-Pal-FirstOtomo=%s is-this-Pal-SecondOtomo=%s",
                    i, describe(first), describe(second), tostring(benchCount), tostring(isFirst), tostring(isSecond)
                ))
            end
        end
        Logger.log("[PalBonds/Capture] [POST-CAPTURE-SLOT] if both is-this-Pal flags read false/nil above, the Pal almost certainly landed on the BENCH, not an active slot — meaning it needs an explicit activation call to actually follow, same as this project already found happens when the player switches Otomo manually (Continuación 7: InactivateCurrentOtomo + ActivateOtomo)")
    end)
    if not ok then
        Logger.log("[PalBonds/Capture] [POST-CAPTURE-SLOT] diagnostic itself failed (safely contained, no risk to the real capture above)")
    end
end

-- Two-hundred-and-fifth pass (2026-09-06): Dragón's real ask, clarified —
-- not "let me preview a VFX out of curiosity," but a genuine completion
-- gap: a bonded Pal reaching 100% trust currently just vanishes in total
-- silence — no animation, no particle, nothing marks the moment it
-- actually joins, unlike a normal sphere capture. His own words: doesn't
-- need to be the "correct" vanilla effect, just needs to look complete.
--
-- Deliberately did NOT attempt to spawn the real capture/cage-release
-- beam VFX from scratch — there's no known content path for that actor
-- (unlike AIResponsePreset's documented CDO folder), so building one
-- would be this project's first from-scratch actor construction purely
-- for cosmetics, a new and bigger risk category for zero functional
-- gain. Reused the exact same safe, already-proven reaction this project
-- calls constantly elsewhere instead: `PlayActionByType(pal, Happy=38)`,
-- self-targeted on the Pal's own `ActionComponent` — the same call
-- Pet/Feed/Play already trigger, confirmed (hook-points.md "Hundred-and-
-- forty-third pass") to include the hearts VFX baked into the action
-- itself. No new native-call risk at all — just a new call SITE for a
-- call shape used dozens of times already in this project.
--
-- `continueFn` runs after a short fixed delay (JOIN_CELEBRATION_DELAY_MS)
-- so the Happy reaction + hearts actually have time to read on screen
-- before the Pal disappears and rejoins as a party member — same honest
-- "fixed delay, not a detected signal" pattern already accepted
-- project-wide (Trust.lua's own `CAPTURE_DELAY_FIXED_MS`, for the exact
-- same reason: no proven way yet to read back a montage's real duration).
-- This STACKS on top of that existing 5s wait (which covers the PRIOR
-- interaction's own animation, not this one) — total time from crossing
-- the capture threshold to actually joining is now ~5s + 2s, worth
-- retuning live if it feels too long.
local JOIN_CELEBRATION_DELAY_MS = 2000

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

    -- Two-hundred-and-thirteenth pass: play the dissolve-into-light VFX at the
    -- END of the happy reaction rather than at its start, so the order reads
    -- happy -> light -> vanish. The capture itself follows immediately after
    -- this callback, which is exactly the "nothing in between" gap Dragón has
    -- been pointing at.
    local scheduled = pcall(function()
        ExecuteInGameThreadWithDelay(JOIN_CELEBRATION_DELAY_MS, function()
            spawn_niagara_at(pal, JOIN_VFX_ASSET_PATH)
            continueFn()
        end)
    end)
    if not scheduled then
        Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] could not schedule the celebration delay — capturing immediately instead")
        continueFn()
    end
end

-- Friendship a Pal gains for joining by choice. Dragón's correction: a flat
-- GRANT of 50000 points, not a raise TO a particular rank.
--
-- The difference is real, not cosmetic. Targeting rank 5 meant "end up at 40000
-- however you got here", so a Pal that already had friendship gained less than
-- one that had none, and a Pal already above 40000 gained nothing at all. A flat
-- grant means every Pal that chooses to join is rewarded the same amount on top
-- of whatever it already had, which is the fairer reading of what the bonus is
-- for.
--
-- For scale, against the real DT_FriendshipRankTable decoded earlier
-- (1->6000, 2->13000, 3->21000, 4->30000, 5->40000, 6->55000): a Pal starting
-- from zero lands at rank 5, just short of 6.
local JOIN_FRIENDSHIP_POINT_GRANT = 50000

function Capture.OnTrustMaxed(pal)
    local name = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format("[PalBonds/Capture] %s reached full trust — capturing for real (sphere-less)", tostring(name)))

    local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
    if not player or not (safe_call(function() return player:IsValid() end)) then
        Logger.log("[PalBonds/Capture] no valid local player found — cannot capture, leaving Pal as a bonding-follower for now")
        return
    end

    -- Two-hundred-and-fourth pass (2026-09-06): resolved HERE, BEFORE the
    -- capture call below, while `pal` is still an ordinary live wild actor
    -- — see diagnose_post_capture_slot's own header comment for why every
    -- past attempt to resolve this AFTER capture failed instead.
    local preCaptureHandle = safe_call(function()
        local utility = get_pal_utility()
        return utility and utility:GetIndividualCharacterHandleByActor(pal)
    end)

    -- Two-hundred-and-tenth pass: resolved HERE, before the capture, for the
    -- same reason preCaptureHandle above is — after PalCaptureSuccess runs,
    -- the Pal actor is mid-teardown and every read off it fails. Dragón's
    -- last run proved this: the toast fell through to its generic fallback
    -- because both name routes failed post-capture.
    local preResolvedDisplayName = resolve_pal_display_name(pal, player)

    -- Two-hundred-and-fortieth pass (2026-09-07): a Pal that JOINS by choice
    -- should not arrive as a stranger, so joining carries a flat friendship
    -- grant on top of whatever the Pal already had.
    --
    -- The mod's own bonding bar tops out around 500 while vanilla's owned-Pal
    -- friendship runs to 200000 — two entirely separate scales. This call is the
    -- single point where the mod hands over from one to the other.
    --
    -- Done BEFORE the capture, on purpose and for the same reason the handle and
    -- the display name above are: once PalCaptureSuccess runs the actor is
    -- mid-teardown and every read or write off it fails. That mistake has
    -- already cost this project two bugs.
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

        Capture.TryDirectCapture(pal, player)

        -- Hundred-and-thirtieth pass: real on-screen confirmation. Fired
        -- unconditionally right after the call above — TryDirectCapture
        -- doesn't currently report success/failure back to its caller, and
        -- PalCaptureSuccess has been 100% reliable across every real capture
        -- tested so far (see this file's own thirty-ninth pass note), so this
        -- matches the project's existing confidence level rather than adding
        -- new uncertainty.
        Capture.NotifyJoined(pal, player, preResolvedDisplayName)

        -- It's a real party member now (assuming the call above worked) —
        -- stop treating it as our own approximated bonding-follow state.
        Combat.StopFollowing(pal)
        -- ...and drop Trust's own record too. Combat.StopFollowing only clears
        -- the follow bookkeeping; Trust kept its bonding state, and its tick
        -- then measured the distance to a Pal that no longer exists in the world
        -- and declared it abandoned. See Trust.ForgetBonding.
        safe_call(function()
            local okT, TrustMod = pcall(require, "Trust")
            if okT and TrustMod and TrustMod.ForgetBonding then TrustMod.ForgetBonding(pal) end
        end)

        -- Hundred-and-thirty-seventh pass: read-only check of where the Pal
        -- actually landed — see diagnose_post_capture_slot's own comment for
        -- why it now takes the pre-resolved handle instead of the actor.
        diagnose_post_capture_slot(preCaptureHandle)
    end)
end

-- DESIGN.md §3.6. `pal` is the actor.
-- Two-hundred-and-forty-third pass (2026-09-07) — Dragón's idea: tell the
-- player when a bond breaks, and why. Until now losing a Pal was completely
-- silent: it simply stopped following and could never be bonded again, with
-- nothing on screen to say it had happened or what caused it. That is the worst
-- kind of consequence — a real, permanent one the player cannot learn from.
--
-- Two causes, two messages, because they teach different lessons:
--   betrayed  — the player hurt it. "You hurt X. It will not trust you again."
--   abandoned — it was left too far behind. "X waited, but you went too far."
--
-- Reuses NotifyJoined's proven toast route exactly (GetLogManager -> AddLog with
-- the resolved widget class), with one difference: LogToneType 2 is the positive
-- tone used for joining, so these use tone 1. Sent BEFORE anything else in this
-- function, while the actor is certainly still readable — the same discipline
-- that the capture path needed after resolving names too late twice.
local function notify_bond_lost(pal, reason)
    pcall(function()
        local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
        if player == nil or not safe_call(function() return player:IsValid() end) then return end
        local utility = get_pal_utility()
        if utility == nil then return end
        local manager = safe_call(function() return utility:GetLogManager(player) end)
        if manager == nil then return end
        local widgetClass = resolve_toast_widget_class(manager)
        if widgetClass == nil then return end
        local textLibrary = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
        if textLibrary == nil then return end

        local palName = resolve_pal_display_name(pal, player)
        local who = palName or "A Pal"
        local message
        if reason == "betrayed" then
            message = who .. " no longer trusts you. It will not bond with you again."
        else
            message = who .. " was left behind and gave up on you."
        end

        local text = safe_call(function() return textLibrary:Conv_StringToText(message) end)
        if text == nil then return end
        manager:AddLog(1, text, { OverrideWidgetClass = widgetClass, LogToneType = 1 })
        Logger.log("[PalBonds/Capture] [NOTIFY] bond-lost message: " .. message)
    end)
end

-- A hit that hurt the bond without ending it. Without this the gradual penalty
-- would be invisible: a player clipping their own follower mid-fight would watch
-- a bond they spent minutes building quietly shrink, with nothing on screen
-- connecting the two. Deliberately worded as a warning rather than a loss.
function Capture.NotifyTrustShaken(pal)
    pcall(function()
        local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
        if player == nil or not safe_call(function() return player:IsValid() end) then return end
        local utility = get_pal_utility()
        if utility == nil then return end
        local manager = safe_call(function() return utility:GetLogManager(player) end)
        if manager == nil then return end
        local widgetClass = resolve_toast_widget_class(manager)
        if widgetClass == nil then return end
        local textLibrary = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary") end)
        if textLibrary == nil then return end

        local palName = resolve_pal_display_name(pal, player)
        local message = (palName or "A Pal") .. " flinched away from you. Its trust is shaken."
        local text = safe_call(function() return textLibrary:Conv_StringToText(message) end)
        if text == nil then return end
        manager:AddLog(1, text, { OverrideWidgetClass = widgetClass, LogToneType = 1 })
        Logger.log("[PalBonds/Capture] [NOTIFY] trust-shaken message: " .. message)
    end)
end

function Capture.OnTrustLost(pal, reason)
    notify_bond_lost(pal, reason)
    -- Two-hundred-and-fifty-seventh pass: Dragon asked the right question --
    -- "why before betrayed pals ran away no problem but now they still follow?
    -- what broke?" -- and the answer is that I broke it two passes ago.
    --
    -- Forcing the tier to 'escape' swaps the Pal's AI response preset, but a
    -- preset only takes effect when the Pal next SENSES the player. Nothing was
    -- prompting that, so the swap sat there unused. It worked before because
    -- back then there was no follow action holding the Pal in place -- the Pal
    -- was free to wander, re-noticed the player on its own, and fled. Now our
    -- action occupies its decision slot, so that never happens by itself.
    --
    -- RefreshSightOn is this project's existing, proven way to make a Pal re-run
    -- its sight check immediately (5/5 successful in the pass-165 measurements).
    -- Called AFTER the tier is forced below, so the check runs against the new
    -- preset rather than the old one.
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
    -- Two-hundred-and-forty-eighth pass (2026-09-07): the reason is now KEPT,
    -- not just used for the toast and thrown away. Dragón wants the two
    -- outcomes labelled differently on the nameplate — "scarred for betrayed
    -- pals so players actually feel bad for what they did", and something
    -- separate for a Pal that was simply left behind. Storing the reason here
    -- is all that was needed; PermanentlyFled was already keyed by actor name,
    -- it was just holding `true` instead of anything informative.
    Logger.log(string.format("[PalBonds/Capture] %s lost all trust (%s) — fleeing permanently", tostring(name), tostring(reason)))

    if name then
        PermanentlyFled[name] = reason or true
    end

    -- Hundred-and-fifty-sixth pass (2026-09-04) FIX: this used to just be
    -- an internal flag with an honest TODO admitting real flee behavior
    -- was never attempted. Not true anymore — the personality-tier work
    -- from earlier this session proved a real, working mechanism for
    -- exactly this: forcing a Pal's tracked tier to "escape" and letting
    -- the already-confirmed-live enforcement path (private AIResponse-
    -- Preset swap) make it genuinely flee, no new native call needed.
    -- Two-hundred-and-sixty-second pass (2026-09-07) — Dragon's idea, and it is
    -- both the better design and the actual technical fix:
    --   "what if instead of making them follow or not, once its scarred turn
    --    hostile on the player? that way the player is forced to run from the pal
    --    or kill it"
    --
    -- Five separate attempts to remove the follow action have now failed --
    -- TerminateCurrentActionByClass, AllCancelPushedAction, swapping the slot
    -- with PawnAction_Wait, cancelling the running action, and pointing Trainer
    -- at the Pal itself. The last one is the telling one: the POST-BOND-DUMP
    -- shows the write HELD (Trainer really is the Pal) and the action carried on
    -- regardless, FollowState 3, still computing destinations.
    --
    -- Turning the Pal hostile sidesteps all of it, because COMBAT IS THE ONE
    -- THING THAT HAS BEEN EVICTING THIS ACTION SUCCESSFULLY ALL ALONG. This
    -- project discovered that weeks ago -- a fight destroys the follow action --
    -- and built the whole rebuild-after-combat system around it without ever
    -- drawing the obvious conclusion. So instead of asking the engine for a
    -- removal API that does not seem to exist, we let the game do the eviction
    -- itself, through the exact path already proven to work.
    --
    -- The two ways a bond ends now diverge, which they should:
    --   betrayed  -> warlike_anyway. You hurt it; it comes after you. The Pal
    --                is telling the player something, and it is unmissable.
    --   abandoned -> escape. You neglected it; it leaves. No grudge, just gone.
    --
    -- "warlike_anyway" is not a guess: it is one of the seven rolled tiers, and
    -- Dragon confirmed in play that Pals on it genuinely do attack him.
    -- Two-hundred-and-sixty-third pass: a BETRAYED Pal is frozen where it stands.
    -- The preset swap below is kept because it costs nothing and is correct in
    -- principle, but this session proved it changes no behaviour on its own --
    -- the Pal's AI will not re-derive its attitude to the player. The freeze is
    -- what the player actually sees, and Dragon's reasoning for it is right:
    -- better a Pal that stands motionless than one that keeps walking after the
    -- person who just beat it.
    --
    -- Abandonment deliberately does NOT freeze. A Pal you merely left behind has
    -- no reason to be paralysed; it just stops being yours.
    -- Two-hundred-and-sixty-fourth pass (2026-09-07) — REVERTED. SetActiveAI(false)
    -- did exactly what it says and that turned out to be far too much: Dragon's
    -- report is that the Pal "gets stuck so hard that it doesnt even realize its
    -- dead, it just stands there idle, not reacting to anything at all, not even
    -- after losing all its hp". A corpse that never dies is much worse than a Pal
    -- that walks after you, so this is off.
    --
    -- Instead of guessing at a seventh mechanism, the block below asks what is
    -- ACTUALLY running on this Pal after the bond breaks. Every real breakthrough
    -- in this project came from that question and none came from guessing.
    safe_call(function()
        local okC, CombatMod = pcall(require, "Combat")
        if okC and CombatMod and CombatMod.DiagnoseAfterBondLoss then
            CombatMod.DiagnoseAfterBondLoss(pal, reason)
        end
    end)

    local palId = safe_call(function() return Personality.GetOrInitState(pal) end)
    if palId then
        local tier = (reason == "abandoned") and "escape" or "warlike_anyway"
        Logger.log("[PalBonds/Capture] bond ended (" .. tostring(reason) ..
            ") — forcing tier '" .. tier .. "'" ..
            (tier == "warlike_anyway" and " so it turns on the player; the resulting combat is also what finally evicts our follow action" or ""))
        Personality.ForceTier(palId, pal, tier)
        -- The swap above only changes what the Pal WOULD decide; this makes it
        -- decide again, now, against the new preset. Without it the escape sits
        -- unused because our follow action occupies the Pal's decision slot and
        -- it never re-notices the player on its own.
        resense_after_flee()
    else
        Logger.log("[PalBonds/Capture] could not resolve a personality state for this Pal — real flee behavior skipped, permanent-flag/interaction-block above still applies")
    end
end

-- `pal` is the actor.
-- Why this Pal's bond ended: "betrayed", "abandoned", or nil if it has not
-- lost its bond at all. Returns nil rather than a default for an unknown
-- reason, so a caller can tell "no bond lost" from "bond lost, cause unrecorded"
-- instead of quietly mislabelling one as the other.
function Capture.GetFledReason(pal)
    local name = safe_call(function() return pal:GetFullName() end)
    if name == nil then return nil end
    local v = PermanentlyFled[name]
    if type(v) == "string" then return v end
    return nil
end

-- Two-hundred-and-fiftieth pass (2026-09-07) — this one line caused BOTH bugs
-- Dragon reported: a betrayed Pal could be petted straight back into bonding,
-- and its nameplate kept its old personality instead of showing Scarred. It is a
-- regression I introduced two passes ago and did not check.
--
-- Pass 248 changed what gets STORED here from the boolean `true` to the reason
-- string ("betrayed" / "abandoned") so the label could tell them apart. This
-- test was never updated with it, and  "betrayed" == true  is false. Every
-- caller asking "has this Pal permanently fled?" was told no, for every Pal that
-- had. The guard I had just added to the radial-menu grant was working perfectly
-- and being handed the wrong answer.
--
-- Tests for PRESENCE now, so it cannot break again the next time the stored
-- shape changes.
-- Two-hundred-and-seventy-fifth pass: keyed by actor name, so every entry
-- refers to an actor that no longer exists once the world changes.
function Capture.ResetForNewWorld()
    local n = 0
    for _ in pairs(PermanentlyFled) do n = n + 1 end
    PermanentlyFled = {}
    Logger.log("[PalBonds/Capture] [WORLD-RESET] dropped " .. n .. " permanently-fled record(s) from the old world")
end

function Capture.HasPermanentlyFled(pal)
    local name = safe_call(function() return pal:GetFullName() end)
    return name ~= nil and PermanentlyFled[name] ~= nil
end

return Capture
