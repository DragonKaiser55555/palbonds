--[[
    PalBonds — development profiler (microstutter investigation, 2026-09-15).

    WHY THIS EXISTS. A PresentMon A/B on 2026-09-15 proved the mod stalls the
    game: 1% low 16 fps with PalBonds on against 36 fps with it off, and three
    repeating stall series (8.1s ~119ms, 2.05s ~48ms, 3.07s ~48ms) that vanish
    with the mod disabled. Matching a stall's period to a timer says WHICH timer;
    it cannot say which part of it is slow, and it says nothing about the costs
    that only appear in active play (followers, fights, the radial menu). This
    measures the actual code.

    HOW. When PROFILING is true, main.lua calls InstallGlobalWrappers() before
    requiring any other module. That replaces the UE4SS globals the mod uses to
    get called (RegisterHook, ExecuteInGameThreadWithDelay, LoopAsync,
    RegisterKeyBind, ...) and the world searches it calls (FindAllOf,
    FindFirstOf, StaticFindObject) with timing wrappers. Every hook, timer and
    world search in every module is then measured without touching the modules,
    including ones added later. Profiler.start()/stop() cover the few places a
    global cannot reach (per-Pal work inside a scan).

    Wrapped callbacks behave exactly like the originals: all return values pass
    through (LoopAsync's "true" still stops its loop), errors are re-raised with
    their original value, and nothing is allocated per call.

    WHEN PROFILING IS FALSE (every shipped build): InstallGlobalWrappers returns
    immediately, the globals are never replaced, and start() returns nil so
    stop() is one nil check. >>> SHIP WITH PROFILING = false. <<<

    OUTPUT. palbonds-profile.log next to palbonds-live.log, one report every
    REPORT_EVERY_S seconds: per system, calls / total / average / worst time and
    how many calls took 8ms+ and 16ms+ (at 60 fps a frame is 16.7ms), sorted by
    total, then every single call of STALL_MS or more with its time. Times are
    INCLUSIVE: a timer's time includes the world searches it made, which are
    also listed on their own lines. The debug log (Logger.lua) stays off; this
    file is written once per report, not per event.

    THE CLOCK. os.clock is all Lua offers here, at roughly 1ms resolution. A
    2026-09-07 note in Combat.lua says os.clock behaved like CPU time in game,
    which would inflate every duration; the 2026-09-15 PresentMon data points
    the other way (a 2.0s os.clock cache on a 1.53s tick expired on every second
    tick, as wall time would). Each report therefore prints os.clock elapsed
    next to wall-clock elapsed. If those two disagree, do not trust the
    durations in that file.
]]

local Profiler = {}

local PROFILING = false
local REPORT_EVERY_S = 10.0
local STALL_MS = 8.0
local MAX_STALLS_PER_REPORT = 200

local PATH_CANDIDATES = {
    "palbonds-profile.log",
    "Pal/Binaries/Win64/ue4ss/Mods/PalBonds/palbonds-profile.log",
    "Mods/NativeMods/UE4SS/Mods/PalBonds/palbonds-profile.log",
}

local clock = os.clock
local enabled = PROFILING
local installed = false

local stats = {}
local stalls = {}
local depth = 0
local sessionStart = 0
local lastReportAt = 0
local wallStart = 0
local minNonZeroMs = nil
local file = nil
local triedOpen = false
local reporting = false

function Profiler.Enabled()
    return enabled
end

local function ensure_open()
    if file or triedOpen then return file end
    triedOpen = true
    for _, candidate in ipairs(PATH_CANDIDATES) do
        local ok, f = pcall(io.open, candidate, "w")
        if ok and f then
            file = f
            break
        end
    end
    return file
end

local function record(name, seconds)
    local ms = seconds * 1000
    local s = stats[name]
    if not s then
        s = { calls = 0, total = 0, max = 0, over8 = 0, over16 = 0 }
        stats[name] = s
    end
    s.calls = s.calls + 1
    s.total = s.total + ms
    if ms > s.max then s.max = ms end
    if ms >= 8 then s.over8 = s.over8 + 1 end
    if ms >= 16 then s.over16 = s.over16 + 1 end
    if ms > 0 and (minNonZeroMs == nil or ms < minNonZeroMs) then minNonZeroMs = ms end
    if ms >= STALL_MS and #stalls < MAX_STALLS_PER_REPORT then
        stalls[#stalls + 1] = { t = clock() - sessionStart, ms = ms, name = name }
    end
end

local function write_report(now)
    reporting = true
    pcall(function()
        local f = ensure_open()
        if not f then return end
        local names = {}
        for n in pairs(stats) do names[#names + 1] = n end
        table.sort(names, function(a, b) return stats[a].total > stats[b].total end)
        local lines = {}
        lines[#lines + 1] = string.format(
            "[%s] os.clock elapsed %.1fs | wall elapsed %ds | window %.1fs | smallest non-zero timing %s ms",
            os.date("%H:%M:%S"), now - sessionStart, os.time() - wallStart, now - lastReportAt,
            minNonZeroMs and string.format("%.3f", minNonZeroMs) or "none")
        for _, n in ipairs(names) do
            local s = stats[n]
            lines[#lines + 1] = string.format(
                "  %-72s calls %6d | total %8.1f ms | avg %7.3f ms | max %6.1f ms | >=8ms %4d | >=16ms %4d",
                n, s.calls, s.total, s.total / s.calls, s.max, s.over8, s.over16)
        end
        for _, st in ipairs(stalls) do
            lines[#lines + 1] = string.format("  STALL at %.2fs  %.1f ms  %s", st.t, st.ms, st.name)
        end
        f:write(table.concat(lines, "\n") .. "\n")
        f:flush()
    end)
    stats = {}
    stalls = {}
    lastReportAt = now
    reporting = false
end

-- Reports are only written at the outermost level, so the write is never
-- counted inside some other callback's time.
local function maybe_report(now)
    if depth == 0 and not reporting and (now - lastReportAt) >= REPORT_EVERY_S then
        write_report(now)
    end
end

local function finish(name, t0, ok, ...)
    local now = clock()
    depth = depth - 1
    record(name, now - t0)
    maybe_report(now)
    if not ok then error((...), 0) end
    return ...
end

local function timed(name, fn)
    return function(...)
        depth = depth + 1
        local t0 = clock()
        return finish(name, t0, pcall(fn, ...))
    end
end

local function short_path(path)
    local s = tostring(path)
    return s:match("([^%./]+:[^:]+)$") or s
end

local function source_name(kind, fn)
    local ok, info = pcall(function() return debug.getinfo(fn, "S") end)
    if ok and type(info) == "table" then
        local src = tostring(info.short_src or info.source or "?")
        -- A file path shortens to "Trust.lua"; a chunk loaded from a string
        -- reports itself as [string "name"] and shortens to "name". Either
        -- way the name has no spaces, so the report stays one token per system.
        local fileName = src:match("([^/\\]+%.lua)") or src:match('^%[string "(.-)"%]$') or src
        fileName = fileName:gsub("%s+", "_")
        return kind .. " " .. fileName .. ":" .. tostring(info.linedefined)
    end
    return kind .. " (unknown source)"
end

local function wrap_function_args(kind, label, ...)
    local n = select("#", ...)
    local args = { ... }
    local seen = 0
    for i = 1, n do
        if type(args[i]) == "function" then
            seen = seen + 1
            local name = label or source_name(kind, args[i])
            if seen > 1 then name = name .. " (callback " .. seen .. ")" end
            args[i] = timed(name, args[i])
        end
    end
    return table.unpack(args, 1, n)
end

-- Times per-call work a global wrapper cannot see. Returns nil when profiling
-- is off, so the matching stop() is a single nil check.
function Profiler.start()
    if enabled then return clock() end
    return nil
end

function Profiler.stop(name, t0)
    if t0 == nil then return end
    local now = clock()
    record(name, now - t0)
    maybe_report(now)
end

function Profiler.InstallGlobalWrappers()
    if not enabled or installed then return false end
    installed = true
    sessionStart = clock()
    lastReportAt = sessionStart
    wallStart = os.time()

    local function wrap_api(globalName, kind, labelFn)
        local original = _G[globalName]
        if type(original) ~= "function" then return end
        _G[globalName] = function(...)
            local label = labelFn and labelFn(...) or nil
            return original(wrap_function_args(kind, label, ...))
        end
    end
    wrap_api("RegisterHook", "hook", function(path) return "hook " .. short_path(path) end)
    wrap_api("ExecuteInGameThreadWithDelay", "timer")
    wrap_api("ExecuteWithDelay", "timer")
    wrap_api("ExecuteInGameThread", "game-thread")
    wrap_api("LoopAsync", "loop")
    wrap_api("LoopInGameThreadWithDelay", "loop")
    wrap_api("RegisterKeyBind", "key")
    wrap_api("NotifyOnNewObject", "new-object", function(class) return "new-object " .. tostring(class) end)

    for _, globalName in ipairs({ "FindAllOf", "FindFirstOf", "StaticFindObject" }) do
        local original = _G[globalName]
        if type(original) == "function" then
            _G[globalName] = function(what, ...)
                depth = depth + 1
                local t0 = clock()
                return finish(globalName .. " " .. tostring(what), t0, pcall(original, what, ...))
            end
        end
    end

    pcall(function()
        local f = ensure_open()
        if f then
            f:write(string.format("[%s] PalBonds profiler started — report every %.0fs, stalls >= %.0f ms listed\n",
                os.date("%Y-%m-%d %H:%M:%S"), REPORT_EVERY_S, STALL_MS))
            f:flush()
        end
    end)
    print("[PalBonds] PROFILING ON — timing every hook, timer and world search into palbonds-profile.log\n")
    return true
end

return Profiler
