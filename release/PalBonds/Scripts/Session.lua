local Session = {}

local mode = nil
local announced = nil
local provisional = nil
local lastReadAt = -1e9

local RE_READ_SECONDS = 2.0

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function is_valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

local function get_world()

    local util = safe_call(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if is_valid(util) then
        local w = safe_call(function() return util:GetWorld() end)
        if is_valid(w) then return w end
    end
    local okH, UEHelpers = pcall(require, "UEHelpers")
    if okH and UEHelpers and UEHelpers.GetWorld then
        local w = safe_call(UEHelpers.GetWorld)
        if is_valid(w) then return w end
    end
    return nil
end

local function read_mode()
    local world = get_world()
    if world == nil then return nil end

    local driver = safe_call(function() return world.NetDriver end)
    if not is_valid(driver) then return "singleplayer" end

    local serverConnection = safe_call(function() return driver.ServerConnection end)
    if is_valid(serverConnection) then return "client" end

    local ksl = safe_call(function() return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary") end)
    if is_valid(ksl) and safe_call(function() return ksl:IsDedicatedServer(world) end) == true then
        return "dedicated"
    end

    local util = safe_call(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if is_valid(util) then
        local netMode = safe_call(function() return util:GetNetMode(world) end)
        if netMode ~= nil then
            local text = tostring(netMode):lower()
            if text:find("dedicated") then return "dedicated" end
        end
    end
    return "host"
end

local function player_is_in_the_world()
    local okRef, PlayerRefMod = pcall(require, "PlayerRef")
    if not (okRef and PlayerRefMod and PlayerRefMod.Get) then return false end
    local p = safe_call(PlayerRefMod.Get)
    return p ~= nil and is_valid(p)
end

function Session.Mode()
    if mode ~= nil then return mode end

    local now = os.clock()
    if provisional ~= nil and (now - lastReadAt) < RE_READ_SECONDS then
        return provisional
    end
    lastReadAt = now
    provisional = read_mode()

    if provisional == "dedicated" or (provisional ~= nil and player_is_in_the_world()) then
        mode = provisional
    end

    local answer = mode or provisional
    local stamp = (mode ~= nil and "final:" or "loading:") .. tostring(answer)
    if answer ~= nil and announced ~= stamp then
        announced = stamp
        local okL, Logger = pcall(require, "Logger")
        if okL and Logger and Logger.log then
            Logger.log("[PalBonds/Session] this is a " .. answer .. " session" ..
                (mode == nil and " (still loading — asking again until the player is in the world)" or ""))
        end
    end
    return answer
end

function Session.ModeIfKnown()
    return mode
end

function Session.IsGuest()
    return Session.Mode() == "client"
end

function Session.IsDedicated()
    return Session.Mode() == "dedicated"
end

function Session.MayAct()
    return not Session.IsGuest()
end

Session.ALLOW_GUEST_INPUT = true

function Session.GuestInputAllowed()
    return Session.ALLOW_GUEST_INPUT == true
end

function Session.Reset()
    mode = nil
    announced = nil
    provisional = nil
    lastReadAt = -1e9
end

function Session.SetModeForTest(m)
    mode = m
    provisional = m
    announced = "final:" .. tostring(m)
    lastReadAt = os.clock()
end

return Session
