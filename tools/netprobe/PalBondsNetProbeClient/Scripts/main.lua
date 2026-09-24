--[[
    PalBonds NET PROBE -- CLIENT SIDE. A development tool, never shipped.

    Runs in the game of the player who JOINS a world (a guest). Press F6 to
    send "PALBONDS-PING <n>" to the server through the game's own
    Debug_CheatCommand_ToServer request; the server probe answers through
    Debug_ReceiveCheatCommand_ToClient, which this logs. If both lines show up
    -- the ping on the server, the pong here -- PalBonds has a private line
    between the host and each guest, which is what lets a host's copy tell a
    guest their trust bar, tag and messages. Changes nothing in the game.
    Log: palbonds-netprobe-client.log next to palbonds-live.log.
]]

local logFile = nil
for _, path in ipairs({
    "palbonds-netprobe-client.log",
    "C:/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64/palbonds-netprobe-client.log",
}) do
    local ok, f = pcall(io.open, path, "w")
    if ok and f then logFile = f break end
end

local function log(msg)
    local line = string.format("[%s] [NetProbe/Client] %s", os.date("%Y-%m-%d %H:%M:%S"), msg)
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

local function valid(obj)
    return obj ~= nil and safe(function() return obj:IsValid() end) == true
end

log("[START] client probe loaded -- F6 sends a ping to the server")

local ok, err = pcall(function()
    RegisterHook("/Script/Pal.PalPlayerController:Debug_ReceiveCheatCommand_ToClient", function(Context, Message)
        local text = safe(function() return Message:get():ToString() end) or "?"
        log(string.format("[CHANNEL] RECEIVED from the server: \"%s\"", tostring(text)))
    end, function() end)
end)
log("[HOOK] Debug_ReceiveCheatCommand_ToClient = " .. (ok and "OK" or ("FAILED: " .. tostring(err))))

local function local_controller()
    local ctrls = safe(function() return FindAllOf("PalPlayerController") end) or {}
    for _, c in ipairs(ctrls) do
        if valid(c) and safe(function() return c:IsLocalPlayerController() end) == true then
            return c
        end
    end
    return nil
end

local pings = 0
local function send_ping()
    local ctrl = local_controller()
    if ctrl == nil then
        log("[CHANNEL] no local player controller yet -- are you in a world?")
        return
    end
    pings = pings + 1
    local text = "PALBONDS-PING " .. pings
    local okSend, errSend = pcall(function() ctrl:Debug_CheatCommand_ToServer(text) end)
    log(string.format("[CHANNEL] sent \"%s\" -> %s", text, okSend and "call ok" or ("FAILED: " .. tostring(errSend))))
end

-- Keybinds run on UE4SS's own thread: hop to the game thread before touching
-- anything (PalBonds' pass-333 lesson).
RegisterKeyBind(Key.F6, function()
    local hopped = pcall(function() ExecuteInGameThread(send_ping) end)
    if not hopped then
        pcall(function() ExecuteInGameThreadWithDelay(1, send_ping) end)
    end
end)
