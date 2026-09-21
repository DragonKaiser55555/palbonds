--[[
    PalBonds — the one place the mod looks up the local player's character.

    WHY THIS EXISTS (profiled 2026-09-15). Finding the player means walking the
    entire loaded object array (FindAllOf "PalPlayerCharacter"), which measured
    ~40ms on a quiet map and 55–100ms in real play — two to six dropped frames
    per lookup. The mod was doing it from twelve places in five files, some of
    them constantly: the radial-menu redirect on every hook fire while the menu
    window was open (3.2–3.8s of freezing per minute of feeding), the 1.5s Trust
    tick, the 8s personality scan, the damage hooks during fights, and Combat's
    follower loop.

    WHAT IT DOES INSTEAD. The player's character almost never changes, so the
    reference is kept and checked with IsValid() on every use. The world is only
    searched again when something says the character may have changed:

      * The kept character became invalid (destroyed).
      * The world changed: Combat.ResetForNewWorld calls PlayerRef.Invalidate().
      * The player DIED (Dragón's suggestion, 2026-09-15, instead of re-searching
        on a short timer). The kept character is checked at most once per
        DEATH_CHECK_SECONDS with the same IsDead/IsDying check Trust.lua uses on
        followers. A dead character is not replaced straight away: the body is
        still returned, exactly as before this file existed, so nothing that
        runs during the death screen suddenly sees "no player". Meanwhile the
        world is searched every RESPAWN_RETRY_SECONDS until a DIFFERENT
        character, or a living one, turns up — the respawn.
      * SAFETY_NET_RESEARCH_SECONDS have passed since the last search. Kept as a
        rare last resort for any way the reference could go stale that none of
        the above catches.

    When a search finds nobody (title screen, loading screen), it waits
    MISS_RETRY_SECONDS before searching again instead of searching on every call.

    THE WORLD-CHANGE CRASH CAME BACK WITH THIS FILE (2026-09-16). Dragón:
    bond a Pal, quit to the menu, load a world -> EXCEPTION_ACCESS_VIOLATION
    reading 0x338, in 1.1.2 and the dev build, never in 1.1.1 (tested both ways,
    pet-only and feed-only). The 1.1.1 log shows why: Combat's fast loop
    re-searched for the player every ~4 s, the search came back EMPTY when he
    quit, and "[WORLD-RESET] the player left the world" dropped every reference.
    In 1.1.2 this file kept handing back the old character, which still passed
    UE4SS's IsValid() while its world was being torn down, so the reset never
    ran and the old world's followers were touched after the new one loaded.

    Two checks, both cheap, stop the kept reference from outliving its world:
      * Once per LIVENESS_CHECK_SECONDS, UKismetSystemLibrary::IsValid on the
        kept character — the engine's own check, which also rejects objects
        marked for destruction. One function call, no search.
      * While a Pal is following (the only time a stale world matters), a real
        search every FOLLOWER_RESEARCH_SECONDS — exactly 1.1.1's cadence, the
        one proven to catch the quit. With nothing following it never runs.
    Both log a [PLAYER-LIFE] line when they notice the player gone or changed,
    so a test run shows which one fired.

    Always FindAllOf, never FindFirstOf: UE4SS issue #1328 (FindFirstOf
    dereferences before its null check), the crash-on-respawn investigation in
    Trust.lua/Combat.lua.

    WHICH PLAYER IS OURS (2026-09-20, the first step towards co-op). Until now
    every lookup here took the FIRST valid PalPlayerCharacter in the object
    list. In singleplayer there is only ever one, so that was always right. In
    a co-op world every player's character is loaded on every machine, and
    "first in the list" is whoever the engine happens to list first -- which is
    how a Workshop player watched the Digtoise HE befriended join his friend's
    party instead (LuWicki97, 2026-09-15). See pick_local below.
]]

local PlayerRef = {}

local SAFETY_NET_RESEARCH_SECONDS = 60.0
local DEATH_CHECK_SECONDS = 1.0
local RESPAWN_RETRY_SECONDS = 2.0
local MISS_RETRY_SECONDS = 2.0
local LIVENESS_CHECK_SECONDS = 1.0
local FOLLOWER_RESEARCH_SECONDS = 4.0

local cached = nil
local cachedName = nil
local cachedAt = -1e9
local lastMissAt = -1e9
local lastDeathCheckAt = -1e9
local deadBody = nil
local deadBodyAddress = nil
local lastRespawnSearchAt = -1e9
local searchCount = 0
local lastLivenessAt = -1e9

-- Set by PlayerRef.ExpectWorldChange while the player has asked to leave the
-- world; nil the rest of the time. See the branch in Get() that reads it.
local fastLivenessUntil = nil

-- ===================================================================
-- WORLD CLOSING (2026-09-17, after the second reproducible crash)
-- ===================================================================
-- Dragón's log settled a question the polling fix could not: when he confirms
-- "return to title", the mod gets NO MORE PASSES. The quit hook fired, and the
-- log ends there -- no world-reset line, because the game never serviced
-- another ExecuteInGameThreadWithDelay callback before the world was gone.
-- Noticing a world change afterwards is therefore impossible by construction;
-- everything has to be released at the moment the player confirms, while the
-- world is still alive.
--
-- Releasing early leaves a second hole, though: the game keeps running for a
-- moment, and the nameplate hook, the personality resolver and the trust
-- recorder would happily refill those tables before the world actually dies.
-- This flag closes it at the single point they all depend on -- Get() returns
-- nil while the world is closing, which every caller already handles, because
-- that is what it returns at the title screen.
--
-- It is cleared by ProbeForNewPlayer (see Combat's watch): a DIFFERENT player
-- means the new world is up; the SAME one still there after a while means the
-- player cancelled the quit.
local worldClosing = false
local closingPlayerAddress = nil
local closingSince = nil
local kismet = nil

local function is_valid(obj)
    local ok, valid = pcall(function() return obj:IsValid() end)
    return ok and valid == true
end

local function address_of(obj)
    local ok, addr = pcall(function() return obj:GetAddress() end)
    if ok then return addr end
    return nil
end

local function is_dead(player)
    local ok, dead = pcall(function()
        local comp = player.CharacterParameterComponent
        if comp == nil or not comp:IsValid() then return false end
        if comp:IsDead() == true then return true end
        return comp:IsDying() == true
    end)
    return ok and dead == true
end

local function log_line(msg)
    local ok, L = pcall(require, "Logger")
    if ok and L and L.log then L.log("[PalBonds/PlayerRef] [PLAYER-LIFE] " .. msg) end
end

-- APawn::IsLocallyControlled(): true only for the character THIS machine
-- controls, on the host and on a guest alike. Returns nil when the call is not
-- available, which is a different answer from false and is treated as one.
local function locally_controlled(p)
    local ok, v = pcall(function() return p:IsLocallyControlled() end)
    if not ok or type(v) ~= "boolean" then return nil end
    return v
end

local unknownLogged = false
local sawLocalTrue = false
-- One line per session saying HOW our character was recognised. It is the only
-- way to tell, from a player's log, whether this build answers the question at
-- all -- which decides whether co-op can ever work.
local resolvedLogged = false
local lastNoLocalLogAt = -1e9
local NO_LOCAL_LOG_SECONDS = 30.0

-- Picks OUR player character out of everything the search returned.
--
-- Three outcomes, and each one is deliberate:
--   * somebody answers true -> that is ours, wherever it sat in the list;
--   * nobody answers true, there is exactly ONE character, and no character
--     has ever answered true this session -> that one. A singleplayer world
--     can never hold more, so if this build ever stopped answering the
--     question, singleplayer keeps working exactly as it does today. This is
--     the fail-open that matters most. Once some character HAS answered true
--     we know the question works, so a lone character saying "not yours" is
--     believed -- otherwise, in co-op, our character unloading for a moment
--     would hand the mod the other player's;
--   * nobody answers true, several characters, and the call never worked at
--     all -> the first one (the old behaviour) plus one log line, because
--     going blind would be worse than the bug we are fixing;
--   * nobody answers true, several characters, and the call DID work -> nil.
--     We are in a co-op world and our character is not possessed yet. Acting
--     for the wrong player is exactly what this function exists to prevent,
--     and the caller searches again shortly, so this heals by itself.
local function pick_local(list, now)
    local valid = {}
    if type(list) == "table" then
        for _, p in ipairs(list) do
            if p ~= nil and is_valid(p) then valid[#valid + 1] = p end
        end
    end
    if #valid == 0 then return nil end

    local answered = false
    for index, p in ipairs(valid) do
        local mine = locally_controlled(p)
        if mine == true then
            sawLocalTrue = true
            if not resolvedLogged then
                resolvedLogged = true
                log_line("our player character is the one this machine controls (IsLocallyControlled), out of " ..
                    #valid .. " in this world")
            end
            if #valid > 1 and index > 1 then
                log_line(string.format(
                    "%d player characters in this world; ours is number %d — the old 'first one found' would have been somebody else's",
                    #valid, index))
            end
            return p
        end
        if mine == false then answered = true end
    end

    if #valid == 1 and not sawLocalTrue then
        if not resolvedLogged then
            resolvedLogged = true
            log_line("only one player character in this world and it did not answer IsLocallyControlled — using it, as before")
        end
        return valid[1]
    end

    if #valid == 1 then
        if now ~= nil and (now - lastNoLocalLogAt) >= NO_LOCAL_LOG_SECONDS then
            lastNoLocalLogAt = now
            log_line("the only player character here is not ours — waiting for ours")
        end
        return nil
    end

    if not answered then
        if not unknownLogged then
            unknownLogged = true
            log_line("IsLocallyControlled is not answering in this build — falling back to the first of the " ..
                #valid .. " player characters found, which may be another player's")
        end
        return valid[1]
    end

    if now ~= nil and (now - lastNoLocalLogAt) >= NO_LOCAL_LOG_SECONDS then
        lastNoLocalLogAt = now
        log_line("none of the " .. #valid .. " player characters here is controlled by this machine yet — waiting for ours")
    end
    return nil
end

local function search(now, reason)
    searchCount = searchCount + 1
    cached, cachedName = nil, nil
    local ok, list = pcall(function() return FindAllOf("PalPlayerCharacter") end)
    if ok then
        local mine = pick_local(list, now)
        if mine ~= nil then
            cached = mine
            cachedAt = now
            return mine
        end
    end
    lastMissAt = now
    return nil
end

-- UKismetSystemLibrary::IsValid(kept character). Returns false only when the
-- engine says so; nil (unknown) if the call itself is unavailable.
local function engine_says_alive(p)
    if kismet == nil or not is_valid(kismet) then
        kismet = nil
        local okH, UEHelpers = pcall(require, "UEHelpers")
        if okH and UEHelpers and UEHelpers.GetKismetSystemLibrary then
            kismet = select(2, pcall(UEHelpers.GetKismetSystemLibrary))
        end
        if kismet == nil or not is_valid(kismet) then kismet = nil return nil end
    end
    local ok, v = pcall(function() return kismet:IsValid(p) end)
    if not ok then return nil end
    return v == true
end

local function anyone_following()
    local ok, Combat = pcall(require, "Combat")
    if not (ok and Combat and Combat.HasAnyFollower) then return false end
    local ok2, v = pcall(Combat.HasAnyFollower)
    return ok2 and v == true
end

-- Re-search, and say so when the answer is "gone" or "someone else".
local function recheck(now, why)
    local before = address_of(cached)
    local found = search(now, why)
    local after = address_of(found)
    if found == nil or (before ~= nil and after ~= nil and before ~= after) then
        local okL, L = pcall(require, "Logger")
        if okL and L and L.log then
            L.log(string.format("[PalBonds/PlayerRef] [PLAYER-LIFE] %s: %s",
                why, found == nil and "no player any more (world going away)" or "a different player character (new world)"))
        end
    end
    return found
end

-- The local player's PalPlayerCharacter, or nil if there is none right now.
function PlayerRef.Get()
    local now = os.clock()

    -- The world is on its way out: hand nobody the player, so nothing the mod
    -- does can build a fresh reference into a world that is about to die. See
    -- the worldClosing comment near the top of this file.
    if worldClosing then return nil end

    -- Waiting for a respawn.
    if deadBody ~= nil then
        if (now - lastRespawnSearchAt) >= RESPAWN_RETRY_SECONDS then
            lastRespawnSearchAt = now
            local found = search(now, "waiting for respawn")
            if found ~= nil then
                local foundAddress = address_of(found)
                local different = foundAddress ~= nil and deadBodyAddress ~= nil and foundAddress ~= deadBodyAddress
                if different or not is_dead(found) then
                    deadBody, deadBodyAddress = nil, nil
                    lastDeathCheckAt = now
                    return found
                end
            end
        end
        if is_valid(deadBody) then return deadBody end
        return cached
    end

    if cached ~= nil then

        -- 2026-09-17: while a quit has been ASKED for (the ESC menu's
        -- return-to-title, see Combat.ExpectWorldChange), the engine check runs
        -- on every call instead of once a second. That window is the only time
        -- the difference matters -- the world is about to go and everything the
        -- mod holds has to be released before the next one loads -- and it ends
        -- by itself, so the normal cadence is untouched for the whole session.
        local livenessEvery = LIVENESS_CHECK_SECONDS
        if fastLivenessUntil ~= nil then
            if now < fastLivenessUntil then livenessEvery = 0 else fastLivenessUntil = nil end
        end
        if is_valid(cached) and (now - lastLivenessAt) >= livenessEvery then
            lastLivenessAt = now
            if engine_says_alive(cached) == false then
                return recheck(now, "engine IsValid=false on the kept player")
            end
        end
        if is_valid(cached) and (now - cachedAt) >= FOLLOWER_RESEARCH_SECONDS and anyone_following() then
            return recheck(now, "follower re-check")
        end
        if (now - cachedAt) < SAFETY_NET_RESEARCH_SECONDS and is_valid(cached) then
            if (now - lastDeathCheckAt) >= DEATH_CHECK_SECONDS then
                lastDeathCheckAt = now
                if is_dead(cached) then
                    deadBody, deadBodyAddress = cached, address_of(cached)
                    lastRespawnSearchAt = now
                end
            end
            return cached
        end
        return search(now, is_valid(cached) and "60s safety net" or "kept player became invalid")
    end
    if (now - lastMissAt) < MISS_RETRY_SECONDS then return nil end
    return search(now, "no player kept")
end

-- The player's GetFullName(), resolved once per kept reference.
function PlayerRef.Name()
    local p = PlayerRef.Get()
    if p == nil then return nil end
    if cachedName == nil or p ~= cached then
        local ok, name = pcall(function() return p:GetFullName() end)
        if ok then
            if p == cached then cachedName = name end
            return name
        end
    end
    return cachedName
end

-- Forget everything; the next Get() searches immediately. Called on a world change.
function PlayerRef.Invalidate()
    cached, cachedName = nil, nil
    cachedAt = -1e9
    lastMissAt = -1e9
    lastDeathCheckAt = -1e9
    deadBody, deadBodyAddress = nil, nil
    lastRespawnSearchAt = -1e9
    lastLivenessAt = -1e9
    fastLivenessUntil = nil
end

-- The player asked to leave the world (the ESC menu's return-to-title). For the
-- next `seconds`, check with the engine on every Get() rather than once a
-- second, so the moment the world actually goes is caught immediately.
function PlayerRef.ExpectWorldChange(seconds)
    fastLivenessUntil = os.clock() + (seconds or 20.0)
end

-- The player CONFIRMED leaving. Nobody gets a player reference from here until
-- a new world is up (or the quit turns out to have been cancelled).
function PlayerRef.SetWorldClosing(on)
    if on then
        closingPlayerAddress = cached ~= nil and address_of(cached) or nil
        closingSince = os.clock()
        worldClosing = true
    else
        worldClosing = false
        closingPlayerAddress = nil
        closingSince = nil
    end
end
-- Read by every hook in the mod (the world-closing gate), so it stays a
-- boolean read plus one os.clock.
--
-- The time limit is a safety net, not a mechanism: while this is true the mod
-- is deliberately blind, and the only thing that clears it is Combat's watch
-- noticing how the quit ended. If that watch ever stopped being serviced --
-- one broken reschedule during a teardown would do it -- the mod would stay
-- blind for the rest of the session and look exactly like "the mod stopped
-- working". After CLOSING_MAX_SECONDS it gives up waiting and lets everything
-- resume; being wrong that way costs a crash risk for one frame, being wrong
-- the other way costs the whole session.
local CLOSING_MAX_SECONDS = 60.0
function PlayerRef.IsWorldClosing()
    if not worldClosing then return false end
    if closingSince ~= nil and (os.clock() - closingSince) >= CLOSING_MAX_SECONDS then
        PlayerRef.SetWorldClosing(false)
        local ok, L = pcall(require, "Logger")
        if ok and L then
            L.log(string.format(
                "[PalBonds/PlayerRef] [PLAYER-LIFE] the world has been 'closing' for %.0fs with no new world and no cancel — giving up waiting and working normally again",
                CLOSING_MAX_SECONDS))
        end
        return false
    end
    return true
end

-- Called while the world is closing, and ONLY then: a real search that ignores
-- the flag, so the mod can tell the two possible endings apart.
--   * a player at a different address -> the new world is up
--   * the same player still there after cancelSeconds -> the quit was cancelled
-- Returns "new-world", "cancelled" or nil (still closing, keep waiting).
function PlayerRef.ProbeForNewPlayer(cancelSeconds)
    if not worldClosing then return nil end
    local now = os.clock()
    local ok, list = pcall(function() return FindAllOf("PalPlayerCharacter") end)
    local found = ok and pick_local(list, now) or nil
    if found == nil then return nil end
    local foundAddress = address_of(found)
    if closingPlayerAddress == nil or foundAddress == nil or foundAddress ~= closingPlayerAddress then
        PlayerRef.SetWorldClosing(false)
        cached, cachedName = found, nil
        cachedAt = now
        lastLivenessAt = now
        return "new-world"
    end
    if closingSince ~= nil and (now - closingSince) >= (cancelSeconds or 10.0) then
        PlayerRef.SetWorldClosing(false)
        cached, cachedName = found, nil
        cachedAt = now
        lastLivenessAt = now
        return "cancelled"
    end
    return nil
end

-- Exposed for the harness: which of these characters is ours (see pick_local).
function PlayerRef.PickLocal(list)
    return pick_local(list, os.clock())
end

-- How many world searches have run this session (tests and profiling).
function PlayerRef.SearchCount()
    return searchCount
end

return PlayerRef
