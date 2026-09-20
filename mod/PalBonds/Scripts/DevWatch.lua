--[[
    DevWatch -- TEMPORARY development instrumentation (2026-09-19).
    NOT SHIPPED: delete this file and its call sites before any release
    (they are all marked "DevWatch"). Does nothing unless Logger's
    DEBUG_LOGGING is on, so a stray copy costs one boolean check.

    Open questions from the 1.1.5 player reports:

    1. PAIR-WATCH -- a Feed (or Pet) on a wild Pal that gets interrupted
       (Goldaer's Reindrix hit him mid-feed) leaves the PLAYER stuck in the
       waiting pose, and the food was already spent. To fix it properly we need
       the real sequence: which actions the player and the Pal run, in what
       order, when the food is taken, and what changes when a hit breaks it.
       So from the moment a Pet/Feed starts, the player's current action, the
       Pal's AI action and the Pal's own action are logged every time any of
       them changes, for 15 seconds.

    2. RECORD-WATCH / BOSS-REWARD -- whether a boss that joins counts as
       defeated: the player's records, and what the game pays for a first kill.
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

-- ------------------------------------------------------------------
-- 2. RECORD-WATCH and BOSS-REWARD
-- ------------------------------------------------------------------
-- Reads the player's own records (boss defeat flags keyed by spawner name,
-- and the counts) so a run can be compared before and after, and watches the
-- two client messages the game sends when a first boss kill pays out. Run 8
-- proved the defeat is credited to players who DAMAGED the boss, which
-- Capture now reports the way a capture sphere does; these lines are how a
-- run shows whether that worked.
local lastRecord = nil

-- The player's records: the boss defeat flags (keyed by spawner name) and the
-- counts, read through UPalUtility:GetLocalRecordData.
local function read_record(player)
    local utility = safe(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
    if utility == nil then return nil end
    local rec = safe(function() return utility:GetLocalRecordData(player) end)
    if rec == nil or not safe(function() return rec:IsValid() end) then return nil end
    local r = { bossFlags = {}, flagCount = 0 }
    r.bossDefeats = safe(function() return rec:GetNormalBossDefeatCount() end)
    r.captures = safe(function() return rec:GetTotalPalCaptureCount() end)
    pcall(function()
        rec.NormalBossDefeatFlag.Items:ForEach(function(_, elem)
            pcall(function()
                local e = elem:get()
                r.bossFlags[safe(function() return e.Key:ToString() end) or "?"] = tostring(e.Value)
                r.flagCount = r.flagCount + 1
            end)
        end)
    end)
    return r
end

function DevWatch.RecordSnapshot(tag)
    if not enabled() then return end
    local player = safe(function() return require("PlayerRef").Get() end)
    if player == nil then return end
    local r = read_record(player)
    if r == nil then
        Logger.log("[RECORD-WATCH] could not read the player's record data")
        return
    end
    local keys = {}
    for k, v in pairs(r.bossFlags) do keys[#keys + 1] = k .. "=" .. v end
    table.sort(keys)
    Logger.log(string.format("[RECORD-WATCH] %s: boss defeats=%s, captures=%s, flags (%d): %s",
        tostring(tag), tostring(r.bossDefeats), tostring(r.captures), r.flagCount, table.concat(keys, ", ")))
    lastRecord = r
end

function DevWatch.RecordSnapshotSoon(tag, ms)
    if not enabled() then return end
    pcall(function()
        ExecuteInGameThreadWithDelay(ms or 3000, function() pcall(DevWatch.RecordSnapshot, tag) end)
    end)
end

function DevWatch.Init()
    if not enabled() then return end

    -- What a real first kill hands out. Run 3 hooked these on
    -- APalPlayerController and they refused: they live on
    -- UPalNetworkPlayerComponent. Client RPCs go through ProcessEvent, so
    -- these should fire on a real kill and show the reward data
    -- (FPalUIBossDefeatRewardDisplayData = TechnologyPoint + the boss id).
    for _, path in ipairs({
        "/Script/Pal.PalNetworkPlayerComponent:ShowBossDefeatRewardUI_ToClient",
        "/Script/Pal.PalNetworkPlayerComponent:ShowDefeatBossBonusExpReward_ToClient",
    }) do
        local short = path:match(":(.+)$")
        local ok = pcall(function()
            RegisterHook(path, function(Context, A1, A2, A3)
                local function tell(v)
                    local x = safe(function() return v:get() end)
                    if x == nil then return "-" end
                    if type(x) == "number" or type(x) == "boolean" or type(x) == "string" then return tostring(x) end
                    local tp = safe(function() return x.TechnologyPoint end)
                    local id = safe(function() return x.DefeatCharacterID:ToString() end)
                    if tp ~= nil or id ~= nil then return string.format("{TechnologyPoint=%s, boss=%s}", tostring(tp), tostring(id)) end
                    return "?"
                end
                Logger.log(string.format("[BOSS-REWARD] %s FIRED | %s | %s | %s", short, tell(A1), tell(A2), tell(A3)))
            end)
        end)
        Logger.log("[BOSS-REWARD] hook " .. short .. ": " .. (ok and "OK" or "FAILED"))
    end

    -- A baseline of the player's records once the world is up; the join's own
    -- [BOSS-CREDIT] and [BOSS-REWARD] lines tell the rest.
    pcall(function()
        ExecuteInGameThreadWithDelay(20000, function() pcall(DevWatch.RecordSnapshot, "baseline") end)
    end)
end

return DevWatch
