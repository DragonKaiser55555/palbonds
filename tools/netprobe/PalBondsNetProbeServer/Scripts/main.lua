--[[
    PalBonds NET PROBE -- SERVER SIDE. A development tool, never shipped.

    Runs inside UE4SS on the machine that OWNS the world (the local dedicated
    server for now). It changes nothing in the game: it only watches and writes
    palbonds-netprobe-server.log, so the co-op design can be built on measured
    facts instead of guesses. See docs/multiplayer-questions.md, "Net probe".

    What it answers:
      1. Does UE4SS load on the dedicated server at all?            ([START])
      2. Which players are in the world, and which one is local?     ([PLAYERS])
      3. What does the server receive when a GUEST pets or feeds a
         wild Pal, and does it know which player sent it?            ([RPC])
      4. Do the pair animations (pet / feed) run here, on the
         server, for a guest?                                        ([PAIR])
      5. Can the server read wild Pals' AI sensors (the guest
         could not read a single one)?                               ([SENSORS])
      6. Does our private line work? A guest's F6 sends
         "PALBONDS-PING n" through Debug_CheatCommand_ToServer; this
         answers "PALBONDS-PONG n" through
         Debug_ReceiveCheatCommand_ToClient on THAT player only.     ([CHANNEL])
]]

local LOG_CANDIDATES = {
    "palbonds-netprobe-server.log",
    "C:/Program Files (x86)/Steam/steamapps/common/PalServer/Pal/Binaries/Win64/palbonds-netprobe-server.log",
}
local logFile = nil
for _, path in ipairs(LOG_CANDIDATES) do
    local ok, f = pcall(io.open, path, "w")
    if ok and f then logFile = f break end
end

local function log(msg)
    local line = string.format("[%s] [NetProbe/Server] %s", os.date("%Y-%m-%d %H:%M:%S"), msg)
    print(line .. "\n")
    if logFile then
        logFile:write(line, "\n")
        logFile:flush()
    end
end

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function get(param)
    if param == nil then return nil end
    return safe(function() return param:get() end)
end

local function name_of(obj)
    if obj == nil then return "nil" end
    local n = safe(function() return obj:GetFullName() end)
    if n == nil then return tostring(obj) end
    -- The short part after the last dot is enough to read, and keeps lines short.
    return tostring(n):match("([^%.]+)$") or tostring(n)
end

local function valid(obj)
    return obj ~= nil and safe(function() return obj:IsValid() end) == true
end

local function fstring(param)
    local v = get(param)
    if v == nil then return nil end
    local s = safe(function() return v:ToString() end)
    if s ~= nil then return tostring(s) end
    return tostring(v)
end

-- A player controller -> "<pawn short name> (local|remote)".
local function describe_controller(ctrl)
    if not valid(ctrl) then return "no controller" end
    local pawn = safe(function() return ctrl.Pawn end)
    local isLocal = safe(function() return ctrl:IsLocalPlayerController() end)
    local who = valid(pawn) and name_of(pawn) or "no pawn"
    return string.format("%s (%s)", who, isLocal == true and "LOCAL" or (isLocal == false and "remote" or "?"))
end

log("[START] server probe loaded -- UE4SS runs on this process")

-- ---------------------------------------------------------------- hooks

local function hook(path, pre, post)
    local ok, err = pcall(function() RegisterHook(path, pre or function() end, post or function() end) end)
    log(string.format("[HOOK] %s = %s", path, ok and "OK" or ("FAILED: " .. tostring(err))))
end

-- 6. The private line, guest -> server -> that same guest.
local pingsSeen = 0
hook("/Script/Pal.PalPlayerController:Debug_CheatCommand_ToServer", function(Context, Command)
    local ctrl = get(Context)
    local text = fstring(Command) or "?"
    pingsSeen = pingsSeen + 1
    log(string.format("[CHANNEL] Debug_CheatCommand_ToServer from %s: \"%s\"", describe_controller(ctrl), text))
    if text:sub(1, 13) == "PALBONDS-PING" and valid(ctrl) then
        local reply = "PALBONDS-PONG" .. text:sub(14) .. " (server saw " .. pingsSeen .. ")"
        local ok, err = pcall(function() ctrl:Debug_ReceiveCheatCommand_ToClient(reply) end)
        log(string.format("[CHANNEL] replied \"%s\" to that player only -> %s", reply, ok and "call ok" or ("FAILED: " .. tostring(err))))
    end
end)

-- 3. What a guest's pet / feed / action request looks like on arrival.
hook("/Script/Pal.PalPlayerController:ActionComponent_PlayAction_ToServer_ForPlayer", function(Context, TargetActor, Param, ActionClass, IssuerID)
    local ctrl = get(Context)
    local target = get(TargetActor)
    local cls = get(ActionClass)
    local issuer = get(IssuerID)
    local actorParam = safe(function() return get(Param).ActorParam end)
    log(string.format("[RPC] PlayAction_ToServer_ForPlayer from %s: action=%s target=%s actorParam=%s issuer=%s",
        describe_controller(ctrl), name_of(cls), name_of(target), name_of(actorParam), tostring(issuer)))
end)

hook("/Script/Pal.PalPlayerController:RequestUseItemToCharacter_ToServer", function(Context)
    log(string.format("[RPC] RequestUseItemToCharacter_ToServer from %s", describe_controller(get(Context))))
end)

hook("/Script/Pal.PalItemSlot:RequestUseToCharacter", function(Context, TargetCharacterID, UseNum)
    log(string.format("[RPC] PalItemSlot:RequestUseToCharacter ran here (slot %s, num %s)",
        name_of(get(Context)), tostring(get(UseNum))))
end)

hook("/Script/Pal.PalCaptureJudgeObject:ChallengeCapture_ToServer", function(Context, Character)
    log(string.format("[RPC] ChallengeCapture_ToServer on %s", name_of(get(Character))))
end)

-- ---------------------------------------------------------------- polling

local knownPlayers = {}
local lastPlayerAction = {}
local lastPalAction = {}
local sensorsReported = false

local INTERESTING = { "Pair", "Petting", "Feed", "Emote" }
local function interesting(n)
    if n == nil then return false end
    for _, w in ipairs(INTERESTING) do
        if n:find(w, 1, true) then return true end
    end
    return false
end

local function player_action(p)
    return safe(function()
        local ac = p.ActionComponent
        if not valid(ac) then return nil end
        local cur = ac:GetCurrentAction()
        if not valid(cur) then return "" end
        return name_of(cur)
    end)
end

local function pal_ai_action(pal)
    return safe(function()
        local ctrl = pal.Controller
        if not valid(ctrl) then return nil end
        local ac = ctrl:GetAIActionComponent()
        if not valid(ac) then return nil end
        local a = ac:GetCurrentAction_BP()
        if not valid(a) then return "" end
        return name_of(a)
    end)
end

local function dist(a, b)
    local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function poll()
    -- 2. players
    local players = safe(function() return FindAllOf("PalPlayerCharacter") end) or {}
    local seenNow, positions = {}, {}
    for _, p in ipairs(players) do
        if valid(p) then
            local key = name_of(p)
            seenNow[key] = true
            local loc = safe(function() return p:K2_GetActorLocation() end)
            if loc then positions[#positions + 1] = loc end
            if not knownPlayers[key] then
                knownPlayers[key] = true
                local isLocal = safe(function() return p:IsLocallyControlled() end)
                local auth = safe(function() return p:HasAuthority() end)
                log(string.format("[PLAYERS] in the world: %s  locallyControlled=%s  hasAuthority=%s  (%d player(s) now)",
                    key, tostring(isLocal), tostring(auth), #players))
            end
            local act = player_action(p)
            if act ~= lastPlayerAction[key] then
                if interesting(act) or interesting(lastPlayerAction[key]) then
                    log(string.format("[PAIR] player %s action: %s -> %s", key, tostring(lastPlayerAction[key]), tostring(act)))
                end
                lastPlayerAction[key] = act
            end
        end
    end
    for key in pairs(knownPlayers) do
        if not seenNow[key] then
            knownPlayers[key] = nil
            lastPlayerAction[key] = nil
            log("[PLAYERS] left the world: " .. key)
        end
    end

    -- 4. pet / feed animations on wild Pals near any player
    if #positions > 0 then
        local pals = safe(function() return FindAllOf("PalCharacter") end) or {}
        for _, pal in ipairs(pals) do
            if valid(pal) then
                local loc = safe(function() return pal:K2_GetActorLocation() end)
                local near = false
                if loc then
                    for _, pp in ipairs(positions) do
                        if dist(loc, pp) < 1500 then near = true break end
                    end
                end
                if near then
                    local key = name_of(pal)
                    local act = pal_ai_action(pal)
                    if act ~= lastPalAction[key] then
                        if interesting(act) or interesting(lastPalAction[key]) then
                            log(string.format("[PAIR] Pal %s AI action: %s -> %s", key, tostring(lastPalAction[key]), tostring(act)))
                        end
                        lastPalAction[key] = act
                    end
                end
            end
        end

        -- 5. sensors: once, when the first player is in
        if not sensorsReported then
            sensorsReported = true
            local sensors = safe(function() return FindAllOf("PalAISensorComponent") end) or {}
            log(string.format("[SENSORS] PalAISensorComponent objects readable on the server: %d (a guest read none)", #sensors))
        end
    end
end

local function loop()
    pcall(poll)
    pcall(function() ExecuteInGameThreadWithDelay(1000, loop) end)
end
pcall(function() ExecuteInGameThreadWithDelay(3000, loop) end)
log("[START] polling every 1 s: players, pair animations, sensors")
