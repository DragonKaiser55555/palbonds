--[[
    PalBonds — entry point.

    Every module below does real gameplay work: Personality rewrites a wild
    Pal's AI response preset, Interaction drives the game's own Pet/Feed/Play
    actions on wild Pals, Trust runs the bonding economy, Combat handles
    following and combat assist, Capture performs a sphere-less capture, and
    Indicator draws the on-screen trust bar and personality tag.

    See CLAUDE.md for current state and DESIGN.md for the design. The
    pass-by-pass research history is in docs/hook-points.md.
]]

local Logger      = require("Logger")
local Personality = require("Personality")
local Interaction = require("Interaction")
local Trust       = require("Trust")
local Combat      = require("Combat")
local Capture     = require("Capture")
local Indicator   = require("Indicator")

local PalBonds = {}

function PalBonds.Init()
    print("[PalBonds] mod loading...\n")

    -- Logger first, so every module below can log through it. It writes its
    -- own file, flushed per line, so it survives a hard crash — UE4SS.log's
    -- buffered output does not.
    Logger.Init()

    -- Co-op (2026-09-21): the private line between the machine that owns the
    -- world and each guest. Two native hooks, registered at load like every
    -- /Script/ hook. Before the other modules, which add their handlers to it.
    pcall(function() require("Net").Init() end)
    -- Co-op stage 3: what a guest sees comes from the host's numbers.
    pcall(function() require("HostView").Init() end)

    -- Indicator before the rest: a wild Pal's health gauge can already be
    -- on-screen and bound before our class-level BindFromHandle hook
    -- registers, and a gauge missed that way stays on the "?" placeholder
    -- forever. Initialising early closes most of that race.
    Indicator.Init()

    Personality.Init()
    Interaction.Init()
    Trust.Init()
    Combat.Init()

    -- One global fast loop keeps the follow action's Trainer pointer
    -- populated; the follow action itself clears it, and a cleared Trainer is
    -- why following used to fail. Started once here rather than per Pal, and
    -- it returns immediately whenever no Pal is bonding, which is most of the
    -- time.
    pcall(Combat.StartShutdownWatch)
    pcall(Combat.StartTrainerReassertLoop)

    -- Diagnostic only (2026-09-12): logs every AI action change on bonded
    -- Pals, so the real sequence is visible instead of a 1.5s sample.
    -- Turn ACTION_CHANGE_PROBE off in Combat.lua before shipping.
    pcall(Combat.StartActionChangeProbe)

    Capture.Init()

    print("[PalBonds] all modules initialized\n")
end

-- UE4SS loads main.lua once per mod; run init immediately.
PalBonds.Init()

return PalBonds
