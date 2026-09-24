--[[
    PalBonds — what kind of session is this, and may we act in it?

    WHY THIS EXISTS (2026-09-20, measured on a local dedicated server).
    Everything this mod does to a Pal — rolling a personality onto its real AI,
    making it follow, the sphere-less join — happens on the machine that owns
    the world. A player who joins someone else's world owns nothing, and the
    game is blunt about it: finishing a bond as a guest killed the game outright
    with its own fatal error,

        PalNetworkIndividualComponent.cpp:157
        "a character-creation request was attempted from the client"

    because the join asks the game to create a character and only the server may
    do that. Short of that, a guest's copy of the mod spent the session failing:
    46 attempts to read a Pal's AI sensor, none successful; the follow action
    rebuilt 25 times in a minute while the server threw it away; pets that could
    not be confirmed because a Pal's actions are not readable either. The tags
    still appeared, showing personalities no Pal actually had.

    Dragón's call: "in case a guest has our mod active shouldnt we just return or
    do nothing on that regard? - like if im a guest and im playing on a server
    with palbonds already active, then my copy of palworld should do nothing so
    they dont crash among themselves."

    So: on a guest, the mod does nothing at all. Not a crash, and not a half
    version of itself that shows trust bars which can never fill.

    HOW THE MODE IS FOUND. The technique is the one the "Multi Party Pals
    Summons" reference mod uses, read from its source rather than invented here:

      * no NetDriver on the world            -> singleplayer
      * the NetDriver has a ServerConnection -> we are a GUEST in someone
                                                else's world
      * the net mode says "dedicated"        -> this is a dedicated server
      * otherwise                            -> we are hosting

    Only "guest" changes what the mod does today. Dedicated-server support would
    mean a different design again (no local player at all, and several players
    to keep apart), and is written up in docs/multiplayer-questions.md.

    FAILING OPEN. If the world, the NetDriver or the net mode cannot be read,
    the answer is "we may act". Singleplayer is the overwhelming majority of
    play, and a mod that silently switches itself off because one engine read
    failed would be a far worse bug than the one this prevents.
]]

local Session = {}

local mode = nil          -- "singleplayer" | "host" | "client" | "dedicated"
local announced = nil     -- the mode already written to the log
local provisional = nil   -- the latest answer while we are not confident yet
local lastReadAt = -1e9
local RE_READ_SECONDS = 0.5

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
    local okH, UEHelpers = pcall(require, "UEHelpers")
    if okH and UEHelpers and UEHelpers.GetWorld then
        local w = safe_call(UEHelpers.GetWorld)
        if is_valid(w) then return w end
    end
    local util = safe_call(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if is_valid(util) then
        local w = safe_call(function() return util:GetWorld() end)
        if is_valid(w) then return w end
    end
    return nil
end

-- Reads the mode fresh. Returns nil when there is no world to ask yet (the
-- title screen), so the answer is not cached before it means anything.
local function read_mode()
    local world = get_world()
    if world == nil then return nil end

    local driver = safe_call(function() return world.NetDriver end)
    if not is_valid(driver) then return "singleplayer" end

    local serverConnection = safe_call(function() return driver.ServerConnection end)
    if is_valid(serverConnection) then return "client" end
    -- Co-op run 1 (2026-09-21): on the local dedicated server the net-mode
    -- text below did NOT contain "dedicated", so the server called itself a
    -- host. The engine's own answer comes first.
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

-- Is our own character in the world yet? Until it is, the world we can see may
-- be the title screen's or one still loading, and a loading world has no
-- NetDriver yet -- which reads exactly like singleplayer.
--
-- THIS COST A TEST RUN (2026-09-20). The answer was cached one second after
-- every world change, while Dragón was still at the title screen: it said
-- "singleplayer", and when he then joined the dedicated server the mod believed
-- it all session. His log shows the three lines, each within two seconds of a
-- reset. So nothing is remembered until our player exists, which is also the
-- first moment anything in the mod has work to do.
local function player_is_in_the_world()
    local okRef, PlayerRefMod = pcall(require, "PlayerRef")
    if not (okRef and PlayerRefMod and PlayerRefMod.Get) then return false end
    local p = safe_call(PlayerRefMod.Get)
    return p ~= nil and is_valid(p)
end

-- "singleplayer", "host", "client", "dedicated", or nil while there is no world.
function Session.Mode()
    if mode ~= nil then return mode end

    local now = os.clock()
    if provisional ~= nil and (now - lastReadAt) < RE_READ_SECONDS then
        return provisional
    end
    lastReadAt = now
    provisional = read_mode()

    -- A dedicated server never has a player of its own to wait for, and a
    -- process never stops being one: that answer is final at once.
    if provisional == "dedicated" or (provisional ~= nil and player_is_in_the_world()) then
        mode = provisional
    end

    -- Announced twice at most per session: once as soon as there is any
    -- answer, and again when it becomes final. Without the second line a log
    -- says "still loading" for a session that settled seconds later, which
    -- reads like the detection never worked.
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

-- True only when we are a guest in somebody else's world. Everything else --
-- including "we cannot tell yet" -- is false, so the mod keeps working.
function Session.IsGuest()
    return Session.Mode() == "client"
end

-- A dedicated server: the world's owner, with no player of its own. Nobody
-- sits at it, so there is no local player, no screen and no keyboard.
function Session.IsDedicated()
    return Session.Mode() == "dedicated"
end

-- The single question every gameplay system asks before it does anything.
function Session.MayAct()
    return not Session.IsGuest()
end

-- GUEST INPUT (1.1.7, 2026-09-23) -- ships TRUE.
-- Co-op is host-authoritative: the machine that owns the world does every
-- Pal-side job, and a guest supplies INPUT. The one piece of input only a
-- guest's own screen can make is the radial-menu substitution (a wild Pal
-- cannot be petted or fed at all in the base game), so a guest keeps those
-- hooks and its game tells the owner what it did (Net.lua). Everything else
-- still stands down on a guest: the follow and the join refuse there as they
-- always have, so the fatal client-side join cannot happen.
--
-- It was born as GUEST_INPUT_PROBE for the net-probe run of 2026-09-21, shipped
-- false while co-op was measured. Set it to false to put a guest back to doing
-- nothing at all, which is 1.1.6's behaviour.
Session.ALLOW_GUEST_INPUT = true

function Session.GuestInputAllowed()
    return Session.ALLOW_GUEST_INPUT == true
end

-- A new world can be a different kind of session: called from
-- Combat.ResetForNewWorld along with everything else that is dropped.
function Session.Reset()
    mode = nil
    announced = nil
    provisional = nil
    lastReadAt = -1e9
end

-- Tests only.
function Session.SetModeForTest(m)
    mode = m
    provisional = m
    announced = "final:" .. tostring(m)
    lastReadAt = os.clock()
end

return Session
