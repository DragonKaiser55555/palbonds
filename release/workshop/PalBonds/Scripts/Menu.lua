local Logger = require("Logger")
local Settings = require("Settings")

local Menu = {}

local MENU_CLASS   = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C"
local BUTTON_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC_Button_S"
local BUTTON_CLASS = BUTTON_ASSET .. ".WBP_MenuESC_Button_S_C"

local CLICK_EVENT  = BUTTON_CLASS ..
    ":BndEvt__WBP_MenuESC_Button_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"
local WIDGET_LIB   = "/Script/UMG.Default__WidgetBlueprintLibrary"

local BUTTON_CANVAS  = "Canvas_Buttons"
local BOTTOM_COLUMN  = "VerticalBox_293"
local PAGE_ROOT      = "CanvasPanel_0"

local COVERED = {
    "Canvas_Buttons", "Canvas_Content", "Canvas_TabSet", "WorldOptionCanvas",
    "CanvasPanelPlayerList", "CanvasPanelServerInfo", "CanvasPanel_MultiTips",
}

local OPTION_DIR = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/"
local ROW_CLASS = OPTION_DIR .. "WBP_OptionSettings_ListContent.WBP_OptionSettings_ListContent_C"

local WINDOW_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/Common/WBP_PalCommonWindow.WBP_PalCommonWindow_C"

local TEXT_SOURCES   = { "BPPalTextBlock_WorldName", "Text_InviteCode" }

local ENTRY_LABEL  = "PalBonds"
local BUILD_DELAY_MS = 50
local ENTRY_H, ENTRY_GAP, ENTRY_Z = 56, 8, 30

local FALLBACK_X, FALLBACK_Y, FALLBACK_W = 60, 640, 400

local VIS_SHOW, VIS_HIDE = 0, 1

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

local function identity(o)
    if not alive(o) then return nil end
    return safe(function() return o:GetFullName() end)
end

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

        pcall(function()
            local f = tb.Font
            f.Size = size
            tb:SetFont(f)
        end)
    end
    return tb
end

local function native_widget(menu, classPath)
    if not alive(menu) then return nil end
    local w = safe(function()
        local lib = StaticFindObject(WIDGET_LIB)
        if not lib or not lib:IsValid() then return nil end
        local cls = StaticFindObject(classPath)
        if not cls or not cls:IsValid() then

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

local function native_button(menu, label)
    local btn = native_widget(menu, BUTTON_CLASS)
    if btn == nil then return nil end

    local labelled = pcall(function() btn.Text_Main:SetText_GDKInternal(true, label) end)
    if not labelled then
        log("could not label the \"" .. tostring(label) .. "\" button")
    end
    return btn
end

local instances = {}
local newestMenu = nil
local hooksArmed = false
local destructArmed = false

local ourButtons = {}

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

local PAGE_Z        = 60

local WIN_L, WIN_T, WIN_R, WIN_B = 300, 96, 300, 56
local TITLE_Y       = 140
local HINT_Y        = 192
local LIST_L, LIST_T, LIST_R, LIST_B = 344, 238, 344, 188
local NOTE_UP       = 140
local BUTTONS_UP    = 76
local BUTTON_W      = 330
local BUTTON_GAP    = 16

local JUSTIFY_CENTER = 1

local ROW_H         = 48
local ROW_GAP       = 8
local SECTION_TOP   = 22
local TITLE_FONT    = 32
local ROW_FONT      = 17
local SECTION_FONT  = 19
local HINT_FONT     = 15
local KEY_BUTTON_W  = 210
local POLL_MS       = 150

local ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT = 1, 2, 3

local SCROLLBAR_GAP = 28

local NOT_CAPTURABLE = { "MOUSE", "ESCAPE", "BACKSPACE", "SHIFT", "CONTROL", "ALT", "WIN", "LOCK", "TAB" }

local function capturable(name)
    if type(name) ~= "string" or name == "" then return false end
    local upper = name:upper()
    for _, pattern in ipairs(NOT_CAPTURABLE) do
        if upper:find(pattern, 1, true) then return false end
    end
    return true
end

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
        if v == value then return i - 1 end
    end
    return 0
end

local LANGUAGE_NAMES = {
    en = "English", es = "Español", fr = "Français", de = "Deutsch",
    it = "Italiano", pl = "Polski", pt = "Português", ru = "Русский",
    tr = "Türkçe", vi = "Tiếng Việt", th = "ไทย", id = "Indonesia",
    ja = "日本語", ko = "한국어", ["zh-hans"] = "简体中文", ["zh-hant"] = "繁體中文",
}

local function choices_for(entry)

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

local function sized(inst, content, width, height)
    local box = construct("/Script/UMG.SizeBox", inst.widgetTree)
    if box == nil then return nil end
    if width then pcall(function() box:SetWidthOverride(width) end) end
    if height then pcall(function() box:SetHeightOverride(height) end) end
    pcall(function() box:SetContent(content) end)
    return box
end

local function show_slider_number(control, value)
    if not alive(control.valueText) then return end
    local text = tostring(value)
    if pcall(function() control.valueText:SetText_GDKInternal(true, text) end) then return end
    pcall(function() control.valueText:SetText(FText(text)) end)
end

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

local function control_value(control)

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

local SETTLE_TRIES = 5

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

    if good ~= value then show_control(control, good) end
    if control.key == "Language" then pcall(refresh_texts, inst) end

    inst.changed = true
end

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
    inst.noteText = nil
end

local function poll_rows(inst, token)
    if inst.disposed or inst.superseded or not inst.pageOpen then return end
    if inst.pollToken ~= token then return end
    for _, control in ipairs(inst.controls or {}) do
        pcall(sync_control, inst, control)
    end
    pcall(function()
        ExecuteInGameThreadWithDelay(POLL_MS, function() poll_rows(inst, token) end)
    end)
end

local function add_to_list(inst, list, child, topPad)
    return (pcall(function()
        local slot = list:AddChildToVerticalBox(child)
        if slot ~= nil and slot:IsValid() then
            slot:SetPadding({ Left = 0, Top = topPad or 0, Right = 0, Bottom = ROW_GAP })
        end
    end))
end

local function add_key_row(inst, list, entry)
    local line = construct("/Script/UMG.Overlay", inst.widgetTree)
    if line == nil then return false end
    local box = sized(inst, line, nil, ROW_H)
    if box == nil or not add_to_list(inst, list, box) then return false end

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

            slot:SetPadding({ Left = 0, Top = 0, Right = SCROLLBAR_GAP, Bottom = 0 })
        end
    end)
    if not placed then return false end

    local control = { key = entry.key, entry = entry, kind = "key", button = button }
    show_control(control, nil)
    local a, id = addr(button), identity(button)
    if a == nil or id == nil then

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

    pcall(function() row.BP_PalTextBlock_Name:SetText_GDKInternal(true, label_for(entry)) end)
    local nameWidget = safe(function() return row.BP_PalTextBlock_Name end)
    if alive(nameWidget) then
        inst.texts[#inst.texts + 1] = { w = nameWidget, entry = entry }

        if inst.rowFont == nil then
            inst.rowFont = safe(function() return nameWidget.Font.Size end)
        end
    end

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

    set_vis(page, VIS_HIDE)
    inst.page = page
    inst.controls = {}

    inst.texts = {}

    local dim = construct("/Script/UMG.Image", inst.widgetTree)
    if dim ~= nil then
        pcall(function() dim:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.82 }) end)
        canvas_fill(page, dim, 0)
    end

    local window = native_widget(inst.menu, WINDOW_CLASS)
    if window ~= nil then
        set_vis(window, 4)
        canvas_inset(page, window, WIN_L, WIN_T, WIN_R, WIN_B, 1)
    else
        log("this build has no common window frame -- the page is drawn without one")
    end

    local title = center_text(make_text(inst, ENTRY_LABEL, TITLE_FONT))
    if title ~= nil then canvas_inset(page, title, WIN_L, TITLE_Y, WIN_R, 0, 3) end

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

    local built, skipped = 0, 0
    for _, entry in ipairs(Settings.Schema()) do
        if inst.disposed or inst.superseded then return false end
        if entry.section then
            add_section(inst, list, entry)
        elseif entry.key then

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

    local tail = construct("/Script/UMG.SizeBox", inst.widgetTree)
    if tail ~= nil then
        pcall(function() tail:SetHeightOverride(ROW_H) end)
        pcall(function() list:AddChildToVerticalBox(tail) end)
    end

    inst.note = center_text(make_text(inst, "", HINT_FONT))
    if inst.note ~= nil then canvas_inset(page, inst.note, WIN_L, 0, WIN_R, NOTE_UP, 3) end

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

local OVERLAY_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/"
    .. "WBP_OptionSettingsOverLayWindow.WBP_OptionSettingsOverLayWindow_C"
local OVERLAY_Z = 90
local OVERLAY_HOOK_RETRY_MS = 4000
local OVERLAY_HOOK_MAX_ROUNDS = 30

local capturing = nil
local overlayHookArmed = false

local hold_input

local function name_text(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local s = safe(function() return v:ToString() end)
    if s == nil then return nil end
    s = tostring(s)
    if s == "" or s == "None" then return nil end
    return s
end

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

local key_pressed

function key_pressed(name)
    local waiting = capturing
    if waiting == nil then return end
    local inst, control = waiting.inst, waiting.control
    if inst.disposed or inst.superseded or not inst.pageOpen then stop_capture() return end
    capturing = nil
    control.capturing = false

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

    for _, covered in ipairs(inst.covered or {}) do
        set_vis(covered.w, VIS_HIDE)
    end
end

local function arm_overlay_hook(round)
    round = round or 1
    if overlayHookArmed then return end

    local ok, err = pcall(function()
        RegisterHook(OVERLAY_CLASS .. ":OnKeySetting", function(Context, NewKey)
            local waiting = capturing
            if waiting == nil or waiting.overlay == nil then return end
            local who = safe(function() return Context:get() end)
            if who == nil then return end

            local mine = safe(function() return waiting.overlay:GetAddress() end)
            local fired = safe(function() return who:GetAddress() end)
            if mine == nil or fired == nil or mine ~= fired then return end

            local key = safe(function() return NewKey:get() end)
            local name = key ~= nil and name_text(safe(function() return key.KeyName end)) or nil
            if name == nil then
                log("the overlay reported a key we could not read -- ignoring it")
                return
            end

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

function Menu.WaitingForKey()
    return capturing ~= nil
end

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

    local again = capturing ~= nil and capturing.control == control
    stop_capture()
    if again then return end

    local overlay = native_widget(inst.menu, OVERLAY_CLASS)
    if overlay == nil or not canvas_fill(inst.page, overlay, OVERLAY_Z) then
        log("could not put up the game's press-a-key overlay -- not listening for a key")
        set_note(inst, label_for(control.entry) .. ": " ..
            ui_text("menu_press_key", "Press a key") .. " (unavailable)")
        return
    end

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

            inst.page = nil
            log("the page could not be built (" .. tostring(ok and "incomplete" or built) .. ")")
            return
        end
        log("page built on first open")
    end
    inst.pageOpen = true

    arm_overlay_hook(1)

    inst.snapshot = {}
    for _, entry in ipairs(Settings.Schema()) do
        if entry.key then inst.snapshot[entry.key] = Settings.Get(entry.key) end
    end
    cover_menu(inst)
    set_vis(inst.page, VIS_SHOW)

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

    for _, control in ipairs(inst.controls or {}) do
        control.shown = Settings.Get(control.key)
        control.settled = false
        control.settleTries = 0
        show_control(control, control.shown)
    end
end

local function save_page(inst)
    local saved = false
    pcall(function() saved = Settings.Flush() end)
    inst.changed = false

    inst.snapshot = {}
    for _, entry in ipairs(Settings.Schema()) do
        if entry.key then inst.snapshot[entry.key] = Settings.Get(entry.key) end
    end
    log(saved and "settings saved to your file" or "settings applied for this session only")
    set_note(inst, ui_text("menu_saved", "Saved"))
end

local function cancel_page(inst)

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

    set_note(inst, ui_text("menu_defaults", "Restore defaults"))
    log("every setting put back to its default (not saved yet)")
end

local function on_click(Context)
    local btn = safe(function() return Context:get() end)
    local a = addr(btn)
    if a == nil then return end
    local record = ourButtons[a]
    if record == nil then return end

    if identity(btn) ~= record.id then

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

    if capturing ~= nil and capturing.inst == inst then pcall(stop_capture) end

    for btnAddr, record in pairs(ourButtons) do
        if record.menuAddr == a then ourButtons[btnAddr] = nil end
    end
    instances[a] = nil
end

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

    if canvas_add(inst.buttonCanvas, btn, FALLBACK_X, FALLBACK_Y, FALLBACK_W, ENTRY_H, ENTRY_Z) then
        log("entry placed at the fallback position (the button column could not be read)")
        return true
    end
    return false
end

local function inject(menu)
    local a = addr(menu)
    if a == nil then return false, "the menu has no address" end
    if instances[a] ~= nil then return true end

    local widgetTree = safe(function() return menu.WidgetTree end)
    local pageRoot = find_by_name(menu, PAGE_ROOT)
    if not alive(pageRoot) and widgetTree then

        pageRoot = safe(function() return widgetTree.RootWidget end)
    end
    local buttonCanvas = find_by_name(menu, BUTTON_CANVAS)
    if not (widgetTree ~= nil and alive(pageRoot) and alive(buttonCanvas)) then
        return false, string.format("the menu's widget tree is not ready (tree=%s root=%s %s=%s)",
            tostring(widgetTree ~= nil), tostring(alive(pageRoot)),
            BUTTON_CANVAS, tostring(alive(buttonCanvas)))
    end

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

        return false, "the entry button has no readable identity"
    end
    inst.entry = entry
    ourButtons[entryAddr] = { ref = entry, id = entryId, menuAddr = a, kind = "open" }
    instances[a] = inst
    arm_hooks()
    log("entry injected into the ESC menu")
    return true
end

function Menu.Init()
    NotifyOnNewObject(MENU_CLASS, function(menu)

        local a = addr(menu)
        newestMenu = a or newestMenu

        ExecuteInGameThreadWithDelay(BUILD_DELAY_MS, function()
            if not alive(menu) then return end

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
