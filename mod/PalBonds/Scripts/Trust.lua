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
      1. INTERACTIONS_TO_START_FOLLOWING successful pets/feeds on the
         same wild Pal -> it starts following the player (Combat.lua).
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

-- Tunable.
local INTERACTIONS_TO_START_FOLLOWING = 5
-- Seventeenth pass (2026-09-01): was 5000ms. Dragón's own test report
-- ("started following but irregularly", a Pal "ran away from its normal
-- skittish behavior" mid-follow) matches a real gap in the old design:
-- a move order only refreshed every 5s left plenty of time for the
-- Pal's own wild AI to retarget/wander/flee in between. Dropped to 1.5s
-- so the move order (and the distance/leash check) refresh much more
-- often; paired with Combat.lua's new SetActiveAI(false) suppression
-- while bonding (see that file's seventeenth-pass note).
local TICK_INTERVAL_MS = 1500          -- how often the follower tick runs (move order + distance check)
local PASSIVE_GAIN_EVERY_N_TICKS = 10  -- passive friendship applied every Nth tick (~15s at the new 1.5s interval, same real-world cadence as before)
local PASSIVE_FRIENDSHIP_PER_GAIN = 2  -- our own approximation of the real Otomo auto-increment
-- Eighteenth pass (2026-09-01): Dragón gave real numbers relative to the
-- +10 per pet/feed (INTERACTION_FRIENDSHIP_GAIN in Interaction.lua):
-- "receiving a hit either by the player or by other pals should take
-- away 25 friendship." Was -50 ("huge chunks", a rough guess before real
-- numbers were given) — now the exact value Dragón specified.
local DAMAGE_FRIENDSHIP_PENALTY = -25
local MAX_FOLLOW_DISTANCE = 3000.0     -- Unreal units (~30m) before a following Pal loses all trust
-- FORTY-FIRST PASS (2026-09-02): Dragón, fairly, called out the previous
-- plan (find the real game's own point-per-rank curve before testing the
-- automatic trigger) as backwards — we're the ones implementing this, so
-- just pick our own round number, confirm the automatic path fires
-- end-to-end, then tune it later. Replaces the old rank-based trigger
-- (`param:GetFriendshipRank() >= 1`, which depended on a real curve we'd
-- never actually read) with a plain point threshold we fully control:
-- 5 pets (50) + roughly one round of passive gain (+2 per ~15s) lands
-- right around Dragón's own "5 pets then about a minute of following"
-- expectation.
local CAPTURE_AT_FRIENDSHIP_POINT = 55

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

local function get_individual_parameter(pal)
    local comp = safe_call(function() return pal.CharacterParameterComponent end)
    if not comp or not comp:IsValid() then return nil end
    return safe_call(function() return comp:GetIndividualParameter() end)
end

-- Shared by OnInteractionSucceeded (right after a pet/feed) and
-- tick_followers (right after passive gain) — the threshold can be
-- crossed by either path now, not just a pet/feed. `captureTriggered`
-- guards against firing more than once for the same Pal (a following
-- Pal that's already past 55 would otherwise re-trigger on every
-- subsequent pet or every passive-gain tick).
local function maybe_trigger_capture(pal, st, key, point)
    if st.captureTriggered then return end
    if point == nil or point < CAPTURE_AT_FRIENDSHIP_POINT then return end

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
        "[PalBonds/Trust] %s reached %d friendship (threshold %d) — trust threshold for sphere-less capture met",
        tostring(key), point, CAPTURE_AT_FRIENDSHIP_POINT
    ))
    local okReq, Capture = pcall(require, "Capture")
    if okReq and Capture.OnTrustMaxed then
        Capture.OnTrustMaxed(pal)
    end
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

    if not st.isFollowing and st.interactionCount >= INTERACTIONS_TO_START_FOLLOWING then
        Trust.StartFollowing(pal, st)
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
            local ratio = point / CAPTURE_AT_FRIENDSHIP_POINT
            if ratio < 0 then ratio = 0 end
            if ratio > 1 then ratio = 1 end
            snapshot[#snapshot + 1] = {
                pal = st.pal,
                ratio = ratio,
                point = point,
                threshold = CAPTURE_AT_FRIENDSHIP_POINT,
            }
        end
    end
    return snapshot
end

function Trust.StartFollowing(pal, st)
    st = st or (select(1, get_state(pal)))
    if not st or st.isFollowing then return end
    st.isFollowing = true
    Logger.log(string.format(
        "[PalBonds/Trust] %d successful interactions reached — this Pal should now start following the player",
        INTERACTIONS_TO_START_FOLLOWING
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
function Trust.OnFollowerDamaged(pal)
    local st = select(1, get_state(pal))
    if not st or not st.isFollowing then return end

    local param = get_individual_parameter(pal)
    if not param or not param:IsValid() then return end

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
                            local param = get_individual_parameter(st.pal)
                            if param and param:IsValid() then
                                local point = safe_call(function() return param:GetFriendshipPoint() end)
                                if point and point > 0 then
                                    safe_call(function() param:AddFriendShip(-point, false) end)
                                end
                            end
                            lostAllTrust = true
                        elseif okReq and Combat.IssueFollowMoveOrder then
                            Combat.IssueFollowMoveOrder(st.pal, playerLoc)
                        end
                    end
                end

                if lostAllTrust then
                    on_follower_lost_all_trust(st.pal, "too far from player")
                elseif st.tickCount % PASSIVE_GAIN_EVERY_N_TICKS == 0 then
                    local param = get_individual_parameter(st.pal)
                    if param and param:IsValid() then
                        safe_call(function() param:AddFriendShip(PASSIVE_FRIENDSHIP_PER_GAIN, false) end)
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

            -- Eighteenth pass: log EVERY real DamageEvent unconditionally
            -- (not just ones that matter to a following Pal). This is
            -- the direct answer to "does this hook even fire for a
            -- player punching their own following Pal, vs. a wild Pal
            -- hitting it" — previous sessions could only infer this
            -- indirectly (once from a lucky hit, once from a log that
            -- cut off before any fight happened). Same [WATCH]-style
            -- unconditional logging already used for AddFriendShip.
            Logger.log(string.format(
                "[PalBonds/Trust] [DAMAGE-WATCH] real DamageEvent fired — defender=%s attacker=%s damage=%s",
                tostring(defenderName), tostring(attackerName), tostring(damage)
            ))

            if defenderName and State[defenderName] and State[defenderName].isFollowing then
                Trust.OnFollowerDamaged(State[defenderName].pal)
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
    local function scheduleTick()
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(TICK_INTERVAL_MS, function()
                Logger.log("[PalBonds/Trust] [TICK] game-thread tick fired")
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
