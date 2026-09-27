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

    Logger.Init()

    pcall(function() require("Net").Init() end)

    pcall(function() require("HostView").Init() end)

    Indicator.Init()

    Personality.Init()
    Interaction.Init()
    Trust.Init()
    Combat.Init()

    pcall(Combat.StartShutdownWatch)
    pcall(Combat.StartTrainerReassertLoop)

    pcall(Combat.StartActionChangeProbe)

    Capture.Init()

    pcall(function() require("Menu").Init() end)

    print("[PalBonds] all modules initialized\n")
end

PalBonds.Init()

return PalBonds
