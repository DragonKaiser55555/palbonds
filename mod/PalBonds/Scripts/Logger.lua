local Logger = {}

-- ===================================================================
-- RELEASE SWITCH (two-hundred-and-forty-second pass, 2026-09-07)
-- ===================================================================
-- Set DEBUG_LOGGING = true to get the full development log back. Shipped as
-- false, and that is the single most important line in this file for anyone
-- who is not developing the mod.
--
-- What this file did all through development, and why none of it can ship:
--   * opened a log file and FLUSHED IT TO DISK ON EVERY SINGLE LINE. That was
--     the right call while chasing crashes — a crash-resistant log survives the
--     process dying — and it is constant disk I/O for a player who will never
--     read it.
--   * grew that file without bound for the length of a session.
--   * printed everything to UE4SS's own console on top of that.
--
-- With DEBUG_LOGGING false, Logger.log returns immediately: no file is opened,
-- nothing is written and nothing is printed.
--
-- HONEST LIMITATION, stated because this project has been bitten by exactly
-- this three separate times: a no-op log function does NOT make a log statement
-- free. Lua evaluates arguments before the call, so any string.format or ".."
-- concatenation at the call site still runs, and any GetFullName() inside it is
-- still a reflection round-trip into the engine. The genuinely hot paths in
-- this mod are already throttled at the call site (the re-assert loop logs one
-- line in a hundred, and reads its diagnostic values only on the passes that
-- actually log), so what remains is the ordinary once-per-event logging, which
-- is cheap. This switch removes the disk I/O and the console spam, which are
-- the parts a player would actually feel.
-- TEMPORARILY TRUE (two-hundred-and-forty-fifth pass, 2026-09-07) for ONE
-- measuring session: Dragón reported feeling lag and agreed to run with logging
-- on so the [RADIAL-REDIRECT-PERF] timings say what is actually slow instead of
-- us guessing. That line already prints any scan taking 15ms or more.
--
-- >>> SET THIS BACK TO false BEFORE SHIPPING. <<<
-- With it on, every log line is flushed to disk as it is written and the file
-- grows for the whole session. That is the behaviour the release build exists to
-- remove.
local DEBUG_LOGGING = true

-- Only used when DEBUG_LOGGING is on. Relative, because the absolute path this
-- used to hardcode pointed at one specific machine's Steam install: mods
-- installed from the Workshop live under
-- Palworld/Mods/NativeMods/UE4SS/Mods/<PackageName>/ instead, so that path
-- silently failed to open for anyone who was not the author, and the fallback
-- print was all they ever got.
-- Tried in order, first one that opens wins. A single path cannot work for
-- everyone: a manual UE4SS install puts the mod under
-- Pal/Binaries/Win64/ue4ss/Mods/PalBonds/ while a Workshop install puts it under
-- Mods/NativeMods/UE4SS/Mods/PalBonds/, and the plain relative name depends
-- entirely on what the game happens to have as its working directory. The old
-- code hardcoded one absolute path belonging to one machine, so for anyone else
-- turning debug logging on produced no file at all and no explanation.
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

        -- Already failed once this session; don't spam retries.
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

-- Writes msg to both the normal UE4SS log (via print, so it still shows
-- up in the console/log when everything goes fine) AND the crash-safe
-- live log file (flushed immediately). Safe to call even if the file
-- couldn't be opened — falls back to print-only silently.
-- ===================================================================
-- DIAGNOSTIC FILTER (two-hundred-and-seventieth pass, 2026-09-07) — v1.0
-- ===================================================================
-- Dragon, packing up: "remove all the unnecesary logs you find, its time to
-- pack up the finished product".
--
-- Every tag below belongs to a research question this project has already
-- ANSWERED. They were how the mod got built -- the widget hunt, the balance
-- numbers, the follow-action field dumps, the feed dispatch chase -- and none of
-- them tells anyone anything now. In the last session's log they were roughly
-- nine lines in ten, which is what buries the handful that matter when something
-- actually goes wrong.
--
-- Filtered rather than deleted from the call sites, for two reasons: ripping out
-- several hundred scattered log statements across seven files is exactly the
-- kind of wide, mechanical edit that breaks something on the eve of a release,
-- and the diagnostics themselves are worth keeping in the source -- they are the
-- reason several of this project's hardest bugs were ever found. Flip
-- SHOW_DIAGNOSTICS back to true and every one of them returns.
--
-- What deliberately still logs, because these are what a real bug report needs:
-- FOLLOW-ACTION, BETRAYAL, HP-WATCH, HATE-ASSIST, HATE-RELEASE, RECALL,
-- JOIN-BONUS, NOTIFY, GRANT, TAG-TOGGLE, LEVEL-MULT, WON-OVER, FORCE-TIER,
-- COMPANION, ENFORCE (un-filtered 2026-09-19: Esaeon's crash log went silent
-- right after a preset dump, and ENFORCE is what runs next), plus anything that
-- reports a real failure.
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

-- Two-hundred-and-eighty-eighth pass (2026-09-09). Logger.log already discards
-- diagnostic lines in a release build, but Lua evaluates a call's ARGUMENTS
-- before the call -- so anything expensive built to produce those lines still
-- runs in full, every time, and is then thrown away. This project has now paid
-- for that three separate times (the SetHPPercent hook, the OTOMO-GETTER-WATCH
-- logging, and the sensor hook's GetFullName dedup).
--
-- Call sites doing real work purely to log can ask first and skip the work
-- outright. This is only worth using where the work is a world scan or
-- reflection -- an ordinary string concat is cheaper than the check.
function Logger.DiagnosticsEnabled()
    return DEBUG_LOGGING and SHOW_DIAGNOSTICS
end
-- REMOVED for the stable build (2026-09-12): the F7 runtime log switch
-- (SetEnabled/IsEnabled/IsDevBuild). It answered its question -- run 37 showed
-- logging is not the fight lag -- and a release build has no log to toggle.
-- DevWatch (temporary instrumentation) asks this before doing any work.
-- ===================================================================
-- PHASE TRACE (2026-09-20, for Esaeon's crash -- GitHub #1)
-- ===================================================================
-- Their game dies inside UE4SS with no Lua error and no stack: the log simply
-- stops. Two crashes now, the same 64 frames, reached from different places,
-- and the second one had no Pal joining at all. What we cannot see is WHICH
-- of the mod's repeating jobs was running at that instant.
--
-- So each job and each risky engine call writes one line before it runs. The
-- log is flushed per line, so whatever line comes last when the game dies
-- names the operation. Off by default (it is loud); the test builds turn it on.
local TRACE_PHASES = false

function Logger.trace(phase, detail)
    if not (DEBUG_LOGGING and TRACE_PHASES) then return end
    Logger.log("[TRACE] " .. tostring(phase) .. (detail ~= nil and (" " .. tostring(detail)) or ""))
end

function Logger.DebugEnabled()
    return DEBUG_LOGGING
end
function Logger.log(msg)

    -- First line on purpose: everything below is development-only.
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

    -- Two-hundred-and-forty-third pass (2026-09-07): the release build was still
    -- announcing itself. Dragón's clean-install console showed
    -- "could not open live log file at palbonds-live.log — falling back to
    -- normal print only", which is a development message about a file the
    -- release deliberately never opens. The previous pass guarded ensure_open
    -- but not this function, so Init still called it, got nil, and printed the
    -- failure branch. A shipped mod should be silent unless something is
    -- actually wrong.
    if not DEBUG_LOGGING then return end
    local f = ensure_open()
    if f then
        Logger.log("[PalBonds/Logger] live log started (crash-resistant, flushed per line) -> " .. LOG_PATH)
    else
        print("[PalBonds/Logger] could not open live log file at " .. LOG_PATH .. " — falling back to normal print only (still subject to UE4SS's own buffering)\n")
    end
end
return Logger
