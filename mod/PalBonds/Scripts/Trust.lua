--[[
    Trust.lua — DESIGN.md §3.3

    FIRST REAL IMPLEMENTATION (2026-09-01), replacing the stub. Wired
    directly to the REAL FriendshipPoint/FriendshipRank mechanic — per
    Dragón's original instruction to reuse the existing mechanic rather
    than invent a parallel one — and shaped around Dragón's own
    description of how it actually works in vanilla:

      - Pals start at rank 0, cap at rank 10.
      - Each rank requires more FriendshipPoint than the last.
      - Rank grants real stat bonuses (HP/ATK/DEF/WorkSpeed) — native
        game behavior, nothing this mod needs to touch.
      - Party Pals gain passive friendship over time; base Pals gain it
        slower. (Real fields for this DO exist — see hook-points.md,
        sixteenth pass: FriendshipPoint_AutoIncrementOtomo /
        _ActiveOtomo / _Worker on what looks like a game balance config
        object — but hooking a bonding WILD Pal into that same system
        means making it a real Otomo, which is still unsolved, DESIGN.md
        Q6. This pass approximates passive gain with our own timer.)
      - "Kinship peaches" give a big one-time boost. NOT implemented this
        pass — needs the item's real FName/ID, which needs either FModel
        or a live feed-and-log session to discover. Left as a TODO with
        the real hook point named (see bottom of this file).

    This mod's OWN rules layered on top (Dragón's spec, 2026-09-01):
      1. Hundred-and-ninety-fifth pass (2026-09-05): the raw
         "N successful interactions" following-trigger has been replaced
         with FOLLOW_TRIGGER_RATIO — the Pal starts following once its
         real FriendshipPoint crosses that fraction of its own bonding
         threshold (see BONDING_TRIGGER_THRESHOLD_BASE), matching Dragón's
         explicit request to make every trigger relative to the bar
         itself rather than a raw action count that stopped incrementing
         reliably once Pet/Feed mostly ran through real vanilla actions.
      2. While following: passive trust gain over time (our own timer —
         see tick_followers below — approximating the real Otomo
         auto-increment mentioned above).
      3. While following, if the Pal is damaged: a big trust LOSS
         (DAMAGE_FRIENDSHIP_PENALTY).
      4. If a following Pal's rank hits 0 (after damage, or after losing
         all trust for distance below): it's done — Capture.OnTrustLost
         flags it permanently, matching DESIGN.md §3.6.
      5. If the player gets too far from a following Pal: it loses ALL
         trust and stops following (approximates a leash break; actual
         forced despawn is NOT implemented this pass — see note below).
      6. Reaching CAPTURE_AT_FRIENDSHIP_POINT -> Capture.OnTrustMaxed
         fires (DESIGN.md §3.5), calling the real sphere-less capture
         function. FORTY-FIRST PASS (2026-09-02): this used to check the
         real game's own FriendshipRank reaching 1, but that meant
         needing the real, never-actually-read point-per-rank curve to
         even predict when it'd fire. Dragón pointed out we control this
         value ourselves — switched to a plain FriendshipPoint threshold
         (55, tunable) checked from both a pet/feed AND the passive-gain
         tick, so it can be tuned freely without any more research.

    Real functions/fields this reuses (confirmed in the SDK dump,
    Pal.hpp — same UPalIndividualCharacterParameter object Interaction.lua
    already reads):
      - GetFriendshipPoint() — already used elsewhere in this project.
      - GetFriendshipRank() — NEW this pass. Same "plain int, no args"
        safe shape as GetFriendshipPoint(). This is the real 0-10 rank
        Dragón described.
      - AddFriendShip(Value, ApplyPassiveSkill) — already proven safe,
        used here with NEGATIVE values (damage/leash loss, passive gain
        uses positive). CONFIRMED LIVE as of the seventeenth-pass test
        session: real negative calls (-38, -22, -76, distance wipes; -50
        from a real damage penalty before the eighteenth pass lowered it
        to -25) all applied cleanly with no crash.

    Per-instance state is keyed by `pal:GetFullName()` (same identifier
    this project has used since the ninth pass), NOT FPalInstanceID
    (the real per-individual save ID the SDK dump confirms exists,
    DESIGN.md Q5) — reading that safely means reaching into a nested
    struct (`param.SaveParameter.InstanceId`, itself containing two FGuid
    fields) not yet tested live. Documented limitation carried over from
    DESIGN.md: this state resets if the Pal despawns or the game reloads.
    Fine for a first pass; a real save-ID pass can come later.

    EXPERIMENTAL: this file is the project's first use of a repeating
    timer rather than a pure event hook (RegisterHook). See Init() below
    for why that's flagged, and what the fallback path is if it doesn't
    work on this build.
]]

local Logger = require("Logger")

local Trust = {}

-- Hundred-and-eighty-first pass (2026-09-05): Dragón asked for confirmation
-- that testing-friendly and real-balanced configurations can coexist as a
-- toggle. This flag is the single place that decides which multiplier
-- applies (Trust.ComputeLevelMultiplier) — flip it here, nothing else
-- needs to change.
-- Hundred-and-eighty-seventh pass (2026-09-05): flipped OFF — Dragón
-- wants to test the real level-gap-based numbers first, and will ask
-- explicitly to flip this back on only when testing something that
-- needs fast, repeated bonding (following, combat assist, etc.), where
-- waiting through the real per-level bar every time would be impractical.
local EASY_TEST_MODE = false

-- Hundred-and-eighty-fourth pass (2026-09-05): Dragón's real balance
-- design, replacing the old easy-only placeholder numbers now that the
-- balance-research data (real friendship-rank curve, vanilla Petting/
-- AutoIncrement/penalty constants, both Kinship Peach tiers) is in hand.
-- EASY_TEST_MODE now controls the level-gap MULTIPLIER specifically
-- (flat 10x for fast testing vs. the real tiered multiplier below) —
-- the base point amounts themselves are the same in both modes, since
-- these ARE the target numbers now, not a separate slow "real" set.
-- Hundred-and-ninety-fifth pass (2026-09-05): the old raw
-- INTERACTIONS_TO_START_FOLLOWING = 5 counter is retired — Dragón's
-- explicit instruction was to replace it, not keep it as a fallback,
-- since the real problem (Pet/Feed mostly routing through real vanilla
-- actions that never incremented this counter reliably) was a root
-- cause, not a tuning issue. Both new triggers are fractions of the same
-- bonding bar used everywhere else (get_bonding_threshold) — a Pal
-- starts following once its real FriendshipPoint crosses 50% of its own
-- bar, and separately (see Personality.MaybeBecomeFriendlyByBar) its
-- tracked disposition shifts to "friendly" once it crosses 20% —
-- regardless of which starting tier it rolled. Both numbers are Dragón's.
local FOLLOW_TRIGGER_RATIO = 0.5
local FRIENDLY_TRIGGER_RATIO = 0.2
-- Seventeenth pass (2026-09-01): was 5000ms. Dragón's own test report
-- ("started following but irregularly", a Pal "ran away from its normal
-- skittish behavior" mid-follow) matches a real gap in the old design:
-- a move order only refreshed every 5s left plenty of time for the
-- Pal's own wild AI to retarget/wander/flee in between. Dropped to 1.5s
-- so the move order (and the distance/leash check) refresh much more
-- often; paired with Combat.lua's new SetActiveAI(false) suppression
-- while bonding (see that file's seventeenth-pass note).
local TICK_INTERVAL_MS = 1500          -- how often the follower tick runs (move order + distance check)
-- Hundred-and-eighty-sixth pass (2026-09-05): Dragón's real target —
-- 10/tick "seems too high," dropped to 5 per tick (~1.5s) for now.
-- Hundred-and-ninety-ninth pass (2026-09-06): dropped again, 5 -> 2 —
-- Dragón's explicit ask, still too fast, not leaving enough of a real
-- window between the follow trigger and the capture trigger to actually
-- test/observe following and combat-assist behavior before the Pal gets
-- captured (confirmed by this same session's log: every Pal that started
-- following also got captured within the same short session). Still his
-- to retune live. NOT scaled by the level-gap multiplier (multiplier now
-- only affects the bonding threshold size, not individual gains — see
-- BONDING_TRIGGER_THRESHOLD_BASE).
-- ===================================================================
-- BALANCE VERIFICATION MODE (two-hundred-and-seventh pass, 2026-09-06)
-- ===================================================================
-- Paired with Interaction.lua's BALANCE_VERIFICATION_MODE — flip both back
-- together. See Trust.ComputeLevelMultiplier for what the first one does.
local LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST = true

-- Passive gain is also silenced during the verification run, and this is
-- NOT cosmetic — it would corrupt the test. At 100 per interaction against
-- a 500 threshold, the 3rd interaction crosses 50% (300 >= 250) and the Pal
-- starts following, at which point passive gain begins adding 2 every 1.5s
-- on its own. By the 5th interaction the total would already be past 500
-- from passive drip alone, so a capture at "5" would prove nothing and a
-- capture at 4 would look like a grant bug that isn't one. Restore to 2
-- when BALANCE_VERIFICATION_MODE goes off.
local REAL_PASSIVE_FRIENDSHIP_PER_TICK = 2
local PASSIVE_FRIENDSHIP_PER_TICK = LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST and 0 or REAL_PASSIVE_FRIENDSHIP_PER_TICK
-- Hundred-and-eighty-fifth pass (2026-09-05): rescaled after Dragón's
-- simplification (small vanilla-scale bonding numbers, one lump bonus
-- at actual capture — see BONDING_TRIGGER_THRESHOLD_BASE and
-- CAPTURE_BONUS_TARGET_POINT below). Roughly 5x the real vanilla
-- Petting amount (30), keeping Dragón's original "damage ≈ 5x pet"
-- ratio, just at the new vanilla scale instead of the old 1000-point
-- draft's. Damage from the PLAYER specifically is handled separately as
-- a full reset to 0 ("betrayal") — see OnFollowerDamaged below — not
-- scaled by this constant at all.
local DAMAGE_FRIENDSHIP_PENALTY = -150
-- Two-hundred-and-twenty-fifth pass: while a follow mechanism is unproven, a
-- drift stops the following but does not destroy the bond. See the branch that
-- uses this below.
local EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS = true
local MAX_FOLLOW_DISTANCE = 3000.0     -- Unreal units (~30m) before a following Pal loses all trust

-- Hundred-and-eighty-sixth pass (2026-09-05): Dragón's real target —
-- 500 (was 100 in the previous pass, before his exact multiplier tiers
-- were pinned down). The level-gap multiplier scales THIS threshold
-- (bigger bar for a much-higher-level Pal, smaller for a much-lower-level
-- one) rather than each individual gain — so Pet/Play/Feed/Peach amounts
-- stay untouched, real, and vanilla-scale regardless of level; only how
-- MUCH of them is needed changes.
local BONDING_TRIGGER_THRESHOLD_BASE = 500

-- Once the bonding threshold above is reached, the Pal is captured for
-- real (Capture.OnTrustMaxed) AND — Dragón's own words — "just then we
-- give enough xp to push past the friendship levels to 3 or higher if
-- we want": a one-time lump bonus so the newly-captured Pal's REAL
-- FriendshipPoint total lands at this real vanilla milestone (Rank 3,
-- from the friendship-rank curve retrieved this session) instead of
-- whatever the small bonding total happened to be. Never reduces the
-- total — a Pal that already exceeded this via peach use keeps its
-- higher real total.
local CAPTURE_BONUS_TARGET_POINT = 21000

-- Kept for anything that still wants the plain post-capture rank-3
-- target as a named constant (e.g. Indicator.lua's bar ratio, which
-- shows progress toward the BONDING threshold today — see its own
-- pass-185 note on why it still uses the small number, not this one).
local CAPTURE_AT_FRIENDSHIP_POINT = BONDING_TRIGGER_THRESHOLD_BASE

-- Fifty-seventh pass (2026-09-03, Indicator.lua): exposed so the on-screen
-- trust bar can compute the same ratio (FriendshipPoint / this) this file
-- already uses for its own capture check, instead of duplicating the
-- number and risking the two drifting apart if it's ever retuned here.
Trust.CAPTURE_AT_FRIENDSHIP_POINT = CAPTURE_AT_FRIENDSHIP_POINT

-- key (GetFullName()) -> { interactionCount, isFollowing, lastRank, lastPoint, pal, tickCount }
local State = {}

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end

local function get_key(pal)
    return safe_call(function() return pal:GetFullName() end)
end

local function get_state(pal)
    local key = get_key(pal)
    if not key then return nil, nil end
    local st = State[key]
    if not st then
        st = { interactionCount = 0, isFollowing = false, lastRank = 0, lastPoint = 0, pal = pal, tickCount = 0, captureTriggered = false }
        State[key] = st
    else
        st.pal = pal -- refresh in case this call handed us a new Lua wrapper for the same actor
    end
    return st, key
end

-- Hundred-and-ninetieth pass (2026-09-05): Dragón's follow-up to the
-- threshold-caching fixes — the trust BAR ITSELF shouldn't be built at
-- all for a Pal that's never been interacted with, not just skip the
-- expensive level-multiplier part. This is the cheap, read-only check
-- Indicator.lua needs to gate bar CONSTRUCTION on: a plain table lookup
-- (no actor/component resolution of its own), safe to call every scan
-- tick for every visible gauge without reintroducing any real cost.
function Trust.HasBondingState(palActor)
    local key = get_key(palActor)
    return key ~= nil and State[key] ~= nil
end

local function get_individual_parameter(pal)
    local comp = safe_call(function() return pal.CharacterParameterComponent end)
    if not comp or not comp:IsValid() then return nil end
    return safe_call(function() return comp:GetIndividualParameter() end)
end

-- Hundred-and-eighty-fourth pass (2026-09-05): Dragón's real per-level
-- balance spec — "if pal level is higher than player level by 20+,
-- values gained = x0.2 ... by 10+ = x0.5 ... roughly equal = x1 ...
-- lower by 10+ = bar x0.5 ... lower by 20+ = bar x0.25." Note the
-- direction: this is now a BAR-SIZE multiplier (bigger number = a
-- bigger/harder bonding threshold), the mirror image of the original
-- "scale each gain" idea from the first draft — a higher-level Pal
-- needs a BIGGER bar filled with the same small real gains, instead of
-- smaller gains against the same bar. Applies ONLY to the bonding
-- threshold (get_bonding_threshold below) — never to individual
-- Pet/Play/Feed/Peach amounts, the damage penalty, or the
-- player-betrayal reset, all of which stay flat regardless of level.
--
-- Dragón's five named breakpoints leave small gaps undefined (e.g. a
-- level gap of exactly 6, or -7) — filled here by defaulting to the
-- "roughly equal" x1 tier for anything that doesn't clear a more
-- extreme threshold, rather than interpolating between tiers. Flagged
-- directly since this is an interpretation, not something Dragón
-- specified exactly — easy to sharpen the cutoffs later if he wants a
-- stricter boundary than "closest named tier wins."
--
-- Mid-testing override, Dragón's own explicit ask ("for easy mode
-- switch and while we do tests, put me a 10x despite level difference
-- with pals"): note this INVERTS to 1/10 here, not 10 — since this
-- function now returns a BAR-SIZE multiplier (bigger = harder), making
-- testing "10x easier/faster" means shrinking the bar to a tenth of its
-- base size, not growing it tenfold. The intent (10x easier while
-- testing) is the same as Dragón asked for; the literal number changed
-- because what this function represents changed under it.
local EASY_TEST_SPEEDUP = 10

-- Hundred-and-eighty-eighth pass (2026-09-05): Dragón caught a real,
-- serious lag bug — this function was being called fresh every single
-- tick for EVERY Pal with a visible trust bar (Indicator.lua's
-- get_friendship_ratio, called from update_trust_bars, itself called
-- every scan tick for every tracked bar), not just Pals actually being
-- bonded with. Each call did a real component lookup + field read on
-- the Pal AND a fresh FindFirstOf("PalPlayerCharacter") + another
-- component lookup on the PLAYER, every time — cost that scales
-- directly with how many Pals are on screen, exactly the kind of
-- per-frame/per-tick-real-work-instead-of-a-cached-read mistake this
-- project has hit and fixed several times before (SelectResponseBySenses,
-- UpdateInteractTargetName, the old per-tick trust-bar full rebuild).
-- Dragón's own diagnosis and fix: "it should be calculated on the
-- interactions... maybe saved in the cache." A Pal's level never
-- changes mid-session, so once computed for a given Pal it's cached
-- PERMANENTLY here, keyed by the same GetFullName() identity already
-- used throughout this file — any later call (whether from a real
-- interaction or the bar just wanting to display something) is then a
-- cheap table lookup, not a fresh computation. Only real staleness risk:
-- if the PLAYER levels up mid-session, already-cached Pals keep the
-- multiplier computed against the player's old level. Accepted
-- trade-off — a rare, minor imprecision against a real, definite,
-- scales-with-Pal-count lag source.
local LevelMultiplierCache = {}

function Trust.ComputeLevelMultiplier(palActor)
    -- Two-hundred-and-seventh pass (2026-09-06): Dragón's balance
    -- verification run, his own design — "turn off the multipliers by level
    -- for now, so i can test the base with all and any pal." With this on,
    -- every Pal's bonding threshold is exactly BONDING_TRIGGER_THRESHOLD_BASE
    -- (500) regardless of its level or the player's, so 5 interactions worth
    -- 100 each capture ANY Pal and a wrong count points at a wrong grant
    -- rather than at level scaling. Set back to false together with
    -- Interaction.lua's BALANCE_VERIFICATION_MODE.
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

    local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
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
    elseif gap <= -20 then
        multiplier = 0.25
    elseif gap <= -10 then
        multiplier = 0.5
    else
        multiplier = 1.0
    end

    if cacheKey then LevelMultiplierCache[cacheKey] = multiplier end

    Logger.log(string.format(
        "[PalBonds/Trust] [LEVEL-MULT] pal level=%d player level=%d gap=%d -> multiplier=%.1fx",
        palLevel, playerLevel, gap, multiplier
    ))
    return multiplier
end

-- Shared by OnInteractionSucceeded (right after a pet/feed) and
-- tick_followers (right after passive gain) — the threshold can be
-- crossed by either path now, not just a pet/feed. `captureTriggered`
-- guards against firing more than once for the same Pal (a following
-- Pal that's already past 55 would otherwise re-trigger on every
-- subsequent pet or every passive-gain tick).
-- Hundred-and-eighty-sixth pass (2026-09-05): the trigger threshold is
-- now PER-PAL (BONDING_TRIGGER_THRESHOLD_BASE × that Pal's own
-- level-gap multiplier — a MULTIPLY now that ComputeLevelMultiplier
-- returns a direct bar-size multiplier, not a divide against a
-- gain-style multiplier as in the previous pass) rather than the flat
-- constant this used to compare against directly — exposed so
-- GetFollowingSnapshot below can show the bar against the SAME number
-- this function actually checks, not a global average.
local function get_bonding_threshold(pal)
    local multiplier = Trust.ComputeLevelMultiplier(pal)
    if multiplier == nil or multiplier <= 0 then multiplier = 1.0 end
    return BONDING_TRIGGER_THRESHOLD_BASE * multiplier
end

-- Hundred-and-ninety-fifth pass (2026-09-05): Dragón's report — feeding a
-- Kinship Peach via the real inventory-based Feed path filled the WHOLE
-- bar in one lump grant, and the real capture fired instantly, before
-- the vanilla eat/feed/happy animation had any chance to play — the Pal
-- just vanished mid-menu-close, with none of the real animations
-- (player feeding gesture, Pal eating, Pal happy reaction) ever showing.
-- Root cause: this used to call Capture.OnTrustMaxed synchronously, the
-- instant the threshold was crossed, with zero regard for whatever real
-- animation might still be playing on the Pal. Not peach-specific — any
-- threshold crossing could in principle cut an animation short — the
-- peach's single large grant just made it happen every time instead of
-- occasionally.
--
-- Dragón's own preference, in order: (1) wait for the real animation to
-- actually FINISH rather than a fixed delay — handles Pals with
-- different animation lengths, and feels more natural in the taming
-- flow — falling back to (2) a flat 5-second delay only if (1) isn't
-- achievable.
--
-- Hundred-and-ninety-sixth pass (2026-09-05) FIX ATTEMPT #1: the first
-- attempt at (1), `ActionComponent:ActionIsEmpty()`, is CONFIRMED
-- UNRELIABLE for this specific purpose — Dragón's live test showed it
-- reporting idle within 0.5ms of starting to wait, while Combat.lua's own
-- [FOLLOW-DIAG] (reading the SAME Pal at almost the same instant) showed a
-- real, still-running AI action (`BP_AIActionPairCall_FeedItem_C`) via a
-- DIFFERENT component. Switched to `GetCurrentAction_BP()` becoming nil.
--
-- Hundred-and-ninety-eighth pass (2026-09-06) FIX ATTEMPT #2: attempt #1
-- over-corrected the OTHER way — 3/3 real captures hit the 20s safety cap,
-- because `GetCurrentAction_BP()` never once returned nil (a wild Pal's
-- AIActionComponent always has SOME baseline action — wander/graze —
-- occupying it). Switched to detecting a CHANGE in the action's identity
-- instead of waiting for nil.
--
-- Hundred-and-ninety-ninth pass (2026-09-06) FIX ATTEMPT #3, ABANDONING
-- the AIActionComponent signal entirely. Dragón's next real test (5
-- captures logged) showed attempt #2 is unreliable in THREE different new
-- ways, not just one: (a) one capture fired the instant the action
-- identity changed from the real Feed pair-call to a plain
-- `BP_AIAction_WildLife_C` — plausible, but with no way to confirm the
-- separate Happy reaction (which plays on `pal.ActionComponent`, a
-- DIFFERENT component this signal never looks at) had actually finished;
-- Dragón's own follow-up question was exactly this — does capturing the
-- instant the Feed AI-action ends risk cutting off the Happy reaction,
-- which is a real, un-checked risk with this whole approach; (b) one
-- capture fired the instant the identity changed from
-- `BP_AIAction_CombatPal_C` to a CHILD sub-action of that SAME parent
-- (`...CombatPal_C_2147406593.BP_AIAction_AnimationSideStep_C_...`) — the
-- Pal was still mid-combat, just transitioning to a combat sub-state, and
-- this signal wrongly read that as "the blocking action finished"; (c) one
-- capture never saw ANY change in 20 real seconds and just hit the safety
-- cap anyway, the exact failure mode attempt #2 was meant to fix. Three
-- different real failure shapes in one session is conclusive: this
-- component's "current action" value is simply too noisy/unpredictable a
-- signal for "did the Feed+Happy sequence finish," in either direction.
--
-- Real fix, honoring Dragón's own stated fallback order from the start of
-- this section ("(1) wait for the real animation... falling back to (2) a
-- flat delay only if (1) isn't achievable") — (1) has now been tried
-- three distinct ways (ActionIsEmpty, nil-check, identity-change) and
-- failed live each time, on the SAME two components already probed
-- everywhere else in this project. No available signal actually tracks
-- the Happy reaction specifically (it plays on a third, one-shot-action
-- system this project has never found a duration/completion readback for
-- either — the exact same wall already hit and accepted for Play's own
-- Happy follow-up, hook-points.md's "Hundred-and-forty-third pass",
-- solved there with a flat delay). Falling back to (2): a single flat
-- delay after the interaction that crossed the capture threshold, same
-- honest, already-proven-acceptable pattern as Play's own
-- `PLAY_HAPPY_FOLLOWUP_DELAY_MS`. Set slightly more generous than Play's
-- 3000ms since Feed's real sequence stacks eating THEN Happy (Play's delay
-- only ever needed to cover Happy alone, after an idle animation that had
-- already played) — Dragón's to retune live once he's actually watched a
-- few real captures against this number.
-- Two-hundredth pass (2026-09-06): Dragón's ask after the first real look
-- at this — bump 4000 -> 5000, tune further from there.
local CAPTURE_DELAY_FIXED_MS = 5000

local function finish_capture_now(pal, key, point)
    -- Hundred-and-eighty-fifth pass: Dragón's lump-sum capture bonus —
    -- "just then we give enough xp to push past the friendship levels to
    -- 3 or higher if we want." Applied right before the real capture call
    -- so the Pal's real FriendshipPoint already reflects it the moment it
    -- joins the party. Never reduces the total (a Pal that already
    -- exceeded CAPTURE_BONUS_TARGET_POINT via a Kinship Peach keeps its
    -- higher real value).
    local param = get_individual_parameter(pal)
    if param and param:IsValid() then
        local currentPoint = safe_call(function() return param:GetFriendshipPoint() end) or point
        local bonus = CAPTURE_BONUS_TARGET_POINT - currentPoint
        if bonus > 0 then
            safe_call(function() param:AddFriendShip(bonus, false) end)
            Logger.log(string.format(
                "[PalBonds/Trust] capture bonus applied — %d -> %d real FriendshipPoint (target %d)",
                currentPoint, currentPoint + bonus, CAPTURE_BONUS_TARGET_POINT
            ))
        end
    end

    local okReq, Capture = pcall(require, "Capture")
    if okReq and Capture.OnTrustMaxed then
        Capture.OnTrustMaxed(pal)
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

    -- Eighty-second pass (2026-09-03) CRITICAL FIX, second layer: even
    -- though OnInteractionSucceeded below now bails out for an
    -- already-owned Pal before ever creating/updating its State entry,
    -- this check is repeated here too (defense in depth — this function
    -- is also reached from tick_followers' passive-gain path
    -- independently) so the actual capture call is NEVER reachable for
    -- an owned Pal through any path, present or future. See Capture.lua's
    -- IsAlreadyOwned for the full incident writeup.
    local okReqGuard, CaptureGuard = pcall(require, "Capture")
    if okReqGuard and CaptureGuard.IsAlreadyOwned and CaptureGuard.IsAlreadyOwned(pal) then
        Logger.log(string.format(
            "[PalBonds/Trust] %s: friendship threshold reached but this Pal already has a real owner — refusing to fire the capture call",
            tostring(key)
        ))
        st.captureTriggered = true -- don't keep re-checking every tick for something we now know is owned
        return
    end

    st.captureTriggered = true
    st.isFollowing = false -- it's about to be a real party member, not our approximated bonding-follow state
    Logger.log(string.format(
        "[PalBonds/Trust] %s reached %s friendship (bonding threshold %.1f) — trust threshold for sphere-less capture met, waiting for its current animation to finish before capturing",
        tostring(key), tostring(point), threshold
    ))

    wait_for_animation_then_capture(pal, key, point)
end

-- Called by Interaction.lua (and, since the eighty-first pass, the real
-- vanilla worker-menu selection hook too) after EVERY successful pet or
-- feed.
--
-- Eighty-second pass (2026-09-03) CRITICAL FIX: this function used to
-- start with "Owned Pals just accumulate harmless state here for now" —
-- that assumption was WRONG. maybe_trigger_capture() below never actually
-- checked ownership, only the real FriendshipPoint value against
-- CAPTURE_AT_FRIENDSHIP_POINT (55). An already-owned, long-bonded Pal's
-- real FriendshipPoint is often far past that (Dragón's own Petallia:
-- 205866) — so calling this function for an owned Pal was ALWAYS
-- guaranteed to immediately fire Capture.OnTrustMaxed -> the real
-- PalCaptureSuccess -> a genuine re-capture attempt on a Pal that was
-- already his.
--
-- This bug existed since the thirty-ninth/forty-first pass but never
-- fired because F9/F10 were rarely if ever pressed on already-owned
-- Pals. It fired for real the moment the eighty-first pass wired a path
-- that DOES get used constantly on owned/base Pals (the vanilla "4"
-- worker-menu wheel) into this same function: confirmed live
-- (2026-09-03) — his boss-tier Petallia got auto-added to the party and
-- dropped capture-reward loot, and a second, lower-friendship Pal was
-- also silently re-captured. Full writeup in docs/hook-points.md's
-- eighty-second pass.
--
-- FIX: bail out immediately, before touching any state at all, if the
-- Pal already has a real owner (Capture.IsAlreadyOwned — same safe
-- field-read pattern as everywhere else in this project, fails toward
-- "treat as owned" on any doubt). This system is for wild Pals only.
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

    local param = get_individual_parameter(pal)
    local rank = param and param:IsValid() and safe_call(function() return param:GetFriendshipRank() end)
    local point = param and param:IsValid() and safe_call(function() return param:GetFriendshipPoint() end)

    st.interactionCount = st.interactionCount + 1
    if rank ~= nil then st.lastRank = rank end
    if point ~= nil then st.lastPoint = point end

    Logger.log(string.format(
        "[PalBonds/Trust] %s: interaction #%d recorded (real rank=%s, real point=%s)",
        key, st.interactionCount, tostring(rank), tostring(point)
    ))

    -- Hundred-and-ninety-fifth pass (2026-09-05): both triggers below are
    -- now fractions of the Pal's own bonding bar (get_bonding_threshold),
    -- replacing the old raw-interaction-count follow trigger and the old
    -- escape-only, first-interaction-only "won over" mechanic. Both need
    -- a real point value to evaluate against a real threshold — bail
    -- cleanly if either is unreadable this tick (next interaction/passive
    -- tick will just try again).
    local threshold = point ~= nil and get_bonding_threshold(pal)
    local ratio = (point ~= nil and threshold and threshold > 0) and (point / threshold) or nil

    if not st.isFollowing and ratio ~= nil and ratio >= FOLLOW_TRIGGER_RATIO then
        Trust.StartFollowing(pal, st, ratio)
    end

    if ratio ~= nil and ratio >= FRIENDLY_TRIGGER_RATIO then
        local okPersonality, Personality = pcall(require, "Personality")
        if okPersonality and Personality.MaybeBecomeFriendlyByBar then
            local palId = safe_call(Personality.GetStableId, pal)
            Personality.MaybeBecomeFriendlyByBar(palId, pal)
        end
    end

    maybe_trigger_capture(pal, st, key, point)
end

-- FORTY-THIRD PASS (2026-09-03): read by Indicator.lua once per rendered
-- frame (ReceiveDrawHUD) to draw the trust-progress bar. Deliberately a
-- cheap read of already-cached state (st.lastPoint, updated elsewhere by
-- OnInteractionSucceeded / tick_followers) rather than a fresh
-- GetFriendshipPoint() call per Pal per frame — ReceiveDrawHUD fires at
-- frame rate, and the thirty-third pass's SelectResponseBySenses incident
-- already taught this project what happens when a per-frame hook makes
-- real per-call work instead of a plain table read.
function Trust.GetFollowingSnapshot()
    local snapshot = {}
    for _, st in pairs(State) do
        if st.isFollowing and st.pal then
            local point = st.lastPoint or 0
            -- Hundred-and-eighty-fifth pass: per-Pal threshold, not the
            -- flat base — a higher-level Pal's bar should show progress
            -- toward ITS OWN (bigger) bonding threshold.
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

-- Hundred-and-eighty-ninth pass (2026-09-05): Dragón's sharper follow-up
-- to the previous pass's caching fix — even a ONE-TIME computation (and
-- cache write) per Pal is still wasted work for the vast majority of
-- Pals, which spawn and despawn in the background and are never
-- actually approached at all. "Only save the data of pals that are
-- being interacted — no interaction = no data needed besides the
-- rolled personality." So this now checks for a REAL Trust.State entry
-- (created only by an actual interaction, via get_state in
-- OnInteractionSucceeded/tick_followers) BEFORE ever touching
-- ComputeLevelMultiplier — a Pal nobody has interacted with yet just
-- shows progress against the flat, un-multiplied base (correct anyway,
-- since it has zero real progress to show), with zero per-Pal level
-- lookups and zero cache entries created for it. Only once a real
-- interaction creates a State entry does the real per-level threshold
-- (and its cache) ever get computed for that specific Pal.
-- Returns nil (not a fallback number) when this Pal has no real
-- interaction on record — Dragón, directly: "dont use a fallback, just
-- dont compute it at all - compute it only when you get the
-- interaction." Callers (Indicator.lua) must treat nil as "nothing to
-- show yet", not substitute a default and divide anyway.
function Trust.GetBondingThreshold(palActor)
    local key = safe_call(function() return palActor:GetFullName() end)
    if key == nil or State[key] == nil then
        return nil
    end
    return get_bonding_threshold(palActor)
end

-- Two-hundred-and-thirtieth pass (2026-09-07) — the bug that made F9 do
-- nothing on its first live test, and it is a chicken-and-egg of my own making.
--
-- Trust.GetBondingThreshold above returns nil for any Pal this file has never
-- tracked (`State[key] == nil`). That is CORRECT for its existing callers: the
-- trust bar and the follow bookkeeping use nil to mean "not a bonding Pal, draw
-- nothing". It is exactly wrong for F9, whose entire purpose is to act on a Pal
-- that has never been touched — so it asked for the bar size of a Pal that did
-- not have a bar yet, got nil, and refused to grant. Ten presses in Dragón's
-- run, every one logging "could not read this Pal's bonding threshold".
--
-- Rather than loosen GetBondingThreshold and change what nil means for its
-- existing callers, this exposes the underlying calculation, which never needed
-- state at all: get_bonding_threshold is just the base value times the level
-- multiplier. Any wild Pal has a well-defined bar size before it is ever
-- touched; only the PROGRESS along it requires state.
function Trust.ComputeBondingThresholdFor(palActor)
    if palActor == nil then return nil end
    return get_bonding_threshold(palActor)
end

function Trust.StartFollowing(pal, st, ratio)
    st = st or (select(1, get_state(pal)))
    if not st or st.isFollowing then return end
    st.isFollowing = true
    Logger.log(string.format(
        "[PalBonds/Trust] bonding bar crossed %.0f%% (ratio=%s) — this Pal should now start following the player",
        FOLLOW_TRIGGER_RATIO * 100, ratio and string.format("%.2f", ratio) or "unknown"
    ))
    local okReq, Combat = pcall(require, "Combat")
    if okReq and Combat.StartFollowing then
        Combat.StartFollowing(pal)
    end
end

-- "Soft" stop: no longer following, but NOT necessarily permanently
-- done (used nowhere yet in this pass — every current stop condition
-- also means permanent flee, see OnFollowerLostAllTrust below). Kept
-- separate from that so a future gentler stop condition has somewhere
-- to go without also permanently flagging the Pal.
function Trust.StopFollowing(pal, reason)
    local st = select(1, get_state(pal))
    if st then st.isFollowing = false end
    Logger.log("[PalBonds/Trust] follow stopped: " .. tostring(reason))
    local okReq, Combat = pcall(require, "Combat")
    if okReq and Combat.StopFollowing then
        Combat.StopFollowing(pal)
    end
end

-- Rank hit 0 while following (damage or distance) -> permanent, per
-- Dragón's spec ("if trust reaches 0, it should run away") and DESIGN.md
-- §3.6's existing "permanently flagged as uninterested" behavior.
local function on_follower_lost_all_trust(pal, reason)
    Trust.StopFollowing(pal, reason)
    local okReq, Capture = pcall(require, "Capture")
    if okReq and Capture.OnTrustLost then
        Capture.OnTrustLost(pal)
    end
end

-- Called (see Init's DamageEvent hook) whenever the real game reports
-- damage to a Pal we're tracking as following.
--
-- Hundred-and-eighty-fourth pass: `attackerIsPlayer` distinguishes
-- Dragón's two damage cases — a hit from another Pal/the environment
-- applies the normal DAMAGE_FRIENDSHIP_PENALTY chunk, but a hit dealt
-- BY THE PLAYER directly is treated as betrayal: an immediate, full
-- reset to 0 regardless of however much trust had built up, then the
-- same permanent-flee path as hitting rank 0 normally. Neither branch
-- is scaled by the level-gap multiplier — Dragón described this
-- penalty flat, only "values gained" get multiplied.
function Trust.OnFollowerDamaged(pal, attackerIsPlayer)
    local st = select(1, get_state(pal))
    if not st or not st.isFollowing then return end

    local param = get_individual_parameter(pal)
    if not param or not param:IsValid() then return end

    if attackerIsPlayer then
        local point = safe_call(function() return param:GetFriendshipPoint() end)
        Logger.log(string.format("[PalBonds/Trust] BETRAYAL — the player directly hit this bonding Pal (had %s points) — resetting trust to 0", tostring(point)))
        if point and point > 0 then
            safe_call(function() param:AddFriendShip(-point, false) end)
        end
        on_follower_lost_all_trust(pal, "hit by the player directly (betrayal)")
        return
    end

    Logger.log(string.format("[PalBonds/Trust] following Pal took damage — applying trust penalty (%d)", DAMAGE_FRIENDSHIP_PENALTY))
    safe_call(function() param:AddFriendShip(DAMAGE_FRIENDSHIP_PENALTY, false) end)

    local rank = safe_call(function() return param:GetFriendshipRank() end)
    if rank and rank <= 0 then
        on_follower_lost_all_trust(pal, "trust hit rank 0 after taking damage")
    end
end

-- Periodic tick for every currently-following Pal: issues a follow move
-- order (Combat.lua), applies passive trust gain every few ticks, and
-- checks distance from the player (leash break).
local function tick_followers()
    local player = FindFirstOf("PalPlayerCharacter")
    local playerLoc = player and safe_call(function() return player:K2_GetActorLocation() end)
    local okReq, Combat = pcall(require, "Combat")

    for key, st in pairs(State) do
        if st.isFollowing and st.pal then
            local stillValid = safe_call(function() return st.pal:IsValid() end)
            if stillValid then
                st.tickCount = st.tickCount + 1
                local lostAllTrust = false

                if playerLoc then
                    local palLoc = safe_call(function() return st.pal:K2_GetActorLocation() end)
                    if palLoc then
                        local dx, dy, dz = palLoc.X - playerLoc.X, palLoc.Y - playerLoc.Y, palLoc.Z - playerLoc.Z
                        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if dist > MAX_FOLLOW_DISTANCE then
                            Logger.log(string.format(
                                "[PalBonds/Trust] %s is %.0f units away (limit %.0f) — losing all trust",
                                key, dist, MAX_FOLLOW_DISTANCE
                            ))
                            -- Two-hundred-and-twenty-fifth pass (2026-09-07):
                            -- while an experimental follow mechanism is being
                            -- tested, a drift should NOT cost Dragón the bond.
                            -- He has now lost Pals to this twice (both
                            -- Petallias last run), and punishing him for a
                            -- mechanism that is still being proven is the
                            -- wrong trade — especially when the drift is the
                            -- experiment's result, not his mistake.
                            --
                            -- The distance check itself is untouched, so the
                            -- log line above still reports drift exactly as
                            -- before and the test signal is preserved. Only
                            -- the punishment is suspended. Set this back to
                            -- false once a follow mechanism is settled.
                            if EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS then
                                Logger.log("[PalBonds/Trust] drift recorded but trust NOT wiped — experimental follow mode (see the two-hundred-and-twenty-fifth pass)")
                            else
                                local param = get_individual_parameter(st.pal)
                                if param and param:IsValid() then
                                    local point = safe_call(function() return param:GetFriendshipPoint() end)
                                    if point and point > 0 then
                                        safe_call(function() param:AddFriendShip(-point, false) end)
                                    end
                                end
                            end
                            lostAllTrust = true
                        elseif okReq then
                            -- Two-hundred-and-second pass (2026-09-06): both
                            -- mechanisms are called from here every tick —
                            -- IssueFollowMoveOrder itself now no-ops when
                            -- USE_OLD_MOVE_ORDER_NUDGE is off (Combat.lua),
                            -- and TickRealOtomoFollow is the repeated push
                            -- for the composite mechanism agreed with
                            -- Dragón, replacing the old one-shot call that
                            -- used to fire only from Combat.StartFollowing.
                            if Combat.IssueFollowMoveOrder then
                                Combat.IssueFollowMoveOrder(st.pal, playerLoc, player) -- two-hundred-and-eleventh pass: actor passed for continuous move-to-actor following
                            end
                            if Combat.TickRealOtomoFollow then
                                Combat.TickRealOtomoFollow(st.pal, key)
                            end
                        end
                    end
                end

                if lostAllTrust then
                    on_follower_lost_all_trust(st.pal, "too far from player")
                else
                    -- Hundred-and-eighty-fifth pass: applied every tick
                    -- (not every Nth), a flat real vanilla-scale amount —
                    -- NOT scaled by the level-gap multiplier (that now
                    -- only affects the bonding threshold's size, not
                    -- individual gains, per Dragón's simplification).
                    local param = get_individual_parameter(st.pal)
                    if param and param:IsValid() then
                        safe_call(function() param:AddFriendShip(PASSIVE_FRIENDSHIP_PER_TICK, false) end)
                        -- FORTY-FIRST PASS: passive gain alone can now
                        -- cross CAPTURE_AT_FRIENDSHIP_POINT without
                        -- another pet/feed — check here too, not just in
                        -- OnInteractionSucceeded.
                        local newPoint = safe_call(function() return param:GetFriendshipPoint() end)
                        if newPoint ~= nil then st.lastPoint = newPoint end
                        maybe_trigger_capture(st.pal, st, key, newPoint)
                    end
                end
            end
        end
    end
end

function Trust.Init()
    Logger.log("[PalBonds/Trust] real hooks active — tracking interaction counts, rank, and follow state via the real FriendshipPoint/FriendshipRank system")

    -- Damage -> trust loss for following Pals. FPalDamageResult (the
    -- struct this function takes) is a plain POD (ints/pointers/FVector/
    -- small enums, NO embedded TArray/FString/TMap — confirmed in the
    -- SDK dump) so reading its .Defender field here is the same safe
    -- shape as every other field-read in this project, NOT the
    -- GetSaveParameter()-style whole-struct-by-value-return that caused
    -- the three real crashes — this is UE4SS handing us an ALREADY-
    -- PASSED-IN hook argument, the same mechanism used successfully for
    -- AddFriendShip's Value/ApplyPassiveSkill args.
    local okDamageWatch = pcall(function()
        RegisterHook("/Script/Pal.PalHate:DamageEvent", function(Context, DamageResult)
            local result = hook_get(DamageResult)
            if result == nil then return end
            local defender = safe_call(function() return result.Defender end)
            local attacker = safe_call(function() return result.Attacker end)
            local damage = safe_call(function() return result.Damage end)
            local defenderName = safe_call(function() return defender and defender:GetFullName() end)
            local attackerName = safe_call(function() return attacker and attacker:GetFullName() end)

            -- Hundred-and-ninety-first pass (2026-09-05): this used to log
            -- EVERY real DamageEvent unconditionally (the Eighteenth pass's
            -- original purpose was just proving the hook fires at all —
            -- that question has been closed for a very long time). Left
            -- unconditional, it logged every hit landed anywhere in the
            -- game world — wild Pals fighting each other, NPCs, anything —
            -- not just hits relevant to a Pal we're actually tracking.
            -- Dragón caught this as real log-volume waste. The real
            -- penalty logic below already gates on State[defenderName], so
            -- the log line now uses the exact same cheap table check
            -- before printing anything.
            -- Two-hundred-and-ninth pass (2026-09-06) — COMBAT ASSIST, real
            -- targeting. Dragón's report: companions now defend themselves
            -- but still "dont defend me". The missing piece was never the
            -- disposition (Damaged_* = Battle already works) — it was that a
            -- companion had no reason to consider the player's enemy its
            -- own.
            --
            -- This hook is the natural place to solve it: it already fires
            -- on every real damage event with both actors resolved, so
            -- whenever the player hits something (or something hits the
            -- player), that other actor IS the player's current enemy. No
            -- polling, no new scan — the information is already in hand.
            -- Combat.OnPlayerCombatTarget then pushes that actor onto every
            -- following companion's real UPalHate system.
            -- Two-hundred-and-fourteenth pass (2026-09-06) — FRIENDLY FIRE.
            -- Dragón's run: "at some point i think one of my followers
            -- accidentally hit another of my followers and they ended up
            -- fighting among everyone, it was chaos... they all died except
            -- one". That is the direct cost of Discover_* = Battle during the
            -- combat window: to a companion, another companion is just another
            -- Pal it noticed, so a stray AoE hit starts a war.
            --
            -- Fix at the source: if BOTH sides of a damage event are Pals we
            -- are bonding with, cancel the grudge immediately by pushing a
            -- large NEGATIVE hate both ways. (UPalHate::ResetHateAll exists but
            -- belongs to the Arena classes, not this one — checked, not
            -- guessed — so ChangeHate with a negative value is the available
            -- route, and negative AddFriendShip is already long-proven safe in
            -- this project, so a negative float here is the same shape.)
            do
                local aIsFollower = attackerName ~= nil and State[attackerName] ~= nil and State[attackerName].isFollowing
                local dIsFollower = defenderName ~= nil and State[defenderName] ~= nil and State[defenderName].isFollowing
                if aIsFollower and dIsFollower and attackerName ~= defenderName then
                    Logger.log("[PalBonds/Trust] [FRIENDLY-FIRE] two bonded companions hit each other — clearing the grudge both ways so they do not start a war")
                    local okC, CombatMod = pcall(require, "Combat")
                    if okC and CombatMod and CombatMod.ClearMutualHate then
                        safe_call(function() CombatMod.ClearMutualHate(attacker, defender) end)
                    end
                end
            end

            do
                -- Two-hundred-and-sixteenth pass (2026-09-06) — Dragón's
                -- edge case, applied at the outermost point too. This hook
                -- fires for EVERY damage event in the world, and the block
                -- below does a FindFirstOf plus a GetFullName on the player
                -- before it can even decide whether the event is relevant.
                -- With nothing following, none of that can lead anywhere, so
                -- skip it on a plain table check first. HasAnyFollower does no
                -- engine calls at all.
                local okHas, CombatCheck = pcall(require, "Combat")
                local anyFollowing = okHas and CombatCheck and CombatCheck.HasAnyFollower and CombatCheck.HasAnyFollower()
                local player = anyFollowing and safe_call(function() return FindFirstOf("PalPlayerCharacter") end) or nil
                local playerName = player and safe_call(function() return player:GetFullName() end)
                if playerName then
                    local enemy = nil
                    if attackerName == playerName then
                        enemy = defender          -- the player hit something
                    elseif defenderName == playerName then
                        enemy = attacker          -- something hit the player
                    end
                    if enemy ~= nil then
                        -- Two-hundred-and-eleventh pass (2026-09-06) — REAL
                        -- BUG FIX, and the reason [HATE-ASSIST] fired ZERO
                        -- times in Dragón's run. This file has no file-level
                        -- `Combat` local: every other call site uses the lazy
                        -- `pcall(require, "Combat")` pattern (see
                        -- StartFollowing/StopFollowing/tick_followers below).
                        -- The previous pass wrote `Combat.OnPlayerCombatTarget`
                        -- here as if the module were in scope, so it indexed a
                        -- nil GLOBAL, raised an error, and safe_call swallowed
                        -- it silently — every single time.
                        --
                        -- Worth recording because the wrong conclusion was
                        -- drawn from it: the zero was reported to Dragón as
                        -- "no companion followed long enough for a fight",
                        -- when in fact the call never ran at all. Combat
                        -- assist has still never actually been exercised.
                        local okCombatReq, CombatMod = pcall(require, "Combat")
                        if okCombatReq and CombatMod and CombatMod.OnPlayerCombatTarget then
                            safe_call(function() CombatMod.OnPlayerCombatTarget(enemy) end)
                        end
                    end
                end
            end

            if defenderName and State[defenderName] and State[defenderName].isFollowing then
                Logger.log(string.format(
                    "[PalBonds/Trust] [DAMAGE-WATCH] real DamageEvent fired — defender=%s attacker=%s damage=%s",
                    tostring(defenderName), tostring(attackerName), tostring(damage)
                ))

                -- Hundred-and-eighty-fourth pass: identify whether the
                -- PLAYER specifically dealt this hit (betrayal, see
                -- OnFollowerDamaged) vs. any other attacker (another Pal,
                -- environment) — same FullName-comparison technique
                -- already used throughout this project wherever reference
                -- equality on actors wasn't trusted (e.g. find_targeted_pal
                -- excluding the player by name, not by reference).
                local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
                local playerName = player and safe_call(function() return player:GetFullName() end)
                local attackerIsPlayer = (attackerName ~= nil and playerName ~= nil and attackerName == playerName)

                -- Two-hundred-and-eleventh pass (2026-09-06) — Dragón's call,
                -- and the log backs it up exactly. His run showed a bonded
                -- FlowerDoll take 21 damage from a wild PinkRabbit, eat the
                -- full -150 penalty, drop to zero trust and get force-tiered
                -- to "escape" — so instead of fighting back it fled, which is
                -- precisely the opposite of the companion behaviour being
                -- built.
                --
                -- His reasoning: "maybe we will need to remove that rule out,
                -- and only make them lose friendship if the player themselves
                -- hit them (the betrayal effect), since right now, in order
                -- for them to enter combat, first need to be hit by
                -- something." That is exactly right, and the rule is now
                -- self-defeating: the whole point of Damaged_* = Battle is
                -- that a companion gets hit and fights back, but the penalty
                -- destroyed the bond at the very moment that was supposed to
                -- happen.
                --
                -- So third-party damage no longer costs any trust at all.
                -- Betrayal (the player hitting their own bonding Pal) is
                -- untouched and still resets the bond outright — that is a
                -- deliberate player choice, not something the world did to
                -- them.
                if attackerIsPlayer then
                    Trust.OnFollowerDamaged(State[defenderName].pal, true)
                else
                    Logger.log("[PalBonds/Trust] following Pal was damaged by something other than the player — no trust penalty (two-hundred-and-eleventh pass: a companion getting hit is expected now that it fights back)")
                end
            end
        end)
    end)
    if not okDamageWatch then
        Logger.log("[PalBonds/Trust] could not install DamageEvent watch hook (name may need adjusting)")
    end

    -- EXPERIMENTAL: this project's first repeating timer. UE4SS exposes
    -- ExecuteInGameThreadWithDelay specifically so the callback runs on
    -- the GAME thread (touching UObjects off it is a real, different
    -- crash risk than anything hit so far) — but this UE4SS build's own
    -- error strings warn its underlying EngineTick/ProcessEvent hook can
    -- fail an AOB scan on some game versions, which would make this
    -- silently do nothing. Logged clearly either way; if
    -- "game-thread tick fired" never appears again after the first line,
    -- that's the signal to fall back to plain LoopAsync (works, but its
    -- callback thread isn't confirmed safe for touching Pal actors —
    -- guarded here with IsInGameThread() as a minimum precaution).
    local tickEverLogged = false
    local function scheduleTick()
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(TICK_INTERVAL_MS, function()
                -- Two-hundred-and-sixth pass (2026-09-06): this line used
                -- to log unconditionally, every 1.5s, forever — 396 lines
                -- in one 10-minute session, whether or not a single Pal
                -- was actually following. That is not free: Logger.lua
                -- flushes every line to disk immediately by design (so a
                -- hard crash can't lose it), so this was a forced
                -- synchronous disk write every 1.5s for the whole session.
                -- Its original purpose was proving the game-thread tick
                -- fires at all, which has been settled for a very long
                -- time. Now logged only once, the first time it fires
                -- (still answers "did the tick ever start?"), plus
                -- whenever there is real follower work to report.
                if not tickEverLogged then
                    tickEverLogged = true
                    Logger.log("[PalBonds/Trust] [TICK] game-thread tick fired (logged once — the tick is alive; further ticks stay silent unless a Pal is actually following)")
                end
                safe_call(tick_followers)
                scheduleTick()
            end)
        end)
        if not ok then
            Logger.log("[PalBonds/Trust] ExecuteInGameThreadWithDelay failed to schedule — falling back to LoopAsync")
            pcall(function()
                LoopAsync(TICK_INTERVAL_MS, function()
                    local inGameThread = true
                    pcall(function() inGameThread = IsInGameThread() end)
                    if inGameThread then
                        Logger.log("[PalBonds/Trust] [TICK] LoopAsync tick fired (game thread confirmed)")
                        safe_call(tick_followers)
                    else
                        Logger.log("[PalBonds/Trust] [TICK] LoopAsync tick fired OFF the game thread — skipping this tick (not touching Pal actors from here)")
                    end
                    return false -- false = keep looping
                end)
            end)
        end
    end
    scheduleTick()
end

-- TODO (future pass): kinship-peach-style big trust boost. Real hook
-- point identified but not wired up — UPalUtility:CanUseTargetGainFriendshipPoint
-- (WorldContextObject, IndividualParameter, Item) decides whether a given
-- item can grant friendship at all, and UPalAction_FeedItemToCharacter /
-- SelectedFeedingItem(ItemSlotId, Num) is the real item-driven feed path
-- (see hook-points.md, twelfth pass). Needs the specific item's real
-- FName, which needs either FModel or a live feed-and-log session to
-- discover, before this can special-case it.
function Trust.OnKinshipItemUsed(pal)
    -- Not implemented yet. See the TODO above this function.
end

return Trust
