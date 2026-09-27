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

local fastLivenessUntil = nil

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

local function locally_controlled(p)
    local ok, v = pcall(function() return p:IsLocallyControlled() end)
    if not ok or type(v) ~= "boolean" then return nil end
    return v
end

local unknownLogged = false
local sawLocalTrue = false

local resolvedLogged = false
local lastNoLocalLogAt = -1e9
local NO_LOCAL_LOG_SECONDS = 30.0

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

local cachedWorld = nil
local askGameLogged = nil

local function world_context()
    if is_valid(cachedWorld) then return cachedWorld end
    cachedWorld = nil
    if cached ~= nil then
        local okW, w = pcall(function() return cached:GetWorld() end)
        if okW and w ~= nil and is_valid(w) then cachedWorld = w; return w end
    end
    local okH, UEHelpers = pcall(require, "UEHelpers")
    if okH and UEHelpers and UEHelpers.GetWorld then
        local okW, w = pcall(UEHelpers.GetWorld)
        if okW and w ~= nil and is_valid(w) then cachedWorld = w; return w end
    end

    local okU, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if okU and util ~= nil then
        local okW, w = pcall(function() return util:GetWorld() end)
        if okW and w ~= nil and is_valid(w) then cachedWorld = w; return w end
    end
    return nil
end

function PlayerRef.ForgetWorld()
    cachedWorld = nil
end

local function ask_game_for_player()
    local okU, util = pcall(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if not okU or util == nil then
        if askGameLogged ~= "no-util" then
            askGameLogged = "no-util"
            log_line("UPalUtility is not reachable -- falling back to the world search")
        end
        return nil
    end
    local world = world_context()
    if world == nil then
        if askGameLogged ~= "no-world" then
            askGameLogged = "no-world"
            log_line("no world context yet -- falling back to the world search")
        end
        return nil
    end
    local okP, mine = pcall(function() return util:GetPlayerCharacter(world) end)
    if okP and mine ~= nil and is_valid(mine) then
        if askGameLogged ~= "ok" then
            askGameLogged = "ok"
            log_line("the game names our character directly (UPalUtility.GetPlayerCharacter)")
        end
        return mine
    end
    if askGameLogged ~= "no-answer" then
        askGameLogged = "no-answer"
        log_line("GetPlayerCharacter gave nothing (call ok=" .. tostring(okP) .. ") -- falling back to the world search")
    end
    cachedWorld = nil
    return nil
end

local function search(now, reason)
    searchCount = searchCount + 1
    cached, cachedName = nil, nil

    local named = ask_game_for_player()
    if named ~= nil then
        cached = named
        cachedAt = now
        if not resolvedLogged then
            resolvedLogged = true
            log_line("the game names our character directly (UPalUtility.GetPlayerCharacter)")
        end
        return named
    end
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

local actingStack = {}

function PlayerRef.WithPlayer(player, fn, ...)
    if player == nil then return fn(...) end
    actingStack[#actingStack + 1] = player
    local results = table.pack(pcall(fn, ...))
    actingStack[#actingStack] = nil
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end

function PlayerRef.Acting()
    return actingStack[#actingStack]
end

local function install_timer_carry()
    if rawget(_G, "__PalBondsTimerCarry") then return end
    local original = rawget(_G, "ExecuteInGameThreadWithDelay")
    if type(original) ~= "function" then return end
    rawset(_G, "__PalBondsTimerCarry", true)
    rawset(_G, "ExecuteInGameThreadWithDelay", function(ms, fn)
        local acting = actingStack[#actingStack]
        if acting == nil or type(fn) ~= "function" then return original(ms, fn) end
        return original(ms, function() return PlayerRef.WithPlayer(acting, fn) end)
    end)
end
install_timer_carry()

local function is_our_character(player)
    if player == nil then return false end
    local mine = ask_game_for_player()
    if mine == nil then mine = cached end
    if mine == nil then return nil end
    if rawequal(mine, player) then return true end
    local okA, a = pcall(function() return mine:GetAddress() end)
    local okB, b = pcall(function() return player:GetAddress() end)
    if okA and okB and a ~= nil and b ~= nil then return a == b end
    local okNA, na = pcall(function() return mine:GetFullName() end)
    local okNB, nb = pcall(function() return player:GetFullName() end)
    if okNA and okNB and na ~= nil and nb ~= nil then return na == nb end
    return nil
end
PlayerRef.IsOurCharacter = is_our_character

function PlayerRef.OwnerKey(player)
    if player == nil then return "local" end
    local ours = is_our_character(player)
    if ours == true then return "local" end
    if ours == nil then
        local okS, Session = pcall(require, "Session")
        if okS and Session and Session.ModeIfKnown and Session.ModeIfKnown() == "singleplayer" then
            return "local"
        end
        if locally_controlled(player) ~= false then return "local" end
    end
    local ctrlName = nil
    local ok = pcall(function()
        local c = player.Controller
        if c ~= nil and c:IsValid() then ctrlName = c:GetFullName() end
    end)
    if ok and ctrlName ~= nil then return tostring(ctrlName) end
    local okN, n = pcall(function() return player:GetFullName() end)
    return okN and tostring(n) or "remote"
end

function PlayerRef.CurrentOwnerKey()
    return PlayerRef.OwnerKey(actingStack[#actingStack])
end

local function on_dedicated_server()
    local ok, Session = pcall(require, "Session")
    if not ok or Session == nil or Session.IsDedicated == nil then return false end
    local okAsk, yes = pcall(Session.IsDedicated)
    return okAsk and yes == true
end

function PlayerRef.IsRemote(player)
    if player == nil then return false end
    local ours = is_our_character(player)
    if ours ~= nil then return not ours end

    local okS, Session = pcall(require, "Session")
    if okS and Session and Session.ModeIfKnown and Session.ModeIfKnown() == "singleplayer" then
        return false
    end
    return locally_controlled(player) == false
end

function PlayerRef.Get()
    local now = os.clock()

    local acting = actingStack[#actingStack]
    if acting ~= nil then
        if is_valid(acting) then return acting end
        return nil
    end

    if on_dedicated_server() then return nil end

    if worldClosing then return nil end

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

function PlayerRef.ExpectWorldChange(seconds)
    fastLivenessUntil = os.clock() + (seconds or 20.0)
end

function PlayerRef.SetWorldClosing(on)
    cachedWorld = nil
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

function PlayerRef.PickLocal(list)
    return pick_local(list, os.clock())
end

function PlayerRef.SearchCount()
    return searchCount
end

return PlayerRef
