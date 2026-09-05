--[[
    Logger.lua — real-time, crash-resistant logging.

    Added 2026-09-01 after two hard game crashes in a row left ZERO trace
    in UE4SS.log of anything that happened in the seconds/minutes right
    before them — not because nothing was logged, but because UE4SS.log
    is buffered internally and only gets flushed to disk periodically. A
    hard native crash kills the process before that flush happens, so
    everything sitting in the buffer (including our own print() calls) is
    lost. Dragón asked for something that doesn't depend on the buffer
    closing cleanly.

    This writes a SEPARATE plain-text file directly via Lua's own `io`
    library (confirmed available in this UE4SS build — bundled mods like
    ConsoleCommandsMod's dump_object.lua already use io.open(...,"w+")),
    and calls file:flush() after every single line. flush() pushes the
    write from Lua's/the C runtime's buffer into the OS's own file cache
    immediately — the OS keeps that regardless of which process crashed,
    so a line written and flushed right before a crash survives on disk
    even though the crash itself is still not something Lua can catch or
    prevent.

    Writes to an ABSOLUTE path (not relative to whatever UE4SS's current
    working directory happens to be at the time) so it's always found in
    the same place: right next to this mod's own Scripts folder.

    UPDATED 2026-09-02: was opening in append ("a") mode, so the file
    grew forever across every game launch — 11,500+ lines after a few
    research sessions, with no real historical need for that (every
    finding worth keeping already gets copied into docs/hook-points.md
    as we go; the live log itself is just a short-term read-during-testing
    tool). Dragón asked for it to stop growing. Switched to "w" (truncate)
    so each game launch starts a fresh, short file again.
]]

local Logger = {}

local LOG_PATH = "C:/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64/ue4ss/Mods/PalBonds/palbonds-live.log"

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

    local ok, f = pcall(io.open, LOG_PATH, "w")
    if ok and f then
        file = f
    end
    return file
end

-- Writes msg to both the normal UE4SS log (via print, so it still shows
-- up in the console/log when everything goes fine) AND the crash-safe
-- live log file (flushed immediately). Safe to call even if the file
-- couldn't be opened — falls back to print-only silently.
function Logger.log(msg)
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
    local f = ensure_open()
    if f then
        Logger.log("[PalBonds/Logger] live log started (crash-resistant, flushed per line) -> " .. LOG_PATH)
    else
        print("[PalBonds/Logger] could not open live log file at " .. LOG_PATH .. " — falling back to normal print only (still subject to UE4SS's own buffering)\n")
    end
end

return Logger
