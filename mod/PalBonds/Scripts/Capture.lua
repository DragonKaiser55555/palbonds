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
            local localized = safe_call(function()
                return masterData:GetLocalizedText(player, PAL_LOCALIZE_CATEGORY_MONSTER_NAME, charId)
            end)
            local asFString = localized and safe_call(function() return textLibrary:Conv_TextToString(localized) end)
            local asString = to_lua_string(asFString)
            if asString ~= nil and asString ~= "" then
                palName = asString
                return
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
        local palName = preResolvedName
        local message
        if palName then
            message = palName .. " likes you and decided to join your party!"
        else
            message = "A wild Pal has joined your party!"
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
function Capture.IsAlreadyOwned(pal)
    local ok, result = pcall(function()
        if pal == nil or not pal:IsValid() then return true end
        local comp = pal.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return true end
        local param = comp:GetIndividualParameter()
        if param == nil or not param:IsValid() then return true end
        local ownerId = param.SaveParameter and param.SaveParameter.OwnerPlayerUId
        if ownerId == nil then return true end
        local isZeroGuid = (ownerId.A == 0) and (ownerId.B == 0) and (ownerId.C == 0) and (ownerId.D == 0)
        return not isZeroGuid
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

function Capture.Init()
    safe_call(function() probe_cage_vfx(1) end)
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

    local scheduled = pcall(function()
        ExecuteInGameThreadWithDelay(JOIN_CELEBRATION_DELAY_MS, function()
            continueFn()
        end)
    end)
    if not scheduled then
        Logger.log("[PalBonds/Capture] [JOIN-CELEBRATION] could not schedule the celebration delay — capturing immediately instead")
        continueFn()
    end
end

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

        -- Hundred-and-thirty-seventh pass: read-only check of where the Pal
        -- actually landed — see diagnose_post_capture_slot's own comment for
        -- why it now takes the pre-resolved handle instead of the actor.
        diagnose_post_capture_slot(preCaptureHandle)
    end)
end

-- DESIGN.md §3.6. `pal` is the actor.
function Capture.OnTrustLost(pal)
    local name = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format("[PalBonds/Capture] %s lost all trust — fleeing permanently", tostring(name)))

    if name then
        PermanentlyFled[name] = true
    end

    -- Hundred-and-fifty-sixth pass (2026-09-04) FIX: this used to just be
    -- an internal flag with an honest TODO admitting real flee behavior
    -- was never attempted. Not true anymore — the personality-tier work
    -- from earlier this session proved a real, working mechanism for
    -- exactly this: forcing a Pal's tracked tier to "escape" and letting
    -- the already-confirmed-live enforcement path (private AIResponse-
    -- Preset swap) make it genuinely flee, no new native call needed.
    local palId = safe_call(function() return Personality.GetOrInitState(pal) end)
    if palId then
        Personality.ForceTier(palId, pal, "escape")
    else
        Logger.log("[PalBonds/Capture] could not resolve a personality state for this Pal — real flee behavior skipped, permanent-flag/interaction-block above still applies")
    end
end

-- `pal` is the actor.
function Capture.HasPermanentlyFled(pal)
    local name = safe_call(function() return pal:GetFullName() end)
    return name ~= nil and PermanentlyFled[name] == true
end

return Capture
