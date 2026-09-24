--[[
    PalBonds -- the private line between the machine that owns the world and
    each player who joined it.

    WHY (2026-09-21). Co-op is built host-authoritative: the machine that owns
    the world (singleplayer, a host, a dedicated server) does every Pal-side
    job, because only it can -- the guest run of 2026-09-20 measured that a
    guest cannot write a Pal's AI, cannot keep a follow action on it, and that
    asking for the join from a guest is a FATAL error in the game itself. A
    guest keeps the one part only its own screen can do, the radial-menu
    substitution, and that already reaches the owner: the game sends the pet
    or feed as its own request and the owner runs the real animation on the
    wild Pal (net probe run 1).

    What the game does not send is OUR part: which Pal it was, what food, and
    the messages back. This file carries those, on two requests every
    APalPlayerController already has and that take a plain string:

      guest -> owner    Debug_CheatCommand_ToServer(FString)
      owner -> guest    Debug_ReceiveCheatCommand_ToClient(FString)

    Measured in net probe run 1: 4 of 4 messages each way, the sender known on
    the owner (the hook's `self` is that player's controller), the reply
    reaching that player only, in 50-90 ms, and NOTHING shown on screen by the
    game for either -- so a player without the mod never notices them.

    FORMAT: "PB1", the kind, then the fields, separated by TAB. Anything that
    does not start with "PB1" is ignored, so the game's own use of these
    requests (if any) is never touched. Fields are plain text; TAB and newline
    inside a field are replaced with spaces.

    WHO LISTENS: every copy registers both hooks. Owner-side handlers
    (Net.OnServer) only run for a message from a REMOTE player -- in
    singleplayer, or for the host's own actions, the ordinary local code path
    already did the work. Guest-side handlers (Net.OnClient) run on the guest.
]]

local Logger = require("Logger")

local Net = {}

local PREFIX = "PB1"
local SEP = "\t"

local serverHandlers = {}
local clientHandlers = {}

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function valid(obj)
    return obj ~= nil and safe_call(function() return obj:IsValid() end) == true
end

local function clean(v)
    local s = tostring(v == nil and "" or v)
    s = s:gsub("[\t\r\n]", " ")
    return s
end

function Net.Encode(kind, ...)
    local parts = { PREFIX, clean(kind) }
    local n = select("#", ...)
    for i = 1, n do
        parts[#parts + 1] = clean((select(i, ...)))
    end
    return table.concat(parts, SEP)
end

-- Returns kind, { fields... } -- or nil for anything that is not ours.
function Net.Decode(text)
    if type(text) ~= "string" then return nil end
    if text:sub(1, #PREFIX + 1) ~= PREFIX .. SEP then return nil end
    local parts = {}
    for piece in (text .. SEP):gmatch("(.-)" .. SEP) do
        parts[#parts + 1] = piece
    end
    local kind = parts[2]
    if kind == nil or kind == "" then return nil end
    local fields = {}
    for i = 3, #parts do fields[#fields + 1] = parts[i] end
    return kind, fields
end

function Net.OnServer(kind, fn) serverHandlers[kind] = fn end
function Net.OnClient(kind, fn) clientHandlers[kind] = fn end

local function local_controller()
    local player = safe_call(function() return require("PlayerRef").Get() end)
    local ctrl = player and safe_call(function() return player.Controller end)
    if valid(ctrl) then return ctrl end
    local all = safe_call(function() return FindAllOf("PalPlayerController") end) or {}
    for _, c in ipairs(all) do
        if valid(c) and safe_call(function() return c:IsLocalPlayerController() end) == true then
            return c
        end
    end
    return nil
end

-- Guest -> the machine that owns the world. True when the request was sent.
function Net.SendToServer(kind, ...)
    local ctrl = local_controller()
    if ctrl == nil then
        Logger.log("[PalBonds/Net] could not send " .. tostring(kind) .. " to the host: no local player controller")
        return false
    end
    local text = Net.Encode(kind, ...)
    local ok, err = pcall(function() ctrl:Debug_CheatCommand_ToServer(text) end)
    Logger.log(string.format("[PalBonds/Net] -> host %s %s", tostring(kind),
        ok and "sent" or ("FAILED: " .. tostring(err))))
    return ok
end

-- The machine that owns the world -> one player. True when the request was sent.
function Net.SendToPlayer(player, kind, ...)
    local ctrl = player and safe_call(function() return player.Controller end)
    if not valid(ctrl) then
        Logger.log("[PalBonds/Net] could not send " .. tostring(kind) .. " to a player: no controller (they may have left)")
        return false
    end
    local text = Net.Encode(kind, ...)
    local ok, err = pcall(function() ctrl:Debug_ReceiveCheatCommand_ToClient(text) end)
    Logger.log(string.format("[PalBonds/Net] -> player %s %s", tostring(kind),
        ok and "sent" or ("FAILED: " .. tostring(err))))
    return ok
end

local function world_is_closing()
    local ok, PlayerRef = pcall(require, "PlayerRef")
    if not ok or PlayerRef == nil or PlayerRef.IsWorldClosing == nil then return false end
    local okAsk, closing = pcall(PlayerRef.IsWorldClosing)
    return okAsk and closing == true
end

-- The owner-side entry point, exposed so the harness can drive it directly.
function Net.HandleFromPlayer(ctrl, text)
    local kind, fields = Net.Decode(text)
    if kind == nil then return false end
    if world_is_closing() then return false end
    if not valid(ctrl) then return false end
    -- Our own controller: singleplayer or the host acting for themselves. The
    -- local code path already did this work; doing it again would pay twice.
    if safe_call(function() return ctrl:IsLocalPlayerController() end) == true then return false end
    local pawn = safe_call(function() return ctrl.Pawn end)
    if not valid(pawn) then
        Logger.log("[PalBonds/Net] <- " .. kind .. " from a player with no character — ignored")
        return false
    end
    local handler = serverHandlers[kind]
    if handler == nil then
        Logger.log("[PalBonds/Net] <- unknown message kind " .. tostring(kind) .. " — ignored (a newer PalBonds on that player?)")
        return false
    end
    Logger.log("[PalBonds/Net] <- " .. kind .. " from " .. tostring(safe_call(function() return pawn:GetFullName() end)) ..
        " [" .. table.concat(fields, " | ") .. "]")
    local ok, err = pcall(handler, ctrl, pawn, fields)
    if not ok then Logger.log("[PalBonds/Net] handler for " .. kind .. " failed (caught): " .. tostring(err)) end
    return ok
end

-- The guest-side entry point, exposed for the harness.
--
-- Only on the machine the message was sent TO. Calling a "to client" request
-- runs our hook on the SENDING machine too (UE4SS sees the call before it goes
-- out), and there the controller belongs to someone else -- without this check
-- a host would show every guest's messages on its own screen.
function Net.HandleFromHost(ctrl, text)
    local kind, fields = Net.Decode(text)
    if kind == nil then return false end
    if valid(ctrl) and safe_call(function() return ctrl:IsLocalPlayerController() end) == false then
        return false
    end
    local handler = clientHandlers[kind]
    if handler == nil then
        Logger.log("[PalBonds/Net] <- unknown message kind " .. tostring(kind) .. " from the host — ignored")
        return false
    end
    local ok, err = pcall(handler, fields)
    if not ok then Logger.log("[PalBonds/Net] host handler for " .. kind .. " failed (caught): " .. tostring(err)) end
    return ok
end

local initialised = false
function Net.Init()
    if initialised then return end
    initialised = true
    local okA, errA = pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:Debug_CheatCommand_ToServer", function(Context, Command)
            local ctrl = safe_call(function() return Context:get() end)
            local text = safe_call(function() return Command:get():ToString() end)
            if text ~= nil then Net.HandleFromPlayer(ctrl, tostring(text)) end
        end, function() end)
    end)
    local okB, errB = pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:Debug_ReceiveCheatCommand_ToClient", function(Context, Message)
            local ctrl = safe_call(function() return Context:get() end)
            local text = safe_call(function() return Message:get():ToString() end)
            if text ~= nil then Net.HandleFromHost(ctrl, tostring(text)) end
        end, function() end)
    end)
    Logger.log("[PalBonds/Net] line to/from other players: from-player hook " ..
        (okA and "OK" or ("FAILED: " .. tostring(errA))) .. ", from-host hook " ..
        (okB and "OK" or ("FAILED: " .. tostring(errB))))
end

return Net
