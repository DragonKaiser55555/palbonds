local Logger = require("Logger")
local Trust = require("Trust") 
local UEHelpers = require("UEHelpers") 
local Personality = require("Personality") 
local Indicator = {}
local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end
local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end
local function describe_widget(widget)
    if widget == nil then return "nil" end
    local ok, fullName = pcall(function() return widget:GetFullName() end)
    if ok and fullName then return fullName end
    return "[could not read GetFullName]"
end
local function describe_pal(pal)
    if pal == nil then return "nil" end
    local ok, fullName = pcall(function() return pal:GetFullName() end)
    if ok and fullName then return fullName end
    return "[could not read GetFullName]"
end

-- Forty-sixth pass: does the gauge class even get instantiated at all?
-- Periodic (not per-frame) existence scan, separate cap from the hook
-- diagnostics above.
local SCAN_INTERVAL_MS = 2000
local MAX_SCAN_LOGS = 25
local scanLogCount = 0
local hasLoggedScanAlive = false

-- Forty-seventh pass: full, unfiltered property dump of the real live
-- canvas instance, run exactly once. Same ForEachProperty/GetSuperStruct
-- technique already proven in Interaction.lua's dump_interesting_properties
-- (itself modeled on ConsoleCommandsMod/dump_object.lua), just unfiltered
-- and with extra ArrayProperty handling (length + element class names)
-- since the per-Pal gauge slots are very likely held in an array.
local MAX_PROPERTY_DUMP_LOGS = 700 
local propertyDumpLogCount = 0
local hasDumpedCanvas = false

-- Forty-eighth pass: once the real live canvas is found, keep a handle to
-- it so later scan ticks can check its panel children without having to
-- re-run FindAllOf/re-match the /Engine/Transient name every time.
local liveCanvasInstance = nil
local function property_dump_log(msg)
    if propertyDumpLogCount >= MAX_PROPERTY_DUMP_LOGS then return end
    propertyDumpLogCount = propertyDumpLogCount + 1
    Logger.log(msg)
    if propertyDumpLogCount == MAX_PROPERTY_DUMP_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-DUMP] reached the property-dump log cap (" .. MAX_PROPERTY_DUMP_LOGS .. ") — stopping here, this should already be enough to see the real field names")
    end
end
local function dump_all_properties(obj, label)
    local ok, err = pcall(function()
        if obj == nil or not obj:IsValid() then return end
        local class = obj:GetClass()
        local seen = {}
        while class ~= nil and class:IsValid() do
            local classNameOk, className = pcall(function() return class:GetFName():ToString() end)
            property_dump_log(string.format("[PalBonds/Indicator] [DIAG-DUMP] === %s (class %s) ===", label, classNameOk and className or "?"))
            class:ForEachProperty(function(prop)
                local propOk, propName = pcall(function() return prop:GetFName():ToString() end)
                if not (propOk and propName) or seen[propName] then return end
                seen[propName] = true
                local typeOk, typeName = pcall(function() return prop:GetClass():GetFName():ToString() end)
                typeName = typeOk and typeName or "?"
                local valueStr = "(not read)"
                local readOk, result = pcall(function()
                    if typeName == "BoolProperty" or typeName == "ByteProperty"
                        or typeName == "IntProperty" or typeName == "FloatProperty" then
                        return tostring(obj[propName])
                    elseif typeName == "NameProperty" then
                        local v = obj[propName]
                        return v and v:ToString()
                    elseif typeName == "StrProperty" then
                        local v = obj[propName]
                        return v and v:ToString()
                    elseif typeName == "EnumProperty" then
                        local v = obj[propName]
                        local enumOk, enumName = pcall(function() return prop:GetEnum():GetNameByValue(v):ToString() end)
                        return enumOk and string.format("%s(%s)", enumName, tostring(v)) or tostring(v)
                    elseif typeName == "ObjectProperty" then
                        local v = obj[propName]
                        if v == nil then return "nil" end
                        local vOk, vName = pcall(function() return v:GetFullName() end)
                        return vOk and vName or "[object, GetFullName failed]"
                    elseif typeName == "StructProperty" then
                        local v = obj[propName]
                        if v == nil then return "nil" end
                        local vOk, vName = pcall(function() return v:GetFullName() end)
                        return vOk and vName or "[struct]"
                    elseif typeName == "ArrayProperty" then
                        local v = obj[propName]
                        local numOk, num = pcall(function() return v:GetArrayNum() end)
                        num = numOk and num or -1
                        local innerOk, innerTypeName = pcall(function() return prop:GetInner():GetClass():GetFName():ToString() end)
                        local summary = string.format("array of %s, length=%d", innerOk and innerTypeName or "?", num)
                        if num > 0 and innerOk and innerTypeName == "ObjectProperty" then
                            local elementNames = {}
                            v:ForEach(function(index, elem)
                                if index <= 5 then
                                    local eOk, e = pcall(function() return elem:get() end)
                                    local eNameOk, eName = pcall(function() return e:GetFullName() end)
                                    elementNames[#elementNames + 1] = (eOk and eNameOk and eName) or "[unreadable]"
                                end
                            end)
                            summary = summary .. " — first elements: " .. table.concat(elementNames, " | ")
                        end
                        return summary
                    end
                    return nil
                end)
                if readOk and result ~= nil then valueStr = tostring(result) end
                property_dump_log(string.format("[PalBonds/Indicator] [DIAG-DUMP]   %s (%s) = %s", propName, typeName, valueStr))
            end)
            class = safe_call(function() return class:GetSuperStruct() end)
        end
    end)
    if not ok then
        Logger.log("[PalBonds/Indicator] [DIAG-DUMP] property dump failed (non-fatal, caught): " .. tostring(err))
    end
end

-- Forty-ninth pass: a WrapBox auto-flows its children into ONE shared
-- list layout — not a great structural fit for gauges that each need to
-- float independently above their own Pal's current screen position.
-- Canvas_Root (a CanvasPanel, whose children are each individually
-- positioned via their own CanvasPanelSlot) is structurally the better
-- fit for that job. The forty-eighth pass's own live test was also
-- inconclusive rather than a real negative: that whole session was only
-- ~95 seconds and the WrapBox never got a single child in that time — not
-- enough time to tell whether it's simply the wrong container or just
-- never got exercised. So this pass checks BOTH panel fields, using the
-- same real UPanelWidget:GetChildrenCount()/GetChildAt(Index), factored
-- into one function keyed by field name so either (or both) can be found
-- independently.
local MAX_PANEL_SCAN_LOGS = 60
local panelScanLogCount = 0
local panelState = {} 

-- Fiftieth pass fix: child[0] turning out to be the WrapBox itself (not a
-- Pal's gauge) is the exact failure mode this guards against — some
-- container classes are structural fixtures of the widget tree, always
-- present, not per-Pal content. Skip dumping these; the first child whose
-- class ISN'T one of these (and hasn't already been dumped) is almost
-- certainly real per-Pal (or per-entity) gauge content.
local KNOWN_CONTAINER_CLASSES = {
    WrapBox = true, CanvasPanel = true, HorizontalBox = true,
    VerticalBox = true, Overlay = true, ScrollBox = true,
    UniformGridPanel = true, GridPanel = true, SizeBox = true,
    Border = true, NamedSlot = true, WidgetSwitcher = true,
}
local dumpedClasses = {} 
local function panel_scan_log(msg)
    if panelScanLogCount >= MAX_PANEL_SCAN_LOGS then return end
    panelScanLogCount = panelScanLogCount + 1
    Logger.log(msg)
    if panelScanLogCount == MAX_PANEL_SCAN_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-PANEL] reached the panel-scan log cap (" .. MAX_PANEL_SCAN_LOGS .. ") — going quiet")
    end
end

-- Fifty-first pass: WBP_PalNPCHPGauge_C turned out to be real and alive
-- after all (see file header) — the exact class the old reference mod
-- used, just never individually header-dumped before. Two things worth
-- reading off it specifically, beyond the generic property dump:
--   1. Its `WBP_EnemyGauge` sub-widget (an ObjectProperty, real, seen in
--      the generic dump) — the old mod wrote text into
--      `WBP_EnemyGauge.Text_WorkName`. Dump ITS fields too, since the
--      generic per-class dump only ever looks at direct panel children,
--      never a child's own sub-widget fields.
--   2. Its `SyncId` field (StructProperty, real, confirmed type
--      `/Script/Pal.PalInstanceID` — this project's own already-answered
--      Q5, the stable per-Pal GUID). The generic dump can only print a
--      struct property's type name, not its actual field values (structs
--      have no GetFullName() identity the way UObjects do) — so this
--      tries indexing directly into the struct value for its real
--      sub-fields (`DebugName`, `InstanceId`, `PlayerUId`), the same way
--      this project has successfully read fields off other small
--      hook-argument structs before (e.g. FPalDamageResult.Defender).
local hasInspectedGaugeWidget = false

-- Fifty-ninth pass: DIAG-HANDLE confirmed the raw `bindedHandle`
-- property value (`handle:type()` = "TSoftObjectPtrUserdata") does not
-- support ANY of the accessors tried (GetFullName/LoadSynchronous/Get/
-- TryGetIndividualActor all FAILED, AssetPathName read nil) — a genuine
-- UE4SS Lua binding gap for this exact wrapped type, the same kind of
-- limitation already documented for MapProperty/DoubleProperty, not a
-- mistake in how it was called. Reading the STORED field after the fact
-- is a dead end with this build.
--
-- Real fix: `BindFromHandle(class UPalIndividualCharacterHandle*
-- targetHandle)` (confirmed real in the header dump, inherited from
-- `WBP_IndividualParameterBindWidget_C`) takes the handle as a plain HARD
-- pointer PARAMETER — a completely different, and much friendlier, shape
-- than the soft-pointer FIELD it presumably gets stored into afterward.
-- This project has always safely read hook arguments this way elsewhere
-- (Trust.lua/Interaction.lua's actor/param reads off hook params) — so
-- hooking this function directly and capturing `targetHandle` at the
-- moment of binding sidesteps the broken soft-pointer read entirely.
--
-- Registered ONCE (globally, keyed off whichever gauge widget's OWN class
-- path we happen to inspect first — `gaugeWidget:GetClass():GetPathName()`
-- gives the exact `/Game/...` Blueprint asset path this specific widget
-- class lives at, so the hook fires only for OUR gauge class, not every
-- individual-parameter-bound widget game-wide). Once registered, it
-- fires for every future BindFromHandle call on any WBP_PalNPCHPGauge_C
-- instance — including ones created after this point, which covers new
-- Pals encountered later in a session. Gauges that were already bound
-- BEFORE this hook was registered (the very first few found each
-- session) won't have a captured handle until their own widget gets
-- destroyed and recreated (which happens naturally as Pals leave/re-enter
-- view) — an acceptable gap, not worth a more invasive fix yet.
local hasRegisteredBindHook = false
local bindHookAttempts = 0
-- Two-hundred-and-ninety-seventh pass (2026-09-11): was 5 — five attempts for
-- an entire session, consumed one per gauge sighting. Once spent, personality
-- tags were dead until the game was restarted. An attempt is one pcall'd
-- RegisterHook and nothing else, and it stops for good on the first success, so
-- the budget bought nothing and cost the feature. Kept as a large finite number
-- rather than infinity purely so a genuinely impossible path cannot log forever;
-- the logging below is throttled separately.
local MAX_BIND_HOOK_ATTEMPTS = 2000
local gaugeHandleByKey = {} 

-- Sixty-second pass (2026-09-03): the sixty-first pass's hardcoded short
-- name ("WBP_IndividualParameterBindWidget_C:BindFromHandle") STILL failed
-- with the exact same "no UFunction with the specified name was found"
-- error, even though that's the function's real, confirmed declaring class
-- (from the header dump). That points at UE4SS's short-name RegisterHook
-- resolution simply not being reliable for Blueprint (/Game/...) classes at
-- all — unlike native /Script/ classes, which are globally unique and
-- exactly what short-name resolution is really meant for. The generally
-- correct, more reliable form for hooking a Blueprint function is the FULL
-- asset path (e.g. "/Game/.../WBP_IndividualParameterBindWidget.
-- WBP_IndividualParameterBindWidget_C:BindFromHandle"), which needs the
-- real UClass object's own `GetPathName()` — the exact call that failed
-- with "TrivialObject" when reached via `gaugeWidget:GetClass()`. The fix
-- isn't to give up on the full path, it's to reach the SAME class object a
-- different way: `FindAllOf("WidgetBlueprintGeneratedClass")` returns every
-- compiled Blueprint class as its own proper, fully-wrapped object (the
-- same kind of object this project's other `FindAllOf` calls already work
-- with fine) — a different route than `someInstance:GetClass()`, which
-- apparently hands back a more limited proxy in this Lua binding. Search
-- that list by name (`GetFName():ToString()`, proven reliable) for
-- "WBP_IndividualParameterBindWidget_C", then call `GetPathName()` on THAT
-- object instead. One-shot search, cached either way (found or not) so it
-- only runs once regardless of how many gauges are seen.
local hasSearchedBindWidgetClass = false
local bindWidgetClassPath = nil
local function find_bind_widget_class_path()
    if hasSearchedBindWidgetClass then return bindWidgetClassPath end
    hasSearchedBindWidgetClass = true
    local classes, classesErr = safe_call(function() return FindAllOf("WidgetBlueprintGeneratedClass") end)
    if not classes then
        Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] FindAllOf(WidgetBlueprintGeneratedClass) failed or returned nothing (caught, non-fatal): " .. tostring(classesErr) .. " -- will fall back to the hardcoded short class name")
        return nil
    end
    for _, cls in ipairs(classes) do
        local nameOk, name = pcall(function() return cls:GetFName():ToString() end)
        if nameOk and name == "WBP_IndividualParameterBindWidget_C" then
            local pathOk, path = pcall(function() return cls:GetPathName() end)
            if pathOk and path then
                bindWidgetClassPath = path
                Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] found the real class object via FindAllOf, full path = " .. path)
                return bindWidgetClassPath
            else
                Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] found the class object by name but GetPathName() still failed on it (caught, non-fatal): " .. tostring(path))
            end
        end
    end
    Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] scanned " .. #classes .. " WidgetBlueprintGeneratedClass instances, none matched WBP_IndividualParameterBindWidget_C by name")
    return nil
end

-- Sixty-first pass (2026-09-03): Dragón's test showed heavy, escalating lag
-- with the sixtieth pass's build, and the bar was still stuck at 50%. Two
-- separate problems, both explained by the log:
--
-- (1) THE REAL FIX: every single attempt failed with "Tried to register a
-- hook with Lua function 'RegisterHook' but no UFunction with the specified
-- name was found" for "WBP_PalNPCHPGauge_C:BindFromHandle". A fresh look at
-- `CXXHeaderDump/WBP_IndividualParameterBindWidget.hpp` explains why:
-- `BindFromHandle` is declared on `UWBP_IndividualParameterBindWidget_C`
-- (the parent class), NOT on `WBP_PalNPCHPGauge_C` (the runtime instance's
-- own class, which has no header dump of its own — it's Blueprint-only and
-- only inherits the function). UE4SS's short-name `RegisterHook` path
-- resolution apparently needs the function's DECLARING class, not any
-- subclass that merely inherits it. Fix: try the known, hardcoded declaring
-- class name "WBP_IndividualParameterBindWidget_C:BindFromHandle" FIRST —
-- this doesn't depend on reading anything off the live widget at all, so it
-- can't fail from a "TrivialObject" class-object read either.
--
-- (2) THE LAG: the sixtieth pass's retry-forever fix (removing the
-- premature `hasRegisteredBindHook = true`) was correct in isolation, but
-- with EVERY attempt doomed to keep failing on the wrong class name, this
-- function was calling `RegisterHook` (twice per call) on EVERY tick for
-- EVERY currently-visible gauge, forever, with no cooldown — and a failing
-- `RegisterHook` lookup is not a cheap no-op internally. That's almost
-- certainly the whole cause of the reported lag, worsening as more wild
-- Pals came into view (more gauges = more failing attempts per tick). Fix:
-- a hard cap (`MAX_BIND_HOOK_ATTEMPTS`) on total attempt ROUNDS across the
-- whole session — once exhausted without success, give up permanently and
-- say so clearly in the log, instead of retrying indefinitely.
-- Sixty-fifth pass (2026-09-03): Dragón asked for a real, thorough look at
-- ALL the reference mods, not just the ones already in the same format as
-- this project. Doing that surfaced the actual answer, sitting in this
-- project's own reference material since before pass one: the bundled
-- `VisiblePalCaptureCounter/Scripts/main.lua` (a working, shipped UE4SS Lua
-- mod, not a guess) hooks this EXACT function successfully, with this
-- EXACT literal path:
--   "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle"
-- The format for a BLUEPRINT class hook is `<content-browser package
-- path>.<ClassName>:<FunctionName>` — a `.` between the package and the
-- class, not the `/Script/Module.Class:Function` shape this project's own
-- NATIVE hooks correctly use elsewhere (Trust.lua/Interaction.lua), and
-- not a bare short class name either. Every previous attempt (60th-62nd
-- passes) was missing the real package path entirely, or trying to
-- rediscover it programmatically instead of just using the known-correct
-- literal string a working mod already demonstrates. Its handler
-- (`function (self, handler) local targetHandle = handler:get() ... end`)
-- also confirms `:get()` on the hook's handle argument is exactly right,
-- and that the resulting handle supports `TryGetIndividualParameter()`
-- directly — exactly this project's own plan, now with real proof it
-- works on a hook-captured handle (unlike the stored soft-pointer field).
--
-- Same source also hooks `Unbind` on the same class — worth adding too:
-- gauge widgets are apparently POOLED/reused across different Pals (not
-- one permanent widget per Pal), so an entry in `gaugeHandleByKey`/
-- `trackedBars` keyed only by widget identity could otherwise go stale
-- once a widget gets rebound to a different Pal. Clearing the captured
-- handle on Unbind keeps a reused widget from briefly showing its
-- previous Pal's trust value.
-- Hundred-and-fifty-fifth pass (2026-09-04): REAL FIX for a genuine race
-- Dragón caught directly — a wild Pal's gauge (a samurai dog he could
-- see and even pet, for the whole session) never got a real actor
-- resolved for its trust bar/personality label, staying on the "?"
-- placeholder the entire time. Traced it to `register_bind_hook_once`
-- below only ever being CALLED from gauge-DISCOVERY code (this file's
-- periodic canvas scan, `scheduleScan`/`check_panel_children`) — meaning
-- the class-level BindFromHandle hook (which, once registered, catches
-- EVERY future call across ALL gauge instances, not just one) doesn't
-- actually get registered until the FIRST gauge is ever discovered by
-- that scan. Any gauge already on-screen and already bound before that
-- exact moment — very plausibly a Pal already visible right as the
-- session starts — permanently misses capture, with zero further chance
-- to ever resolve (BindFromHandle only fires once per bind, and this
-- project has no mechanism to re-trigger it).
--
-- The fix doesn't need to wait for a live gauge at all: the FIRST
-- candidate path below is already a hardcoded, PROVEN-real literal
-- string (confirmed via a real bundled reference mod, see the big
-- comment on register_bind_hook_once) — it needs no gauge instance to
-- compute. Registering just that one candidate here, unconditionally, at
-- Indicator.Init() time (called before this file's own scan ever runs),
-- closes almost the entire race window. register_bind_hook_once's
-- gauge-dependent fallback candidates stay in place below as a safety
-- net for a future game build where this literal path might change —
-- `hasRegisteredBindHook` being already true after a successful call
-- here makes that later call a clean no-op, not a duplicate registration.
-- Hundred-and-fifty-seventh pass (2026-09-04) FIX, REAL REGRESSION FOUND:
-- Dragón's very next test showed this one-shot attempt FAILING outright
-- at Init() — "no UFunction with the specified name was found" — because
-- moving registration this early meant the target Blueprint class itself
-- isn't loaded into memory yet at that exact moment (the same "class not
-- loaded yet" problem this project has hit and fixed with a bounded
-- retry loop many times before — Radial Menu, Worker Menu, Indicator
-- classes, EMOTE-WATCH). With no retry, this silently fell back to
-- exactly the same race register_bind_hook_once already had — the
-- previous pass's fix accomplished nothing in that specific test.
-- Applying the same already-proven fix here instead of a single attempt:
-- a short, bounded retry (1s cadence, well before most gauges are likely
-- to bind, unlike register_bind_hook_once's path which only ever gets
-- its first chance once a gauge is actually discovered by the scan).
-- Fast rounds are for the rare case where the class IS already loaded; after
-- that it drops to the slow cadence and keeps going until it succeeds, because
-- the class normally only becomes hookable once the player is in-world (see
-- register_bind_hook_immediate's "NO GIVING UP" comment).
local IMMEDIATE_BIND_HOOK_MAX_ROUNDS = 30
local IMMEDIATE_BIND_HOOK_RETRY_MS = 1000
local IMMEDIATE_BIND_HOOK_SLOW_RETRY_MS = 5000
local function register_bind_hook_immediate(round)
    round = round or 1
    if hasRegisteredBindHook then return end
    local hookPath = "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle"
    local hookOk, hookErr = pcall(function()
        RegisterHook(hookPath, function(Context, TargetHandle)
            local self = hook_get(Context)
            local handle = hook_get(TargetHandle)
            if self == nil or handle == nil then return end
            gaugeHandleByKey[describe_widget(self)] = handle
        end)
    end)
    if hookOk then
        Logger.log(string.format("[PalBonds/Indicator] [TAGS] bind hook INSTALLED (immediate, round %d) — personality tags and trust bars can now resolve their Pal: %s", round, hookPath))
        hasRegisteredBindHook = true
        local unbindPath = hookPath:gsub(":BindFromHandle$", ":Unbind")
        local unbindOk, unbindErr = pcall(function()
            RegisterHook(unbindPath, function(Context)
                local self = hook_get(Context)
                if self == nil then return end
                gaugeHandleByKey[describe_widget(self)] = nil
            end)
        end)
        Logger.log("[PalBonds/Indicator] [TAGS] (immediate) RegisterHook(" .. unbindPath .. ") = " .. (unbindOk and "OK" or ("FAILED (non-fatal, BindFromHandle hook still stands): " .. tostring(unbindErr))))
        return
    end
    local errFirstLine = tostring(hookErr):match("^[^\n]*") or tostring(hookErr)

    -- ===============================================================
    -- NO GIVING UP (two-hundred-and-ninety-seventh pass, 2026-09-11)
    -- ===============================================================
    -- This used to stop dead after IMMEDIATE_BIND_HOOK_MAX_ROUNDS (30 rounds
    -- at 1s = a 30-second window opening at MOD LOAD) and hand over to the
    -- scan-triggered fallback, which had a budget of five attempts for the
    -- whole session. That is the cause of the intermittent "no personality
    -- tags" Dragón has been hitting and could never pin down.
    --
    -- Why the 30-second window was always wasted: the mod loads while the game
    -- is still on the title screen, and WBP_PalNPCHPGauge_C cannot be hooked
    -- until that Blueprint class is actually loaded, which does not happen
    -- until the player is in-world with a Pal on screen. His 2026-09-11 run
    -- shows it exactly — mod loaded 19:25:44, so this window expired around
    -- 19:26:14, and the first evidence of being in-world is 19:26:58, three
    -- quarters of a minute after the last attempt.
    --
    -- So in practice every session depended on those five fallback attempts
    -- landing in the narrow moment the class became registerable. When they
    -- missed, tags were gone until the game was restarted, because nothing
    -- ever tried again. Tags have no other route: the hook is what fills
    -- gaugeHandleByKey, and resolve_pal_actor_from_gauge's only other path is
    -- the bindedHandle field, recorded in the fifty-ninth pass as a dead end
    -- in this UE4SS build.
    --
    -- Now it simply keeps trying, slowing to SLOW_RETRY_MS once the fast
    -- rounds are used up, and stops permanently the moment it succeeds. The
    -- cost of a round is one pcall'd RegisterHook — no world scan, no
    -- reflection — which is why an open-ended retry is affordable here and was
    -- not for the cage-VFX probe that had to be removed.
    local isFast = round < IMMEDIATE_BIND_HOOK_MAX_ROUNDS
    local delay = isFast and IMMEDIATE_BIND_HOOK_RETRY_MS or IMMEDIATE_BIND_HOOK_SLOW_RETRY_MS

    -- Log the first failure, the handover to slow retries, and then only
    -- occasionally: this runs until it succeeds, so it must not grow the log
    -- without bound.
    if round == 1 or round == IMMEDIATE_BIND_HOOK_MAX_ROUNDS or (round % 60 == 0) then
        Logger.log(string.format(
            "[PalBonds/Indicator] [TAGS] bind hook not installable yet (round %d, %s cadence): %s — still retrying; personality tags and trust bars cannot appear until this succeeds",
            round, isFast and "fast" or "slow", errFirstLine))
    end
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(delay, function()
            safe_call(function() register_bind_hook_immediate(round + 1) end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Indicator] [TAGS] COULD NOT schedule a retry round — personality tags and trust bars will not appear this session. Stopped after round " .. round)
    end
end
local function register_bind_hook_once(gaugeWidget)
    if hasRegisteredBindHook then return end
    if bindHookAttempts >= MAX_BIND_HOOK_ATTEMPTS then return end
    bindHookAttempts = bindHookAttempts + 1
    local candidates = {

        -- Sixty-fifth pass: the real, confirmed-working literal path, tried first.
        "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle",
    }
    local fullClassPath = find_bind_widget_class_path()
    if fullClassPath then candidates[#candidates + 1] = fullClassPath .. ":BindFromHandle" end
    candidates[#candidates + 1] = "WBP_IndividualParameterBindWidget_C:BindFromHandle"
    local pathOk, classPath = pcall(function() return gaugeWidget:GetClass():GetPathName() end)
    local classNameOk, className = pcall(function() return gaugeWidget:GetClass():GetFName():ToString() end)
    if pathOk and classPath then candidates[#candidates + 1] = classPath .. ":BindFromHandle" end
    if classNameOk and className then candidates[#candidates + 1] = className .. ":BindFromHandle" end
    for _, hookPath in ipairs(candidates) do
        local hookOk, hookErr = pcall(function()
            RegisterHook(hookPath, function(Context, TargetHandle)
                local self = hook_get(Context)
                local handle = hook_get(TargetHandle)
                if self == nil or handle == nil then return end
                gaugeHandleByKey[describe_widget(self)] = handle
            end)
        end)
        -- Success is logged once and permanently visible; failures only on the
        -- first attempt, because this path retries now instead of giving up
        -- after five tries (two-hundred-and-ninety-seventh pass).
        if hookOk then
            Logger.log("[PalBonds/Indicator] [TAGS] bind hook INSTALLED (via gauge scan, attempt " .. tostring(bindHookAttempts) .. ") — personality tags and trust bars can now resolve their Pal: " .. hookPath)
        elseif bindHookAttempts == 1 then
            Logger.log("[PalBonds/Indicator] [TAGS] bind hook attempt failed on " .. hookPath .. ": " .. tostring(hookErr) .. " — will keep retrying as gauges appear")
        end
        if hookOk then
            hasRegisteredBindHook = true

            -- Also hook Unbind (same literal-path convention) so a reused
            -- gauge widget's stale captured handle gets cleared instead of
            -- briefly showing the wrong Pal's trust value.
            local unbindPath = hookPath:gsub(":BindFromHandle$", ":Unbind")
            local unbindOk, unbindErr = pcall(function()
                RegisterHook(unbindPath, function(Context)
                    local self = hook_get(Context)
                    if self == nil then return end
                    gaugeHandleByKey[describe_widget(self)] = nil
                end)
            end)
            Logger.log("[PalBonds/Indicator] [TAGS] RegisterHook(" .. unbindPath .. ") = " .. (unbindOk and "OK" or ("FAILED (non-fatal, BindFromHandle hook still stands): " .. tostring(unbindErr))))
            return
        end
    end
    if bindHookAttempts >= MAX_BIND_HOOK_ATTEMPTS then
        Logger.log("[PalBonds/Indicator] [TAGS] GAVE UP after " .. MAX_BIND_HOOK_ATTEMPTS .. " attempts — every candidate hook path failed every time, so personality tags and trust bars will not appear for the rest of this session. Reaching this at all means something structural changed in the gauge Blueprint; the class path is the first thing to re-check.")
    end
end

-- Seventy-first pass (2026-09-03): the seventieth pass's "fix" did NOT
-- fix it — Dragón's own console showed the exact same "TrivialObject"
-- error, just moved from a hook-Context object (sixty-second pass) to a
-- FindAllOf-returned instance: `instance:GetClass():GetPathName()` fails
-- identically either way. That's the THIRD distinct technique this
-- project has tried for getting a Blueprint class's real asset path from
-- Lua reflection — FindAllOf("WidgetBlueprintGeneratedClass"),
-- FindAllOf("BlueprintGeneratedClass"), and instance:GetClass() — and all
-- three are now confirmed dead in this UE4SS build, regardless of how the
-- class reference is obtained. Checked the web too (see
-- docs/hook-points.md) for a published literal path the way
-- BindFromHandle's and BP_OtomoPalHolderComponent's were found — nothing
-- surfaced for these two classes.
--
-- WORSE: the dead call was retrying every single 2s scan tick forever,
-- with its failure log NOT behind prism_log's cap — and with TWO live
-- BP_CapturePrism_C instances apparently existing at once (first/third
-- person view-model duplicates, most likely), that was 2 unthrottled,
-- flushed log lines roughly every 2 seconds, forever — real, ongoing spam
-- Dragón caught directly in the console. That regression is on me; it
-- should have been capped from the start.
--
-- Real fix: give up on RegisterHook for these two classes — there is no
-- known literal path, and every way to derive one from Lua reflection is
-- now exhausted. Pivot to the technique that's worked everywhere ELSE in
-- this project when no literal path is available: read fields directly
-- off the live instance FindAllOf already hands us. No path, no
-- RegisterHook, no :GetClass() call at all — just :IsValid(), a full-name
-- identity, and direct field reads, all of which have worked reliably
-- throughout this whole project. Logs a new instance's identity once
-- (existence/creation timing is itself useful — BP_CapturePrismBullet_C
-- in particular should only exist briefly, right around an actual throw)
-- and the bullet's CaptureTarget/isBound whenever they change, not every
-- tick.





local function inspect_gauge_widget(gaugeWidget)
    register_bind_hook_once(gaugeWidget)
end

-- Fifty-fifth pass (2026-09-03): the fifty-fourth pass's test came back
-- with every single logged step OK, and Dragón confirmed a real magenta
-- bar rendered on the one Chikipi tested — runtime widget creation is
-- CONFIRMED working in this build. Two real gaps in that first version,
-- exactly matching what Dragón observed:
--   1. It only ever ran once per session (a single global one-shot flag),
--      so only the very first gauge widget the scan ever saw got a bar —
--      Dragón correctly guessed this was the nearest wild Pal at spawn.
--      Fixed here: gating is now keyed per-gauge (by its own GetFullName,
--      which is unique to that specific live instance) via a small table,
--      so every distinct gauge widget gets its own bar exactly once,
--      instead of the whole feature running only once ever. Also moved
--      the call site out of inspect_gauge_widget (which stays its own,
--      separate one-shot deep-dump, to keep log volume down) and into
--      check_panel_children's own per-child loop, unconditionally, so it
--      runs for every gauge child seen, not just whichever one happened
--      to trigger the diagnostic dump.
--   2. Position (0,25) and size (80,6) were blind, arbitrary guesses
--      relative to Canvas_Innner's own coordinate space, made without
--      ever reading anything real to compare against — which is exactly
--      why Dragón saw it "not rightly aligned". Fixed here: read the
--      REAL HP bar's own slot (`WBP_EnemyGauge.ProgressBar_HP.Slot`,
--      inherited from UWidget, a UCanvasPanelSlot since ProgressBar_HP
--      lives in this same kind of canvas) via its own
--      GetPosition()/GetSize(), and place the new bar directly under it
--      (same X/width, Y offset by the real bar's own height + a small
--      gap) instead of a guessed absolute position. Falls back to the
--      old blind guess, clearly logged as a fallback, if any of that
--      read fails.
--
-- Still NOT wired to real FriendshipPoint yet — SetPercent(0.5) and the
-- magenta test color are both still static placeholders, deliberately
-- kept obvious/fake-looking rather than switched to a "real-looking"
-- color, so it stays visually clear this isn't live data yet. Dragón's
-- own observation that "it never moved, stayed at the same half-full
-- look" through the whole capture is the expected, correct behavior of
-- this version — nothing in this pass or the last one calls SetPercent
-- more than once. Wiring a live value needs the still-unresolved
-- gauge-to-Pal matching problem solved first (SyncId's GUIDs still read
-- all-zero; Dragón's own suggested `bindedHandle` lead is still unread) —
-- that's the next real blocker, not this pass's job.
--
-- FIFTY-FIFTH PASS RESULT (2026-09-03): every gauge got its own bar this
-- time (one DIAG-CREATE sequence per Pal in the log, all succeeding), so
-- the per-gauge fix worked. But the screenshot Dragon sent still showed
-- the bar shifted right and visibly WIDER than the real HP bar, not just
-- off vertically. See the FIFTY-SIXTH PASS comment inside
-- install_trust_bar below for the real cause and fix.
local barInstalledForGauge = {} 
local trackedBars = {} 
local function resolve_pal_actor_from_gauge(gaugeWidget)

    -- Fifty-ninth pass: try the hook-captured HARD handle first — see
    -- register_bind_hook_once's comment for why this is the real fix,
    -- now that DIAG-HANDLE confirmed the stored soft-pointer FIELD is a
    -- dead end in this UE4SS Lua build.
    local key = describe_widget(gaugeWidget)
    local hookedHandle = gaugeHandleByKey[key]
    if hookedHandle ~= nil then
        local validOk, valid = pcall(function() return hookedHandle:IsValid() end)
        if validOk and valid then
            local actorOk, actor = pcall(function() return hookedHandle:TryGetIndividualActor() end)
            if actorOk and actor ~= nil then
                local actorValidOk, actorValid = pcall(function() return actor:IsValid() end)
                if actorValidOk and actorValid then return actor, nil end
            end
        end
    end

    -- Fall back to the stored bindedHandle field, kept only as a
    -- diagnostic path — DIAG-HANDLE showed this route consistently fails
    -- in this build (the raw value has no working IsValid/GetFullName/
    -- LoadSynchronous/Get/TryGetIndividualActor/AssetPathName), so this
    -- almost never succeeds, but costs nothing to still try.
    local handleOk, handle = pcall(function() return gaugeWidget.bindedHandle end)
    if not (handleOk and handle ~= nil) then
        return nil, "no hooked handle yet, and bindedHandle unreadable: " .. tostring(handle)
    end

    -- Two-hundred-and-seventy-fourth pass (2026-09-08) — REMOVED, and it is the
    -- best crash suspect this project has had.
    --
    -- Dragon's crash log ends on this probe's own output: five DIAG-HANDLE lines
    -- reporting GetFullName FAILED, LoadSynchronous FAILED, Get FAILED,
    -- TryGetIndividualActor FAILED, AssetPathName nil -- and then the process
    -- died with an access violation. It ran, everything it tried failed, and the
    -- game fell over immediately after.
    --
    -- Its question was ANSWERED in the fifty-ninth pass, in this file's own
    -- words: the raw bindedHandle is a TSoftObjectPtrUserdata that "does not
    -- support ANY of the accessors tried ... a genuine UE4SS Lua binding gap".
    -- It has kept running once per session ever since, calling four accessors on
    -- an object it already knows it cannot touch, to re-learn a fact written
    -- down long ago.
    --
    -- pcall is no defence here, for the third time in this project: it catches
    -- Lua errors, not a native access violation inside the engine call. An
    -- unsupported binding poking at a wrapped pointer is exactly how you read
    -- from a bad address.
    --
    -- Not proven -- correlation and a plausible mechanism, not a confession. But
    -- it costs nothing to remove: no code reads its output, and the answer it
    -- produces is already in the comments above. The function stays defined and
    -- unbound, the same convention used for the other retired probes here.
    -- inspect_bindedHandle_shape(handle)

    local directOk, actor = pcall(function() return handle:TryGetIndividualActor() end)
    if directOk and actor ~= nil then
        local validOk, valid = pcall(function() return actor:IsValid() end)
        if validOk and valid then return actor, nil end
    end
    local loadOk, resolved = pcall(function() return handle:LoadSynchronous() end)
    if loadOk and resolved ~= nil then
        local actorOk2, actor2 = pcall(function() return resolved:TryGetIndividualActor() end)
        if actorOk2 and actor2 ~= nil then
            local validOk2, valid2 = pcall(function() return actor2:IsValid() end)
            if validOk2 and valid2 then return actor2, nil end
        end
    end
    return nil, "no hooked handle for this gauge yet (bound before the hook was registered), and the stored bindedHandle field doesn't resolve in this build — see DIAG-HANDLE log"
end

-- Reuses this project's own already-proven route to the friendship value
-- (Interaction.lua's get_individual_parameter: actor.CharacterParameterComponent
-- :GetIndividualParameter()), just starting from an actor resolved via the
-- gauge's bindedHandle instead of a targeted/interacted-with Pal.
local function get_friendship_ratio(actor)
    local paramOk, param = pcall(function()
        local comp = actor.CharacterParameterComponent
        if comp ~= nil and comp:IsValid() then
            return comp:GetIndividualParameter()
        end
        return nil
    end)
    if not (paramOk and param ~= nil and param:IsValid()) then
        return nil, "no readable CharacterParameterComponent/IndividualParameter"
    end
    local pointOk, point = pcall(function() return param:GetFriendshipPoint() end)
    if not (pointOk and point ~= nil) then
        return nil, "GetFriendshipPoint() failed"
    end

    -- Hundred-and-eighty-ninth pass (2026-09-05): Trust.GetBondingThreshold
    -- now returns nil on purpose for a Pal with no real interaction on
    -- record — Dragón's explicit ask, "dont use a fallback, just dont
    -- compute it at all." A nil here means literally nothing to show
    -- yet, so this returns 0 directly WITHOUT dividing by any default —
    -- no per-Pal level lookup, no fallback constant, nothing computed
    -- for the vast majority of Pals that are never actually interacted
    -- with.
    local capOk, cap = pcall(function() return Trust.GetBondingThreshold(actor) end)
    if not (capOk and cap ~= nil and cap > 0) then
        return 0, nil
    end
    local ratio = point / cap
    if ratio > 1 then ratio = 1 end
    if ratio < 0 then ratio = 0 end
    return ratio, nil
end

-- Sixty-sixth pass (2026-09-03): Dragón asked to stylize the trust bar,
-- specifically a color gradient from white-pinkish (empty) to red (full)
-- as trust rises — replacing both the magenta creation-time placeholder
-- and the never-updated fill color. `UProgressBar:SetFillColorAndOpacity`
-- is a real, already-used call (the magenta placeholder itself proves it
-- works); this just computes a real color instead of a fixed one. Kept as
-- a plain linear interpolation per channel (R/G/B), no extra libraries
-- needed. Real visual-styling options exposed to Lua turned out to be
-- narrow — `UProgressBar`'s own header dump (CXXHeaderDump/UMG.hpp) only
-- ===================================================================
-- PLAYER-FACING PERSONALITY NAMES (two-hundred-and-thirty-sixth pass, 2026-09-07)
-- ===================================================================
-- Until now the label printed this project's INTERNAL tier strings —
-- "notinterested", "warlike_anyway", "companion_combat". Fine for development,
-- unshippable. Dragón asked for player-friendly names and chose them himself;
-- these are his, with one substitution of mine he accepted (Feral).
--
-- The rolled personalities:
--   normal          -> Normal    (behaviour comes from the species, untouched)
--   friendly        -> Curious   (stops and looks at the player as he approaches)
--   escape          -> Timid     (runs away on approach)
--   notinterested   -> Aloof     (ignores the player; deliberately distinct from Normal)
--   warlike         -> Grumpy    (postures, rarely starts a fight)
--   warlike_anyway  -> Hostile   (always attacks the player)
--   kill_all        -> Feral     (attacks anything on sight)
--
-- Grumpy and Hostile stay SEPARATE, on Dragón's explicit call and for a reason
-- worth recording so nobody merges them later as a tidy-up: "while grumpy
-- doesnt attack inmediately, it can attack if it sees another pal of its same
-- species attacking, so kind of like they join - its an interesting
-- personality". It is a joiner, not a weaker hostile.
--
-- THE BONDING STATES OVERRIDE THE PERSONALITY, and are keyed off the bar
-- directly rather than off the disposition string. That is deliberate: a Pal
-- won over by bonding and a Pal that merely ROLLED the friendly tier both end up
-- with disposition == "friendly", so the string alone cannot tell them apart and
-- would show two different meanings under one name. The ratio can, exactly, and
-- the thresholds are the same ones the systems themselves use.
--
--   >= 20% of the bar -> "Friendly"   (the friendly-trigger fraction)
--   >= 50% of the bar -> "Bonding"    (the follow trigger)
--
-- No name for 100%, per Dragón: by then the Pal is already being captured.
local USE_PLAYER_FACING_PERSONALITY_NAMES = true
local PERSONALITY_DISPLAY_NAMES = {
    normal = "Normal",
    unknown = "Normal",
    friendly = "Curious",
    escape = "Timid",
    notinterested = "Aloof",
    warlike = "Grumpy",
    warlike_anyway = "Hostile",
    kill_all = "Feral",

    -- Reached only if the ratio lookup fails; the thresholds below normally
    -- catch this state first.
    companion_combat = "Bonding",
}
local BOND_LABEL_FRIENDLY_RATIO = 0.2
local BOND_LABEL_BONDING_RATIO = 0.5

-- ===================================================================
-- LABEL STYLING (two-hundred-and-thirty-seventh pass, 2026-09-07)
-- ===================================================================
-- Dragón's direction, after seeing it in game for the first time: "keep it
-- white, capitalize it, smaller and dimmer, but not next to the name, below the
-- friendship bar, more close and aligned to it, not with so much space around".
-- Explicitly NO colour coding — he considered it and said no.
--
-- The screenshot showed why it read as part of the Pal's NAME rather than as a
-- status: the text renders at the widget's default size, which is far larger
-- than the 14px slot it sits in, so it overflowed its box and floated well below
-- the bars with a lot of air around it.
--
-- Layout of the nameplate stack, so the numbers below are readable rather than
-- magic. refY/refH are the HP bar's own slot position and height:
--     HP bar      Y = refY                    height refH
--     trust bar   Y = refY + refH + 2         height 6      (ends at +refH+8)
--     label       Y = refY + refH + 9         height 12     (was +12, height 14)
-- One pixel under the trust bar instead of four, and the same X and width as the
-- bars so it lines up with them rather than with the name above.
--
-- Size and dimming are done with RenderScale and RenderOpacity rather than by
-- setting a font: FSlateFontInfo is a struct this project has no confirmed-safe
-- way to build from Lua, while these two are plain UWidget setters. Both are
-- pcall-guarded and the result is logged once, so if either turns out not to
-- exist on this build it shows up as a log line instead of an invisible no-op.
-- Measured from the DIAG-GEOM dump rather than estimated, using the real slot
-- numbers this build reports:
--     ProgressBar_HP   pos=(64, 26)  size=(120, 4)   -> bottom edge at 30
--     trust bar        pos=(64, 32)  size=(120, 6)   -> bottom edge at 38
--     personality      pos=(64, 39)  size=(120, 18)
-- So the SLOT was already sitting one pixel under the trust bar and the gap
-- Dragón is seeing is not slot spacing at all — it is the copied name font being
-- taller than the 18px box, so the glyphs render low inside it. Pulling the slot
-- up by 3 closes the visible gap without moving the box into the bar: at 36 the
-- slot top still sits below the HP bar and only overlaps the trust bar's last
-- two pixels, which the text does not occupy anyway.
local LABEL_GAP_BELOW_BAR = 6
local LABEL_HEIGHT = 18   

-- Two-hundred-and-thirty-eighth pass (2026-09-07). The previous attempt shrank
-- and faded the label with RenderScale/RenderOpacity, and Dragón's screenshot
-- shows why that was the wrong tool: "still looks off ... the text looks too
-- dim now, i asume you lowered the font-weight, raise it a bit or again, copy it
-- from the name lol". He is right about the cause even if not the mechanism —
-- RenderOpacity fades the whole widget, which reads as thin, washed-out text
-- rather than as smaller text, and RenderScale resamples the glyphs instead of
-- rendering them at a smaller size, which is what made it look soft.
--
-- His instruction is the better one and it is now what this does: COPY THE STYLE
-- FROM THE PAL'S OWN NAME. WBP_EnemyGauge_C exposes Text_Name (a
-- UBP_PalTextBlock_C — the exact same class our label already is, since the
-- label class is taken from Text_WorkName:GetClass()), so its Font,
-- ColorAndOpacity and shadow can be handed straight across as same-typed values.
-- No struct is built and no struct is mutated: the font is read from one widget
-- and passed to the other's SetFont, which is the safest possible form of this.
-- Deliberately NOT modifying the copied FSlateFontInfo's Size field — that
-- struct may well be a live reference to the name widget's own font, and
-- shrinking it could shrink the Pal's actual NAME.
--
-- RenderScale and RenderOpacity are explicitly reset to 1, both because the font
-- now carries the appearance and because leaving them would compound with it.
--
-- ALIGNMENT. Dragón also reported "it looks like if the name had an extra
-- padding or something that is not letting it align correctly with the
-- friendship bar". Rather than guess at an offset a third time, this dumps the
-- real slot geometry of Text_Name, ProgressBar_HP and our own label once per
-- session, so the next adjustment is made from measured numbers instead of from
-- looking at a screenshot.
local loggedLabelStyleOnce = false
local loggedLabelGeometryOnce = false
local function style_personality_label(labelObj, gaugeWidget)
    if labelObj == nil then return end

    -- Always neutralise the previous pass's render tricks, even if the font copy
    -- below fails — otherwise a failed copy would leave the label dim AND
    -- unstyled, which is worse than either.
    local scaleOk = pcall(function() labelObj:SetRenderScale({X = 1.0, Y = 1.0}) end)
    local opacityOk = pcall(function() labelObj:SetRenderOpacity(1.0) end)
    local nameText = nil
    pcall(function() nameText = gaugeWidget.WBP_EnemyGauge.Text_Name end)
    local nameValid = nameText ~= nil and pcall(function() return nameText:IsValid() end) and nameText:IsValid()
    local fontOk, colorOk, shadowOk, justifyOk = false, false, false, false
    if nameValid then
        fontOk = pcall(function() labelObj:SetFont(nameText.Font) end)
        colorOk = pcall(function() labelObj:SetColorAndOpacity(nameText.ColorAndOpacity) end)

        -- The name reads crisply against any background because it carries a
        -- shadow/outline. Without copying this the label would be the right size
        -- and weight but still hard to read over bright terrain.
        shadowOk = pcall(function() labelObj:SetShadowColorAndOpacity(nameText.ShadowColorAndOpacity) end)
        pcall(function() labelObj.ShadowOffset = nameText.ShadowOffset end)
        justifyOk = pcall(function() labelObj:SetJustification(nameText.Justification) end)
    end
    if not loggedLabelStyleOnce then
        loggedLabelStyleOnce = true
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-LABEL] copied style from Text_Name (logged once) — nameFound=%s font=%s color=%s shadow=%s justify=%s | render resets scale=%s opacity=%s",
            tostring(nameValid), tostring(fontOk), tostring(colorOk),
            tostring(shadowOk), tostring(justifyOk), tostring(scaleOk), tostring(opacityOk)
        ))
    end
end

-- One-shot, read-only. Prints where the name, the HP bar and our label actually
-- sit, so the alignment complaint can be answered with numbers.
local function dump_label_geometry(gaugeWidget, labelObj)
    if loggedLabelGeometryOnce then return end
    loggedLabelGeometryOnce = true
    local function slotOf(w)
        local sx, sy, sw, sh
        pcall(function()
            local sl = w.Slot
            local pos = sl:GetPosition()
            local size = sl:GetSize()
            sx, sy = pos.X, pos.Y
            sw, sh = size.X, size.Y
        end)
        return string.format("pos=(%s,%s) size=(%s,%s)", tostring(sx), tostring(sy), tostring(sw), tostring(sh))
    end
    pcall(function()
        local eg = gaugeWidget.WBP_EnemyGauge
        Logger.log("[PalBonds/Indicator] [DIAG-GEOM] Text_Name      " .. slotOf(eg.Text_Name))
        Logger.log("[PalBonds/Indicator] [DIAG-GEOM] ProgressBar_HP " .. slotOf(eg.ProgressBar_HP))
    end)
    if labelObj ~= nil then
        Logger.log("[PalBonds/Indicator] [DIAG-GEOM] personality    " .. slotOf(labelObj))
    end
end

-- Two-hundred-and-fortieth pass (2026-09-07): player-facing on/off switch for
-- the personality tags, bound to F9. Dragón's reasoning: the tags are a visible
-- change to every nameplate in the game and some players will not want them.
--
-- Implemented as an empty-string write rather than by destroying and rebuilding
-- the label widgets. Rebuilding is how this file caused a real crash before (the
-- Control-reuse bug), and an empty string is indistinguishable from no tag on
-- screen while leaving every widget in a known-good state. Flipping it back is
-- immediate because update_trust_bars rewrites the text on its next pass.
--
-- labelLastText is cleared on every Pal at toggle time so the "only write when
-- the text CHANGES" optimisation does not skip the very write that applies the
-- toggle.
local personalityLabelsVisible = true
function Indicator.TogglePersonalityLabels()
    personalityLabelsVisible = not personalityLabelsVisible
    for _, entry in pairs(trackedBars) do
        if type(entry) == "table" then entry.labelLastText = nil end
    end
    Logger.log("[PalBonds/Indicator] [TAG-TOGGLE] personality tags are now " ..
        (personalityLabelsVisible and "VISIBLE" or "HIDDEN") ..
        " (F9; session-only, resets to visible on the next launch)")

    -- Two-hundred-and-eighty-seventh pass: returned so the key handler can put
    -- the new state on screen. Both toggles are invisible otherwise -- with the
    -- tags hidden there is nothing left to look at, so without a toast the only
    -- feedback that F9 did anything is the thing it just removed.
    return personalityLabelsVisible
end

-- Two-hundred-and-forty-sixth pass (2026-09-07) — Dragón: "the label of the
-- pals both betrayed and abbandoned change to timid (which was the old escape)
-- that feels kind of weird considering what they just went through".
--
-- He is right, and it is misleading rather than merely odd. Losing all trust
-- forces the Pal's tier to "escape" so it genuinely flees, and "escape" displays
-- as Timid — the tag for a Pal that is naturally shy. A player reading it would
-- think they had found a skittish Chikipi, when what they are actually looking
-- at is a Pal that will never trust them again. The one state in this mod that
-- is permanent and irreversible was being shown under a word that suggests
-- nothing of the kind.
--
-- "Wary" is short enough to sit in the same tag space as the others and says
-- what it means: this one remembers.
-- Dragón's words, and his reasoning is the right one for a mod built on
-- earning trust: "wary sounds too soft from having been just betrayed, i would
-- put scarred for betrayed pals so players actually feel bad for what they did,
-- and abandoned or something for pals that got left behind".
--
-- The two causes are genuinely different things the player did, so they get
-- different words. Betrayal was an act; abandonment was a neglect.
local BROKEN_BOND_LABELS = {
    betrayed = "Scarred",
    abandoned = "Abandoned",
}

-- Used only if a bond ended without its cause being recorded — older saves, or
-- any future path that forgets to pass a reason. Deliberately not one of the two
-- real words: a Pal should never be labelled "Scarred" unless the player
-- actually hurt it.
local BROKEN_BOND_FALLBACK = "Wary"
local function personality_display_text(actor, disposition)
    if not personalityLabelsVisible then return "" end

    -- Checked before anything else, including the bonding thresholds. A
    -- permanently fled Pal has had its friendship reset to zero, so the ratio
    -- tests below would fall through to its personality tag and hide the one
    -- fact that actually matters about it.
    local okCap, CaptureMod = pcall(require, "Capture")
    if okCap and CaptureMod and CaptureMod.HasPermanentlyFled then
        if safe_call(function() return CaptureMod.HasPermanentlyFled(actor) end) then
            local why = CaptureMod.GetFledReason and safe_call(function() return CaptureMod.GetFledReason(actor) end)
            return BROKEN_BOND_LABELS[why] or BROKEN_BOND_FALLBACK
        end
    end
    if not USE_PLAYER_FACING_PERSONALITY_NAMES then
        return disposition or "?"
    end

    -- Bonding progress wins over the rolled personality: once a Pal is being
    -- won over, what it started as stops being the useful thing to show.
    local ratio = get_friendship_ratio(actor)
    if ratio ~= nil then
        if ratio >= BOND_LABEL_BONDING_RATIO then return "Bonding" end
        if ratio >= BOND_LABEL_FRIENDLY_RATIO then return "Friendly" end
    end
    if disposition == nil then return "?" end

    -- An unmapped disposition falls back to the raw string rather than to a
    -- wrong name: if a tier is ever added and this table is not updated, it
    -- should look obviously unfinished instead of silently mislabelling a Pal.
    return PERSONALITY_DISPLAY_NAMES[disposition] or disposition
end

-- exposes `SetPercent`, `SetIsMarquee`, and `SetFillColorAndOpacity` as
-- callable functions; the brush/border imagery live inside `WidgetStyle`
-- (an `FProgressBarStyle` struct holding `FSlateBrush` images), which
-- isn't something safe to construct from scratch via Lua — so the color
-- gradient is the real, deliverable piece of "more design" available
-- here without risking a broken/invisible bar.
-- Sixty-ninth pass (2026-09-03): Dragón tested the white-pink -> red
-- gradient live and it "didn't convince at all" — not readable/distinct
-- enough in practice. First follow-up: a bronze->gold gradient instead.
--
-- Seventy-second pass (2026-09-03): Dragón liked the gold better but
-- asked to drop the gradient entirely — one flat, solid gold color,
-- regardless of ratio. `ratio` is kept as a parameter (harmless, ignored)
-- rather than changing every call site, since the fill LENGTH already
-- shows progress via SetPercent; the color no longer needs to.
local function compute_trust_bar_color(ratio)
    return { R = 1.00, G = 0.84, B = 0.00, A = 1 }
end

-- Hundred-and-eightieth pass (2026-09-05): Dragón asked to try the
-- technique found while reading the "Pal Analyzer" reference mod's
-- extracted Blueprint strings — it keeps its own Pal-actor-keyed map
-- (Map_Add/Map_Find/Map_Keys/Map_Values, confirmed in its strings) and
-- reuses one widget per Pal, rather than rebuilding whenever the
-- underlying gauge changes. A real log breakdown (previous pass) showed
-- 315 full StaticConstructObject+AddChildToCanvas builds in a 3-minute
-- busy-base session — far more than the number of actually-distinct
-- Pals near a base, confirming the game's own gauge-widget pool
-- genuinely recycles/rebinds the SAME small set of widgets across
-- DIFFERENT Pals over time (matches the sixty-fifth pass's own finding,
-- "gauge widgets are apparently POOLED/reused"), and every single
-- recycle was paying full construction cost again even for a Pal this
-- mod was already tracking.
--
-- This moves an ALREADY-BUILT bar+label onto a NEW gauge widget's real
-- parent panel instead of building new ones — `UPanelWidget:RemoveChild`
-- confirmed real in this game's own UMG.hpp (same header this file
-- already trusts for AddChildToCanvas/GetChildrenCount/GetChildAt). The
-- widget OBJECTS themselves persist; only their panel membership and
-- position change, skipping StaticConstructObject/StaticFindObject/the
-- label-class lookup entirely. First attempt at moving an already-added
-- widget between different parent panels in this project — wrapped in
-- the same per-step pcall discipline as every other untested operation
-- here, with a full-construction fallback if any step fails.
-- Hundred-and-ninety-fourth pass (2026-09-05): an entry may now be
-- label-only (no bar built yet — see install_trust_bar, which builds the
-- personality label for every spawned Pal but the real trust bar only
-- once a real interaction exists). This used to require `entry.bar` to
-- already be valid just to reparent the LABEL, so a label-only entry
-- could never be reused across a gauge recycle — it would silently fall
-- through to full re-construction every time, building a duplicate label.
-- Now handles bar/label independently: moves whichever of the two
-- actually exists, and only fails outright if NEITHER does.
local function reparent_existing_bar(entry, newGaugeWidget)
    local hasBar = entry.bar ~= nil
    local barOk, barValid = true, true
    if hasBar then
        barOk, barValid = pcall(function() return entry.bar:IsValid() end)
    end
    if hasBar and not (barOk and barValid) then hasBar = false end
    local hasLabel = entry.label ~= nil
    local labelOk, labelValid = true, true
    if hasLabel then
        labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
    end
    if hasLabel and not (labelOk and labelValid) then hasLabel = false end
    if not hasBar and not hasLabel then return false end
    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = newGaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)
    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
    else
        local innerOk, innerCanvas = pcall(function() return newGaugeWidget.Canvas_Innner end)
        if innerOk and innerCanvas ~= nil and innerCanvas:IsValid() then
            targetPanel = innerCanvas
        else
            return false
        end
    end
    if hasBar then
        pcall(function()
            local oldParent = entry.bar.Slot and entry.bar.Slot.Parent
            if oldParent ~= nil and oldParent:IsValid() then
                oldParent:RemoveChild(entry.bar)
            end
        end)
        local addOk, newSlot = pcall(function() return targetPanel:AddChildToCanvas(entry.bar) end)
        if addOk and newSlot ~= nil and newSlot:IsValid() then
            local newY = (refY or 0) + (refH or 6) + 2
            pcall(function() newSlot:SetPosition({X = refX or 0, Y = newY}) end)
            pcall(function() newSlot:SetSize({X = refW or 80, Y = 6}) end)
        end
    end
    if hasLabel then
        pcall(function()
            local oldLabelParent = entry.label.Slot and entry.label.Slot.Parent
            if oldLabelParent ~= nil and oldLabelParent:IsValid() then
                oldLabelParent:RemoveChild(entry.label)
            end
        end)
        local labelAddOk, labelSlot = pcall(function() return targetPanel:AddChildToCanvas(entry.label) end)
        if labelAddOk and labelSlot ~= nil and labelSlot:IsValid() then
            pcall(function() labelSlot:SetPosition({X = refX or 0, Y = (refY or 0) + (refH or 6) + LABEL_GAP_BELOW_BAR}) end)
            pcall(function() labelSlot:SetSize({X = refW or 80, Y = LABEL_HEIGHT}) end)
            style_personality_label(entry.label, newGaugeWidget)
            dump_label_geometry(newGaugeWidget, entry.label)
        end
    end
    entry.gaugeWidget = newGaugeWidget
    entry.targetPanel = targetPanel
    return true
end

-- Hundred-and-ninety-fourth pass: upgrades an existing label-only entry
-- (a Pal that was seen and given its personality label, but had no real
-- interaction yet when it was first tracked) with a real trust/friendship
-- bar, the moment a real interaction actually happens. Mirrors
-- install_trust_bar's own bar-construction steps exactly, just callable
-- on an entry that already exists — used both right after a successful
-- reuse/reparent and from update_trust_bars's own per-tick loop, so the
-- bar appears the moment bonding starts, not only on the next gauge
-- recycle.
local function try_upgrade_entry_with_bar(entry)
    if entry.bar ~= nil then return end
    if entry.actor == nil or not Trust.HasBondingState(entry.actor) then return end
    local gaugeOk, gaugeValid = pcall(function() return entry.gaugeWidget:IsValid() end)
    if not (gaugeOk and gaugeValid) then return end
    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = entry.gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)
    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
    else
        local innerOk, innerCanvas = pcall(function() return entry.gaugeWidget.Canvas_Innner end)
        if innerOk and innerCanvas ~= nil and innerCanvas:IsValid() then
            targetPanel = innerCanvas
        else
            return
        end
    end
    local classOk, progressBarClass = pcall(function() return StaticFindObject("/Script/UMG.ProgressBar") end)
    if not (classOk and progressBarClass ~= nil and progressBarClass:IsValid()) then return end
    local constructOk, newBar = pcall(function()
        return StaticConstructObject(progressBarClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not (constructOk and newBar ~= nil and newBar:IsValid()) then return end
    pcall(function() newBar:SetPercent(0.0) end)
    pcall(function() newBar:SetFillColorAndOpacity(compute_trust_bar_color(0)) end)
    pcall(function() newBar:SetVisibility(0) end)
    local addOk, slot = pcall(function() return targetPanel:AddChildToCanvas(newBar) end)
    if not (addOk and slot ~= nil and slot:IsValid()) then return end
    if refOk then
        local newY = (refY or 0) + (refH or 6) + 2
        pcall(function() slot:SetPosition({X = refX or 0, Y = newY}) end)
        pcall(function() slot:SetSize({X = refW or 80, Y = 6}) end)
    else
        pcall(function() slot:SetPosition({X = 0, Y = 25}) end)
        pcall(function() slot:SetSize({X = 80, Y = 6}) end)
    end
    local ratio = get_friendship_ratio(entry.actor)
    if ratio then
        pcall(function() newBar:SetPercent(ratio) end)
        pcall(function() newBar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
    end
    entry.bar = newBar
    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] upgraded a label-only entry with a real trust bar (first interaction) for " .. describe_pal(entry.actor))
end
local function install_trust_bar(gaugeWidget)
    local key = describe_widget(gaugeWidget)
    if barInstalledForGauge[key] then return end

    -- Hundred-and-ninetieth pass (2026-09-05): Dragón's follow-up to the
    -- threshold-caching fixes — don't build a bar AT ALL for a Pal with
    -- no real interaction on record, not just skip the expensive
    -- level-multiplier part of it. Most Pals the game shows a native
    -- gauge for are never actually approached, so building (or even
    -- reusing) custom widgets for every one of them, refreshed every
    -- scan tick, is wasted work for the vast majority. `resolve_pal_actor_
    -- from_gauge` was ALREADY being called unconditionally here every
    -- scan tick before this pass (needed for the reuse-check below), so
    -- checking `Trust.HasBondingState` (a plain table lookup, no actor/
    -- component resolution of its own) on top of that adds no new real
    -- cost. Deliberately does NOT mark `barInstalledForGauge[key]` when
    -- skipping this way — the actor may not have resolved yet (a real,
    -- separate race, see below) or may simply not be interacted with
    -- YET — either way, this needs to keep re-checking on later scan
    -- ticks (cheap) rather than permanently giving up on this exact
    -- gauge widget.
    local earlyActor = resolve_pal_actor_from_gauge(gaugeWidget)
    if earlyActor == nil then
        return 
    end
    -- The widget itself rather than `true`, so scan_for_gauge_widgets can drop
    -- entries for destroyed gauges instead of keeping one per gauge ever seen.
    barInstalledForGauge[key] = gaugeWidget

    -- Hundred-and-ninety-fourth pass (2026-09-05): Dragón asked for the
    -- personality label back for EVERY spawned Pal — it's the one thing
    -- he wants visible from a distance without interacting at all — while
    -- keeping the hundred-and-ninetieth pass's lag fix intact for the
    -- real trust/friendship bar itself (that one still only makes sense,
    -- and only costs anything, once a Pal is actually being bonded with).
    -- `hasBonding` splits the rest of this function: the label always
    -- gets built below; the bar only when this is true.
    local hasBonding = Trust.HasBondingState(earlyActor)

    -- Hundred-and-eightieth pass: this exact Pal might already have a
    -- live tracked entry (label and/or bar, from a different, now-stale
    -- gauge widget the game already recycled away from) — reuse it via
    -- reparent_existing_bar instead of paying full construction cost
    -- again. Falls through to the normal build path below if reparenting
    -- itself fails for any reason.
    local earlyPalId = safe_call(Personality.GetStableId, earlyActor)
    if earlyPalId and trackedBars[earlyPalId] then
        local entry = trackedBars[earlyPalId]
        local reused = reparent_existing_bar(entry, gaugeWidget)
        if reused then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] REUSED existing widget(s) for already-tracked Pal " .. describe_pal(earlyActor) .. " on recycled gauge " .. key .. " (no new widgets built)")
            if hasBonding then
                try_upgrade_entry_with_bar(entry)
            end
            return
        end
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] reparent attempt failed for already-tracked Pal " .. describe_pal(earlyActor) .. " — falling back to full construction")
    end
    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] attempting to construct widget(s) for gauge: " .. key)

    -- Fifty-sixth pass: the fifty-fifth pass's numbers came back IDENTICAL
    -- across every single Pal (pos=64,26 size=120,4, every time) — that's
    -- correct and expected (it's the Blueprint's own static per-widget
    -- design-space layout, same for every instance of the same class,
    -- with the whole gauge's own screen position handled at a higher
    -- level). But Dragón's screenshot still showed the new bar shifted
    -- right AND noticeably wider than the real HP bar — not just off
    -- vertically. That's the signature of a COORDINATE-SPACE mismatch,
    -- not a wrong offset: the fifty-fifth pass added the new bar into
    -- `Canvas_Innner` (a guess) while reading position numbers that are
    -- only meaningful relative to whatever panel `ProgressBar_HP` ACTUALLY
    -- lives in — if that's a different panel than Canvas_Innner (nested
    -- canvases each have their own local coordinate space), the same raw
    -- numbers land somewhere else entirely.
    --
    -- Real fix: `UPanelSlot` has a real `Parent` field (UMG.hpp) pointing
    -- to the exact live UPanelWidget a widget is already a child of. Read
    -- `ProgressBar_HP.Slot.Parent` and add the new bar into THAT SAME
    -- panel object, instead of guessing Canvas_Innner — guaranteeing
    -- identical coordinate space, so the real bar's own position/size
    -- numbers apply directly with no translation needed. This is also
    -- what Dragón suggested independently ("copy the healthbar
    -- positioning" ) — same idea, just anchored to the real parent panel
    -- so the copy actually lands in the same space instead of a
    -- differently-scaled sibling.
    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)
    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-CREATE] using ProgressBar_HP's REAL parent panel (%s) — pos=(%s,%s) size=(%s,%s)",
            describe_widget(realParent), tostring(refX), tostring(refY), tostring(refW), tostring(refH)
        ))
    else
        local innerOk, innerCanvas = pcall(function() return gaugeWidget.Canvas_Innner end)
        if not (innerOk and innerCanvas ~= nil and innerCanvas:IsValid()) then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] neither ProgressBar_HP's real parent nor Canvas_Innner is readable — cannot proceed: " .. tostring(refX))
            return
        end
        targetPanel = innerCanvas
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] could not read ProgressBar_HP's real parent (caught, non-fatal) — falling back to Canvas_Innner as a guess: " .. tostring(refX))
    end

    -- ---------------------------------------------------------------------
    -- PERSONALITY LABEL (hundred-and-fiftieth pass, 2026-09-04; promoted
    -- from temporary debug text to a permanent, always-visible feature in
    -- the hundred-and-ninety-fourth pass, 2026-09-05, at Dragón's explicit
    -- request — this is the one thing he wants visible on every spawned
    -- Pal from a distance, without interacting at all, and he's floated
    -- eventually exposing it as a real user-facing on/off setting once
    -- the wording/styling gets a real polish pass). Built for EVERY
    -- spawned Pal now, unconditionally — NOT gated on `hasBonding` the way
    -- the real trust bar below is, since personality is rolled once per
    -- individual regardless of interaction history anyway.
    -- Reuses the exact same widget-construction technique already proven
    -- above for the trust bar itself (StaticFindObject the native UMG
    -- class, StaticConstructObject into the same real parent panel,
    -- AddChildToCanvas, position relative to the trust bar's own real
    -- coordinates) — the only new parts are the widget class (TextBlock
    -- instead of ProgressBar) and setting its text, both first attempts
    -- for this project, wrapped safely and logged honestly per this
    -- file's own established discipline (nothing in this file has ever
    -- worked on the very first try).
    -- Hundred-and-fifty-first/second passes (2026-09-04): this block
    -- caused a real crash on its first live test — root cause found via
    -- [CRASH-DIAG] before/after bracketing (a raw `.Text = string`
    -- property write into an FText field) and fixed by constructing the
    -- game's own real text-widget class (`BP_PalTextBlock_C`, pulled off
    -- an already-live `Text_WorkName` instance on this same gauge) and
    -- writing via the confirmed-safe `SetText_GDKInternal` method
    -- instead. Confirmed crash-free in Dragón's next real test.
    --
    -- Hundred-and-fifty-fourth pass (2026-09-04) FIX, REAL LAG FOUND:
    -- that same [CRASH-DIAG] bracketing was left in AFTER the crash was
    -- already found and fixed — Dragón felt real lag on the very next
    -- test, and the log showed why: [CRASH-DIAG] alone was 516 of 981
    -- Indicator lines in a 140-second session (over half), each one a
    -- forced synchronous disk write (Logger.lua's own crash-safety
    -- design). Exact same self-inflicted-logging lag shape this project
    -- has hit and fixed before (INDICATOR-WATCH, ninety-eighth pass) —
    -- diagnostic bracketing is meant to be temporary, trimmed once the
    -- specific bug it was hunting is confirmed fixed, not left running
    -- forever. Removed here; kept only the one line that reports the
    -- real outcome (OK/FAILED), matching every other one-shot creation
    -- log elsewhere in this function.
    local newLabel = nil
    local labelClassOk, labelClass = pcall(function() return gaugeWidget.WBP_EnemyGauge.Text_WorkName:GetClass() end)
    if labelClassOk and labelClass ~= nil and labelClass:IsValid() then
        local labelConstructOk, labelObj = pcall(function()
            return StaticConstructObject(labelClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
        end)
        if labelConstructOk and labelObj ~= nil and labelObj:IsValid() then
            local labelAddOk, labelSlot = pcall(function() return targetPanel:AddChildToCanvas(labelObj) end)
            if labelAddOk and labelSlot ~= nil and labelSlot:IsValid() then
                if refOk then
                    pcall(function() labelSlot:SetPosition({X = refX or 0, Y = (refY or 0) + (refH or 6) + LABEL_GAP_BELOW_BAR}) end)
                    pcall(function() labelSlot:SetSize({X = refW or 80, Y = LABEL_HEIGHT}) end)
                else
                    pcall(function() labelSlot:SetPosition({X = 0, Y = 32}) end)
                    pcall(function() labelSlot:SetSize({X = 80, Y = LABEL_HEIGHT}) end)
                end
                pcall(function() labelObj:SetVisibility(0) end)
                style_personality_label(labelObj, gaugeWidget)
                dump_label_geometry(gaugeWidget, labelObj)
                local setTextOk, setTextErr = pcall(function() labelObj:SetText_GDKInternal(true, "?") end)
                Logger.log("[PalBonds/Indicator] [DIAG-LABEL] personality label created and positioned — initial text write = " .. (setTextOk and "OK" or ("FAILED: " .. tostring(setTextErr))))
                newLabel = labelObj
            else
                Logger.log("[PalBonds/Indicator] [DIAG-LABEL] AddChildToCanvas FAILED for personality label: " .. tostring(labelSlot))
            end
        else
            Logger.log("[PalBonds/Indicator] [DIAG-LABEL] StaticConstructObject FAILED for personality label: " .. tostring(labelObj))
        end
    else
        Logger.log("[PalBonds/Indicator] [DIAG-LABEL] could not read Text_WorkName's real class FAILED: " .. tostring(labelClass))
    end

    -- Real trust/friendship bar — still gated on `hasBonding` (a real
    -- interaction on record), per the hundred-and-ninetieth pass's lag
    -- fix, which stays fully intact. Only built when that's true; a
    -- non-interacted Pal gets its label above and nothing else.
    local newBar = nil
    if hasBonding then
        local classOk, progressBarClass = pcall(function() return StaticFindObject("/Script/UMG.ProgressBar") end)
        if not (classOk and progressBarClass ~= nil and progressBarClass:IsValid()) then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] StaticFindObject('/Script/UMG.ProgressBar') failed: " .. tostring(progressBarClass))
        else
            local constructOk, barObj = pcall(function()
                return StaticConstructObject(progressBarClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
            end)
            if not (constructOk and barObj ~= nil and barObj:IsValid()) then
                Logger.log("[PalBonds/Indicator] [DIAG-CREATE] StaticConstructObject FAILED (caught, non-fatal): " .. tostring(barObj))
            else
                pcall(function() barObj:SetPercent(0.0) end)
                pcall(function() barObj:SetFillColorAndOpacity(compute_trust_bar_color(0)) end)
                pcall(function() barObj:SetVisibility(0) end)
                local addOk, slot = pcall(function() return targetPanel:AddChildToCanvas(barObj) end)
                if not (addOk and slot ~= nil and slot:IsValid()) then
                    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] AddChildToCanvas FAILED (caught, non-fatal) — bar exists but is not in the widget tree, so it cannot render: " .. tostring(slot))
                else
                    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] AddChildToCanvas SUCCEEDED — new bar is now a real child of the same panel ProgressBar_HP lives in")
                    if refOk then
                        local newY = (refY or 0) + (refH or 6) + 2
                        pcall(function() slot:SetPosition({X = refX or 0, Y = newY}) end)
                        pcall(function() slot:SetSize({X = refW or 80, Y = 6}) end)
                    else
                        pcall(function() slot:SetPosition({X = 0, Y = 25}) end)
                        pcall(function() slot:SetSize({X = 80, Y = 6}) end)
                    end
                    local ratio = get_friendship_ratio(earlyActor)
                    if ratio then
                        pcall(function() barObj:SetPercent(ratio) end)
                        pcall(function() barObj:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
                    end
                    Logger.log(string.format(
                        "[PalBonds/Indicator] [DIAG-TRUST] built real trust bar for %s — initial ratio=%s",
                        describe_pal(earlyActor), ratio and string.format("%.2f", ratio) or "unreadable"
                    ))
                    newBar = barObj
                end
            end
        end
    end

    -- Hundred-and-eightieth pass: store under the real Pal ID when
    -- already known at this point rather than the gauge's own temporary
    -- identity — that's what lets a LATER gauge recycle for this same
    -- Pal find and reuse this entry via reparent_existing_bar instead of
    -- building yet another one. Falls back to the gauge-widget key (old
    -- behavior) when the Pal still isn't resolvable yet; update_trust_bars
    -- promotes it to the real key once resolution succeeds on a later
    -- retry.
    local trackKey = earlyPalId or key
    trackedBars[trackKey] = { bar = newBar, gaugeWidget = gaugeWidget, actor = earlyActor, label = newLabel, palId = earlyPalId }
end

-- Fifty-seventh pass: periodic refresh for every installed bar — re-reads
-- the live FriendshipPoint and updates the bar's fill every scan tick, so
-- it actually moves as trust changes (petting, damage, passive gain,
-- capture) instead of staying frozen like the fifty-fourth/fifty-fifth
-- passes' static test value.
--
-- Fifty-ninth pass: also RETRIES actor resolution every tick for any
-- entry that hasn't resolved yet (see install_trust_bar's comment above
-- for why a single attempt at creation time isn't enough), so a gauge
-- whose BindFromHandle hook fires slightly after its bar was created
-- still ends up wired to real data instead of being stuck at the
-- placeholder for the rest of its life. Drops any entry whose bar or
-- gaugeWidget has gone invalid (Pal despawned/left range, or the gauge
-- widget itself was destroyed) rather than erroring on it.
local function update_trust_bars()

    -- Hundred-and-eightieth pass: promotions (moving an entry from its
    -- temporary gauge-widget key to its real Pal-ID key once resolution
    -- succeeds) are collected here and applied AFTER the loop below —
    -- Lua's `pairs()` doesn't allow inserting a NEW key into a table
    -- while traversing it (removing/nil-ing an EXISTING key, as already
    -- done below, is explicitly fine; adding one is not).
    local promotions = {}
    for key, entry in pairs(trackedBars) do

        -- Hundred-and-ninety-fourth pass: `entry.bar` can legitimately be
        -- nil now (a label-only entry for a Pal with no interaction yet)
        -- — that used to unconditionally fail this check and drop the
        -- WHOLE entry (including its personality label) every single
        -- tick, which would have made the "always show the label" feature
        -- impossible. Only require the bar to be valid when one exists.
        local hasBar = entry.bar ~= nil
        local barOk, barValid = true, true
        if hasBar then
            barOk, barValid = pcall(function() return entry.bar:IsValid() end)
        end
        local gaugeOk, gaugeValid = pcall(function() return entry.gaugeWidget:IsValid() end)
        if not gaugeValid or (hasBar and not (barOk and barValid)) then
            trackedBars[key] = nil
        else
            if entry.actor == nil then
                local actor = resolve_pal_actor_from_gauge(entry.gaugeWidget)
                if actor then
                    entry.actor = actor
                    Logger.log("[PalBonds/Indicator] [DIAG-TRUST] resolved a real Pal actor on a retry for a previously-unresolved gauge: " .. describe_pal(actor))

                    -- This entry may still be keyed by its gauge widget's
                    -- own temporary identity (Pal ID wasn't known yet at
                    -- creation). Now that it is, promote it to the real
                    -- Pal-ID key so a FUTURE gauge recycle for this same
                    -- Pal can find and reuse it (install_trust_bar's
                    -- early-reuse check) instead of building fresh again.
                    -- Skipped if this Pal already has a different tracked
                    -- entry (a rare duplicate — left as accepted, cosmetic
                    -- debt rather than merging/destroying widgets here).
                    if entry.palId == nil then
                        local palId = safe_call(Personality.GetStableId, actor)
                        if palId and palId ~= key and trackedBars[palId] == nil then
                            entry.palId = palId
                            promotions[#promotions + 1] = { oldKey = key, newKey = palId }
                        end
                    end
                end
            end
            if entry.actor ~= nil then
                local actorOk, actorValid = pcall(function() return entry.actor:IsValid() end)
                if not (actorOk and actorValid) then
                    entry.actor = nil 
                else

                    -- Hundred-and-ninety-fourth pass: a label-only entry
                    -- (no bar yet) gets checked here every tick — a cheap
                    -- Trust.HasBondingState table lookup inside
                    -- try_upgrade_entry_with_bar — for whether its Pal has
                    -- just had its first real interaction. If so, the real
                    -- trust bar gets built right then, next to the
                    -- personality label that was already showing, instead
                    -- of waiting for this exact gauge widget to recycle.
                    if entry.bar == nil then
                        try_upgrade_entry_with_bar(entry)
                    end
                    if entry.bar ~= nil then
                        local ratio = get_friendship_ratio(entry.actor)
                        if ratio then
                            pcall(function() entry.bar:SetPercent(ratio) end)
                            pcall(function() entry.bar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
                        end
                    end

                    -- TEMPORARY DEBUG FEATURE (hundred-and-fiftieth pass,
                    -- 2026-09-04) — see install_trust_bar's matching
                    -- comment above. Only writes when the text actually
                    -- CHANGES (labelLastText), not every tick — this runs
                    -- once per tracked bar per scan, same lag discipline
                    -- as everything else in this file, and a personality
                    -- disposition basically never changes after the
                    -- initial roll (Won-Over is the one exception), so
                    -- this should write once per Pal and then go quiet.
                    if entry.label then
                        local labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
                        if labelOk and labelValid then
                            local palId = safe_call(Personality.GetStableId, entry.actor)
                            local disposition = palId and Personality.GetDisposition(palId)
                            local text = personality_display_text(entry.actor, disposition)
                            if entry.labelLastText ~= text then
                                entry.labelLastText = text

                                -- Hundred-and-fifty-second pass FIX: same
                                -- crash-causing direct `.Text =` property
                                -- write as install_trust_bar's — switched
                                -- to the confirmed-real SetText_GDKInternal
                                -- method here too. Hundred-and-fifty-fourth
                                -- pass: dropped the [CRASH-DIAG] before/
                                -- after pair once the crash was confirmed
                                -- fixed — see install_trust_bar's matching
                                -- comment for the real lag numbers this
                                -- caused.
                                local setOk, setErr = pcall(function() entry.label:SetText_GDKInternal(true, text) end)
                                if not setOk then
                                    Logger.log("[PalBonds/Indicator] [DIAG-LABEL] text write FAILED for " .. describe_pal(entry.actor) .. ": " .. tostring(setErr))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, promotion in ipairs(promotions) do
        local entry = trackedBars[promotion.oldKey]
        if entry ~= nil then
            trackedBars[promotion.oldKey] = nil
            trackedBars[promotion.newKey] = entry
        end
    end
end
local function check_panel_children(fieldName)
    if liveCanvasInstance == nil or not liveCanvasInstance:IsValid() then return end
    local state = panelState[fieldName]
    if state == nil then
        state = { lastCount = nil, listedAtCount = nil, seenChildren = {} }
        panelState[fieldName] = state
    end
    local panelOk, panel = pcall(function() return liveCanvasInstance[fieldName] end)
    if not panelOk or panel == nil then
        panel_scan_log("[PalBonds/Indicator] [DIAG-PANEL] canvas." .. fieldName .. " is nil/unreadable — cannot enumerate children this way")
        return
    end
    local countOk, count = pcall(function() return panel:GetChildrenCount() end)
    if not countOk then
        panel_scan_log("[PalBonds/Indicator] [DIAG-PANEL] GetChildrenCount() failed on " .. fieldName .. ": " .. tostring(count))
        return
    end

    -- Hundred-and-ninety-second pass (2026-09-05): this used to log every
    -- time the native gauge pool's child count changed — useful while this
    -- project was still figuring out that pool's structure (pass 28-30),
    -- meaningless now that the structure is fully documented. In a busy
    -- area this count changes almost every scan tick, so it was pure log
    -- volume for a question closed long ago. Just track the count now,
    -- don't log it.
    if count ~= state.lastCount then
        state.lastCount = count
    end

    -- Fifty-eighth pass fix: Dragón reported that Pals seen after walking
    -- away from the spawn area got no bar at all. Root cause — this loop
    -- used to only run when `count` DIFFERED from the last count it was
    -- run at (`state.listedAtCount ~= count`). If a Pal leaves range at
    -- the same moment a new one enters, the total count can land back on
    -- a value already seen before (e.g. 5 -> 6 -> 5), so this guard would
    -- skip the loop entirely even though the actual SET of children
    -- changed — the new Pal's gauge would simply never get processed.
    -- Fix: always walk every child when count > 0, every tick — install_
    -- trust_bar/inspect_gauge_widget are already idempotent per-widget
    -- (barInstalledForGauge/hasInspectedGaugeWidget), so re-calling them
    -- on already-handled children is a cheap no-op. Only the VERBOSE
    -- per-child log line and the one-time-per-class property dump are
    -- still gated (via a `seenChildren` set keyed by full name) so this
    -- doesn't spam the log every 2s once a bunch of Pals are on screen.
    if count > 0 then
        state.listedAtCount = count
        for i = 0, count - 1 do
            local childOk, child = pcall(function() return panel:GetChildAt(i) end)
            if childOk and child ~= nil then
                local classOk, className = pcall(function() return child:GetClass():GetFName():ToString() end)
                className = classOk and className or "?"
                local fullName = describe_widget(child)
                if not state.seenChildren[fullName] then
                    state.seenChildren[fullName] = true

                    -- Hundred-and-ninety-second pass: this used to log an
                    -- identify line for every distinct gauge widget object
                    -- ever seen this session (fullName includes the
                    -- object's own address suffix, so a busy session sees
                    -- hundreds of these as the game's gauge pool churns).
                    -- The widget structure this was mapping out has been
                    -- fully documented since the fifty-first pass — kept
                    -- only the still-useful part below (dumping a
                    -- genuinely NEW, never-seen class).

                    -- Dump the first NEW, non-structural class we see. A
                    -- container class we already know about (WrapBox etc.)
                    -- gets skipped — those are fixed widget-tree fixtures,
                    -- not per-Pal content. Each real class is only dumped
                    -- once, even if it shows up under both WrapBox and
                    -- Canvas_Root.
                    --
                    -- Sixty-eighth pass: WBP_PalNPCHPGauge_C specifically
                    -- is now fully characterized (fifty-first pass) and
                    -- was re-dumping its whole inheritance chain every
                    -- single session for no reason — a real, measured
                    -- contributor to a 507-line/8-second log burst Dragón
                    -- felt as lag (see inspect_gauge_widget's comment).
                    -- Skip the known one with a one-line ack; still fully
                    -- dump anything genuinely new (e.g. a boss/NPC gauge
                    -- class this project hasn't seen yet) — that case
                    -- still has real diagnostic value.
                    if classOk and not KNOWN_CONTAINER_CLASSES[className] and not dumpedClasses[className] then
                        dumpedClasses[className] = true
                        if className == "WBP_PalNPCHPGauge_C" then
                            Logger.log("[PalBonds/Indicator] [DIAG-PANEL] known class WBP_PalNPCHPGauge_C seen (already fully characterized, fifty-first pass) — skipping the full dump")
                        else
                            Logger.log("[PalBonds/Indicator] [DIAG-PANEL] new non-container class found: " .. className .. " — dumping its fields")
                            dump_all_properties(child, className)
                        end
                    end
                end

                -- Fifty-first pass: regardless of the logging above,
                -- specifically inspect/install a bar on EVERY real gauge
                -- widget seen, EVERY tick — both functions are internally
                -- idempotent (per-widget), so this is what actually
                -- guarantees a Pal that appears after the count has
                -- already cycled back to a "seen" value still gets its
                -- bar (the fifty-eighth pass's fix).
                if classOk and className == "WBP_PalNPCHPGauge_C" then
                    inspect_gauge_widget(child)
                    install_trust_bar(child)
                end
            else
                if not state.seenChildren["unreadable:" .. tostring(i)] then
                    state.seenChildren["unreadable:" .. tostring(i)] = true
                    Logger.log(string.format("[PalBonds/Indicator] [DIAG-PANEL]   %s child[%d] unreadable: %s", fieldName, i, tostring(child)))
                end
            end
        end
    end
end
local function check_all_panels()
    check_panel_children("WrapBox")
    check_panel_children("Canvas_Root")
end

-- FIFTY-EIGHTH PASS RESULT + FIFTY-NINTH PASS (2026-09-03) — the real,
-- severe bug: Dragón's test came back WORSE than before ("pals ahead had
-- no bar at all", "the few bars I saw were still stuck at 50%"). The log
-- explains why, and it's a bug that's been latent since the forty-sixth
-- pass: this whole
-- function used to start with `if scanLogCount >= MAX_SCAN_LOGS then
-- return end`. That cap was written back when this function did nothing
-- but a lightweight existence-scan diagnostic — reasonable to go quiet
-- after MAX_SCAN_LOGS (25) lines. But `canvasCount > 0` is true on EVERY
-- tick forever once the canvas is found (it's a single, always-present
-- live instance), so the `if gaugeCount > 0 or canvasCount > 0` branch
-- unconditionally increments `scanLogCount` by at least 1 EVERY tick —
-- meaning `scanLogCount` reaches 25 after ~25 ticks of the 2-second scan
-- interval, i.e. about 50 SECONDS into every single session. Once that
-- happens, the early `return` at the top skips the ENTIRE rest of the
-- function forever — including `check_all_panels()` (all bar creation)
-- and `update_trust_bars()` (all live refresh), which by this pass now
-- live inside this same function even though the cap was never designed
-- with them in mind. This exactly matches what Dragón saw: a burst of
-- bars near spawn (before the ~50s mark), then nothing at all afterward,
-- for the rest of the session, no matter how far they walked or how many
-- Pals they pet.
--
-- Fix: the log-volume cap now ONLY throttles the verbose DIAG-SCAN print
-- lines (via a small helper, same shared-counter pattern as
-- panel_scan_log/property_dump_log elsewhere in this file) — it no
-- longer gates the function's actual work. FindAllOf, check_all_panels(),
-- and update_trust_bars() now run every tick unconditionally, for the
-- entire session.
local function scan_log(msg)
    if scanLogCount >= MAX_SCAN_LOGS then return end
    scanLogCount = scanLogCount + 1
    Logger.log(msg)
    if scanLogCount == MAX_SCAN_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-SCAN] reached the scan-log cap (" .. MAX_SCAN_LOGS .. ") — going quiet on DIAG-SCAN lines specifically; bar creation/refresh keep running regardless")
    end
end

-- probe_screen_projection removed in the two-hundred-and-eighty-ninth pass.
-- It projected a Pal's world position to screen space to test placing UI there.
-- The nameplate work went a different route entirely -- widgets are parented into
-- the game's own gauge, which needs no projection -- and the only call site had
-- already been commented out.

local GAUGE_FLAG_PRUNE_EVERY_N_SCANS = 30   -- ~60s at SCAN_INTERVAL_MS
local gaugeFlagScanCount = 0
local function scan_for_gauge_widgets()
    -- Every wild Pal that ever showed an HP gauge left an entry here for the
    -- whole session (2026-09-12 growth audit). Prune the destroyed ones.
    gaugeFlagScanCount = gaugeFlagScanCount + 1
    if gaugeFlagScanCount % GAUGE_FLAG_PRUNE_EVERY_N_SCANS == 0 then
        for k, w in pairs(barInstalledForGauge) do
            if type(w) ~= "userdata" and type(w) ~= "table"
                or not safe_call(function() return w:IsValid() end) then
                barInstalledForGauge[k] = nil
            end
        end
    end

    -- Two-hundred-and-seventy-second pass: this sweep touches live UI widgets,
    -- which are destroyed early in teardown. Stop as soon as the world is going.
    local okShut, CombatShut = pcall(require, "Combat")
    if okShut and CombatShut and CombatShut.IsShuttingDown and CombatShut.IsShuttingDown() then
        return
    end

    -- Two-hundred-and-seventy-first pass (2026-09-08) — Dragon went to take
    -- screenshots and found "a lot of pals didnt show their personality tags".
    --
    -- The cause is in the startup timing, and his own UE4SS log shows it: the
    -- mod loads at 00:00:43, but the WBP_PalNPCHPGauge:BindFromHandle hook --
    -- the thing that creates a label when a nameplate attaches to a Pal -- only
    -- registers at 00:01:38. That is fifty-five seconds, because the widget
    -- class is not loaded yet and the registration has to keep retrying until it
    -- is. Every nameplate that binds inside that window never gets a tag, and it
    -- never gets one later either, because nothing revisits an existing gauge.
    --
    -- That window is exactly when a player loads in and looks around, which is
    -- why it looks like "a lot" rather than "occasionally one".
    --
    -- This sweep closes it. install_trust_bar is idempotent per widget (it has
    -- been since the fifty-first pass, and the [DIAG-CREATE] "REUSED existing
    -- widget(s)" line is it declining to rebuild), so calling it on every live
    -- gauge every couple of seconds costs nothing for gauges that already have
    -- their label and fixes the ones that missed the hook.
    safe_call(function()
        local gauges = FindAllOf("WBP_PalNPCHPGauge_C")
        if gauges == nil then return end
        for _, g in ipairs(gauges) do
            if g ~= nil and safe_call(function() return g:IsValid() end) then
                safe_call(function() install_trust_bar(g) end)
            end
        end
    end)

    -- Two-hundred-and-eighty-eighth pass (2026-09-09) -- PERFORMANCE.
    --
    -- These two are FULL UObject-array walks, and this sweep runs every 2
    -- seconds for the whole session. Neither result reaches gameplay:
    -- gaugeInstances is used only to print [DIAG-SCAN] lines, and
    -- canvasInstances only to capture liveCanvasInstance, whose sole consumer
    -- is check_panel_children -- which also just logs. In a release build every
    -- one of those lines is discarded by Logger, so this was two array walks a
    -- second spent building strings nobody ever reads.
    --
    -- The third scan in this sweep, FindAllOf("WBP_PalNPCHPGauge_C") above, is
    -- load-bearing (it installs the trust bars) and is untouched.
    local diagnosticsOn = true
    do
        local okD, LoggerMod = pcall(require, "Logger")
        if okD and LoggerMod and LoggerMod.DiagnosticsEnabled then
            diagnosticsOn = LoggerMod.DiagnosticsEnabled()
        end
    end
    local gaugeInstances = diagnosticsOn and safe_call(function() return FindAllOf("PalUICharacterHPGaugeBase") end) or nil
    local canvasInstances = diagnosticsOn and safe_call(function() return FindAllOf("PalUINPCHPGaugeCanvasBase") end) or nil
    local gaugeCount = gaugeInstances and #gaugeInstances or 0
    local canvasCount = canvasInstances and #canvasInstances or 0
    if not hasLoggedScanAlive then
        hasLoggedScanAlive = true
        scan_log("[PalBonds/Indicator] [DIAG-SCAN] first scan ran (FindAllOf works) — real counts only get logged below once either class actually has a live instance")
    end
    if gaugeCount > 0 or canvasCount > 0 then
        scan_log(string.format(
            "[PalBonds/Indicator] [DIAG-SCAN] live instances — PalUICharacterHPGaugeBase=%d PalUINPCHPGaugeCanvasBase=%d",
            gaugeCount, canvasCount
        ))
        if gaugeInstances then
            for i, inst in ipairs(gaugeInstances) do
                if i > 5 then break end
                scan_log("[PalBonds/Indicator] [DIAG-SCAN]   gauge instance: " .. describe_widget(inst))
            end
        end
        if canvasInstances then
            for i, inst in ipairs(canvasInstances) do
                if i > 5 then break end
                scan_log("[PalBonds/Indicator] [DIAG-SCAN]   canvas instance: " .. describe_widget(inst))
            end

            -- Forty-seventh pass: the moment we see the REAL live instance
            -- (not the Blueprint archetype baked into the asset — that one's
            -- full name starts with /Game/..., the live one starts with
            -- /Engine/Transient), grab a handle to it — `liveCanvasInstance`
            -- is still load-bearing (check_all_panels below needs it).
            --
            -- Sixty-eighth pass: the actual field DUMP is not — its
            -- questions were fully answered back in the forty-seventh
            -- pass and it was just re-running every session for free,
            -- contributing real lines to the 507-line/8-second log burst
            -- Dragón felt as lag (see inspect_gauge_widget's comment for
            -- the full log evidence). Keep grabbing the handle; drop the
            -- dump.
            if not hasDumpedCanvas then
                for _, inst in ipairs(canvasInstances) do
                    local nameOk, fullName = pcall(function() return inst:GetFullName() end)
                    if nameOk and fullName and fullName:find("^WBP_PalNPCHPGaugeCanvas_C /Engine/Transient") then
                        hasDumpedCanvas = true
                        liveCanvasInstance = inst
                        Logger.log("[PalBonds/Indicator] [DIAG-SCAN] found the real live canvas instance (already fully characterized, forty-seventh pass — not re-dumping): " .. fullName)
                        break
                    end
                end
            end
        end
    end

    -- Forty-eighth pass: independent of the one-shot canvas dump above,
    -- keep checking the WrapBox's live children on every tick once we
    -- have a handle to the canvas. Fifty-ninth pass: this (and the line
    -- below) now run unconditionally every tick, no matter how much
    -- DIAG-SCAN logging has happened — see the big comment above.
    -- Reads live widget fields and calls GetChildrenCount purely to log the
    -- result, so it is skipped for the same reason as the scans above.
    if diagnosticsOn then check_all_panels() end

    -- Fifty-seventh pass: refresh every trust bar that resolved a real
    -- Pal actor, every tick, so they actually move.
    update_trust_bars()

    -- Two-hundred-and-thirty-seventh pass (2026-09-07) — REMOVED FROM THE
    -- TICK, and this is a real crash suspect, not just cleanup.
    --
    -- Dragón hit an EXCEPTION_ACCESS_VIOLATION reading address 0x338 (a null
    -- pointer plus a field offset) with UE4SS frames interleaved in the stack,
    -- on a game launched IMMEDIATELY after closing a previous session. This
    -- probe is the only place in the entire mod that calls engine screen-
    -- projection functions — ProjectWorldToScreen / ProjectWorldLocationToScreen
    -- — on a PlayerController, and by its own design it "keeps retrying each
    -- tick until one exists", which means it fires repeatedly during world load
    -- against a controller that may be half-constructed. That is exactly how a
    -- null-plus-offset read happens.
    --
    -- It also already threw this session: UE4SS.log carries a live stack
    -- traceback through ProjectWorldLocationToScreen at Indicator.lua:2261. That
    -- one was caught, but pcall only catches LUA errors — a native access
    -- violation inside the engine call takes the process down regardless of how
    -- many pcalls wrap it. So "it is guarded" was never protection here.
    --
    -- And it feeds nothing. Its only consumer is posmatch_log: it writes log
    -- lines and no code reads a projected coordinate anywhere. The labels are
    -- positioned from ProgressBar_HP's real parent panel, not from projection —
    -- that question was settled passes ago and this probe outlived it.
    --
    -- The function is left DEFINED but uncalled, matching what this file already
    -- does with poll_prism_class/poll_prism_bullet_state, so the research is
    -- preserved rather than deleted if a future pass wants to run it on demand.
    --
    -- Stated honestly: this is not proven to be the crash. There is no dump from
    -- that launch and the live log ends normally, because the crash happened
    -- before the mod's logger reopened the file. But it is the only null-deref
    -- vector this mod has against a loading player controller, it is known to
    -- have thrown, it matches the signature and the timing, and it has no
    -- reason to exist any more. Removing it costs nothing.
    -- probe_screen_projection()

    -- Two-hundred-and-sixth pass (2026-09-06) — poll_prism_state() REMOVED
    -- from this tick. It ran TWO full-world FindAllOf scans
    -- (BP_CapturePrism_C and BP_CapturePrismBullet_C) plus a GetFullName()
    -- reflection call per instance found, every 2 seconds, for the entire
    -- session — and BP_CapturePrism_C is the player's own held Palsphere
    -- weapon, so it reliably finds instances rather than usually returning
    -- nothing.
    --
    -- Its throttles only ever suppressed the log LINES (seenPrismInstances
    -- and prism_log's cap); the two world scans themselves ran every tick
    -- regardless, which is the part that actually costs anything. Same
    -- invisible-cost shape as the SetHPPercent hook removed at the bottom
    -- of this file.
    --
    -- The research it fed is closed: it was watching the sphere projectile
    -- to chase the capture light-beam VFX, and the hundred-and-ninety-third
    -- pass's dedicated test run settled that whole thread (the
    -- ABP_ReturnPalEffect_C candidate was ruled out against three real
    -- capture/rescue events). The VFX question itself is still open, but it
    -- needs a fresh candidate found via repak/FModel — not this poll, which
    -- never had a live consumer and produced nothing any code reads.
    -- poll_prism_class/poll_prism_bullet_state are left defined but
    -- uncalled, in case a future pass wants to run one on demand.
end

-- Same scheduling approach already proven in Trust.lua.
local function scheduleScan()
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(SCAN_INTERVAL_MS, function()
            safe_call(scan_for_gauge_widgets)
            scheduleScan()
        end)
    end)
    if not ok then
        pcall(function()
            LoopAsync(SCAN_INTERVAL_MS, function()
                local inGameThread = true
                pcall(function() inGameThread = IsInGameThread() end)
                if inGameThread then
                    safe_call(scan_for_gauge_widgets)
                end
                return false 
            end)
        end)
    end
end
function Indicator.Init()
    -- Five startup banner lines were removed here on 2026-09-11. They announced
    -- findings from passes 64-71 on every single launch, and one of them ended
    -- "See poll_prism_state" — a function deleted in the 2026-09-08 cleanup.
    -- A startup banner describing code that no longer exists is worse than no
    -- banner: the research it reported is settled and lives in docs/hook-points.md.

    -- Hundred-and-fifty-fifth pass (2026-09-04): register the class-level
    -- BindFromHandle/Unbind hooks HERE, first thing, rather than waiting
    -- for the periodic scan to discover a gauge widget — see
    -- register_bind_hook_immediate's own comment for the real race this
    -- closes (a Pal already on-screen at session start permanently
    -- missing capture otherwise).
    register_bind_hook_immediate()

    -- Two-hundred-and-sixth pass (2026-09-06) — REMOVED, REAL LAG SOURCE.
    -- Two read-only diagnostic hooks used to live here, on
    -- PalUICharacterHPGaugeBase's SetTargetCharacter and SetHPPercent.
    -- They existed only to learn the native gauge widget's structure — a
    -- question closed back in the fifty-first pass — but were never taken
    -- back out.
    --
    -- Why they were a genuine, invisible performance cost rather than just
    -- log noise: SetHPPercent is called by the game every time ANY visible
    -- Pal's HP gauge updates its fill, continuously, for every gauge on
    -- screen at once. Every one of those calls crossed into Lua and ran
    -- `describe_widget(widget)` — a real GetFullName() reflection
    -- round-trip — plus a string.format, BEFORE `diagnostic_log` ever got
    -- the chance to discard the result. `diagnostic_log`'s
    -- MAX_DIAGNOSTIC_LOGS cap only silenced the OUTPUT: because Lua
    -- evaluates call arguments before the call, the reflection and string
    -- work still happened on every single call for the entire session,
    -- long after the log itself went quiet. That made this cost invisible
    -- in the log (only 20 lines ever appear) while scaling directly with
    -- how many Pals are on screen — matching the "worse when entering a
    -- new area" shape of the lag Dragón has been reporting.
    -- SetTargetCharacter had the identical shape, with two describes per
    -- call instead of one.
    --
    -- Nothing reads these lines any more and no live feature depends on
    -- them, so they are removed outright rather than throttled. The real
    -- gauge work this module actually needs (finding gauges to attach the
    -- trust bar/personality label to) runs from scheduleScan() below and
    -- the BindFromHandle hook above, both untouched.

    scheduleScan()
end
return Indicator
