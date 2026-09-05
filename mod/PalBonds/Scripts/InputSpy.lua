--[[
    InputSpy.lua — TEMPORARY research tool

    Dragón asked (2026-09-03): "can you make it so you can check which
    function or which hook my keypresses trigger? or my clicks trigger?
    maybe that way we could find more if i interact with things while
    you're spying up."

    Checked first whether there's a clean native way to do this: no.
    Neither `Engine.hpp` nor `Pal.hpp` reflect a generic, event-style
    `InputKey`-shaped UFunction on `APlayerController`/`UPlayerInput` (only
    query functions like `IsInputKeyDown`/`WasInputKeyJustPressed` are
    exposed) — so there's nothing to `RegisterHook` that would fire once
    for literally every raw key/click the way a single well-known function
    name normally would.

    What IS available, and already proven safe in this exact project
    (F9/F10/CTRL+K), is `RegisterKeyBind`/`RegisterKeyBindAsync` — so this
    file just applies that SAME mechanism to every valid key name this
    UE4SS install accepts, each bound to one shared logging callback. The
    full name list below is transcribed directly from the bundled
    `Keybinds` mod's own comment block (`Mods/Keybinds/Scripts/main.lua`)
    — the authoritative list for this exact install, not guessed.

    This turns every real key press or mouse click into one timestamped,
    flushed log line, sitting in the SAME log file as every other
    `[RADIAL-WATCH]`/`[MENU-WATCH]`/etc. line this project already writes.
    Logger.lua writes each line synchronously and flushed in the order
    calls actually happen, so even though the displayed timestamp is only
    second-precision, simple adjacency in the file — "this key-pressed
    line appears right before/after these hook lines" — is enough to
    answer Dragón's question in practice. It's not a true automated
    correlator (there's no clean way to ask the engine "which handler
    consumed this specific event" from Lua), but it's the best available
    without deeper engine access.

    RISK ASSESSMENT — read before re-enabling after any doubt: binding
    ~150 keys (instead of the 3 specific, game-unused keys this project
    has bound before) is a new category — the first time this project
    registers a Lua-side listener on keys the game ITSELF actively uses
    for real gameplay (WASD, mouse buttons, etc). `RegisterKeyBind` is
    documented/understood to ADD a listener alongside the game's own input
    handling, not replace or consume it — so normal gameplay should be
    completely unaffected — but this specific "bind nearly everything"
    shape hasn't been tried by this project before. Watch closely the
    first time this runs for anything like movement/attack/interact keys
    feeling unresponsive, and disable this module immediately (comment out
    its `require`/`Init()` call in main.lua) if so. Every callback below
    is wrapped in `pcall` and does nothing but log a string — no game
    state is read or touched, so even a bad key name just fails to
    register rather than doing anything unsafe.

    Also capped (MAX_INPUT_LOGS), same discipline as every other capped
    logger in this project (see Indicator.lua's prism spy) — in case some
    key type turns out to fire every tick while held rather than once per
    press (not expected, but unconfirmed for every one of ~150 keys).

    THIS IS DIAGNOSTIC-ONLY. Not meant to ship — disable once it's done
    its job answering the radial-menu question, same as Spy.lua/
    OtomoWatch.lua before it.
]]

local Logger = require("Logger")

local InputSpy = {}

local MAX_INPUT_LOGS = 400
local inputLogCount = 0
local function input_log(msg)
    inputLogCount = inputLogCount + 1
    if inputLogCount > MAX_INPUT_LOGS then
        if inputLogCount == MAX_INPUT_LOGS + 1 then
            Logger.log("[PalBonds/InputSpy] hit the " .. MAX_INPUT_LOGS .. "-line cap — going quiet for the rest of this session (raise MAX_INPUT_LOGS in InputSpy.lua if you need more)")
        end
        return
    end
    Logger.log(msg)
end

-- Full valid key-name list, transcribed from the bundled Keybinds mod's
-- own comment block (Mods/Keybinds/Scripts/main.lua) — the authoritative
-- list of names UE4SS's `Key` table accepts for THIS install, not guessed.
local ALL_KEY_NAMES = {
    "LEFT_MOUSE_BUTTON", "RIGHT_MOUSE_BUTTON", "MIDDLE_MOUSE_BUTTON", "XBUTTON_ONE", "XBUTTON_TWO",
    "CANCEL", "BACKSPACE", "TAB", "CLEAR", "RETURN", "PAUSE", "CAPS_LOCK", "ESCAPE", "SPACE",
    "PAGE_UP", "PAGE_DOWN", "END", "HOME", "LEFT_ARROW", "UP_ARROW", "RIGHT_ARROW", "DOWN_ARROW",
    "SELECT", "PRINT", "EXECUTE", "PRINT_SCREEN", "INS", "DEL", "HELP",
    "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "LEFT_WIN", "RIGHT_WIN", "APPS", "SLEEP",
    "NUM_ZERO", "NUM_ONE", "NUM_TWO", "NUM_THREE", "NUM_FOUR",
    "NUM_FIVE", "NUM_SIX", "NUM_SEVEN", "NUM_EIGHT", "NUM_NINE",
    "MULTIPLY", "ADD", "SEPARATOR", "SUBTRACT", "DECIMAL", "DIVIDE",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24",
    "NUM_LOCK", "SCROLL_LOCK",
    "BROWSER_BACK", "BROWSER_FORWARD", "BROWSER_REFRESH", "BROWSER_STOP",
    "BROWSER_SEARCH", "BROWSER_FAVORITES", "BROWSER_HOME",
    "VOLUME_MUTE", "VOLUME_DOWN", "VOLUME_UP",
    "MEDIA_NEXT_TRACK", "MEDIA_PREV_TRACK", "MEDIA_STOP", "MEDIA_PLAY_PAUSE",
    "LAUNCH_MAIL", "LAUNCH_MEDIA_SELECT", "LAUNCH_APP1", "LAUNCH_APP2",
    "OEM_ONE", "OEM_PLUS", "OEM_COMMA", "OEM_MINUS", "OEM_PERIOD",
    "OEM_TWO", "OEM_THREE", "OEM_FOUR", "OEM_FIVE", "OEM_SIX", "OEM_SEVEN", "OEM_EIGHT", "OEM_102",
    "IME_PROCESS", "PACKET", "ATTN", "CRSEL", "EXSEL", "EREOF", "PLAY", "ZOOM", "PA1", "OEM_CLEAR",
    "SHIFT", "CONTROL", "ALT",
}

local hookedCount = 0
local skippedCount = 0

local function register_key_watch(name)
    local ok = pcall(function()
        local keyObj = Key[name]
        if keyObj == nil then
            error("Key." .. name .. " does not exist in this Key table", 0)
        end
        RegisterKeyBind(keyObj, function()
            input_log(string.format("[PalBonds/InputSpy] key/click pressed: %s", name))
        end)
    end)
    if ok then
        hookedCount = hookedCount + 1
    else
        skippedCount = skippedCount + 1
    end
end

function InputSpy.Init()
    Logger.log("[PalBonds/InputSpy] TEMPORARY research tool active — binding every known key/mouse button to a plain logger so real key/click input shows up in this log, right next to whatever hooks fire around the same moment. See file header for the full reasoning and the risk note before leaving this on long-term.")
    for _, name in ipairs(ALL_KEY_NAMES) do
        register_key_watch(name)
    end
    Logger.log(string.format(
        "[PalBonds/InputSpy] done — %d key binds registered, %d names skipped/failed to resolve (harmless, just means that name isn't valid in this Key table)",
        hookedCount, skippedCount
    ))
end

return InputSpy
