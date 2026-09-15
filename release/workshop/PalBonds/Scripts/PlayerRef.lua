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

    Always FindAllOf, never FindFirstOf: UE4SS issue #1328 (FindFirstOf
    dereferences before its null check), the crash-on-respawn investigation in
    Trust.lua/Combat.lua.
]]

local PlayerRef = {}

local SAFETY_NET_RESEARCH_SECONDS = 60.0
local DEATH_CHECK_SECONDS = 1.0
local RESPAWN_RETRY_SECONDS = 2.0
local MISS_RETRY_SECONDS = 2.0

local cached = nil
local cachedName = nil
local cachedAt = -1e9
local lastMissAt = -1e9
local lastDeathCheckAt = -1e9
local deadBody = nil
local deadBodyAddress = nil
local lastRespawnSearchAt = -1e9
local searchCount = 0

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

local function search(now)
    searchCount = searchCount + 1
    cached, cachedName = nil, nil
    local ok, list = pcall(function() return FindAllOf("PalPlayerCharacter") end)
    if ok and type(list) == "table" then
        for _, p in ipairs(list) do
            if p ~= nil and is_valid(p) then
                cached = p
                cachedAt = now
                return p
            end
        end
    end
    lastMissAt = now
    return nil
end

-- The local player's PalPlayerCharacter, or nil if there is none right now.
function PlayerRef.Get()
    local now = os.clock()

    -- Waiting for a respawn.
    if deadBody ~= nil then
        if (now - lastRespawnSearchAt) >= RESPAWN_RETRY_SECONDS then
            lastRespawnSearchAt = now
            local found = search(now)
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
        return search(now)
    end
    if (now - lastMissAt) < MISS_RETRY_SECONDS then return nil end
    return search(now)
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
end

-- How many world searches have run this session (tests and profiling).
function PlayerRef.SearchCount()
    return searchCount
end

return PlayerRef
