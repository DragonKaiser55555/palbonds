--[[
    PalBonds — entry point

    Wires the subsystem modules together and does startup registration.
    See DESIGN.md for the overall plan and docs/hook-points.md for which
    real class/function names each module is still waiting on.

    NOTHING in the required modules does real hooking yet — they're stubs
    that log their own startup so we have a fast "is this even loading"
    smoke test (Phase 0 in DESIGN.md) before any game-specific work begins.
]]

local Logger       = require("Logger")
local Personality = require("Personality")
local Interaction = require("Interaction")
local Trust        = require("Trust")
local Combat       = require("Combat")
local Capture      = require("Capture")
local Indicator    = require("Indicator") -- Forty-third pass (2026-09-03):
                                           -- on-screen trust-progress bar,
                                           -- see Indicator.lua header.
-- local Spy       = require("Spy") -- TEMPORARY research tool, see Spy.lua
                                     -- header. Disabled 2026-09-01: it did
                                     -- its job (see hook-points.md, "Spy.lua
                                     -- results") — real Pet/Feed calls
                                     -- AddFriendShip(10,true) then the
                                     -- target's own ActionComponent plays
                                     -- Happy(38) on itself. Re-enable (and
                                     -- call Spy.Init() below) if we need to
                                     -- watch again, e.g. to find the
                                     -- player-side animation trigger.
local OtomoWatch   = require("OtomoWatch") -- TEMPORARY research tool, see
                                            -- OtomoWatch.lua header.
                                            -- Twenty-second pass
                                            -- (2026-09-01): read-only watch
                                            -- on the real Otomo-holder API
                                            -- (AddOtomoHandleToFreeSlot /
                                            -- ActivatePalByHandle / etc.)
                                            -- to confirm, from real vanilla
                                            -- play, whether it's safe to
                                            -- try on a wild Pal. Disable
                                            -- once that's answered.
local InputSpy     = require("InputSpy") -- TEMPORARY research tool, see
                                          -- InputSpy.lua header. Seventy-
                                          -- fifth pass (2026-09-03): Dragón
                                          -- asked to be able to see which
                                          -- function/hook his own key-
                                          -- presses/clicks trigger, to help
                                          -- pin down the real radial-menu
                                          -- functions. Logs every key/mouse
                                          -- button press so it's visible
                                          -- next to the RADIAL-WATCH/
                                          -- MENU-WATCH lines. Disable
                                          -- (comment out this require and
                                          -- InputSpy.Init() below) once the
                                          -- radial-menu question is closed.

local PalBonds = {}

function PalBonds.Init()
    print("[PalBonds] mod loading...\n")

    -- First, so every module below can log through it. See Logger.lua —
    -- writes a separate, flushed-per-line log file that survives a hard
    -- crash, unlike UE4SS.log's own buffered output.
    Logger.Init()

    -- Hundred-and-fifty-fifth pass (2026-09-04): moved Indicator.Init()
    -- to run right after Logger, before every other module — closes most
    -- of a real race Dragón caught (a wild Pal's gauge already on-screen
    -- and bound before Indicator's class-level BindFromHandle hook
    -- registered permanently missed capture, staying on the "?"
    -- placeholder forever). Indicator.lua's own require("Personality")
    -- already returns the cached module table regardless of Init() call
    -- order (Lua's require caches at first load, not at Init time), and
    -- Indicator only actually CALLS into Personality from its own
    -- runtime update loop — well after every module's Init() has already
    -- run — so there's no real ordering dependency here, just less delay
    -- before this specific hook goes live.
    Indicator.Init()
    Personality.Init()
    Interaction.Init()
    Trust.Init()
    Combat.Init()
    Capture.Init()
    OtomoWatch.Init()
    InputSpy.Init()

    print("[PalBonds] all modules initialized (stub mode — no real hooks registered yet)\n")
end

-- UE4SS loads main.lua once per mod; run init immediately.
PalBonds.Init()

return PalBonds
