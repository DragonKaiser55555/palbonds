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

    [PLAYER-SPY] lines (diagnostics only, 2026-09-15): every search, death and
    respawn is logged when Logger's DEBUG_LOGGING and SHOW_DIAGNOSTICS are both
    on, to check whether a stale or missing player explains a bug. They are
    rare events, so they cost nothing measurable, and nothing at all in a
    release build. Remove them once the question they were added for is closed.

    Always FindAllOf, never FindFirstOf: UE4SS issue #1328 (FindFirstOf
    dereferences before its null check), the crash-on-respawn investigation in
    Trust.lua/Combat.lua.
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
local kismet = nil

local function spy_enabled()
    local ok, L = pcall(require, "Logger")
    return ok and L and L.DiagnosticsEnabled and L.DiagnosticsEnabled() and L or nil
end

local function spy(buildMessage)
    local L = spy_enabled()
    if not L then return end
    local ok, msg = pcall(buildMessage)
    L.log("[PalBonds/PlayerRef] [PLAYER-SPY] " .. (ok and tostring(msg) or ("(message failed: " .. tostring(msg) .. ")")))
end

local function describe(obj)
    if obj == nil then return "nil" end
    local okName, name = pcall(function() return obj:GetFullName() end)
    local okAddr, addr = pcall(function() return obj:GetAddress() end)
    return string.format("%s @%s", okName and tostring(name) or "?", okAddr and tostring(addr) or "?")
end

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

local function search(now, reason)
    searchCount = searchCount + 1
    cached, cachedName = nil, nil
    local ok, list = pcall(function() return FindAllOf("PalPlayerCharacter") end)
    local count = (ok and type(list) == "table") and #list or 0
    if ok and type(list) == "table" then
        for _, p in ipairs(list) do
            if p ~= nil and is_valid(p) then
                cached = p
                cachedAt = now
                spy(function()
                    return string.format("search #%d (%s): %d PalPlayerCharacter(s) in the world, kept %s", searchCount, reason, count, describe(p))
                end)
                return p
            end
        end
    end
    lastMissAt = now
    spy(function()
        return string.format("search #%d (%s): %d PalPlayerCharacter(s), none valid — no player", searchCount, reason, count)
    end)
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

    -- Waiting for a respawn.
    if deadBody ~= nil then
        if (now - lastRespawnSearchAt) >= RESPAWN_RETRY_SECONDS then
            lastRespawnSearchAt = now
            local found = search(now, "waiting for respawn")
            if found ~= nil then
                local foundAddress = address_of(found)
                local different = foundAddress ~= nil and deadBodyAddress ~= nil and foundAddress ~= deadBodyAddress
                if different or not is_dead(found) then
                    spy(function()
                        return string.format("respawn found: %s (different character=%s)", describe(found), tostring(different))
                    end)
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
        if is_valid(cached) and (now - lastLivenessAt) >= LIVENESS_CHECK_SECONDS then
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
                    spy(function() return "player death detected on " .. describe(cached) .. " — keeping the body until the respawn is found" end)
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
    spy(function() return "invalidated (world change) — was " .. describe(cached) end)
    cached, cachedName = nil, nil
    cachedAt = -1e9
    lastMissAt = -1e9
    lastDeathCheckAt = -1e9
    deadBody, deadBodyAddress = nil, nil
    lastRespawnSearchAt = -1e9
    lastLivenessAt = -1e9
end

-- How many world searches have run this session (tests and profiling).
function PlayerRef.SearchCount()
    return searchCount
end

return PlayerRef
