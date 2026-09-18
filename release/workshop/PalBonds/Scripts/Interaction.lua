local Logger = require("Logger")
local Trust = require("Trust")
local Capture = require("Capture")
local Personality = require("Personality")
local UEHelpers = require("UEHelpers") 
local Interaction = {}

-- Hundred-and-thirty-eighth pass (2026-09-04): CTRL+J, repurposed. Used
-- to be TEST_FEED_ITEM_KEY (the real-food-item test) — that thread is
-- confirmed dead-end for wild Pals (hundred-and-nineteenth pass:
-- RequestUseToCharacter only works on the player's own active Otomo) and
-- item 7 on the saved priority list is shelved because of it. Per
-- Dragón's own standing rule ("if you need to add a new one, remove or
-- swap for one already used in the project"), this physical key is
-- reused for the new Play interaction instead of adding a fifth bind.
-- Two-hundred-and-first pass (2026-09-06): moved off CTRL+J entirely, per
-- Dragon's direct ask (a two-key-press combo was too annoying for
-- something used this often). He confirmed F9/F10 (Pet/Feed) can stay as
-- they are — he uses the real radial menu day to day, which internally
-- calls these same do_pet/do_feed functions anyway (see do_interaction) —
-- so this claims F8 instead, a single plain key, same shape as F9/F10.
local PLAY_KEY = "F8"

-- Cheer is emote 0, identified by Dragón with the F7 probe. Declared up here
-- rather than next to the emote code because do_play uses it far above that
-- point, and Lua locals are not hoisted.
local CHEER_EMOTE_INDEX = 0
local play_player_emote   -- forward: defined with the other emote helpers below
-- How far past PET_RANGE a Pal's ROOT may be before we stop bothering to read
-- its capsule. A Pal whose root is further than this cannot have a body within
-- range, so it is rejected on the cheap distance test alone and never costs the
-- two capsule reads. Sized for the largest Pals in the game with room to spare.
local CAPSULE_COARSE_MARGIN = 600.0

-- Species already reported by the [AIM] line, so it prints once each
-- instead of once per Pal per scan.
local capsuleReported = {}

-- Two-hundred-and-ninety-ninth pass (2026-09-11): 500 -> 900, from a measurement
-- rather than a feel.
--
-- Dragón could not pet a Mammorest "no matter how close" he got. The [AIM]
-- diagnostic added last pass says why, and it is not the angle: at his closest
-- approach the Mammorest's actor ROOT was 628 units away, already past the old
-- 500 limit. A giant Pal's own body stops the player from getting nearer, and
-- its root sits at the centre of the creature rather than at the surface — so
-- the range was being measured from the player to a point deep inside a Pal he
-- was standing against.
--
-- The capsule work from the previous pass could not rescue this, because the
-- same diagnostic proved the capsule is not size data at all: BOSS_GrassMammoth,
-- BOSS_Anubis, FlowerRabbit and PinkRabbit ALL report radius=30 halfHeight=30.
-- Palworld does not scale the ACharacter capsule to the creature; it is a fixed
-- placeholder. So there is no per-Pal size available on the live actor yet (see
-- the [AIM] bounds probe for the attempt to find some), and a single range that
-- is generous enough for the largest Pals is the honest interim answer.
--
-- Why raising it is not as loose as it sounds: selection is still gated by
-- PET_MAX_ANGLE_DEG, a 25-degree cone around the crosshair, and among everything
-- in that cone the NEAREST Pal wins. A normal-sized Pal 800 units away is only
-- reachable if the player is looking almost directly at it and nothing closer is
-- in the way.
local PET_RANGE = 900.0
local PET_MAX_ANGLE_DEG = 25  

-- Two-hundred-and-first pass: Play-specific now (Pet has its own
-- PET_FRIENDSHIP_GAIN/top-up mechanism below) — bumped 10 -> 25 per
-- Dragon's balance ask.
local INTERACTION_FRIENDSHIP_GAIN = 25

-- Hundred-and-eighty-fifth pass (2026-09-05): Dragón's simplified real
-- balance spec — Pet/Play/Feed all use small, real vanilla-scale
-- amounts during wild bonding (not the mod's own big custom numbers),
-- and the level-gap multiplier scales the BONDING THRESHOLD (how much
-- of these small amounts is needed) instead of each individual gain.
-- This means Pet/Play need NO override at all — vanilla's own real
-- Happy-triggered grant (≈30, confirmed via [BALANCE-DIAG]'s
-- FriendshipPoint_Petting) just applies untouched, same as it always
-- has. Feed still needs an explicit grant (it currently gives zero real
-- credit at all — nothing to conflict with), sized at 2x Pet's real
-- amount per Dragón's original ratio ("feed requires an item"), just
-- applied at vanilla scale instead of the earlier 1000/2000 draft.
-- Kinship Peach amounts are the REAL numbers already found via
-- [BALANCE-DIAG] (FloatValue1 on each item's static data) — genuinely
-- vanilla, no scaling needed.
-- Two-hundred-and-first pass (2026-09-06): 60 -> 50, Dragon's balance ask.
-- 60 -> 75. Note this deliberately breaks the old 2x-Pet ratio: at 50/75 feeding
-- is 1.5x a pet rather than double it. Dragón chose both numbers directly, and
-- the tighter ratio makes petting (free, unlimited) meaningfully competitive
-- with feeding (costs an item), which suits a mod about spending time with a Pal
-- rather than buying its affection.
-- 2026-09-12: 75 -> 50, the same as Pet and Play, plus a bonus by the food's
-- rarity (Dragón's scale): common +10, uncommon +20, rare +30, epic +40,
-- legendary +50, so a feed gives 60-100. See Interaction.FeedGrantAmount.
-- Kinship Peaches keep their own amounts below.
local FEED_FRIENDSHIP_BASE = 50
local FEED_RARITY_BONUS = { [0] = 10, [1] = 20, [2] = 30, [3] = 40, [4] = 50 }

-- Two-hundred-and-first pass (2026-09-06): the comment three passes above
-- (this same block) assumed Pet's real vanilla Happy-triggered grant just
-- applies untouched at ~30 and needs no override — but that number was
-- NEVER actually isolated from a real, clean, wild-Pal-Pet-specific
-- observation. Every "AddFriendShip fired" line this project has ever
-- read comes from ONE global, unconditional watch hook
-- (RegisterHook("...PalIndividualCharacterParameter:AddFriendShip"...))
-- that logs literally every real grant in the whole game, on any Pal, for
-- any reason — including totally unrelated ambient events like a
-- real Otomo party member's own passive gain (vanilla's real
-- FriendshipPoint_AutoIncrementOtomo, confirmed = 10 via [BALANCE-DIAG]).
-- Dragon caught this directly: recent test logs were full of
-- "value=10 applyPassiveSkill=true" lines that were misread as Pet's own
-- grant, when they almost certainly were exactly that ambient Otomo
-- auto-increment firing in the background, unrelated to any wild-Pal Pet
-- interaction. Pet's real, isolated amount has genuinely never been
-- confirmed. Rather than guess again, do_interaction below now measures
-- it directly (before/after FriendshipPoint around one real Pet
-- interaction) and adjusts the real total to land on this exact target —
-- positive OR negative (AddFriendShip with a negative value is already
-- proven-safe elsewhere in this project, e.g. Trust.lua's damage/distance
-- penalties), so the outcome is exactly 25 regardless of whatever
-- vanilla's real amount turns out to be. This first live use also finally
-- gives a clean, isolated read of that real number, closing the question
-- either way.
-- Two-hundred-and-fortieth pass (2026-09-07): 25 -> 30, Dragón's call after
-- playing the restored real values. Feed keeps its 2x ratio at 60, Play matches
-- Pet at 30.
-- Two-hundred-and-forty-third pass (2026-09-07): 30 -> 50. Dragón played the
-- previous numbers on a fresh save and reported the early game "felt a bit
-- slower". The early game is where it matters most, because that is where a
-- player decides whether the mod is fun.
local PET_FRIENDSHIP_GAIN = 50

-- Hundred-and-eighty-sixth pass (2026-09-05): Dragón moved off the raw
-- real vanilla FloatValue1 numbers (2000/20000) to clean values sized
-- directly against his own BONDING_TRIGGER_THRESHOLD_BASE=500 (Trust.lua)
-- instead — the full peach now grants exactly the base bar's worth in
-- one use (a clean one-shot at equal level, matching Dragón's "it is
-- indeed a one shot killer for friendship"), self-limiting against abuse
-- since a much-higher-level Pal's own bonding threshold scales up too.
local KINSHIP_PEACH_LESSER_FRIENDSHIP_BASE = 250   
local KINSHIP_PEACH_FULL_FRIENDSHIP_BASE = 500     
local PLAY_FRIENDSHIP_GAIN = 50

-- Forward declaration. The real definition lives next to
-- closeRadialMenuActionWindow (it needs the radial-menu state), but do_play
-- above it also grants through it, and Lua locals are not hoisted. Assigned
-- immediately after that definition; every call site is inside a safe_call,
-- so even a missing assignment degrades to a logged failure, not an error.
local grant_wild_interaction = nil

-- Happy: confirmed via Spy.lua/the [WATCH] hook to be exactly what the
-- target Pal's own ActionComponent plays, self-targeted, after every real
-- AddFriendShip call during a vanilla Pet/Feed interaction, and to itself
-- reliably trigger exactly one AddFriendShip(10, true) call as a side
-- effect (see eleventh-pass notes). Reused for both pet and feed so both
-- interactions share the one proven-safe reaction/grant mechanism.
local ACTION_TYPE_HAPPY = 38

-- Hundred-and-thirty-eighth pass (2026-09-04): PalRandomRest, confirmed
-- real in Pal_enums.hpp (value 77) — the same simple int enum every
-- other reaction in this file already plays through PlayActionByType.
-- Used for the new Play interaction's Pal-idle half: no new calling
-- mechanism needed, just a different EPalActionType value than Happy.
local ACTION_TYPE_PAL_RANDOM_REST = 77

-- Hundred-and-forty-third pass (2026-09-04): how long to wait after the
-- Pal-idle animation before sequencing the Happy follow-up (the hearts
-- VFX, confirmed baked into BP_ActionHappy's own graph — see hook-points.
-- md). PalRandomRest picks one of several montages at random per species
-- (FPalRandomRestInfo, different LoopNum_Min/Max per entry), so there is
-- no single real duration to read back yet — this is an honest fixed
-- approximation (same category as Feed's item-selection gap), not a
-- precise sync. Adjust based on real observation if it feels off.
-- Hundred-and-forty-eighth pass (2026-09-04): Dragón's real test — 3s cut
-- some idle animations off before they'd finished playing properly.
-- Bumped to 6s per his direct request.
local PLAY_HAPPY_FOLLOWUP_DELAY_MS = 6000
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
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
local function vec_sub(a, b)
    return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end
local function vec_length(v)
    return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end
local function vec_normalize(v)
    local len = vec_length(v)
    if len < 1e-6 then
        return { X = 0, Y = 0, Z = 0 }
    end
    return { X = v.X / len, Y = v.Y / len, Z = v.Z / len }
end
local function vec_dot(a, b)
    return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

-- Builds a forward unit vector from an FRotator (Pitch/Yaw in degrees).
local function rotator_to_forward(rot)
    local yaw = math.rad(rot.Yaw)
    local pitch = math.rad(rot.Pitch)
    return {
        X = math.cos(pitch) * math.cos(yaw),
        Y = math.cos(pitch) * math.sin(yaw),
        Z = math.sin(pitch),
    }
end

-- Finds the PalCharacter the player is actually looking at: within
-- PET_RANGE of originLoc AND within PET_MAX_ANGLE_DEG of forwardVec.
-- Among qualifying candidates, picks the most centered one (smallest
-- angle), not just the nearest.
--
-- BUG FOUND (2026-09-01, tenth-pass log, fixed eleventh pass):
-- FindAllOf("PalCharacter") also returns the PLAYER's own actor
-- (PalPlayerCharacter is itself a PalCharacter subclass). The old
-- `pal ~= excludeActor` check was meant to filter it out, but Lua
-- reference equality on two separately-obtained UE4SS object wrappers
-- for the SAME underlying UObject isn't reliable here. Fixed by
-- comparing `GetFullName()` strings instead, which reliably identifies
-- the same actual game object regardless of which Lua wrapper instance
-- is holding it. Confirmed fixed live (zero self-targeting occurrences
-- across a full follow-up session).
--
-- KNOWN LIMITATION (not yet fixed): large bosses (e.g. Mammorest) can be
-- effectively untargetable — this does a single-point distance/angle
-- check against pal:K2_GetActorLocation() (the actor's root/pivot),
-- which for a boss-scale creature can sit far from wherever the player
-- is visually aiming at its bulk. Confirmed via ~44s of "not looking at
-- any Pal" while clearly looking at a Mammorest. Future fix: scale
-- tolerance by actor bounding size, or check mesh/capsule extent instead
-- of a single origin point. Not urgent — normal-sized wild Pals work
-- correctly.
-- Two-hundred-and-forty-fourth pass (2026-09-07) — THE LAST KNOWN STUTTER.
--
-- Dragón: "i did feel a bit of lag when playing". This is the one cost in the
-- mod that was actually measured rather than suspected: the project's own
-- [RADIAL-REDIRECT-PERF] line has been reporting this scan at 36-74ms, several
-- times per second while the radial menu is open. At 60fps a frame is 16ms, so
-- a single scan drops three to four frames, and the menu recomputes every 0.5s
-- for as long as it is held open. That is exactly a stutter on pressing "4".
--
-- The two-hundred-and-eighth pass already fixed the part of this that was ours:
-- it removed a GetFullName() reflection call per Pal per scan. What is left is
-- FindAllOf("PalCharacter") itself — a sweep of every loaded object in the
-- world, whose cost is set by how busy the area is and cannot be optimised from
-- Lua at all. It can only be called less often.
--
-- So the sweep is cached and the geometry is not. Which Pals EXIST changes
-- slowly (spawns and despawns); where they ARE changes constantly. Re-running
-- the distance and angle maths on a cached list every call keeps aiming exactly
-- as responsive as before, while the expensive sweep drops from every call to
-- one in four — roughly one every two seconds of held-open menu instead of two
-- a second.
--
-- The visible cost of being wrong here is small and self-correcting: a Pal that
-- spawns mid-menu may not be targetable for up to two seconds. Every cached
-- actor is still IsValid()-checked in the loop below, which it already was, so
-- a despawned Pal is skipped rather than crashing anything.
local palScanCache = nil
local palScanCacheAge = 0
local PAL_SCAN_CACHE_MAX_AGE = 4   

-- Two-hundred-and-sixty-ninth pass (2026-09-07). Dragon, reading his own log:
-- "this thing that seemed to spam often ... why create a log about it everytime
-- - who are you telling that to?"
--
-- Nobody. These three lines report that the redirect decided to do NOTHING -- no
-- Pal aimed at, the aimed Pal is the current Otomo, or it is already owned --
-- and the redirect recomputes about twice a second for as long as the menu is
-- held open. Dozens of identical lines saying nothing happened, burying the
-- lines that matter when something does.
--
-- They are not free either, even in the release build where Logger.log returns
-- immediately: Lua builds the argument before the call, so each one still
-- constructs its string. Worth keeping only as a state CHANGE.
local lastRedirectIdleReason = nil
local function redirect_idle_log(reason, msg)
    if lastRedirectIdleReason == reason then return end
    lastRedirectIdleReason = reason
    Logger.log(msg .. "  (logged once until this changes)")
end
local function find_targeted_pal(originLoc, forwardVec, excludeActor)
    local pals = palScanCache
    if pals == nil or palScanCacheAge >= PAL_SCAN_CACHE_MAX_AGE then
        pals = FindAllOf("PalCharacter")
        palScanCache = pals
        palScanCacheAge = 0
    else
        palScanCacheAge = palScanCacheAge + 1
    end
    if not pals then
        return nil, nil, nil
    end

    -- Two-hundred-and-eighth pass (2026-09-06) — REAL LAG FIX, measured.
    -- Dragón's live log shows this scan costing 48-74ms EVERY time, several
    -- times per radial-menu open (it recomputes on a 0.25s throttle while
    -- the menu is up). At ~4 scans/second that is 200-300ms of frame-
    -- blocking Lua per second of menu time — by far the largest single
    -- hitch this project has, and the one Dragón feels as a stutter when he
    -- presses "4".
    --
    -- The waste: the old loop called `GetFullName()` — a string-building
    -- reflection round-trip — on EVERY Pal in the loaded world, purely to
    -- test whether it was the one actor to exclude. In a busy area that is
    -- dozens of reflection calls per scan, for a comparison that can only
    -- ever match once.
    --
    -- Fix: do the cheap geometry first and resolve the exclusion ONLY for
    -- the single Pal that actually wins. Same result, but GetFullName goes
    -- from once-per-Pal-per-scan to at most once per scan. The distance
    -- check is also now ordered before the angle math (dist is a plain
    -- subtract-and-length; the angle needs a normalize, a dot and an acos),
    -- so far-away Pals cost almost nothing.
    local best, bestAngle, bestDist = nil, nil, nil
    for _, pal in ipairs(pals) do
        local validOk, isValid = pcall(function() return pal ~= nil and pal:IsValid() end)
        if validOk and isValid then
            local loc = safe_call(function() return pal:K2_GetActorLocation() end)
            if loc then
                local toTarget = vec_sub(loc, originLoc)
                local dist = vec_length(toTarget)

                -- Two-hundred-and-ninety-sixth pass (2026-09-11): aim at the
                -- Pal's BODY, not at its actor root.
                --
                -- Dragón: "range of interaction needs to be bumped a bit, since
                -- bigger pals have a weird hitbox which sometimes doesnt match
                -- their model". The range was never really the problem. Every
                -- test here was against `K2_GetActorLocation()`, which is the
                -- actor root — for a Pal that is down at its feet. On a big Pal
                -- the body you are actually looking at is metres above that
                -- point, so the angle is measured to somewhere near the ground
                -- and the check fails while the crosshair is squarely on the
                -- creature. This is the same single-point weakness recorded
                -- long ago as "large bosses are effectively impossible to aim
                -- at".
                --
                -- Every Pal is an APalCharacter, which inherits ACharacter, so
                -- every Pal has a CapsuleComponent with its real scaled size.
                -- Treat the Pal as a sphere at root + halfHeight, of the
                -- capsule's radius, and measure to that sphere's SURFACE:
                --
                --   * distance becomes centre distance minus radius, so range
                --     is measured to the body rather than through it;
                --   * the sphere subtends a real angular radius, so a big Pal
                --     is genuinely easier to point at, in proportion to how
                --     big it is.
                --
                -- A normal-sized Pal barely moves (small radius, low capsule),
                -- so this is not a blanket range increase — it is targeted
                -- exactly at the Pals that were hard to hit. Read only for
                -- Pals that already passed a cheap coarse distance test, so
                -- the hot loop keeps the pass-208 cost profile.
                local radius, halfHeight = 0.0, 0.0
                if dist <= PET_RANGE + CAPSULE_COARSE_MARGIN then
                    local capsule = safe_call(function() return pal.CapsuleComponent end)
                    if capsule and safe_call(function() return capsule:IsValid() end) then
                        radius = safe_call(function() return capsule:GetScaledCapsuleRadius() end) or 0.0
                        halfHeight = safe_call(function() return capsule:GetScaledCapsuleHalfHeight() end) or 0.0
                    end
                end
                if radius > 0.0 or halfHeight > 0.0 then
                    local centre = { X = loc.X, Y = loc.Y, Z = loc.Z + halfHeight }
                    toTarget = vec_sub(centre, originLoc)
                    dist = vec_length(toTarget)
                end

                -- Two-hundred-and-ninety-eighth pass (2026-09-11): report the
                -- capsule ONCE per species, because the fix above has a silent
                -- failure mode and Dragón reported "no significant difference".
                --
                -- If pal.CapsuleComponent does not resolve, radius and
                -- halfHeight stay 0 and every line below behaves exactly as the
                -- old root-point code did — with nothing in the log to say so.
                -- That is a fallback that hides a failure, which this project
                -- forbids, and it is the most likely reason the change was not
                -- felt. This line settles it: if the numbers come back as zeros
                -- the fix never ran, and if they come back real the geometry is
                -- live and the tuning is the thing to argue about.
                --
                -- Keyed by species so it is a handful of lines per session
                -- rather than one per Pal per scan, and NOT tagged [DIAG...] so
                -- Logger's suppression list cannot swallow it.
                if radius > 0.0 or halfHeight > 0.0 or dist <= PET_RANGE then
                    local speciesKey = safe_call(function()
                        local comp = pal.CharacterParameterComponent
                        if comp == nil or not comp:IsValid() then return nil end
                        local p = comp:GetIndividualParameter()
                        if p == nil or not p:IsValid() then return nil end
                        local cid = p:GetCharacterID()
                        return cid and cid:ToString()
                    end)
                    local sk = tostring(speciesKey)
                    if not capsuleReported[sk] then
                        capsuleReported[sk] = true

                        -- Two-hundred-and-ninety-ninth pass (2026-09-11): hunt
                        -- for REAL per-Pal size, since the capsule turned out to
                        -- be a fixed 30x30 placeholder on every species and the
                        -- range is now a blanket 900 as a result.
                        --
                        -- AActor::GetActorBounds is a real UFUNCTION in this
                        -- build (Engine.hpp) but it returns its answer through
                        -- OUT PARAMETERS, and whether this UE4SS build hands
                        -- those back to Lua is exactly the kind of thing this
                        -- project has been burned by guessing at. So it is
                        -- probed, once per species, inside pcall, and whatever
                        -- comes back is printed verbatim. If real extents appear
                        -- here, per-Pal sizing becomes possible and the blanket
                        -- range can go back down.
                        local boundsDesc = "unreadable"
                        safe_call(function()
                            local o, e = pal:GetActorBounds(false)
                            if e ~= nil and e.X ~= nil then
                                boundsDesc = string.format("extent=(%.0f, %.0f, %.0f)", e.X or 0, e.Y or 0, e.Z or 0)
                            elseif o ~= nil then
                                boundsDesc = "returned something, but not a readable extent: " .. tostring(o)
                            end
                        end)
                        Logger.log("[PalBonds/Interaction] [AIM] " .. sk ..
                            " GetActorBounds probe -> " .. boundsDesc)
                        Logger.log(string.format(
                            "[PalBonds/Interaction] [AIM] %s capsule radius=%.0f halfHeight=%.0f | root dist=%.0f -> body dist=%.0f (limit %.0f)%s",
                            sk, radius, halfHeight, vec_length(vec_sub(loc, originLoc)),
                            math.max(0.0, dist - radius), PET_RANGE,
                            (radius == 0.0 and halfHeight == 0.0)
                                and "  <-- ZEROS: capsule unreadable, aiming fell back to the old root-point behaviour"
                                or ""
                        ))
                    end
                end

                local surfaceDist = math.max(0.0, dist - radius)
                if surfaceDist <= PET_RANGE and dist > 1e-3 then
                    local dir = vec_normalize(toTarget)
                    local dot = math.max(-1.0, math.min(1.0, vec_dot(dir, forwardVec)))
                    local angle = math.deg(math.acos(dot))

                    -- How wide the Pal looks from here. asin is only defined
                    -- for |x| <= 1; a player standing inside a huge Pal's
                    -- capsule clamps to 90 degrees, which is the right answer
                    -- (it fills the view).
                    local angularRadius = 0.0
                    if radius > 0.0 and dist > radius then
                        angularRadius = math.deg(math.asin(math.min(1.0, radius / dist)))
                    elseif radius > 0.0 then
                        angularRadius = 90.0
                    end
                    angle = math.max(0.0, angle - angularRadius)

                    -- Ranking still uses the surface distance, so the Pal whose
                    -- BODY is nearest wins rather than the one whose root
                    -- happens to be closest.
                    dist = surfaceDist
                    if angle <= PET_MAX_ANGLE_DEG then

                        -- Two-hundred-and-fifty-seventh pass (2026-09-07) --
                        -- Dragon's idea, and it is better than what I had been
                        -- doing: "cant we make that simply doesnt count it as a
                        -- valid target for the 4 radial menu? that way opening
                        -- the menu on a scarred pal simply ignores it and thinks
                        -- there's nothing there?"
                        --
                        -- I had been guarding each grant path one at a time --
                        -- pet, then the radial fallback, then the real inventory
                        -- feed -- and finding a new one every run. Those guards
                        -- work (his log shows both refusing correctly) but they
                        -- refuse LATE: the menu still opens, the Pal is still
                        -- substituted, and vanilla's own petting animation still
                        -- plays. Nothing is granted, yet it looks exactly like a
                        -- successful interaction, which is why he reported he
                        -- "could still pet it".
                        --
                        -- Excluding it here is the root fix. A Pal that has
                        -- permanently lost its trust stops being something the
                        -- player can aim at, so every path downstream -- the
                        -- ones I have found and the ones I have not -- gets
                        -- nothing to act on. The existing guards stay as a
                        -- backstop rather than as the mechanism.
                        local fled = false
                        if Capture and Capture.HasPermanentlyFled then
                            fled = safe_call(function() return Capture.HasPermanentlyFled(pal) end) and true or false
                        end
                        if not fled and (not bestAngle or angle < bestAngle) then
                            best, bestAngle, bestDist = pal, angle, dist
                        end
                    end
                end
            end
        end
    end

    -- Exclusion resolved once, on the winner only. If the best candidate IS
    -- the excluded actor we return nothing rather than re-scanning for the
    -- runner-up: the excluded actor is the current Otomo standing right next
    -- to the player, so "the Otomo is the closest thing to my crosshair"
    -- genuinely means the player is not aiming at a wild Pal.
    if best ~= nil and excludeActor ~= nil then
        local excludeName = safe_call(function() return excludeActor:GetFullName() end)
        if excludeName then
            local bestName = safe_call(function() return best:GetFullName() end)
            if bestName ~= nil and bestName == excludeName then
                return nil, nil, nil
            end
        end
    end
    return best, bestDist, bestAngle
end
local function get_individual_parameter(pal)
    local comp = pal.CharacterParameterComponent
    if not comp or not comp:IsValid() then
        return nil
    end
    return safe_call(function() return comp:GetIndividualParameter() end)
end

-- Eighty-eighth pass (2026-09-03): companion to get_individual_parameter,
-- for the OnClose-binding fix below. UPalCharacterParameterComponent has a
-- plain `IndividualHandle` FIELD right next to `IndividualParameter` in the
-- SDK dump (Pal.hpp) — not a by-value struct, just a pointer, so a direct
-- field read is safe by this project's established rule (field access
-- safe, whole-struct-by-value calls risky). This is what lets us get the
-- SAME kind of handle object the real vanilla WorkerRadialMenu dispatch
-- parameter expects in its own `IndividualHandle` field, for ANY Pal actor
-- (wild or owned) — not just the current Otomo.
local function get_individual_handle(pal)
    local comp = pal.CharacterParameterComponent
    if not comp or not comp:IsValid() then
        return nil
    end
    return safe_call(function() return comp.IndividualHandle end)
end

-- Hundred-and-thirty-eighth pass (2026-09-04): Play — item 1 on the
-- saved priority TODO list, a third bonding interaction alongside
-- Pet/Feed. Dragón's own framing: a real player emote (Dance/Beckon)
-- played together with a random Pal idle animation. Split by explicit
-- decision (see hook-points.md/CLAUDE.md, same-day continuation) into
-- two halves: this ships ONLY the Pal-idle half now, using
-- PlayActionByType(pal, PalRandomRest) — the exact same safe call shape
-- as Happy above, just a different EPalActionType value, zero new risk.
-- The player-emote half goes through a DIFFERENT, unproven mechanism
-- (ActionComponent:PlayAction(ActionTarget, actionClass), confirmed real
-- in Pal.hpp as a sibling overload of PlayActionByType — see the new
-- [EMOTE-DIAG] read-only class scan in Interaction.Init()) and is
-- deliberately deferred to its own future pass rather than guessed at
-- here, given this project's crash history with unproven native calls.
--
-- Trust: Dragón asked for Play to grant trust, same amount as Pet/Feed.
-- Unlike do_interaction(), PalRandomRest has no Happy-style automatic
-- friendship side effect to piggyback on, so this calls
-- param:AddFriendShip() directly — the same call already used
-- explicitly elsewhere in this project (Trust.lua), just not previously
-- needed in this file. Exactly ONE call fires per press, so this can't
-- reintroduce the eleventh-pass double-grant bug (that was specifically
-- about TWO calls firing for the same press).
-- Stops the player's cheer when the Pal's Play animation ends (2026-09-12).
-- Dragón: the Pal's animation ends after ~6s, but the player kept cheering
-- until they moved. The emote has no length of its own that matches the Pal's,
-- so it is cancelled at the same moment the Pal's rest animation is.
--
-- Only the emote is cancelled: if the player has since started anything else
-- (an attack, a dodge, a new emote from the game's own wheel is fine to stop
-- too), the current action's name is checked first, so a real action is never
-- cut off. UPalActionComponent::GetCurrentAction / CancelAction, from the
-- header dump; this is singleplayer/self-hosted, so the local cancel is
-- authoritative.
local function stop_player_cheer(player)
    if player == nil then return false end
    return safe_call(function()
        if not player:IsValid() then return false end
        local ac = player.ActionComponent
        if ac == nil or not ac:IsValid() then return false end
        local cur = ac:GetCurrentAction()
        if cur == nil or not cur:IsValid() then return false end
        local name = tostring(cur:GetFullName())
        if name:find("BP_Action_Emote_", 1, true) == nil then return false end
        ac:CancelAction(cur)
        return true
    end) == true
end
Interaction.StopPlayerCheer = stop_player_cheer
-- Exported for the harness: the emote call is where the world-change crash
-- lived (see the parameter block in play_player_emote), so a test has to be
-- able to fire it directly rather than through aiming at a Pal.
function Interaction.PlayPlayerEmote(n)
    return play_player_emote(n)
end

local function do_play()
    Logger.log(string.format("[PalBonds/Interaction] %s pressed — starting Play", PLAY_KEY))
    local player = require("PlayerRef").Get()
    if not player or not player:IsValid() then
        Logger.log("[PalBonds/Interaction] no local PalPlayerCharacter found — are you in-world?")
        return
    end

    local playerActionComp = player.ActionComponent
    if playerActionComp and playerActionComp:IsValid() then
        local playerIdle = safe_call(function() return playerActionComp:ActionIsEmpty() end)
        if playerIdle == false then
            Logger.log("[PalBonds/Interaction] player is already mid-action — ignoring Play press")
            return
        end
    end
    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
    if not originLoc then
        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
    end
    if not originLoc then
        Logger.log("[PalBonds/Interaction] could not read player/camera location")
        return
    end
    local controlRot = safe_call(function() return player:GetControlRotation() end)
    if not controlRot then
        Logger.log("[PalBonds/Interaction] could not read player control rotation")
        return
    end
    local forward = rotator_to_forward(controlRot)
    local pal, dist, angle = find_targeted_pal(originLoc, forward, player)
    if not pal then
        Logger.log(string.format(
            "[PalBonds/Interaction] not looking at any Pal (need within %.0f units and %.0f degrees of center)",
            PET_RANGE, PET_MAX_ANGLE_DEG
        ))
        return
    end
    if Capture.HasPermanentlyFled(pal) then
        Logger.log("[PalBonds/Interaction] this Pal already lost all its trust and fled permanently — refusing Play")
        return
    end
    local actionComp = pal.ActionComponent
    local targetIdle = nil
    if actionComp and actionComp:IsValid() then
        targetIdle = safe_call(function() return actionComp:ActionIsEmpty() end)
    end
    if targetIdle ~= true then
        Logger.log("[PalBonds/Interaction] target is busy or its action state couldn't be read — skipping Play")
        return
    end
    local param = get_individual_parameter(pal)
    if not param or not param:IsValid() then
        Logger.log("[PalBonds/Interaction] targeted Pal has no IndividualParameter — can't grant trust")
        return
    end
    local actorName = safe_call(function() return pal:GetFullName() end)
    Logger.log(string.format(
        "[PalBonds/Interaction] Play targeting %s at %.0f units (%.1f deg off-center)",
        tostring(actorName), dist, angle
    ))

    -- Hundred-and-forty-fifth pass (2026-09-04) REMOVED: the player-Cheer
    -- attempt (PlayAction + :GetClass() on a CDO) that lived here across
    -- the hundred-and-forty-first through hundred-and-forty-fourth
    -- passes. Dragón's real test showed do_play() was dying silently
    -- right after this point every single time — no idle animation, no
    -- Happy follow-up, nothing — meaning something in this block was
    -- throwing an uncaught error that killed the rest of the function
    -- (swallowed by the outer safe_call(do_play) in the keybind handler,
    -- which explains why nothing crashed but Play also did nothing at
    -- all). The leading suspect: `:GetClass()` on a CDO obtained via
    -- StaticFindObject is likely a second instance of the same danger
    -- class as the fortieth pass's real crash (a method call on an
    -- object gotten through an unusual channel, not proven safe just
    -- because a DIFFERENT method — GetClass() — works fine on ordinary
    -- live actors elsewhere in this file). Rather than keep pushing on
    -- an increasingly risky mechanism that was actively breaking the
    -- two things that DO work, pulled it out entirely. The player-emote
    -- half goes back to being deferred to its own separate, later
    -- investigation (matching the original hundred-and-thirty-eighth
    -- pass decision, before this thread's real dump made it look closer
    -- than it turned out to be) — the read-only [EMOTE-DIAG] scan and
    -- the [EMOTE-WATCH] live hooks in Interaction.Init() are left
    -- running (harmless, read-only/hook-registration only) for whenever
    -- that research resumes.
    -- ===============================================================
    -- THE PLAYER CHEERS TOO (2026-09-12)
    -- ===============================================================
    -- Play has always been able to make the PAL react and never the player, and
    -- the player-emote half was deferred for many passes because the call was
    -- unproven and this file has a crash history. The Kick Keybind reference
    -- mod Dragón supplied settled it: that mod ships this exact call and works.
    --
    -- Which emote was still unknown, because the assets are numbered rather
    -- than named. The F7 probe answered it from his own run: cheer is index 0.
    --
    -- ORDERING, AND IT IS THE WHOLE SAFETY ARGUMENT. The cheer fires at the
    -- very END of this function, not here. Read the hundred-and-forty-fifth
    -- pass note directly above: the previous player-Cheer attempt sat at this
    -- exact spot and killed do_play silently every single time -- no idle
    -- animation, no Happy follow-up, no trust -- because an uncaught error here
    -- takes the whole rest of the function with it, swallowed by the outer
    -- safe_call in the keybind handler.
    --
    -- Putting it last makes that failure mode structurally impossible: by the
    -- time the cheer runs, the Pal has already played its animation and the
    -- trust has already been granted or scheduled. The worst case is a missing
    -- player emote, not a dead interaction.
    Logger.log(string.format("[PalBonds/Interaction] target playing: PlayActionByType(pal, PalRandomRest=%d) NOW", ACTION_TYPE_PAL_RANDOM_REST))
    local actionOk, actionErr = pcall(function()
        actionComp:PlayActionByType(pal, ACTION_TYPE_PAL_RANDOM_REST)
    end)
    Logger.log(string.format("[PalBonds/Interaction] target PalRandomRest call returned — result=%s", actionOk and "ok" or tostring(actionErr)))

    -- Hundred-and-forty-third pass (2026-09-04): Dragón's request — some
    -- idle poses don't read as visibly "happy," so sequence the real
    -- Happy reaction right after the idle animation, purely for its
    -- hearts VFX (confirmed baked into BP_ActionHappy's own graph, not
    -- separable — see hook-points.md). PalRandomRest and Happy are
    -- mutually exclusive on the same ActionComponent, so this can't be
    -- simultaneous — first timed-sequencing attempt in this project,
    -- approximated with a fixed delay (PLAY_HAPPY_FOLLOWUP_DELAY_MS; no
    -- proven way yet to read back which specific montage/duration
    -- PalRandomRest actually picked). Trust now comes ENTIRELY from
    -- Happy's own automatic side effect (same mechanism Pet/Feed already
    -- rely on) — the explicit AddFriendShip() call this function used to
    -- make was removed, since keeping it would double-grant once Happy
    -- also fires its own real AddFriendShip (the exact eleventh-pass bug
    -- this project already fixed once). Re-validates pal/actionComp with
    -- :IsValid() before touching them again after the delay, since a
    -- live actor held across a multi-second timer is a genuinely new
    -- category for this project (a wild Pal could in principle despawn
    -- or die in that window) — every other delayed callback in this file
    -- only re-checks CLASSES, never holds a live actor reference.
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(PLAY_HAPPY_FOLLOWUP_DELAY_MS, function()
            -- First, and independent of the Pal still existing: the player's
            -- cheer ends when the Pal's animation does.
            safe_call(function() stop_player_cheer(player) end)
            safe_call(function()
                local palStillValid = pal ~= nil and pal:IsValid()
                local actionCompStillValid = actionComp ~= nil and actionComp:IsValid()
                if not (palStillValid and actionCompStillValid) then
                    Logger.log("[PalBonds/Interaction] Play: target no longer valid when Happy follow-up was due — skipping")
                    return
                end

                -- Hundred-and-forty-fourth pass (2026-09-04) FIX: Dragón's
                -- real test showed the busy-gate check above meant Happy
                -- never fired at all — some species' random-rest montages
                -- run 20+ real seconds (well past the 3s follow-up delay),
                -- so `ActionIsEmpty()` was still false every single time
                -- and this always hit the "skipping" branch. Dragón's own
                -- fix, exactly as asked: after the delay, cut the idle
                -- animation short and force Happy regardless of busy
                -- state, so the trust grant/hearts are never silently
                -- lost to a long-running idle.
                --
                -- Hundred-and-forty-sixth pass (2026-09-04) FIX: just
                -- calling PlayActionByType(Happy) without a real cancel
                -- first didn't actually interrupt anything — confirmed in
                -- the log: the call returned "ok" every time (no Lua
                -- error), but ZERO real AddFriendShip fires happened
                -- anywhere in that whole test session, meaning the engine
                -- silently no-op's a new PlayActionByType call while the
                -- target is still mid-action, rather than auto-
                -- interrupting it — matching Dragón's own direct report
                -- (no visible cut, no hearts). The busy-gate elsewhere in
                -- this file isn't just cosmetic politeness, it reflects a
                -- real engine-level restriction. Found the actual fix in
                -- Pal.hpp: `CancelActionByType(EPalActionType Type)`,
                -- right next to PlayActionByType/PlayAction on the same
                -- ActionComponent, same simple enum-parameter shape
                -- already proven safe everywhere in this file — cancel
                -- the idle animation for real before starting Happy.
                Logger.log(string.format("[PalBonds/Interaction] Play: cancelling PalRandomRest=%d on target NOW", ACTION_TYPE_PAL_RANDOM_REST))
                local cancelOk, cancelErr = pcall(function()
                    actionComp:CancelActionByType(ACTION_TYPE_PAL_RANDOM_REST)
                end)
                Logger.log(string.format("[PalBonds/Interaction] Play: CancelActionByType call returned — result=%s", cancelOk and "ok" or tostring(cancelErr)))
                Logger.log("[PalBonds/Interaction] Play: target playing Happy follow-up (hearts) NOW")
                local happyOk, happyErr = pcall(function()
                    actionComp:PlayActionByType(pal, ACTION_TYPE_HAPPY)
                end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] Play: Happy follow-up call returned — result=%s",
                    happyOk and "ok" or tostring(happyErr)
                ))

                -- Two-hundred-and-seventh pass (2026-09-06) — REAL BUG FIX.
                -- This used to grant nothing at all and simply call
                -- OnWildPalPetted, on the assumption (stated in the old log
                -- line here: "the [WATCH] hook will log the real grant a
                -- couple seconds from now") that the Happy action above
                -- grants friendship as a side effect.
                --
                -- The hundred-and-fifty-ninth pass DISPROVED that with a
                -- controlled 9-datapoint test: Happy() grants exactly zero
                -- in this context. So Play has been worth 0 friendship the
                -- entire time, and the 10 -> 25 rebalance Dragón asked for
                -- in the two-hundred-and-first pass was applied to a
                -- constant that only appears in the fallback branch below —
                -- a branch that runs only if SCHEDULING fails, i.e.
                -- essentially never. Play's number has never once been the
                -- number Dragón configured.
                --
                -- Now granted explicitly, through the same bookkeeping path
                -- Pet and Feed use (ownership-guarded, logs [BALANCE-TEST],
                -- notifies Trust). The Happy animation above still plays —
                -- that part was always fine, it just never paid out.
                safe_call(function()
                    grant_wild_interaction(pal, PLAY_FRIENDSHIP_GAIN, "Play")
                end)
            end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Interaction] Play: could not schedule the Happy follow-up (ExecuteInGameThreadWithDelay failed) — granting trust immediately as a fallback so the interaction isn't silently lost")
        local grantOk, grantErr = pcall(function()
            param:AddFriendShip(INTERACTION_FRIENDSHIP_GAIN, true)
        end)
        Logger.log(string.format("[PalBonds/Interaction] Play fallback AddFriendShip(%d, true) call returned — result=%s", INTERACTION_FRIENDSHIP_GAIN, grantOk and "ok" or tostring(grantErr)))
        if Interaction.OnWildPalPetted then
            Interaction.OnWildPalPetted(pal)
        end
    end

    -- ===============================================================
    -- THE PLAYER CHEERS TOO (2026-09-12)
    -- ===============================================================
    -- Play could always make the PAL react and never the player. The
    -- player-emote half was deferred for many passes because the call was
    -- unproven and this file has a crash history; the Kick Keybind reference
    -- mod Dragón supplied settled it, since that mod ships this exact call and
    -- works in production. Note what it does NOT do: call :GetClass() on a CDO,
    -- which was the leading suspect for the hundred-and-forty-fifth pass's
    -- silent death. The class object from StaticFindObject is passed straight
    -- through, exactly as the reference mod passes it.
    --
    -- Which emote was still unknown, because the assets are numbered rather
    -- than named. The F7 probe answered it from Dragón's own run: cheer is 0.
    --
    -- Deliberately the last statement in the function, and double-guarded
    -- (safe_call here, pcall inside play_player_emote) so that Play keeps
    -- working exactly as it did even if the emote fails outright.
    safe_call(function() play_player_emote(CHEER_EMOTE_INDEX) end)
end

-- Hundred-and-seventy-first pass (2026-09-05): REAL CRASH FOUND — a second,
-- distinct danger from the hundred-and-seventieth pass's reuse hang. This
-- time Dragón pressed CTRL+H immediately followed by "4", close enough
-- together that the real log shows them genuinely interleaved: "4"'s own
-- native menu-opening sequence (CanOpenPlayerActionMenu, the substitution
-- system's own TryGetSpawnedOtomo hook) started firing WHILE
-- do_test_direct_feed_dispatch was still mid-execution, and continued
-- firing (RADIAL-REDIRECT substituting the SAME Pal, a SECOND
-- CanOpenPlayerActionMenu) essentially concurrently with our own direct
-- pal:OnSelectedOrderWorkerRadialMenu(parameter) call — then the log simply
-- stops and a real Windows crash dump followed. Two entirely separate
-- systems doing real native UI/menu construction on the IDENTICAL Pal at
-- the same instant is the likely cause — not the call itself (which has
-- completed cleanly many times in isolation).
--
-- Fix: declared here, BEFORE do_test_direct_feed_dispatch's definition,
-- so it can read the existing radialMenuActionWindowOpen flag (declared
-- much later in this file, where the "4"-menu substitution system lives) —
-- true for exactly the window between a real "4" press's CanOpenPlayer-
-- ActionMenu and its CloseMenu. Checked right before the risky call (not
-- just at function entry, since "4" can be pressed AFTER CTRL+H starts,
-- as it was here) — if the game's own real menu system is active at that
-- moment, abort instead of racing it. This only guards one direction
-- (CTRL+H already running, "4" pressed during it, which is what actually
-- happened) — it cannot detect the reverse order if "4" is pressed first
-- and CTRL+H is pressed a few milliseconds later before its own flag
-- state settles. Given that, the real, standing safety rule for testing
-- stays: never press "4" and CTRL+H close together — wait a couple of
-- seconds between them regardless of order.
local radialMenuActionWindowOpen = false

-- Hundred-and-seventy-seventh pass (2026-09-05): REAL, REPRODUCED FINDING —
-- `RequestUseToCharacter` never actually decrements StackCount for a wild
-- Pal target, confirmed across 6 real feeds (3 Berries all reading 110, 3
-- peaches all reading 10 — zero movement, not intermittent). This matches
-- a limitation already found and worked around once before in this exact
-- project (the old CTRL+J experiment, hundred-and-seventeenth/eighteenth
-- passes): the function silently no-ops for a non-owned target instead of
-- erroring, while working correctly for an owned Otomo. The real "4" menu
-- Feed path ultimately routes through this same function, so it inherits
-- the same wall. Same fix reused: manually decrement ourselves when the
-- game's own call was for a confirmed-wild target.
--
-- Set right before the risky OnSelectedOrderWorkerRadialMenu call in
-- do_real_wild_feed_via_worker_menu (declared before this point in the
-- file, see below), read and cleared in the RequestUseToCharacter post-
-- hook (Init(), later in the file) — declared here, early, so both sides
-- can see the same file-level local (the exact ordering mistake already
-- made twice this session with other shared flags, not repeating it a
-- third time).
local pendingWildFeedTarget = nil

-- Hundred-and-sixty-eighth pass (2026-09-05): Dragón's real, direct
-- question after the first success — does this permanently depend on
-- having fed a real base worker first (this session's own test only
-- worked because a Chikipi had already been fed for real earlier), or was
-- that just this pass's cautious bootstrap? Answer: it's the bootstrap,
-- not a real requirement of the mechanism — find_any_worker_menu_parameter
-- only reused an already-existing live object because reusing a real value
-- is this project's established lower-risk default (same discipline as
-- BaseCampId/ContainerId reuse elsewhere in this file), not because
-- OnSelectedOrderWorkerRadialMenu's Feed branch actually needs one to have
-- come from a real worker interaction. Per the Ghidra trace (hundred-and-
-- sixty-fifth pass), the Feed branch only reads `resultType` off the
-- passed parameter — a fresh, freshly-constructed instance should work
-- exactly the same, using the same StaticConstructObject technique already
-- proven safe in this project (Indicator.lua's trust bar/personality label
-- widgets) — just for a plain dispatch-parameter object instead of a UMG
-- widget this time, a smaller step than constructing a widget.
--
-- This becomes the REAL fallback, tried only when no live one already
-- exists to reuse (reuse still wins when available — free, zero
-- construction risk) — so on a brand new save, with zero real base workers
-- ever interacted with, this should still work standalone.
-- ===========================================================================
-- THE WORLD-CHANGE CRASH FIX (two-hundred-and-eighty-fifth pass, 2026-09-09)
-- ===========================================================================
-- This function built the object that was crashing the game, and the bug was
-- one line: the Outer.
--
--     local player = FindFirstOf("PalPlayerCharacter")
--     local outer = (player and player:IsValid()) and player or paramClass
--
-- The parameter was outered to the PLAYER CHARACTER -- a world actor. We then
-- hand the object to OnSelectedOrderWorkerRadialMenu and the game keeps it,
-- because that is how the picker knows what it is doing. But the thing holding
-- it is the HUD, and the HUD lives under the GameInstance, which SURVIVES a
-- world change. The player character does not.
--
-- So one feed is enough: quit to the menu, the world dies, the player actor and
-- everything outered to it goes with it -- and the surviving HUD is still
-- pointing at our parameter. Load anything afterwards and the HUD touches it.
-- EXCEPTION_ACCESS_VIOLATION, in game code, underneath a UE4SS hook.
--
-- That accounts for every observation Dragon collected, which no earlier theory
-- did: it needs a FEED and never petting (only this path constructs one), it
-- survives capture, it needs no bond and no follower, and it was untouched by
-- three separate rounds of clearing the mod's own Lua tables -- because the
-- dangling pointer was never in Lua. It was an object we made and gave away.
--
-- The fix is to give it a lifetime that matches the thing that stores it. The
-- GameInstance outlives worlds exactly as the HUD does, so an object outered
-- there is still alive whenever the HUD looks at it.
--
-- It is also cached and reused for the whole session rather than rebuilt per
-- feed. Now that these objects outlive worlds, constructing a fresh one every
-- time would pile them up for the life of the process; one reused object also
-- means exactly one thing is ever handed to native code, no matter how much
-- the player feeds.
--
-- Deliberately NOT cleared by ResetForNewWorld: surviving the world change is
-- the entire point.
local cachedWorkerMenuParameter = nil
local function construct_worker_menu_parameter()
    if cachedWorkerMenuParameter ~= nil
       and safe_call(function() return cachedWorkerMenuParameter:IsValid() end) then
        return cachedWorkerMenuParameter
    end
    local classOk, paramClass = pcall(function() return StaticFindObject("/Script/Pal.PalHUDDispatchParameter_WorkerRadialMenu") end)
    if not classOk or not paramClass or not paramClass:IsValid() then
        Logger.log("[PalBonds/Interaction] [FEED-PARAM] StaticFindObject('/Script/Pal.PalHUDDispatchParameter_WorkerRadialMenu') failed: " .. tostring(paramClass))
        return nil
    end

    -- The GameInstance is the correct owner: same lifetime as the HUD that will
    -- hold this object. Falling back to the class object rather than to the
    -- player, because the player is precisely the lifetime that caused the bug.
    local outer = safe_call(function() return UEHelpers.GetGameInstance() end)
    local outerLabel = "GameInstance"
    if outer == nil or not safe_call(function() return outer:IsValid() end) then
        outer = paramClass
        outerLabel = "the parameter class (GameInstance unavailable)"
    end
    local constructOk, newParam = pcall(function()
        return StaticConstructObject(paramClass, outer, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not (constructOk and newParam ~= nil and newParam:IsValid()) then
        Logger.log("[PalBonds/Interaction] [FEED-PARAM] StaticConstructObject(WorkerRadialMenu parameter) FAILED (caught, non-fatal): " .. tostring(newParam))
        return nil
    end
    cachedWorkerMenuParameter = newParam
    Logger.log("[PalBonds/Interaction] [FEED-PARAM] built the WorkerRadialMenu parameter once for this session, outered to " ..
        outerLabel .. " so it outlives a world change like the HUD that stores it")
    return newParam
end
local WORKER_RESULT_FEED = 1 

-- Hundred-and-twenty-seventh pass (2026-09-03): Dragón hit a real practical
-- wall trying to test Skittish→Curious — he can't tell which wild Pals
-- actually rolled "skittish" just by watching them, because ENFORCEMENT
-- (making the rolled tier show up in real AI behavior) is still
-- unconfirmed: a Pal that looks like it's fleeing might just be doing
-- ordinary wild-AI wandering/disengaging, unrelated to our tracked tier.
-- Confirmed directly this session: he petted 5 Pals that visibly ran off
-- Hundred-and-thirty-first pass (2026-09-03): tried `holder:ActivatePalByHandle`
-- (found real/working via the "MultiPals" reference mod) on a targeted wild
-- Pal's handle via a dedicated CTRL+O key. Hundred-and-thirty-second pass
-- confirmed a clean negative result: the call ran without error every time
-- but had zero visible effect on the wild Pal — the same pattern already
-- seen with RequestUseToCharacter. Key removed (continuación 106, at
-- Dragón's request to stop letting keybinds accumulate); the finding and
-- full experiment writeup stay in hook-points.md if this lead is revisited.

-- RETIRED (hundred-and-thirty-eighth pass, 2026-09-04): the
-- hundred-and-seventeenth-through-hundred-and-nineteenth passes' CTRL+J
-- test proved `UPalItemSlot:RequestUseToCharacter` really does consume a
-- real item and feed a Pal — but ONLY when the target resolves to the
-- player's own active Otomo, never an arbitrary wild Pal's
-- FPalInstanceID (confirmed: 0/N fires against a wild BP_ChickenPal_C,
-- consistent success against the player's real Otomo). Combined with
-- Ghidra's earlier finding that the actual vanilla feeding-eligibility
-- check is an unreachable raw C++ vtable call, real food-item feeding
-- for WILD Pals is a confirmed dead end from two independent angles —
-- item 7 on the saved priority list, shelved, do not reopen without new
-- evidence. Full writeup in hook-points.md. CTRL+J itself is reused
-- below for the new Play interaction rather than left dead.

-- Small helpers for reading RegisterHook callback args, same pattern as
-- Spy.lua (params arrive wrapped and need :get(); objects are described
-- via :GetFullName() with a tostring() fallback).
local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end
local function hook_describe(obj)
    if obj == nil then return "nil" end
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and name then return name end
    return tostring(obj)

-- Eighty-first pass (2026-09-03): remembers whatever
-- `PalInteractComponent:StartTriggerInteract` last saw as
-- `TargetInteractiveObject` for a real ActionType=4 press (confirmed,
-- seventy-fourth/seventy-seventh passes, to mean "aiming at a specific
-- Pal's own interactable sphere" — the exact case that opens
-- WBP_WorkerRadialMenu). Read by the real (non-watch-only) selection hook
-- below to know WHICH Pal a Worker-menu Pet/Feed selection was actually
end

-- for. Only ever meaningful for the aimed-Pal case — the "press 4 with no
-- aim target" Player-menu path never fires StartTriggerInteract at all
-- (confirmed seventy-sixth pass), so there's no cross-contamination risk
-- between the two menu systems sharing this one variable.
local lastAimedInteractTarget = nil

-- Eighty-fifth pass (2026-09-03): brackets the short window during which
-- the no-aim WBP_PlayerRadialMenu_C is actually open, so the
-- TryGetSpawnedOtomo redirect below only ever substitutes a wild Pal
-- during that narrow window — never during the ~4/sec ambient calls the
-- eighty-fourth pass proved happen the rest of the time (indicator UI, AI,
-- whatever else reads this getter). `radialMenuWindowGeneration` guards
-- the safety-timeout auto-clear against a stale timer clearing a NEWER
-- open window if menus open/close faster than the timeout.
-- `radialMenuRedirectedThisWindow` (stale note removed hundredth pass —
-- see that pass's comment below where it's actually set for its current,
-- real meaning: "was a wild Pal genuinely substituted this window").
-- radialMenuActionWindowOpen itself is now declared much earlier in this
-- file (hundred-and-seventy-first pass) so do_test_direct_feed_dispatch
-- can read it — not redeclared here, same variable.
local radialMenuWindowGeneration = 0
local radialMenuRedirectedThisWindow = false

-- Ninety-sixth pass: tracks the aimed Pal's name for the dedup described
-- above, reset each time a new window opens so a new "4" press always
-- re-announces even if you happen to aim at the same Pal as last time.
local lastRedirectedWildPalName = nil

-- Two-hundred-and-seventh pass (2026-09-06): the ACTOR, not just its name.
-- closeRadialMenuActionWindow needs a real reference to the wild Pal that
-- was substituted for this window, so it can grant friendship to it
-- directly rather than routing through do_pet()/do_interaction() and being
-- swallowed by that function's anti-spam gate (see grant_wild_interaction's
-- comment for the full bug). Set on every qualifying redirect and cleared
-- when a new window opens, exactly like lastRedirectedWildPalName above —
-- and re-validated with IsValid() at the point of use, since a wild Pal can
-- despawn between the menu opening and the action resolving.
local lastRedirectedWildPalActor = nil

-- Two-hundred-and-eighth pass: throttles [RADIAL-REDIRECT-FIELD] to one
-- line per menu window (it fired 8-10 times per '4' press). Reset when a
-- window opens, same as the two above.
local loggedFieldWriteThisWindow = false

-- Hundredth pass (2026-09-03) FIX: this was 1500ms, and Dragón's live test
-- proved that's too short — real decision events (OnDecidedInstructionCare/
-- Feed) kept firing 3-4 real seconds after the menu opened, well past this
-- safety-timeout, so `radialMenuActionWindowOpen` had already gone false by
-- the time the player actually clicked, silently dropping the ninety-ninth
-- pass's new wild-action wiring (the substitution itself also stops the
-- moment this flag goes false, so a late aim/decision loses the redirect
-- too). CloseMenu itself has now fired reliably in every single test this
-- project has run — it's the real signal this timeout only exists to guard
-- against NEVER firing — so it's safe to make this timeout much more
-- generous without weakening that safety net in practice. 15s covers any
-- realistic amount of time a player might spend aiming/deciding inside the
-- menu; CloseMenu still closes the window immediately the moment it fires.
local RADIAL_ACTION_WINDOW_TIMEOUT_MS = 15000

-- Ninety-ninth pass (2026-09-03): the real "wire it up" step, now that the
-- ninety-eighth pass's live test proved (1) the grey-out is gone and (2)
-- OnDecidedInstructionCare/OnDecidedInstructionFeed genuinely fire on the
-- substituted wild Pal right after a real click. Deliberately NOT trying
-- to decode arg1's exact boolean meaning (the one sample we have — Care
-- fired with arg1=false on a real, confirmed Pet click — doesn't cleanly
-- support a "true=selected" guess either way, and guessing wrong here is
-- exactly the kind of thing this project's discipline says not to do
-- without a real diagnostic). Instead: just remember WHICH named event
-- fired most recently during this window (ignore the argument entirely),
-- and act on it at CloseMenu — a single, always-real, always-once-per-
-- window event, same one already used to end the redirect window itself.
-- `radialMenuRedirectedThisWindow` (already tracked above) is reused as
-- the hard gate for "was a wild Pal actually substituted this window" —
-- this must NEVER fire for the player's own real Otomo, which already has
-- its own working vanilla Pet/Feed path; double-firing our own
-- do_pet()/do_feed() on top of that would reintroduce exactly the kind of
-- double-grant bug fixed early in this project, just for a different
-- system.
local lastDecidedInstruction = nil

-- Hundred-and-second pass (2026-09-03): Dragón reported a real, felt
-- hitch every time the radial menu opens on a wild Pal, and asked to
-- chase it rather than let it sit. `find_targeted_pal` (below, inside the
-- TryGetSpawnedOtomo redirect) calls `FindAllOf("PalCharacter")` — a
-- full scan of every loaded Pal actor — plus one `GetFullName()` and one
-- location read PER pal, every single time it runs. The redirect calls
-- it on every qualifying `TryGetSpawnedOtomo` hook fire while the menu is
-- open, which per the eighty-fourth pass is roughly 4 times a second —
-- and, since the hundredth pass extended the window to 15 real seconds,
-- that's now up to ~60 full actor scans per single "4" press, on a base
-- or in an area where a dozen-plus Pals can easily be loaded at once.
-- That's a real, plausible, and self-inflicted cost, not a guess. Cheap,
-- safe fix: cache the aimed-Pal result for a short window and only
-- re-scan after it expires — a player's aim doesn't meaningfully change
-- within 250ms, so this can't make the feature less responsive, only
-- cheaper. Only caches a REAL found Pal (a "not aiming at anything"
-- result always re-scans next call, which is fine — that's already the
-- less common, less expensive case).
local cachedRedirectWildPal = nil
local lastRedirectComputeClock = nil

-- Two-hundred-and-fourteenth pass: 0.25 -> 0.5. find_targeted_pal still costs
-- 42-70ms per scan even after removing the GetFullName-per-Pal waste (the
-- remainder is FindAllOf plus a location read per Pal, with no cheaper route
-- available), and Dragón's last log had 126 scans over 15ms. The radial menu
-- is only open for a second or two and the player aims before opening it, so
-- recomputing twice a second instead of four times is not noticeable in
-- behaviour and halves the worst hitch in the mod.
local REDIRECT_RECOMPUTE_INTERVAL_S = 0.5

-- Hundred-and-twenty-third pass (2026-09-03): remembers the actual live
-- WBP_PlayerRadialMenu_C widget instance for the currently-open window —
-- the same `self_` `CanOpenPlayerActionMenu`'s hook already receives on
-- every fire, just never kept before. Needed for the new field-write
-- attempt below (see the TryGetSpawnedOtomo redirect's own comment for
-- the full reasoning): the hundred-and-twenty-second pass's live test
-- showed `OpenOtomoFeedInventory` firing identically for both the real
-- Otomo and a substituted wild Pal, while `SelectedFeed` only ever fires
-- for the real one — meaning whatever gates real item selection reads
-- something OTHER than a fresh `TryGetSpawnedOtomo()` call, most likely
-- this exact widget's own cached `SpawnedOtomo` variable (confirmed real
-- via the `RemoteAccessEverything` string dump, sixty-fifth pass).
local lastOpenMenuWidget = nil
local function openRadialMenuActionWindow(widget)
    radialMenuWindowGeneration = radialMenuWindowGeneration + 1
    local myGen = radialMenuWindowGeneration
    radialMenuActionWindowOpen = true
    radialMenuRedirectedThisWindow = false
    lastRedirectedWildPalName = nil
    lastRedirectedWildPalActor = nil
    loggedFieldWriteThisWindow = false
    lastDecidedInstruction = nil
    cachedRedirectWildPal = nil
    lastRedirectComputeClock = nil
    lastOpenMenuWidget = widget
    pcall(function()
        ExecuteInGameThreadWithDelay(RADIAL_ACTION_WINDOW_TIMEOUT_MS, function()
            if radialMenuWindowGeneration == myGen then
                radialMenuActionWindowOpen = false
            end
        end)
    end)

-- do_pet/do_feed are declared earlier in this same file (the F9/F10
-- shared do_interaction() body) so they're already valid upvalues here —
-- no forward declaration needed. Reusing them wholesale means this new
-- path gets do_interaction's own real-time targeting (re-aims from
-- scratch, doesn't trust anything cached from earlier in the window),
-- its busy-gate (a call while an animation is still playing just no-ops,
-- so an accidental double-fire here is harmless), and the Trust.lua
end

-- ownership guard already sitting at the end of that call chain
-- (Capture.IsAlreadyOwned, added after the eighty-second pass's
-- incident) — the exact three protections that make this safe to wire up
-- now where it wasn't yet in the eighty-first pass.
-- Hundred-and-seventy-third pass (2026-09-05): wiring the CONFIRMED-real
-- inventory Feed mechanism (hundred-and-sixty-fifth/seventy-second passes,
-- proven standalone via CTRL+H — no ownership check, no dependency on the
-- Otomo/"4" system at all) into the ACTUAL "4" menu itself, at Dragón's
-- direct request ("lets add it to the menu, lets see how it works with
-- the actual radial menu instead of ctrl+h"), replacing the gesture+Happy
-- approximation (`do_feed`) for wild Pals specifically.
--
-- Reuses the exact same proven call shape as do_test_direct_feed_dispatch:
-- construct a FRESH parameter every time (never reuse — hundred-and-
-- seventieth pass's reproduced hang), write IndividualHandle/resultType,
-- call OnSelectedOrderWorkerRadialMenu directly. Targets
-- `cachedRedirectWildPal` (the same live wild Pal reference this exact
-- menu window has been substituting the whole time) rather than re-aiming
-- from scratch, since by the time the menu is closing the player may no
-- longer be looking at the Pal at all.
--
-- Falls back to the old approximation (do_feed) if anything about the real
-- path fails to even get set up (construction failure, no valid Pal) —
-- never leaves Dragón with silent nothing. Once the real call itself
-- succeeds, do_feed is NOT also called — this is a replacement for wild
-- Feed, not an addition (unlike CTRL+H, which always ran alongside
-- whatever "4" was doing, since it was a separate, independent key).
--
-- Known, expected, and already-documented behavior: the real popup this
-- opens can take several seconds to actually become visible/clickable
-- after the "4" menu itself has already closed — not a bug, confirmed
-- twice now (hundred-and-sixty-eighth/seventy-second passes).
local function do_real_wild_feed_via_worker_menu()
    local wildPal = cachedRedirectWildPal
    if not wildPal or not wildPal:IsValid() then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] no valid cached wild Pal to target — falling back to the approximation")
        return false
    end
    local parameter = construct_worker_menu_parameter()
    if not parameter then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] fresh parameter construction failed — falling back to the approximation")
        return false
    end
    local handle = get_individual_handle(wildPal)
    if handle then
        pcall(function() parameter.IndividualHandle = handle end)
    end
    local setResultOk = pcall(function() parameter.resultType = WORKER_RESULT_FEED end)
    if not setResultOk then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] resultType write failed — falling back to the approximation")
        return false
    end

    -- Hundred-and-seventy-seventh pass: the popup that's about to appear
    -- can take several seconds for the player to act on (confirmed
    -- earlier), so this flag needs to survive until whenever the real
    -- RequestUseToCharacter actually fires — not cleared here, only set.
    pendingWildFeedTarget = wildPal
    Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] calling OnSelectedOrderWorkerRadialMenu(Feed) on the real wild Pal now — the item-picker popup may take a few seconds to actually appear")
    local callOk, callErr = pcall(function() wildPal:OnSelectedOrderWorkerRadialMenu(parameter) end)
    if not callOk then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] call errored: " .. tostring(callErr) .. " — falling back to the approximation")
        return false
    end
    Logger.log("[PalBonds/Interaction] [WILD-ACTION] [REAL-FEED] call returned ok")
    return true

-- Two-hundred-and-seventh pass (2026-09-06) — THE ROOT CAUSE OF THE
-- IRREGULAR FRIENDSHIP GAINS, and the fix.
--
-- The bug: for a radial-menu Pet on a substituted wild Pal, this function
-- called `do_pet()`, which routes into `do_interaction()`. But
-- `do_interaction`'s FIRST gate is "is the player already mid-action? if
-- so, ignore this press" — an anti-spam guard written for a raw keypress.
end

-- On the radial path that guard is not just useless but actively wrong:
-- the whole point of the substitution is that the game's OWN Cuidar action
-- is starting on the player at that exact moment. So the player is
-- legitimately mid-action, the gate fires, and `do_interaction` returns
-- before ever reaching the friendship grant OR the
-- `Interaction.OnWildPalPetted(pal)` call at its end.
--
-- That call is what gates EVERYTHING downstream in Trust.lua: the 20%
-- friendly trigger, the 50% follow trigger, the capture-threshold check,
-- and whether the Pal gets a trust bar at all. So a radial Pet would
-- sometimes register fully and sometimes register nothing, depending purely
-- on whether our call won a race against vanilla's own animation starting.
-- That is exactly the "friendship gains working irregularly" Dragón has
-- been reporting across several runs, and it also explains bars that appear
-- late and thresholds that fire several at once.
--
-- The fix: on the radial path, stop calling `do_pet()` at all. Vanilla is
-- already playing the real animation — we do not want to play another one,
-- we only want the BOOKKEEPING half. `grant_wild_interaction` below is that
-- half, extracted with no busy-gates and no `PlayActionByType`: resolve the
-- wild target, grant the configured amount, notify Trust. It cannot be
-- raced or silently skipped.
-- NOTE: assignment, not `local function` — this fills in the forward
-- declaration near the top of the file (see PLAY_FRIENDSHIP_GAIN's block).
-- Writing `local function` here would create a second, shadowing local and
-- leave do_play's earlier reference permanently nil.
grant_wild_interaction = function(pal, amount, label)
    if pal == nil then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": no target actor — nothing granted")
        return false
    end
    local valid = safe_call(function() return pal:IsValid() end)
    if not valid then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": target actor no longer valid — nothing granted")
        return false
    end

    -- Same hard ownership guard every other real-effect path in this
    -- project uses, and the specific reason the eighty-second pass's
    -- re-capture incident cannot repeat here: an owned Pal is never
    -- granted through this path, and IsAlreadyOwned fails safe toward
    -- "treat as owned".
    local isOwned = safe_call(function() return Capture.IsAlreadyOwned(pal) end)
    if isOwned ~= false then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": target is owned (or ownership unreadable) — refusing to grant, this path is wild-Pal only")
        return false
    end

    -- Two-hundred-and-forty-sixth pass (2026-09-07) — REAL BUG, caught by
    -- Dragón: "are you sure a betrayed pal cannot be interacted with later?
    -- because im pretty sure i could pet again the chikipi i betrayed". He is
    -- right, and the reason is a gap rather than a broken check.
    --
    -- HasPermanentlyFled was being tested in three places — the direct pet, play
    -- and feed handlers — but NOT here, and this is the path the radial menu
    -- actually uses. So the guard covered the keyboard shortcuts, which are all
    -- either removed or secondary, and missed the one route a player really
    -- takes. A Pal that had permanently fled could be petted straight back into
    -- bonding, which quietly undoes the entire consequence.
    if safe_call(function() return Capture.HasPermanentlyFled(pal) end) then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": this Pal already lost all its trust permanently — refusing to grant")
        return false
    end
    local param = get_individual_parameter(pal)
    if not param or not param:IsValid() then
        Logger.log("[PalBonds/Interaction] [GRANT] " .. tostring(label) .. ": could not resolve IndividualParameter — nothing granted")
        return false
    end
    local before = safe_call(function() return param:GetFriendshipPoint() end)
    local grantOk, grantErr = pcall(function() param:AddFriendShip(amount, false) end)
    local after = safe_call(function() return param:GetFriendshipPoint() end)

    -- [BALANCE-TEST] is the line to read during Dragón's 5-interactions-per-
    -- Pal verification run: it states the exact before, the exact after and
    -- the amount intended, so a wrong number is visible directly instead of
    -- being inferred from how many interactions a capture took.
    Logger.log(string.format(
        "[PalBonds/Interaction] [BALANCE-TEST] %s on %s — intended +%s, friendship %s -> %s (call=%s)",
        tostring(label), tostring(safe_call(function() return pal:GetFullName() end)),
        tostring(amount), tostring(before), tostring(after),
        grantOk and "ok" or tostring(grantErr)
    ))
    if Interaction.OnWildPalPetted then
        Interaction.OnWildPalPetted(pal)
    end
    return true

-- F9. Grants a share of the bonding bar directly, with NO interaction played.
--
-- Deliberately different from do_play() in two ways, both of which are the
-- point of the test rather than oversights:
--   * it does NOT require the player to be idle, and
--   * it does NOT require the TARGET to be idle
-- because nothing is played on either of them. do_play() checks both because
end
-- ===========================================================================
-- A PET ONLY COUNTS IF IT HAPPENED (2026-09-16)
-- ===========================================================================
-- Dragón petted two wild Pals mid-attack; the pet visibly failed, yet each
-- gained +50. The grant used to run the moment the radial menu closed with
-- "care" chosen, which says what the player ASKED for, not what happened.
-- The log showed the difference: a pet that works puts the Pal into
-- BP_AIActionPairCall_Petting_C within a moment (the Chillet, and both second
-- pets); both failed pets left the Pal in BP_AIAction_CombatPal_C.
--
-- So the grant now waits: the Pal's current action is checked every
-- PET_VERIFY_POLL_MS for up to PET_VERIFY_MAX_SECONDS, and the points are
-- given the first time it is seen being petted. If that never happens, the
-- pet failed and nothing is granted. The check is a few reads on one Pal,
-- only after a pet was chosen.
local PET_VERIFY_POLL_MS = 250
local PET_VERIFY_MAX_SECONDS = 4.0
local PET_ACTION_MARKER = "Petting"

-- The Pal's current action: its full name and its address (nil if unreadable).
local function current_action(pal)
    local cur = safe_call(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return nil end
        local ac = ctrl:GetAIActionComponent()
        if ac == nil or not ac:IsValid() then return nil end
        local a = ac:GetCurrentAction_BP()
        if a == nil or not a:IsValid() then return nil end
        return a
    end)
    if cur == nil then return nil, nil end
    return safe_call(function() return cur:GetFullName() end), safe_call(function() return cur:GetAddress() end)
end

-- 2026-09-16, run 3 (Lyleen): a second pet chosen while the FIRST pet's
-- animation was still playing was confirmed instantly ("after 0.00s") and paid
-- again. Only a NEW petting animation counts now: one already playing when the
-- pet is chosen is remembered and ignored, and an animation that already paid
-- never pays twice. If addresses cannot be read, the check instead requires
-- the Pal to be seen doing something else first.
local paidPetActionByPal = {}

local function is_pet_action(name)
    return name ~= nil and tostring(name):find(PET_ACTION_MARKER, 1, true) ~= nil
end

local function grant_pet_when_it_happens(pal)
    if pal == nil then return end
    local palKey = safe_call(function() return pal:GetFullName() end) or tostring(pal)
    local startedAt = os.clock()
    local lastSeen = nil
    local startName, startAddr = current_action(pal)
    local oldAddr = is_pet_action(startName) and startAddr or nil
    local sawGap = not is_pet_action(startName)
    local function check()
        if not safe_call(function() return pal:IsValid() end) then
            Logger.log("[PalBonds/Interaction] [PET-CHECK] the Pal is gone before the pet happened — nothing granted")
            return
        end
        local name, addr = current_action(pal)
        lastSeen = name or lastSeen
        if is_pet_action(name) then
            local isNew
            if addr ~= nil and (oldAddr ~= nil or not sawGap) then
                isNew = addr ~= oldAddr
            else
                isNew = sawGap
            end
            if isNew and addr ~= nil and paidPetActionByPal[palKey] == addr then isNew = false end
            if isNew then
                paidPetActionByPal[palKey] = addr
                Logger.log(string.format("[PalBonds/Interaction] [PET-CHECK] pet confirmed after %.2fs — granting", os.clock() - startedAt))
                safe_call(function() grant_wild_interaction(pal, PET_FRIENDSHIP_GAIN, "Pet (radial)") end)
                return
            end
        else
            sawGap = true
        end
        if (os.clock() - startedAt) >= PET_VERIFY_MAX_SECONDS then
            local busy = lastSeen and tostring(lastSeen):match("^(%S+)") or "unknown action"
            if is_pet_action(lastSeen) then busy = busy .. ", still the PREVIOUS pet" end
            Logger.log("[PalBonds/Interaction] [PET-CHECK] the pet never happened (Pal was busy: " .. busy .. ") — nothing granted")
            return
        end
        local ok = pcall(function()
            ExecuteInGameThreadWithDelay(PET_VERIFY_POLL_MS, function() safe_call(check) end)
        end)
        if not ok then
            Logger.log("[PalBonds/Interaction] [PET-CHECK] could not schedule the check — nothing granted")
        end
    end
    check()
end
-- Exported for tools/harness/bosstest.js, like FeedGrantAmount.
Interaction.GrantPetWhenItHappens = grant_pet_when_it_happens

local function closeRadialMenuActionWindow()
    if radialMenuRedirectedThisWindow and lastDecidedInstruction then
        Logger.log("[PalBonds/Interaction] [WILD-ACTION] window closing with a substituted wild Pal and a decided instruction=" .. tostring(lastDecidedInstruction) .. " — firing the real action now")
        if lastDecidedInstruction == "care" then

            -- Bookkeeping only. Vanilla's own Cuidar action is already
            -- playing on this Pal because of the substitution — calling
            -- do_pet() here would try to play a SECOND animation and, far
            -- worse, would be swallowed by its own anti-spam gate.
            -- 2026-09-16: granted only once the pet is seen happening.
            local petTarget = lastRedirectedWildPalActor
            safe_call(function() grant_pet_when_it_happens(petTarget) end)
        elseif lastDecidedInstruction == "feed" then
            local realFeedOk = safe_call(do_real_wild_feed_via_worker_menu)
            if not realFeedOk then

                -- Two-hundred-and-eighty-sixth pass (2026-09-09) -- REMOVED, and
                -- Dragon found why it had to go. He walked up to a Pal, opened
                -- the radial menu, and the Pal fled before the item picker could
                -- open. The feed correctly failed. The Pal gained trust anyway.
                --
                -- What used to be here was a fallback grant of
                -- FEED_FRIENDSHIP_BASE, added in the two-hundred-and-seventh
                -- pass for a narrower case: the dispatch failing to SET UP while
                -- the Pal was still standing there, where granting nothing
                -- looked like a silent bug. The problem is that this branch
                -- cannot tell that apart from the Pal simply leaving, and the
                -- real feed path grants on its own from the
                -- RequestUseToCharacter post-hook (which reads the item actually
                -- consumed, so Kinship Peaches get their own amounts). So the
                -- only thing this branch reliably did was pay out for a feed
                -- that never happened -- free trust for walking up to a Pal and
                -- pressing 4, with no item spent.
                --
                -- Granting nothing is the correct outcome: no item left the
                -- inventory and no interaction reached the Pal.
                Logger.log("[PalBonds/Interaction] the wild feed did not go through (the Pal moved away, or the picker never opened) - granting nothing, since no item was spent and no interaction happened")
            end
        end
    end
    radialMenuActionWindowOpen = false
    lastDecidedInstruction = nil

-- Hundred-and-thirty-eighth pass (2026-09-04): [EMOTE-DIAG]. Read-only,
-- one-shot at Init() — resolves each of the 9 real emote action classes
-- Dragón's own Live-View dump showed live (BP_Action_Emote_0_C through
-- _8_C, all children of BP_Action_Emote_Base_C, confirmed real earlier
-- this pass) via their class default objects, and reads the inherited
-- `EmoteAnimation` field — a plain ObjectProperty pointing at a
-- UAnimMontage, the same safe direct-field-read pattern used everywhere
end

-- ===================================================================
-- [EMOTE] — the player's cheer during Play (pass 326, 2026-09-12)
-- ===================================================================
-- The call comes from the Kick Keybind reference mod Dragón supplied, a
-- shipped mod doing it in production:
--
--     StaticFindObject(".../Emote/BP_Action_Emote_8.BP_Action_Emote_8_C")
--     PC:ActionComponent_PlayAction_ToServer_ForPlayer(Pawn, {}, EmoteClass, 0)
--
-- The emote assets are numbered, not named (BP_Action_Emote_0_C.._8_C, 8 is
-- kick). An F7 probe that cycled through them lived here until Dragón
-- identified the cheer as 0; it was removed once answered. If another emote
-- ever needs identifying, the probe is in git history (commit 1ca339b).
local EMOTE_PATH_FMT = "/Game/Pal/Blueprint/Action/Palmi/Emote/BP_Action_Emote_%d.BP_Action_Emote_%d_C"

local function resolve_emote_class(n)
    return safe_call(function()
        return StaticFindObject(string.format(EMOTE_PATH_FMT, n, n))
    end)
end

-- Guarded player-controller lookup. The Kick mod uses FindFirstOf, but this
-- project routes player lookups through FindAllOf on purpose -- upstream UE4SS
-- issue #1328 makes FindFirstOf read out of bounds and it lacks the null guard
-- FindAllOf has (see the known-defects list).
local function find_player_controller()
    -- 2026-09-15 (profiling): the player's character already holds its
    -- controller, so ask it first. The world search below cost 53ms on a single
    -- F8 press in run D and is now only the fallback when that read fails.
    local player = require("PlayerRef").Get()
    if player ~= nil then
        local pc = safe_call(function() return player.Controller end)
        if pc ~= nil and safe_call(function() return pc:IsValid() end) then return pc end
    end
    local list = safe_call(function() return FindAllOf("BP_PalPlayerController_C") end)
    if type(list) ~= "table" then return nil end
    for _, pc in ipairs(list) do
        if pc ~= nil and safe_call(function() return pc:IsValid() end) then return pc end
    end
    return nil
end

play_player_emote = function(n)
    local cls = resolve_emote_class(n)
    if cls == nil or not safe_call(function() return cls:IsValid() end) then
        Logger.log("[PalBonds/Interaction] [EMOTE] emote " .. n .. " does not resolve — skipping")
        return false
    end
    local pc = find_player_controller()
    if pc == nil then
        Logger.log("[PalBonds/Interaction] [EMOTE] no BP_PalPlayerController_C — are you in-world?")
        return false
    end
    local pawn = safe_call(function() return pc.Pawn end)
    if pawn == nil or not safe_call(function() return pawn:IsValid() end) then
        Logger.log("[PalBonds/Interaction] [EMOTE] the player controller has no valid Pawn")
        return false
    end
    -- Through the player's own ActionComponent: no parameter block, nothing
    -- networked, the same shape of call this mod already makes on Pals.
    --
    -- History, so nobody chases it again (2026-09-17): this used to be
    -- pc:ActionComponent_PlayAction_ToServer_ForPlayer(pawn, {}, cls, 0), from the
    -- Kick Keybind reference mod, and the empty `{}` for its
    -- FActionDynamicParameter was briefly blamed for the world-change crash.
    -- It was not: filling the block in made UE4SS refuse the call, so the emote
    -- simply never played. The real cause was that F8 ran this OFF the game
    -- thread -- see run_on_game_thread near Interaction.Init.
    local playerActionComp = safe_call(function() return pawn.ActionComponent end)
    if playerActionComp == nil or not safe_call(function() return playerActionComp:IsValid() end) then
        Logger.log("[PalBonds/Interaction] [EMOTE] the player has no readable ActionComponent — skipping the cheer")
        return false
    end
    local ok, err = pcall(function()
        playerActionComp:PlayAction(pawn, cls)
    end)
    Logger.log("[PalBonds/Interaction] [EMOTE] BP_Action_Emote_" .. n ..
        "_C via ActionComponent:PlayAction — " .. (ok and "call ok" or ("FAILED: " .. tostring(err))))
    return ok
end

-- ===================================================================
-- FEED AMOUNT BY ITEM RARITY (2026-09-12)
-- ===================================================================
-- The item's rarity comes from its STATIC definition (UPalStaticItemDataBase,
-- field Rarity), via UPalUtility::GetItemIDManager + GetStaticItemData. Pass
-- 183 proved that exact route in game (Kinship Peach full = Rarity 3, lesser =
-- Rarity 1) after two crashes, and both of that pass's fixes are required
-- here: the world context must be a LIVE in-world actor (a CDO crashed), and
-- the item id must be a real FName built with FindOrAddFName (a plain Lua
-- string crashed).
--
-- ASSUMED, to be confirmed by the [FEED-RARITY] log line: rarity 0 = common up
-- to 4 = legendary. Anything above 4 is treated as legendary.
--
-- Cached per item id -- static data never changes, and the table is bounded by
-- the number of item types. Failures are not cached, so they are retried.
local itemRarityCache = {}
local function read_item_rarity(itemId, worldContext)
    if type(itemId) ~= "string" or worldContext == nil then return nil end
    local cached = itemRarityCache[itemId]
    if cached ~= nil then return cached end
    local rarity = safe_call(function()
        if not worldContext:IsValid() then return nil end
        local utility = StaticFindObject("/Script/Pal.Default__PalUtility")
        if utility == nil or not utility:IsValid() then return nil end
        local manager = utility:GetItemIDManager(worldContext)
        if manager == nil or not manager:IsValid() then return nil end
        local data = manager:GetStaticItemData(UEHelpers.FindOrAddFName(itemId))
        if data == nil or not data:IsValid() then return nil end
        return data.Rarity
    end)
    if type(rarity) == "number" then itemRarityCache[itemId] = rarity end
    return rarity
end

-- Returns the friendship a wild feed grants and a short note for the log.
function Interaction.FeedGrantAmount(itemId, worldContext)
    if itemId == "AffectionFruit_02" then
        return KINSHIP_PEACH_LESSER_FRIENDSHIP_BASE, "Kinship Peach (lesser), own amount"
    elseif itemId == "AffectionFruit_01" then
        return KINSHIP_PEACH_FULL_FRIENDSHIP_BASE, "Kinship Peach, own amount"
    end
    local rarity = read_item_rarity(itemId, worldContext)
    if type(rarity) ~= "number" then
        return FEED_FRIENDSHIP_BASE, "rarity UNREADABLE, base amount only"
    end
    local tier = math.max(0, math.min(4, math.floor(rarity)))
    return FEED_FRIENDSHIP_BASE + FEED_RARITY_BONUS[tier], "rarity " .. tostring(rarity)
end

-- ===================================================================
-- KEYBINDS RUN OFF THE GAME THREAD (pass 333, 2026-09-17) — THE CRASH
-- ===================================================================
-- Dragón's bisect ended here, and the answer was never in the quit path at all:
--
--   pet only  -> clean      feed only -> clean      Play (F8) -> crash
--
-- Pet and Feed reach the mod through RegisterHook, which fires INSIDE the
-- game's own call stack — the game thread. F8 reaches it through
-- RegisterKeyBind, which UE4SS services on its OWN thread. From there the mod
-- was starting animations, allocating action objects and queueing montages
-- straight into the engine, off-thread. Nothing fails at the time; the engine
-- state is quietly corrupted and the next world load reads freed memory —
-- EXCEPTION_ACCESS_VIOLATION 0x338, in game code, under UE4SS. Which is
-- exactly why four correct fixes to the world-change handling changed nothing,
-- and why the two clean v1.1.1 runs were the pet-only and feed-only ones.
--
-- UE4SS's own maintainer (narknon, issue #1345, already quoted in
-- docs/hook-points.md) says the same thing about their async entry points:
-- use the in-game-thread helpers. This mod does that everywhere EXCEPT its
-- keybinds, which is the one place it touched the engine directly.
--
-- So every keybind body now hops onto the game thread first. The cost is one
-- scheduled callback per press.
local function run_on_game_thread(fn)
    local direct = pcall(function() ExecuteInGameThread(function() safe_call(fn) end) end)
    if direct then return true end
    local delayed = pcall(function() ExecuteInGameThreadWithDelay(1, function() safe_call(fn) end) end)
    if delayed then return true end

    -- Neither helper exists: better to do the work late than not at all, but
    -- say so, because this is the state the crash lived in.
    Logger.log("[PalBonds/Interaction] [KEYBIND] could not reach the game thread — running directly, which is what used to corrupt the next world load")
    safe_call(fn)
    return false
end

function Interaction.Init()
    Logger.log(string.format("[PalBonds/Interaction] %s = Play — random Pal idle animation + trust grant, same range/gating as Pet/Feed", PLAY_KEY))
    RegisterKeyBind(Key[PLAY_KEY], function()
        run_on_game_thread(do_play)
    end)

    RegisterKeyBind(Key.F9, function()
        -- Same game-thread hop as Play (pass 333): this one touches live
        -- nameplate widgets and shows a toast, both engine work.
        run_on_game_thread(function()
            local okI, IndicatorMod = pcall(require, "Indicator")
            if not (okI and IndicatorMod and IndicatorMod.TogglePersonalityLabels) then
                Logger.log("[PalBonds/Interaction] [TAG-TOGGLE] Indicator.TogglePersonalityLabels is unavailable — nothing toggled")
                return
            end
            local nowVisible = IndicatorMod.TogglePersonalityLabels()
            safe_call(function()
                local okC, CaptureMod = pcall(require, "Capture")
                if okC and CaptureMod and CaptureMod.ShowToast then
                    CaptureMod.ShowToast(nowVisible
                        and "Personality tags: ON"
                        or "Personality tags: OFF")
                end
            end)
        end)
    end)

    -- Two-hundred-and-eighty-sixth pass: F10 toggles the followers' passive
    -- friendship drip. F10 was the old Feed key back when interactions were on
    -- bare function keys; nothing has been bound to it since the radial menu
    -- took over, so it is free.
    RegisterKeyBind(Key.F10, function()
        -- Same game-thread hop as Play (pass 333): this one touches live
        -- nameplate widgets and shows a toast, both engine work.
        run_on_game_thread(function()
            local okT, TrustMod = pcall(require, "Trust")
            if not (okT and TrustMod and TrustMod.TogglePassiveFriendshipGain) then
                Logger.log("[PalBonds/Interaction] [PASSIVE-TOGGLE] Trust.TogglePassiveFriendshipGain is unavailable — nothing toggled")
                return
            end
            local nowOn = TrustMod.TogglePassiveFriendshipGain()
            safe_call(function()
                local okC, CaptureMod = pcall(require, "Capture")
                if okC and CaptureMod and CaptureMod.ShowToast then

                    -- Says the state first, then what it means. The state is
                    -- the part being asked for; the sentence after it is there
                    -- because "OFF" alone does not tell a player whether they
                    -- just lost the trust their followers had already earned.
                    CaptureMod.ShowToast(nowOn
                        and "Passive bonding: ON - your Pals grow closer over time."
                        or "Passive bonding: OFF - your Pals keep the trust they have.")
                end
            end)
        end)
    end)

    -- Hundred-and-fifteenth pass (2026-09-03): the hundred-and-third
    -- pass's SelectedFeedingItem watch just went through three confirmed
    -- real Otomo feeds (via the vanilla radial menu, read straight out of
    -- Dragón's own UE4SS.log) without firing ONCE — a clean negative
    -- result. Reading Dragón's own Live View dumps from that same session
    -- instead revealed the real mechanism: a full Blueprint AI-action
    -- pairing (BP_ActionPairStandby_FeedItem_C /
    -- BP_ActionPairBehavior_FeedItem_C / BP_AIActionPairCall_FeedItem_C)
    -- carrying the real FeedItemSlotId/FeedItemNum as plain fields —
    -- too much machinery (animation montages, camera work, a whole
    -- PawnAction-based AI queue) to safely replicate for a wild Pal. See
    -- hook-points.md's hundred-and-fourteenth pass for the full writeup.
    --
    -- But UPalItemSlot itself — the object those FeedItemSlotId values
    -- point AT — has its own native method, found in the same SDK dump
    -- that found UPalItemSlot in the first place (hundred-and-thirteenth
    -- pass): `RequestUseToCharacter(FPalIndividualCharacterHandle
    -- TargetCharacterID, int32 UseNum)`. If vanilla actually calls THIS
    -- to consume the item — plausible, since it's a method ON the slot
    -- holding the item, named exactly for "use this on a character" —
    -- it would be a much simpler, much safer path for us: find the live
    -- slot object holding the food (FindAllOf, the same proven-safe
    -- pattern used everywhere else in this file), read the target
    -- handle directly off an already-live Pal exactly like
    -- get_individual_handle() already does, and call this method ON THE
    -- OBJECT WE FOUND — never constructing a new FPalItemSlotId struct
    -- from scratch, which is the exact pattern that caused Crash #4.
    -- WATCH ONLY for now, same zero-risk discipline as every hook in
    -- this file: confirm it's real and see its real argument shapes
    -- before ever calling it ourselves. Test plan: feed the Otomo again
    -- through the normal radial menu (no new keybind needed) and check
    -- the log for a [SLOT-USE-DIAG] line.
    --
    -- HUNDRED-AND-SIXTEENTH PASS (2026-09-03) FIX: Dragón's very first
    -- test came back with a real, clean hit — THREE TIMES, in fact — and
    -- proved this really is the live consumption call: StackCount read
    -- 65, then 64, then 63 on three separate real fires, each with
    -- UseNum=1, a perfect one-for-one decrement. That's the confirmation
    -- this whole diagnostic existed to get. The only problem was
    -- cosmetic: plain tostring() on an FGuid or FName field in UE4SS Lua
    -- just prints its userdata address ("UScriptStruct: 0x...",
    -- "FNameUserdata: 0x..."), not the human-readable value — both
    -- FGuid and FName support a real :ToString() method that does what
    -- we actually want (confirmed by the earlier Live View JSON dumps
    -- rendering ContainerId as "(ID=<32-hex>)" and ItemId.StaticId as a
    -- plain string). Added a small `readable()` helper that tries
    -- `:ToString()` first and only falls back to plain tostring() if
    -- that fails — a method call on a value we already safely read off
    -- a live object, not a new native call with constructed arguments,
    -- so this carries the same zero risk as the rest of this watch.
    local function readable(value)
        if value == nil then return "nil" end
        local ok, str = pcall(function() return value:ToString() end)
        if ok and str ~= nil then return str end
        return tostring(value)
    end
    local okWatchUseSlot = pcall(function()
        RegisterHook("/Script/Pal.PalItemSlot:RequestUseToCharacter", function() end,

        -- Hundred-and-seventy-seventh pass (2026-09-05): POST-hook added —
        -- confirmed via 6 real feeds (3 Berries at 110, 3 peaches at 10,
        -- zero movement across all 6) that this function silently no-ops
        -- the real decrement for a wild target, matching a limitation
        -- already found once before in this project (the old CTRL+J
        -- experiment against RequestUseToCharacter directly). Only acts
        -- when `pendingWildFeedTarget` was set moments earlier by
        -- do_real_wild_feed_via_worker_menu (the real "4" menu's wild-Feed
        -- path) — never touches a normal owned-Pal feed, which already
        -- decrements correctly on its own (confirmed via this same
        -- session's party-Pal feeds, 114->113->112->111).
        function(Context, TargetCharacterID, UseNum)
            local wildTarget = pendingWildFeedTarget
            pendingWildFeedTarget = nil 
            if not wildTarget or not wildTarget:IsValid() then return end
            local slot = hook_get(Context)
            local useNum = hook_get(UseNum)
            if not slot or not slot:IsValid() or type(useNum) ~= "number" then
                Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] pending wild feed but slot/useNum unreadable — skipping")
                return
            end
            local beforeCount = safe_call(function() return slot.StackCount end)
            if type(beforeCount) ~= "number" then
                Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] could not read StackCount — skipping")
                return
            end
            local newCount = beforeCount - useNum
            if newCount < 0 then newCount = 0 end
            local writeOk, writeErr = pcall(function() slot.StackCount = newCount end)
            Logger.log(string.format(
                "[PalBonds/Interaction] [SLOT-USE-DIAG] [MANUAL-DECREMENT] wild target confirmed — real decrement never applies for a wild Pal, applying it ourselves: %d -> %d (write %s)",
                beforeCount, newCount, writeOk and "ok" or ("FAILED: " .. tostring(writeErr))
            ))

            -- Hundred-and-eighty-fifth pass (2026-09-05): real Feed for
            -- wild Pals grants ZERO trust today (this exact function is
            -- the confirmed reason why — the real consumption itself
            -- never reaches any friendship-granting code for a wild
            -- target, same as it never reached the real decrement).
            -- Nothing to conflict with, so this grants directly: the
            -- Kinship Peach's REAL discovered bonus if that's the item
            -- consumed (AffectionFruit_02/01), else the plain Feed base
            -- amount. Not scaled by the level-gap multiplier (that only
            -- affects the bonding threshold's SIZE now, not individual
            -- gains — see Trust.lua's BONDING_TRIGGER_THRESHOLD_BASE).
            local itemId = safe_call(function() return slot.ItemId and readable(slot.ItemId.StaticId) end)
            local grantAmount, rarityNote = Interaction.FeedGrantAmount(itemId, wildTarget)
            Logger.log(string.format("[PalBonds/Interaction] [FEED-RARITY] %s -> %d friendship (%s)",
                tostring(itemId), grantAmount, tostring(rarityNote)))

            -- Two-hundred-and-fifty-fourth pass (2026-09-07) — the last hole,
            -- and the log names it exactly. After a real betrayal, lines 815 and
            -- 833 show Pet and Feed both correctly REFUSED... and line 848 shows
            -- this path handing over 75 friendship anyway, four times in a row,
            -- until the Chikipi was back over the threshold and following again.
            --
            -- This is the REAL inventory feed -- the vanilla item-consumption
            -- route, reached through the RequestUseToCharacter hook -- and it
            -- grants directly rather than going through grant_wild_interaction,
            -- so it never saw the guard added there. Every other way of giving a
            -- Pal friendship now checks; this one did not, which made the
            -- permanence of betrayal a fiction as long as the player had berries.
            if safe_call(function() return Capture.HasPermanentlyFled(wildTarget) end) then
                Logger.log("[PalBonds/Interaction] [FEED-FRIENDSHIP] this Pal permanently lost its trust — the food is consumed but no friendship is granted")
                return
            end
            local param = get_individual_parameter(wildTarget)
            if param and param:IsValid() then
                local grantOk, grantErr = pcall(function() param:AddFriendShip(grantAmount, false) end)
                Logger.log(string.format(
                    "[PalBonds/Interaction] [FEED-FRIENDSHIP] real wild Feed granting %d friendship (item=%s) — result=%s",
                    grantAmount, tostring(itemId), grantOk and "ok" or tostring(grantErr)
                ))
            else
                Logger.log("[PalBonds/Interaction] [FEED-FRIENDSHIP] could not resolve wild target's IndividualParameter — no friendship granted")
            end
            if Interaction.OnWildPalPetted then
                Interaction.OnWildPalPetted(wildTarget)
            end
        end)
    end)
    if not okWatchUseSlot then
        Logger.log("[PalBonds/Interaction] [SLOT-USE-DIAG] could not install PalItemSlot:RequestUseToCharacter watch hook (name may need adjusting)")
    end

    -- ---------------------------------------------------------------
    -- Forty-second pass (2026-09-03): the REAL radial-menu ("4" key)
    -- Pet/Feed system, prompted by Dragón asking to move off F9/F10 and
    -- onto the game's own UI ("its already kind of annoying to try and
    -- find a key that's usually not in the game like f9 and f10, im just
    -- used to pet and feed pals with the radial menu"). The thirteenth-
    -- pass MENU-WATCH hooks above (native PalInteractComponent) turned
    -- out NOT to be it — a full log review showed ActionType=1 always has
    -- real Start+End pairs but only against non-Pal objects (PalBox,
    -- storage, fast-travel towers); ActionType=2/3/4 only ever appear as
    -- orphaned EndTriggerInteract calls every few seconds regardless of
    -- player action — an unrelated periodic background reset, not a real
    -- radial-menu selection.
    --
    -- Real lead instead, found by reading this project's OWN actual game
    -- file directly rather than guessing: `Pal-Windows.pak` (the real,
    -- unencrypted 40GB main asset archive already sitting on disk) opened
    -- with `repak` (same tool already used on reference mods) revealed
    -- the real radial-menu widget assets:
    --   /Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu
    --   /Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu_MenuContent
    -- Reading their compiled string tables (`strings`, same technique
    -- proven in the sixty-fifth pass's BindFromHandle fix) surfaced real
    -- function names: CreatePlayerActionMenu / OpenPlayerActionMenu /
    -- "Can Open Player Action Menu" (the eligibility gate) /
    -- OnDecidedPlayerActionMenu / "On Decided Instruction Care" /
    -- OnDecidedInstruction_Feed. The path FORMAT below
    -- (<package path>.<ClassName>:<FunctionName>) is the same
    -- confirmed-correct shape the sixty-fifth pass already proved works
    -- for Blueprint targets — this is the first time this project points
    -- that proven shape at a NEW class, using a real path instead of a
    -- guess.
    --
    -- IMPORTANT CAVEAT, found in the same string dump: this whole system
    -- is built around the player's OWN ACTIVE OTOMO
    -- (GetOtomoHolderComponent, TryGetSpawnedOtomo, SpawnedOtomo,
    -- IsOtomoActivated...) — not a generic "whatever Pal you're looking
    -- at" system. It may simply have no concept of a wild, unowned target
    -- at all. That is exactly the open question these hooks exist to
    -- answer — WATCH ONLY, zero side effects, same discipline as the
    -- thirteenth-pass hooks above, before deciding whether wild Pals can
    -- hook in here or need a different (possibly custom-built) UI. Also
    -- worth noting: EPalOtomoPalOrderType (the enum behind
    -- RequestSetOtomoOrder/SetOtomoOrder_ToServer, watched below too) only
    -- has 3 values — Default/Warlike/NotCombat, a combat-STANCE toggle,
    -- NOT Care/Feed/Attack/Assist/Escape as the message-ID names
    -- (PAL_INSTRUCTION_CARE etc., also found in the same string dump)
    -- previously suggested — those are just UI text labels. The real
    -- per-instruction trigger functions are the Blueprint ones below.
    --
    -- Test plan for next session: press "4" near your own active Otomo
    -- and actually pick Care, then Feed, from the wheel — the log should
    -- show which of these fire, in what order, with what args. Then try
    -- the same while looking at a WILD Pal (no Otomo targeted) to see
    -- whether ANY of this fires at all — that answers the ownership-gate
    -- question directly instead of guessing, and decides the next step
    -- toward removing F9/F10.
    -- CORRECTION made while writing this pass, before ever deploying:
    -- re-running `strings` specifically on WBP_PlayerRadialMenu_MenuContent
    -- alone (not the combined dump) shows it only contains generic
    -- container/text-block strings (PalRetainerBox, BP_PalTextBlock) — no
    -- Care/Feed/Otomo/instruction strings at all. Every interesting name
    -- above (OnDecidedPlayerActionMenu, "On Decided Instruction Care",
    -- OnDecidedInstruction_Feed, DecideMenuAction) actually came from the
    -- OUTER WBP_PlayerRadialMenu.uasset/.uexp pair, not from MenuContent.
    -- MenuContent looks like a generic, reusable "content slot" container
    -- the outer wheel pushes whichever child widget into (construction
    -- list, Otomo swap icons, instruction icons, etc.), not where the
    -- decision logic itself lives. So every candidate below now targets
    -- the one real class, WBP_PlayerRadialMenu_C.
    -- FORTY-THIRD PASS (2026-09-03) RESULT + FIX: Dragón's test came back
    -- with two real findings.
    --
    -- (1) Dragón corrected a wrong assumption in the comment above: the
    -- radial menu is NOT limited to your one active/following Otomo. He
    -- petted a Lamball with it (active Otomo), then took a Tanzee out at
    -- his base to roam, aimed at IT specifically, and petted it the same
    -- way. The live [MENU-WATCH] log (native PalInteractComponent, already
    -- hooked since the thirteenth pass) proves this directly — it shows a
    -- real ActionType=4 Start+End pair firing repeatedly, with a REAL
    -- TargetInteractiveObject: a "PalInteractableSphereComponentNative" on
    -- the targeted Pal actor. This directly contradicts this project's own
    -- earlier read of ActionType=2/3/4 as "unrelated periodic background
    -- calls" — that read was wrong, or at least incomplete: ActionType=4
    -- clearly IS the real per-Pal radial-interact trigger, gated by AIMING
    -- (a Pal exposes its own interactable sphere; the interact system
    -- finds whichever one you're looking at), not by "is this my current
    -- active Otomo." That's good news for wild Pals — the gate is more
    -- likely an ownership check somewhere upstream, not a hard "must be
    -- the one active Otomo" restriction.
    --
    -- (2) EVERY ONE of the 8 Blueprint hook candidates below FAILED with
    -- "no UFunction with the specified name was found" — the path FORMAT
    -- is confirmed correct (same shape as the working BindFromHandle fix),
    -- so this points at the NAMES themselves. Re-examining the string dump:
    -- `strings` can't tell a real callable FName apart from a cosmetic
    -- "DisplayName" — and Unreal auto-generates a spaced-out DisplayName
    -- from a PascalCase FName for the editor UI (e.g. real name
    -- `CanOpenPlayerActionMenu` displays as "Can Open Player Action Menu").
    -- The strings dump's OWN pin name `CallFunc_Can_Open_Player_Action_
    -- Menu_Result` is strong evidence for this: it's Unreal's auto-derived
    -- pin name for a call to `CanOpenPlayerActionMenu`, splitting the real
    -- PascalCase FName at capitals and joining with underscores — which
    -- only produces that exact pin name if the real FName has NO spaces.
    -- So the spaced strings seen earlier were very likely just cosmetic
    -- display text, not the real hookable name. Fixed by trying the
    -- no-space PascalCase form FIRST, keeping the originally-observed
    -- spaced form as a fallback candidate in case this guess is wrong.
    --
    -- Also added: a bounded retry over time (same discipline as
    -- Indicator.lua's register_bind_hook_once/MAX_BIND_HOOK_ATTEMPTS) in
    -- case the REAL problem is that this widget class simply isn't loaded
    -- yet this early (mod Init() runs at game boot, likely before the
    -- radial menu widget is ever constructed) rather than a naming issue —
    -- covers both possibilities without guessing which one it is.
    local RADIAL_MENU_CLASS = "/Game/Pal/Blueprint/UI/PlayerRadialMenu/WBP_PlayerRadialMenu.WBP_PlayerRadialMenu_C"

    -- Ninety-seventh pass (2026-09-03) FIX: the 12:05-12:08 test session's
    -- log proved this budget was the real problem, not the ninety-sixth
    -- pass's redirect-window fix. `RADIAL-REDIRECT` fired ZERO times that
    -- session despite 7 real "4" presses — because EVERY hook on
    -- WBP_PlayerRadialMenu_C (including "Can Open Player Action Menu",
    -- the exact hook that arms the redirect window) failed all 8 rounds
    -- and gave up at ~12:06:07, roughly 37s after mod load — but Dragón's
    -- first "4" press wasn't until 12:07:39, ~90s AFTER the retry loop had
    -- already quit. Same simultaneous "giving up" failure hit
    -- INDICATOR-WATCH (x2), WORKER-WATCH (x2), and WORKER-BIND-FIX in the
    -- same few seconds — strong evidence this is a general "these
    -- Blueprint UI widget classes just aren't loaded into memory yet this
    -- early" timing issue (they likely only load on first real
    -- construction, i.e. the player's first actual menu-open), not a
    -- per-class naming problem — the names above are mostly already
    -- confirmed real across many past sessions (pass 77's comment above).
    --
    -- Fix: extend the shared retry budget from 8 rounds (40s total) to 60
    -- rounds (5 minutes total) at the same 5s cadence. Kept it a bounded
    -- number rather than infinite retry — a couple of candidates in these
    -- target lists (ChangeMode/DecideMenuAction) are still unconfirmed
    -- guesses, and this project has hit real lag bugs from unbounded
    -- per-round logging twice before (ninety-third/ninety-fifth passes) —
    -- so an eventual stop still exists, just far enough out to plausibly
    -- cover a normal player's actual pre-first-"4"-press delay.
    local MAX_RADIAL_HOOK_ROUNDS = 60
    local RADIAL_HOOK_RETRY_MS = 5000

    -- Cadence after the fast rounds are spent, while the class has still never
    -- loaded. One pcall'd RegisterHook every 15s costs nothing and is the only
    -- thing standing between a slow load and a session where "4" does nothing.
    local RADIAL_HOOK_SLOW_RETRY_MS = 15000

    -- Seventy-ninth pass (2026-09-03) cleanup: Dragón saw a burst of
    -- repeated failure lines fire in quick succession and asked to trim
    -- out whatever's already confirmed dead, to cut the noise. Two kinds
    -- of trims applied here, both backed by real log evidence from full
    -- prior sessions (not guesses):
    --   1. REMOVED outright — RegisterHook itself failed for these on
    --      EVERY one of 8 rounds in a session where sibling candidates on
    --      this exact same class succeeded (proving the class WAS loaded
    --      and reachable): SelectMapObjectId, SelectPageByMapObject,
    --      SelectPageAndIndex, IsOpened. These names conclusively don't
    --      exist on WBP_PlayerRadialMenu_C under any form tried.
    --   2. SIMPLIFIED to one candidate — CanOpenPlayerActionMenu and
    --      OnDecidedInstructionCare both confirmed live (seventy-sixth
    --      pass) to be the SPACED form only; the no-space PascalCase guess
    --      always failed first. Dropped the dead guess, kept the real name.
    -- Left `ChangeMode`/`DecideMenuAction` alone — no direct evidence
    -- either way (they simply never appeared in a "confirmed working" list,
    -- which could mean the names are wrong OR just that Dragón's test never
    -- triggered whatever they correspond to). Also left the
    -- OpenSetup/CloseSetup/SetupEvent/OpenMenu/CloseMenu/IsAnyMenuOpened
    -- dual-candidate entries alone — pass 77 confirmed these six DO work,
    -- but the live log that would show WHICH of the two name forms
    -- actually fired no longer exists (Logger.lua truncates per session),
    -- so trimming the "wrong" one blind risks deleting the real one.
    local radialHookTargets = {

        -- Eighty-fifth pass: this is the earliest confirmed-real signal
        -- that a "4"-press's no-aim menu is opening (fires first, every
        -- cycle, per the eighty-fourth pass's live log) — used to open the
        -- narrow TryGetSpawnedOtomo redirect window below, nothing else.
        { tag = "CanOpenPlayerActionMenu", candidates = {"Can Open Player Action Menu"}, onFire = openRadialMenuActionWindow },

        -- Ninety-ninth pass: these two now also record which instruction
        -- was last decided during the CURRENT window (see
        -- lastDecidedInstruction above) — deliberately ignoring the
        -- event's own arg1, whose exact meaning isn't confirmed yet (see
        -- the comment above lastDecidedInstruction's declaration). The
        -- actual real-world effect only happens later, at CloseMenu, and
        -- only if radialMenuRedirectedThisWindow is also true.
        { tag = "OnDecidedInstructionCare", candidates = {"On Decided Instruction Care"}, onFire = function()
            if radialMenuActionWindowOpen then
                lastDecidedInstruction = "care"
            end
        end },
        { tag = "OnDecidedInstructionFeed", candidates = {"OnDecidedInstruction_Feed"}, onFire = function()
            if radialMenuActionWindowOpen then
                lastDecidedInstruction = "feed"
            end
        end },

        -- Eighty-fifth pass: confirmed-real close signal — closes the
        -- redirect window the moment the menu closes, so the substitution
        -- can never linger past the actual "4" interaction.
        { tag = "CloseMenu", candidates = {"CloseMenu", "Close Menu"}, onFire = closeRadialMenuActionWindow },
    }
    local loggedHookFailureOnce = {}
    local function make_hook_handler(onFire)
        return function(Context, A, B, C)
            if world_is_closing() then return end
            local self_ = hook_get(Context)
            if onFire then

                -- Hundred-and-twenty-third pass: now passes self_ through
                -- (the live widget instance) — openRadialMenuActionWindow
                -- is the only current onFire that uses it; every other
                -- onFire in radialHookTargets/workerMenuTargets ignores
                -- extra arguments harmlessly (closeRadialMenuActionWindow
                -- and the two lastDecidedInstruction closures all take
                -- zero declared params already).
                safe_call(function() onFire(self_) end)
            end
        end
    end

    -- Ninety-eighth pass (2026-09-03) FIX: the ninety-seventh pass's live
    -- test confirmed the extended budget WORKED (RADIAL-REDIRECT fired,
    -- Pet/Feed lit up) but Dragón also reported it "felt terribly
    -- laggy" — worse than before. Root cause, found in the log: each
    -- FAILED RegisterHook error's `tostring(err)` embeds a full ~10-line
    -- stack traceback (always the same one — the call site never
    -- changes, so it adds no diagnostic value), and a handful of
    -- candidate names (ChangeMode/DecideMenuAction on the radial class;
    -- several on the worker classes; several on the indicator class)
    -- are genuinely dead — real evidence, not a guess: their sibling
    -- targets on the SAME class resolved within a couple of rounds,
    -- proving the class loads fine, while these specific names kept
    -- failing through round 19 (the whole log was cut off there —
    -- would have kept failing, with a full traceback each, every 5s
    -- out to the new round-60/5-minute cap). Two fixes, both cheap:
    --   1. Log only the first line of the error (the actual message),
    --      not the embedded traceback — cuts every failure line from
    --      ~10 lines to 1 without losing any real information.
    --   2. Track the round a class FIRST proves loaded (any one of its
    --      targets hooks successfully). Once proven, give the remaining
    --      unresolved targets a few more rounds (they might just be
    --      slightly slower) but then stop — a name still unresolved
    --      long after a sibling on the same class succeeded is a wrong
    --      name, not a loading-timing issue, and no amount of extra
    --      waiting fixes that.
    -- Same discipline proven in the seventy-fourth/seventy-fifth passes,
    -- extended in the ninety-seventh pass, tightened here.
    local EARLY_EXIT_ROUNDS_AFTER_PROOF = 3
    local function make_hook_round_runner(className, targets, logTag)
        local round = 0
        local provenLoadedAtRound = nil
        local runner
        runner = function()
            round = round + 1
            local allDone = true
            local anyHookedThisGroup = false
            for _, target in ipairs(targets) do
                if not target.hooked then
                    for _, funcName in ipairs(target.candidates) do
                        local path = className .. ":" .. funcName
                        local ok, err = pcall(function()
                            RegisterHook(path, make_hook_handler(target.onFire))
                        end)
                        local errFirstLine
                        if not ok then
                            errFirstLine = tostring(err):match("^[^\n]*") or tostring(err)
                        end

                        -- Two-hundred-and-fourteenth pass: log each SUCCESS,
                        -- but each failing name only ONCE instead of once per
                        -- retry round. Dragón's last run had 430 of these
                        -- lines at startup (282 WORKER-WATCH + 170
                        -- RADIAL-WATCH) — all of them the same handful of
                        -- dead function names failing over and over, each one
                        -- forced to disk by Logger's flush-per-line design.
                        -- The names that never resolve are already known and
                        -- documented; repeating them dozens of times adds
                        -- nothing and costs real startup time.
                        if ok or not loggedHookFailureOnce[path] then
                            if not ok then loggedHookFailureOnce[path] = true end
                            Logger.log(string.format(
                                "[PalBonds/Interaction] [%s] round %d: RegisterHook(%s) = %s",
                                logTag, round, path, ok and "OK" or ("FAILED (logged once for this name): " .. errFirstLine)
                            ))
                        end
                        if ok then
                            target.hooked = true
                            break
                        end
                    end
                    if not target.hooked then
                        allDone = false
                    else
                        anyHookedThisGroup = true
                    end
                else
                    anyHookedThisGroup = true
                end
            end
            if anyHookedThisGroup and provenLoadedAtRound == nil then
                provenLoadedAtRound = round
            end
            if allDone then
                -- Visible tag: this is the line that says wild-Pal interaction
                -- is actually armed this session.
                Logger.log("[PalBonds/Interaction] [HOOKS] " .. logTag ..
                    ": all candidate hooks registered at round " .. round ..
                    " — petting and feeding wild Pals is armed")
                return
            end
            if provenLoadedAtRound and (round - provenLoadedAtRound) >= EARLY_EXIT_ROUNDS_AFTER_PROOF then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] stopping early — class proven loaded at round " .. provenLoadedAtRound .. " (a sibling hook succeeded), remaining unresolved names are very likely just wrong, not a timing issue (see FAILED lines above for exact names tried)")
                return
            end
            -- =======================================================
            -- NO GIVING UP WHILE THE CLASS HAS NEVER LOADED
            -- (three-hundred-and-first pass, 2026-09-11)
            -- =======================================================
            -- This used to stop permanently at MAX_RADIAL_HOOK_ROUNDS — 60
            -- rounds at 5s, a five-minute window that starts at MOD LOAD.
            --
            -- Mod load happens on the title screen, and these are BLUEPRINT
            -- hooks: WBP_PlayerRadialMenu_C cannot be hooked until the class is
            -- actually loaded, which does not happen until the player is in a
            -- world. On 2026-09-11 Dragón had a slow load — the world did not
            -- exist until 9.5 minutes in — so this gave up four and a half
            -- minutes before there was anything to hook, and pressing "4" never
            -- redirected to a wild Pal for the entire session. He reported it as
            -- "i could no longer interact with the pals, no matter how close i
            -- got", and there was nothing in the log, because every line here is
            -- tagged [RADIAL-WATCH]/[WORKER-WATCH] and Logger suppresses both.
            --
            -- This is the SAME bug already fixed for the nameplate bind hook in
            -- the two-hundred-and-ninety-seventh pass. That fix was applied to
            -- one instance without checking for siblings, and this was the
            -- sibling. The rule worth keeping: a retry budget anchored at mod
            -- load is measuring the wrong thing, because mod load is not when
            -- the game's Blueprint classes exist.
            --
            -- The give-up is kept for the case it was actually written for: the
            -- class HAS proved loaded (a sibling hooked) and some names still do
            -- not resolve, which means those names are wrong rather than early.
            -- That is handled by the early-exit above. While nothing has ever
            -- hooked, the only honest reading is "not yet", so it keeps trying
            -- at a slower cadence, forever, and stops the instant it succeeds.
            local waitingForClass = (provenLoadedAtRound == nil)
            if round >= MAX_RADIAL_HOOK_ROUNDS and not waitingForClass then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] giving up after " .. round .. " rounds — some functions never resolved (see FAILED lines above for exact names tried)")
                return
            end
            local nextDelay = RADIAL_HOOK_RETRY_MS
            if round >= MAX_RADIAL_HOOK_ROUNDS then
                nextDelay = RADIAL_HOOK_SLOW_RETRY_MS

                -- Visible tag on purpose: [RADIAL-WATCH] is suppressed, and the
                -- silence is what made this cost a whole test run.
                if round == MAX_RADIAL_HOOK_ROUNDS or (round % 40 == 0) then
                    Logger.log(string.format(
                        "[PalBonds/Interaction] [HOOKS] %s: the radial-menu class is still not loaded after %d rounds — still retrying (petting and feeding wild Pals cannot work until it is)",
                        logTag, round))
                end
            end
            local rescheduleOk = pcall(function()
                ExecuteInGameThreadWithDelay(nextDelay, function()
                    safe_call(runner)
                end)
            end)
            if not rescheduleOk then
                Logger.log("[PalBonds/Interaction] [" .. logTag .. "] could not schedule a retry round (ExecuteInGameThreadWithDelay failed) — stopping after round " .. round)
            end
        end
        return runner
    end
    make_hook_round_runner(RADIAL_MENU_CLASS, radialHookTargets, "RADIAL-WATCH")()

    -- ---------------------------------------------------------------
    -- Eighty-third pass (2026-09-03): research step toward Dragón's
    -- preferred direction — make the REAL vanilla radial menu act on the
    -- wild Pal you're aiming at, instead of building a custom menu from
    -- scratch (which would need real icon art/animations/sound this
    -- project has no way to produce well) or forcing the menu open on an
    -- unsupported target (the same risky category that caused the
    -- eighty-second pass's incident).
    --
    -- The idea: the "press 4 with no aim target" wheel must internally
    -- ask SOME function "who is my target Otomo" before it opens. Found a
    -- strong, real candidate in the SDK dump: `TryGetSpawnedOtomo()` on
    -- `UPalOtomoHolderComponentBase` — a plain, no-argument, NATIVE
    -- getter (not a Blueprint-only function) returning the player's
    -- current active Otomo actor. If the menu really reads this (or
    -- something equivalent) to decide its target, and if UE4SS hooks can
    -- override a native function's RETURN value here (confirmed possible
    -- in principle — `BPML_GenericFunctions`'s bundled
    -- `ConstructPersistentObject` custom event uses `OutParam:set(...)`
    -- to write a value back through a hook — but not yet confirmed for
    -- overriding an ordinary function's return specifically), we could
    -- redirect the ENTIRE existing, fully-polished Pet/Feed pipeline onto
    -- a wild Pal by substituting just this one value, with ZERO new UI
    -- work and no need to touch Trust/Capture at all.
    --
    -- Eighty-fourth pass (2026-09-03): the eighty-third pass's no-op
    -- `ReturnValue:set()` test already proved the override mechanism works
    -- (474/474 calls succeeded in one ~2min session) — no need to keep
    -- re-testing that every single call. That same session showed
    -- TryGetSpawnedOtomo firing ~4x/second even with no menu open at all
    -- (clearly read by other systems too — indicator UI, AI, who knows),
    -- which is the same "per-tick spam" shape as the eightieth pass's
    -- UpdateInteractTargetName lag bug. So this pass dedupes: only log
    -- when the described return value actually CHANGES from the last
    -- call. That session also surfaced a real anomaly worth watching for:
    -- for a stretch, the return's GetFullName() call started throwing
    -- (hook_describe falls back to the bare `UObject: 0x...` tostring),
    -- with a DIFFERENT address every ~3 seconds — consistent with UE4SS's
    -- wrapper for a null/invalid pointer, i.e. TryGetSpawnedOtomo can and
    -- does return nothing while the Otomo is between states.
    --
    -- Bigger finding from that same session: WORKER-WATCH gave up after 8
    -- rounds with EVERY candidate failing to register — WBP_WorkerRadialMenu
    -- never loaded into memory at all, meaning the aim-based Worker Menu
    -- never actually opened once, on the party Pal OR the wild Pal Dragón
    -- tested against. Every one of that session's 7 "4" presses instead
    -- went through the no-aim WBP_PlayerRadialMenu_C (RADIAL-WATCH's
    -- IsAnyMenuOpened fired right on cue), which is hardcoded to act on
    -- TryGetSpawnedOtomo's Otomo — fully explaining why the wild Pal was
    -- ignored both times, with no override ever having been attempted.
    --
    -- Eighty-fifth pass (2026-09-03): Dragón's next test (aimed "4" at a
    -- wild Pal — no menu-visible effect — then summoned his Otomo and pet
    -- it for real) gave two clean, comparable `OnDecidedInstructionCare`
    -- fires: arg1=false while TryGetSpawnedOtomo was returning an
    -- unresolvable/likely-null object (Otomo not out yet), and arg1=true
    -- once TryGetSpawnedOtomo had just returned a real, resolvable Otomo
    -- (`BP_SheepBall_C`) a moment before. That strongly says this
    -- function's bool argument is an OUTPUT reporting whether a valid
    -- target was found — not an input we could redirect — and the
    -- function itself takes no Pal reference as a parameter at all. So the
    -- eighty-fourth pass's plan (hook `OnDecidedInstructionCare` directly)
    -- is a dead end: by the time it fires, the target has already been
    -- resolved elsewhere, almost certainly via TryGetSpawnedOtomo itself
    -- or an equivalent internal call.
    --
    -- That puts the redirect back on TryGetSpawnedOtomo after all — but
    -- SCOPED, not global, to avoid the exact risk that ruled it out last
    -- pass. `radialMenuActionWindowOpen` (declared near the top of this
    -- file) is only ever true for the few hundred milliseconds between the
    -- confirmed-real `Can Open Player Action Menu` and `CloseMenu` fires —
    -- i.e. only while a "4"-press's menu is actually open — with a 1.5s
    -- safety timeout in case `CloseMenu` somehow doesn't fire. Outside
    -- that window (the ~4/sec ambient calls from whatever else reads this
    -- getter), behavior is 100% untouched — this is the same
    -- non-negotiable lesson from the eighty-second pass incident: never
    -- change a shared function's behavior for more callers than intended.
    --
    -- Inside the window, substitution only happens if `find_targeted_pal`
    -- (the exact same look-based targeting F9/F10 already use safely)
    -- finds a Pal you're aiming at that ISN'T the real Otomo, AND
    -- `Capture.IsAlreadyOwned` confirms it's genuinely wild.
    --
    -- NINETY-SIXTH PASS (2026-09-03) FIX: this used to cap the actual
    -- substitution to ONE attempt per window (`radialMenuRedirectedThisWindow`).
    -- Dragón reported Pet/Feed showing up grayed-out/unclickable every time
    -- he tried this on a wild Pal. Re-reading the log showed WHY that
    -- one-shot cap is a real problem, not just noise-reduction: within the
    -- same ~1.5s window, TryGetSpawnedOtomo gets called MULTIPLE times
    -- (this getter fires ~4x/second per the eighty-fourth pass) — our
    -- redirect only ever caught the FIRST of those calls. Whatever later
    -- decides the buttons' enabled/grayed state very plausibly reads a
    -- LATER call that we deliberately left un-redirected, meaning the real
    -- Otomo (or nothing) was still what fed the button-enable check the
    -- whole time — this may have nothing to do with a deeper "is this a
    -- real party member" wall at all, just our own once-only cap missing
    -- the call that mattered. Removed the cap: substitution now applies to
    -- EVERY qualifying call for as long as the window stays open (still
    -- fully gated by `radialMenuActionWindowOpen`, still wild-Pal-only,
    -- still excludes the player) — cheap and idempotent, since it just
    -- re-runs the same aim check and returns the same wild Pal each time
    -- your aim hasn't changed. Only the "EXPERIMENTAL: substituting..."
    -- log line itself is still deduped (see lastRedirectedWildPalName
    -- below) so this doesn't turn into another repeat-log spam source.
    --
    -- THIS IS THE FIRST LIVE ATTEMPT AT AN ACTUAL SUBSTITUTION, not just a
    -- no-op test. It is still an open question whether the game's own
    -- Pet/Feed logic, once handed a non-Otomo Pal here, will actually
    -- treat it correctly — that function doesn't receive a Pal reference
    -- as a parameter, so whatever runs the actual petting animation almost
    -- certainly re-reads this SAME getter rather than being passed a
    -- value, which is the whole bet this pass is making. If it goes wrong,
    -- the blast radius is contained: no Trust/Capture code is touched by
    -- this substitution at all, and the window auto-closes within 1.5s
    -- either way.
    local okOtomoGetter = pcall(function()
        RegisterHook("/Script/Pal.PalOtomoHolderComponentBase:TryGetSpawnedOtomo", function(Context) end, function(Context, ReturnValue)
            if world_is_closing() then return end

            -- Two-hundred-and-sixth pass (2026-09-06) — IDLE PATH MADE FREE.
            -- This hook is LOAD-BEARING and must stay: the substitution
            -- below is what lets the real vanilla Pet action land on a wild
            -- Pal at all (the hundred-and-fifty-ninth pass's root-cause
            -- finding for why Pet works and Feed/Play don't). What did NOT
            -- need to stay is the ambient [OTOMO-GETTER-WATCH] logging that
            -- used to sit above this line.
            --
            -- The problem: this getter fires ~4x/second even with no menu
            -- open, and the watch ran `hook_get` + `hook_describe` — a real
            -- GetFullName() reflection round-trip, with a tostring()
            -- fallback — on EVERY one of those calls, before any throttle
            -- could decide whether to log. The Two-hundred-and-fourth pass
            -- fixed the throttle so the LINES stopped repeating, but left
            -- the per-call reflection work in place, which was always the
            -- larger cost. Dragón confirmed the lag survived that fix.
            --
            -- Now the idle path is a single boolean test and an immediate
            -- return: no hook_get, no describe, no string work, no disk
            -- write unless the radial-menu window is genuinely open. The
            -- watch line itself is dropped entirely — the question it was
            -- built for (what this getter returns, and when) was answered
            -- back in the eighty-fourth pass.
            if not radialMenuActionWindowOpen then return end
            local returned = hook_get(ReturnValue)
            do
                local ok, err = pcall(function()
                    local player = require("PlayerRef").Get()
                    if not player or not player:IsValid() then return end
                    local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
                    if not originLoc then
                        originLoc = safe_call(function() return player:K2_GetActorLocation() end)
                    end
                    if not originLoc then return end
                    local controlRot = safe_call(function() return player:GetControlRotation() end)
                    if not controlRot then return end
                    local forward = rotator_to_forward(controlRot)

                    -- Eighty-seventh pass (2026-09-03) FIX, REAL INCIDENT
                    -- FOUND: the eighty-fifth pass excluded only the
                    -- current Otomo (`returned`) from `find_targeted_pal`,
                    -- not the player. Dragón's live log showed it twice
                    -- substituting `BP_Player_Female_C` — his OWN character
                    -- — in place of the Otomo, because APalPlayerCharacter
                    -- apparently satisfies the same "PalCharacter" scan
                    -- this function uses, and `Capture.IsAlreadyOwned`
                    -- read an all-zero owner GUID off the player's own
                    -- shared character-parameter component and wrongly
                    -- called that "wild". No harm reached the player this
                    -- time — the real `AddFriendShip` both times landed on
                    -- the real Otomo's parameter, meaning whatever actually
                    -- runs the pet animation does NOT re-read this getter
                    -- (the eighty-fifth pass's open question is answered:
                    -- it doesn't) — but this was luck, not a guarantee, and
                    -- is exactly the kind of gap this project has been
                    -- burned by before (eighty-second pass). Fixed at the
                    -- source: exclude the PLAYER from candidates (the same
                    -- proven-safe exclusion do_pet/do_feed already use),
                    -- not the Otomo — and added an explicit belt-and-
                    -- suspenders re-check afterward in case any future
                    -- exclusion-by-name edge case slips through.
                    --
                    -- Hundred-and-second pass: throttled per-call cost —
                    -- reuse the last real find, IsValid()-rechecked, if
                    -- it's still fresh; otherwise pay for a real scan.
                    local wildPal = nil
                    local now = safe_call(function() return os.clock() end)
                    if cachedRedirectWildPal and lastRedirectComputeClock and now
                        and (now - lastRedirectComputeClock) < REDIRECT_RECOMPUTE_INTERVAL_S then
                        local stillValid = safe_call(function() return cachedRedirectWildPal:IsValid() end)
                        if stillValid then
                            wildPal = cachedRedirectWildPal
                        end
                    end
                    if not wildPal then
                        local scanStart = now
                        wildPal = find_targeted_pal(originLoc, forward, player)
                        local scanEnd = safe_call(function() return os.clock() end)
                        if scanStart and scanEnd then

                            -- Real evidence, not a guess: this is throttled
                            -- to at most ~4/sec (the recompute interval
                            -- above) rather than the raw hook-fire rate, so
                            -- logging every real scan stays cheap and gives
                            -- Dragón's next test concrete ms numbers to
                            -- confirm or rule out this as the hitch source.
                            -- Two-hundred-and-eighth pass: this diagnostic
                            -- did its job — Dragón's log gave the concrete
                            -- numbers (48-74ms per scan, several per menu
                            -- open) that identified find_targeted_pal as
                            -- this project's largest single frame hitch, and
                            -- the GetFullName-per-Pal waste inside it has now
                            -- been removed. Kept, but only reports scans that
                            -- are still slow enough to matter, so it can
                            -- confirm the fix without adding its own cost
                            -- back on every scan.
                            local scanMs = (scanEnd - scanStart) * 1000
                            if scanMs >= 15.0 then
                                Logger.log(string.format(
                                    "[PalBonds/Interaction] [RADIAL-REDIRECT-PERF] find_targeted_pal scan took %.2fms (only logged when >= 15ms — see two-hundred-and-eighth pass)",
                                    scanMs
                                ))
                            end
                        end
                        cachedRedirectWildPal = wildPal
                        lastRedirectComputeClock = now
                    end
                    if not wildPal or not wildPal:IsValid() then
                        redirect_idle_log("noaim", "[PalBonds/Interaction] [RADIAL-REDIRECT] menu window open but not aiming at any Pal — leaving the real Otomo in place")
                        return
                    end
                    local playerName = safe_call(function() return player:GetFullName() end)
                    local wildPalName = safe_call(function() return wildPal:GetFullName() end)
                    if playerName and wildPalName and playerName == wildPalName then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] SAFETY: find_targeted_pal returned the player itself — refusing to substitute, leaving the real Otomo in place")
                        return
                    end
                    local returnedName = safe_call(function() return returned and returned:GetFullName() end)
                    if returnedName and wildPalName and returnedName == wildPalName then
                        redirect_idle_log("isotomo", "[PalBonds/Interaction] [RADIAL-REDIRECT] aimed Pal is already the current Otomo — nothing to substitute")
                        return
                    end
                    local isWild = Capture.IsAlreadyOwned and (not Capture.IsAlreadyOwned(wildPal))
                    if not isWild then
                        redirect_idle_log("owned", "[PalBonds/Interaction] [RADIAL-REDIRECT] the aimed Pal is already owned — leaving the real Otomo in place (this system is for wild Pals only)")
                        return
                    end

                    -- NINETY-SIXTH PASS: dedupe just the announcement, not
                    -- the actual substitution below — with the once-only
                    -- cap removed, this branch can now run several times a
                    -- second for as long as you keep aiming at the same
                    -- wild Pal within the window; only log again if the
                    -- aimed Pal itself changes.
                    -- Two-hundred-and-seventh pass: capture the actor on
                    -- EVERY qualifying redirect, deliberately outside the
                    -- name-change dedup below (that dedup exists only to
                    -- throttle the log line). If this were inside it, a
                    -- second "4" press aimed at the same Pal would leave a
                    -- stale/cleared reference and the grant would be lost.
                    lastRedirectedWildPalActor = wildPal
                    lastRedirectIdleReason = nil
                    if lastRedirectedWildPalName ~= wildPalName then
                        lastRedirectedWildPalName = wildPalName
                        Logger.log(string.format(
                            "[PalBonds/Interaction] [RADIAL-REDIRECT] EXPERIMENTAL: substituting wild %s in place of the Otomo for this menu action (every qualifying call now, not just the first — see ninety-sixth pass) — watch closely",
                            hook_describe(wildPal)
                        ))

                        -- Hundred-and-ninety-third pass (2026-09-05):
                        -- diagnose_party_membership's own probe
                        -- (PawnOtmoIsPartyOtomo) was checked 17 times in one
                        -- real session — including real wild-Pal
                        -- substitutions like this one — and
                        -- FindAllOf(PalPlayerPartyPalHolder) found 0
                        -- instances every single time. Confirmed dead for
                        -- this project's actual scope (singleplayer, no
                        -- Arena — that class structurally doesn't exist
                        -- outside it). Call removed; function kept below,
                        -- commented, in case Arena support is ever revisited.
                        -- diagnose_party_membership(wildPal, get_individual_handle(wildPal))
                    end

                    -- Hundredth pass (2026-09-03) FIX: this is now the ONLY
                    -- place `radialMenuRedirectedThisWindow` is set true —
                    -- it used to be set unconditionally the moment the
                    -- window was open, before any of the checks above ran,
                    -- which meant it was ALSO true for the player's own
                    -- real Otomo (aimed-at-your-own-Pal case never reaches
                    -- here — every branch above returns early first). That
                    -- was harmless while the flag was "visibility only"
                    -- (ninety-sixth pass), but the ninety-ninth pass turned
                    -- it into the hard gate for actually firing do_pet()/
                    -- do_feed() — so it needs to mean what its name says:
                    -- true only when a wild Pal is genuinely substituted
                    -- this window, never for the player's real Otomo.
                    radialMenuRedirectedThisWindow = true
                    local setOk, setErr = pcall(function()
                        ReturnValue:set(wildPal)
                    end)
                    if not setOk then
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] substitution failed: " .. tostring(setErr))
                    end

                    -- Hundred-and-twenty-third pass (2026-09-03): the
                    -- actual next experiment, per the hundred-and-twenty-
                    -- second pass's finding — `OpenOtomoFeedInventory`
                    -- fires identically whether or not the getter above is
                    -- overridden, but `SelectedFeed` (a real item actually
                    -- getting picked) never does for a substituted wild
                    -- Pal. That means whatever gates real selection reads
                    -- something OTHER than a fresh `TryGetSpawnedOtomo()`
                    -- call — the leading candidate is this exact menu
                    -- widget's OWN cached `SpawnedOtomo` variable (real,
                    -- confirmed via the RemoteAccessEverything string dump,
                    -- sixty-fifth pass), set once early in the menu's own
                    -- open sequence rather than re-read from the getter
                    -- each time. `lastOpenMenuWidget` (captured off
                    -- `CanOpenPlayerActionMenu`'s own Context, hundred-and-
                    -- twenty-third pass) is this project's live reference
                    -- to that exact widget instance.
                    --
                    -- This is a NEW category of write for this project —
                    -- not overriding a function's return value through the
                    -- hook mechanism (already done above, and via
                    -- IndividualHandle/OnClose for the Worker Menu), but
                    -- writing a plain Blueprint variable directly on a live
                    -- UI widget. Risk is still low relative to everything
                    -- this project has been cautious about before: it's a
                    -- transient UI widget's own display state, not save
                    -- data, not a native gameplay function call, and it
                    -- only ever runs in the same narrow, already-gated
                    -- window as the getter override (genuinely wild Pal
                    -- confirmed, real Otomo excluded, once per newly-aimed
                    -- Pal). Wrapped in its own pcall, logged independently
                    -- of the getter-override result so a live test shows
                    -- clearly whether the field even exists under this
                    -- name/type on this build.
                    if lastOpenMenuWidget then
                        local widgetValid = safe_call(function() return lastOpenMenuWidget:IsValid() end)
                        if widgetValid then
                            local fieldSetOk, fieldSetErr = pcall(function()
                                lastOpenMenuWidget.SpawnedOtomo = wildPal
                            end)

                            -- Two-hundred-and-eighth pass: this fired 8-10
                            -- times per single "4" press in Dragón's log,
                            -- each line rebuilding the wild Pal's full path
                            -- via hook_describe (a reflection call) and
                            -- forcing a disk flush — for a write that either
                            -- always works or always fails, on the same Pal,
                            -- within one menu window. Now logged once per
                            -- window, and always on failure.
                            if not fieldSetOk or not loggedFieldWriteThisWindow then
                                loggedFieldWriteThisWindow = true
                                Logger.log(string.format(
                                    "[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] widget.SpawnedOtomo = wild %s -> %s (logged once per menu window)",
                                    hook_describe(wildPal),
                                    fieldSetOk and "ok" or ("FAILED: " .. tostring(fieldSetErr))
                                ))
                            end
                        else
                            Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] lastOpenMenuWidget is no longer valid — skipping field write")
                        end
                    else
                        Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT-FIELD] no lastOpenMenuWidget captured yet this window — skipping field write")
                    end
                end)
                if not ok then
                    Logger.log("[PalBonds/Interaction] [RADIAL-REDIRECT] error while attempting redirect: " .. tostring(err))
                end
            end
        end)
    end)
    if not okOtomoGetter then
        Logger.log("[PalBonds/Interaction] [OTOMO-GETTER-WATCH] could not install TryGetSpawnedOtomo watch hook (name or pre+post signature may need adjusting)")
    end

    -- ---------------------------------------------------------------
    -- Eighty-eighth pass (2026-09-03) — THE ACTUAL FIX ATTEMPT for "the
    -- real vanilla Worker Radial Menu (Pet/Feed/etc, the '4' wheel) does
    -- nothing when aimed at a WILD Pal."
    --
    -- Root cause, confirmed by comparing two real live JSON dumps of
    -- PalHUDDispatchParameter_WorkerRadialMenu (one from pressing 4 on the
    -- real owned Kitsunebi partner, one from pressing 4 on a wild Foxparks,
    -- both captured via Live View's "Dump as JSON"):
    --
    --   owned: IndividualHandle = PalIndividualCharacterHandle_2147480691
    --          OnClose          = (BP_Kitsunebi_C_2147425992.OnSelectedOrderWorkerRadialMenu)
    --   wild:  IndividualHandle = PalIndividualCharacterHandle_2147480691   <- SAME OBJECT
    --          OnClose          = ()                                       <- EMPTY
    --
    -- Two things are wrong for the wild case, not just one:
    --   1. OnClose (a single/dynamic delegate, DECLARE_DYNAMIC_DELEGATE
    --      style — hence the "(Object.Function)" single-target format, not
    --      a multicast list) is never bound to anything, so selecting a
    --      menu option has no completion callback to run at all.
    --   2. IndividualHandle is IDENTICAL in both dumps — the exact same
    --      handle object, not just the same handle by coincidence. That
    --      means even if OnClose were bound, the handler would still act
    --      on whatever Pal that ONE shared/stale handle actually points
    --      to (almost certainly the real Otomo, or some other cached
    --      handle) — never the wild Pal actually being aimed at.
    --
    -- The fix: intercept the dispatch parameter right before it's used, and
    -- rewrite BOTH fields to point at the aimed wild Pal specifically.
    --
    -- Hook point: APalHUDInGame:PushWidgetStackableUI(WidgetClass,
    -- Parameter) — a real, confirmed-in-SDK native function (Pal.hpp /
    -- shared Lua type stubs both show it taking exactly
    -- (TSubclassOf<UPalUserWidgetStackableUI>, UPalHUDDispatchParameterBase*)
    -- and returning an FGuid). This is the moment the ALREADY-CONSTRUCTED
    -- Parameter object is handed off to actually open the widget — late
    -- enough that every field the menu will read is already set by
    -- whatever built it, early enough that nothing has READ those fields
    -- yet. UPalHUDService:Push has the identical signature and is very
    -- likely just a thin wrapper around the same call, so it's hooked too
    -- (whichever one the real code path actually uses will fire; hooking
    -- both is harmless since each bails out immediately for every Parameter
    -- that isn't a WorkerRadialMenu one — every other UI in the game, chest,
    -- inventory, dialogs, etc., all go through this same function and must
    -- be left completely untouched).
    --
    -- Unlike the eighty-fifth pass's TryGetSpawnedOtomo redirect, this does
    -- NOT need the radialMenuActionWindowOpen scoping hack — that was only
    -- needed because TryGetSpawnedOtomo fires ~4x/second ambiently for
    -- unrelated systems. PushWidgetStackableUI only fires when a stackable
    -- UI widget is actually being pushed, i.e. exactly when a menu is
    -- opening. Much more surgical on its own.
    --
    -- Safety gates, same discipline as every real-effect hook in this file:
    --   - Early-out unless the Parameter's own class name contains
    --     "WorkerRadialMenu" (checked via GetFullName(), which always
    --     starts with the class name) — every other UI push is a no-op.
    --   - Uses find_targeted_pal (the exact same proven look-based
    --     targeting F9/F10 and the RADIAL-REDIRECT hack already use) to
    --     find what's actually being aimed at, excluding the player.
    --   - Capture.IsAlreadyOwned gates to WILD Pals only — if the aimed Pal
    --     (or nothing) resolves as already-owned/unclear, this leaves the
    --     Parameter's fields completely untouched, so the existing, already
    --     -working owned-Pal case (real Otomo, OnClose already correctly
    --     bound by the game itself) is never interfered with.
    --   - Every native call/write is wrapped in pcall; a failure here logs
    --     and gives up on that one menu-open, it never propagates.
    --
    -- STILL UNCONFIRMED, first live attempt: the exact UE4SS Lua API for
    -- binding a single/dynamic delegate property. Best-evidenced guess,
    -- consistent with how UE4SS exposes FScriptDelegate-style properties:
    --   Parameter.OnClose:Bind(wildPal, "OnSelectedOrderWorkerRadialMenu")
    -- `OnSelectedOrderWorkerRadialMenu` is confirmed real and universal —
    -- declared on APalMonsterCharacter (Pal.hpp), the base class for EVERY
    -- Pal actor, wild or owned, so the exact function this call needs
    -- already exists on the wild Pal itself. If `:Bind(...)` isn't the
    -- right method name/signature, the pcall around it will catch the
    -- error and log the exact Lua error message, which should say either
    -- "attempt to call a nil value" (wrong method name — OnClose isn't a
    -- table with a Bind key) or a specific argument-count/type complaint
    -- (right method, wrong call shape) — real evidence to iterate from,
    -- same trial-and-error discipline as every other native call in this
    -- project.
    -- Eighty-ninth pass (2026-09-03) DIAGNOSTIC addition: three real test
    -- sessions in a row (spamming "4" at a clean-ground wild Lamball,
    -- close range, nothing else nearby) all showed ZERO [WORKER-BIND-FIX]
    -- fires AND WORKER-WATCH still giving up after all 8 rounds — the
    -- WBP_WorkerRadialMenu_C Blueprint class never loads at all this
    -- session, on ANY target, wild or owned. Every single "4" press opens
    -- the no-aim Player Menu instead, confirmed directly by Dragón ("the
    -- radial menu that popped up was always the one from the active
    -- pal"). That raises a real open question this diagnostic exists to
    -- answer: does `PushWidgetStackableUI`/`PalHUDService:Push` even fire
    -- AT ALL for the Player Menu (or anything) during a "4" press, or is
    -- EVERY radial menu (Player and Worker alike) actually dispatched
    -- through some other, still-unidentified function — which would mean
    -- this whole hook point is watching the wrong door entirely,
    -- regardless of aim precision. This logs the class of literally every
    -- widget pushed through either hooked function (deduped to only log
    -- on change, same discipline as OTOMO-GETTER-WATCH, since some UI
    -- panels may push repeatedly) — cheap, and answers the question
    -- directly from the very next test.
    local lastLoggedPushedClass = nil

    -- Ninetieth pass (2026-09-03): extracted the actual field-rewrite logic
    -- out of try_fix_worker_menu_parameter so it can be reused from a
    -- SECOND, real interception point found this pass (see below) — the
    -- eighty-eighth/eighty-ninth passes' PushWidgetStackableUI/
    -- PalHUDService:Push hooks are proven (via the diagnostic) to never
    -- carry WorkerRadialMenu traffic at all, even though the Worker Menu
    -- genuinely did open for the first time this session (full
    -- Construct/OnSetup/OnAnyUIPushed/OnSelectedEvent/Destruct sequence,
    -- WORKER-WATCH confirmed) — meaning this menu is NOT dispatched through
    -- either hooked function. Kept as a no-cost diagnostic fallback.
    local function apply_wild_fix_to_worker_parameter(parameter, hookLabel)
        local paramDesc = hook_describe(parameter)
        Logger.log(string.format(
            "[PalBonds/Interaction] [WORKER-BIND-FIX] %s saw a WorkerRadialMenu Parameter: %s",
            hookLabel, paramDesc
        ))
        local ok, err = pcall(function()
            local player = require("PlayerRef").Get()
            if not player or not player:IsValid() then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] no local player — skipping")
                return
            end
            local originLoc = safe_call(function() return player.FollowCamera:K2_GetComponentLocation() end)
            if not originLoc then
                originLoc = safe_call(function() return player:K2_GetActorLocation() end)
            end
            if not originLoc then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not read player/camera location — skipping")
                return
            end
            local controlRot = safe_call(function() return player:GetControlRotation() end)
            if not controlRot then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not read control rotation — skipping")
                return
            end
            local forward = rotator_to_forward(controlRot)
            local aimedPal = find_targeted_pal(originLoc, forward, player)
            if not aimedPal or not aimedPal:IsValid() then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] menu opening but not aiming at any Pal — leaving Parameter untouched")
                return
            end
            local playerName = safe_call(function() return player:GetFullName() end)
            local aimedName = safe_call(function() return aimedPal:GetFullName() end)
            if playerName and aimedName and playerName == aimedName then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] SAFETY: find_targeted_pal returned the player itself — refusing to touch Parameter")
                return
            end
            local isWild = Capture.IsAlreadyOwned and (not Capture.IsAlreadyOwned(aimedPal))
            if not isWild then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] aimed Pal (" .. tostring(aimedName) .. ") is already owned — leaving Parameter untouched, this fix is for wild Pals only")
                return
            end
            local wildHandle = get_individual_handle(aimedPal)
            if not wildHandle or not wildHandle:IsValid() then
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] wild " .. tostring(aimedName) .. " has no readable IndividualHandle — cannot safely redirect, leaving Parameter untouched")
                return
            end
            Logger.log(string.format(
                "[PalBonds/Interaction] [WORKER-BIND-FIX] EXPERIMENTAL: redirecting WorkerRadialMenu Parameter onto wild %s — setting IndividualHandle and binding OnClose",
                tostring(aimedName)
            ))
            local setHandleOk, setHandleErr = pcall(function()
                parameter.IndividualHandle = wildHandle
            end)
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] IndividualHandle write: " .. (setHandleOk and "ok" or ("FAILED: " .. tostring(setHandleErr))))
            local bindOk, bindErr = pcall(function()
                parameter.OnClose:Bind(aimedPal, "OnSelectedOrderWorkerRadialMenu")
            end)
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] OnClose:Bind() call: " .. (bindOk and "ok" or ("FAILED: " .. tostring(bindErr))))
        end)
        if not ok then
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] error while attempting redirect: " .. tostring(err))
        end
    end
    local function try_fix_worker_menu_parameter(hookLabel, Context, WidgetClassParam, ParameterParam)
        local parameter = hook_get(ParameterParam)
        local paramDesc = hook_describe(parameter)
        local diagKey = hookLabel .. ":" .. paramDesc
        if diagKey ~= lastLoggedPushedClass then
            lastLoggedPushedClass = diagKey
            Logger.log(string.format(
                "[PalBonds/Interaction] [WORKER-BIND-FIX-DIAG] %s pushed a widget with Parameter: %s",
                hookLabel, paramDesc
            ))
        end
        if not parameter then return end
        if not paramDesc:find("WorkerRadialMenu", 1, true) then
            return 
        end
        apply_wild_fix_to_worker_parameter(parameter, hookLabel)
    end

    -- Ninetieth pass (2026-09-03): THE REAL INTERCEPTION POINT, found from
    -- this session's own log. `WBP_WorkerRadialMenu_Overlay_C:OnSetup`
    -- fired for real (WORKER-WATCH, confirmed) but with EVERY argument
    -- nil — meaning it takes no meaningful arguments, and (per this
    -- Blueprint family's pattern of exposing a plain `Parameter` variable,
    -- matching PushWidgetStackableUI's own parameter name) the dispatch
    -- Parameter is very likely stored as a plain Blueprint variable on the
    -- widget itself: `self.Parameter`, readable directly off the `self`
    -- object OnSetup already hands us via Context — not passed as a
    -- function argument at all, which is exactly why neither the eighty-
    -- eighth pass's hook nor this pass's diagnostic ever saw it. `OnSetup`
    -- fires as part of the SAME confirmed-real sequence
    -- (Construct→OnSetup→OnAnyUIPushed→...→OnClosed→Destruct) that WORKER-
    -- WATCH already proved happens on every real Worker Menu open, so if
    -- `self.Parameter` resolves here, this is a hook point PROVEN to fire,
    -- unlike the abandoned Push-based one. Needs its own retry loop, same
    -- as every other Worker Menu Blueprint hook in this file — the class
    -- isn't loaded at Init() time.
    local workerOnSetupRound = 0
    -- The Worker radial menu overlay class. Its OnSetup is where a wild Pal
    -- gets substituted into the menu parameter, which is what makes Pet and
    -- Feed work on a wild Pal at all. Keep this declaration next to its use:
    -- a cleanup pass once deleted it and left the use behind, and because an
    -- undeclared Lua local reads as a nil global, Interaction.Init() threw on
    -- the concatenation below and Trust/Combat/Capture never initialised.
    local WORKER_MENU_OVERLAY_CLASS = "/Game/Pal/Blueprint/UI/WorkerRadialMenu/WBP_WorkerRadialMenu_Overlay.WBP_WorkerRadialMenu_Overlay_C"
    local function install_worker_onsetup_fix_hook()
        local path = WORKER_MENU_OVERLAY_CLASS .. ":OnSetup"
        local ok = pcall(function()
            RegisterHook(path, function(Context)
                if world_is_closing() then return end
                local self_ = hook_get(Context)
                if not self_ then return end
                local parameter = safe_call(function() return self_.Parameter end)
                local paramDesc = hook_describe(parameter)
                Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] OnSetup self.Parameter = " .. paramDesc)
                if not parameter then return end
                if not paramDesc:find("WorkerRadialMenu", 1, true) then return end
                apply_wild_fix_to_worker_parameter(parameter, "WBP_WorkerRadialMenu_Overlay_C:OnSetup")
            end)
        end)
        return ok
    end
    local function worker_onsetup_retry_runner()
        workerOnSetupRound = workerOnSetupRound + 1
        if install_worker_onsetup_fix_hook() then
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] OnSetup fix hook installed on round " .. workerOnSetupRound)
            return
        end
        if workerOnSetupRound >= MAX_RADIAL_HOOK_ROUNDS then
            Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] giving up installing the OnSetup fix hook after " .. workerOnSetupRound .. " rounds")
            return
        end
        pcall(function()
            ExecuteInGameThreadWithDelay(RADIAL_HOOK_RETRY_MS, function()
                safe_call(worker_onsetup_retry_runner)
            end)
        end)
    end
    worker_onsetup_retry_runner()
    local okPushWidget = pcall(function()
        RegisterHook("/Script/Pal.PalHUDInGame:PushWidgetStackableUI", function(Context, WidgetClassParam, ParameterParam)
            if world_is_closing() then return end
            try_fix_worker_menu_parameter("PalHUDInGame:PushWidgetStackableUI", Context, WidgetClassParam, ParameterParam)
        end)
    end)
    if not okPushWidget then
        Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not install PushWidgetStackableUI hook")
    end
    local okServicePush = pcall(function()
        RegisterHook("/Script/Pal.PalHUDService:Push", function(Context, WidgetClassParam, ParameterParam)
            if world_is_closing() then return end
            try_fix_worker_menu_parameter("PalHUDService:Push", Context, WidgetClassParam, ParameterParam)
        end)
    end)
    if not okServicePush then
        Logger.log("[PalBonds/Interaction] [WORKER-BIND-FIX] could not install PalHUDService:Push hook")
    end

-- Called once a pet OR feed successfully lands on any Pal (wild or
-- owned). REAL as of the sixteenth pass (2026-09-01): forwards to
-- Trust.lua, which reads the real FriendshipRank and handles the
-- follow-at-5-interactions / capture-at-rank-1 thresholds. Fires for ANY
-- Pal, owned or not — harmless for an owned one (it just accumulates
-- interaction-count state Trust.lua never acts on, since an owned Pal is
-- already captured).
end
function Interaction.OnWildPalPetted(palActor)
    Trust.OnInteractionSucceeded(palActor)

    -- Thirty-fourth pass (2026-09-02): first real, live use of
    -- Personality.lua's new helpers. Deliberately called here — a
    -- successful pet/feed is already a rare, gated event (never per-tick)
    -- — rather than as a new standalone hook, per the lesson from the
    -- thirty-third pass's frame-rate incident. Logs once per interaction,
    -- not per-tick, so this is safe to leave on permanently.
    local palId = Personality.GetOrInitState(palActor)
    if palId then
        local state = Personality.GetState(palId)
        Logger.log(string.format(
            "[PalBonds/Personality] resolved state for id=%s — disposition=%s (species default=%s, preset=%s)",
            palId,
            tostring(state and state.disposition),
            tostring(state and state.speciesDefault),
            tostring(state and state.presetClassName)
        ))
    else
        Logger.log("[PalBonds/Personality] could not resolve a stable ID for this Pal (handle/ID lookup failed) — see Personality.lua")
    end
end

-- ===================================================================
-- WORLD CHANGE (three-hundred-and-twenty-eighth pass, 2026-09-17)
-- ===================================================================
-- The radial-menu and aim caches all remember a Pal, a menu widget or a scan
-- result from the world that just closed, and a Lua reference keeps a UObject
-- alive past its world. Dropped here so the next world starts clean.
--
-- Deliberately KEPT: cachedWorkerMenuParameter, which is outered to the
-- GameInstance precisely so it SURVIVES a world change (pass 285 -- outering it
-- to the player character was the original 0x338 crash).
function Interaction.ResetForNewWorld()
    palScanCache = nil
    palScanCacheAge = 0
    pendingWildFeedTarget = nil
    lastAimedInteractTarget = nil
    lastRedirectedWildPalName = nil
    lastRedirectedWildPalActor = nil
    lastDecidedInstruction = nil
    cachedRedirectWildPal = nil
    lastRedirectComputeClock = nil
    lastOpenMenuWidget = nil
    paidPetActionByPal = {}
    capsuleReported = {}
    Logger.log("[PalBonds/Interaction] [WORLD-RESET] dropped the radial-menu, aim and pet-check references from the old world")
end
return Interaction
