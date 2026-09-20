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
-- Two-hundred-and-ninety-third pass: the HP watch no longer decides betrayal,
-- so its per-drop line is off by default. It would otherwise print on every
-- enemy hit a follower takes in a fight, which is most of a fight.
local HP_WATCH_VERBOSE = false
local TICK_INTERVAL_MS = 1500          

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
-- Two-hundred-and-thirty-ninth pass (2026-09-07) — RELEASE PREP. Dragón:
-- "lets turn back up the balance mode once more and lets remove the f9 instant
-- bond shortcut, also any other shortcut we are not using also remove it, just
-- leave the play interaction shortcut for now ... this is already endgame".
-- Level scaling back ON: a Pal far above the player's level should take
-- meaningfully longer to win over. Re-enabling this also restores the passive
-- gain below to its real 2 per tick.
local LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST = false

-- Passive gain is also silenced during the verification run, and this is
-- NOT cosmetic — it would corrupt the test. At 100 per interaction against
-- a 500 threshold, the 3rd interaction crosses 50% (300 >= 250) and the Pal
-- starts following, at which point passive gain begins adding 2 every 1.5s
-- on its own. By the 5th interaction the total would already be past 500
-- from passive drip alone, so a capture at "5" would prove nothing and a
-- capture at 4 would look like a grant bug that isn't one. Restore to 2
-- when BALANCE_VERIFICATION_MODE goes off.
-- Two-hundred-and-eighty-sixth pass (2026-09-09), Dragon's request: an F10
-- on/off switch for the passive drip, so a player can deliberately keep a pile
-- of followers instead of watching them bond their way into the party one by
-- one. His words: "not that is recommended but sounds like a fun availability".
--
-- Session-only and starts ON, matching how the F9 tag toggle already behaves --
-- nothing about it is written to the save, so a player who forgets they left it
-- off just gets the normal behaviour back on the next launch.
local passiveGainEnabled = true
local REAL_PASSIVE_FRIENDSHIP_PER_TICK = require("Settings").Get("PassivePerTick")  -- the player's settings file (2026-09-18)
local PASSIVE_FRIENDSHIP_PER_TICK = LEVEL_MULTIPLIER_DISABLED_FOR_BALANCE_TEST and 0 or REAL_PASSIVE_FRIENDSHIP_PER_TICK

-- Seconds between third-party-damage log lines per follower. A multi-hit
-- attack lands far faster than this; the hits are counted and reported in
-- the next line rather than each forcing its own disk flush.
local THIRD_PARTY_DAMAGE_LOG_INTERVAL = 2.0

-- Two-hundred-and-twenty-fifth pass: while a follow mechanism is unproven, a
-- drift stops the following but does not destroy the bond. See the branch that
-- uses this below.
-- Two-hundred-and-thirty-ninth pass: back to false for release. This was set
-- true while following was broken, so that a Pal drifting away because of OUR
-- bug did not also destroy the bond Dragón had just spent interactions
-- building. Following works now, so drifting out of range is once again a real
-- consequence the player is responsible for, which is the intended design.
local EXPERIMENTAL_FOLLOW_NO_TRUST_LOSS = false
local MAX_FOLLOW_DISTANCE = 3000.0

-- ===================================================================
-- THE GRACE PERIOD (three-hundred-and-twenty-third pass, 2026-09-12)
-- ===================================================================
-- Crossing the leash used to end the bond in the same instant, and run 27 shows
-- why that is too harsh to keep:
--
--     11:38:23  Ribbuny is 3074 units away but is away FIGHTING - trust untouched
--     11:38:38  player combat window closed
--     11:38:39  Ribbuny is 3886 units away - losing all trust
--
-- She was protected while the fight was on, the fight ended, and she was gone
-- one second later. She was never given a single tick in which to walk back.
-- The same shape took Petallia three minutes earlier, and Dragon's objection is
-- the correct one: "petallia was faster than me so there was no way for me to
-- catch her during combat". Losing a companion to a foot-speed difference is
-- not a decision the player ever got to make.
--
-- So the distance now starts a clock instead of ending the bond. While the
-- clock runs, the follow tick keeps running too (it used to be skipped entirely
-- past the leash, which meant nothing was even trying to bring the Pal back),
-- and Combat.lua's recall is force-marching it home on the fast loop. Only if
-- the Pal is STILL beyond the leash when the clock runs out does the bond end.
-- Coming back inside the leash at any point clears it with no penalty.
--
-- 2026-09-15: 15 -> 3 seconds, Dragón's call. He expected crossing the leash to
-- end the bond immediately (the pre-323 rule) and had not been asked about the
-- window applying to ordinary drift, only about the post-fight case it was
-- built for. Three seconds keeps the "walked back in time" escape that the
-- Petallia/Ribbuny incident needed, without giving the world 15 seconds in
-- which it can despawn the Pal before the bond resolves (see the abandoned-
-- status bug, 2026-09-15). Every log line and the in-game wording read this
-- constant, so they follow automatically.
local DRIFT_GRACE_SECONDS = 3.0
local driftingSince = {}

-- Friendly-fire accounting. The per-pair latch keeps the log readable (run 28
-- produced 53 events in two bursts) while the counter keeps the real number
-- visible, which is the mistake pass 322 made with the target-discipline latch.
local friendlyFireEvents = 0
local friendlyFirePairLogged = {}
function Trust.ReportFriendlyFire()
    local n = friendlyFireEvents
    friendlyFireEvents = 0
    friendlyFirePairLogged = {}
    return n
end

-- Hundred-and-eighty-sixth pass (2026-09-05): Dragón's real target —
-- 500 (was 100 in the previous pass, before his exact multiplier tiers
-- were pinned down). The level-gap multiplier scales THIS threshold
-- (bigger bar for a much-higher-level Pal, smaller for a much-lower-level
-- one) rather than each individual gain — so Pet/Play/Feed/Peach amounts
-- stay untouched, real, and vanilla-scale regardless of level; only how
-- MUCH of them is needed changes.
local BONDING_TRIGGER_THRESHOLD_BASE = 500

-- Share of a Pal's own bonding bar lost per direct hit from the player. At 0.5
-- a bond survives one accident and dies on the second hit, whatever the Pal's
-- level. See OnFollowerDamaged for the full reasoning.
local PLAYER_HIT_PENALTY_FRACTION = 0.5

-- ===================================================================
-- OWN TRUST POINTS (2026-09-18, Dragón's rework)
-- ===================================================================
-- The bar used to BE the game's own friendship value (FriendshipPoint on the
-- Pal's IndividualParameter): every grant was an AddFriendShip and every read a
-- GetFriendshipPoint, a reflection call into the engine each time. The game
-- also added to that value on its own (a vanilla pet gives +10), so the bar was
-- never entirely ours.
--
-- Now PalBonds keeps its own number, `st.points`, in the same per-Pal record as
-- the rest of the bonding state below. Every amount is unchanged (Pet 50, Play
-- 50, Feed 60-100, Peaches 250/500, passive +2 per tick, the level and boss
-- multipliers on the bar size). Reading it is a table lookup.
--
-- The game's friendship is touched in exactly ONE place now: the flat join
-- bonus in Capture.OnTrustMaxed, when the Pal becomes the player's. The old
-- raise-to-21000 (rank 3) that ran just before it is gone -- Dragón: "it
-- shouldn't be 2 bonuses, only one".
--
-- Lifetime: a record lives until the Pal joins (ForgetBonding) or the world
-- changes (ResetForNewWorld), exactly like the rest of this state. Wild Pals are
-- rebuilt when a world loads, so nothing is lost there that the game kept.

-- key (GetFullName()) -> { interactionCount, isFollowing, points, pal, tickCount, ... }
local State = {}

-- key -> token for a Pal on its short 20% Friendly follow (Trust.StartBriefFollow).
-- Declared up here, next to State, so ResetForNewWorld below clears THIS table.
-- It used to be declared further down, which made the reset's `briefFollow = {}`
-- write a stray global and leave the real table untouched (found 2026-09-18).
local briefFollow = {}

-- ===================================================================
-- THE WORLD-WIDE DAMAGE HOOK NEEDS A CHEAPER GATE (pass 331, 2026-09-12)
-- ===================================================================
-- Dragón asked the right question: "at some point i felt lag without fighting,
-- just by looking at a few wild pals in the distance fight - you're not
-- tracking every fight right? just the ones of my followers and me right?"
--
-- We were tracking every fight. /Script/Pal.PalHate:DamageEvent fires for EVERY
-- damage event in the world, and its existing cheap exit is `next(State) == nil`
-- -- but State holds an entry for every Pal the player has ever interacted
-- with, so after the very first pet of the session it is never empty again.
-- From that point on, every hit between any two wild Pals anywhere near him
-- paid for TWO GetFullName() calls, and GetFullName is a reflection round-trip
-- that builds a full path string. This project has already identified that
-- exact call as its most expensive operation, twice.
--
-- So the gate is now an ADDRESS check. GetAddress() is a pointer read rather
-- than a string build, and the set of addresses we care about is tiny (the Pals
-- being bonded with). Rebuilt at most once a second, which for a handful of
-- Pals is a few pointer reads -- nothing against two path builds per hit in a
-- world full of fighting Pals.
--
-- SAFETY NOTE on address reuse: a stale address can only ever produce a FALSE
-- POSITIVE, which costs one name build and is then rejected by the existing
-- name-based checks below. It can never cause a wrong decision, because nothing
-- downstream trusts the address for identity -- only for "might be worth
-- looking at".
local trackedAddresses = {}
local trackedAddressesAt = -99
local addressGateUsable = true
local TRACKED_ADDRESS_REFRESH_SECONDS = 1.0
local find_player   -- forward: defined below, called from refresh_tracked_addresses

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

    -- THE PLAYER BELONGS IN THIS SET, and leaving them out was a regression
    -- that switched combat assist off completely (run 31: zero [HATE-ASSIST]
    -- lines, one combat install in the whole session).
    --
    -- This hook is where the player's current enemy is discovered: whenever the
    -- player hits something, or something hits the player, that other actor IS
    -- the enemy, and Combat.OnPlayerCombatTarget pushes it onto the companions.
    -- In exactly that event NEITHER side is a bonded Pal -- the attacker is the
    -- player and the defender is a wild enemy -- so an address gate built only
    -- from State rejected the one event the whole feature depends on.
    --
    -- The lesson is about what the gate is FOR. It exists to skip fights the mod
    -- has no stake in (wild versus wild), not to skip the player.
    local player = find_player and find_player()
    if player ~= nil then
        local paddr = address_of(player)
        if paddr ~= nil then fresh[paddr] = true end
    end

    trackedAddresses = fresh

    -- FAIL OPEN, and this is the part that matters most.
    --
    -- If GetAddress() does not work on these objects for any reason, every
    -- lookup returns nil, the set comes back empty, and a gate that treats
    -- "not in the set" as "not ours" silently switches off trust penalties,
    -- friendly-fire detection and combat assist all at once -- with no error
    -- anywhere, because every call is inside a pcall. That is precisely the
    -- shape of failure this project keeps paying for, and it is unacceptable in
    -- a performance optimisation: the worst a speed-up may do is be slow.
    --
    -- So if we are tracking Pals but could not resolve a single address, the
    -- gate marks itself unusable and stops filtering entirely. The mod goes
    -- back to being correct-but-slower, and says so once.
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

-- True when this damage event could possibly concern us: a Pal we are bonding
-- with on either side, OR the player on either side (which is how the player's
-- current enemy is discovered for combat assist).
--
-- Deliberately permissive: when in doubt it says yes and the slower name-based
-- checks decide. The only thing it is meant to reject outright is a fight
-- between two actors we have no stake in at all.
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

-- ===========================================================================
-- SAFER PLAYER LOOKUP (two-hundred-and-ninety-second pass, 2026-09-09)
-- ===========================================================================
-- Dragon crashed on death and respawn, and this one is NOT the world-change
-- crash that was fixed earlier -- different fault address, different stack:
--
--     EXCEPTION_ACCESS_VIOLATION reading address 0x10
--     31 consecutive UE4SS frames, then Palworld
--
-- 0x10 is UObjectBase::ClassPrivate -- his own UE4SS startup log prints exactly
-- that offset. So something read Object->ClassPrivate on a NULL object, deep
-- inside UE4SS itself rather than in game code.
--
-- That is the signature described in UE4SS issue #1328, by the same person who
-- found the out-of-bounds iteration bug:
--
--     "FindFirstOf also derefs Object/Class before validating, while FindAllOf
--      already guards, so that's worth a null check too."
--
-- FindFirstOf calls IsA on whatever the iteration hands back, without checking
-- it first. FindAllOf performs that check. Death is a bad moment to be walking
-- the object array -- the player actor is being destroyed while we look for it.
--
-- This cannot be fixed from Lua, so it is avoided instead: same lookup, via the
-- path that guards. Honest about the limits -- the upstream bug is unfixed and
-- this reduces exposure rather than removing it, and the deep UE4SS recursion
-- in that stack is not something a mod can reach at all.
-- ===========================================================================
-- CACHED, BECAUSE THIS WAS RUNNING ON EVERY HIT (2026-09-12, run 37)
-- ===========================================================================
-- Dragón: turning the log off changed nothing, and the lag tracks the hits
-- themselves, "possibly something that triggers on multihit attacks". It did:
-- FindAllOf walks the ENTIRE UObject array, and it ran up to three times per
-- damage event -- the betrayal hook, the damage hook's player-enemy branch and
-- its third-party branch each looked the player up afresh. A multi-hit attack
-- is dozens of events a second, so dozens of full object-array walks a second.
--
-- The player actor is now cached for PLAYER_CACHE_SECONDS and re-validated with
-- IsValid on every use, the same shape Combat's lastKnownPlayerActor has used
-- safely for months. A destroyed player (death, world change) fails IsValid and
-- triggers a fresh, still-guarded FindAllOf. The name is cached with it, so the
-- per-hit "is the attacker the player" test is a string compare, not another
-- reflection call.
--
-- 2026-09-15 (profiling): that 2-second cache still searched the whole world
-- on every second 1.5s Trust tick — ~27 object-array walks a minute at 40-100ms
-- each, whether or not anything was bonding. The lookup now lives in
-- PlayerRef.lua, shared by every module: the reference is kept until it goes
-- invalid and re-checked at most every 10s. Same IsValid-on-every-use
-- protection and the same FindAllOf-not-FindFirstOf rule as described above.
local PlayerRef = require("PlayerRef")
find_player = function()
    return PlayerRef.Get()
end
local function find_player_name()
    return PlayerRef.Name()
end

-- REMOVED for the stable build (2026-09-12): timed_hook and [HIT-COST], the
-- per-fight measurement of the two damage hooks. It confirmed the fix in run 38
-- (player lookups stopped scaling with hits) and cost a pcall plus two clock
-- reads on every damage event with nothing left to report to.
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
        st = { interactionCount = 0, isFollowing = false, points = 0, pal = pal, tickCount = 0, captureTriggered = false }
        State[key] = st
    else
        st.pal = pal 
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
-- the Pal AND a fresh find_player() + another
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

-- Pals the game shows a BOSS HP bar for (Indicator.lua's boss-bar hook), keyed
-- by full name. 2026-09-16, run 3: the "BOSS_" CharacterID prefix missed the
-- tower/gym Lyleen ("GYM_LilyQueen" got a 125 bar where the "BOSS_" Dark
-- Lyleen got 500), and Dragón's rule is every boss. The boss bar is the
-- game's own "this is a boss" (the UseBossHPGauge data flag), so seeing one
-- counts too.
local BossActorsSeen = {}
function Trust.MarkBossActor(palActor)
    local key = safe_call(function() return palActor:GetFullName() end)
    if key == nil or BossActorsSeen[key] then return end
    BossActorsSeen[key] = true
    -- A multiplier cached before the boss bar appeared was computed without x2.
    LevelMultiplierCache[key] = nil
end

-- Any of: a "BOSS_"/"GYM_"/"RAID_" CharacterID prefix, a "_BOSS"/"_GYM"/"_RAID"
-- Blueprint class (BP_LilyQueen_GYM_C, BP_MummyPal_BOSS_Predator_C, the raid
-- BP_LegendDeer_RAID_C in the object dump), or a boss bar seen.
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

    -- Two-hundred-and-forty-fourth pass (2026-09-07): ±5 steps added at Dragón's
    -- request. The old table had a single flat band from -9 to +9, so a Pal four
    -- levels above the player and one four levels below were identical, and
    -- nothing at all changed until a ten-level gap. That is a very wide stretch
    -- of "no difference" for a stat the player can see on every nameplate.
    --
    -- 1.5x for +5 sits evenly between 1.0 and the +10 step's 2.0. Dragón asked
    -- for 0.75x on the low side and was unsure it was the right inverse; it is
    -- the one that matches the curve's own shape — each step down roughly halves
    -- the distance to the next (1.0 -> 0.75 -> 0.5 -> 0.25), the same way each
    -- step up doubles it.
    --
    --   gap >= +20 ...... 4.00x   much harder
    --   gap >= +10 ...... 2.00x
    --   gap >=  +5 ...... 1.50x
    --   -4 .. +4 ........ 1.00x   unchanged
    --   gap <=  -5 ...... 0.75x
    --   gap <= -10 ...... 0.50x
    --   gap <= -20 ...... 0.25x   much easier
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
    -- ALPHA / BOSS PALS: double bar on top of the level multiplier (2026-09-12).
    -- Dragón: "bosses should always have 2x friendship bar required on top of
    -- the normal multiplier". Wild alphas carry a "BOSS_" CharacterID
    -- ("BOSS_GrassMammoth", already relied on by Capture.lua's name lookup);
    -- the data table's IsBoss column is the same fact. Lucky Pals (IsRarePal)
    -- are a different flag and are not affected.
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
        -- %.2f, not %.1f: the real multipliers include 0.75 and 0.25, which
        -- %.1f printed as "0.8x" and "0.2x". The maths was always right, but the
        -- log said a number that is not in the table above, and this project has
        -- twice reached a wrong conclusion from a misleading log line. The bar
        -- size is printed alongside so the number can be checked directly
        -- against the ratios in the lines that follow.
        "[PalBonds/Trust] [LEVEL-MULT] pal level=%d player level=%d gap=%d id=%s%s -> multiplier=%.2fx (bonding bar = %.0f)",
        palLevel, playerLevel, gap, tostring(charIdText), isBoss and " (BOSS: bar x2)" or "",
        multiplier, BONDING_TRIGGER_THRESHOLD_BASE * multiplier
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

    -- The only friendship the game gets is Capture.OnTrustMaxed's flat join
    -- bonus. The raise to rank 3 that used to run here is removed (2026-09-18).
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
    local point = st.points or 0
    st.interactionCount = st.interactionCount + 1

    -- Hundred-and-ninety-fifth pass (2026-09-05): both triggers below are
    -- now fractions of the Pal's own bonding bar (get_bonding_threshold),
    -- replacing the old raw-interaction-count follow trigger and the old
    -- escape-only, first-interaction-only "won over" mechanic.
    local threshold = get_bonding_threshold(pal)
    local ratio = (threshold and threshold > 0) and (point / threshold) or nil
    Logger.log(string.format(
        "[PalBonds/Trust] %s: interaction #%d recorded (trust %d / %s = %s)",
        key, st.interactionCount, point, tostring(threshold),
        ratio and string.format("%.0f%%", ratio * 100) or "unknown"
    ))
    if not st.isFollowing and ratio ~= nil and ratio >= FOLLOW_TRIGGER_RATIO then
        -- An interaction that jumps straight to 100% (a Kinship Peach) also
        -- starts the follow here, but the Pal is about to join: skip the
        -- "starts following you" message so only the join message shows
        -- (Dragón, 2026-09-18). The follow itself still starts, as it always
        -- has, for the few seconds before the join.
        local joinsNow = not st.captureTriggered and ratio >= 1
        Trust.StartFollowing(pal, st, ratio, joinsNow)
    end
    -- Two-hundred-and-ninety-sixth pass (2026-09-11): `not st.isFollowing` is
    -- new, and it fixes a real preset clobber Dragón's log caught.
    --
    -- The 50% follow trigger above applies the COMPANION preset (player slots
    -- Ignore, other Discover slots Battle). This 20% trigger then swapped the
    -- real preset to plain 'friendly'. Normally the two fire on different
    -- interactions and nobody notices — but a low-level Pal can cross both
    -- thresholds on a SINGLE interaction, and then these run back to back and
    -- the companion preset is overwritten microseconds after being applied.
    -- Dragón's log shows it exactly: "[COMPANION] now has a companion preset"
    -- immediately followed by "[WON-OVER] (was 'companion_combat') ... real
    -- AIResponsePreset ALSO swapped to friendly".
    --
    -- Once a Pal is following, 'friendly' is a DOWNGRADE from 'companion' —
    -- it is the disposition of a wild Pal that likes you, not of one fighting
    -- at your side. Nothing is lost by skipping it: a follower is already past
    -- the friendly threshold by definition.
    if ratio ~= nil and ratio >= FRIENDLY_TRIGGER_RATIO and not st.isFollowing then
        local okPersonality, Personality = pcall(require, "Personality")
        if okPersonality and Personality.MaybeBecomeFriendlyByBar then
            local palId = safe_call(Personality.GetStableId, pal)
            Personality.MaybeBecomeFriendlyByBar(palId, pal)
        end
    end
    maybe_trigger_capture(pal, st, key, point)
end

-- Two-hundred-and-fiftieth pass (2026-09-07) — Dragon: "both full bond toast and
-- abandoned toast appeared on screen <- why abandoned too xd?"
--
-- Because a captured Pal leaves the world while this file still holds bonding
-- state for it. The log shows all four lines inside one second: join message,
-- no longer following, "follow stopped: too far from player", bond-lost. The
-- actor was already gone, so the follower tick's distance came back enormous and
-- the leash-break branch called it abandonment -- congratulating the player and
-- then telling them off for the very same event.
--
-- Fixed at the source rather than by teaching the distance check to recognise
-- captures: once a Pal has joined the party it is not a bonding Pal any more, so
-- this file should have nothing left to say about it. Capture.OnTrustMaxed calls
-- this immediately after the capture, in the same synchronous callback, so the
-- tick can never see the in-between state.
function Trust.ForgetBonding(pal)
    local key = safe_call(function() return pal:GetFullName() end)
    if key == nil or State[key] == nil then return end
    State[key] = nil
    LevelMultiplierCache[key] = nil
    Logger.log("[PalBonds/Trust] " .. tostring(key) .. " joined the party — dropping its bonding state so the follower tick stops tracking it")
end

-- Two-hundred-and-seventy-fifth pass: every entry in State points at an actor
-- from the world that is going away. See Combat's WORLD CHANGE RESET comment.
function Trust.ResetForNewWorld()
    local n = 0
    for _ in pairs(State) do n = n + 1 end
    State = {}
    LevelMultiplierCache = {}
    BossActorsSeen = {}
    briefFollow = {}
    Logger.log("[PalBonds/Trust] [WORLD-RESET] dropped " .. n .. " bonding record(s) from the old world")
end

-- Returns the new state so the caller can tell the player which way it went.
function Trust.TogglePassiveFriendshipGain()
    passiveGainEnabled = not passiveGainEnabled
    Logger.log("[PalBonds/Trust] [PASSIVE-TOGGLE] passive friendship gain is now " ..
        (passiveGainEnabled and "ON" or "OFF") ..
        " (" .. tostring(require("Settings").Get("KeyPassiveGain")) .. "; session-only, back to ON on the next launch)")
    return passiveGainEnabled
end
function Trust.IsPassiveGainEnabled()
    return passiveGainEnabled
end
function Trust.GetFollowingSnapshot()
    local snapshot = {}
    for _, st in pairs(State) do
        if st.isFollowing and st.pal then
            local point = st.points or 0

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

-- ===================================================================
-- READING AND CHANGING THE POINTS (own trust points, 2026-09-18)
-- ===================================================================
-- Every grant in the mod goes through Trust.AddPoints: Pet, Play and Feed
-- (Interaction.lua). The follower tick and the hit rules in this file change
-- st.points directly. Nothing here calls into the engine except the ownership
-- guard and the one GetFullName that finds the record.

function Trust.GetPoints(palActor)
    local key = get_key(palActor)
    local st = key ~= nil and State[key] or nil
    return st and st.points or 0
end

-- Returns before, after -- or nil when nothing was granted. Refuses an owned
-- Pal outright, the same hard guard every other real-effect path uses (see
-- OnInteractionSucceeded): the points are for wild Pals only.
function Trust.AddPoints(palActor, amount, label)
    if palActor == nil or type(amount) ~= "number" then return nil end
    local okReqGuard, CaptureGuard = pcall(require, "Capture")
    if okReqGuard and CaptureGuard.IsAlreadyOwned and CaptureGuard.IsAlreadyOwned(palActor) then
        Logger.log("[PalBonds/Trust] [POINTS] " .. tostring(label) .. ": this Pal already has a real owner — no points")
        return nil
    end
    local st, key = get_state(palActor)
    if not st then return nil end
    local before = st.points or 0
    local after = before + amount
    if after < 0 then after = 0 end
    st.points = after
    return before, after
end

-- The bar's fill, 0..1. A Pal with no record shows an empty bar without any
-- level lookup (Dragón's rule from pass 189: compute nothing until a real
-- interaction happens).
function Trust.GetBarRatio(palActor)
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

-- A Pal just became a real, bonded follower (50%). Both ways in go through
-- here: crossing 50% normally (StartFollowing) and crossing it during the 20%
-- calm-down, where the Pal simply keeps following (StartBriefFollow).
--   * Its name and gender are read now, while the Pal is certainly here: if it
--     despawns later the abandoned toast still has a name to show
--     (forget_despawned_pals). The calm-down path used to skip this.
--   * The player is told it is now following (Dragón, 2026-09-18).
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

-- `quiet`: no "starts following you" message (the Pal is joining right away).
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

-- ===================================================================
-- BRIEF FOLLOW AT 20% (2026-09-16, experiment, Dragón's go-ahead)
-- ===================================================================
-- Three ways of making a Friendly Pal stop attacking the player failed in
-- live runs (ChangeHate, player slots on Ignore, cancel + rest animation).
-- The one thing that worked every time was starting to follow: the Pal's hate
-- on the player was gone within ~3 s. So at 20% the Pal gets the REAL follow,
-- exactly as at 50%, for a short time, and is then released back to being a
-- wild Pal. Started straight away, while the pet is still playing, because
-- Combat will not install follow over a Pal it sees fighting — and both
-- successful cases in the logs started during a pet.
--
-- Released once the Pal no longer hates the player (after at least
-- BRIEF_FOLLOW_MIN_SECONDS, so it is visible), or at BRIEF_FOLLOW_MAX_SECONDS.
-- If the bar has passed 50% by then (a second pet during the brief follow),
-- the follow simply stays: that Pal has earned it.
local BRIEF_FOLLOW_MIN_SECONDS = 3.0
local BRIEF_FOLLOW_MAX_SECONDS = 15.0
local BRIEF_FOLLOW_POLL_MS = 500

function Trust.IsBriefFollowing(pal)
    local key = get_key(pal)
    return key ~= nil and briefFollow[key] ~= nil
end

-- onDone(calmed, elapsedSeconds, stayedFollowing) is called once at the end.
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
            -- Something else ended the follow first (bond lost, death).
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

-- Rank hit 0 while following (damage or distance) -> permanent, per
-- Dragón's spec ("if trust reaches 0, it should run away") and DESIGN.md
-- §3.6's existing "permanently flagged as uninterested" behavior.
local function on_follower_lost_all_trust(pal, reason)
    Trust.StopFollowing(pal, reason)
    local okReq, Capture = pcall(require, "Capture")
    if okReq and Capture.OnTrustLost then

        -- Two-hundred-and-forty-third pass: the reason is now forwarded so the
        -- player gets told WHICH mistake they made. The two call sites use
        -- "too far from player" and a damage reason; anything containing "far"
        -- is an abandonment, everything else is a betrayal.
        local kind = (type(reason) == "string" and reason:find("far")) and "abandoned" or "betrayed"
        Capture.OnTrustLost(pal, kind)
    end
end

-- Called by both damage hooks in Init when the PLAYER hits a Pal we are
-- tracking. Only the player's hits cost trust: the flat -150 for anything else
-- hitting a follower was removed on 2026-09-18 (Dragón: "since we now make the
-- pals fight together this shouldn't exist anymore"), and neither hook passes
-- attackerIsPlayer = false any more. The parameter stays so a caller cannot
-- accidentally turn a third-party hit into a betrayal.
-- Two-hundred-and-forty-sixth pass (2026-09-07) — Dragón: "one of the other
-- chikipis didnt feel betrayed even tho i hitted it multiple times, with my
-- fists and my axe".
--
-- The cause was the second half of the guard below: betrayal only applied to a
-- Pal that was already FOLLOWING, which means a bar past 50%. A Pal he had
-- petted once or twice — bonding, trusting him, showing a trust bar — could be
-- hit as often as he liked with no consequence at all. That is the wrong line to
-- draw: the bond starts at the first interaction, so betraying it should be
-- possible from the first interaction too.
--
-- The line that IS right is bonding state itself. A Pal with no bonding state
-- has never been touched by the player, and hitting one of those is just
-- ordinary Palworld combat — it must stay completely unaffected, or every wild
-- Pal the player ever fights would be poisoned and unbondable forever.
--
-- So: no state means no betrayal, any state means betrayal. get_state is
-- deliberately NOT used to make that test, because it CREATES state for a Pal
-- that has none, which would hand every Pal in a fight exactly the bonding
-- record this check is trying to look for.
-- Two-hundred-and-fifty-sixth pass (2026-09-07) — REVERTED to requiring an
-- actual FOLLOWER, at Dragon's call, and he is right that it should never have
-- changed.
--
-- Pass 246 widened this to "any Pal with a bond" because he had reported a
-- Chikipi that would not betray however hard he hit it, and I decided the follow
-- requirement was the blocker. He then corrected me -- that Chikipi WAS
-- following -- and the real cause turned out to be that neither damage hook
-- fired at all. The hook problem is now solved by watching health instead, but
-- the widening was never reverted. It was collateral from a wrong diagnosis and
-- had no evidence behind it at any point.
--
-- What it cost, from his run: a FERAL Cattiva attacking him wandered into a pet
-- aimed at a different Cattiva, picked up bonding state from that one accidental
-- pet, and from then on every single hit he landed defending himself spammed the
-- "its trust is shaken" toast. A Pal that is actively trying to kill you should
-- not be generating remorse messages.
--
-- Requiring a follower draws the line where the player would draw it: a Pal that
-- chose to walk with you can be betrayed; one that merely got touched once
-- cannot. That is also the original design, and the bar is visible, so the
-- player always knows which side of it a Pal is on.
-- ===================================================================
-- A PLAYER HIT ON A PAL THAT IS NOT BONDED (1.1.4, Dragón, 2026-09-18)
-- ===================================================================
-- "Bonding is a status that starts or should start at 50% friendship." Below
-- that there is nothing to betray, so no betrayal and no scarred status -- but
-- the hit is not free either: the bar drops to 0 ("since the wild pal will most
-- likely become hostile after that, drop it all"), and a Pal that had forgiven
-- the player at 20% goes back to the personality it had before
-- (Personality.RevertForgiveness). What it does about being hit is its own
-- natural reaction; nothing here tells it to fight or flee.
--
-- A Pal in its 20% calm-down is unbonded too, even though the calm-down marks
-- it as following: a hit there ends the calm-down on the spot, without the
-- Friendly preset ever being written.
--
-- Only the PLAYER's hits reach this; Pal-versus-Pal damage never costs trust
-- (his ruling, pass 211). Both damage hooks report the same hit, hence the
-- short dedupe.
local UNBONDED_HIT_DEDUPE_SECONDS = 1.0
local function on_unbonded_pal_hit_by_player(pal, st, key)
    local now = os.clock()
    if st.lastUnbondedHitAt ~= nil and (now - st.lastUnbondedHitAt) < UNBONDED_HIT_DEDUPE_SECONDS then return end
    st.lastUnbondedHitAt = now

    if briefFollow[key] ~= nil then
        -- The poll sees its token gone and stops without calling onDone, so
        -- the Friendly preset is never written for this Pal.
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

    -- The capture is already under way (the 5 s celebration, then the join).
    -- For a boss, Capture tells the game the player hit it so the defeat is
    -- recorded, which comes back through this very hook: without this, the
    -- mod would punish the player for its own capture -- half the bar gone and
    -- a "trust is shaken" toast in the middle of the join.
    if st.captureTriggered then return end

    -- A Pal that already fled for good (betrayed or abandoned) keeps what that
    -- did to it. Without this, the player hitting a betrayed Pal back reached
    -- the below-50% rule and RevertForgiveness put it back to its original
    -- personality, undoing the betrayal (2026-09-18, the Cattiva in Dragón's run;
    -- present since 1.1.4).
    local okCapFled, CaptureFled = pcall(require, "Capture")
    if okCapFled and CaptureFled and CaptureFled.HasPermanentlyFled
        and safe_call(function() return CaptureFled.HasPermanentlyFled(pal) end) then
        return
    end

    -- Below 50%, or in the 20% calm-down: no bond yet (see above).
    if attackerIsPlayer and (not st.isFollowing or briefFollow[key] ~= nil) then
        on_unbonded_pal_hit_by_player(pal, st, key)
        return
    end
    if not st.isFollowing or not attackerIsPlayer then return end
    do

        -- Two-hundred-and-forty-ninth pass (2026-09-07) — GRADUAL, at Dragón's
        -- call. This used to zero the bar on a single hit at any level: one
        -- stray swing, at 95% of the way to a bond, ended it permanently.
        --
        -- That was defensible while the detection was broken, because in
        -- practice it almost never fired. Now that the player-side hook catches
        -- every real hit, instant loss would trigger constantly and unfairly --
        -- followers stand a couple of metres behind the player and swing at the
        -- same enemies, so clipping one is going to happen.
        --
        -- Half the Pal's own bar per hit: an accident is survivable and visibly
        -- costly, two deliberate hits still end the bond. Scaled off the Pal's
        -- threshold rather than a flat number so it means the same thing at
        -- every level gap.
        local point = st.points or 0
        local threshold = get_bonding_threshold(pal) or BONDING_TRIGGER_THRESHOLD_BASE
        local penalty = math.ceil(threshold * PLAYER_HIT_PENALTY_FRACTION)
        if point - penalty > 0 then
            st.points = point - penalty
            Logger.log(string.format(
                "[PalBonds/Trust] the player hit a bonding Pal — trust %d -> %d (-%d, %.0f%% of its %d bar). The bond survives, for now.",
                point, point - penalty, penalty, PLAYER_HIT_PENALTY_FRACTION * 100, threshold
            ))

            -- Tell the player. Erosion the player cannot see is worse than
            -- instant loss: they would watch a bond quietly disappear with no
            -- idea they were causing it.
            -- One warning per Pal per few seconds. Health is sampled on the
            -- follower tick, so a sustained attack can reach this more than
            -- once before the second hit finishes the bond, and three identical
            -- toasts stacked on screen reads as a bug rather than a warning.
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

-- ===================================================================
-- A DESPAWNED PAL IS FORGOTTEN (2026-09-18, Dragón)
-- ===================================================================
-- "The pals are still wild so on world reload or even by teleporting away they
-- should despawn and that's fine, those don't need to be recorded unless still
-- inside the radius of the player area - so let them despawn normally, no need
-- to save their data."
--
-- So a record whose Pal is no longer in the world is dropped, points and all.
-- A Pal that despawns and comes back later starts from an empty bar.
--
-- A bonded FOLLOWER that despawns (the known spawner despawn when the player
-- travels far) ends its bond with the abandoned toast -- Dragón: "if a pal
-- despawn lets show the abandoned toast". Until now it was skipped silently
-- and kept counting as a follower until the next world change. Its name was
-- cached when it started following, because the actor can no longer be read,
-- and Combat drops its references by key without touching it. A Pal on its 20%
-- calm-down is not bonded, so it is forgotten quietly.
--
-- Cost: one IsValid per record per tick, and records exist only for Pals the
-- player has interacted with.
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
            if wasBonded then
                local okCap, CaptureD = pcall(require, "Capture")
                if okCap and CaptureD and CaptureD.NotifyBondLostByName then
                    safe_call(CaptureD.NotifyBondLostByName, st.displayName, "abandoned", st.displayFemale)
                end
            end
        end
    end
end

-- Periodic tick for every currently-following Pal: issues a follow move
-- order (Combat.lua), applies passive trust gain every few ticks, and
-- checks distance from the player (leash break).
local function tick_followers()

    -- Two-hundred-and-seventy-second pass: this tick touches every follower's
    -- actor, so it stops dead once the world is going away. See Combat's
    -- SHUTDOWN GUARD comment for why validity checks are not enough here.
    local okShut, CombatShut = pcall(require, "Combat")
    if okShut and CombatShut and CombatShut.IsShuttingDown and CombatShut.IsShuttingDown() then
        return
    end
    forget_despawned_pals()
    local player = find_player()
    local playerLoc = player and safe_call(function() return player:K2_GetActorLocation() end)
    local okReq, Combat = pcall(require, "Combat")
    for key, st in pairs(State) do
        if st.isFollowing and st.pal then
            local stillValid = safe_call(function() return st.pal:IsValid() end)
            if stillValid then
                st.tickCount = st.tickCount + 1

                -- ===========================================================
                -- DEATH, BEFORE ANYTHING ELSE (two-hundred-and-ninety-sixth
                -- pass, 2026-09-11)
                -- ===========================================================
                -- Until now nothing in the bond-loss path ever asked whether a
                -- follower was alive. A companion that died in combat kept its
                -- State entry, its corpse drifted past MAX_FOLLOW_DISTANCE, and
                -- the drift branch below declared it "abandoned" — so Dragón
                -- watched a Cawgnito die defending him and then got told it had
                -- been left behind and gave up on him.
                --
                -- Checked here, at the top, so a dead Pal never reaches the
                -- distance check, the passive gain, or the follow re-issue.
                -- `endedThisPass` guards the rest of this iteration, because
                -- ending the bond does not break out of the loop body — the
                -- same trap the two-hundred-and-sixty-fifth pass documents
                -- below, where a bond ended at the top of an iteration got a
                -- brand new follow action installed at the bottom of it.
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

                -- ===========================================================
                -- BETRAYAL BY HEALTH, NOT BY HOOK
                -- (two-hundred-and-fifty-third pass, 2026-09-07)
                -- ===========================================================
                -- Two hooks have now been tried and both registered perfectly
                -- and then never fired once: UPalHate::DamageEvent (silenced by
                -- the Damaged_Player = Ignore we set on every follower) and
                -- UPalDamageReactionComponent's processed-damage delegate. I was
                -- guessing at damage entry points and losing, so this stops
                -- guessing and watches the one thing that cannot lie or be
                -- suppressed: the Pal's health.
                --
                -- GetHPRate() is a plain float on a component this file already
                -- reads. Compared against the previous tick, a drop means the
                -- Pal was hurt, whatever the game's AI decided to feel about it.
                -- No hook, no reflection beyond one accessor, on a loop that was
                -- already running.
                --
                -- ATTRIBUTION, and this is a real design decision rather than a
                -- technical one, so it is stated plainly: health alone cannot
                -- say WHO landed the hit. The rule chosen is that a bond can
                -- only be broken OUTSIDE a fight. If the player is in an active
                -- combat window, a follower losing health is treated as the
                -- brawl it almost certainly is and costs nothing. With no fight
                -- happening, a bonded Pal standing next to you does not lose
                -- health by accident.
                --
                -- That is not merely a workaround for the attribution problem;
                -- it is arguably the better rule. Deliberately hitting a Pal
                -- that trusts you is a betrayal. Clipping it with a stray swing
                -- while three things are attacking you is not, and Dragon's own
                -- followers stand two metres behind him and fight the same
                -- enemies he does.
                do
                    local rate = safe_call(function()
                        local comp = st.pal.CharacterParameterComponent
                        if comp == nil or not comp:IsValid() then return nil end
                        return comp:GetHPRate()
                    end)
                    if type(rate) == "number" then
                        local prev = st.lastHPRate
                        st.lastHPRate = rate

                        -- 1% of max health, so healing ticks and float noise do
                        -- not register as a hit.
                        if prev ~= nil and rate < prev - 0.01 then

                            -- Two-hundred-and-ninety-third pass (2026-09-09) --
                            -- NO LONGER TREATED AS BETRAYAL. Dragon: "during
                            -- combat sometimes they achieved the betrayal, even
                            -- tho i never hit them and only the enemy pals
                            -- hitted them".
                            --
                            -- This branch GUESSED. It saw a health drop, asked
                            -- Combat.IsPlayerInCombat(), and if no fight was
                            -- registered it concluded the player must have done
                            -- it. That inference is wrong whenever a follower is
                            -- being mauled by a wild Pal while the player has not
                            -- personally hit or been hit recently -- which is the
                            -- common case, because that flag tracks the PLAYER's
                            -- fight, not the follower's. The Pal takes real
                            -- damage from an enemy, no fight is "in progress" by
                            -- that measure, and it is recorded as the player
                            -- betraying it.
                            --
                            -- It only existed as a fallback for when the real
                            -- damage hooks were not yet confirmed to fire on this
                            -- build. They are -- the delegate route logs
                            -- [BETRAYAL-HOOK] "this hook FIRES on this build" --
                            -- and BOTH of them compare the attacker's name
                            -- against the player's before counting anything.
                            -- Real attribution instead of a guess.
                            --
                            -- The HP reading itself is kept: st.lastHPRate is
                            -- still updated above, which is what the rest of the
                            -- follower logic reads.
                            if HP_WATCH_VERBOSE then
                                Logger.log(string.format(
                                    "[PalBonds/Trust] [HP-WATCH] %s lost health (%.2f -> %.2f) - recorded only; betrayal is decided by the damage hooks, which check who actually attacked",
                                    tostring(key), prev, rate
                                ))
                            end
                        end
                    end
                end
                local lostAllTrust = false
                if playerLoc and not endedThisPass then
                    local palLoc = safe_call(function() return st.pal:K2_GetActorLocation() end)
                    if palLoc then
                        local dx, dy, dz = palLoc.X - playerLoc.X, palLoc.Y - playerLoc.Y, palLoc.Z - playerLoc.Z
                        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                        -- Three-hundred-and-fourteenth pass (2026-09-12): a Pal
                        -- that is off fighting is not abandoning the player.
                        -- Combat.lua drops its follow action for the duration of
                        -- a fight (see [COMBAT-FREE]), which is exactly when it
                        -- will chase an enemy out of range. Dragón had to
                        -- physically run after chasing companions to stop them
                        -- being declared abandoned; that is not a mistake he
                        -- should be punished for. The suspension is time-capped
                        -- in Combat.lua, so this cannot be held open forever.
                        -- Combat.IsBusyFighting rather than IsSuspendedForCombat:
                        -- the suspension flag is mod bookkeeping and run 27
                        -- proved it can be wrong (target discipline was clearing
                        -- it every tick), whereas IsBusyFighting asks the Pal
                        -- what it is actually doing. IsSuspendedForCombat stays
                        -- as the fallback for an older Combat.lua.
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
                            -- First tick past the leash and not fighting: start
                            -- the clock, say so, and let the recall work.
                            driftingSince[key] = os.clock()
                            Logger.log(string.format(
                                "[PalBonds/Trust] %s is %.0f units away (limit %.0f) — being marched back; it has %.0fs to return before the bond breaks",
                                key, dist, MAX_FOLLOW_DISTANCE, DRIFT_GRACE_SECONDS
                            ))
                        elseif pastLeash and (os.clock() - driftingSince[key]) < DRIFT_GRACE_SECONDS then
                            -- Still inside the grace window. Deliberately silent:
                            -- this runs every 1.5s and the line above already
                            -- said what is happening.
                        elseif pastLeash then
                            driftingSince[key] = nil
                            Logger.log(string.format(
                                "[PalBonds/Trust] %s is %.0f units away (limit %.0f) and did not come back within %.0fs — losing all trust",
                                key, dist, MAX_FOLLOW_DISTANCE, DRIFT_GRACE_SECONDS
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
                                st.points = 0
                            end
                            lostAllTrust = true

                        -- Two-hundred-and-sixty-fifth pass (2026-09-07) — the
                        -- actual bug, after seven attempts aimed at the wrong
                        -- thing entirely.
                        --
                        -- The [AFTER-BOND] probe finally asked what the Pal was
                        -- DOING, and both betrayed Pals came back running
                        -- BP_AIAction_OtomoFollow_C -- while the earlier dump had
                        -- already proved the original action object was destroyed.
                        -- So it was never surviving our cleanup. It was being
                        -- REBUILT, and by this loop.
                        --
                        -- The health check that detects betrayal runs at the TOP
                        -- of this same iteration. It sets isFollowing = false and
                        -- clears everything correctly... and then execution
                        -- carries on down to the branch below, in the SAME pass,
                        -- for the SAME Pal, and installs a brand new follow
                        -- action. Every removal mechanism I tried worked. This
                        -- put one straight back, 1.5 seconds later, forever.
                        --
                        -- st.isFollowing is re-read here rather than trusted from
                        -- the top of the iteration, because anything above may
                        -- have ended the bond in between.
                        end

                        if (not lostAllTrust) and okReq and st.isFollowing then

                            -- Two-hundred-and-second pass (2026-09-06): both
                            -- mechanisms are called from here every tick —
                            -- IssueFollowMoveOrder itself now no-ops when
                            -- USE_OLD_MOVE_ORDER_NUDGE is off (Combat.lua),
                            -- and TickRealOtomoFollow is the repeated push
                            -- for the composite mechanism agreed with
                            -- Dragón, replacing the old one-shot call that
                            -- used to fire only from Combat.StartFollowing.
                            if Combat.IssueFollowMoveOrder then
                                Combat.IssueFollowMoveOrder(st.pal, playerLoc, player) 
                            end
                            if Combat.TickRealOtomoFollow then
                                Combat.TickRealOtomoFollow(st.pal, key)
                            end
                        end
                    end
                end
                if lostAllTrust then
                    on_follower_lost_all_trust(st.pal, "too far from player")
                elseif not passiveGainEnabled then

                    -- Switched off with F10. Deliberately skips the capture
                    -- check as well as the gain: that check lives here to catch
                    -- a Pal crossing the join threshold on passive drip alone,
                    -- and leaving it running while the drip is off would still
                    -- convert a follower the player is trying to keep.
                    -- Interaction-driven joins (petting or feeding a Pal over
                    -- the line) are untouched.
                elseif briefFollow[key] ~= nil then

                    -- 2026-09-16, run 5: a Pal on its short Friendly follow
                    -- (Trust.StartBriefFollow) is not a real follower yet and
                    -- earns no passive trust; the SamuraiDog went 50% -> 51%
                    -- during its three seconds and was kept as a follower.
                else

                    -- Hundred-and-eighty-fifth pass: applied every tick
                    -- (not every Nth), a flat real vanilla-scale amount —
                    -- NOT scaled by the level-gap multiplier (that now
                    -- only affects the bonding threshold's size, not
                    -- individual gains, per Dragón's simplification).
                    st.points = (st.points or 0) + PASSIVE_FRIENDSHIP_PER_TICK

                    -- FORTY-FIRST PASS: passive gain alone can cross the join
                    -- threshold without another pet/feed — check here too,
                    -- not just in OnInteractionSucceeded.
                    maybe_trigger_capture(st.pal, st, key, st.points)
                end
            end
        end
    end
end
function Trust.Init()
    Logger.log("[PalBonds/Trust] real hooks active — tracking interaction counts, follow state and PalBonds' own trust points")

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

        -- ===================================================================
        -- BETRAYAL, VIA THE PLAYER RATHER THAN THE VICTIM
        -- (two-hundred-and-forty-seventh pass, 2026-09-07)
        -- ===================================================================
        -- Dragón hit a bonded, FOLLOWING Chikipi repeatedly with fists and an
        -- axe and it was never betrayed. He then corrected my first theory --
        -- it was following, so "betrayal only applies to followers" did not
        -- explain it. The log settles what actually happened:
        --
        --   * exactly ONE DamageEvent with the player as attacker fired in the
        --     whole session, against ChickenPal#2147450603, and that one DID
        --     betray correctly (447 points reset to 0).
        --   * ChickenPal#2147443417 -- the one he was hitting -- has 79 log
        --     lines and not a single DamageEvent of any kind.
        --
        -- So the hits landed and the hook below never ran. The cause is one of
        -- our own deliberate design decisions, working exactly as written:
        -- ApplyCompanionPreset sets Damaged_Player = Ignore on every follower,
        -- because a companion must never turn on its own trainer. But
        -- "Damaged_Player = Ignore" tells the Pal's AI to do NOTHING when the
        -- player hurts it -- and UPalHate::DamageEvent is part of that reaction.
        -- Ignore the damage, and the hate system never processes it, and the
        -- hook we hang betrayal on never fires. The better a Pal's bond, the
        -- more thoroughly it could be beaten with no consequence.
        --
        -- The preset is right and is not changing. What is wrong is detecting
        -- betrayal on the VICTIM's side, where the victim has been told not to
        -- react. So this hooks the PLAYER's side instead:
        --
        --   APalPlayerController::DamageReactionComponent_ProcessDamage_ToServer_ToNPC
        --       (const FPalDamageInfo& Info, const AActor* Defender)
        --
        -- confirmed in Pal.hpp, sitting between its _ToSelfPlayer and
        -- _ToEnemyPlayer siblings. It fires on the player's own controller when
        -- the player damages a Pal, so no AI response setting on the target can
        -- suppress it, and it hands over the victim directly.
        --
        -- The old hook below STAYS. It still handles Pal-versus-Pal damage and
        -- the friendly-fire clearing, which this one knows nothing about. Both
        -- can fire for the same hit; OnFollowerDamaged is idempotent for
        -- betrayal (it zeroes an already-zero bar and re-flags an
        -- already-flagged Pal), and a short dedupe below keeps it to one log
        -- line and one toast per hit rather than two.
        local lastBetrayalKey, lastBetrayalAt = nil, 0
        local loggedBetrayalHookFired = false

        -- Two-hundred-and-fifty-second pass (2026-09-07). The pass-247 hook
        -- registered OK and then never fired once across a whole session, so it
        -- is replaced rather than kept alongside -- a hook that demonstrably
        -- does nothing is just noise for the next person reading this.
        --
        -- Dragon's correction is what pinned the real problem down. The Gumoss
        -- WAS following (log line 1090) and DID have the companion preset
        -- applied (1092) before he started hitting it, so neither of the
        -- follower-only gates fixed last pass explains it. What is left is the
        -- original theory after all: Damaged_Player = Ignore tells the Pal's AI
        -- to do nothing when the player hurts it, and UPalHate::DamageEvent is
        -- part of that reaction, so the hate hook cannot see these hits.
        --
        -- New candidate, and the shape is right this time:
        --   UPalDamageReactionComponent
        --     OnProcessedActualDamageDelegate__DelegateSignature
        --       (AActor* Attacker, AActor* Defender, int32 ActualDamage)
        --
        -- It fires when damage is actually PROCESSED rather than when the AI
        -- decides how to feel about it, and it names both parties outright, so
        -- no response-preset setting on the victim should be able to silence it.
        --
        -- Honest: whether UE4SS can hook a multicast delegate's signature
        -- function on this build is not something I can confirm from the header
        -- alone. The registration result is logged either way, and the handler
        -- logs its first firing, so the next run answers it plainly instead of
        -- leaving another silent nothing.
        local okBetray, errBetray = pcall(function()
            RegisterHook("/Script/Pal.PalDamageReactionComponent:OnProcessedActualDamageDelegate__DelegateSignature", function(Context, Attacker, Defender, ActualDamage)
                if world_is_closing() then return end

                -- Dragón caught this before it shipped, and he was right:
                -- "if you're tracking every hit of the player on pals, wouldnt
                -- that cause lag? if im attacking a pal without followers will
                -- that trigger too even tho there is no one to betray?"
                --
                -- Yes, it would have. This hook fires on EVERY hit the player
                -- lands on ANY Pal in the world, and the first thing the body
                -- below does is GetFullName() -- a reflection round-trip into
                -- the engine -- purely to look up a table. In a real fight that
                -- is several engine calls a second for a question that usually
                -- has no answer.
                --
                -- So the cheapest possible test goes first, before ANY engine
                -- call including hook_get: is there a single bonding Pal in the
                -- world at all? `next` on an empty table is one lookup and no
                -- reflection. A player who has never interacted with a wild Pal
                -- pays literally nothing for this hook, and one mid-fight with
                -- no bonds pays nothing either.
                --
                -- Same shape as the early-out already guarding
                -- Combat.OnPlayerCombatTarget, and for the same reason.
                if next(State) == nil then return end
                safe_call(function()
                    local victim = hook_get(Defender)
                    if victim == nil or not victim:IsValid() then return end
                    local key = safe_call(function() return victim:GetFullName() end)
                    if key == nil or State[key] == nil then return end

                    -- Only the PLAYER's hits are a betrayal. Everything else
                    -- reaching this delegate is an ordinary fight.
                    local hitter = hook_get(Attacker)
                    if hitter == nil or not hitter:IsValid() then return end
                    local player = find_player()
                    local playerName = player and find_player_name()
                    local hitterName = safe_call(function() return hitter:GetFullName() end)
                    if playerName == nil or hitterName ~= playerName then return end
                    if not loggedBetrayalHookFired then
                        loggedBetrayalHookFired = true
                        Logger.log("[PalBonds/Trust] [BETRAYAL-HOOK] this hook FIRES on this build — the delegate route works (logged once)")
                    end

                    -- Same hit reaching us twice (this hook and the hate hook).
                    local now = os.clock()
                    if key == lastBetrayalKey and (now - lastBetrayalAt) < 0.5 then return end
                    lastBetrayalKey, lastBetrayalAt = key, now
                    Logger.log("[PalBonds/Trust] [BETRAYAL-HOOK] the player damaged a Pal that is bonding with them — " .. tostring(key))
                    Trust.OnFollowerDamaged(victim, true)
                end)
            end)
        end)
        Logger.log("[PalBonds/Trust] [BETRAYAL-HOOK] RegisterHook(PalDamageReactionComponent:OnProcessedActualDamageDelegate) = " ..
            (okBetray and "OK" or ("FAILED: " .. tostring(errBetray) .. " — betrayal falls back to the hate hook, which misses followers whose Damaged_Player slot is Ignore")))
        RegisterHook("/Script/Pal.PalHate:DamageEvent", function(Context, DamageResult)
            if world_is_closing() then return end
            local result = hook_get(DamageResult)
            if result == nil then return end

            -- ===========================================================
            -- CHEAP EXIT FIRST (two-hundred-and-ninety-eighth pass, 2026-09-11)
            -- ===========================================================
            -- This hook fires for EVERY damage event in the world, not just
            -- ones involving a bonding Pal — every hit between any two Pals
            -- anywhere near the player. It used to resolve BOTH actor names
            -- immediately, and GetFullName() is a reflection call that builds a
            -- string. Two of those per hit, for every hit in the world.
            --
            -- Dragón felt this as a hitch when a follower was caught by a
            -- multi-hit DPS attack: his log shows 22 damage events in three
            -- seconds, peaking at ten in one second, each paying for two
            -- reflection round-trips before anything checked whether the mod
            -- even cared. It is the same cost that made find_targeted_pal
            -- 74ms in the two-hundred-and-eighth pass, for the same reason.
            --
            -- Nothing below this point can do anything useful unless at least
            -- one Pal is bonding, so bail out before paying for a single name.
            -- In ordinary play — no Pal bonding — the whole hook is now one
            -- table check.
            if next(State) == nil then
                local okEarly, CombatEarly = pcall(require, "Combat")
                local anyFollower = okEarly and CombatEarly and CombatEarly.HasAnyFollower
                    and CombatEarly.HasAnyFollower()
                if not anyFollower then return end
            end

            local defender = safe_call(function() return result.Defender end)
            local attacker = safe_call(function() return result.Attacker end)

            -- Pointer-cheap gate, BEFORE the two GetFullName calls below. See
            -- the comment on trackedAddresses: without this, two wild Pals
            -- brawling in the distance cost two path-string builds per hit.
            if not damage_event_is_ours(defender, attacker) then return end

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
            -- The original fix here pushed a large NEGATIVE hate both ways to
            -- cancel the grudge. That was removed in the three-hundred-and-
            -- twenty-second pass: run 25's [HATE-VERIFY] proved hate
            -- subtraction does nothing in this build, so it was two native
            -- calls per damage event to achieve nothing. Companion-on-companion
            -- fights are ended by enforce_target_discipline instead, which
            -- cancels the ACTION rather than editing the hate table.
            --
            -- What remains is purely a MEASUREMENT, and pass 324 made it an
            -- honest one. The old line said it was "clearing the grudge both
            -- ways" long after it had stopped doing anything -- a log that
            -- lies about its own behaviour is worse than no log, and this file
            -- has been bitten by exactly that before. It now reports what it
            -- actually knows, and names both Pals: run 27 and run 28 could both
            -- see THAT companions were clipping each other (53 events in run
            -- 28, in two bursts that line up exactly with the two fights) but
            -- not WHO, which is the number needed to tell a stray AoE hit from
            -- a genuine duel.
            do
                local aIsFollower = attackerName ~= nil and State[attackerName] ~= nil and State[attackerName].isFollowing
                local dIsFollower = defenderName ~= nil and State[defenderName] ~= nil and State[defenderName].isFollowing
                if aIsFollower and not dIsFollower then
                    -- A companion hitting something else keeps its own
                    -- self-defence fight alive (Combat.OnFollowerAttacked).
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

                -- Two-hundred-and-sixteenth pass (2026-09-06) — Dragón's
                -- edge case, applied at the outermost point too. This hook
                -- fires for EVERY damage event in the world, and the block
                -- below does a FindFirstOf plus a GetFullName on the player
                -- before it can even decide whether the event is relevant.
                -- With nothing following, none of that can lead anywhere, so
                -- skip it on a plain table check first. HasAnyFollower does no
                -- engine calls at all.
                local okHas, CombatCheck = pcall(require, "Combat")

                -- Two-hundred-and-fifty-first pass (2026-09-07) — the reason
                -- Dragon could hit a partially-bonded Gumoss forever with no
                -- penalty. The log is blunt about it: ZERO DamageEvent lines in
                -- the entire session, so this whole block never ran once.
                --
                -- This gate was added at Dragon's own request (pass 216, "only
                -- activate that IF there are pals following") and it was correct
                -- then, because back then damage only ever mattered to a
                -- FOLLOWER. Pass 246 widened this gate to any Pal with a trust
                -- record (CORRECTED 2026-09-18: that pass claimed "the bond starts
                -- at the first pet"; it does not -- bonding starts at 50%, and
                -- below that a player hit empties the bar instead) -- and
                -- this gate was not widened with it. So a Pal you had petted
                -- four times but that was not yet following you could be hit as
                -- often as you liked, which is exactly the bug pass 246 was
                -- meant to fix, still alive one level further up.
                --
                -- `next(State)` is the same shape of test and just as cheap --
                -- one table lookup, no engine calls -- while matching what
                -- betrayal actually cares about: does this Pal have a bond at
                -- all. A player with no bonds anywhere still pays nothing.
                local anyBonding = next(State) ~= nil
                local anyFollowing = anyBonding or (okHas and CombatCheck and CombatCheck.HasAnyFollower and CombatCheck.HasAnyFollower())
                local player = anyFollowing and find_player() or nil
                local playerName = player and find_player_name()
                if playerName then
                    local enemy = nil
                    if attackerName == playerName then
                        enemy = defender          
                    elseif defenderName == playerName then
                        enemy = attacker          
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
                            safe_call(function() CombatMod.OnPlayerCombatTarget(enemy, player) end)
                        end
                    end
                end
            end

            -- Two-hundred-and-fifty-first pass: the SECOND follower-only gate,
            -- and the one that would still have blocked Dragon's Gumoss even
            -- after widening the outer one. Same story as that gate: written
            -- when damage only mattered to a follower. (CORRECTED 2026-09-18:
            -- pass 246 claimed the bond starts at the first interaction. It
            -- does not: bonding starts at 50%. Dragón's Gumoss report meant it
            -- never attacked him back, not that it should be punished. Below
            -- 50% a player hit now empties the bar -- OnFollowerDamaged.)
            --
            -- Widened to "has a bond", but ONLY the player-betrayal branch below
            -- acts on the wider set. The non-player penalty stays follower-only
            -- on purpose: it exists for a companion taking hits in a fight the
            -- player is part of, and letting ambient Pal-versus-Pal scraps chip
            -- away at a bond the player is not even present for would be a
            -- different feature nobody asked for.
            if defenderName and State[defenderName] then
                local defenderIsFollowing = State[defenderName].isFollowing
                -- Guarded because [DAMAGE-WATCH] is in Logger's SUPPRESSED_TAGS:
                -- without the check the string.format still ran on every hit and
                -- the result was thrown away, since Lua evaluates arguments
                -- before the call. Exactly the trap the hundred-and-seventy-fifth
                -- pass found in the SetHPPercent hook.
                if Logger.DiagnosticsEnabled and Logger.DiagnosticsEnabled() then
                    Logger.log(string.format(
                        "[PalBonds/Trust] [DAMAGE-WATCH] real DamageEvent fired — defender=%s attacker=%s damage=%s",
                        tostring(defenderName), tostring(attackerName), tostring(damage)
                    ))
                end

                -- Hundred-and-eighty-fourth pass: identify whether the
                -- PLAYER specifically dealt this hit (betrayal, see
                -- OnFollowerDamaged) vs. any other attacker (another Pal,
                -- environment) — same FullName-comparison technique
                -- already used throughout this project wherever reference
                -- equality on actors wasn't trusted (e.g. find_targeted_pal
                -- excluding the player by name, not by reference).
                local player = find_player()
                local playerName = player and find_player_name()
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
                elseif defenderIsFollowing then

                    -- Something other than the player hit a companion: let it
                    -- fight back (2026-09-12, run 34). Before this, our own
                    -- follow action held it out of the fight entirely.
                    local okSD, CombatSD = pcall(require, "Combat")
                    if okSD and CombatSD and CombatSD.OnFollowerAttacked then
                        safe_call(function() CombatSD.OnFollowerAttacked(State[defenderName].pal, attacker) end)
                    end

                    -- Throttled and counted (two-hundred-and-ninety-eighth pass,
                    -- 2026-09-11). This line is NOT in Logger's suppressed list,
                    -- and Logger flushes to disk per line, so a multi-hit DPS
                    -- attack turned into ten synchronous writes in one second —
                    -- the hitch Dragón reported. The information is worth
                    -- keeping, so it is aggregated rather than dropped: one line
                    -- per follower every THIRD_PARTY_DAMAGE_LOG_INTERVAL, saying
                    -- how many hits it covers.
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
                Logger.trace("follower tick (trust)")

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
                    return false 
                end)
            end)
        end
    end
    scheduleTick()
end
return Trust
