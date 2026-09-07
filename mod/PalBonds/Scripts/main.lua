--[[
    PalBonds — entry point

    Wires the subsystem modules together and does startup registration.
    See DESIGN.md for the overall plan and docs/hook-points.md for which
    real class/function names each module is still waiting on.

    STALE COMMENT CORRECTED (two-hundred-and-sixth pass, 2026-09-06). This
    header used to say "NOTHING in the required modules does real hooking
    yet — they're stubs." That stopped being true within days of being
    written and stayed here for months, which is exactly the kind of thing
    that makes a later session (or a different assistant) misjudge the
    project's real state.

    The truth: every module below does real hooking and real gameplay work.
    Personality rewrites a wild Pal's AI response preset, Interaction drives
    the game's own Pet/Feed/Play actions on wild Pals, Trust runs the real
    bonding economy, Capture performs a real sphere-less capture, and
    Indicator draws live on-screen UI. The only genuine research-only
    modules left are Spy and OtomoWatch, and neither is initialized.
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
                                            -- Two-hundred-and-sixth pass
                                            -- (2026-09-06): that IS now
                                            -- answered, and its own last
                                            -- four open threads were closed
                                            -- in the hundred-and-ninety-
                                            -- third pass — so per this
                                            -- comment's own instruction,
                                            -- OtomoWatch.Init() below is
                                            -- commented out. It installed
                                            -- ELEVEN hooks, two of them on
                                            -- genuinely hot functions the
                                            -- game calls constantly:
                                            -- PalAISensorComponent:
                                            -- SelectResponseBySenses (every
                                            -- Pal's AI sense decision —
                                            -- ALSO hooked by Personality.lua
                                            -- for real enforcement, so this
                                            -- was a duplicate hook on the
                                            -- same hot function) and
                                            -- PalBattleManager:
                                            -- TargetIsPlayerOrPlayersOtomoPal
                                            -- (every combat targeting
                                            -- evaluation). Both logged
                                            -- unconditionally with
                                            -- reflection describes. Plus a
                                            -- FindAllOf class-existence poll
                                            -- every 10s whose own comment
                                            -- admits "no further use planned
                                            -- for it right now".
                                            -- require() left in place
                                            -- (harmless, does nothing unless
                                            -- .Init() is called).
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
                                          -- MENU-WATCH lines.
                                          -- Hundred-and-seventy-eighth pass
                                          -- (2026-09-05): the radial-menu
                                          -- question this was built for is
                                          -- long closed (WORKER-WATCH/
                                          -- RADIAL-WATCH mappings confirmed,
                                          -- the real wild-feed mechanism
                                          -- fully working since pass 173) —
                                          -- InputSpy.Init() below is now
                                          -- commented out per this file's
                                          -- own original removal plan. It
                                          -- was firing on every WASD/mouse
                                          -- press during ordinary movement,
                                          -- a real ongoing log-volume cost
                                          -- for a question that's already
                                          -- answered. require() left in
                                          -- place (harmless, does nothing
                                          -- unless .Init() is called).

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
    -- Two-hundred-and-thirty-second pass: one global fast loop that keeps the
    -- follow action's Trainer pointer populated. Started once, here, rather than
    -- per Pal or per event. It returns immediately whenever no Pal has a follow
    -- action installed, which is almost always.
    pcall(Combat.StartTrainerReassertLoop)
    Capture.Init()
    -- OtomoWatch.Init() -- DISABLED two-hundred-and-sixth pass (2026-09-06),
    -- see the require() note above. Same removal reasoning as InputSpy: it
    -- is pure research instrumentation (nothing in this mod ever calls into
    -- it — it exports Init() and nothing else), every question it was built
    -- to answer is closed, and two of its eleven hooks sit on genuinely hot
    -- game functions.
    -- InputSpy.Init() -- disabled hundred-and-seventy-eighth pass, see require() note above

    print("[PalBonds] all modules initialized\n")
end

-- UE4SS loads main.lua once per mod; run init immediately.
PalBonds.Init()

return PalBonds
