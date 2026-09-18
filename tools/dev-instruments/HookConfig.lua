local HookConfig = {}

-- ===================================================================
-- HOOK GROUPS (three-hundred-and-thirtieth pass, 2026-09-17)
-- ===================================================================
-- Why this file exists: the world-change crash survived three real fixes, and
-- the third log proved our Lua does NOTHING during a quit any more (the
-- world-closing gate holds, the log is silent from the confirm to the crash).
-- What is left that is ours is the mere EXISTENCE of the hooks -- 23 of them,
-- ten inside UI blueprints that are loaded and unloaded with the world, and
-- UE4SS in this build cannot unregister a hook once registered.
--
-- So the next step is elimination, not another theory: run with groups of hooks
-- never registered at all and see which group the crash needs. Each run costs
-- Dragón a manual test, so the groups are chosen to split the suspects roughly
-- in half rather than one hook at a time.
--
-- OUTCOME (2026-09-17): the hooks were innocent. The same method, carried on
-- into behaviour, found the real cause -- F8 ran engine work off the game
-- thread (Interaction.lua, run_on_game_thread). This file stays because it
-- turned a blind hunt into a straight line, and it is the first tool to reach
-- for the next time something crashes only in game.
--
-- EVERY group ships as true. This file is a diagnostic instrument; a release
-- must have the whole mod armed. A disabled group logs itself once, so a log
-- can never be misread as "the feature is broken".
HookConfig.GROUPS = {
    -- Blueprint (script) hooks on UI classes that the game loads on demand.
    -- These are the prime suspects: they are the only hooks whose owning class
    -- is not loaded when the mod starts (they need 15-20 retry rounds), and the
    -- widgets themselves are created and destroyed with the world.
    nameplate = true,   -- WBP_PalNPCHPGauge: BindFromHandle + Unbind (tags and trust bars)
    boss      = true,   -- WBP_BossEnemyHPGauge: SetTargetCharacter (boss bars)
    radial    = true,   -- WBP_PlayerRadialMenu: the four Pet/Feed hooks
    workermenu = true,  -- WBP_WorkerRadialMenu_Overlay:OnSetup + the two HUD pushes
    quit      = true,   -- WBP_MenuESC: ConfirmReturnTitle + OnReturn2Title

    -- Native (/Script/Pal) hooks. Their classes exist for the whole session, so
    -- these are the less likely half.
    senses    = true,   -- PalAISensorComponent:SelectResponseBySenses
    itemslot  = true,   -- PalItemSlot:RequestUseToCharacter (feed decrement)
    otomo     = true,   -- PalOtomoHolderComponentBase:TryGetSpawnedOtomo (pet substitution)
    damage    = true,   -- PalDamageReactionComponent delegate + PalHate:DamageEvent
}

local logged = {}

-- True when this group's hooks should be registered. Callers check this BEFORE
-- calling RegisterHook, so a disabled group leaves no hook behind at all --
-- which is the whole point, since a registered hook cannot be taken back.
function HookConfig.Enabled(group)
    local on = HookConfig.GROUPS[group]
    if on == nil then return true end
    if not on and not logged[group] then
        logged[group] = true
        local ok, L = pcall(require, "Logger")
        if ok and L then
            L.log("[PalBonds/HookConfig] hook group '" .. tostring(group) ..
                "' is DISABLED for this run (crash bisect) — the features that depend on it will not work")
        end
    end
    return on == true
end

return HookConfig
