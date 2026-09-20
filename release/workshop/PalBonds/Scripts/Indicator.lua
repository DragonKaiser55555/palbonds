local Logger = require("Logger")
local Locale = require("Locale")
local Trust = require("Trust") 
local UEHelpers = require("UEHelpers") 
local Personality = require("Personality") 
local Indicator = {}

-- An object's address, read while it is alive (see Indicator.ForgetJoinedPal).
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

-- ===================================================================
-- WORLD-CLOSING GATE (three-hundred-and-twenty-ninth pass, 2026-09-17)
-- ===================================================================
-- Dragon's third crash log caught this file's hook still WORKING after the
-- world had started closing: the last line written before the crash was a
-- personality read that came back "PalAIResponsePreset" -- the engine's raw
-- base name, which is what reading a half-destroyed object looks like.
--
-- Letting go of our references at the confirm (pass 328) was necessary but not
-- sufficient, because the game keeps calling the functions we hooked while it
-- tears the world down, and UE4SS in this build cannot unregister a hook. So
-- every hook callback in this file asks this first and returns immediately
-- while a quit is in progress: the mod goes deliberately blind from the moment
-- the player confirms until the next world's character exists.
--
-- Cost: one function call per hook invocation, no scan, no reflection -- and it
-- is a plain boolean read the rest of the session.
local playerRefForGate = nil
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

-- The 2-second nameplate/boss-bar tick (scheduleScan).
local SCAN_INTERVAL_MS = 2000

-- Fifty-ninth pass: DIAG-HANDLE confirmed the raw `bindedHandle`
-- property value (`handle:type()` = "TSoftObjectPtrUserdata") does not
-- support ANY of the accessors tried (GetFullName/LoadSynchronous/Get/
-- TryGetIndividualActor all FAILED, AssetPathName read nil) — a genuine
-- UE4SS Lua binding gap for this exact wrapped type, the same kind of
-- limitation already documented for MapProperty/DoubleProperty, not a
-- mistake in how it was called. Reading the STORED field after the fact
-- is a dead end with this build.
--
-- Real fix: `BindFromHandle(class UPalIndividualCharacterHandle*
-- targetHandle)` (confirmed real in the header dump, inherited from
-- `WBP_IndividualParameterBindWidget_C`) takes the handle as a plain HARD
-- pointer PARAMETER — a completely different, and much friendlier, shape
-- than the soft-pointer FIELD it presumably gets stored into afterward.
-- This project has always safely read hook arguments this way elsewhere
-- (Trust.lua/Interaction.lua's actor/param reads off hook params) — so
-- hooking this function directly and capturing `targetHandle` at the
-- moment of binding sidesteps the broken soft-pointer read entirely.
--
-- Registered ONCE (globally, keyed off whichever gauge widget's OWN class
-- path we happen to inspect first — `gaugeWidget:GetClass():GetPathName()`
-- gives the exact `/Game/...` Blueprint asset path this specific widget
-- class lives at, so the hook fires only for OUR gauge class, not every
-- individual-parameter-bound widget game-wide). Once registered, it
-- fires for every future BindFromHandle call on any WBP_PalNPCHPGauge_C
-- instance — including ones created after this point, which covers new
-- Pals encountered later in a session. Gauges that were already bound
-- BEFORE this hook was registered (the very first few found each
-- session) won't have a captured handle until their own widget gets
-- destroyed and recreated (which happens naturally as Pals leave/re-enter
-- view) — an acceptable gap, not worth a more invasive fix yet.
local hasRegisteredBindHook = false

-- ===========================================================================
-- NAMEPLATES FROM THE HOOK, NOT FROM A WORLD SWEEP (2026-09-15, profiling)
-- ===========================================================================
-- Tags and trust bars used to be created only by scan_for_gauge_widgets, which
-- ran FindAllOf("WBP_PalNPCHPGauge_C") every 2 seconds for the whole session:
-- ~29 object-array walks a minute at 40-100ms each, the single most frequent
-- stall the mod caused. The BindFromHandle hook already fires for every
-- nameplate that attaches to a Pal, so it now puts that nameplate here, and the
-- 2-second tick runs install_trust_bar on just these. A nameplate stays pending
-- until its tag is installed (its Pal may not resolve on the first try), and is
-- dropped when it becomes invalid or its Unbind fires.
--
-- The world sweep is kept for what the hook cannot see:
--   * every tick until the hook is registered (the class only becomes hookable
--     once the player is in-world), exactly as before;
--   * NAMEPLATE_SWEEPS_AFTER_HOOK more ticks after it registers, for nameplates
--     that attached before the hook existed;
--   * then one sweep every NAMEPLATE_SAFETY_SWEEP_EVERY_N_SCANS ticks (~30s) as
--     a safety net, so a nameplate the hook somehow missed still gets its tag,
--     just later instead of never.
local pendingGauges = {}
local NAMEPLATE_SWEEPS_AFTER_HOOK = 5
local NAMEPLATE_SAFETY_SWEEP_EVERY_N_SCANS = 15
local nameplateSweepsSinceHook = 0
local gaugeHandleByKey = {}

-- (2026-09-16: the scan-triggered fallback registration, register_bind_hook_once,
-- was removed with the diagnostic panel scan that was its only caller. The
-- retrying registration below is the one route; it keeps trying until it works.)
-- Hundred-and-fifty-fifth pass (2026-09-04): REAL FIX for a genuine race
-- Dragón caught directly — a wild Pal's gauge (a samurai dog he could
-- see and even pet, for the whole session) never got a real actor
-- resolved for its trust bar/personality label, staying on the "?"
-- placeholder the entire time. Traced it to `register_bind_hook_once`
-- below only ever being CALLED from gauge-DISCOVERY code (this file's
-- periodic canvas scan, `scheduleScan`/`check_panel_children`) — meaning
-- the class-level BindFromHandle hook (which, once registered, catches
-- EVERY future call across ALL gauge instances, not just one) doesn't
-- actually get registered until the FIRST gauge is ever discovered by
-- that scan. Any gauge already on-screen and already bound before that
-- exact moment — very plausibly a Pal already visible right as the
-- session starts — permanently misses capture, with zero further chance
-- to ever resolve (BindFromHandle only fires once per bind, and this
-- project has no mechanism to re-trigger it).
--
-- The fix doesn't need to wait for a live gauge at all: the FIRST
-- candidate path below is already a hardcoded, PROVEN-real literal
-- string (confirmed via a real bundled reference mod, see the big
-- comment on register_bind_hook_once) — it needs no gauge instance to
-- compute. Registering just that one candidate here, unconditionally, at
-- Indicator.Init() time (called before this file's own scan ever runs),
-- closes almost the entire race window. register_bind_hook_once's
-- gauge-dependent fallback candidates stay in place below as a safety
-- net for a future game build where this literal path might change —
-- `hasRegisteredBindHook` being already true after a successful call
-- here makes that later call a clean no-op, not a duplicate registration.
-- Hundred-and-fifty-seventh pass (2026-09-04) FIX, REAL REGRESSION FOUND:
-- Dragón's very next test showed this one-shot attempt FAILING outright
-- at Init() — "no UFunction with the specified name was found" — because
-- moving registration this early meant the target Blueprint class itself
-- isn't loaded into memory yet at that exact moment (the same "class not
-- loaded yet" problem this project has hit and fixed with a bounded
-- retry loop many times before — Radial Menu, Worker Menu, Indicator
-- classes, EMOTE-WATCH). With no retry, this silently fell back to
-- exactly the same race register_bind_hook_once already had — the
-- previous pass's fix accomplished nothing in that specific test.
-- Applying the same already-proven fix here instead of a single attempt:
-- a short, bounded retry (1s cadence, well before most gauges are likely
-- to bind, unlike register_bind_hook_once's path which only ever gets
-- its first chance once a gauge is actually discovered by the scan).
-- Fast rounds are for the rare case where the class IS already loaded; after
-- that it drops to the slow cadence and keeps going until it succeeds, because
-- the class normally only becomes hookable once the player is in-world (see
-- register_bind_hook_immediate's "NO GIVING UP" comment).
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
            local self = hook_get(Context)
            local handle = hook_get(TargetHandle)
            if self == nil or handle == nil then return end
            local key = describe_widget(self)
            gaugeHandleByKey[key] = handle
            pendingGauges[key] = self
        end)
    end)
    if hookOk then
        Logger.log(string.format("[PalBonds/Indicator] [TAGS] bind hook INSTALLED (immediate, round %d) — personality tags and trust bars can now resolve their Pal: %s", round, hookPath))
        hasRegisteredBindHook = true
        local unbindPath = hookPath:gsub(":BindFromHandle$", ":Unbind")
        local unbindOk, unbindErr = pcall(function()
            RegisterHook(unbindPath, function(Context)
                if world_is_closing() then return end
                local self = hook_get(Context)
                if self == nil then return end
                local key = describe_widget(self)
                gaugeHandleByKey[key] = nil
                pendingGauges[key] = nil
            end)
        end)
        Logger.log("[PalBonds/Indicator] [TAGS] (immediate) RegisterHook(" .. unbindPath .. ") = " .. (unbindOk and "OK" or ("FAILED (non-fatal, BindFromHandle hook still stands): " .. tostring(unbindErr))))
        return
    end
    local errFirstLine = tostring(hookErr):match("^[^\n]*") or tostring(hookErr)

    -- ===============================================================
    -- NO GIVING UP (two-hundred-and-ninety-seventh pass, 2026-09-11)
    -- ===============================================================
    -- This used to stop dead after IMMEDIATE_BIND_HOOK_MAX_ROUNDS (30 rounds
    -- at 1s = a 30-second window opening at MOD LOAD) and hand over to the
    -- scan-triggered fallback, which had a budget of five attempts for the
    -- whole session. That is the cause of the intermittent "no personality
    -- tags" Dragón has been hitting and could never pin down.
    --
    -- Why the 30-second window was always wasted: the mod loads while the game
    -- is still on the title screen, and WBP_PalNPCHPGauge_C cannot be hooked
    -- until that Blueprint class is actually loaded, which does not happen
    -- until the player is in-world with a Pal on screen. His 2026-09-11 run
    -- shows it exactly — mod loaded 19:25:44, so this window expired around
    -- 19:26:14, and the first evidence of being in-world is 19:26:58, three
    -- quarters of a minute after the last attempt.
    --
    -- So in practice every session depended on those five fallback attempts
    -- landing in the narrow moment the class became registerable. When they
    -- missed, tags were gone until the game was restarted, because nothing
    -- ever tried again. Tags have no other route: the hook is what fills
    -- gaugeHandleByKey, and resolve_pal_actor_from_gauge's only other path is
    -- the bindedHandle field, recorded in the fifty-ninth pass as a dead end
    -- in this UE4SS build.
    --
    -- Now it simply keeps trying, slowing to SLOW_RETRY_MS once the fast
    -- rounds are used up, and stops permanently the moment it succeeds. The
    -- cost of a round is one pcall'd RegisterHook — no world scan, no
    -- reflection — which is why an open-ended retry is affordable here and was
    -- not for the cage-VFX probe that had to be removed.
    local isFast = round < IMMEDIATE_BIND_HOOK_MAX_ROUNDS
    local delay = isFast and IMMEDIATE_BIND_HOOK_RETRY_MS or IMMEDIATE_BIND_HOOK_SLOW_RETRY_MS

    -- Log the first failure, the handover to slow retries, and then only
    -- occasionally: this runs until it succeeds, so it must not grow the log
    -- without bound.
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

-- Fifty-fifth pass (2026-09-03): the fifty-fourth pass's test came back
-- with every single logged step OK, and Dragón confirmed a real magenta
-- bar rendered on the one Chikipi tested — runtime widget creation is
-- CONFIRMED working in this build. Two real gaps in that first version,
-- exactly matching what Dragón observed:
--   1. It only ever ran once per session (a single global one-shot flag),
--      so only the very first gauge widget the scan ever saw got a bar —
--      Dragón correctly guessed this was the nearest wild Pal at spawn.
--      Fixed here: gating is now keyed per-gauge (by its own GetFullName,
--      which is unique to that specific live instance) via a small table,
--      so every distinct gauge widget gets its own bar exactly once,
--      instead of the whole feature running only once ever. Also moved
--      the call site out of inspect_gauge_widget (which stays its own,
--      separate one-shot deep-dump, to keep log volume down) and into
--      check_panel_children's own per-child loop, unconditionally, so it
--      runs for every gauge child seen, not just whichever one happened
--      to trigger the diagnostic dump.
--   2. Position (0,25) and size (80,6) were blind, arbitrary guesses
--      relative to Canvas_Innner's own coordinate space, made without
--      ever reading anything real to compare against — which is exactly
--      why Dragón saw it "not rightly aligned". Fixed here: read the
--      REAL HP bar's own slot (`WBP_EnemyGauge.ProgressBar_HP.Slot`,
--      inherited from UWidget, a UCanvasPanelSlot since ProgressBar_HP
--      lives in this same kind of canvas) via its own
--      GetPosition()/GetSize(), and place the new bar directly under it
--      (same X/width, Y offset by the real bar's own height + a small
--      gap) instead of a guessed absolute position. Falls back to the
--      old blind guess, clearly logged as a fallback, if any of that
--      read fails.
--
-- Still NOT wired to real FriendshipPoint yet — SetPercent(0.5) and the
-- magenta test color are both still static placeholders, deliberately
-- kept obvious/fake-looking rather than switched to a "real-looking"
-- color, so it stays visually clear this isn't live data yet. Dragón's
-- own observation that "it never moved, stayed at the same half-full
-- look" through the whole capture is the expected, correct behavior of
-- this version — nothing in this pass or the last one calls SetPercent
-- more than once. Wiring a live value needs the still-unresolved
-- gauge-to-Pal matching problem solved first (SyncId's GUIDs still read
-- all-zero; Dragón's own suggested `bindedHandle` lead is still unread) —
-- that's the next real blocker, not this pass's job.
--
-- FIFTY-FIFTH PASS RESULT (2026-09-03): every gauge got its own bar this
-- time (one DIAG-CREATE sequence per Pal in the log, all succeeding), so
-- the per-gauge fix worked. But the screenshot Dragon sent still showed
-- the bar shifted right and visibly WIDER than the real HP bar, not just
-- off vertically. See the FIFTY-SIXTH PASS comment inside
-- install_trust_bar below for the real cause and fix.
local barInstalledForGauge = {} 
local trackedBars = {} 
local function resolve_pal_actor_from_gauge(gaugeWidget)

    -- Fifty-ninth pass: try the hook-captured HARD handle first — see
    -- register_bind_hook_once's comment for why this is the real fix,
    -- now that DIAG-HANDLE confirmed the stored soft-pointer FIELD is a
    -- dead end in this UE4SS Lua build.
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

    -- Fall back to the stored bindedHandle field, kept only as a
    -- diagnostic path — DIAG-HANDLE showed this route consistently fails
    -- in this build (the raw value has no working IsValid/GetFullName/
    -- LoadSynchronous/Get/TryGetIndividualActor/AssetPathName), so this
    -- almost never succeeds, but costs nothing to still try.
    local handleOk, handle = pcall(function() return gaugeWidget.bindedHandle end)
    if not (handleOk and handle ~= nil) then
        return nil, "no hooked handle yet, and bindedHandle unreadable: " .. tostring(handle)
    end

    -- Two-hundred-and-seventy-fourth pass (2026-09-08) — REMOVED, and it is the
    -- best crash suspect this project has had.
    --
    -- Dragon's crash log ends on this probe's own output: five DIAG-HANDLE lines
    -- reporting GetFullName FAILED, LoadSynchronous FAILED, Get FAILED,
    -- TryGetIndividualActor FAILED, AssetPathName nil -- and then the process
    -- died with an access violation. It ran, everything it tried failed, and the
    -- game fell over immediately after.
    --
    -- Its question was ANSWERED in the fifty-ninth pass, in this file's own
    -- words: the raw bindedHandle is a TSoftObjectPtrUserdata that "does not
    -- support ANY of the accessors tried ... a genuine UE4SS Lua binding gap".
    -- It has kept running once per session ever since, calling four accessors on
    -- an object it already knows it cannot touch, to re-learn a fact written
    -- down long ago.
    --
    -- pcall is no defence here, for the third time in this project: it catches
    -- Lua errors, not a native access violation inside the engine call. An
    -- unsupported binding poking at a wrapped pointer is exactly how you read
    -- from a bad address.
    --
    -- Not proven -- correlation and a plausible mechanism, not a confession. But
    -- it costs nothing to remove: no code reads its output, and the answer it
    -- produces is already in the comments above. The function stays defined and
    -- unbound, the same convention used for the other retired probes here.
    -- inspect_bindedHandle_shape(handle)

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

-- The bar's fill comes from PalBonds' own trust points (Trust.GetBarRatio,
-- 2026-09-18). It used to read the game's FriendshipPoint through the Pal's
-- CharacterParameterComponent, three reflection calls per bar per refresh; it is
-- now one name lookup and a table read. A Pal with no bonding record reads 0
-- without any level lookup, as before.
local function get_friendship_ratio(actor)
    local ok, ratio = pcall(function() return Trust.GetBarRatio(actor) end)
    if not ok or type(ratio) ~= "number" then
        return nil, "Trust.GetBarRatio failed: " .. tostring(ratio)
    end
    return ratio, nil
end

-- Sixty-sixth pass (2026-09-03): Dragón asked to stylize the trust bar,
-- specifically a color gradient from white-pinkish (empty) to red (full)
-- as trust rises — replacing both the magenta creation-time placeholder
-- and the never-updated fill color. `UProgressBar:SetFillColorAndOpacity`
-- is a real, already-used call (the magenta placeholder itself proves it
-- works); this just computes a real color instead of a fixed one. Kept as
-- a plain linear interpolation per channel (R/G/B), no extra libraries
-- needed. Real visual-styling options exposed to Lua turned out to be
-- narrow — `UProgressBar`'s own header dump (CXXHeaderDump/UMG.hpp) only
-- ===================================================================
-- PLAYER-FACING PERSONALITY NAMES (two-hundred-and-thirty-sixth pass, 2026-09-07)
-- ===================================================================
-- Until now the label printed this project's INTERNAL tier strings —
-- "notinterested", "warlike_anyway", "companion_combat". Fine for development,
-- unshippable. Dragón asked for player-friendly names and chose them himself;
-- these are his, with one substitution of mine he accepted (Feral).
--
-- The rolled personalities:
--   normal          -> Normal    (behaviour comes from the species, untouched)
--   friendly        -> Curious   (stops and looks at the player as he approaches)
--   escape          -> Timid     (runs away on approach)
--   notinterested   -> Aloof     (ignores the player; deliberately distinct from Normal)
--   warlike         -> Grumpy    (postures, rarely starts a fight)
--   warlike_anyway  -> Hostile   (always attacks the player)
--   kill_all        -> Feral     (attacks anything on sight)
--
-- Grumpy and Hostile stay SEPARATE, on Dragón's explicit call and for a reason
-- worth recording so nobody merges them later as a tidy-up: "while grumpy
-- doesnt attack inmediately, it can attack if it sees another pal of its same
-- species attacking, so kind of like they join - its an interesting
-- personality". It is a joiner, not a weaker hostile.
--
-- THE BONDING STATES OVERRIDE THE PERSONALITY, and are keyed off the bar
-- directly rather than off the disposition string. That is deliberate: a Pal
-- won over by bonding and a Pal that merely ROLLED the friendly tier both end up
-- with disposition == "friendly", so the string alone cannot tell them apart and
-- would show two different meanings under one name. The ratio can, exactly, and
-- the thresholds are the same ones the systems themselves use.
--
--   >= 20% of the bar -> "Friendly"   (the friendly-trigger fraction)
--   >= 50% of the bar -> "Bonding"    (the follow trigger)
--
-- No name for 100%, per Dragón: by then the Pal is already being captured.
local USE_PLAYER_FACING_PERSONALITY_NAMES = true
-- 2026-09-18: translation keys (Locale.lua), not the words themselves; the
-- tag is shown in the game's language. English: Normal, Curious, Timid,
-- Aloof, Grumpy, Hostile, Feral, Bonding.
local PERSONALITY_DISPLAY_NAMES = {
    normal = "tag_normal",
    unknown = "tag_normal",
    friendly = "tag_curious",
    escape = "tag_timid",
    notinterested = "tag_aloof",
    warlike = "tag_grumpy",
    warlike_anyway = "tag_hostile",
    kill_all = "tag_feral",

    -- Reached only if the ratio lookup fails; the thresholds below normally
    -- catch this state first.
    companion_combat = "tag_bonding",
}
local BOND_LABEL_FRIENDLY_RATIO = 0.2
local BOND_LABEL_BONDING_RATIO = 0.5

-- ===================================================================
-- LABEL STYLING (two-hundred-and-thirty-seventh pass, 2026-09-07)
-- ===================================================================
-- Dragón's direction, after seeing it in game for the first time: "keep it
-- white, capitalize it, smaller and dimmer, but not next to the name, below the
-- friendship bar, more close and aligned to it, not with so much space around".
-- Explicitly NO colour coding — he considered it and said no.
--
-- The screenshot showed why it read as part of the Pal's NAME rather than as a
-- status: the text renders at the widget's default size, which is far larger
-- than the 14px slot it sits in, so it overflowed its box and floated well below
-- the bars with a lot of air around it.
--
-- Layout of the nameplate stack, so the numbers below are readable rather than
-- magic. refY/refH are the HP bar's own slot position and height:
--     HP bar      Y = refY                    height refH
--     trust bar   Y = refY + refH + 2         height 6      (ends at +refH+8)
--     label       Y = refY + refH + 9         height 12     (was +12, height 14)
-- One pixel under the trust bar instead of four, and the same X and width as the
-- bars so it lines up with them rather than with the name above.
--
-- Size and dimming are done with RenderScale and RenderOpacity rather than by
-- setting a font: FSlateFontInfo is a struct this project has no confirmed-safe
-- way to build from Lua, while these two are plain UWidget setters. Both are
-- pcall-guarded and the result is logged once, so if either turns out not to
-- exist on this build it shows up as a log line instead of an invisible no-op.
-- Measured from the DIAG-GEOM dump rather than estimated, using the real slot
-- numbers this build reports:
--     ProgressBar_HP   pos=(64, 26)  size=(120, 4)   -> bottom edge at 30
--     trust bar        pos=(64, 32)  size=(120, 6)   -> bottom edge at 38
--     personality      pos=(64, 39)  size=(120, 18)
-- So the SLOT was already sitting one pixel under the trust bar and the gap
-- Dragón is seeing is not slot spacing at all — it is the copied name font being
-- taller than the 18px box, so the glyphs render low inside it. Pulling the slot
-- up by 3 closes the visible gap without moving the box into the bar: at 36 the
-- slot top still sits below the HP bar and only overlaps the trust bar's last
-- two pixels, which the text does not occupy anyway.
local LABEL_GAP_BELOW_BAR = 6
local LABEL_HEIGHT = 18   

-- Two-hundred-and-thirty-eighth pass (2026-09-07). The previous attempt shrank
-- and faded the label with RenderScale/RenderOpacity, and Dragón's screenshot
-- shows why that was the wrong tool: "still looks off ... the text looks too
-- dim now, i asume you lowered the font-weight, raise it a bit or again, copy it
-- from the name lol". He is right about the cause even if not the mechanism —
-- RenderOpacity fades the whole widget, which reads as thin, washed-out text
-- rather than as smaller text, and RenderScale resamples the glyphs instead of
-- rendering them at a smaller size, which is what made it look soft.
--
-- His instruction is the better one and it is now what this does: COPY THE STYLE
-- FROM THE PAL'S OWN NAME. WBP_EnemyGauge_C exposes Text_Name (a
-- UBP_PalTextBlock_C — the exact same class our label already is, since the
-- label class is taken from Text_WorkName:GetClass()), so its Font,
-- ColorAndOpacity and shadow can be handed straight across as same-typed values.
-- No struct is built and no struct is mutated: the font is read from one widget
-- and passed to the other's SetFont, which is the safest possible form of this.
-- Deliberately NOT modifying the copied FSlateFontInfo's Size field — that
-- struct may well be a live reference to the name widget's own font, and
-- shrinking it could shrink the Pal's actual NAME.
--
-- RenderScale and RenderOpacity are explicitly reset to 1, both because the font
-- now carries the appearance and because leaving them would compound with it.
--
-- ALIGNMENT. Dragón also reported "it looks like if the name had an extra
-- padding or something that is not letting it align correctly with the
-- friendship bar". Rather than guess at an offset a third time, this dumps the
-- real slot geometry of Text_Name, ProgressBar_HP and our own label once per
-- session, so the next adjustment is made from measured numbers instead of from
-- looking at a screenshot.
local loggedLabelStyleOnce = false
local loggedLabelGeometryOnce = false
-- `sourceText` (optional, 2026-09-16): the text widget to copy the style from.
-- Nameplates leave it nil and copy their own Text_Name; the boss bar passes one
-- of its own text widgets, since it has no WBP_EnemyGauge.
local function style_personality_label(labelObj, gaugeWidget, sourceText)
    if labelObj == nil then return end

    -- Always neutralise the previous pass's render tricks, even if the font copy
    -- below fails — otherwise a failed copy would leave the label dim AND
    -- unstyled, which is worse than either.
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

        -- The name reads crisply against any background because it carries a
        -- shadow/outline. Without copying this the label would be the right size
        -- and weight but still hard to read over bright terrain.
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

-- One-shot, read-only. Prints where the name, the HP bar and our label actually
-- sit, so the alignment complaint can be answered with numbers.
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
        Logger.log("[PalBonds/Indicator] [DIAG-GEOM] Text_Name      " .. slotOf(eg.Text_Name))
        Logger.log("[PalBonds/Indicator] [DIAG-GEOM] ProgressBar_HP " .. slotOf(eg.ProgressBar_HP))
    end)
    if labelObj ~= nil then
        Logger.log("[PalBonds/Indicator] [DIAG-GEOM] personality    " .. slotOf(labelObj))
    end
end

-- Two-hundred-and-fortieth pass (2026-09-07): player-facing on/off switch for
-- the personality tags, bound to F9. Dragón's reasoning: the tags are a visible
-- change to every nameplate in the game and some players will not want them.
--
-- Implemented as an empty-string write rather than by destroying and rebuilding
-- the label widgets. Rebuilding is how this file caused a real crash before (the
-- Control-reuse bug), and an empty string is indistinguishable from no tag on
-- screen while leaving every widget in a known-good state. Flipping it back is
-- immediate because update_trust_bars rewrites the text on its next pass.
--
-- labelLastText is cleared on every Pal at toggle time so the "only write when
-- the text CHANGES" optimisation does not skip the very write that applies the
-- toggle.
--
-- Three-hundred-and-thirty-fourth pass (2026-09-20), niconoko on Nexus: "me
-- prefer the personality info to be hidden and not want to press toggle
-- everytime me log into the game". So where the tags START is now the player's
-- to decide in the settings file; the key still toggles them from there.
local personalityLabelsVisible = (require("Settings").Get("ShowPersonalityTags") ~= 0)
function Indicator.TogglePersonalityLabels()
    personalityLabelsVisible = not personalityLabelsVisible
    for _, entry in pairs(trackedBars) do
        if type(entry) == "table" then entry.labelLastText = nil end
    end
    Logger.log("[PalBonds/Indicator] [TAG-TOGGLE] personality tags are now " ..
        (personalityLabelsVisible and "VISIBLE" or "HIDDEN") ..
        " (" .. tostring(require("Settings").Get("KeyTags")) .. "; session-only, back to ShowPersonalityTags on the next launch)")

    -- Two-hundred-and-eighty-seventh pass: returned so the key handler can put
    -- the new state on screen. Both toggles are invisible otherwise -- with the
    -- tags hidden there is nothing left to look at, so without a toast the only
    -- feedback that F9 did anything is the thing it just removed.
    return personalityLabelsVisible
end

-- Two-hundred-and-forty-sixth pass (2026-09-07) — Dragón: "the label of the
-- pals both betrayed and abbandoned change to timid (which was the old escape)
-- that feels kind of weird considering what they just went through".
--
-- He is right, and it is misleading rather than merely odd. Losing all trust
-- forces the Pal's tier to "escape" so it genuinely flees, and "escape" displays
-- as Timid — the tag for a Pal that is naturally shy. A player reading it would
-- think they had found a skittish Chikipi, when what they are actually looking
-- at is a Pal that will never trust them again. The one state in this mod that
-- is permanent and irreversible was being shown under a word that suggests
-- nothing of the kind.
--
-- "Wary" is short enough to sit in the same tag space as the others and says
-- what it means: this one remembers.
-- Dragón's words, and his reasoning is the right one for a mod built on
-- earning trust: "wary sounds too soft from having been just betrayed, i would
-- put scarred for betrayed pals so players actually feel bad for what they did,
-- and abandoned or something for pals that got left behind".
--
-- The two causes are genuinely different things the player did, so they get
-- different words. Betrayal was an act; abandonment was a neglect.
local BROKEN_BOND_LABELS = {
    betrayed = "tag_scarred",
    abandoned = "tag_abandoned",
}

-- Used only if a bond ended without its cause being recorded — older saves, or
-- any future path that forgets to pass a reason. Deliberately not one of the two
-- real words: a Pal should never be labelled "Scarred" unless the player
-- actually hurt it.
local BROKEN_BOND_FALLBACK = "tag_wary"
local function personality_display_text(actor, disposition, palId)
    -- Picks the feminine word for a female Pal where the language has one.
    local g = { female = palId ~= nil and Personality.IsFemale and Personality.IsFemale(palId) or false }
    if not personalityLabelsVisible then return "" end

    -- 2026-09-14, Dragón's instruction: "owned pals should not show tags at
    -- all, they're already part of the player's roster so they dont need any
    -- tag." Checked before EVERYTHING else below, including the broken-bond
    -- label — an owned Pal (active Otomo or base worker) gets no tag under
    -- any circumstance. This is the display half of the same-day fix that
    -- stopped owned Pals being randomly rolled a personality at all; that
    -- one made the tag read "Normal" instead of a random word, and this one
    -- removes it entirely.
    local okCap, CaptureMod = pcall(require, "Capture")
    if okCap and CaptureMod and CaptureMod.IsAlreadyOwned then
        if safe_call(function() return CaptureMod.IsAlreadyOwned(actor) end) then
            return ""
        end
    end

    -- Checked before anything else, including the bonding thresholds. A
    -- permanently fled Pal has had its friendship reset to zero, so the ratio
    -- tests below would fall through to its personality tag and hide the one
    -- fact that actually matters about it.
    if okCap and CaptureMod and CaptureMod.HasPermanentlyFled then
        if safe_call(function() return CaptureMod.HasPermanentlyFled(actor) end) then
            local why = CaptureMod.GetFledReason and safe_call(function() return CaptureMod.GetFledReason(actor) end)
            return Locale.T(BROKEN_BOND_LABELS[why] or BROKEN_BOND_FALLBACK, g)
        end
    end
    if not USE_PLAYER_FACING_PERSONALITY_NAMES then
        return disposition or "?"
    end

    -- Bonding progress wins over the rolled personality: once a Pal is being
    -- won over, what it started as stops being the useful thing to show.
    local ratio = get_friendship_ratio(actor)
    if ratio ~= nil then
        if ratio >= BOND_LABEL_BONDING_RATIO then return Locale.T("tag_bonding", g) end
        if ratio >= BOND_LABEL_FRIENDLY_RATIO then return Locale.T("tag_friendly", g) end
    end
    if disposition == nil then return "?" end

    -- An unmapped disposition falls back to the raw string rather than to a
    -- wrong name: if a tier is ever added and this table is not updated, it
    -- should look obviously unfinished instead of silently mislabelling a Pal.
    local nameKey = PERSONALITY_DISPLAY_NAMES[disposition]
    if nameKey == nil then return disposition end
    return Locale.T(nameKey, g)
end

-- exposes `SetPercent`, `SetIsMarquee`, and `SetFillColorAndOpacity` as
-- callable functions; the brush/border imagery live inside `WidgetStyle`
-- (an `FProgressBarStyle` struct holding `FSlateBrush` images), which
-- isn't something safe to construct from scratch via Lua — so the color
-- gradient is the real, deliverable piece of "more design" available
-- here without risking a broken/invisible bar.
-- Sixty-ninth pass (2026-09-03): Dragón tested the white-pink -> red
-- gradient live and it "didn't convince at all" — not readable/distinct
-- enough in practice. First follow-up: a bronze->gold gradient instead.
--
-- Seventy-second pass (2026-09-03): Dragón liked the gold better but
-- asked to drop the gradient entirely — one flat, solid gold color,
-- regardless of ratio. `ratio` is kept as a parameter (harmless, ignored)
-- rather than changing every call site, since the fill LENGTH already
-- shows progress via SetPercent; the color no longer needs to.
local function compute_trust_bar_color(ratio)
    return { R = 1.00, G = 0.84, B = 0.00, A = 1 }
end

-- Hundred-and-eightieth pass (2026-09-05): Dragón asked to try the
-- technique found while reading the "Pal Analyzer" reference mod's
-- extracted Blueprint strings — it keeps its own Pal-actor-keyed map
-- (Map_Add/Map_Find/Map_Keys/Map_Values, confirmed in its strings) and
-- reuses one widget per Pal, rather than rebuilding whenever the
-- underlying gauge changes. A real log breakdown (previous pass) showed
-- 315 full StaticConstructObject+AddChildToCanvas builds in a 3-minute
-- busy-base session — far more than the number of actually-distinct
-- Pals near a base, confirming the game's own gauge-widget pool
-- genuinely recycles/rebinds the SAME small set of widgets across
-- DIFFERENT Pals over time (matches the sixty-fifth pass's own finding,
-- "gauge widgets are apparently POOLED/reused"), and every single
-- recycle was paying full construction cost again even for a Pal this
-- mod was already tracking.
--
-- This moves an ALREADY-BUILT bar+label onto a NEW gauge widget's real
-- parent panel instead of building new ones — `UPanelWidget:RemoveChild`
-- confirmed real in this game's own UMG.hpp (same header this file
-- already trusts for AddChildToCanvas/GetChildrenCount/GetChildAt). The
-- widget OBJECTS themselves persist; only their panel membership and
-- position change, skipping StaticConstructObject/StaticFindObject/the
-- label-class lookup entirely. First attempt at moving an already-added
-- widget between different parent panels in this project — wrapped in
-- the same per-step pcall discipline as every other untested operation
-- here, with a full-construction fallback if any step fails.
-- Hundred-and-ninety-fourth pass (2026-09-05): an entry may now be
-- label-only (no bar built yet — see install_trust_bar, which builds the
-- personality label for every spawned Pal but the real trust bar only
-- once a real interaction exists). This used to require `entry.bar` to
-- already be valid just to reparent the LABEL, so a label-only entry
-- could never be reused across a gauge recycle — it would silently fall
-- through to full re-construction every time, building a duplicate label.
-- Now handles bar/label independently: moves whichever of the two
-- actually exists, and only fails outright if NEITHER does.
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

-- Hundred-and-ninety-fourth pass: upgrades an existing label-only entry
-- (a Pal that was seen and given its personality label, but had no real
-- interaction yet when it was first tracked) with a real trust/friendship
-- bar, the moment a real interaction actually happens. Mirrors
-- install_trust_bar's own bar-construction steps exactly, just callable
-- on an entry that already exists — used both right after a successful
-- reuse/reparent and from update_trust_bars's own per-tick loop, so the
-- bar appears the moment bonding starts, not only on the next gauge
-- recycle.
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
local function install_trust_bar(gaugeWidget)
    Logger.trace("build trust bar")
    local key = describe_widget(gaugeWidget)
    if barInstalledForGauge[key] then return end

    -- Hundred-and-ninetieth pass (2026-09-05): Dragón's follow-up to the
    -- threshold-caching fixes — don't build a bar AT ALL for a Pal with
    -- no real interaction on record, not just skip the expensive
    -- level-multiplier part of it. Most Pals the game shows a native
    -- gauge for are never actually approached, so building (or even
    -- reusing) custom widgets for every one of them, refreshed every
    -- scan tick, is wasted work for the vast majority. `resolve_pal_actor_
    -- from_gauge` was ALREADY being called unconditionally here every
    -- scan tick before this pass (needed for the reuse-check below), so
    -- checking `Trust.HasBondingState` (a plain table lookup, no actor/
    -- component resolution of its own) on top of that adds no new real
    -- cost. Deliberately does NOT mark `barInstalledForGauge[key]` when
    -- skipping this way — the actor may not have resolved yet (a real,
    -- separate race, see below) or may simply not be interacted with
    -- YET — either way, this needs to keep re-checking on later scan
    -- ticks (cheap) rather than permanently giving up on this exact
    -- gauge widget.
    local earlyActor = resolve_pal_actor_from_gauge(gaugeWidget)
    if earlyActor == nil then
        return 
    end
    -- The widget itself rather than `true`, so scan_for_gauge_widgets can drop
    -- entries for destroyed gauges instead of keeping one per gauge ever seen.
    barInstalledForGauge[key] = gaugeWidget

    -- Hundred-and-ninety-fourth pass (2026-09-05): Dragón asked for the
    -- personality label back for EVERY spawned Pal — it's the one thing
    -- he wants visible from a distance without interacting at all — while
    -- keeping the hundred-and-ninetieth pass's lag fix intact for the
    -- real trust/friendship bar itself (that one still only makes sense,
    -- and only costs anything, once a Pal is actually being bonded with).
    -- `hasBonding` splits the rest of this function: the label always
    -- gets built below; the bar only when this is true.
    local hasBonding = Trust.HasBondingState(earlyActor)

    -- Hundred-and-eightieth pass: this exact Pal might already have a
    -- live tracked entry (label and/or bar, from a different, now-stale
    -- gauge widget the game already recycled away from) — reuse it via
    -- reparent_existing_bar instead of paying full construction cost
    -- again. Falls through to the normal build path below if reparenting
    -- itself fails for any reason.
    local earlyPalId = safe_call(Personality.GetStableId, earlyActor)
    if earlyPalId and trackedBars[earlyPalId] then
        local entry = trackedBars[earlyPalId]
        local reused = reparent_existing_bar(entry, gaugeWidget)
        if reused then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] REUSED existing widget(s) for already-tracked Pal " .. describe_pal(earlyActor) .. " on recycled gauge " .. key .. " (no new widgets built)")
            if hasBonding then
                try_upgrade_entry_with_bar(entry)
            end
            return
        end
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] reparent attempt failed for already-tracked Pal " .. describe_pal(earlyActor) .. " — falling back to full construction")
    end
    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] attempting to construct widget(s) for gauge: " .. key)

    -- Fifty-sixth pass: the fifty-fifth pass's numbers came back IDENTICAL
    -- across every single Pal (pos=64,26 size=120,4, every time) — that's
    -- correct and expected (it's the Blueprint's own static per-widget
    -- design-space layout, same for every instance of the same class,
    -- with the whole gauge's own screen position handled at a higher
    -- level). But Dragón's screenshot still showed the new bar shifted
    -- right AND noticeably wider than the real HP bar — not just off
    -- vertically. That's the signature of a COORDINATE-SPACE mismatch,
    -- not a wrong offset: the fifty-fifth pass added the new bar into
    -- `Canvas_Innner` (a guess) while reading position numbers that are
    -- only meaningful relative to whatever panel `ProgressBar_HP` ACTUALLY
    -- lives in — if that's a different panel than Canvas_Innner (nested
    -- canvases each have their own local coordinate space), the same raw
    -- numbers land somewhere else entirely.
    --
    -- Real fix: `UPanelSlot` has a real `Parent` field (UMG.hpp) pointing
    -- to the exact live UPanelWidget a widget is already a child of. Read
    -- `ProgressBar_HP.Slot.Parent` and add the new bar into THAT SAME
    -- panel object, instead of guessing Canvas_Innner — guaranteeing
    -- identical coordinate space, so the real bar's own position/size
    -- numbers apply directly with no translation needed. This is also
    -- what Dragón suggested independently ("copy the healthbar
    -- positioning" ) — same idea, just anchored to the real parent panel
    -- so the copy actually lands in the same space instead of a
    -- differently-scaled sibling.
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

    -- ---------------------------------------------------------------------
    -- PERSONALITY LABEL (hundred-and-fiftieth pass, 2026-09-04; promoted
    -- from temporary debug text to a permanent, always-visible feature in
    -- the hundred-and-ninety-fourth pass, 2026-09-05, at Dragón's explicit
    -- request — this is the one thing he wants visible on every spawned
    -- Pal from a distance, without interacting at all, and he's floated
    -- eventually exposing it as a real user-facing on/off setting once
    -- the wording/styling gets a real polish pass). Built for EVERY
    -- spawned Pal now, unconditionally — NOT gated on `hasBonding` the way
    -- the real trust bar below is, since personality is rolled once per
    -- individual regardless of interaction history anyway.
    -- Reuses the exact same widget-construction technique already proven
    -- above for the trust bar itself (StaticFindObject the native UMG
    -- class, StaticConstructObject into the same real parent panel,
    -- AddChildToCanvas, position relative to the trust bar's own real
    -- coordinates) — the only new parts are the widget class (TextBlock
    -- instead of ProgressBar) and setting its text, both first attempts
    -- for this project, wrapped safely and logged honestly per this
    -- file's own established discipline (nothing in this file has ever
    -- worked on the very first try).
    -- Hundred-and-fifty-first/second passes (2026-09-04): this block
    -- caused a real crash on its first live test — root cause found via
    -- [CRASH-DIAG] before/after bracketing (a raw `.Text = string`
    -- property write into an FText field) and fixed by constructing the
    -- game's own real text-widget class (`BP_PalTextBlock_C`, pulled off
    -- an already-live `Text_WorkName` instance on this same gauge) and
    -- writing via the confirmed-safe `SetText_GDKInternal` method
    -- instead. Confirmed crash-free in Dragón's next real test.
    --
    -- Hundred-and-fifty-fourth pass (2026-09-04) FIX, REAL LAG FOUND:
    -- that same [CRASH-DIAG] bracketing was left in AFTER the crash was
    -- already found and fixed — Dragón felt real lag on the very next
    -- test, and the log showed why: [CRASH-DIAG] alone was 516 of 981
    -- Indicator lines in a 140-second session (over half), each one a
    -- forced synchronous disk write (Logger.lua's own crash-safety
    -- design). Exact same self-inflicted-logging lag shape this project
    -- has hit and fixed before (INDICATOR-WATCH, ninety-eighth pass) —
    -- diagnostic bracketing is meant to be temporary, trimmed once the
    -- specific bug it was hunting is confirmed fixed, not left running
    -- forever. Removed here; kept only the one line that reports the
    -- real outcome (OK/FAILED), matching every other one-shot creation
    -- log elsewhere in this function.
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

    -- Real trust/friendship bar — still gated on `hasBonding` (a real
    -- interaction on record), per the hundred-and-ninetieth pass's lag
    -- fix, which stays fully intact. Only built when that's true; a
    -- non-interacted Pal gets its label above and nothing else.
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

    -- Hundred-and-eightieth pass: store under the real Pal ID when
    -- already known at this point rather than the gauge's own temporary
    -- identity — that's what lets a LATER gauge recycle for this same
    -- Pal find and reuse this entry via reparent_existing_bar instead of
    -- building yet another one. Falls back to the gauge-widget key (old
    -- behavior) when the Pal still isn't resolvable yet; update_trust_bars
    -- promotes it to the real key once resolution succeeds on a later
    -- retry.
    local trackKey = earlyPalId or key
    trackedBars[trackKey] = { bar = newBar, gaugeWidget = gaugeWidget, actor = earlyActor, label = newLabel, palId = earlyPalId,
        actorAddr = address_of_obj(earlyActor) }
end

-- Fifty-seventh pass: periodic refresh for every installed bar — re-reads
-- the live FriendshipPoint and updates the bar's fill every scan tick, so
-- it actually moves as trust changes (petting, damage, passive gain,
-- capture) instead of staying frozen like the fifty-fourth/fifty-fifth
-- passes' static test value.
--
-- Fifty-ninth pass: also RETRIES actor resolution every tick for any
-- entry that hasn't resolved yet (see install_trust_bar's comment above
-- for why a single attempt at creation time isn't enough), so a gauge
-- whose BindFromHandle hook fires slightly after its bar was created
-- still ends up wired to real data instead of being stuck at the
-- placeholder for the rest of its life. Drops any entry whose bar or
-- gaugeWidget has gone invalid (Pal despawned/left range, or the gauge
-- widget itself was destroyed) rather than erroring on it.
-- 2026-09-15 (profiling), see the label block inside update_trust_bars:
-- a label-only tag rebuilds its text when its personality or F9 visibility
-- changes, and otherwise at most this often as a safety net.
local LABEL_REFRESH_SECONDS = 10.0
-- A tag still showing "?" (no personality created yet) retries creating it at
-- most this often per Pal.
local LABEL_STATE_RETRY_SECONDS = 10.0
local function update_trust_bars()

    -- Hundred-and-eightieth pass: promotions (moving an entry from its
    -- temporary gauge-widget key to its real Pal-ID key once resolution
    -- succeeds) are collected here and applied AFTER the loop below —
    -- Lua's `pairs()` doesn't allow inserting a NEW key into a table
    -- while traversing it (removing/nil-ing an EXISTING key, as already
    -- done below, is explicitly fine; adding one is not).
    local promotions = {}
    for key, entry in pairs(trackedBars) do

        -- Hundred-and-ninety-fourth pass: `entry.bar` can legitimately be
        -- nil now (a label-only entry for a Pal with no interaction yet)
        -- — that used to unconditionally fail this check and drop the
        -- WHOLE entry (including its personality label) every single
        -- tick, which would have made the "always show the label" feature
        -- impossible. Only require the bar to be valid when one exists.
        local hasBar = entry.bar ~= nil
        local barOk, barValid = true, true
        if hasBar then
            barOk, barValid = pcall(function() return entry.bar:IsValid() end)
        end
        local gaugeOk, gaugeValid = pcall(function() return entry.gaugeWidget:IsValid() end)
        if not gaugeValid or (hasBar and not (barOk and barValid)) then
            trackedBars[key] = nil
        else
            if entry.actor == nil then
                local actor = resolve_pal_actor_from_gauge(entry.gaugeWidget)
                if actor then
                    entry.actor = actor
                    entry.actorAddr = address_of_obj(actor)
                    Logger.log("[PalBonds/Indicator] [DIAG-TRUST] resolved a real Pal actor on a retry for a previously-unresolved gauge: " .. describe_pal(actor))

                    -- This entry may still be keyed by its gauge widget's
                    -- own temporary identity (Pal ID wasn't known yet at
                    -- creation). Now that it is, promote it to the real
                    -- Pal-ID key so a FUTURE gauge recycle for this same
                    -- Pal can find and reuse it (install_trust_bar's
                    -- early-reuse check) instead of building fresh again.
                    -- Skipped if this Pal already has a different tracked
                    -- entry (a rare duplicate — left as accepted, cosmetic
                    -- debt rather than merging/destroying widgets here).
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

                    -- Hundred-and-ninety-fourth pass: a label-only entry
                    -- (no bar yet) gets checked here every tick — a cheap
                    -- Trust.HasBondingState table lookup inside
                    -- try_upgrade_entry_with_bar — for whether its Pal has
                    -- just had its first real interaction. If so, the real
                    -- trust bar gets built right then, next to the
                    -- personality label that was already showing, instead
                    -- of waiting for this exact gauge widget to recycle.
                    if entry.bar == nil then
                        try_upgrade_entry_with_bar(entry)
                    end
                    if entry.bar ~= nil then
                        local ratio = get_friendship_ratio(entry.actor)

                        -- 2026-09-15 (profiling): written only when the value
                        -- changed. It used to be two widget writes per bar
                        -- every 2 seconds whether or not anything moved.
                        if ratio and ratio ~= entry.lastRatio then
                            entry.lastRatio = ratio
                            pcall(function() entry.bar:SetPercent(ratio) end)
                            pcall(function() entry.bar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
                        end
                    end

                    -- TEMPORARY DEBUG FEATURE (hundred-and-fiftieth pass,
                    -- 2026-09-04) — see install_trust_bar's matching
                    -- comment above. Only writes when the text actually
                    -- CHANGES (labelLastText), not every tick — this runs
                    -- once per tracked bar per scan, same lag discipline
                    -- as everything else in this file, and a personality
                    -- disposition basically never changes after the
                    -- initial roll (Won-Over is the one exception), so
                    -- this should write once per Pal and then go quiet.
                    if entry.label then
                        local labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
                        if labelOk and labelValid then
                            -- 2026-09-15 (profiling): this block ran in full for
                            -- EVERY label on screen every 2 seconds — a four-call
                            -- id rebuild, the owned/fled checks, a friendship read
                            -- — and was the largest remaining recurring cost in run
                            -- D. Now:
                            --   * the Pal's id is resolved once per actor;
                            --   * a label-only Pal (no bar, so no bonding progress
                            --     that could change its text) rebuilds its text only
                            --     when its personality or the F9 visibility changed,
                            --     and otherwise at most every LABEL_REFRESH_SECONDS
                            --     as a safety net;
                            --   * a Pal with a bar (being bonded) still updates every
                            --     tick, since its label follows its progress.
                            -- And a label still waiting on "?" (no personality yet —
                            -- its Pal's AI has not sensed near the player) creates
                            -- that one Pal's personality now instead of waiting for
                            -- the ~64s safety scan, retried at most every
                            -- LABEL_STATE_RETRY_SECONDS.
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

                                -- Hundred-and-fifty-second pass FIX: same
                                -- crash-causing direct `.Text =` property
                                -- write as install_trust_bar's — switched
                                -- to the confirmed-real SetText_GDKInternal
                                -- method here too. Hundred-and-fifty-fourth
                                -- pass: dropped the [CRASH-DIAG] before/
                                -- after pair once the crash was confirmed
                                -- fixed — see install_trust_bar's matching
                                -- comment for the real lag numbers this
                                -- caused.
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
end
-- ===========================================================================
-- BOSS HP BAR (2026-09-16)
-- ===========================================================================
-- Bosses (alphas, raid, tower and predator bosses; Dragón has bonded every
-- kind) never showed the trust bar or the personality tag, because the game
-- does not give them the WBP_PalNPCHPGauge_C nameplate everything above attaches
-- to. They get WBP_BossEnemyHPGauge_C instead: the big bar at the top of the
-- screen. From the UE4SS header/object dumps:
--
--   WBP_BossEnemyHPGauge_C              one per boss, owned by the gauge canvas
--     .TargetCharacter                  the boss Pal itself (a plain field)
--     :SetTargetCharacter(APalCharacter) called when the bar is set up
--     .WBP_IngameBossHP                 WBP_IngameBossHP_C, the visible bar
--        .BossGaugeHP                   the HP ProgressBar (in canvas "BossHP")
--        .Text_BossName / .Text_LvTitle / .Text_LvValue
--
-- Dragón's layout call: the friendship bar goes under the HP bar "like always,
-- ideally with the same length too"; the tag sits under it as on nameplates.
-- Both are added to the same panel as BossGaugeHP, so they move with that
-- boss's bar when several bosses stack. Whether the stacked bars leave room
-- under each other is the open question for the first test run —
-- [BOSS-GEOM] prints the real layout once so it can be fixed from numbers.
--
-- Performance, same rules as 1.1.2: the SetTargetCharacter hook reports each
-- boss bar, so there is no timed world search. The one exception is a single
-- FindAllOf right after the hook first installs, for a bar that was already on
-- screen before then. A handful of boss bars at most are refreshed on the
-- existing 2-second tick.
local BOSS_GAUGE_HOOK_PATH = "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_BossEnemyHPGauge.WBP_BossEnemyHPGauge_C:SetTargetCharacter"
local BOSS_BAR_GAP = 2
local BOSS_BAR_MIN_HEIGHT = 6
local BOSS_BAR_MAX_HEIGHT = 10
local BOSS_LABEL_GAP = 1
local BOSS_LABEL_HEIGHT = 22
-- Copy the tag's look from the small "Lv" text rather than the big boss name,
-- which would make the tag as large as the name. Falls back to the name.
local BOSS_LABEL_STYLE_FIELDS = { "Text_LvTitle", "Text_BossName" }
local hasRegisteredBossHook = false
local pendingBossGauges = {}
local bossEntries = {}
local bossGeometryLogged = false

local function is_valid_obj(obj)
    return obj ~= nil and safe_call(function() return obj:IsValid() end) == true
end

-- The boss HP bar's slot is ANCHORED, not placed at a fixed size. The first
-- live run (2026-09-16) read it as pos=(4,18) size=(4,8): with a horizontally
-- stretched anchor, SetPosition/SetSize-style numbers are really the offsets
-- Left/Top/Right/Bottom, so "size X = 4" is a 4px right MARGIN, not a width.
-- Building our bar with SetSize({X = 4}) made it 4px wide — the tiny yellow
-- mark at the left end of the HP bar in Dragón's screenshot. So the layout is
-- read as offsets + anchors + alignment and our widgets copy the same anchors,
-- which gives them exactly the HP bar's length whatever the anchoring is.
local function boss_hp_layout(gaugeWidget)
    -- GetPosition/GetSize return the slot's raw offsets (Left,Top) and
    -- (Right,Bottom) whatever the anchoring; both are proven to work live.
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
    -- Height is the Bottom offset only when the anchor is not stretched
    -- vertically; otherwise it is a margin and the real height is unknown.
    local stretchedY = anc ~= nil and anc.minY ~= anc.maxY
    local h = stretchedY and 8 or off.bottom
    local topEdge = off.top - ((al.y or 0) * h)
    return { inner = inner, parent = parent, off = off, anc = anc, al = al,
             h = h, topEdge = topEdge, stretchedY = stretchedY }
end

-- Puts a widget under the HP bar: same anchors, same left/right offsets (so
-- the same length whether the HP bar is stretched or fixed-width), its own
-- top edge and height. Anchors are set first: changing anchors afterwards
-- would reinterpret the offsets.
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

-- One-shot, diagnostics only: where the boss bar's pieces really sit, and what
-- the HP bar is nested in, so the stacking question is answered with numbers.
local function log_boss_geometry(entry, layout)
    if bossGeometryLogged or not Logger.DiagnosticsEnabled() then return end
    bossGeometryLogged = true
    local function slotOf(wd)
        local s = "?"
        pcall(function()
            local sl = wd.Slot
            local pos, size = sl:GetPosition(), sl:GetSize()
            s = string.format("pos=(%s,%s) size=(%s,%s)", tostring(pos.X), tostring(pos.Y), tostring(size.X), tostring(size.Y))
        end)
        return s
    end
    local function nameOf(wd)
        local n = safe_call(function() return wd:GetFullName() end)
        return n and (tostring(n):match("^(%S+)") .. " " .. (tostring(n):match("([^%.:]+)$") or "")) or "?"
    end
    Logger.log("[PalBonds/Indicator] [BOSS-GEOM] BossGaugeHP    " .. slotOf(layout.inner.BossGaugeHP))
    local a = layout.anc
    Logger.log(string.format("[PalBonds/Indicator] [BOSS-GEOM] BossGaugeHP anchors=%s alignment=(%s,%s) -> height used=%s topEdge=%s",
        a and string.format("min(%s,%s) max(%s,%s)", tostring(a.minX), tostring(a.minY), tostring(a.maxX), tostring(a.maxY)) or "UNREADABLE",
        tostring(layout.al.x), tostring(layout.al.y), tostring(layout.h), tostring(layout.topEdge)))
    pcall(function() Logger.log("[PalBonds/Indicator] [BOSS-GEOM] Text_BossName  " .. slotOf(layout.inner.Text_BossName)) end)
    pcall(function() Logger.log("[PalBonds/Indicator] [BOSS-GEOM] Text_LvTitle   " .. slotOf(layout.inner.Text_LvTitle)) end)
    if entry.bar then Logger.log("[PalBonds/Indicator] [BOSS-GEOM] trust bar      " .. slotOf(entry.bar)) end
    if entry.label then Logger.log("[PalBonds/Indicator] [BOSS-GEOM] tag            " .. slotOf(entry.label)) end
    local chain = {}
    local cur = layout.inner.BossGaugeHP
    for _ = 1, 8 do
        local parent = safe_call(function() return cur.Slot.Parent end)
        if not is_valid_obj(parent) then break end
        chain[#chain + 1] = nameOf(parent)
        cur = parent
    end
    Logger.log("[PalBonds/Indicator] [BOSS-GEOM] HP bar nesting (inner→outer): " .. table.concat(chain, "  <  "))
    local clip = safe_call(function() return layout.parent.Clipping end)
    Logger.log("[PalBonds/Indicator] [BOSS-GEOM] HP bar's panel clipping = " .. tostring(clip) .. " (0 = children may draw outside it)")
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
    if Logger.DiagnosticsEnabled() then
        pcall(function()
            local p, s, a = slot:GetPosition(), slot:GetSize(), slot:GetAnchors()
            Logger.log(string.format("[PalBonds/Indicator] [BOSS-GEOM] trust bar placed: offsets=(%s,%s,%s,%s) anchors=min(%s,%s) max(%s,%s)",
                tostring(p.X), tostring(p.Y), tostring(s.X), tostring(s.Y),
                tostring(a.Minimum.X), tostring(a.Minimum.Y), tostring(a.Maximum.X), tostring(a.Maximum.Y)))
        end)
    end
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
    -- The game shows this bar only for bosses: count it for the x2 bond meter.
    safe_call(Trust.MarkBossActor, actor)
    local entry = { widget = widget, actor = actor, palId = safe_call(Personality.GetStableId, actor),
        actorAddr = address_of_obj(actor) }
    build_boss_label(entry, layout)
    if Trust.HasBondingState(actor) then build_boss_bar(entry, layout) end
    bossEntries[key] = entry
    Logger.log(string.format("[PalBonds/Indicator] [BOSS] boss bar attached for %s (id %s) — tag=%s bar=%s",
        describe_pal(actor), tostring(entry.palId), tostring(entry.label ~= nil), tostring(entry.bar ~= nil)))
    log_boss_geometry(entry, layout)
    return true
end

local function update_boss_entry(key, entry)
    if not is_valid_obj(entry.widget) then bossEntries[key] = nil return end
    local actor = safe_call(function() return entry.widget.TargetCharacter end)
    if not is_valid_obj(actor) then actor = entry.actor end
    if not is_valid_obj(actor) then return end
    -- Compared by address: UE4SS hands out a fresh wrapper per read, so `~=`
    -- on the objects themselves would read as "changed" every tick.
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
        -- Same bar re-targeted: let the tick pick up the new Pal.
        return
    end
    pendingBossGauges[key] = { widget = widget, actor = actor }
end

-- One search, right after the hook installs, for boss bars already on screen.
local function sweep_existing_boss_gauges()
    local list = safe_call(function() return FindAllOf("WBP_BossEnemyHPGauge_C") end)
    local n = 0
    if type(list) == "table" then
        for _, g in ipairs(list) do
            local name = safe_call(function() return g:GetFullName() end)
            -- Skip the class default object; only live bars.
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
            queue_boss_gauge(hook_get(Context), hook_get(TargetCharacter))
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

-- probe_screen_projection removed in the two-hundred-and-eighty-ninth pass.
-- It projected a Pal's world position to screen space to test placing UI there.
-- The nameplate work went a different route entirely -- widgets are parented into
-- the game's own gauge, which needs no projection -- and the only call site had
-- already been commented out.

local GAUGE_FLAG_PRUNE_EVERY_N_SCANS = 30   -- ~60s at SCAN_INTERVAL_MS
local gaugeFlagScanCount = 0
local function scan_for_gauge_widgets()
    -- Every wild Pal that ever showed an HP gauge left an entry here for the
    -- whole session (2026-09-12 growth audit). Prune the destroyed ones.
    gaugeFlagScanCount = gaugeFlagScanCount + 1
    if gaugeFlagScanCount % GAUGE_FLAG_PRUNE_EVERY_N_SCANS == 0 then
        for k, w in pairs(barInstalledForGauge) do
            if type(w) ~= "userdata" and type(w) ~= "table"
                or not safe_call(function() return w:IsValid() end) then
                barInstalledForGauge[k] = nil
            end
        end
    end

    -- Two-hundred-and-seventy-second pass: this sweep touches live UI widgets,
    -- which are destroyed early in teardown. Stop as soon as the world is going.
    local okShut, CombatShut = pcall(require, "Combat")
    if okShut and CombatShut and CombatShut.IsShuttingDown and CombatShut.IsShuttingDown() then
        return
    end

    -- Two-hundred-and-seventy-first pass (2026-09-08) — Dragon went to take
    -- screenshots and found "a lot of pals didnt show their personality tags".
    --
    -- The cause is in the startup timing, and his own UE4SS log shows it: the
    -- mod loads at 00:00:43, but the WBP_PalNPCHPGauge:BindFromHandle hook --
    -- the thing that creates a label when a nameplate attaches to a Pal -- only
    -- registers at 00:01:38. That is fifty-five seconds, because the widget
    -- class is not loaded yet and the registration has to keep retrying until it
    -- is. Every nameplate that binds inside that window never gets a tag, and it
    -- never gets one later either, because nothing revisits an existing gauge.
    --
    -- That window is exactly when a player loads in and looks around, which is
    -- why it looks like "a lot" rather than "occasionally one".
    --
    -- This sweep closes it. install_trust_bar is idempotent per widget (it has
    -- been since the fifty-first pass, and the [DIAG-CREATE] "REUSED existing
    -- widget(s)" line is it declining to rebuild), so calling it on every live
    -- gauge every couple of seconds costs nothing for gauges that already have
    -- their label and fixes the ones that missed the hook.
    -- 2026-09-15 (profiling): see NAMEPLATES FROM THE HOOK near the top of this
    -- file. Every tick installs tags on the nameplates the BindFromHandle hook
    -- reported, which needs no search. The world sweep below it now runs only
    -- until that hook is registered, for NAMEPLATE_SWEEPS_AFTER_HOOK ticks after,
    -- and then every NAMEPLATE_SAFETY_SWEEP_EVERY_N_SCANS ticks as a safety net.

    for key, g in pairs(pendingGauges) do
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

    -- 2026-09-16: two diagnostic-only world searches used to run here every
    -- tick whenever SHOW_DIAGNOSTICS was on (FindAllOf PalUICharacterHPGaugeBase
    -- and PalUINPCHPGaugeCanvasBase), feeding [DIAG-SCAN]/[DIAG-PANEL] lines
    -- about a widget structure mapped out in passes 46-51. The profiler caught
    -- them in run 3 as the dev build's biggest cost: 676 stalls, ~145 ms each,
    -- about 3.5 s per minute. Removed with everything only they used.

    -- Fifty-seventh pass: refresh every trust bar that resolved a real
    -- Pal actor, every tick, so they actually move.
    update_trust_bars()

    update_boss_displays()

    -- Two-hundred-and-thirty-seventh pass (2026-09-07) — REMOVED FROM THE
    -- TICK, and this is a real crash suspect, not just cleanup.
    --
    -- Dragón hit an EXCEPTION_ACCESS_VIOLATION reading address 0x338 (a null
    -- pointer plus a field offset) with UE4SS frames interleaved in the stack,
    -- on a game launched IMMEDIATELY after closing a previous session. This
    -- probe is the only place in the entire mod that calls engine screen-
    -- projection functions — ProjectWorldToScreen / ProjectWorldLocationToScreen
    -- — on a PlayerController, and by its own design it "keeps retrying each
    -- tick until one exists", which means it fires repeatedly during world load
    -- against a controller that may be half-constructed. That is exactly how a
    -- null-plus-offset read happens.
    --
    -- It also already threw this session: UE4SS.log carries a live stack
    -- traceback through ProjectWorldLocationToScreen at Indicator.lua:2261. That
    -- one was caught, but pcall only catches LUA errors — a native access
    -- violation inside the engine call takes the process down regardless of how
    -- many pcalls wrap it. So "it is guarded" was never protection here.
    --
    -- And it feeds nothing. Its only consumer is posmatch_log: it writes log
    -- lines and no code reads a projected coordinate anywhere. The labels are
    -- positioned from ProgressBar_HP's real parent panel, not from projection —
    -- that question was settled passes ago and this probe outlived it.
    --
    -- The function is left DEFINED but uncalled, matching what this file already
    -- does with poll_prism_class/poll_prism_bullet_state, so the research is
    -- preserved rather than deleted if a future pass wants to run it on demand.
    --
    -- Stated honestly: this is not proven to be the crash. There is no dump from
    -- that launch and the live log ends normally, because the crash happened
    -- before the mod's logger reopened the file. But it is the only null-deref
    -- vector this mod has against a loading player controller, it is known to
    -- have thrown, it matches the signature and the timing, and it has no
    -- reason to exist any more. Removing it costs nothing.
    -- probe_screen_projection()

    -- Two-hundred-and-sixth pass (2026-09-06) — poll_prism_state() REMOVED
    -- from this tick. It ran TWO full-world FindAllOf scans
    -- (BP_CapturePrism_C and BP_CapturePrismBullet_C) plus a GetFullName()
    -- reflection call per instance found, every 2 seconds, for the entire
    -- session — and BP_CapturePrism_C is the player's own held Palsphere
    -- weapon, so it reliably finds instances rather than usually returning
    -- nothing.
    --
    -- Its throttles only ever suppressed the log LINES (seenPrismInstances
    -- and prism_log's cap); the two world scans themselves ran every tick
    -- regardless, which is the part that actually costs anything. Same
    -- invisible-cost shape as the SetHPPercent hook removed at the bottom
    -- of this file.
    --
    -- The research it fed is closed: it was watching the sphere projectile
    -- to chase the capture light-beam VFX, and the hundred-and-ninety-third
    -- pass's dedicated test run settled that whole thread (the
    -- ABP_ReturnPalEffect_C candidate was ruled out against three real
    -- capture/rescue events). The VFX question itself is still open, but it
    -- needs a fresh candidate found via repak/FModel — not this poll, which
    -- never had a live consumer and produced nothing any code reads.
    -- poll_prism_class/poll_prism_bullet_state are left defined but
    -- uncalled, in case a future pass wants to run one on demand.
end

-- Same scheduling approach already proven in Trust.lua.
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
        pcall(function()
            LoopAsync(SCAN_INTERVAL_MS, function()
                local inGameThread = true
                pcall(function() inGameThread = IsInGameThread() end)
                if inGameThread then
                    safe_call(scan_for_gauge_widgets)
                end
                return false 
            end)
        end)
    end
end
function Indicator.Init()
    -- Five startup banner lines were removed here on 2026-09-11. They announced
    -- findings from passes 64-71 on every single launch, and one of them ended
    -- "See poll_prism_state" — a function deleted in the 2026-09-08 cleanup.
    -- A startup banner describing code that no longer exists is worse than no
    -- banner: the research it reported is settled and lives in docs/hook-points.md.

    -- Hundred-and-fifty-fifth pass (2026-09-04): register the class-level
    -- BindFromHandle/Unbind hooks HERE, first thing, rather than waiting
    -- for the periodic scan to discover a gauge widget — see
    -- register_bind_hook_immediate's own comment for the real race this
    -- closes (a Pal already on-screen at session start permanently
    -- missing capture otherwise).
    register_bind_hook_immediate()
    -- 2026-09-16: the boss bar equivalent — see BOSS HP BAR above.
    register_boss_hook()

    -- Two-hundred-and-sixth pass (2026-09-06) — REMOVED, REAL LAG SOURCE.
    -- Two read-only diagnostic hooks used to live here, on
    -- PalUICharacterHPGaugeBase's SetTargetCharacter and SetHPPercent.
    -- They existed only to learn the native gauge widget's structure — a
    -- question closed back in the fifty-first pass — but were never taken
    -- back out.
    --
    -- Why they were a genuine, invisible performance cost rather than just
    -- log noise: SetHPPercent is called by the game every time ANY visible
    -- Pal's HP gauge updates its fill, continuously, for every gauge on
    -- screen at once. Every one of those calls crossed into Lua and ran
    -- `describe_widget(widget)` — a real GetFullName() reflection
    -- round-trip — plus a string.format, BEFORE `diagnostic_log` ever got
    -- the chance to discard the result. `diagnostic_log`'s
    -- MAX_DIAGNOSTIC_LOGS cap only silenced the OUTPUT: because Lua
    -- evaluates call arguments before the call, the reflection and string
    -- work still happened on every single call for the entire session,
    -- long after the log itself went quiet. That made this cost invisible
    -- in the log (only 20 lines ever appear) while scaling directly with
    -- how many Pals are on screen — matching the "worse when entering a
    -- new area" shape of the lag Dragón has been reporting.
    -- SetTargetCharacter had the identical shape, with two describes per
    -- call instead of one.
    --
    -- Nothing reads these lines any more and no live feature depends on
    -- them, so they are removed outright rather than throttled. The real
    -- gauge work this module actually needs (finding gauges to attach the
    -- trust bar/personality label to) runs from scheduleScan() below and
    -- the BindFromHandle hook above, both untouched.

    scheduleScan()
end

-- ===================================================================
-- WORLD CHANGE (three-hundred-and-twenty-eighth pass, 2026-09-17)
-- ===================================================================
-- Every table below holds either a nameplate widget from the world that just
-- closed or the Pal actor that widget belonged to, and a Lua reference keeps a
-- UObject alive. Nothing cleared them until now, so they survived a quit and
-- the engine walked them again in the next world -- the 0x338 crash shape this
-- project has now paid for three times (see Combat.ResetForNewWorld).
--
-- Only references are dropped; no game call is made. The gauge widgets
-- themselves live under the GameInstance and are the game's to manage. The tags
-- and bars we build hang off nameplates that die with their world, so the
-- correct response to a world change is simply to forget all of them and let
-- the hook install fresh ones in the new world.
-- ===================================================================
-- FORGETTING A PAL THAT JOINED (2026-09-19, Esaeon's crash)
-- ===================================================================
-- Esaeon (Proton, GitHub issue #1): the game crashes 5-15 s after a Pal
-- joins, with PalBonds as the only mod (1.1.5), EXCEPTION_ACCESS_VIOLATION
-- reading 0x0 with every frame inside UE4SS. Swordfish (Windows) saw it once
-- "right when the trust bar went full". A join destroys the wild actor and
-- the game later frees it -- a one-Pal version of the world change that
-- 1.1.3/1.1.4 fixed by dropping every reference. At a join, only Trust
-- (ForgetBonding) and Combat (StopFollowing) let go; the rest kept the dead
-- Pal for up to 10 minutes and went on calling IsValid() and more on it.
-- IsValid() on a freed object has to read freed memory: on Windows that
-- memory usually still holds something readable, under Proton/Wine it
-- often doesn't. So this module now forgets the Pal the moment it joins,
-- the same way ResetForNewWorld forgets a whole world.
-- `actorAddr` is the wild actor's address, read before the capture; entries
-- are compared by address or Pal id, never by calling into the stored actor.
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

function Indicator.ResetForNewWorld()
    local bars, bosses = 0, 0
    for _ in pairs(trackedBars) do bars = bars + 1 end
    for _ in pairs(bossEntries) do bosses = bosses + 1 end
    pendingGauges = {}
    gaugeHandleByKey = {}
    barInstalledForGauge = {}
    trackedBars = {}
    pendingBossGauges = {}
    bossEntries = {}
    nameplateSweepsSinceHook = 0
    Logger.log(string.format(
        "[PalBonds/Indicator] [WORLD-RESET] dropped %d tracked nameplate bar(s) and %d boss bar(s) from the old world",
        bars, bosses))
end
return Indicator
