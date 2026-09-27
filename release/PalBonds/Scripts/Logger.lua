local Logger = {}

local DEBUG_LOGGING = false

local LOG_PATH_CANDIDATES = {
    "palbonds-live.log",
    "Pal/Binaries/Win64/ue4ss/Mods/PalBonds/palbonds-live.log",
    "Mods/NativeMods/UE4SS/Mods/PalBonds/palbonds-live.log",
    "C:/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64/ue4ss/Mods/PalBonds/palbonds-live.log",
}
local LOG_PATH = LOG_PATH_CANDIDATES[1]
local file = nil
local triedOpen = false
local function ensure_open()
    if file then
        return file
    end
    if triedOpen then

        return nil
    end
    triedOpen = true
    if not DEBUG_LOGGING then return end
    for _, candidate in ipairs(LOG_PATH_CANDIDATES) do
        local ok, f = pcall(io.open, candidate, "w")
        if ok and f then
            file = f
            LOG_PATH = candidate
            break
        end
    end
    return file
end

local SHOW_DIAGNOSTICS = false
local SUPPRESSED_TAGS = {
    "%[DIAG", "%[BALANCE%-DIAG%]", "%[BALANCE%-TEST%]", "%[EMOTE%-DIAG%]",
    "%[FOOD%-DIAG%]", "%[SLOT%-USE%-DIAG%]", "%[REST%-POOL%-DIAG%]",
    "%[CRASH%-DIAG%]", "%[NAME%-DIAG%]", "%[CAGE%-VFX%]",
    "%[FOLLOW%-FIELDS%]", "%[FOLLOW%-DIFF%]", "%[FOLLOW%-DIAG%]",
    "%[FOLLOW%-ACTOR%]", "%[FOLLOW%-POS%]", "%[FOLLOW%-INIT%]",
    "%[POST%-BOND%-DUMP%]", "%[AFTER%-BOND%]", "%[FOLLOW%-STUCK%]",
    "%[WORKER%-WATCH%]", "%[RADIAL%-WATCH%]", "%[INVENTORY%-WATCH%]",
    "%[OTOMO%-GETTER%-WATCH%]", "%[DAMAGE%-WATCH%]", "%[FOUR%-KEY%-SPY%]",
    "%[TRAINER%-REASSERT%]", "%[AIM%-FREEZE%]", "%[RADIAL%-REDIRECT%-PERF%]",
    "%[RADIAL%-REDIRECT%-FIELD%]", "%[RADIAL%-REDIRECT%]",
    "%[WORKER%-BIND%-FIX", "%[DIRECT%-FEED%-TEST%]", "%[EXPERIMENT%]",
    "%[PERSONALITY%-ROLL%]", "%[POST%-CAPTURE%-SLOT%]",
    "%[WILD%-ACTION%]", "%[FEED%-FRIENDSHIP%]", "%[RETARGET%]",
    "%[JOIN%-CELEBRATION%]", "%[JOIN%-VFX%]", "%[TERRITORY%]", "%[LEASH%]",
}
local function is_diagnostic(msg)
    for _, pattern in ipairs(SUPPRESSED_TAGS) do
        if msg:find(pattern) then return true end
    end
    return false
end

function Logger.DiagnosticsEnabled()
    return DEBUG_LOGGING and SHOW_DIAGNOSTICS
end

local TRACE_PHASES = false

local traceSeq = 0

function Logger.trace(phase, detail)
    if not (DEBUG_LOGGING and TRACE_PHASES) then return end
    local f = ensure_open()
    if not f then return end
    traceSeq = traceSeq + 1
    pcall(function()
        f:write(string.format("[T%07d %.3f] %s%s\n", traceSeq, os.clock(),
            tostring(phase), detail ~= nil and (" " .. tostring(detail)) or ""))
        f:flush()
    end)
end

function Logger.log(msg)

    if not DEBUG_LOGGING then return end
    if not SHOW_DIAGNOSTICS and type(msg) == "string" and is_diagnostic(msg) then return end
    print(msg)
    local f = ensure_open()
    if not f then
        return
    end
    pcall(function()
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
        f:flush()
    end)
end
function Logger.Init()

    if not DEBUG_LOGGING then return end
    local f = ensure_open()
    if f then
        Logger.log("[PalBonds/Logger] live log started (crash-resistant, flushed per line) -> " .. LOG_PATH)
    else
        print("[PalBonds/Logger] could not open live log file at " .. LOG_PATH .. " — falling back to normal print only (still subject to UE4SS's own buffering)\n")
    end
end
return Logger
