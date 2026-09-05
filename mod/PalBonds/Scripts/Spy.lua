--[[
    Spy.lua — temporary research tool, NOT a real subsystem (no DESIGN.md
    section of its own).

    Purpose: after a crash from guessing at raw PlayActionByType calls
    (see hook-points.md, 2026-09-01), Dragón suggested the much safer
    approach — capture a Pal normally, pet it through the game's OWN
    "4" action-wheel menu, and just WATCH what the game itself calls.

    This only registers read-only pre-hooks (RegisterHook). A pre-hook
    fires right before the real function runs and lets us log its
    arguments — it does NOT call anything itself and does NOT change
    game behavior, so this cannot cause the kind of crash the direct
    PlayActionByType experiment did. Safe to leave running.

    What's hooked and why:
      - UPalActionComponent:PlayActionByType — confirms whether the real
        "Pet" menu option actually goes through this function at all, and
        if so, with what target and what EPalActionType value (we assumed
        HumanPetting = 55 from the enum name, but the real menu might use
        a different type, a different function entirely, or call it on a
        different object than we guessed).
      - UPalIndividualCharacterParameter:AddFriendShip — confirms exactly
        how much friendship the vanilla interaction grants and when,
        settling whether Interaction.lua's own AddFriendShip call
        double-counts against it (still an open question, see Trust
        section of hook-points.md).

    Once we've seen a real "Pet" press on an owned Pal go through the
    log, delete/disable this file — it's diagnostic only, not part of the
    mod's real behavior, and hooking functions we don't need to modify
    just adds overhead.

    FIX (same day, second attempt): tried "PalActionComponent:PlayActionByType"
    (dropping the C++ "U" prefix) — still failed to attach. Checked how
    UE4SS's OWN bundled mods do it (CheatManagerEnablerMod, ConsoleEnablerMod,
    both call RegisterHook on "/Script/Engine.PlayerController:ClientRestart")
    — the real required format is the FULL path:
    "/Script/<ModuleName>.<ClassName>:<FunctionName>", not a bare
    "ClassName:FunctionName" shorthand. Fixed below to
    "/Script/Pal.PalActionComponent:PlayActionByType" and
    "/Script/Pal.PalIndividualCharacterParameter:AddFriendShip".
]]

local Spy = {}

local function safe_get(param)
    if param == nil then
        return nil
    end
    local ok, value = pcall(function() return param:get() end)
    if ok then
        return value
    end
    return nil
end

local function describe(obj)
    if obj == nil then
        return "nil"
    end
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok and name then
        return name
    end
    return tostring(obj)
end

function Spy.Init()
    print("[PalBonds/Spy] installing read-only watch hooks (no calls made, safe)\n")

    local okAction = pcall(function()
        RegisterHook("/Script/Pal.PalActionComponent:PlayActionByType", function(Context, ActionTarget, Type)
            local self = safe_get(Context)
            local target = safe_get(ActionTarget)
            local actionType = safe_get(Type)
            print(string.format(
                "[PalBonds/Spy] PlayActionByType called — component=%s target=%s type=%s\n",
                describe(self), describe(target), tostring(actionType)
            ))
        end)
    end)
    if not okAction then
        print("[PalBonds/Spy] could not hook /Script/Pal.PalActionComponent:PlayActionByType (name may need adjusting)\n")
    end

    local okFriend = pcall(function()
        RegisterHook("/Script/Pal.PalIndividualCharacterParameter:AddFriendShip", function(Context, Value, ApplyPassiveSkill)
            local self = safe_get(Context)
            local value = safe_get(Value)
            local applyPassive = safe_get(ApplyPassiveSkill)
            print(string.format(
                "[PalBonds/Spy] AddFriendShip called — param=%s value=%s applyPassiveSkill=%s\n",
                describe(self), tostring(value), tostring(applyPassive)
            ))
        end)
    end)
    if not okFriend then
        print("[PalBonds/Spy] could not hook /Script/Pal.PalIndividualCharacterParameter:AddFriendShip (name may need adjusting)\n")
    end
end

return Spy
