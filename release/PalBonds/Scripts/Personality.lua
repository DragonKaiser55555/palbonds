local Logger = require("Logger")
local Personality = {}

-- Per-instance state, keyed by the real stable ID (see GetStableId).
-- Shape: PersonalityState[palId] = { disposition = "friendly", speciesDefault = "friendly", presetClassName = "BP_AIResponsePreset_friendly_C" }
local PersonalityState = {}

-- Hundred-and-fifty-third pass (2026-09-04): renamed from the old
-- curious/skittish/hostile vocabulary to the REAL AIResponsePreset base
-- names, at Dragón's explicit request — he originally used curious/
-- hostile/skittish only because he didn't know the real in-code names,
-- and asked to switch once he did, specifically so the exact bug found
-- this same session (a species defaulting to plain "escape" silently
-- misread as "curious" because only "Escape_to_Battle" was recognized)
-- can't happen again the same way, and so the debug label can show which
-- of the three "warlike" variants a Pal actually has (they behave very
-- differently — see hook-points.md). "normal" is not a real preset name,
-- it's this project's own sentinel for "don't touch it, use the species'
-- real default."
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

-- Ninety-second pass (2026-09-03) — Dragón's spec, a second, independent
-- frontier from the radial-menu work: every wild Pal, regardless of
-- species, gets ONE randomly-rolled "personality tier" the first time we
-- see it, weighted:
--   The exact weights live in PERSONALITY_TIERS below and nowhere else --
--   they have been changed several times (curious/hostile/skittish were
--   replaced by the real preset names, and warlike_without_player became
--   kill_all), and every copy of the numbers written into prose has gone
--   stale. Read the table; do not trust a percentage in a comment.
-- This is the ASSIGNMENT half only. Rolled once per stable individual ID,
-- persisted in PersonalityState so it doesn't re-roll on every
-- interaction. IMPORTANT, same honesty this file has kept from the start:
-- this pass only decides and STORES the tier — it does not yet make the
-- game's actual AI behave differently (a hostile-tier Lamball won't
-- really attack yet, a skittish-tier boss won't really flee yet). That's
-- a separate, harder enforcement step (see the note at the bottom of this
-- file, now updated) — needs either overriding a live Pal's
-- AIResponsePreset pointer or a properly-throttled SelectResponseBySenses
-- override, neither attempted yet.
-- Hundred-and-fifty-third pass (2026-09-04): Dragón's new split, adding
-- the three previously-unused real presets (notinterested, warlike_anyway,
-- warlike_without_player) he wants to compare live against plain
-- "warlike" (which he confirmed did NOT attack him in the last two real
-- tests — see hook-points.md's hypothesis on why). Sums to 100.
-- Hundred-and-sixty-second pass (2026-09-04): Dragón's rebalance —
-- friendly 20->30, warlike_anyway and warlike_without_player both
-- 10->5 each (still sums to 100).
local PERSONALITY_TIERS = {
    { tier = "normal", weight = 35 },
    { tier = "friendly", weight = 30 },
    { tier = "escape", weight = 10 },
    { tier = "notinterested", weight = 10 },
    { tier = "warlike", weight = 5 },
    { tier = "warlike_anyway", weight = 5 },

    -- Two-hundred-and-sixteenth pass (2026-09-06): "warlike_without_player"
    -- swapped out for "kill_all" at Dragón's request. His report: that tier
    -- "seems to not be reacting at all as it should", and what he actually
    -- wanted from it was a Pal that attacks anyone on sight — behaviour he has
    -- seen in vanilla but could not name. BP_AIResponsePreset_Kill_All_C is
    -- that preset, confirmed real (it is one of the 11 found via repak against
    -- the vanilla pak, and already referenced in EXCLUDED_FROM_ROLLING below).
    --
    -- Note the two mechanisms do NOT conflict, same as with NotInterested:
    -- EXCLUDED_FROM_ROLLING keeps Pals whose SPECIES preset is already
    -- Kill_All out of the roll, while this entry makes "kill_all" an outcome
    -- the roll can assign to any other Pal.
    --
    -- warlike_without_player stays defined in the tables below so ForceTier
    -- can still reach it and so existing saved/labelled state stays readable —
    -- it just is not rolled any more.
    { tier = "kill_all", weight = 5 },
}

-- Hundred-and-twenty-eighth pass (2026-09-03): Dragón hit a real, fair
-- problem testing Skittish→Curious — with the roll active, a Pal that
-- LOOKS skittish (fleeing) usually isn't tracked as skittish at all (real
-- session data: 5/5 fleeing Pals he petted rolled curious/hostile), since
-- real behavior is driven by the UNMODIFIED species AI, not our tracked
-- tier (enforcement remains unconfirmed). Checking each one with CTRL+P
-- turned out impractical too — the console scrolls faster than he can
-- read it. His own framing: either make Pals really behave like their
-- rolled tier, or turn the roll off for now so a Pal that's naturally
-- skittish (real species default, already reflected in real vanilla
-- behavior — no enforcement needed for THIS to be true) is the one that's
-- actually tracked as skittish, letting Won-Over be tested against ground
-- truth instead of a hidden, invisible roll.
--
-- This flag does exactly that: false means every individual's rolled tier
-- is forced to "normal," so the tracked/effective disposition always
-- equals the real species default — genuinely skittish species (whatever
-- the real AIResponsePreset says) are visibly, trackedly skittish, with
-- zero dependency on enforcement. The weighted-roll system itself is left
-- fully intact below, purely toggled off — flip this back to true once
-- Skittish→Curious (and, ideally, enforcement) are confirmed working, to
-- resume the original "every Pal gets its own rolled personality" design.
--
-- Hundred-and-twenty-ninth pass (2026-09-03) RE-ENABLED: enforcement was
-- just rewritten to no longer need a live donor Pal at all (see
-- find_preset_cdo/apply_forced_preset below — technique confirmed via a
-- real, shipped reference mod, "Passive Pals"). With the roll left off,
-- every individual's rolledTier is "normal" and try_enforce_personality's
-- very first check exits immediately — the new mechanism would never
-- actually run. Turned back on so this fix gets a real test.
local ENABLE_PERSONALITY_TIER_ROLL = true

-- Hundred-and-forty-sixth pass (2026-09-04): Dragón's ask — the original
-- "Passive Pals"-inspired design (a weighted RANDOM personality roll per
-- individual, so some Pals stay skittish/hostile and some don't) never
-- got confirmed working end-to-end the way it was meant to. For now, he
-- wants every wild Pal simply calm/approachable — his own word is
-- "curious" (this project's own DISPOSITIONS bucket for "watches the
-- player instead of fleeing or attacking," matching what he described)
-- — so he doesn't have to chase fleeing Pals down just to interact with
-- them. Forces EVERY newly-seen individual's rolled tier to "curious"
-- unconditionally, skipping the weighted table below entirely. The
-- ENFORCEMENT mechanism further down (confirmed working on 1170/1173
-- real attempts) then does the actual work of swapping each individual's
-- real AIResponsePreset to match, exactly as it already does for any
-- other rolled tier — nothing new needed there.
--
-- Kept as a separate toggle rather than deleting PERSONALITY_TIERS/
-- roll_personality_tier's weighted logic — same "toggle, don't delete"
-- convention this file already uses for ENABLE_PERSONALITY_TIER_ROLL
-- itself — so the original per-individual-variety design is one flag
-- away from resuming later if Dragón wants that back.
-- Hundred-and-forty-ninth pass (2026-09-04): flipped off for a real test
-- of the per-individual randomizer, now that the reactive sensor hook
-- (hundred-and-forty-eighth pass) confirmed the enforcement path actually
-- works end-to-end (real [ENFORCE] SUCCESS lines). Dragón's own bar,
-- correctly held: "if it's not visible in behavior, it's not confirmed
-- working" — this is that real test. The weighted table below
-- (PERSONALITY_TIERS, still 50/25/10/15) is UNCHANGED — comparing
-- same-species Pals for different rolled behavior with the existing
-- weights is the actual ask, not a new split yet.
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

-- Maps a real UPalAIResponsePreset Blueprint class name to one of our own
-- DISPOSITIONS buckets. Only 3 real presets confirmed live so far
-- (thirty-third pass) — there are certainly more (this is a small game
-- with dozens of species/archetypes). Unrecognized presets fall back to
-- "curious" and get logged ONCE so we can extend this table over time
-- without needing another risky broad hook.
-- Hundred-and-fifty-third pass (2026-09-04) BUG FIX: plain
-- "BP_AIResponsePreset_escape_C" was NEVER in this table — only
-- "Escape_to_Battle_C" was. Any species whose real default is plain
-- "escape" fell through to the unrecognized-preset fallback and got
-- silently mislabeled "curious" (now "friendly") even though its real,
-- untouched behavior is to flee — this is very likely the exact
-- explanation for Dragón's "some curious Pals run away" observation
-- (a normal-tier roll on one of these species never gets enforced,
-- since normal means "leave it alone," but the TRACKED label was wrong).
-- Fixed by adding the missing entry, and renamed every value to the real
-- preset base names throughout, per Dragón's explicit request.
local PRESET_NAME_TO_DISPOSITION = {
    ["BP_AIResponsePreset_friendly_C"] = "friendly",
    ["BP_AIResponsePreset_escape_C"] = "escape",
    ["BP_AIResponsePreset_Escape_to_Battle_C"] = "escape",
    ["BP_AIResponsePreset_NotInterested_C"] = "notinterested",
    ["BP_AIResponsePreset_Warlike_C"] = "warlike",
    ["BP_AIResponsePreset_Warlike_Anyway_C"] = "warlike_anyway",
    ["BP_AIResponsePreset_Warlike_WithoutPlayer_C"] = "warlike_without_player",

    -- VillageNPC/Kill_All/Boss are deliberately NOT mapped to a real
    -- tracked disposition here — GetOrInitState below excludes them from
    -- rolling/enforcement entirely (Dragón: "npc, bosses and other
    -- things, those should stay normal always"). Left as "friendly" here
    -- only as a harmless label if ever displayed, never acted on.
    ["BP_AIResponsePreset_Kill_All_C"] = "kill_all", 
    ["BP_AIResponsePreset_VillageNPC_C"] = "friendly",
}

-- Hundred-and-fifty-third pass (2026-09-04): Dragón — "npc, bosses and
-- other things, those should stay normal always." Before this, the
-- weighted roll ran unconditionally on every actor GetOrInitState saw
-- (including human NPCs and bosses, which do get swept up by the periodic
-- scan's FindAllOf("PalCharacter")/enforcement path) — meaning an NPC or
-- boss could in principle get randomly rolled "warlike_anyway" and have
-- its real AI swapped, which was never the intent. Checked by the
-- individual's REAL current preset class name (already resolved for
-- every Pal anyway) rather than guessing at actor type — any Pal whose
-- real preset is one of these three is forced to rolledTier="normal"
-- unconditionally, skipping the random roll entirely, so it's never
-- enforcement-swapped no matter what.
-- Hundred-and-sixty-second pass (2026-09-04): Dragón's ask — Pals whose
-- REAL current preset is already NotInterested should be left alone
-- entirely (same exclusion category as VillageNPC/Kill_All/Boss),
-- since several human NPCs use this real preset and were getting swept
-- into the random roll like any other Pal. This did NOT remove
-- "notinterested" from the weighted table above — a Pal whose real
-- default is something else (friendly/escape/warlike/etc.) could still
-- randomly roll "notinterested" as its assigned tier; this only stopped
-- an already-genuinely-notinterested Pal from being re-rolled into
-- something else.
-- Hundred-and-seventy-eighth pass (2026-09-05): REMOVED. This entry only
-- ever existed as an indirect proxy for catching human NPCs by their
-- preset — a real, direct check now exists instead
-- (is_confirmed_pal_monster, gated in GetOrInitState BEFORE this table
-- is even consulted), which catches every human NPC regardless of what
-- preset they resolve to. Dragón confirmed this directly: "that means
-- we can include notinterested pals once more... now that you've found
-- that separation, then we can use that instead." Any actual MONSTER
-- (passes IsPalMonster) whose species default happens to be
-- NotInterested is no longer force-excluded from the roll — it can now
-- roll a real personality tier like any other monster. VillageNPC/
-- Kill_All/Boss are left in place: Boss in particular is a real
-- monster-preset category (Alpha Pals) Dragón explicitly wants excluded
-- regardless of the human/monster question, and removing the other two
-- wasn't asked for.
local EXCLUDED_FROM_ROLLING = {
    ["BP_AIResponsePreset_VillageNPC_C"] = true,
    ["BP_AIResponsePreset_Kill_All_C"] = true,
    ["BP_AIResponsePreset_Boss_C"] = true,
}

-- Ninety-third pass — ENFORCEMENT: which real, existing preset class
-- corresponds to each forced tier. Confirmed via repak/strings against the
-- vanilla game's own Pal-Windows.pak that these are 3 of only 11 total
-- AIResponsePreset variants that exist anywhere in the game (the others:
-- Default, NotInterested, Warlike_Anyway, Warlike_WithoutPlayer, Kill_All,
-- Boss — not used here, either redundant with these three or carrying
-- scope beyond "attack/flee/watch the player" specifically). "normal" is
-- deliberately absent — it means "leave the species' own preset alone,"
-- never a swap. Base names (no "_C" suffix) — the "_C" is appended where
-- needed, matching the real asset path shape used below.
--
-- Hundred-and-twenty-ninth pass (2026-09-03): these used to be full class
-- names (with "_C") because the OLD mechanism needed to match a live
-- donor Pal's class name string. See find_preset_cdo below for why a
-- donor Pal is no longer needed at all.
local TIER_TO_DONOR_PRESET_CLASS = {
    friendly = "BP_AIResponsePreset_friendly",
    escape = "BP_AIResponsePreset_escape",
    notinterested = "BP_AIResponsePreset_NotInterested",
    warlike = "BP_AIResponsePreset_Warlike",
    warlike_anyway = "BP_AIResponsePreset_Warlike_Anyway",
    warlike_without_player = "BP_AIResponsePreset_Warlike_WithoutPlayer",
    kill_all = "BP_AIResponsePreset_Kill_All",
}

-- Hundred-and-twenty-ninth pass (2026-09-03) — REAL FIX, found by reading a
-- second reference mod Dragón provided ("Passive Pals"), which is a real
-- UE4SS Lua mod (not a compiled Blueprint like every other reference mod
-- so far) doing almost exactly what this project's enforcement half needs,
-- and doing it more reliably. Two things it does differently, both proven
-- (it's a real, shipped mod):
--
-- 1. It never needs a live "donor" Pal at all. Every `AIResponsePreset` is
--    a normal Blueprint DATA ASSET with its own Class Default Object
--    (CDO) — and a CDO is resolvable via `StaticFindObject` the moment its
--    class is loaded, with ZERO dependency on any Pal actor existing
--    anywhere nearby (this project's entire "no live donor found nearby
--    yet, will keep retrying" blocker was solved by realizing this: we
--    were seeting a live Pal instance as a proxy for the object we
--    actually wanted, when the object itself was reachable directly the
--    whole time). Real path pattern, confirmed via the reference mod's own
--    `config.lua`: `/Game/Pal/Blueprint/Controller/AIResponsePreset/
--    <name>.Default__<name>_C` (its fallback path, only needed if the
--    first one somehow fails, reads the class then calls `:GetCDO()`).
-- 2. It builds a FRESH, PRIVATE preset instance via `StaticConstructObject`
--    (owned by the sensor component, never shared with any other Pal) and
--    copies the source preset's 8 real fields into it, rather than ever
--    pointing two different Pals at the exact same shared object. This
--    project's own prior attempts already avoided ever WRITING to a
--    shared object — this goes one step further and avoids even having
--    two Pals ever POINT AT the same object at all, which is strictly
--    safer.
local PRESET_ASSET_DIR = "/Game/Pal/Blueprint/Controller/AIResponsePreset/"
local NATIVE_PRESET_CLASS_PATH = "/Script/Pal.PalAIResponsePreset"

-- The 8 real fields on UPalAIResponsePreset (DESIGN.md/hook-points.md
-- Question 1, confirmed since the thirty-second pass) — same names
-- confirmed again independently in the Passive Pals reference mod's own
-- config.lua (config.discoverProps/config.damagedProps).
local PRESET_SLOTS = {
    "Discover_Player", "Discover_Greater", "Discover_Equal", "Discover_Smaller",
    "Damaged_Player", "Damaged_Greater", "Damaged_Equal", "Damaged_Smaller",
}

-- How often the enforcement scan re-checks nearby wild Pals. 8s, matching
-- OtomoWatch.lua's PrismSpy poll interval — deliberately NOT a per-tick or
-- sub-second hook (see this project's thirty-third and ninth pass lag
-- lessons); this scan walks every currently-loaded PalCharacter, which is
-- more actors than the follow-tick's small bonding-only set, so it runs
-- less often to compensate.
local PERSONALITY_SCAN_INTERVAL_MS = 8000

-- Presets we've seen but didn't recognize, logged once each so Dragón (or
-- a future pass) can extend PRESET_NAME_TO_DISPOSITION above.
local loggedUnknownPresets = {}

-- NINETY-FOURTH PASS (2026-09-03): GetPresetClassName's [DIAG] logging
-- below was written in the thirty-fifth/thirty-sixth passes when it was
-- only ever called from a rare pet/feed event — logging every single call
-- was fine then. It's now also called from GetOrInitState's retry path
-- (see below) every time the periodic personality-enforcement scan sees a
-- Pal whose preset still hasn't resolved, every 8s, for as long as that
-- stays true. Dragón's first live test of that scan produced 2813
-- identical copies of one of these lines in ~3 minutes and visible lag.
-- Throttled to once per (actor, failure-reason) pair — a persistently
-- unreadable Pal still gets retried silently forever, just not re-logged.
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

-- Cache the UClass lookups (StaticFindObject) once — these are cheap,
-- static, unchanging references, no need to re-resolve every call.
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

-- Hundred-and-seventy-first pass (2026-09-05): Dragón found human NPCs
-- (traders in a town) rolling "warlike" and actually shooting at him —
-- the EXCLUDED_FROM_ROLLING check above only ever worked by resolving
-- the individual's REAL preset class name, which depends on the whole
-- AISensorComponent/AIResponsePreset chain already documented elsewhere
-- in this file as frequently failing to resolve at all. A human NPC
-- likely never resolves a preset the same way a monster does, so it
-- silently fell through EXCLUDED_FROM_ROLLING (checking a table with a
-- nil/wrong key) straight into the random roll.
--
-- Found a real, structural fix while investigating the "Pal Analyzer"
-- reference mod (Dragón's ask — it shows Pal info without the lag our
-- own Indicator.lua has, so its Blueprint graph was inspected for
-- technique): its own logic explicitly branches on
-- `UPalUtility::IsPalMonster(AActor*)` before ever treating something
-- as an actual creature. Confirmed live in this game's own native
-- header dump (CXXHeaderDump/Pal.hpp, class UPalUtility) — same trusted
-- static utility class this file already calls via get_pal_utility()
-- for GetIndividualCharacterHandleByActor. Unlike the preset chain,
-- this takes the raw actor directly — no AISensorComponent, no preset
-- object, nothing that can silently fail to resolve.
--
-- Fails toward the SAFE side on purpose (same convention as
-- Capture.IsAlreadyOwned): if this call itself fails for any reason,
-- treat the actor as NOT a monster (exclude it from rolling) rather
-- than risk repeating the trader incident. The only cost of a false
-- exclusion is one fewer Pal getting personality variety; the cost of
-- a false inclusion is a human NPC turned hostile.
local function is_confirmed_pal_monster(palActor)
    local utility = get_pal_utility()
    if utility == nil then return false end
    local isMonster = safe_call(function()
        return utility:IsPalMonster(palActor)
    end)
    return isMonster == true
end

-- Hundred-and-twenty-ninth pass: the native class every fresh, private
-- preset instance is constructed from (StaticConstructObject needs the
-- CLASS, not an instance) — cached once, same pattern as every other
-- StaticFindObject lookup in this file.
local function get_native_preset_class()
    if NativePresetClass then return NativePresetClass end
    NativePresetClass = safe_call(function()
        return StaticFindObject(NATIVE_PRESET_CLASS_PATH)
    end)
    return NativePresetClass
end

-- Resolves a real preset's Class Default Object (CDO) directly — no live
-- Pal actor needed anywhere. Tries the default-object path first (fast,
-- one lookup); if that fails for any reason, falls back to resolving the
-- class itself and calling :GetCDO() on it (same two-step fallback the
-- Passive Pals reference mod itself uses). Cached per base name since a
-- CDO is a permanent, unchanging reference once its class is loaded.
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

-- Hundred-and-thirty-fifth pass (2026-09-03): Dragón's live test of the
-- lag fix (hundred-and-thirty-second pass) confirmed `GetComponentByClass`
-- doesn't just fail SOMETIMES for a wild Pal's AISensorComponent — it
-- failed 41/41 real ENFORCE attempts and all 92 new-individual species-
-- preset reads in one full ~5-minute session, never once resolving. Not a
-- spawn-timing race (retrying every 8s for 5 minutes would have caught
-- that) — an outright broken path for this specific component class.
--
-- Same fix already proven in this exact project for the same shape of
-- problem (a class-based getter that just doesn't reach real live
-- instances, even though they demonstrably exist): `FindAllOf` for every
-- live instance of the class, then match by owner — the technique that
-- found the real HP-gauge canvas widget in Indicator.lua after
-- `GetComponentByClass`/`RegisterHook` both failed there too. Rebuilt at
-- most once per SENSOR_INDEX_REFRESH_SECONDS (never per-Pal-per-scan —
-- that exact mistake caused the ninety-fourth pass's lag bug), reused by
-- both GetPresetClassName (species default) and find_sensor_component
-- (enforcement/Won-Over) below.
local SENSOR_INDEX_REFRESH_SECONDS = 5
local sensorIndexByOwnerKey = {}
local sensorIndexBuiltAt = nil

-- Forward declaration for find_cached_sensor, which is defined further down
-- this file (next to the reactive SelectResponseBySenses hook that fills the
-- cache) but is needed by try_enforce_personality above it. Lua locals are
-- not hoisted, so without this the earlier function would silently see a
-- global nil instead. Assigned immediately after find_cached_sensor's real
-- definition; every read site guards on it being non-nil anyway, so even if
-- that assignment were ever removed the behaviour degrades to the old
-- fallback path rather than erroring.
local find_cached_sensor_fwd = nil

-- Hundred-and-thirty-sixth pass (2026-09-03): Dragón's retest showed the
-- FindAllOf fallback ALSO failed for every Pal (still 0 real species
-- presets read, 98/98 fell back to "curious"). Logged once ever, so the
-- next session finally shows WHICH half is empty: FindAllOf itself
-- returning nothing/very little (wrong class name, or these aren't
-- separately-reflected UActorComponent instances the way this project
-- assumed), or instances existing but the owner-key match failing (a
-- GetFullName() format mismatch between a component's :GetOwner() and the
-- Pal actor reference used elsewhere).
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

-- Returns a valid sensor component for palActor via the FindAllOf-based
-- index, rebuilding the index first if it's stale or has never been built.
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

-- Real stable ID for a live Pal actor (wild or owned). Returns nil if
-- anything along the chain fails (actor invalid, no handle yet, etc.) —
-- callers must handle nil, never assume this always succeeds.
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

    -- THIRTY-FIFTH PASS FIX (2026-09-02): the first live test produced a
    -- correct, STABLE id (same Pal -> same string, confirmed across two
    -- separate interactions) but a cosmetically wrong one — some fields
    -- came out 16 hex digits instead of 8. Root cause: UE4SS returns each
    -- int32 field as a full Lua number, and a NEGATIVE int32 (e.g. -1)
    -- sign-extends to a huge 64-bit value once handed to Lua's integer
    -- string.format — "%08X" only sets a MINIMUM width, so a negative
    -- field prints 16 hex digits instead of being masked to 32 bits.
    -- Masking each field with `% 0x100000000` first forces exactly 8 hex
    -- digits every time, regardless of sign.
    return safe_call(function()
        local function mask32(n)
            return math.floor((n or 0)) % 0x100000000
        end
        return string.format("%08X%08X%08X%08X",
            mask32(guid.A), mask32(guid.B), mask32(guid.C), mask32(guid.D))
    end)
end

-- Reads the real UPalAIResponsePreset class name off a live Pal actor's
-- sensor component, e.g. "BP_AIResponsePreset_friendly_C". Returns nil if
-- the actor has no sensor component or anything fails.
--
-- THIRTY-FIFTH PASS (2026-09-02): the first live test returned nil here
-- for a real Chikipi (logged as "preset=nil"), silently — safe_call
-- swallows the actual Lua error, so we couldn't tell which step failed.
-- Instrumented every step with its own explicit ok/err capture (same
-- "log the exact failing line" approach that found the real crash cause
-- back in Interaction.lua's seventh pass) so the NEXT test tells us
-- exactly where this breaks instead of just "nil". Logs every call for
-- now (still only from the already-rare pet/feed event, not per-tick) —
-- trim back to once-per-failure-type once the real cause is known.
function Personality.GetPresetClassName(palActor)
    if palActor == nil then return nil end

    -- NINETY-FOURTH PASS: dedup key for log_diag_once below — best-effort,
    -- falls back to the raw wrapper's tostring() if GetFullName() itself
    -- fails (rare, but this key only needs to be "stable enough," not
    -- perfect).
    local actorKey = safe_call(function() return palActor:GetFullName() end) or tostring(palActor)
    local sensorClass = get_sensor_component_class()
    if sensorClass == nil then
        log_diag_once(actorKey, "no-sensor-class", "[PalBonds/Personality] [DIAG] GetPresetClassName: could not resolve PalAISensorComponent class via StaticFindObject")
        return nil
    end
    local sensorOk, sensor = pcall(function()
        return palActor:GetComponentByClass(sensorClass)
    end)
    local sensorValidOk, sensorIsValid = false, false
    if sensorOk and sensor ~= nil then
        sensorValidOk, sensorIsValid = pcall(function() return sensor:IsValid() end)
    end
    if not (sensorOk and sensor ~= nil and sensorValidOk and sensorIsValid) then

        -- Hundred-and-thirty-fifth pass: GetComponentByClass confirmed
        -- broken for this component (see find_sensor_component_via_index's
        -- own comment above) — fall back to the FindAllOf-based index
        -- before giving up.
        sensor = find_sensor_component_via_index(palActor)
        if sensor == nil then
            log_diag_once(actorKey, "no-sensor", "[PalBonds/Personality] [DIAG] GetPresetClassName: GetComponentByClass AND the FindAllOf-based fallback both failed for " .. tostring(actorKey))
            return nil
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

    -- THIRTY-SIXTH PASS (2026-09-02): every real test so far (Sheepball,
    -- PinkCat/Cattiva, across two separate sessions) reaches this point
    -- with no earlier failure logged, then fails at GetFullName() with a
    -- plain "nil" — no Lua error message at all. That specific shape
    -- (silent nil, not a thrown error) matches a known UE4SS pattern:
    -- a field read can hand back a valid-looking Lua wrapper table around
    -- a NULL underlying UObject pointer, and calling a method on it
    -- returns nil instead of erroring. Checking preset:IsValid() first
    -- lets us tell "the pointer really is null for this Pal" (logged
    -- explicitly below) apart from some other, still-unexplained
    -- GetFullName failure (which would still fall through to the
    -- original diagnostic below).
    local validOk, isValid = pcall(function() return preset:IsValid() end)
    if validOk and isValid == false then

        -- NINETY-FOURTH PASS: Dragón's first live test of the new
        -- enforcement scan hit THIS exact branch 2813 times in ~3 minutes
        -- — a NEW failure shape (every prior test, thirty-fifth/-sixth
        -- passes, hit the GetFullName()-fails-silently branch below
        -- instead). Whether that's because these particular Pals were
        -- freshly spawned when first scanned (preset pointer genuinely not
        -- set up yet) or something else is still an open question — see
        -- CLAUDE.md's "Continuación 68". GetOrInitState now retries this
        -- resolution on later calls instead of caching nil forever, so if
        -- it's a timing issue this self-heals; log throttled either way.
        log_diag_once(actorKey, "null-preset", "[PalBonds/Personality] [DIAG] GetPresetClassName: sensor.AIResponsePreset is a NULL object reference (preset:IsValid() == false) for " .. tostring(actorKey) .. " — this Pal's preset pointer isn't actually set (yet?), despite the field read succeeding")
        return nil
    end

    -- GetClass():GetFName() would be more "correct," but GetFullName()
    -- already gives us a path ending in the class name, same pattern
    -- used everywhere else in this project (OtomoWatch.lua's describe()).
    local nameOk, fullName = pcall(function() return preset:GetFullName() end)
    if not nameOk or fullName == nil then
        log_diag_once(actorKey, "getfullname-failed", "[PalBonds/Personality] [DIAG] GetPresetClassName: preset:GetFullName() FAILED for " .. tostring(actorKey) .. " — " .. tostring(fullName) .. " (preset:IsValid() check " .. (validOk and tostring(isValid) or ("also failed: " .. tostring(isValid))) .. ")")
        return nil
    end

    -- fullName looks like "BP_AIResponsePreset_friendly_C /Game/.../Foo.Foo:...Preset_2147459442"
    -- — the class name is the first token.
    return fullName:match("^(%S+)")
end

-- Maps a real preset class name to one of our DISPOSITIONS. Logs the
-- first time an unrecognized preset is seen (not every time — see the
-- thirty-third pass lesson about unthrottled logging).
--
-- Hundred-and-sixty-first pass (2026-09-04): the fallback used to be
-- "friendly" for both failure cases below (unreadable preset, and a
-- real-but-unmapped preset name) — Dragón pointed out directly that
-- this was actively misleading: since `GetPresetClassName` fails to
-- read a real preset for nearly every Pal (confirmed live — the [DIAG]
-- failure line fires on almost every new individual), most of what
-- looked like a genuinely friendly species default on the on-screen
-- label was actually just this fallback silently standing in for "we
-- don't know," making a broken read look identical to a real, confirmed
-- disposition. Changed the fallback to a distinct sentinel, "unknown",
-- specifically so a failed read is visibly different from a real
-- "friendly" species default everywhere this value surfaces (the label
-- in Indicator.lua, GetDisposition() callers, this project's own
-- future debugging). "unknown" is deliberately NOT added to the
-- DISPOSITIONS list above — it's not a real, rollable tier, just a
-- failure marker for this one specific lookup.
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

-- Convenience: species-default disposition for a live Pal actor, in one
-- call. nil if anything along the chain fails.
function Personality.GetSpeciesDefaultDisposition(palActor)
    local presetClassName = Personality.GetPresetClassName(palActor)
    if presetClassName == nil then return nil end
    return Personality.PresetClassNameToDisposition(presetClassName)
end

-- Ensures per-instance state exists for a given live Pal actor, seeding
-- it from the species default the first time we see this Pal. Safe to
-- call repeatedly — a no-op after the first successful call for a given
-- Pal. Returns the palId (or nil if a stable ID couldn't be resolved) so
-- callers can use it for subsequent Get/SetDisposition calls without
-- resolving the ID twice.
function Personality.GetOrInitState(palActor)
    local palId = Personality.GetStableId(palActor)
    if palId == nil then return nil end
    if PersonalityState[palId] == nil then

        -- THIRTY-SIXTH PASS (2026-09-02) FIX: this used to call
        -- GetPresetClassName(palActor) twice — once indirectly via
        -- GetSpeciesDefaultDisposition, once again just to populate the
        -- presetClassName field below — which meant every [DIAG] failure
        -- line got logged twice per new Pal. One call now, reused for both.
        local presetClassName = Personality.GetPresetClassName(palActor)
        local speciesDefault = Personality.PresetClassNameToDisposition(presetClassName)

        -- Ninety-second pass: roll this individual's personality tier ONCE,
        -- right here, at the same moment its state is first created (first
        -- pet/feed/interaction encounter — the closest on-demand proxy this
        -- project has to "at spawn," since nothing here runs a real per-
        -- spawn hook). "normal" tier just keeps the species default;
        -- anything else OVERRIDES it as the effective disposition.
        local rolledTier
        if not is_confirmed_pal_monster(palActor) then

            -- Hundred-and-seventy-first pass: structural exclusion, checked
            -- BEFORE the preset-name table — catches human NPCs even when
            -- their preset never resolves (the trader incident).
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
        PersonalityState[palId] = {
            disposition = effectiveDisposition,
            speciesDefault = speciesDefault,
            presetClassName = presetClassName,
            rolledTier = rolledTier,

            -- Ninety-third pass: whether the ENFORCEMENT swap (see below)
            -- has been successfully applied (or deliberately skipped as
            -- not-needed) for this individual. false means "keep retrying
            -- on the next scan" — e.g. no live donor Pal of the desired
            -- species happens to be nearby yet.
            enforcementApplied = false,
        }
        Logger.log(string.format(
            "[PalBonds/Personality] [PERSONALITY-ROLL] new individual %s — rolled tier=%s, species default=%s, effective disposition=%s",
            tostring(palId), tostring(rolledTier), tostring(speciesDefault), tostring(effectiveDisposition)
        ))
    elseif PersonalityState[palId].presetClassName == nil then

        -- NINETY-FOURTH PASS: the very first read can fail if the preset
        -- pointer genuinely isn't set yet at the exact moment we first see
        -- a Pal (Dragón's first live enforcement test hit this 100% of the
        -- time, unlike any prior session — see the null-preset note in
        -- GetPresetClassName above). Without this, that individual would
        -- be stuck on the "curious" fallback default forever, and
        -- enforcement could never confirm "already naturally uses X."
        -- Retrying here (called every scan pass anyway) costs nothing when
        -- it keeps failing (throttled logging) and self-heals once the
        -- pointer becomes valid — never re-rolls the tier itself, only
        -- refreshes the species-default side of the state.
        local retryPresetClassName = Personality.GetPresetClassName(palActor)
        if retryPresetClassName ~= nil then
            local state = PersonalityState[palId]
            state.presetClassName = retryPresetClassName
            state.speciesDefault = Personality.PresetClassNameToDisposition(retryPresetClassName)
            local logSuffix
            if state.rolledTier == "normal" then
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

-- Read-only accessor for just the rolled tier (as opposed to the
-- resolved effective disposition GetDisposition returns) — mainly for
-- logging/debugging so "normal that happens to default to hostile" and
-- "actually rolled hostile" stay distinguishable.
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
function Personality.GetDisposition(palId)
    if palId == nil then return nil end
    local state = PersonalityState[palId]
    return state and state.disposition or nil
end

-- Read-only accessor for the full per-instance state table, mainly for
-- logging/debugging (e.g. seeing the original species default alongside
-- the current, possibly-drifted disposition).
function Personality.GetState(palId)
    if palId == nil then return nil end
    return PersonalityState[palId]
end

-- ==========================================================================
-- NINETY-THIRD PASS — ENFORCEMENT. Everything below is new this pass, all
-- read-only against shared game data (only ever WRITES to one specific
-- wild Pal's own AIResponsePreset field, gated by an explicit ownership
-- check first — see try_enforce_personality below).
-- ==========================================================================

-- Reads a live Pal actor's AISensorComponent, or nil if anything fails.
-- Small, standalone helper (deliberately not reusing GetPresetClassName's
-- internals) so this new, untested enforcement path can't regress the
-- already-working species-default detection above.
-- Hundred-and-thirty-second pass (2026-09-03): find_sensor_component fails
-- on 1170 out of 1173 real [ENFORCE] attempts in Dragón's own test session
-- — near-100%, not "sometimes." That's a real, un-diagnosed reliability
-- problem, not just a rare edge case — but the three possible failure
-- branches below were never individually logged, so it was impossible to
-- tell WHICH one was actually happening. Logs the exact failure branch
-- ONCE EVER (a single global flag, not per-individual — this function is
-- called constantly, every scan, for every non-done Pal, so anything less
-- strict would reintroduce the exact lag bug just fixed above) so the
-- next test session finally shows which of the three is the real cause.
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

    -- Hundred-and-thirty-fifth pass: Dragón's live test confirmed
    -- GetComponentByClass is broken for this component, not just
    -- unreliable — 41/41 real ENFORCE attempts and all 92 new-individual
    -- species-preset reads failed the same way in one full session. Fall
    -- back to the FindAllOf-based index (see its own comment above) before
    -- giving up.
    local viaIndex = find_sensor_component_via_index(palActor)
    if viaIndex ~= nil then
        return viaIndex
    end
    log_sensor_failure_once("GetComponentByClass AND the FindAllOf-based fallback both failed to resolve a valid sensor component")
    return nil
end

-- Hundred-and-forty-seventh pass (2026-09-04): Dragón's direct pushback —
-- "isn't the answer in the mod? copy what the reference does" — was right.
-- Re-read the Passive Pals reference mod's actual main.lua (not just its
-- comments already summarized in this file) and found its PRIMARY, DEFAULT
-- mechanism was never the per-individual "species layer" this project had
-- been trying to replicate (that's an OPT-IN refinement in the reference
-- mod, off by default) — it's a much simpler "preset layer" that never
-- touches individual Pal instances or their sensor components AT ALL: it
-- directly rewrites the SHARED preset Class Default Objects themselves
-- (findPreset in main.lua — the exact same find_preset_cdo technique this
-- file already uses for apply_forced_preset above). Every wild Pal that
-- uses a given AIResponsePreset points at the SAME shared object, so one
-- write to that preset's own 8 fields changes every Pal using it globally
-- and instantly — zero dependency on FindAllOf("PalAISensorComponent")
-- (the still-broken mechanism item 4 on the saved priority list depends
-- on), zero per-individual retry loop, zero waiting for a specific Pal's
-- sensor component to exist. This sidesteps that whole bug entirely for
-- the "make every wild Pal calm" goal, rather than needing it fixed first.
--
-- Real values confirmed via the reference mod's own config.lua
-- (EPalAIResponseType: Ignore=0, Escape=1, Battle=2, Special=3,
-- Battle_Anyway=4) and its own humanPresetNames list (VillageNPC/Kill_All
-- are human-NPC-only presets, never real Pals — excluded here too).
-- Deliberately narrower than "every preset in the game": only the
-- confirmed real wild-Pal flee/combat presets are targeted, leaving
-- Default/NotInterested/Boss untouched for now (Boss especially — pacifying
-- boss encounters is a separate design question Dragón hasn't asked for).
--
-- Safety copied directly from the reference mod's own applyProfileToObject:
-- a slot already holding EPalAIResponseType.Special (3) is left alone,
-- never overwritten. This project's own Pet/Feed interaction relies on a
-- real Special-tagged reaction existing somewhere in the game's own data —
-- blindly overwriting it here could break vanilla pet/feed eligibility on
-- whatever species carry it, so this preserves it exactly as the reference
-- mod does, not a new guess.
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

-- Hundred-and-twenty-ninth pass (2026-09-03): shared core, used by both the
-- periodic enforcement scan and the one-shot Won-Over event. Builds a
-- fresh, PRIVATE preset object (never shared with any other Pal) matching
-- `desiredBaseName`'s real 8 field values, read from that preset's own
-- Class Default Object (`find_preset_cdo` above — no live donor Pal needed
-- anywhere, see that function's own comment for the real reference-mod
-- technique this is based on), and assigns it to `sensor`. Returns
-- `true, nil` on success or `false, reason` on failure — the caller
-- decides how to log/retry, this function never touches PersonalityState
-- itself so it stays reusable from either call site.
-- Two-hundred-and-second pass (2026-09-06): Dragón's real, still-open
-- question from the agreed plan — the copied preset's `Damaged_*` fields
-- (as opposed to `Discover_*`, the only ones ever glanced at before) have
-- never actually been read/verified. If a Pal is already engaged in
-- combat when its preset swaps to "friendly," its next decision may be
-- driven by the Damaged_* branch instead of Discover_* — if THAT branch
-- of the source CDO isn't actually peaceful, no amount of repeating
-- interrupt_and_resense would fix the interrupt bug. Logs the real 8
-- field values read off the SOURCE cdo (identical to what ends up on the
-- fresh per-Pal copy, since this is a straight field-for-field copy)
-- exactly once per desiredBaseName — the CDO is a shared, static,
-- never-changing reference regardless of which Pal receives it, so
-- logging it once ever is enough to answer the question, not per-Pal.
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
local function apply_forced_preset(sensor, desiredBaseName)
    local cdo = find_preset_cdo(desiredBaseName)
    if not cdo then
        return false, "could not resolve the default preset object for " .. tostring(desiredBaseName)
    end
    log_preset_slots_once(desiredBaseName, cdo)
    local nativeClass = get_native_preset_class()
    if not nativeClass then
        return false, "could not resolve the native PalAIResponsePreset class"
    end
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
    local setOk, setErr = pcall(function() sensor.AIResponsePreset = fresh end)
    if not setOk then
        return false, "AIResponsePreset write FAILED: " .. tostring(setErr)
    end
    return true, nil
end

-- Hundred-and-ninety-seventh pass (2026-09-05): Dragón's real question —
-- even when a preset swap succeeds, a Pal already mid-fleeing/mid-fighting
-- keeps executing that ALREADY-DECIDED action, since swapping
-- AIResponsePreset only changes what a FUTURE decision reads, not
-- whatever's already running. He separately pointed at the game's own
-- real "notice" mechanic (the "!" over a Pal's head, which visibly
-- interrupts whatever it was doing to turn and face the player) as
-- evidence this game DOES have a real mechanism for exactly this. Found
-- two concrete, real, simple functions in Pal.hpp (never called by this
-- project before) that mirror that natural behavior:
--   - `UPalAIActionComponent:AllCancelAction_Logic_HardScript_Reaction
--     (Instigator)` — cancels whatever's running at the AI-decision
--     priority tiers (Logic/HardScript/Reaction, i.e. ordinary wild-AI
--     flee/fight decisions, as opposed to lower-priority SoftScript
--     background behavior). A single-pointer-argument call, same safety
--     shape as everything else already proven in this project.
--   - `UPalAISensorComponent:RequestSightCheckAsync(bIncludePlayer,
--     bIncludeAliveNPC, bIncludeEdibleDeadNPC, RangeRate, bIgnoreOtomo)` —
--     the real function declared right next to SelectResponseBySenses,
--     almost certainly what actually produces the real "notice" trigger
--     Dragón described. Also a plain-args call.
-- Calling the cancel FIRST (stop the current action) then requesting a
-- fresh sight check (force a new decision using the just-swapped preset)
-- mirrors that natural notice-and-turn sequence. Neither constructs or
-- attaches a new AI object (the bigger, still-untried risk category
-- Combat.lua's own notes flag) — both are simple calls on components this
-- file already resolves safely elsewhere (the Controller/AIActionComponent
-- chain is the exact same one Combat.lua's FOLLOW-DIAG already reads).
-- First live use of either function in this project — bracketed with
-- before/after logging per this project's standing crash-diagnosis
-- discipline (the only method that's ever actually found a real crash's
-- cause here). Best-effort only: any failure here still leaves the
-- tracked disposition/preset swap intact, just without the interrupt.
-- Two-hundred-and-fourteenth pass: the before/after chatter here produced 222
-- lines for only 37 real calls in Dragón's run (six lines each), every one
-- forced to disk. The before/after pattern exists for crash forensics and has
-- earned its keep historically, but these three calls are long proven safe, so
-- it is off by default now and failures still always log. Flip to true if this
-- ever needs crash-tracing again.
local INTERRUPT_VERBOSE = false
-- ===================================================================
-- TWO JOBS, AND THEY ARE SEPARABLE (three-hundred-and-seventh pass, 2026-09-11)
-- ===================================================================
-- This function does two different things, and the previous pass learned the
-- hard way that they must be controllable independently:
--
--   1. AllCancelAction_Logic_HardScript_Reaction — CANCELS whatever the Pal is
--      doing. Necessary when turning a fleeing or attacking Pal into a friendly
--      one, because otherwise it carries on fleeing or attacking. Destructive
--      for a Pal already fighting FOR us: it kills the swing in progress, which
--      is what was breaking melee companions.
--
--   2. ResetResponsedMaxBiologicalGrade + RequestSightCheckAsync — makes the
--      newly written preset actually TAKE EFFECT. A preset is only consulted
--      when the Pal next senses (passes 166/169), so without this the write sits
--      unused and the Pal keeps acting on its old disposition.
--
-- The previous pass skipped the WHOLE function for an existing companion to
-- protect its attack, and thereby also skipped job 2 — so the Discover = Battle
-- flip was written and never read, and the companions stopped fighting
-- altogether rather than fighting intermittently. Dragón: "this run they didnt
-- even made the animation for attack at all, neither responded when getting hit
-- either". That is what a preset that never takes effect looks like.
--
-- `cancelActions` splits them: false does job 2 only.
local function interrupt_and_resense(palActor, sensor, palId, cancelActions)
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

        -- Hundred-and-ninety-ninth pass (2026-09-06): the swap+cancel+resense
        -- combo above is now confirmed running clean 5/5 times, but Dragón
        -- still saw zero visible behavior change — a Pal that turned
        -- "friendly" kept fleeing/attacking exactly as before. Since nothing
        -- here errors, the real blocker is some OTHER persistent state,
        -- separate from the preset, that keeps a Pal committed to a
        -- decision it already made. Real, concrete candidate found right on
        -- this same sensor class: `ResponsedMaxBiologicalGrade` (a plain
        -- int32 field) plus its own reset function,
        -- `ResetResponsedMaxBiologicalGrade()` — the name and shape strongly
        -- suggest a hysteresis/dedup value ("the strongest threat grade
        -- I've already reacted to") meant to stop a Pal from re-reacting to
        -- something weaker than whatever it already committed to — exactly
        -- the kind of lock that would survive a preset swap untouched.
        -- Dragón's own framing ("reset their behavior") matches this
        -- function almost literally. Calling it right alongside the
        -- existing cancel+resense, before the fresh sight check runs, so
        -- the next real decision isn't silently discarded by this guard.
        if INTERRUPT_VERBOSE then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — about to call ResetResponsedMaxBiologicalGrade NOW") end
        local ok3, err3 = pcall(function() sensor:ResetResponsedMaxBiologicalGrade() end)
        if INTERRUPT_VERBOSE or not ok3 then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — ResetResponsedMaxBiologicalGrade returned: " .. (ok3 and "ok" or ("FAILED: " .. tostring(err3)))) end
        if INTERRUPT_VERBOSE then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — about to call RequestSightCheckAsync NOW") end
        local ok2, err2 = pcall(function() sensor:RequestSightCheckAsync(true, true, false, 1.0, false) end)
        if INTERRUPT_VERBOSE or not ok2 then Logger.log("[PalBonds/Personality] [INTERRUPT] " .. tostring(palId) .. " — RequestSightCheckAsync returned: " .. (ok2 and "ok" or ("FAILED: " .. tostring(err2)))) end
    end
end

-- Hundred-and-forty-eighth pass (2026-09-04) REFACTOR: split the old
-- try_enforce_personality into a sensor-AGNOSTIC core (everything except
-- actually finding a sensor) plus two thin callers — the original
-- proactive scan (finds a sensor via the broken find_sensor_component,
-- kept running as a fallback) and a new REACTIVE hook below (gets a
-- sensor handed to it directly, no search needed at all). Behavior
-- unchanged for the scan path; this is a pure extraction.
local function try_enforce_personality_with_sensor(palActor, palId, sensor)
    local state = PersonalityState[palId]
    if not state or state.enforcementApplied then return end
    if state.rolledTier == "normal" then

        -- Nothing to enforce — species default IS the rolled result.
        state.enforcementApplied = true
        return
    end

    -- SAFETY: never touch an owned Pal. Ownership can change after the
    -- roll (a wild Pal gets captured), so this is re-checked every time
    -- for anything not yet marked done, same "verify before writing to
    -- real game state" discipline this project has kept since the
    -- eighteenth/eighty-second passes. Capture.lua doesn't require this
    -- module (confirmed no circular require), but this still loads it
    -- lazily/defensively, matching Trust.lua's tick_followers pattern.
    local okReq, Capture = pcall(require, "Capture")
    if not okReq or not Capture or not Capture.IsAlreadyOwned then
        Logger.log("[PalBonds/Personality] [ENFORCE] could not load Capture.IsAlreadyOwned — skipping this attempt for " .. tostring(palId) .. " out of caution (ownership unknown)")
        return
    end
    local isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
    if isOwned ~= false then

        -- true, or unknown (safe_call failed) — either way, never write.
        -- Mark done: an owned Pal's personality tier no longer matters
        -- (it's the player's Otomo now, this system is wild-Pal-only).
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

        -- This species already naturally uses the preset the rolled tier
        -- wants (e.g. rolled "hostile" on an already-Warlike species) —
        -- nothing to swap.
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

        -- Two-hundred-and-sixth pass (2026-09-06) — interrupt_and_resense
        -- REMOVED from this path deliberately. It stays on the two paths
        -- that actually need it (MaybeBecomeFriendlyByBar and ForceTier).
        --
        -- Why it was wrong here: interrupt_and_resense exists to make a Pal
        -- that is ALREADY mid-behavior (fleeing from you, or attacking you)
        -- drop that behavior and re-decide, because its disposition changed
        -- underneath it. That is a real need when the player has just won a
        -- Pal over, or when a Pal is being forced to flee on trust loss.
        --
        -- This call site is different: it is the routine spawn-time
        -- enforcement that gives a freshly-seen wild Pal the preset matching
        -- its rolled tier. That Pal has not changed its mind about anything
        -- — it is simply being set up — so there is nothing to interrupt.
        -- Firing it here meant every single wild Pal that rolled a non-normal
        -- tier got AllCancelAction_Logic_HardScript_Reaction (cancelling
        -- whatever it was doing) plus ResetResponsedMaxBiologicalGrade plus
        -- RequestSightCheckAsync (an async sight trace) as it came into
        -- range. The live log from 2026-09-06 shows this hitting 43 distinct
        -- Pals in a single 10-minute session — work that scales directly
        -- with how many Pals stream in around the player, which matches the
        -- "worse when entering a new area" shape of the lag being reported.
        --
        -- Both of these calls were added on 2026-09-06 (the hundred-and-
        -- ninety-seventh and two-hundredth passes), which also matches
        -- Dragón's own timing report: "lag still feels a lot laggier than
        -- yesterday, im sure it was something last added."
        --
        -- Behavioural note, so this isn't mistaken for a regression: the
        -- preset swap itself is untouched and still applies exactly as
        -- before. The only thing removed is the forced action-cancel and
        -- re-sense on a Pal that was never in a stale behaviour to begin
        -- with.
    else
        Logger.log("[PalBonds/Personality] [ENFORCE] " .. tostring(palId) .. " — " .. tostring(err) .. ", will retry")
    end
end

-- Attempts to make ONE wild Pal's real behavior match its already-rolled
-- tier, via the proactive scan (finds its own sensor — the historically
-- unreliable path, kept as a fallback for whatever the reactive hook
-- below misses). Safe to call repeatedly — becomes a no-op once
-- state.enforcementApplied is true.
local function try_enforce_personality(palActor, palId)
    local state = PersonalityState[palId]
    if not state or state.enforcementApplied then return end

    -- Two-hundred-and-sixth pass (2026-09-06): try the reactive hook's
    -- sensor cache BEFORE falling back to find_sensor_component.
    --
    -- This is a real cost fix, not just tidiness. find_sensor_component's
    -- own fallback (find_sensor_component_via_index) rebuilds a world-wide
    -- index every 5 seconds: a FindAllOf("PalAISensorComponent") across the
    -- whole loaded world, plus GetOwner() + GetFullName() — two reflection
    -- round-trips — for EVERY sensor component it returns. Because this
    -- scan runs every 8s and the index goes stale every 5s, essentially
    -- every scan that still has an unenforced Pal in range paid for a full
    -- rebuild.
    --
    -- Meanwhile the reactive SelectResponseBySenses hook (hundred-and-
    -- ninety-seventh pass) already caches a valid, live sensor for
    -- practically every wild Pal near the player, for free, as a side
    -- effect of the game's own AI calls. Reading that table first turns the
    -- common case into a single table lookup and skips the rebuild
    -- entirely; the old path stays as the fallback for any Pal the reactive
    -- hook hasn't seen yet, so nothing that worked before stops working.
    local sensor = find_cached_sensor_fwd and find_cached_sensor_fwd(palId)
    if not sensor then
        sensor = find_sensor_component(palActor)
    end
    if not sensor then

        -- Hundred-and-thirty-second pass (2026-09-03) FIX, REAL LAG
        -- REGRESSION FOUND: unlike the old donor-search failure (which was
        -- throttled via state.noDonorLoggedOnce), this rewrite never
        -- throttled this specific line — and it turns out
        -- find_sensor_component fails almost every time in practice (1170
        -- of 1173 real [ENFORCE] lines in Dragón's very next test session
        -- were this exact message, repeating every 8s forever for every
        -- non-normal-tier Pal). Same shape of self-inflicted lag bug this
        -- project has hit before (ninety-fourth/ninety-fifth passes) —
        -- should have been throttled from the start, same discipline as
        -- every other "will keep retrying" message in this file.
        if not state.noSensorLoggedOnce then
            state.noSensorLoggedOnce = true
            Logger.log("[PalBonds/Personality] [ENFORCE] " .. tostring(palId) .. " has no readable AISensorComponent via the proactive scan — cannot enforce this way yet, will keep quietly retrying every scan until it resolves (logged once). The reactive hook below may catch it first.")
        end
        return
    end
    try_enforce_personality_with_sensor(palActor, palId, sensor)
end

-- Hundred-and-forty-eighth pass (2026-09-04): the REAL fix for the sensor
-- bug, found by re-reading the Passive Pals reference mod's own "species
-- layer" in full (not just its already-summarized preset-layer technique
-- — see hook-points.md/the design-for-future-scale memory's third
-- recurrence). Instead of proactively SEARCHING for each Pal's
-- AISensorComponent (find_sensor_component above, confirmed broken —
-- 1170/1173 real failures), hook the function the GAME itself calls every
-- time a sensor makes a decision, and take the sensor directly from the
-- hook's own Context. This was already flagged as a real candidate back
-- in the ninety-second pass's own notes ("a properly-throttled
-- SelectResponseBySenses override, neither attempted yet") but never
-- actually wired until now.
--
-- Real hook path, confirmed via the reference mod's own config.lua:
-- `/Script/Pal.PalAISensorComponent:SelectResponseBySenses`.
--
-- LAG DISCIPLINE (this project has been burned by unthrottled per-event
-- hooks before — ninety-fourth/ninety-fifth/hundred-and-thirty-second
-- passes): this can fire at real AI decision-making frequency for every
-- wild Pal in range, so `handledSensorKeys` dedupes FIRST, before any
-- other work, so every fire after the first for a given sensor is just a
-- cheap table lookup — never a repeat of the ownership check/preset
-- resolution/apply_forced_preset. Marking a sensor handled even after a
-- FAILED attempt (rather than retrying every single fire) is a
-- deliberate tradeoff: a Pal that fails here can still be caught later by
-- the proactive scan above instead of this hook hammering it forever.
-- Hundred-and-ninety-eighth pass (2026-09-06): Dragón's real test found
-- MaybeBecomeFriendlyByBar's own one-shot sensor lookup (find_sensor_component,
-- called fresh, no retry, right at the WON-OVER moment) failing live for
-- the actual bonding-target Pal — the exact "layer 1" root cause the
-- hundred-and-ninety-sixth pass already flagged, just confirmed with real
-- log evidence this time: "[WON-OVER] ... has no readable
-- AISensorComponent — cannot swap its real AI" fired immediately after
-- "[WON-OVER] ... crossed the friendly-trigger fraction," with zero retry
-- opportunity. Meanwhile this reactive hook — proven far more reliable,
-- since it gets its sensor handed directly from the game's own call rather
-- than searching for one — sees a huge number of real sensors fire, for
-- every wild Pal in range, all the time (that's the whole reason
-- handledSensorKeys exists to dedupe it). Caching every sensor this hook
-- ever sees, keyed by the owning Pal's stable ID, gives
-- MaybeBecomeFriendlyByBar/ForceTier a real, already-proven-reliable
-- source to check FIRST, before ever falling back to the search-based
-- find_sensor_component. Cached regardless of rolled tier (normal-tier
-- Pals were never cached before, since the old code returned before
-- reaching this point for them) and regardless of the dedup state below —
-- this is a passive, read-only cache update, no new native call, no
-- extra work beyond a table write.
local cachedSensorByPalId = {}
local function cache_sensor_for_pal(sensor, pawn)
    local palId = Personality.GetOrInitState(pawn)
    if palId then cachedSensorByPalId[palId] = sensor end
    return palId
end

-- Read-only accessor other functions in this file use INSTEAD of calling
-- find_sensor_component first — a real, already-live sensor reference,
-- validated fresh each time (a Pal's sensor component doesn't change once
-- created, but the Pal itself could have despawned since the hook last saw it).
local function find_cached_sensor(palId)
    if not palId then return nil end
    local sensor = cachedSensorByPalId[palId]
    if not sensor then return nil end
    local validOk, isValid = pcall(function() return sensor:IsValid() end)
    if validOk and isValid then return sensor end
    cachedSensorByPalId[palId] = nil
    return nil
end

-- Two-hundred-and-sixth pass: publish it to the forward declaration near the
-- top of this file so try_enforce_personality (defined above) can use this
-- cache instead of rebuilding the world-wide sensor index every scan.
find_cached_sensor_fwd = find_cached_sensor
local handledSensorKeys = {}
local handledSensorAddresses = {}

-- Two-hundred-and-eighty-eighth pass (2026-09-09) -- ORDER OF OPERATIONS FIX.
--
-- This runs on EVERY sense evaluation of EVERY Pal in the world, continuously.
-- It used to call GetFullName() -- a reflection round-trip that builds a full
-- object path -- and then GetOuter(), and then cache_sensor_for_pal() (which
-- calls GetOrInitState and resolves the Pal's individual ID) BEFORE reaching
-- the handledSensorKeys dedup that makes the whole thing a once-per-Pal
-- operation. So the dedup only ever skipped the last step; all the expensive
-- work ran on every evaluation, forever.
--
-- That is the third time this exact shape has cost this project real frames:
-- the SetHPPercent diagnostic hook and the OTOMO-GETTER-WATCH logging were both
-- removed for it. A throttle placed after the expensive call throttles nothing.
--
-- GetAddress() is the fix: it returns the object's raw memory address with no
-- name or path construction, so the common case is now one table lookup.
--
-- Known and accepted limitation: an address can be reused after the original
-- object is collected, so a recycled address could skip enforcement for a new
-- Pal. The consequence is that one Pal behaves with vanilla AI instead of its
-- rolled personality, and the proactive scan (PERSONALITY_SCAN_INTERVAL_MS)
-- already exists as the backstop for exactly this -- it is the documented
-- fallback for when this hook cannot be registered at all.
local function on_sensor_select_response(Context)
    local sensor = safe_call(function() return Context:get() end)
    if not sensor then return end

    -- Cheap identity first. Everything below this line is expensive.
    local addr = safe_call(function() return sensor:GetAddress() end)
    if addr ~= nil and handledSensorAddresses[addr] then return end
    local sensorKey = safe_call(function() return sensor:GetFullName() end)
    if not sensorKey then return end
    local owner = safe_call(function() return sensor:GetOuter() end)
    local pawn = owner and safe_call(function() return owner.Pawn end)
    local validOk, isValid = pcall(function() return pawn ~= nil and pawn:IsValid() end)
    if not (validOk and isValid) then return end
    local palId = cache_sensor_for_pal(sensor, pawn)
    if not palId then return end
    if handledSensorKeys[sensorKey] then
        if addr ~= nil then handledSensorAddresses[addr] = true end
        return
    end
    handledSensorKeys[sensorKey] = true

    -- Two-hundred-and-ninety-second pass (2026-09-09): the address is marked
    -- HERE, not on entry. The previous version marked it as soon as the name
    -- resolved -- before the pawn validity check below it -- and a sensor's
    -- first sense evaluation frequently happens before its pawn is resolvable.
    -- Those Pals were then skipped forever: no personality state, so no
    -- personality tag and no enforcement. Dragon caught it as "the personality
    -- tags dont appear even tho its toggled on".
    --
    -- The whole point of the address check is to skip work already DONE, so it
    -- has to be set where the work finishes -- the same place handledSensorKeys
    -- has always been set -- not where it starts.
    if addr ~= nil then handledSensorAddresses[addr] = true end
    try_enforce_personality_with_sensor(pawn, palId, sensor)
end
local SENSOR_HOOK_MAX_ROUNDS = 20
local SENSOR_HOOK_RETRY_MS = 5000
local function register_sensor_sense_hook(round)
    round = round or 1
    local ok, err = pcall(function()
        RegisterHook("/Script/Pal.PalAISensorComponent:SelectResponseBySenses", function(Context)
            safe_call(function() on_sensor_select_response(Context) end)
        end)
    end)
    if ok then
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

-- Hundred-and-twenty-fifth pass (2026-09-03) — Dragón's original personality
-- idea, from before the tier-rolling system even existed: "if the player
-- chases a skittish pal to pet it, and once it manages, the pal is like
-- 'hey, this hoomin is not so bad' then changes to curious."
--
-- Hundred-and-ninety-fifth pass (2026-09-05): REPLACED the original
-- one-shot version of this idea (fired once, only for a Pal whose
-- disposition was "escape", only on its first ever successful
-- interaction) with a bar-relevant version, per Dragón's explicit
-- instruction to remove the old mechanic entirely in favor of this one.
-- Now triggers off crossing a real fraction of the Pal's OWN bonding bar
-- (FRIENDLY_TRIGGER_RATIO in Trust.lua, currently 20%) — called from
-- Trust.OnInteractionSucceeded, which already has the real point/
-- threshold numbers needed to compute that ratio. Applies from ANY
-- starting disposition, not just "escape" — generalizes the same "you've
-- clearly made real progress taming this Pal" idea to every tier, not
-- only the shy one.
function Personality.MaybeBecomeFriendlyByBar(palId, palActor)
    if palId == nil then return end
    local state = PersonalityState[palId]
    if not state then return end
    if state.disposition == "friendly" then return end 
    if state.becameFriendlyByBar then return end 
    local fromDisposition = state.disposition
    state.becameFriendlyByBar = true
    state.disposition = "friendly"
    Logger.log(string.format(
        "[PalBonds/Personality] [WON-OVER] %s crossed the friendly-trigger fraction of its bonding bar (was '%s') — tracked disposition now 'friendly' (rolled tier stays recorded as '%s' for history/debugging)",
        tostring(palId), tostring(fromDisposition), tostring(state.rolledTier)
    ))
    if not palActor then return end

    -- Same ownership re-check discipline as try_enforce_personality — a
    -- Pal's real-world status can change between the roll and this event.
    local okReq, Capture = pcall(require, "Capture")
    local isOwned = true 
    if okReq and Capture and Capture.IsAlreadyOwned then
        isOwned = safe_call(function() return Capture.IsAlreadyOwned(palActor) end)
        if isOwned == nil then isOwned = true end
    end
    if isOwned ~= false then
        return 
    end
    local desiredBaseName = TIER_TO_DONOR_PRESET_CLASS["friendly"]
    local desiredClassName = desiredBaseName .. "_C"
    if state.presetClassName == desiredClassName then
        return 
    end

    -- Hundred-and-ninety-eighth pass: check the reactive hook's cached
    -- sensor FIRST — confirmed live to be the reliable source, see
    -- cache_sensor_for_pal's own comment for why the plain
    -- find_sensor_component fallback below just failed for a real Pal.
    local sensor = find_cached_sensor(palId) or find_sensor_component(palActor)
    if not sensor then
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " has no readable AISensorComponent (neither cached nor found via scan) — cannot swap its real AI, tracked disposition still updated")
        return
    end
    local ok, err = apply_forced_preset(sensor, desiredBaseName)
    if ok then
        state.enforcementApplied = true
        Logger.log(string.format(
            "[PalBonds/Personality] [WON-OVER] %s real AIResponsePreset ALSO swapped to friendly (private preset, no live donor Pal needed — hundred-and-twenty-ninth pass)",
            tostring(palId)
        ))
        interrupt_and_resense(palActor, sensor, palId)
    else
        Logger.log("[PalBonds/Personality] [WON-OVER] " .. tostring(palId) .. " — " .. tostring(err) .. " (tracked disposition still updated)")
    end
end

-- Hundred-and-fifty-sixth pass (2026-09-04): generic version of the
-- WON-OVER pattern above, for the opposite direction — Dragón's real
-- fleeing on trust-loss (item 2 on the saved priority list). Capture.lua
-- used to just flag a Pal internally and block further interaction,
-- with an honest TODO admitting real flee behavior was never attempted
-- (forcing an actor to flee looked like a new, risky call category at
-- the time). It isn't anymore: this reuses the EXACT same private-preset
-- swap already confirmed live today for the "escape" tier — no new
-- native call, just forcing the tracked tier and letting the
-- already-proven enforcement path apply it.
--
-- Resets `enforcementApplied = false` before attempting anything, so a
-- Pal that was already successfully enforced under its OLD tier gets a
-- genuine new attempt rather than being silently skipped (every
-- enforcement path below gates on this flag). Honest caveat: the
-- REACTIVE hook (on_sensor_select_response) dedupes by sensor identity,
-- not by tier — a Pal whose sensor already fired through that hook once
-- won't be re-caught by it for this NEW tier; only the immediate attempt
-- here and the proactive periodic scan (find_sensor_component, the
-- historically less reliable path) can retry it after that. Worth
-- watching in real testing, not something to solve blind right now.
-- Two-hundred-and-seventh pass (2026-09-06) — COMPANION PRESET.
--
-- The reasoning, so a later session doesn't mistake this for another blind
-- attempt at the follow problem. Every previous follow mechanism tried to
-- ADD a following behaviour (a move order, an Otomo composite, the Funnel
-- system) and lost to the Pal's own AI, which kept re-deciding and
-- overriding it. Dragón's own observation was the clearest evidence: a
-- FlowerRabbit turned to look at him as the order landed, then resumed its
-- own path one frame later, every 1.5 seconds.
--
-- This takes the opposite approach: instead of out-shouting the wild AI,
-- SILENCE IT. The AI's whole decision vocabulary about the player is one of
-- four values (EPalAIResponseType: Ignore=0, Escape=1, Battle=2,
-- Special=3). Setting every "what do I do about the player" slot to Ignore
-- means the Pal's own AI stops producing any decision about the player at
-- all — so there is nothing left to override the move order Combat.lua
-- issues. This is not a new mechanism: it is the exact private-preset write
-- that already demonstrably works (Dragón confirmed warlike Pals really do
-- attack and escape Pals really do flee), just aimed at a different result.
--
-- Note honestly what this does NOT do: it does not make the Pal follow. It
-- removes the interference. The actual movement still comes from Combat's
-- move order, which is still an approximation, not real Otomo following.
--
-- combatAssist additionally sets the three non-player Discover slots to
-- Battle, so a bonded companion engages other Pals it notices while leaving
-- the player alone. That is the same Warlike behaviour already proven to
-- work, scoped to exclude the player.
-- Two-hundred-and-eighth pass (2026-09-06) — COMBAT BEHAVIOUR CORRECTED
-- from Dragón's live run. He reported three things that look unrelated but
-- share one root cause, and the split between Discover_* and Damaged_*
-- explains all three exactly:
--
--   1. "a petallia changed to combat and started attacking my flopie
--      follower, despite both of them not having fought nor i receiving
--      damage" — a companion with Discover_Equal=Battle attacks ANY
--      similarly-sized Pal it notices, and his other bonding companion is
--      just another wild Pal to it. Companions were fighting each other.
--   2. "combat pals followers start attacking random nearby pals... that
--      caused a few to receive damage themselves and change to escape" —
--      same cause, plus the knock-on: taking damage runs Trust's follower
--      damage penalty, which can drop trust to zero and force the escape
--      tier. The escape was a symptom, not a separate bug.
--   3. "they followed but never attacked, even when i got in combat with
--      a caprity, they didnt fight back even when they received damage" —
--      the apparent contradiction with 1 and 2, and the key to the whole
--      thing. Discover_* governs "I have NOTICED something", Damaged_*
--      governs "something HURT me". Only the Discover slots were being set
--      to Battle; the Damaged slots kept the friendly preset's passive
--      value. So a companion would start fights with strangers it spotted,
--      yet stand there taking hits without retaliating.
--
-- The corrected design, which is also the better one: companions do NOT
-- start fights (Discover_* = Ignore, so they stop attacking each other and
-- stop picking fights that get them killed), but they DO fight back when
-- something actually attacks them (Damaged_* = Battle). That reads as a
-- loyal companion rather than an aggressive one, and it removes the
-- friendly-fire and the death-spiral in one change.
--
-- Honest limitation, unchanged: this makes a companion defend ITSELF, not
-- the player. A companion will join a fight the player starts only once the
-- enemy also turns on the companion. Making them attack the player's own
-- target on sight needs the Hate system (HateSystem:ChangeHate /
-- APalAIController.TargetPlayers), which is real but has never been
-- explored for this purpose — that is the next step if this still feels too
-- passive in play.
local COMPANION_RESPONSE_IGNORE = 0
local COMPANION_RESPONSE_BATTLE = 2

-- Every slot facing the player stays Ignore: a companion must never turn on
-- its own trainer, and this is also what stops the Pal's AI generating the
-- competing decisions that used to override the follow order.
local COMPANION_PLAYER_SLOTS = { "Discover_Player", "Damaged_Player" }

-- Noticing another creature: do nothing. This is the fix for 1 and 2.
local COMPANION_OTHER_DISCOVER_SLOTS = { "Discover_Greater", "Discover_Equal", "Discover_Smaller" }

-- Being hurt by another creature: fight back. This is the fix for 3.
local COMPANION_OTHER_DAMAGED_SLOTS = { "Damaged_Greater", "Damaged_Equal", "Damaged_Smaller" }

-- THE A/B SWITCH for the three-hundred-and-twenty-fifth pass. Dragón asked to
-- test this both ways rather than pick blind: "can we try both? a run with and
-- without?".
--
--   true  -> companions do not retaliate to damage WHILE the player is in a
--            fight (Discover_* = Battle still lets them engage). Out of combat
--            they defend themselves exactly as before.
--   false -> retaliation always on, which is run 28's behaviour.
--
-- Only this one line differs between the two runs, so the comparison is clean.
-- Compare the [FRIENDLY-FIRE] per-fight totals and the [TARGET-DISCIPLINE]
-- cancellation counts, and watch whether a companion still fights back when a
-- real enemy attacks it mid-fight.
local QUIET_RETALIATION_DURING_PLAYER_FIGHT = true

-- Two-hundred-and-fifteenth pass: force a Pal to re-run its sight check, so it
-- notices the player again. This is Dragón's own "they forget im there, making
-- noise brings them back" observation turned into code — see Combat.lua's
-- [RE-SENSE] block. Uses only the sensor call already proven safe here.
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

    -- Start from the friendly preset's real defaults, then override. Using a
    -- real CDO as the base (rather than constructing every field from
    -- scratch) keeps any slot this project doesn't know about at a sane,
    -- game-authored value.
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

        -- Two-hundred-and-thirteenth pass (2026-09-06) — the discover slots are
        -- now CONDITIONAL, which is the fix for "they still didn't defend me".
        --
        -- Dragón's run confirmed the hate push itself works: [HATE-ASSIST]
        -- fired three times, correctly naming the BerryGoat he was fighting.
        -- But the companions still did not join in. That is exactly the
        -- uncertainty flagged when combat assist shipped — hate gives the AI a
        -- TARGET, but the decision to engage still runs through the response
        -- preset, and Discover_* was pinned to Ignore, so "I notice that
        -- BerryGoat" resolved to "do nothing" no matter how much hate it
        -- carried.
        --
        -- Setting Discover_* permanently to Battle is not the answer either —
        -- that is what caused companions to attack each other and pick losing
        -- fights two passes ago. So it is now time-limited: Battle while the
        -- player is actually in a fight, Ignore otherwise. Combat.lua flips
        -- this by re-applying the preset when a player-combat target appears
        -- and again when it goes quiet.
        local discoverResponse = COMPANION_RESPONSE_IGNORE
        if combatAssist and playerInCombat then
            discoverResponse = COMPANION_RESPONSE_BATTLE
        end
        for _, prop in ipairs(COMPANION_OTHER_DISCOVER_SLOTS) do
            fresh[prop] = discoverResponse
        end
        if combatAssist then

            -- ===========================================================
            -- RETALIATION, SCOPED TO WHEN IT IS SAFE
            -- (three-hundred-and-twenty-fifth pass, 2026-09-12)
            -- ===========================================================
            -- Dragón rejected turning retaliation off outright, and he was
            -- right to: "stopping them from attacking something that hits them
            -- is too big of a trade... if im busy doing something else means
            -- they will stand idle until i finally target the enemy, posibly
            -- letting them die without they even able to fight back".
            --
            -- He is describing the OUT-OF-COMBAT case exactly, and the code
            -- agrees with him. Look at the Discover branch above: outside a
            -- player fight every Discover slot is Ignore, so Damaged_* = Battle
            -- is the ONLY thing that lets a companion defend itself out there.
            -- Removing it globally would leave an ambushed Pal defenceless.
            --
            -- But he also set the condition under which he would prefer it:
            -- "if the stop retaliation lets them still fight back when struck
            -- by enemies then that would be the better option". DURING a player
            -- fight that condition is met by a different route -- Discover_* is
            -- Battle for the whole window, so a companion engages anything it
            -- notices, including whatever is hitting it. The damage-triggered
            -- reflex is redundant there, and it is precisely the friendly-fire
            -- amplifier: run 28 logged 53 companion-on-companion hits, entirely
            -- inside the two combat windows, starting one second after both
            -- companions charged the same enemy and began clipping each other.
            --
            -- So retaliation is kept where it is the only defence and dropped
            -- where it only feeds the pile-on:
            --     out of combat -> Damaged_* = Battle  (self-defence, unchanged)
            --     during a fight -> Damaged_* = Ignore  (Discover_* covers it)
            --
            -- STATED PLAINLY AS UNVERIFIED: whether Discover_* = Battle really
            -- does make a companion engage something that attacks it mid-fight
            -- has never been measured. That is exactly what the A/B run pair
            -- below is for, and it is why this is a toggle rather than a
            -- rewrite. If they stop defending themselves during fights, this
            -- goes back to false and target discipline stays the containment.
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
    local setOk, setErr = pcall(function() sensor.AIResponsePreset = fresh end)
    if not setOk then
        Logger.log("[PalBonds/Personality] [COMPANION] AIResponsePreset write FAILED: " .. tostring(setErr))
        return false
    end

    -- ===============================================================
    -- READ IT BACK (three-hundred-and-eighth pass, 2026-09-11)
    -- ===============================================================
    -- Three separate theory-driven fixes in this area have now failed, each
    -- looking correct in code and doing nothing in game. Every log line here
    -- reports what we INTENDED to write -- the "(player slots=Ignore, other
    -- Discover slots=Battle)" text is built from the combatAssist constant, not
    -- from anything actually read back -- so a write that silently does not
    -- stick is indistinguishable from one that works.
    --
    -- Dragón's last run is the case that forces this: the companion preset says
    -- Damaged_* = Battle, which means "fight back when something hurts you", and
    -- his Pals did not fight back when hurt. Either the write is not landing, or
    -- the sensor we write to is not the one the Pal consults, or something
    -- replaces it afterwards. Those are three different bugs and guessing
    -- between them has already cost three runs.
    --
    -- So this reads the eight values back off the sensor immediately, and again
    -- a few seconds later to see whether they survive. Cheap (once per
    -- application), and tagged [PRESET-VERIFY] so Logger's suppression list
    -- cannot eat it.
    -- REMOVED (pass 327): [PRESET-VERIFY]. It read the eight slots back off the
    -- sensor immediately after the write and again 4 seconds later, to find out
    -- whether the write was landing. It answered that -- the write lands and
    -- sticks -- and has been confirming the same thing on every application
    -- since. Run 29 produced 58 of these lines plus 29 extra scheduled
    -- callbacks, each doing eight field reads and a GetFullName path build.
    --
    -- The companion preset is now covered offline by presettest.js, which
    -- asserts all eight slots in both combat states, so the live probe is not
    -- the only thing standing between us and a silent regression.

    -- Was this Pal ALREADY a companion before this call? Read BEFORE the
    -- disposition is overwritten below, because it decides whether the
    -- interrupt at the end of this function is appropriate or destructive.
    local wasAlreadyCompanion = false
    if PersonalityState[palId] and type(PersonalityState[palId].disposition) == "string"
        and PersonalityState[palId].disposition:find("^companion") ~= nil then
        wasAlreadyCompanion = true
    end

    local st = PersonalityState[palId]
    if st then
        st.disposition = (combatAssist and playerInCombat) and "companion_fighting" or (combatAssist and "companion_combat" or "companion")

        -- Two-hundred-and-eighth pass: mark enforcement as done so the
        -- periodic 8s personality scan does not later overwrite this
        -- companion preset with the Pal's originally-rolled tier. Without
        -- this, a Pal that had not yet been enforced (a "normal" roll, or
        -- one whose sensor only resolved later) could silently revert to
        -- warlike/escape behaviour part-way through bonding — which would
        -- look exactly like a random companion turning hostile.
        st.enforcementApplied = true
    end
    Logger.log(string.format(
        "[PalBonds/Personality] [COMPANION] %s now has a companion preset (player slots=Ignore%s) — its own AI should no longer generate decisions about the player",
        tostring(palId), combatAssist and ", other Discover slots=Battle" or ""
    ))

    -- Same interrupt already proven to succeed 5/5 on wild Pals: drop
    -- whatever the Pal decided a moment ago so the new preset is consulted
    -- on its next decision instead of a stale one being held.
    -- ===============================================================
    -- DO NOT INTERRUPT A PAL THAT IS ALREADY A COMPANION
    -- (three-hundred-and-sixth pass, 2026-09-11)
    -- ===============================================================
    -- interrupt_and_resense exists for one job: make a NEWLY CHANGED
    -- disposition take effect at once. A preset is only consulted when the Pal
    -- next senses, so converting a fleeing or hostile Pal to friendly needs a
    -- shove -- cancel what it is doing, reset the "strongest threat I already
    -- reacted to" value, and force a fresh sight check.
    --
    -- Running it on a Pal that is ALREADY a companion is destructive, and it is
    -- what has been breaking combat assist. Combat.lua re-applies this preset on
    -- every combat-window transition (the Discover slots flip Battle/Ignore),
    -- and those windows churn every few seconds, so every companion was having
    -- AllCancelAction_Logic_HardScript_Reaction fired at it again and again --
    -- cancelling the attack it had just started -- followed by a forced
    -- re-discovery of the player.
    --
    -- Dragon described the symptom exactly, without seeing any of this code:
    -- "as soon as combat starts its like the petallia loses track of me and has
    -- to re-discover me all over again, but then when it does it starts
    -- following instead of attacking... almost as if the combat order cleans
    -- their memory to what they were doing or who the player is". That is a
    -- precise description of these three calls.
    --
    -- It also explains the species split, and HIS theory was the right one. The
    -- earlier guess -- that a slower Pal lost a race against the combat window
    -- -- was wrong, and he corrected it with numbers: a Petallia moves at about
    -- 575 against a Ribbuny's 280, nearly double. The real difference is melee
    -- versus ranged. A Ribbuny attacks from where it stands, a short action that
    -- often completes between interrupts. A Petallia has to close the distance
    -- and wind up a melee swing -- a long action, so an interrupt lands inside
    -- it nearly every time.
    --
    -- The preset write above still happens either way. Only the shove is
    -- skipped, and a Pal already fighting for us does not need to be told to
    -- notice the player again.
    -- A brand-new companion gets the full treatment: it may still be fleeing or
    -- attacking under its old disposition, and that has to be cut off.
    --
    -- An EXISTING companion gets the sight-check half only. It still needs the
    -- re-sense, or the Discover = Battle flip this call just wrote would never
    -- be consulted — that was the previous pass's mistake. But its current
    -- action is left alone, so a melee swing survives.
    -- BISECT (three-hundred-and-ninth pass, 2026-09-11): back to run 9's
    -- behaviour -- the full interrupt on every application. In run 9 combat
    -- assist WORKED, for a Petallia and a Flopie both, with this interrupt
    -- firing. Passes 306/307 changed it on a theory about melee wind-ups being
    -- cancelled, and combat has not worked since. Flip to false to re-test that
    -- theory once the baseline is confirmed good again.
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

-- Periodic scan. Hundred-and-twenty-ninth pass SIMPLIFICATION: this used
-- to be two passes (build a presetClassName->live-actor donor lookup,
-- THEN attempt enforcement using it) because the old mechanism needed a
-- live Pal of the right species to borrow a preset reference from. Now
-- that apply_forced_preset resolves each desired preset's own Class
-- Default Object directly (find_preset_cdo — no donor Pal needed at all),
-- enforcement no longer depends on anything else found in this same scan,
-- so it's back to one straightforward pass: initialize state (rolling a
-- tier the first time a Pal is seen) and attempt enforcement immediately,
-- per Pal, independently. Each Pal is wrapped in its own safe_call so one
-- bad actor can't stop the rest of the scan.
local function scan_nearby_wild_pals_for_personality()
    local pals = safe_call(function() return FindAllOf("PalCharacter") end)
    if not pals then return end
    local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
    local playerName = player and safe_call(function() return player:GetFullName() end)
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
            try_enforce_personality(palActor, palId)
        end)
    end
end
local function schedule_personality_scan()
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(PERSONALITY_SCAN_INTERVAL_MS, function()
            safe_call(scan_nearby_wild_pals_for_personality)
            schedule_personality_scan()
        end)
    end)
    if not ok then
        Logger.log("[PalBonds/Personality] [ENFORCE] could not schedule the personality scan — ExecuteInGameThreadWithDelay itself failed, enforcement will never run this session")
    end
end
function Personality.Init()

    -- Ninety-second pass: seed math.random once at mod load so the
    -- personality-tier roll below isn't the same fixed sequence every
    -- single game session (Lua's default seed is otherwise deterministic).
    -- Wrapped in pcall purely out of this project's usual caution — os.time
    -- is expected to be available in this UE4SS Lua environment, but a
    -- missing/sandboxed os library should degrade to "still random within
    -- a session, just the same sequence across sessions," not a crash.
    pcall(function() math.randomseed(os.time()) end)
    Logger.log("[PalBonds/Personality] real read-only helpers active (GetStableId, GetSpeciesDefaultDisposition) — no per-tick hooks, on-demand only, see file header")
    if ENABLE_PERSONALITY_TIER_ROLL and FORCE_ALL_CURIOUS then
        Logger.log("[PalBonds/Personality] [PERSONALITY-ROLL] FORCE_ALL_CURIOUS active — every wild Pal gets tier=friendly, weighted roll bypassed (hundred-and-forty-sixth pass, Dragón's request)")
    elseif ENABLE_PERSONALITY_TIER_ROLL then
        Logger.log("[PalBonds/Personality] [PERSONALITY-ROLL] weighted personality-tier assignment active (35% normal / 30% friendly / 10% escape / 10% notinterested / 5% warlike / 5% warlike_anyway / 5% warlike_without_player)")
    else
        Logger.log("[PalBonds/Personality] [PERSONALITY-ROLL] tier roll DISABLED (hundred-and-twenty-eighth pass, temporary) — every Pal's tracked disposition is its real species default, no override")
    end

    -- Ninety-third pass: start the recurring enforcement scan (see
    -- schedule_personality_scan above) so tiers start affecting real
    -- behavior as soon as a wild Pal is nearby, not only at pet/feed time.
    -- Hundred-and-forty-seventh pass: confirmed live (no longer
    -- "untested") — real testing shows this scan runs and finds Pals, but
    -- every attempt currently fails on the still-open sensor-component bug
    -- (item 4 on the saved priority list). GLOBAL-CURIOUS below doesn't
    -- depend on this scan at all, so it isn't blocked by that bug.
    schedule_personality_scan()
    Logger.log("[PalBonds/Personality] [ENFORCE] recurring personality-enforcement scan scheduled, every " .. tostring(PERSONALITY_SCAN_INTERVAL_MS) .. "ms — proactive fallback path, still blocked by the sensor-component bug on its own")

    -- Hundred-and-forty-eighth pass (2026-09-04): the REAL per-individual
    -- fix — arm the reactive SelectResponseBySenses hook (see its own
    -- comment above) so enforcement no longer depends on the broken
    -- proactive scan at all. This is what actually lets per-individual
    -- variety (the weighted tier roll) work in real gameplay, not just
    -- get rolled and stored.
    register_sensor_sense_hook(1)

    -- Hundred-and-forty-seventh pass (2026-09-04): the real fix for
    -- "wild Pals should just be calm, I shouldn't have to chase them" —
    -- see apply_global_curious_preset_override's own comment above for
    -- the full reasoning (copied from the Passive Pals reference mod's
    -- actual default mechanism, not the per-individual one this project
    -- had been trying). Runs independently of FORCE_ALL_CURIOUS/the
    -- ENFORCE scan — a global, one-time (per session) shared-preset
    -- rewrite, not per-Pal.
    if FORCE_ALL_CURIOUS then
        Logger.log("[PalBonds/Personality] [GLOBAL-CURIOUS] starting global preset override (rewrites shared AIResponsePreset objects directly — affects every wild Pal using them, no per-individual lookup)")
        safe_call(function() apply_global_curious_preset_override(1) end)
    end
end
return Personality
