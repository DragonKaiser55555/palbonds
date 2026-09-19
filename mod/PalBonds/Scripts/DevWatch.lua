--[[
    DevWatch -- TEMPORARY development instrumentation (2026-09-19).
    NOT SHIPPED: delete this file and its call sites before any release
    (they are all marked "DevWatch"). Does nothing unless Logger's
    DEBUG_LOGGING is on, so a stray copy costs one boolean check.

    Open question from the 1.1.5 player reports:

    1. PAIR-WATCH -- a Feed (or Pet) on a wild Pal that gets interrupted
       (Goldaer's Reindrix hit him mid-feed) leaves the PLAYER stuck in the
       waiting pose, and the food was already spent. To fix it properly we need
       the real sequence: which actions the player and the Pal run, in what
       order, when the food is taken, and what changes when a hit breaks it.
       So from the moment a Pet/Feed starts, the player's current action, the
       Pal's AI action and the Pal's own action are logged every time any of
       them changes, for 15 seconds.

    (The boss/record watchers that lived here answered their question on
    2026-09-19 -- the defeat record is written by native sphere/kill code the
    mod cannot reach -- and were removed.)
]]

local Logger = require("Logger")

local DevWatch = {}

local function enabled()
    return Logger.DebugEnabled and Logger.DebugEnabled() == true
end

local function safe(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

local function short_name(obj)
    if obj == nil then return "-" end
    local valid = safe(function() return obj:IsValid() end)
    if not valid then return "-" end
    local full = safe(function() return obj:GetFullName() end)
    if type(full) ~= "string" then return "?" end
    return full:match("^(%S+)") or full
end

local function class_of_action(obj)
    if obj == nil then return "-" end
    local valid = safe(function() return obj:IsValid() end)
    if not valid then return "-" end
    local full = safe(function() return obj:GetFullName() end)
    if type(full) ~= "string" then return "?" end
    return full:match("^(%S+)") or full
end

-- ------------------------------------------------------------------
-- 1. PAIR-WATCH
-- ------------------------------------------------------------------
local PAIR_POLL_MS = 200
local PAIR_SECONDS = 15.0
local pairToken = 0

local function snapshot_pair(player, pal)
    local playerAction = safe(function()
        local ac = player.ActionComponent
        if ac == nil or not ac:IsValid() then return nil end
        return ac:GetCurrentAction()
    end)
    local palAI = safe(function()
        local ctrl = pal.Controller
        if ctrl == nil or not ctrl:IsValid() then return nil end
        local ac = ctrl:GetAIActionComponent()
        if ac == nil or not ac:IsValid() then return nil end
        return ac:GetCurrentAction_BP()
    end)
    local palAction = safe(function()
        local ac = pal.ActionComponent
        if ac == nil or not ac:IsValid() then return nil end
        return ac:GetCurrentAction()
    end)
    local dist = safe(function()
        local a = player:K2_GetActorLocation()
        local b = pal:K2_GetActorLocation()
        local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
        return math.sqrt(dx * dx + dy * dy + dz * dz)
    end)
    return class_of_action(playerAction), class_of_action(palAI), class_of_action(palAction), dist
end

function DevWatch.WatchPair(pal, label)
    if not enabled() or pal == nil then return end
    local player = safe(function() return require("PlayerRef").Get() end)
    if player == nil then return end
    pairToken = pairToken + 1
    local token = pairToken
    local startedAt = os.clock()
    local palName = short_name(pal)
    local last = nil
    Logger.log(string.format("[PAIR-WATCH] %s on %s started", tostring(label), palName))
    local function tick()
        if token ~= pairToken then return end
        local elapsed = os.clock() - startedAt
        if not safe(function() return pal:IsValid() end) then
            Logger.log(string.format("[PAIR-WATCH] +%.1fs the Pal is gone", elapsed))
            return
        end
        if not safe(function() return player:IsValid() end) then return end
        local p, ai, pa, dist = snapshot_pair(player, pal)
        local now = p .. "|" .. ai .. "|" .. pa
        if now ~= last then
            last = now
            Logger.log(string.format("[PAIR-WATCH] +%.1fs player=%s | pal AI=%s | pal action=%s | dist=%s",
                elapsed, p, ai, pa, dist and string.format("%.0f", dist) or "?"))
        end
        if elapsed >= PAIR_SECONDS then
            Logger.log(string.format("[PAIR-WATCH] %s on %s ended the %.0fs watch (last: player=%s)",
                tostring(label), palName, PAIR_SECONDS, p))
            return
        end
        pcall(function() ExecuteInGameThreadWithDelay(PAIR_POLL_MS, function() pcall(tick) end) end)
    end
    tick()
end

-- A marker inside a running watch, e.g. the moment the food is taken.
function DevWatch.Note(text)
    if not enabled() then return end
    Logger.log("[PAIR-WATCH] note: " .. tostring(text))
end

return DevWatch
