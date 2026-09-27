-- ===========================================================================
-- THE PALBONDS ENTRY IN THE GAME'S OWN PAUSE MENU (2026-09-25)
-- ===========================================================================
-- Dragón's ruling: "ideally we simply add it to the game menu the player
-- already knows and uses like the esc menu, and we simply add a new tab there
-- with the name palbonds mod or something like that". This is that entry, and
-- for now only that: a row named PalBonds at the bottom of the ESC menu's
-- button list that opens a page of our own. What the page eventually HOLDS is
-- a separate decision -- "first we need to see something visible for the
-- player ingame, no point in adding more values to the settings if we cant
-- even achieve the screen itself".
--
-- WHY THIS FILE IS SEPARATE AND WHY NOTHING ELSE CALLS INTO IT: everything
-- here touches the game's live UI, which is the most crash-prone thing this
-- project has ever done. Keeping it in one file with a single Init means it
-- can be dropped from a package without touching a line of the mod that works
-- today.
--
-- THE RULES BELOW ARE NOT STYLE CHOICES. Each one is a crash somebody already
-- paid for -- ours in Indicator.lua, DarnMenu's in the reference copy Dragón
-- put in the project (its author documented four separate CTDs in the exact
-- code this file replaces):
--
--   1. NEVER BUILD INSIDE THE CONSTRUCTION CALLBACK. NotifyOnNewObject fires
--      while the engine is still assembling the menu; mutating its layout
--      there is an access violation writing 0x80. We wait BUILD_DELAY_MS,
--      which is still inside the menu's open animation, so nothing pops in
--      late.
--   2. ONLY EVER ADD A CHILD TO A CanvasPanel. Adding to a VerticalBox
--      reflows the whole column on the engine's next layout pass -- after our
--      Lua has returned, so there is nothing to pcall. That is the crash that
--      killed DarnMenu three times out of three under ESC-spam, and it is why
--      our row is positioned ABOVE the "Return to Title" column on the shared
--      canvas rather than inserted into it.
--   3. NEVER RemoveFromParent ANYTHING ON A MENU WE NO LONGER OWN. A replaced
--      menu lingers and keeps painting; touching its children AVs. The engine
--      frees our widgets when it destroys the menu, so we simply forget them.
--   4. A RAW `.Text = "string"` WRITE CRASHES THIS GAME (our own crash,
--      2026-09-04, Indicator.lua). Text goes through the game's own
--      BP_PalTextBlock_C class and SetText_GDKInternal, the pair that fixed it.
--   5. BUILD THE PAGE ON THE FIRST CLICK, NEVER AHEAD OF TIME. Widget churn
--      inside an open menu is DarnMenu's crash family: pre-building its page
--      on every ESC open caused seven incidents before it was switched off.
--
-- SHARING THE SHELF: Canvas_Buttons is public space. Other menu mods (DarnMenu,
-- Better Mod Manager, AntiPhat) pin their own row above the same column and
-- compute the same spot we do, so whoever arrives second draws on top of the
-- first. We read what is already parked there and sit above it.
-- ===========================================================================

local Logger = require("Logger")
local Settings = require("Settings")

local Menu = {}

local MENU_CLASS   = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C"
local BUTTON_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC_Button_S"
local BUTTON_CLASS = BUTTON_ASSET .. ".WBP_MenuESC_Button_S_C"
-- The button blueprint's own click delegate. Verified present in this build's
-- object dump; the class is shared with every native ESC row, so this hook
-- fires for the game's buttons too and must ignore anything we did not create.
local CLICK_EVENT  = BUTTON_CLASS ..
    ":BndEvt__WBP_MenuESC_Button_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"
local WIDGET_LIB   = "/Script/UMG.Default__WidgetBlueprintLibrary"

-- Widget names on WBP_MenuESC, all confirmed in this build's object dump.
-- Canvas_Buttons holds the two button columns; VerticalBox_293 is the BOTTOM
-- one ("Return to Title"), which is where a mod row reads as native. The top
-- column (VerticalBox_148) is auto-sized and reports height 0, so anchoring
-- under it lands in the middle of the native rows.
local BUTTON_CANVAS  = "Canvas_Buttons"
local BOTTOM_COLUMN  = "VerticalBox_293"
local PAGE_ROOT      = "CanvasPanel_0"

-- WHAT THE PAGE HAS TO HIDE BEHIND ITSELF. The first version hid three of these
-- and the ESC menu's own TAB STRIP kept drawing over the top of our page, which
-- cut the title in half (Dragón, live test 2026-09-25). Everything the menu can
-- have on screen at once is listed, each one's own visibility is remembered
-- before it is hidden, and close puts back exactly what was there -- not a
-- guess, because which of these is visible depends on whether the world is
-- hosted, who is in it, and what tab the player last used.
local COVERED = {
    "Canvas_Buttons", "Canvas_Content", "Canvas_TabSet", "WorldOptionCanvas",
    "CanvasPanelPlayerList", "CanvasPanelServerInfo", "CanvasPanel_MultiTips",
}

-- The game's own settings row.
local OPTION_DIR = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/"
local ROW_CLASS = OPTION_DIR .. "WBP_OptionSettings_ListContent.WBP_OptionSettings_ListContent_C"
-- THE REBIND BUTTON IS THE ESC MENU'S OWN BUTTON, not the Options screen's
-- small one. The small one was tried first and its delegate fires on HOVER:
-- Dragón could not move the mouse across the screen without the row demanding a
-- new key ("the keys change works terribly, just by hovering the mouse forces
-- the player to change the key"). WBP_MenuESC_Button_S_C's delegate is the one
-- this file already proves is click-only -- it is what the entry, Save, Cancel
-- and Restore defaults all use.
-- The game's own panel frame, so the page is framed the way every other
-- Palworld panel is instead of being a flat rectangle of our own invention.
local WINDOW_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_PalCommonWindow.WBP_PalCommonWindow_C"
-- A live BP_PalTextBlock_C on this same menu: we take our text widgets' class
-- and styling from it instead of inventing either.
local TEXT_SOURCES   = { "BPPalTextBlock_WorldName", "Text_InviteCode" }

local ENTRY_LABEL  = "PalBonds"
local BUILD_DELAY_MS = 50
local ENTRY_H, ENTRY_GAP, ENTRY_Z = 56, 8, 30
-- Only reached if the column's slot cannot be read. On screen in the wrong
-- place beats absent.
local FALLBACK_X, FALLBACK_Y, FALLBACK_W = 60, 640, 400

local VIS_SHOW, VIS_HIDE = 0, 1

-- ---------------------------------------------------------------------------
-- plumbing
-- ---------------------------------------------------------------------------
local function log(msg)
    Logger.log("[PalBonds/Menu] " .. msg)
end

local function safe(f)
    local ok, v = pcall(f)
    if ok then return v end
    return nil
end

local function alive(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

local function addr(o)
    if o == nil then return nil end
    return safe(function() return o:GetAddress() end)
end

-- An address is not an identity: the engine recycles them, so another mod's
-- widget can land on the address of one of ours. The full name carries the
-- class, the outer path and Unreal's own object number.
local function identity(o)
    if not alive(o) then return nil end
    return safe(function() return o:GetFullName() end)
end

-- Named widgets are usually direct properties on the UserWidget -- one
-- reflection call instead of the hundreds a tree walk costs. Only the ones
-- that are not (VerticalBox_293, CanvasPanel_0) fall through to the walk.
local function find_by_name(menu, name)
    local direct = safe(function() return menu[name] end)
    if alive(direct) then return direct end
    local root = safe(function() return menu.WidgetTree.RootWidget end)
    if not alive(root) then return nil end
    if safe(function() return root:GetFName():ToString() end) == name then return root end
    local seen = {}
    local function walk(w)
        if not alive(w) then return nil end
        local a = addr(w)
        if a ~= nil then
            if seen[a] then return nil end
            seen[a] = true
        end
        if safe(function() return w:GetFName():ToString() end) == name then return w end
        local count = safe(function() return w:GetChildrenCount() end)
        if count then
            for i = 0, count - 1 do
                local hit = walk(safe(function() return w:GetChildAt(i) end))
                if hit then return hit end
            end
        end
        return nil
    end
    return walk(root)
end

-- StaticConstructObject on a dead outer is an access violation, and pcall
-- cannot catch a native fault -- hence the alive() gate before the call
-- rather than a pcall around it.
local function construct(classPathOrClass, outer)
    if not alive(outer) then return nil end
    local w = safe(function()
        local cls = classPathOrClass
        if type(cls) == "string" then cls = StaticFindObject(cls) end
        if not cls or not cls:IsValid() then return nil end
        return StaticConstructObject(cls, outer, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if alive(w) then return w end
    return nil
end

-- AddChildToCanvas returns the new slot, or NOTHING when the engine refuses
-- the add. Writing to that is a store through a null pointer at a small
-- offset, which pcall does not save us from either -- so every add site checks
-- the slot before it writes.
local function slot_of(canvas, w)
    local slot = canvas:AddChildToCanvas(w)
    if not (slot and slot:IsValid()) then error("canvas refused the child", 0) end
    return slot
end

local function canvas_fill(canvas, w, z)
    if not (alive(canvas) and alive(w)) then return false end
    return (pcall(function()
        local slot = slot_of(canvas, w)
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        slot:SetZOrder(z or 1)
    end))
end

local function canvas_add(canvas, w, x, y, sx, sy, z)
    if not (alive(canvas) and alive(w)) then return false end
    return (pcall(function()
        local slot = slot_of(canvas, w)
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
        slot:SetAlignment({ X = 0, Y = 0 })
        slot:SetPosition({ X = x, Y = y })
        slot:SetSize({ X = sx, Y = sy })
        slot:SetZOrder(z or 1)
    end))
end

-- Centred on the parent's own width, so the layout holds at any aspect ratio.
-- Dragón's screen is not the only one this has to be right on.
local function canvas_add_top_center(canvas, w, y, sx, sy, z)
    if not (alive(canvas) and alive(w)) then return false end
    return (pcall(function()
        local slot = slot_of(canvas, w)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
        slot:SetAlignment({ X = 0.5, Y = 0 })
        slot:SetPosition({ X = 0, Y = y })
        slot:SetSize({ X = sx, Y = sy })
        slot:SetZOrder(z or 1)
    end))
end

-- Sit directly above a widget that is anchored to its canvas's bottom edge,
-- mirroring its anchors so the result tracks at any resolution. A stretched
-- slot is made of OFFSETS, not position/size: writing the latter into one
-- produces a rectangle the slot cannot represent, and Slate crashed laying
-- that out. Inheriting Left/Right also matches the native rows' width for free.
local function canvas_add_above_stretch(anchorWidget, w, gap, h, z)
    if not (alive(anchorWidget) and alive(w)) then return false end
    return (pcall(function()
        local parent = anchorWidget:GetParent()
        if not alive(parent) then error("anchor has no parent", 0) end
        local aslot = anchorWidget.Slot
        local anchors = aslot:GetAnchors()
        local align = aslot:GetAlignment()
        local off = aslot:GetOffsets()
        if not (off and off.Top) then error("anchor slot has no offsets", 0) end
        local slot = slot_of(parent, w)
        slot:SetAnchors(anchors)
        slot:SetAlignment(align)
        slot:SetOffsets({ Left = off.Left, Top = off.Top - (h + (gap or 0)),
                          Right = off.Right, Bottom = h })
        slot:SetZOrder(z or 1)
    end))
end

-- Anchored to all four edges with margins, so the page keeps its padding at any
-- resolution instead of being a fixed rectangle that runs off a narrow screen.
local function canvas_inset(canvas, w, left, top, right, bottom, z)
    if not (alive(canvas) and alive(w)) then return false end
    return (pcall(function()
        local slot = slot_of(canvas, w)
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        slot:SetOffsets({ Left = left, Top = top, Right = right, Bottom = bottom })
        slot:SetZOrder(z or 1)
    end))
end

local function set_vis(w, vis)
    if not alive(w) then return end
    pcall(function() w:SetVisibility(vis) end)
end

-- ---------------------------------------------------------------------------
-- text, the way this project already knows works
-- ---------------------------------------------------------------------------
-- A raw `.Text = string` write into an FText field crashed the game on the
-- trust bar's first live test (2026-09-04). The fix was to construct the
-- game's own BP_PalTextBlock_C -- taken off a live instance rather than a path
-- -- and write through SetText_GDKInternal. Same pair here, which also means
-- the font and colour arrive already matching the menu.
local function text_class(menu)
    for _, name in ipairs(TEXT_SOURCES) do
        local t = find_by_name(menu, name)
        if alive(t) then
            local cls = safe(function() return t:GetClass() end)
            if cls and safe(function() return cls:IsValid() end) then return cls end
        end
    end
    return nil
end

local function center_text(tb)
    if not alive(tb) then return tb end
    pcall(function() tb:SetJustification(JUSTIFY_CENTER) end)
    return tb
end

local function make_text(inst, str, size)
    local tb = inst.textClass and construct(inst.textClass, inst.widgetTree)
    if tb == nil then return nil end
    local ok = pcall(function() tb:SetText_GDKInternal(true, str) end)
    if not ok then
        log("SetText_GDKInternal refused the text \"" .. tostring(str) .. "\"")
    end
    if size then
        -- Best-effort only: a font write is cosmetic and must never be able to
        -- take the page down with it.
        pcall(function()
            local f = tb.Font
            f.Size = size
            tb:SetFont(f)
        end)
    end
    return tb
end

-- ---------------------------------------------------------------------------
-- the game's own widgets
-- ---------------------------------------------------------------------------
-- Everything the player sees on our screen is one of the game's own blueprints,
-- so it looks like the game rather than like a mod -- and it follows a game
-- update for free. They are built through WidgetBlueprintLibrary:Create, which
-- is what gives a UserWidget an owning player; a bare StaticConstructObject
-- does not, and a widget without one does not draw.
--
-- The asset is loaded on demand: on a cold boot the menu's own blueprints are
-- not in memory until something asks for them.
local function native_widget(menu, classPath)
    if not alive(menu) then return nil end
    local w = safe(function()
        local lib = StaticFindObject(WIDGET_LIB)
        if not lib or not lib:IsValid() then return nil end
        local cls = StaticFindObject(classPath)
        if not cls or not cls:IsValid() then
            -- The asset path is the class path without the ".Name_C" tail.
            local asset = classPath:match("^(.*)%.[^%.]+$") or classPath
            pcall(function() LoadAsset(asset) end)
            cls = StaticFindObject(classPath)
        end
        if not cls or not cls:IsValid() then return nil end
        return lib:Create(menu, cls, menu:GetOwningPlayer())
    end)
    if alive(w) then return w end
    return nil
end

-- One of the ESC menu's own rows, labelled. Used for our entry in the menu and
-- for the page's Close button, so both read as native.
local function native_button(menu, label)
    local btn = native_widget(menu, BUTTON_CLASS)
    if btn == nil then return nil end
    -- Text_Main is the row's own label widget, and it is already a
    -- BP_PalTextBlock_C -- so the same safe write applies.
    local labelled = pcall(function() btn.Text_Main:SetText_GDKInternal(true, label) end)
    if not labelled then
        log("could not label the \"" .. tostring(label) .. "\" button")
    end
    return btn
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
-- One record per ESC menu, keyed by the menu's address. A menu is a fresh
-- widget tree every time it opens, so nothing here survives a close.
local instances = {}
local newestMenu = nil
local hooksArmed = false
local destructArmed = false
-- What our own buttons are, so the shared click hook can tell them from the
-- game's. Keyed by address, holding the identity that address must still have.
local ourButtons = {}

-- How far the shared canvas's bottom-anchored stack already reaches upward:
-- the smallest (most negative) Offsets.Top among its bottom-anchored children.
-- READ-ONLY -- it enumerates and reads slots and mutates nothing, which is
-- what makes it safe on a native panel.
--
-- Learned once and kept: another mod cannot be installed mid-session, so where
-- its row sits is a property of the session, not of this menu instance.
local shelfLift = nil

local function bottom_stack_top(canvas, exclude)
    local best = nil
    pcall(function()
        local count = canvas:GetChildrenCount()
        for i = 0, (count or 0) - 1 do
            local ch = canvas:GetChildAt(i)
            if alive(ch) and ch ~= exclude then
                pcall(function()
                    local s = ch.Slot
                    -- Bottom-anchored means Anchors.Minimum.Y == 1. Top-anchored
                    -- children live in a different origin and must not be mixed in.
                    if s and s:IsValid() and s:GetAnchors().Minimum.Y == 1 then
                        local t = s:GetOffsets().Top
                        if type(t) == "number" and (best == nil or t < best) then best = t end
                    end
                end)
            end
        end
    end)
    return best
end

-- ---------------------------------------------------------------------------
-- the page
-- ---------------------------------------------------------------------------
-- EVERY ROW IS THE GAME'S OWN SETTINGS ROW. WBP_OptionSettings_ListContent_C is
-- the widget Palworld's own Options screen is built from, and one row class
-- covers all three shapes we need: SetSwitcher for on/off, SetSlider for a
-- number, SetSelecter_String for a list. So the screen does not imitate the
-- game's look, it IS the game's look, and it follows a game update for free.
-- (Found by reading Better Mod Manager, which drives the same widget; Dragón
-- pointed at it. Every method and sub-widget below is verified present in this
-- build's object dump.)
--
-- THE LIST IS BUILT FROM Settings.Schema(), not from a list kept here. A
-- setting added to the file therefore appears on the screen with no second
-- place to remember, and the two can never disagree about what exists.
--
-- CONTAINERS: ScrollBox and VerticalBox are fine here because they are OURS.
-- The rule that costs crashes is about mutating the GAME's live panels; inside
-- our own subtree a reflow is ordinary UMG.
--
-- EVERY LABEL IS WRITTEN FOR PLAYERS AND TRANSLATED. The first version showed
-- the setting names out of the config file (`Pet`, `FeedBase`, `ChanceNormal`)
-- and Dragón was right to reject it: "lets keep the labels easy to understand
-- and far from code names", and "the settings themselves should change language
-- when one changes languages". Each schema entry now names a Locale entry, and
-- the seven personality rows reuse tag_normal..tag_feral -- the exact words the
-- player already reads over a Pal's head, so the two can never drift apart.
--
-- AND THE CONTROLS COME FROM THE SCHEMA'S `ui`, NOT FROM ITS VALIDATION BOUNDS.
-- Deriving a slider's range from `max` produced a slider from 0 to 100000 for a
-- value whose useful range is around 50, which made it physically impossible to
-- set: the smallest drag jumped by thousands. See the note above SCHEMA in
-- Settings.lua for why the two ranges are separate.
local PAGE_Z        = 60
-- Margins, in the menu's design units. The window frame sits inside the screen,
-- the list inside the frame, and the buttons clear of the bottom edge -- the
-- first version had the title cut by the tabs above it and the Close button
-- touching the bottom border.
local WIN_L, WIN_T, WIN_R, WIN_B = 300, 96, 300, 56
local TITLE_Y       = 140
local HINT_Y        = 192
local LIST_L, LIST_T, LIST_R, LIST_B = 344, 238, 344, 188
local NOTE_UP       = 140        -- from the bottom
local BUTTONS_UP    = 76
local BUTTON_W      = 330
local BUTTON_GAP    = 16
-- ETextJustify: 0 left, 1 centre, 2 right. A TextBlock draws LEFT inside its
-- slot, so a slot centred on the canvas is not the same as centred text -- which
-- is exactly why the title and the subtitle sat off to the left of the panel in
-- Dragón's screenshot even though their slots were centred.
local JUSTIFY_CENTER = 1
-- The game's own Options rows are 48 high with 8 between them; matching that is
-- most of what makes the page read as native.
local ROW_H         = 48
local ROW_GAP       = 8
local SECTION_TOP   = 22
local TITLE_FONT    = 32
local ROW_FONT      = 17
local SECTION_FONT  = 19
local HINT_FONT     = 15
local KEY_BUTTON_W  = 210
local POLL_MS       = 150

-- UMG alignment and size-rule values.
local ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT = 1, 2, 3
-- The scroll bar is drawn inside the list's own width, so a row that reaches the
-- very edge is drawn under it.
local SCROLLBAR_GAP = 28

-- ANY KEY, NOT A LIST. The first version offered a fixed selection to rebind to,
-- which Dragón called awful and he is right -- it is our implementation's
-- convenience limiting what the player is allowed to do. Rebinding is now
-- "click, then press the key you want".
--
-- Reading an arbitrary press means UE4SS has to have a binding on every key, so
-- that is exactly what happens -- but only from the moment the player first
-- opens this screen, never at mod load, and every one of those handlers returns
-- immediately unless the screen is actually waiting for a key. A player who
-- never opens the screen never gets them.
--
-- Mouse buttons and the modifiers are left out: a click on the rebind button
-- would otherwise become the new binding, and Escape and Backspace belong to
-- the menu itself.
local NOT_CAPTURABLE = { "MOUSE", "ESCAPE", "BACKSPACE", "SHIFT", "CONTROL", "ALT", "WIN", "LOCK", "TAB" }

local function capturable(name)
    if type(name) ~= "string" or name == "" then return false end
    local upper = name:upper()
    for _, pattern in ipairs(NOT_CAPTURABLE) do
        if upper:find(pattern, 1, true) then return false end
    end
    return true
end

-- What a row is called on screen. The schema names a Locale entry; Locale.T
-- hands back the key itself when it has no such entry, which is the one case
-- where falling back to the internal name beats showing nothing.
-- `labelPrefix` puts another translated word in front, joined with a dash: the
-- seven bonding switches read "Curious — can be bonded" without seven more
-- strings to translate, and they reuse the very tag the player sees on the Pal.
local function translated(key)
    if type(key) ~= "string" then return nil end
    local okL, Locale = pcall(require, "Locale")
    if not (okL and Locale and Locale.T) then return nil end
    local text = Locale.T(key)
    if type(text) == "string" and text ~= "" and text ~= key then return text end
    return nil
end

local function label_for(entry)
    local text = translated(entry.label)
    if text == nil then return entry.key or entry.section or "?" end
    local prefix = translated(entry.labelPrefix)
    if prefix ~= nil then return prefix .. " — " .. text end
    return text
end

local function ui_text(key, fallback)
    local okL, Locale = pcall(require, "Locale")
    if okL and Locale and Locale.T then
        local text = Locale.T(key)
        if type(text) == "string" and text ~= "" and text ~= key then return text end
    end
    return fallback
end

-- The control a setting gets. A setting added later with no `ui` block still
-- gets something usable rather than being left off the screen.
local function ui_of(entry)
    if type(entry.ui) == "table" then return entry.ui end
    if entry.kind == "language" then return { kind = "choice" } end
    if entry.kind == "key" then return { kind = "key" } end
    if entry.min == 0 and entry.max == 1 then return { kind = "switch" } end
    if type(entry.min) == "number" and type(entry.max) == "number" then
        return { kind = "slider", min = entry.min, max = entry.max, step = 1 }
    end
    return { kind = "switch" }
end

local function anchored_bottom_center(canvas, w, up, sx, sy, z)
    if not (alive(canvas) and alive(w)) then return false end
    return (pcall(function()
        local slot = slot_of(canvas, w)
        slot:SetAnchors({ Minimum = { X = 0.5, Y = 1 }, Maximum = { X = 0.5, Y = 1 } })
        slot:SetAlignment({ X = 0.5, Y = 1 })
        slot:SetPosition({ X = 0, Y = -up })
        slot:SetSize({ X = sx, Y = sy })
        slot:SetZOrder(z or 1)
    end))
end

local function index_of(list, value)
    for i, v in ipairs(list) do
        if v == value then return i - 1 end      -- the widget counts from 0
    end
    return 0
end

-- Only the language is a list now. The keys used to be one, which was the wrong
-- answer (see the any-key note above).
--
-- WHAT IS STORED AND WHAT IS SHOWN ARE DIFFERENT THINGS. The setting is a code
-- ("es"), which is what the file holds and what the screen showed in Dragón's
-- screenshot -- a code name in front of a player, the thing this screen is not
-- supposed to do. Each language is listed under its OWN name instead, which
-- needs no translating: somebody looking for Spanish is looking for "Español".
local LANGUAGE_NAMES = {
    en = "English", es = "Español", fr = "Français", de = "Deutsch",
    it = "Italiano", pl = "Polski", pt = "Português", ru = "Русский",
    tr = "Türkçe", vi = "Tiếng Việt", th = "ไทย", id = "Indonesia",
    ja = "日本語", ko = "한국어", ["zh-hans"] = "简体中文", ["zh-hant"] = "繁體中文",
}

local function choices_for(entry)
    -- A setting that names its own allowed values (a colour, a size) is listed
    -- from them, each shown under its translated name.
    if type(entry.values) == "table" then
        local values, shown = {}, {}
        for _, name in ipairs(entry.values) do
            values[#values + 1] = name
            shown[#shown + 1] = ui_text("opt_" .. name, name)
        end
        return values, shown
    end
    if entry.kind ~= "language" then return {}, {} end
    local values, shown = { "auto" }, { ui_text("menu_auto", "Auto") }
    local okL, Locale = pcall(require, "Locale")
    if okL and Locale and Locale.LANGUAGES then
        for _, code in ipairs(Locale.LANGUAGES) do
            values[#values + 1] = code
            shown[#shown + 1] = LANGUAGE_NAMES[code] or code
        end
    end
    return values, shown
end

-- A SizeBox is how a fixed width or height is asked for in UMG.
local function sized(inst, content, width, height)
    local box = construct("/Script/UMG.SizeBox", inst.widgetTree)
    if box == nil then return nil end
    if width then pcall(function() box:SetWidthOverride(width) end) end
    if height then pcall(function() box:SetHeightOverride(height) end) end
    pcall(function() box:SetContent(content) end)
    return box
end

-- The number beside a slider. The row's own value label is a BP_PalTextBlock,
-- so it takes the same safe write as every other piece of text here, with the
-- plain UMG call as a fallback for a build where that method is absent.
local function show_slider_number(control, value)
    if not alive(control.valueText) then return end
    local text = tostring(value)
    if pcall(function() control.valueText:SetText_GDKInternal(true, text) end) then return end
    pcall(function() control.valueText:SetText(FText(text)) end)
end

-- Put a value into a row. Used to seed it, and to put a refused value back --
-- a screen that keeps showing a number the mod did not accept is lying.
local function show_key_button(control)
    if not alive(control.button) then return end
    local text
    if control.capturing then
        text = ui_text("menu_press_key", "Press a key")
    else
        local name = Settings.Get(control.key)
        text = (type(name) == "string" and name ~= "") and name or "--"
    end
    pcall(function() control.button.Text_Main:SetText_GDKInternal(true, text) end)
end

local function show_control(control, value)
    if control.kind == "key" then
        show_key_button(control)
        return
    end
    if not alive(control.row) then return end
    if control.kind == "switch" then
        pcall(function() control.row:SetSwitcher(value ~= 0) end)
    elseif control.kind == "slider" then
        pcall(function()
            control.row:SetSlider(value, control.min, control.max, control.step, true)
        end)
        show_slider_number(control, value)
    else
        pcall(function()
            control.row:SetSelecter_String(control.labels or control.choices,
                                           index_of(control.choices, value))
        end)
    end
end

-- What the row says right now, in the setting's own terms.
local function control_value(control)
    -- A key is not polled: it changes on a press, not by being dragged.
    if control.kind == "key" then return nil end
    if not alive(control.widget) then return nil end
    if control.kind == "switch" then
        local on = safe(function() return control.widget.CurrentIsOn end)
        if on == nil then return nil end
        return on and 1 or 0
    end
    if control.kind == "slider" then
        local v = safe(function() return control.widget.CurrentValue end)
        if type(v) ~= "number" or v ~= v then return nil end
        -- The slider works in floats; every setting of ours is a whole number.
        return math.floor(v + 0.5)
    end
    local i = safe(function() return control.widget.Current end)
    if type(i) ~= "number" then return nil end
    return control.choices[math.floor(i) + 1]
end

local function set_note(inst, text)
    if not alive(inst.note) then return end
    if inst.noteText == text then return end
    inst.noteText = text
    if pcall(function() inst.note:SetText_GDKInternal(true, text) end) then return end
    pcall(function() inst.note:SetText(FText(text)) end)
end

-- ---------------------------------------------------------------------------
-- watching the rows
-- ---------------------------------------------------------------------------
-- The rows are POLLED while the page is open rather than each control being
-- hooked. Three reasons, in order of how much they matter: the switch and the
-- selector have no delegate we could hook without adding three more native
-- hooks to the mod; polling only ever runs while the player is standing in a
-- paused menu, which is the cheapest moment in the game; and one loop that
-- reads every row is far less machinery than a hook per control type, which is
-- the kind of machinery this file is trying not to accumulate.
-- TWO GUARDS, BOTH LEARNED FROM WHAT THIS SCREEN CAN DO TO A PLAYER'S FILE.
--
-- 1. A widget is not believed until it has given back the value we put into it.
--    A native row that has not laid out yet can report 0, and the watch would
--    then treat that 0 as the player's choice and save it -- a settings screen
--    that empties your settings just by being opened. Bounded, so a value the
--    widget genuinely cannot hold is accepted rather than fought forever.
-- 2. A value already outside the screen's range widens the row instead of being
--    clamped (see add_row). Clamping would silently rewrite a setting the player
--    put in the file by hand, which is the same failure wearing a different hat.
local SETTLE_TRIES = 5

-- Forward-declared: sync_control calls it the moment the language changes, and
-- it is defined below next to the rest of the drawing.
local refresh_texts

local function sync_control(inst, control)
    local value = control_value(control)
    if value == nil then return end
    if not control.settled then
        if value == control.shown then
            control.settled = true
        else
            control.settleTries = (control.settleTries or 0) + 1
            if control.settleTries >= SETTLE_TRIES then
                control.settled = true
                log(control.key .. ": the row would not take the stored value -- following the row from now on")
            else
                show_control(control, control.shown)
            end
        end
        return
    end
    if value == control.shown then return end
    local good, why = Settings.Set(control.key, value)
    if good == nil then
        show_control(control, control.shown)
        set_note(inst, label_for(control.entry) .. ": " .. tostring(why))
        return
    end
    control.shown = good
    -- Settings may normalise (a language to lower case, a key name to upper),
    -- so the row is corrected when what it holds is not what was stored.
    if good ~= value then show_control(control, good) end
    if control.key == "Language" then pcall(refresh_texts, inst) end
    -- NOTHING IS SAID WHEN A CHANGE SIMPLY WORKS. It used to print the setting's
    -- internal name and value -- code words in front of a player, for something
    -- they can already see on the row they just moved. The note line is for the
    -- two things the row cannot say by itself: a refusal, and "Saved".
    inst.changed = true
end

-- THE SUBTITLE PROMISES THIS. Changing the language has to change the screen
-- the player is looking at, not just the next toast -- Dragón: "changing
-- language doesnt inmediately changes languages as the subtitle of the screen
-- says". Every label, heading, hint and button is rewritten from Locale, and
-- the lists rebuild their own choices (the language list is written in each
-- language's own name, and "Auto" is translated).
function refresh_texts(inst)
    for _, t in ipairs(inst.texts or {}) do
        if alive(t.w) then
            local text = t.entry ~= nil and label_for(t.entry) or ui_text(t.key, t.fallback or "")
            pcall(function() t.w:SetText_GDKInternal(true, text) end)
        end
    end
    for _, control in ipairs(inst.controls or {}) do
        if control.kind == "choice" then
            control.choices, control.labels = choices_for(control.entry)
            show_control(control, Settings.Get(control.key))
        elseif control.kind == "key" then
            show_control(control, nil)
        end
    end
    inst.noteText = nil          -- so the next note is written even if it matches
end

local function poll_rows(inst, token)
    if inst.disposed or inst.superseded or not inst.pageOpen then return end
    if inst.pollToken ~= token then return end        -- a newer poll owns the page
    for _, control in ipairs(inst.controls or {}) do
        pcall(sync_control, inst, control)
    end
    pcall(function()
        ExecuteInGameThreadWithDelay(POLL_MS, function() poll_rows(inst, token) end)
    end)
end

-- ---------------------------------------------------------------------------
-- building it
-- ---------------------------------------------------------------------------
local function add_to_list(inst, list, child, topPad)
    return (pcall(function()
        local slot = list:AddChildToVerticalBox(child)
        if slot ~= nil and slot:IsValid() then
            slot:SetPadding({ Left = 0, Top = topPad or 0, Right = 0, Bottom = ROW_GAP })
        end
    end))
end

-- A KEY ROW IS NOT THE GAME'S OPTION ROW. The native row can show a key, but
-- only through SetKeyIcon/SetConfigButton, which take an engine FKey and one of
-- the game's OWN input actions -- neither of which a mod's own keybind is. So a
-- key row is the label plus the game's small option button showing the current
-- key, which keeps the game's styling without pretending our keybind is one of
-- the game's actions.
-- AN OVERLAY, NOT A HORIZONTAL BOX. A horizontal box inside a scroll box is
-- given as much width as its children ask for, so the fixed-width button sat
-- past the list's right edge and was clipped in half -- "the keys still look cut
-- off by the same screen". An overlay fills the width it is GIVEN and aligns its
-- children inside it, so the button lands against the right edge of the list, a
-- little clear of the scrollbar, whatever that width turns out to be.
local function add_key_row(inst, list, entry)
    local line = construct("/Script/UMG.Overlay", inst.widgetTree)
    if line == nil then return false end
    local box = sized(inst, line, nil, ROW_H)
    if box == nil or not add_to_list(inst, list, box) then return false end

    -- The GAME's own row decides the size, not us: a key row is the one row we
    -- draw the label for ourselves, and at our own size it stood out as bigger
    -- than every row around it (Dragón, 2026-09-25).
    local label = make_text(inst, label_for(entry), inst.rowFont or ROW_FONT)
    if label ~= nil then
        pcall(function()
            local slot = line:AddChildToOverlay(label)
            if slot ~= nil and slot:IsValid() then
                slot:SetHorizontalAlignment(ALIGN_LEFT)
                slot:SetVerticalAlignment(ALIGN_CENTER)
                slot:SetPadding({ Left = 12, Top = 0, Right = 0, Bottom = 0 })
            end
        end)
        inst.texts[#inst.texts + 1] = { w = label, entry = entry }
    end

    local button = native_button(inst.menu, "")
    if button == nil then return false end
    local buttonBox = sized(inst, button, KEY_BUTTON_W, ROW_H - 8)
    if buttonBox == nil then return false end
    local placed = pcall(function()
        local slot = line:AddChildToOverlay(buttonBox)
        if slot ~= nil and slot:IsValid() then
            slot:SetHorizontalAlignment(ALIGN_RIGHT)
            slot:SetVerticalAlignment(ALIGN_CENTER)
            -- Clear of the scrollbar, which sits inside the list's own width.
            slot:SetPadding({ Left = 0, Top = 0, Right = SCROLLBAR_GAP, Bottom = 0 })
        end
    end)
    if not placed then return false end

    local control = { key = entry.key, entry = entry, kind = "key", button = button }
    show_control(control, nil)
    local a, id = addr(button), identity(button)
    if a == nil or id == nil then
        -- A button we cannot recognise later would look clickable and do
        -- nothing, which is worse than a row that says so.
        log(entry.key .. ": the rebind button has no readable identity")
        return false
    end
    ourButtons[a] = { ref = button, id = id, menuAddr = inst.addr, kind = "key", control = control }
    inst.controls[#inst.controls + 1] = control
    return true
end

local function add_row(inst, list, entry)
    local ui = ui_of(entry)
    if ui.kind == "key" then return add_key_row(inst, list, entry) end

    local row = native_widget(inst.menu, ROW_CLASS)
    if row == nil then return false end
    local box = sized(inst, row, nil, ROW_H)
    if box == nil or not add_to_list(inst, list, box) then return false end

    -- The label goes in the row's own name widget, so it sits exactly where the
    -- game puts the name of one of its own settings.
    pcall(function() row.BP_PalTextBlock_Name:SetText_GDKInternal(true, label_for(entry)) end)
    local nameWidget = safe(function() return row.BP_PalTextBlock_Name end)
    if alive(nameWidget) then
        inst.texts[#inst.texts + 1] = { w = nameWidget, entry = entry }
        -- Read once, from the game's own row, and reused by the rebind rows.
        if inst.rowFont == nil then
            inst.rowFont = safe(function() return nameWidget.Font.Size end)
        end
    end

    -- A file can hold a value the screen would not normally offer (its own
    -- bounds are far wider). The row stretches to reach it rather than clamping,
    -- because clamping would quietly rewrite a number the player chose.
    local current = Settings.Get(entry.key)
    local low, high = ui.min, ui.max
    if ui.kind == "slider" and type(current) == "number" then
        if current < low then low = current end
        if current > high then high = current end
        if low ~= ui.min or high ~= ui.max then
            log(entry.key .. " is " .. tostring(current) ..
                ", outside this screen's usual range -- the row was widened to keep it")
        end
    end
    local values, labels = nil, nil
    if ui.kind == "choice" then values, labels = choices_for(entry) end
    local control = {
        key = entry.key,
        entry = entry,
        row = row,
        kind = ui.kind,
        min = low,
        max = high,
        step = ui.step or 1,
        choices = values,
        labels = labels,
    }
    if ui.kind == "switch" then
        control.widget = safe(function() return row.WBP_OptionSettings_ListContentSwitch end)
    elseif ui.kind == "slider" then
        control.widget = safe(function() return row.WBP_OptionSettings_ListContentSlider end)
        control.valueText = safe(function() return control.widget.BP_PalTextBlock_Value end)
    else
        control.widget = safe(function() return row.WBP_OptionSettings_ListContentLR end)
    end
    if not alive(control.widget) then
        log(entry.key .. ": the row has no " .. tostring(ui.kind) .. " to drive — left off the screen")
        return false
    end
    control.shown = Settings.Get(entry.key)
    show_control(control, control.shown)
    inst.controls[#inst.controls + 1] = control
    return true
end

local function add_section(inst, list, entry)
    local text = make_text(inst, label_for(entry), SECTION_FONT)
    if text == nil then return end
    add_to_list(inst, list, text, SECTION_TOP)
    inst.texts[#inst.texts + 1] = { w = text, entry = entry }
end

local function build_page(inst)
    if not (alive(inst.menu) and alive(inst.widgetTree) and alive(inst.pageRoot)) then
        return false
    end
    if inst.disposed or inst.superseded then return false end

    local page = construct("/Script/UMG.CanvasPanel", inst.widgetTree)
    if page == nil or not canvas_fill(inst.pageRoot, page, PAGE_Z) then return false end
    -- Hidden from birth: a visible parent paints its children as they are
    -- built, which is a flash of half-made page on the way in.
    set_vis(page, VIS_HIDE)
    inst.page = page
    inst.controls = {}
    -- Every translated string on screen, so the whole page can be rewritten the
    -- moment the language changes -- which is the one setting that has to prove
    -- the subtitle right in front of the player.
    inst.texts = {}

    -- A tinted Image is the whole backdrop. The menu's own blur is behind it.
    local dim = construct("/Script/UMG.Image", inst.widgetTree)
    if dim ~= nil then
        pcall(function() dim:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.82 }) end)
        canvas_fill(page, dim, 0)
    end

    -- The game's own panel frame, inset from every edge. If this build has no
    -- such asset the page is still perfectly usable against the dim above, so a
    -- missing frame is not a failure.
    local window = native_widget(inst.menu, WINDOW_CLASS)
    if window ~= nil then
        set_vis(window, 4)          -- SelfHitTestInvisible: decoration only
        canvas_inset(page, window, WIN_L, WIN_T, WIN_R, WIN_B, 1)
    else
        log("this build has no common window frame -- the page is drawn without one")
    end

    local title = center_text(make_text(inst, ENTRY_LABEL, TITLE_FONT))
    if title ~= nil then canvas_inset(page, title, WIN_L, TITLE_Y, WIN_R, 0, 3) end

    -- One quiet line saying the thing a player most needs to know about this
    -- screen: nothing here waits for a restart.
    local hint = center_text(make_text(inst, ui_text("menu_applies_now", "Changes apply right away"), HINT_FONT))
    if hint ~= nil then
        canvas_inset(page, hint, WIN_L, HINT_Y, WIN_R, 0, 3)
        inst.texts[#inst.texts + 1] = { w = hint, key = "menu_applies_now", fallback = "Changes apply right away" }
    end

    local scroll = construct("/Script/UMG.ScrollBox", inst.widgetTree)
    local list = construct("/Script/UMG.VerticalBox", inst.widgetTree)
    if scroll == nil or list == nil then return false end
    if not pcall(function() scroll:AddChild(list) end) then return false end
    if not canvas_inset(page, scroll, LIST_L, LIST_T, LIST_R, LIST_B, 3) then return false end

    -- One row per setting, in the file's own order, under the file's own
    -- headings. Nothing here decides WHICH settings exist.
    local built, skipped = 0, 0
    for _, entry in ipairs(Settings.Schema()) do
        if inst.disposed or inst.superseded then return false end
        if entry.section then
            add_section(inst, list, entry)
        elseif entry.key then
            -- Guarded per row on purpose. A setting whose shape this code does
            -- not expect must cost that one row and nothing else: an unguarded
            -- loop here meant a single bad entry threw and the player got no
            -- screen at all, with the rows already built left dangling.
            local ok, added = pcall(add_row, inst, list, entry)
            if ok and added then
                built = built + 1
            else
                skipped = skipped + 1
                log(entry.key .. " could not be drawn" ..
                    ((not ok) and (": " .. tostring(added)) or ""))
            end
        end
    end
    if built == 0 then return false end
    -- A little air at the end of the list, so the last row can be scrolled fully
    -- into view instead of sitting against the clip edge.
    local tail = construct("/Script/UMG.SizeBox", inst.widgetTree)
    if tail ~= nil then
        pcall(function() tail:SetHeightOverride(ROW_H) end)
        pcall(function() list:AddChildToVerticalBox(tail) end)
    end

    inst.note = center_text(make_text(inst, "", HINT_FONT))
    if inst.note ~= nil then canvas_inset(page, inst.note, WIN_L, 0, WIN_R, NOTE_UP, 3) end

    -- THREE BUTTONS, Dragón's call: save what you changed, put it back, or go
    -- back to the values the mod ships with. Cancel is only possible because the
    -- page remembers what everything was when it opened.
    local bar = construct("/Script/UMG.HorizontalBox", inst.widgetTree)
    if bar ~= nil then
        local total = BUTTON_W * 3 + BUTTON_GAP * 2
        anchored_bottom_center(page, bar, BUTTONS_UP, total, ROW_H, 3)
        local buttons = {
            { kind = "save",     key = "menu_save",     fallback = "Save" },
            { kind = "cancel",   key = "menu_cancel",   fallback = "Cancel" },
            { kind = "defaults", key = "menu_defaults", fallback = "Restore defaults" },
        }
        for i, spec in ipairs(buttons) do
            local button = native_button(inst.menu, ui_text(spec.key, spec.fallback))
            if button ~= nil then
                local labelWidget = safe(function() return button.Text_Main end)
                if alive(labelWidget) then
                    inst.texts[#inst.texts + 1] = { w = labelWidget, key = spec.key, fallback = spec.fallback }
                end
            end
            local holder = button ~= nil and sized(inst, button, BUTTON_W, ROW_H) or nil
            if holder ~= nil then
                pcall(function()
                    local slot = bar:AddChildToHorizontalBox(holder)
                    if slot ~= nil and slot:IsValid() and i > 1 then
                        slot:SetPadding({ Left = BUTTON_GAP, Top = 0, Right = 0, Bottom = 0 })
                    end
                end)
                local a, id = addr(button), identity(button)
                if a ~= nil and id ~= nil then
                    ourButtons[a] = { ref = button, id = id, menuAddr = inst.addr, kind = spec.kind }
                end
            end
        end
    end

    log(string.format("page built with %d setting(s)%s", built,
        skipped > 0 and (", " .. skipped .. " could not be drawn") or ""))
    return true
end

-- ---------------------------------------------------------------------------
-- rebinding a key
-- ---------------------------------------------------------------------------
-- One screen at a time can be waiting for a press, so this is file-level rather
-- than per menu: a second ESC menu cannot exist while the player is looking at
-- the first one's page.
-- ===========================================================================
-- HOW A KEY IS CAPTURED (rebuilt 2026-09-26) -- THE GAME'S OWN MODAL
-- ===========================================================================
-- This used to arm ~154 RegisterKeyBind watchers on first open, one per
-- bindable key, and they stayed for the whole session firing on every press.
-- That is what was crashing the game every few minutes: UE4SS issue #1345
-- (narknon) states main_lua, hook_lua and async_lua are coroutines off ONE
-- lua_State sharing one global_State and one GC, WITH NO LOCK, and a
-- RegisterKeyBind callback runs on UE4SS's own thread. Marshalling to the game
-- thread inside the handler is too late -- the `if capturing == nil` check has
-- already executed Lua off-thread. Three trace runs showed the damage:
-- LUA_ERRERR, ten hook calls that entered and never returned, and a death
-- inside a hook's own Context:get().
--
-- Six probe rounds found the replacement, and it is the game's own:
--     WBP_OptionSettingsOverLayWindow_C  (the "press a key" overlay the
--     game's key-config screen puts up while it waits)
--       void OnKeySetting(FKey NewKey);   <-- an FKey as a HOOK PARAMETER
--       FEventReply OnKeyDown(FGeometry, FKeyEvent);
--       UWidget* BP_GetDesiredFocusTarget();
-- Hooking OnKeySetting returned clean names for every key tried, including
-- SpaceBar and W -- the two a curated RegisterKeyBind battery cannot capture.
--
-- The rule the crashes bought, worth keeping: CALLING a function that takes or
-- returns an FKey-bearing struct by value kills the process; HOOKING one and
-- READING the FKey as a parameter works. Reading goes through UE4SS's property
-- path, which is safe; calling marshals a struct it cannot build.
local OVERLAY_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/"
    .. "WBP_OptionSettingsOverLayWindow.WBP_OptionSettingsOverLayWindow_C"
local OVERLAY_Z = 90
local OVERLAY_HOOK_RETRY_MS = 4000
local OVERLAY_HOOK_MAX_ROUNDS = 30

local capturing = nil          -- { inst = , control = , overlay = }
local overlayHookArmed = false

local hold_input                 -- defined below, once `capturing` exists

-- A UE4SS FName prints as "FNameUserdata: <address>" under tostring(); the text
-- comes from :ToString(). Capture.lua has said so since its 168th line, and a
-- probe round was lost to forgetting it.
local function name_text(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local s = safe(function() return v:ToString() end)
    if s == nil then return nil end
    s = tostring(s)
    if s == "" or s == "None" then return nil end
    return s
end

-- Ours, built by us, so taking it back out is our own child -- not the game's
-- menu, which rule 3 forbids touching.
local function close_overlay(waiting)
    if waiting == nil or waiting.overlay == nil then return end
    local overlay = waiting.overlay
    waiting.overlay = nil
    pcall(function()
        local parent = overlay.Slot and overlay.Slot.Parent
        if parent ~= nil and parent:IsValid() then parent:RemoveChild(overlay) end
    end)
end

local function stop_capture()
    local waiting = capturing
    capturing = nil
    if waiting ~= nil then
        close_overlay(waiting)
        waiting.control.capturing = false
        show_control(waiting.control, nil)
        if hold_input ~= nil then pcall(hold_input, waiting.inst, false) end
    end
end

-- REMOVED 2026-09-26: CAPTURE_MIN_WAIT, a 0.25s deaf period after the click.
--
-- It existed for the RegisterKeyBind mechanism, where UE4SS's registration
-- burst could deliver a key nobody pressed the instant capture began (Dragón's
-- Play key silently became D). That mechanism is gone: the overlay only reports
-- a key it actually received while focused, so there is nothing to defend
-- against -- and the guard's only remaining effect was to swallow the player's
-- FIRST press. His run shows it plainly, four times:
--     ignoring F6: it arrived before the screen finished asking
--     ignoring F5: ...  ignoring F4: ...  ignoring F2: ...
-- and each time the screen then sat holding the keyboard until he pressed
-- again or the timer let go, which is the "it locks me when the key fails" he
-- reported. A quarter of a second is squarely inside human reaction time; a
-- guard that cannot tell a real press from a phantom one is worse than none
-- once the phantom cannot happen.
local key_pressed

-- Forward-declared: arm_overlay_hook (below) calls it, and a Lua local declared
-- further down is not in scope above it. This project has paid for that three
-- times.
function key_pressed(name)
    local waiting = capturing
    if waiting == nil then return end
    local inst, control = waiting.inst, waiting.control
    if inst.disposed or inst.superseded or not inst.pageOpen then stop_capture() return end
    capturing = nil
    control.capturing = false
    -- TAKE THE OVERLAY DOWN FIRST. The success path does not go through
    -- stop_capture, so without this the game's modal stayed on screen after the
    -- key was accepted -- caught by menutest, not by reading the code.
    close_overlay(waiting)
    hold_input(inst, false)
    local good, why = Settings.Set(control.key, name)
    if good == nil then
        log(control.key .. ": " .. tostring(name) .. " refused — " .. tostring(why))
        set_note(inst, label_for(control.entry) .. ": " .. tostring(why))
    else
        inst.changed = true
        log(control.key .. " set to " .. tostring(good) .. " (the player pressed it)")
        set_note(inst, "")
    end
    show_control(control, nil)
    -- Q and E are the game's OWN menu navigation, routed above the layer input
    -- mode reaches, so they still change the tab underneath our page while we
    -- are listening. The binding itself takes; this puts back whatever that
    -- uncovered, so the page is not left sitting over a different tab.
    for _, covered in ipairs(inst.covered or {}) do
        set_vis(covered.w, VIS_HIDE)
    end
end

-- ONE hook, class-wide, registered the first time the screen opens. It fires
-- for any instance of the overlay -- including the game's own key-config screen
-- -- so the handler checks that the instance firing is the one WE put up before
-- it touches anything. Without that, rebinding in the game's own options would
-- also write one of our settings.
local function arm_overlay_hook(round)
    round = round or 1
    if overlayHookArmed then return end

    local ok, err = pcall(function()
        RegisterHook(OVERLAY_CLASS .. ":OnKeySetting", function(Context, NewKey)
            local waiting = capturing
            if waiting == nil or waiting.overlay == nil then return end
            local who = safe(function() return Context:get() end)
            if who == nil then return end
            -- Same instance? Compared by address: two wrappers for one object
            -- are not necessarily the same Lua value.
            local mine = safe(function() return waiting.overlay:GetAddress() end)
            local fired = safe(function() return who:GetAddress() end)
            if mine == nil or fired == nil or mine ~= fired then return end

            local key = safe(function() return NewKey:get() end)
            local name = key ~= nil and name_text(safe(function() return key.KeyName end)) or nil
            if name == nil then
                log("the overlay reported a key we could not read -- ignoring it")
                return
            end
            -- The overlay reports whatever was pressed, so the filter that used
            -- to decide which keys got a watcher now decides which reported keys
            -- are ACCEPTED. Escape cancels, the way it does in the game's own
            -- key config; a mouse button or a bare modifier is simply not an
            -- answer, so the screen keeps waiting.
            if name:upper():find("ESCAPE", 1, true) then
                log("escape while waiting for a key -- cancelled")
                pcall(stop_capture)
                return
            end
            if not capturable(name) then
                log("ignoring '" .. name .. "': not a bindable key")
                return
            end
            key_pressed(name)
        end)
    end)

    if ok then
        overlayHookArmed = true
        log("key capture ready (the game's own press-a-key overlay, no key watchers)")
        return
    end
    if round >= OVERLAY_HOOK_MAX_ROUNDS then
        log("could not hook the game's press-a-key overlay -- rebinding will not work: "
            .. tostring(err))
        return
    end
    pcall(function()
        ExecuteInGameThreadWithDelay(OVERLAY_HOOK_RETRY_MS, function() arm_overlay_hook(round + 1) end)
    end)
end

-- Asked by Interaction before it acts on one of our own keys: while the player
-- is choosing a new key, pressing F8 should not also play with a Pal.
function Menu.WaitingForKey()
    return capturing ~= nil
end

-- HOLDING THE KEYBOARD WHILE WE ASK FOR A KEY.
--
-- Without this the press does double duty: Dragón tried to bind the key that
-- opens the inventory and the game opened the inventory instead. UE4SS cannot
-- swallow a key, but the ENGINE can be told to stop routing input to gameplay
-- at all -- UWidgetBlueprintLibrary::SetInputMode_UIOnlyEx, which is what the
-- game's own modal screens use. Our own bindings are UE4SS-level and still fire,
-- so we can read the key that the game no longer acts on.
--
-- EVERY EXIT PATH PUTS IT BACK, and there is a timeout on top, because the one
-- unacceptable outcome here is a player left unable to move.
local CAPTURE_TIMEOUT_MS = 8000
local inputHeld = false

function hold_input(inst, on)
    if on == inputHeld then return end
    local ok = pcall(function()
        local lib = StaticFindObject(WIDGET_LIB)
        if not (lib and lib:IsValid()) then error("no widget library", 0) end
        local controller = inst.menu:GetOwningPlayer()
        if controller == nil then error("no controller", 0) end
        if on then
            -- Focus the overlay when one is up: it only receives OnKeyDown,
            -- and therefore only reports a key, if it actually has focus.
            local focus = (capturing ~= nil and capturing.overlay ~= nil)
                and capturing.overlay or inst.page
            lib:SetInputMode_UIOnlyEx(controller, focus, 0, true)
        else
            lib:SetInputMode_GameAndUIEx(controller, nil, 0, false, false)
        end
    end)
    if ok then
        inputHeld = on
        log(on and "holding the keyboard while a key is chosen"
                or "gave the keyboard back")
    else
        log("could not " .. (on and "hold" or "release") ..
            " the keyboard — a key being chosen may also do its usual job")
    end
end

local function begin_capture(inst, control)
    -- Clicking the same button again gives up rather than trapping the player on
    -- a row that is waiting for something.
    local again = capturing ~= nil and capturing.control == control
    stop_capture()
    if again then return end
    -- The game's own modal, built the same way as every other native widget on
    -- this page. KeyConfigParam is deliberately LEFT NIL: the widget's own
    -- apply-logic then has no game action to write to, so putting it up cannot
    -- rebind one of the player's REAL game bindings.
    local overlay = native_widget(inst.menu, OVERLAY_CLASS)
    if overlay == nil or not canvas_fill(inst.page, overlay, OVERLAY_Z) then
        log("could not put up the game's press-a-key overlay -- not listening for a key")
        set_note(inst, label_for(control.entry) .. ": " ..
            ui_text("menu_press_key", "Press a key") .. " (unavailable)")
        return
    end

    -- THE OVERLAY ARRIVES IN THE GAME'S OWN WORDS. Dragón's first run showed it
    -- in Japanese: with KeyConfigParam nil the widget never runs the game's own
    -- text setup, so both of its blocks keep their design-time defaults. They
    -- are BP_PalTextBlock_C, so the same SetText_GDKInternal write every other
    -- label on this page uses applies -- a raw .Text = "string" crashes this
    -- game (rule 4).
    pcall(function()
        overlay.BP_PalTextBlock_Title:SetText_GDKInternal(true, label_for(control.entry))
    end)
    pcall(function()
        overlay.BP_PalTextBlock_Command:SetText_GDKInternal(true,
            ui_text("menu_press_key", "Press a key") .. "   ·   "
            .. ui_text("menu_press_key_cancel", "Esc to cancel"))
    end)

    capturing = { inst = inst, control = control, at = os.clock(), overlay = overlay }
    control.capturing = true
    hold_input(inst, true)
    show_control(control, nil)
    set_note(inst, label_for(control.entry) .. ": " .. ui_text("menu_press_key", "Press a key"))
    -- If no key ever arrives -- a build where our bindings cannot see one while
    -- the engine holds input -- the screen lets go by itself rather than leaving
    -- the player unable to play.
    local waiting = capturing
    pcall(function()
        ExecuteInGameThreadWithDelay(CAPTURE_TIMEOUT_MS, function()
            if capturing == waiting and waiting ~= nil then
                log("no key arrived while waiting -- giving up and letting go of the keyboard")
                pcall(stop_capture)
            end
        end)
    end)
end

-- ---------------------------------------------------------------------------
-- covering the menu while the page is up
-- ---------------------------------------------------------------------------
-- Every panel the ESC menu can have on screen is hidden and its own previous
-- visibility remembered, so closing restores exactly what was there. Which of
-- them were visible depends on the world, who is in it and the last tab used --
-- it is not something to assume.
local function cover_menu(inst)
    inst.covered = {}
    for _, name in ipairs(COVERED) do
        local w = inst.panels and inst.panels[name] or nil
        if alive(w) then
            local was = safe(function() return w:GetVisibility() end)
            inst.covered[#inst.covered + 1] = { w = w, was = was }
            set_vis(w, VIS_HIDE)
        end
    end
end

local function uncover_menu(inst)
    for _, entry in ipairs(inst.covered or {}) do
        if entry.was ~= nil then set_vis(entry.w, entry.was) else set_vis(entry.w, VIS_SHOW) end
    end
    inst.covered = {}
end

local function open_page(inst)
    if inst.pageOpen or inst.disposed or inst.superseded then return end
    if inst.page == nil then
        if inst.pageFailed then return end
        local ok, built = pcall(build_page, inst)
        if not ok or not built then
            inst.pageFailed = true
            -- The half-built page stays parented to the menu and dies with
            -- it. Removing it is what crashed DarnMenu twice.
            inst.page = nil
            log("the page could not be built (" .. tostring(ok and "incomplete" or built) .. ")")
            return
        end
        log("page built on first open")
    end
    inst.pageOpen = true
    -- ARMED ON OPEN, NOT WHEN A REBIND IS ASKED FOR. Registering ~150 key
    -- watchers is not instantaneous: UE4SS's own thread fires them a moment
    -- later, and arming them inside begin_capture meant that first burst landed
    -- while the screen was already waiting -- so a key nobody pressed was taken
    -- as the answer. Dragón: "i never pressed the d for rebind, it changed to
    -- that the first time automatically". Armed here, the same burst arrives
    -- while nothing is waiting and is ignored. (It has to be here rather than in
    -- build_page: arm_overlay_hook is declared below that, and a Lua local
    -- declared further down is not in scope above it.)
    arm_overlay_hook(1)
    -- What Cancel puts back. Taken on every open, so a second visit undoes only
    -- what was done on that visit.
    inst.snapshot = {}
    for _, entry in ipairs(Settings.Schema()) do
        if entry.key then inst.snapshot[entry.key] = Settings.Get(entry.key) end
    end
    cover_menu(inst)
    set_vis(inst.page, VIS_SHOW)
    -- Watch the rows only while they are on screen. The token means a page
    -- opened again later cannot be polled by an older loop as well.
    inst.pollToken = (inst.pollToken or 0) + 1
    poll_rows(inst, inst.pollToken)
    log("page opened")
end

local function close_page(inst)
    if not inst.pageOpen then return end
    inst.pageOpen = false
    stop_capture()
    if inst.disposed or inst.superseded then return end
    set_vis(inst.page, VIS_HIDE)
    uncover_menu(inst)
    log("page closed")
end

-- Put a whole set of values back at once. TWO PASSES, because the settings
-- refuse two actions sharing one key: restoring "Play = F8" while Tags is still
-- sitting on F8 is refused, and is fine on the second pass once Tags has moved.
local function apply_all(inst, values)
    local refused = {}
    for pass = 1, 2 do
        refused = {}
        for key, value in pairs(values) do
            if Settings.Get(key) ~= value then
                local good, why = Settings.Set(key, value)
                if good == nil then refused[key] = why end
            end
        end
        if next(refused) == nil then break end
    end
    for key, why in pairs(refused) do
        log("could not put " .. key .. " back: " .. tostring(why))
    end
    -- Every row re-reads the settings, and none of them is believed again until
    -- it has given the new value back (the settle guard).
    for _, control in ipairs(inst.controls or {}) do
        control.shown = Settings.Get(control.key)
        control.settled = false
        control.settleTries = 0
        show_control(control, control.shown)
    end
end

-- SAVE DOES NOT CLOSE. It used to, and Dragón read that as "save doesnt save,
-- instead quits the screen" -- which is exactly what it looks like when the only
-- confirmation you get is the screen disappearing.
local function save_page(inst)
    local saved = false
    pcall(function() saved = Settings.Flush() end)
    inst.changed = false
    -- SAVING MOVES THE POINT CANCEL GOES BACK TO. Without this, saving and then
    -- cancelling would undo the values that were just written to the file --
    -- the screen and the file would disagree about what the settings are.
    inst.snapshot = {}
    for _, entry in ipairs(Settings.Schema()) do
        if entry.key then inst.snapshot[entry.key] = Settings.Get(entry.key) end
    end
    log(saved and "settings saved to your file" or "settings applied for this session only")
    set_note(inst, ui_text("menu_saved", "Saved"))
end

local function cancel_page(inst)
    -- Everything the player did on this visit goes back, live, and nothing is
    -- written: the restores mark themselves dirty on the way through, which is
    -- exactly what Discard is for.
    if inst.snapshot ~= nil then apply_all(inst, inst.snapshot) end
    pcall(Settings.Discard)
    inst.changed = false
    log("changes on this visit were put back")
    close_page(inst)
end

local function defaults_page(inst)
    local defaults = {}
    for _, entry in ipairs(Settings.Schema()) do
        if entry.key ~= nil then defaults[entry.key] = entry.default end
    end
    apply_all(inst, defaults)
    inst.changed = true
    -- Left on screen on purpose: the player can still Cancel out of it, which
    -- they cannot do if this closed the page for them.
    set_note(inst, ui_text("menu_defaults", "Restore defaults"))
    log("every setting put back to its default (not saved yet)")
end

-- ---------------------------------------------------------------------------
-- clicks
-- ---------------------------------------------------------------------------
-- This hook fires for EVERY button of this class, which includes every native
-- ESC row. Anything we did not create must fall straight through untouched --
-- that is what keeps Options, Link Discord and Return to Title working.
local function on_click(Context)
    local btn = safe(function() return Context:get() end)
    local a = addr(btn)
    if a == nil then return end
    local record = ourButtons[a]
    if record == nil then return end
    -- The address is ours; is the WIDGET? The engine recycles addresses, so
    -- another mod's button can land on one of ours and would otherwise open our
    -- page instead of doing its own job.
    if identity(btn) ~= record.id then
        -- Forget the record ONLY if our own button is the one that went away.
        -- Clearing it on the strength of the failed probe is what broke our
        -- entry for the rest of the session: the foreign widget shares the
        -- address, so its mismatch says nothing about ours.
        if identity(record.ref) ~= record.id then ourButtons[a] = nil end
        log("a click arrived on one of our addresses but the widget there is not ours -- ignored")
        return
    end
    local inst = instances[record.menuAddr]
    if inst == nil or inst.disposed then return end
    if record.kind == "close" then
        pcall(close_page, inst)
    elseif record.kind == "save" then
        pcall(save_page, inst)
    elseif record.kind == "cancel" then
        pcall(cancel_page, inst)
    elseif record.kind == "defaults" then
        pcall(defaults_page, inst)
    elseif record.kind == "key" then
        if inst.pageOpen and record.control ~= nil then
            pcall(begin_capture, inst, record.control)
        end
    else
        pcall(open_page, inst)
    end
end

local function on_destruct(Context)
    local a = addr(safe(function() return Context:get() end))
    if a == nil then return end
    local inst = instances[a]
    if inst == nil then return end
    inst.disposed = true
    -- Let go of the keyboard first, while this menu is still the one the engine
    -- knows about. A player left in UI-only input mode cannot move.
    if capturing ~= nil and capturing.inst == inst then pcall(stop_capture) end
    -- Forget our buttons on this menu. The widgets themselves are the engine's
    -- to free, and touching them now is exactly the crash rule 3 is about.
    for btnAddr, record in pairs(ourButtons) do
        if record.menuAddr == a then ourButtons[btnAddr] = nil end
    end
    instances[a] = nil
end

-- Arming happens on the first successful inject, not at load: on a cold boot
-- WBP_MenuESC_C is not loaded yet, RegisterHook returns nil ids, and the hook
-- silently never exists. Verified ids, retried until they come back.
local function arm_hooks()
    if not destructArmed then
        local ok, preId, postId = pcall(RegisterHook, MENU_CLASS .. ":Destruct", on_destruct)
        if ok and preId ~= nil and postId ~= nil then
            destructArmed = true
            log("destruct hook armed")
        else
            log("destruct hook did not arm -- retrying on the next menu")
        end
    end
    if hooksArmed then return end
    local ok = pcall(RegisterHook, CLICK_EVENT, on_click)
    hooksArmed = true
    log("click hook " .. (ok and "armed" or "FAILED -- the entry will not respond"))
end

-- ---------------------------------------------------------------------------
-- placing the entry
-- ---------------------------------------------------------------------------
local function place_entry(inst, btn)
    local column = find_by_name(inst.menu, BOTTOM_COLUMN)
    if alive(column) then
        if shelfLift == nil then
            shelfLift = 0
            local baseTop = safe(function() return column.Slot:GetOffsets().Top end)
            local stackTop = bottom_stack_top(inst.buttonCanvas, nil)
            if type(baseTop) == "number" and type(stackTop) == "number" and stackTop < baseTop then
                local rows = math.ceil((baseTop - stackTop) / (ENTRY_H + ENTRY_GAP))
                shelfLift = rows * (ENTRY_H + ENTRY_GAP)
                log(string.format("another mod's row is already parked above the column " ..
                    "(%.0f vs %.0f) -- sitting %d row(s) higher", stackTop, baseTop, rows))
            end
        end
        if canvas_add_above_stretch(column, btn, ENTRY_GAP + shelfLift, ENTRY_H, ENTRY_Z) then
            log(string.format("entry placed above %s (lift %.0f)", BOTTOM_COLUMN, shelfLift))
            return true
        end
    end
    -- Visible in the wrong place beats absent.
    if canvas_add(inst.buttonCanvas, btn, FALLBACK_X, FALLBACK_Y, FALLBACK_W, ENTRY_H, ENTRY_Z) then
        log("entry placed at the fallback position (the button column could not be read)")
        return true
    end
    return false
end

local function inject(menu)
    local a = addr(menu)
    if a == nil then return false, "the menu has no address" end
    if instances[a] ~= nil then return true end          -- already done

    local widgetTree = safe(function() return menu.WidgetTree end)
    local pageRoot = find_by_name(menu, PAGE_ROOT)
    if not alive(pageRoot) and widgetTree then
        -- Generated root names are not a stable blueprint contract; the tree's
        -- own root is, if a game update ever renames CanvasPanel_0.
        pageRoot = safe(function() return widgetTree.RootWidget end)
    end
    local buttonCanvas = find_by_name(menu, BUTTON_CANVAS)
    if not (widgetTree ~= nil and alive(pageRoot) and alive(buttonCanvas)) then
        return false, string.format("the menu's widget tree is not ready (tree=%s root=%s %s=%s)",
            tostring(widgetTree ~= nil), tostring(alive(pageRoot)),
            BUTTON_CANVAS, tostring(alive(buttonCanvas)))
    end

    -- Every earlier menu is on its way out with our widgets still attached.
    -- Mark them so nothing of ours ever writes to one again.
    for otherAddr, other in pairs(instances) do
        if otherAddr ~= a then other.superseded = true end
    end

    local closeLabel = "Close"
    pcall(function() closeLabel = require("Locale").T("menu_close") end)

    local inst = {
        addr = a,
        menu = menu,
        widgetTree = widgetTree,
        pageRoot = pageRoot,
        buttonCanvas = buttonCanvas,
        panels = (function()
            -- Looked up once per menu: several of these are not properties on
            -- the class, so each miss costs a tree walk and doing it on every
            -- open would repeat that for nothing.
            local found = {}
            for _, name in ipairs(COVERED) do found[name] = find_by_name(menu, name) end
            return found
        end)(),
        textClass = text_class(menu),
        closeLabel = closeLabel,
        pageOpen = false,
    }

    local entry = native_button(menu, ENTRY_LABEL)
    if entry == nil then
        return false, "the game's button blueprint was not ready"
    end
    if not place_entry(inst, entry) then
        return false, "the entry button could not be placed"
    end
    local entryAddr = addr(entry)
    local entryId = identity(entry)
    if entryAddr == nil or entryId == nil then
        -- A visible button with no identity can never be dispatched safely: it
        -- would sit there looking clickable and do nothing, or inherit
        -- somebody else's action later.
        return false, "the entry button has no readable identity"
    end
    inst.entry = entry
    ourButtons[entryAddr] = { ref = entry, id = entryId, menuAddr = a, kind = "open" }
    instances[a] = inst
    arm_hooks()
    log("entry injected into the ESC menu")
    return true
end

-- ---------------------------------------------------------------------------
-- init
-- ---------------------------------------------------------------------------
function Menu.Init()
    NotifyOnNewObject(MENU_CLASS, function(menu)
        -- Stamp the newest menu HERE, on the notification itself, so it is
        -- already current when an older menu's delayed build wakes up.
        local a = addr(menu)
        newestMenu = a or newestMenu
        -- RULE 1: nothing is touched from inside this callback.
        ExecuteInGameThreadWithDelay(BUILD_DELAY_MS, function()
            if not alive(menu) then return end
            -- ESC can be pressed again before we wake. Injecting now would
            -- hang our entry on a menu the player has already moved past.
            if newestMenu ~= nil and newestMenu ~= addr(menu) then return end
            local ok, done, reason = pcall(inject, menu)
            if not ok or not done then
                log("could not add the entry: " .. tostring(ok and reason or done or "unknown"))
            end
        end)
    end)
    log("watching for the pause menu")
end

return Menu
