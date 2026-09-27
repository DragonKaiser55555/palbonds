// 2026-09-25: the PalBonds entry in the game's own pause menu (Menu.lua).
//
// Everything here is UI work inside a live native menu, which is the most
// crash-prone thing this project does -- and a mistake costs Dragón a whole
// test run to find. So the rules that exist BECAUSE of a crash are the ones
// this suite pins down, not just the happy path:
//
//   A. Nothing is built inside the construction callback: the notification only
//      schedules, and it is the delayed pass that touches the menu (AV writing
//      0x80 if it does not wait).
//   B. The entry goes on the CANVAS above the bottom button column, never into
//      the column itself (adding to a VerticalBox reflows it on the engine's
//      next layout pass -- four CTDs in the reference mod), and it mirrors the
//      column's stretched anchors as OFFSETS.
//   C. The shared shelf: a row another menu mod already parked above the column
//      pushes ours one row higher instead of under it.
//   D. The page is built on the FIRST CLICK, never ahead of time (pre-building
//      per menu open was the reference mod's seven-incident crash family).
//   E. Click dispatch: the hook is shared with every native ESC row, so only
//      our own buttons act and a recycled address is refused.
//   F. Supersession: ESC pressed twice does not inject into the menu the player
//      has already moved past, and nothing writes to the older one again.
//   G. Destruct: the menu and its buttons are forgotten, and never touched.
//
// Usage: node menutest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node menutest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');
let failures = 0;

function expect(label, actual, pred) {
  const ok = typeof pred === 'function' ? pred(actual) : actual === pred;
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

const MENU_CLASS = '/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C';
const CLICK_EVENT = '/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC_Button_S.WBP_MenuESC_Button_S_C'
  + ':BndEvt__WBP_MenuESC_Button_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature';

// A UMG stand-in: widgets, canvas slots, the ESC menu's own tree, and the two
// factories Menu.lua builds through. Deliberately literal about the parts the
// real crashes came from -- a canvas that can REFUSE a child (it returns
// nothing, not an error), and a stretch-anchored column slot made of offsets.
const FAKE_UMG = [
  '__ADDR = 0',
  'function __slot(anchors, align, off)',
  '  local s = {}',
  '  s.__anchors = anchors or { Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } }',
  '  s.__align = align or { X = 0, Y = 0 }',
  '  s.__off = off or { Left = 0, Top = 0, Right = 0, Bottom = 0 }',
  '  function s:IsValid() return true end',
  '  function s:GetAnchors() return self.__anchors end',
  '  function s:GetAlignment() return self.__align end',
  '  function s:GetOffsets() return self.__off end',
  '  function s:SetAnchors(a) self.__anchors = a end',
  '  function s:SetAlignment(a) self.__align = a end',
  '  function s:SetOffsets(o) self.__off = o end',
  '  function s:SetPosition(p) self.__pos = p end',
  '  function s:SetSize(z) self.__size = z end',
  '  function s:SetZOrder(z) self.__z = z end',
  '  function s:SetPadding(pad) self.__pad = pad end',
  '  function s:SetSize(v) self.__size = v end',
  '  function s:SetVerticalAlignment(v) self.__vAlign = v end',
  '  function s:SetHorizontalAlignment(v) self.__hAlign = v end',
  '  return s',
  'end',
  'function __w(name)',
  '  __ADDR = __ADDR + 1',
  '  local w = { __name = name, __children = {}, __vis = 0, __addr = __ADDR, __dead = false }',
  // Unreal's own object number, independent of the pointer: it is what makes a
  // recycled address still distinguishable, so the fake must not fold it in.
  '  w.__serial = __ADDR',
  '  function w:IsValid() return not self.__dead end',
  '  function w:GetAddress() return self.__addr end',
  '  function w:GetFullName() return self.__name .. "#" .. self.__serial end',
  '  function w:GetFName() return { ToString = function() return self.__name end } end',
  '  function w:GetChildrenCount() return #self.__children end',
  '  function w:GetChildAt(i) return self.__children[i + 1] end',
  '  function w:GetParent() return self.__parent end',
  '  function w:SetVisibility(v) self.__vis = v end',
  '  function w:GetVisibility() return self.__vis end',
  '  function w:SetColorAndOpacity(c) self.__color = c end',
  '  function w:SetText_GDKInternal(_, s) self.__text = s end',
  '  function w:SetFont(f) self.__font = f end',
  '  function w:GetClass() return __TEXTCLASS end',
  '  function w:RemoveFromParent() self.__removed = true end',
  // AddChildToCanvas returns NOTHING when the engine refuses the add. That is
  // the shape that produced a null-pointer store on 2026-07-27, so the fake
  // reproduces it rather than erroring.
  '  function w:AddChildToCanvas(child)',
  '    if self.__refuse then return nil end',
  '    self.__children[#self.__children + 1] = child',
  '    child.__parent = self',
  '    child.Slot = __slot()',
  // A real UPanelSlot knows its panel, and taking a child back out is how the
  // press-a-key overlay is removed when the capture ends.
  '    child.Slot.Parent = self',
  '    return child.Slot',
  '  end',
  '  function w:RemoveChild(child)',
  '    for i, c in ipairs(self.__children) do',
  '      if c == child then table.remove(self.__children, i); child.__parent = nil; child.Slot = nil; return true end',
  '    end',
  '    return false',
  '  end',
  // Containers of our OWN (SizeBox, ScrollBox, VerticalBox). Adding to these is
  // ordinary UMG -- the reflow rule is about the GAME's live panels.
  '  function w:SetHeightOverride(h) self.__height = h end',
  '  function w:SetWidthOverride(x) self.__width = x end',
  '  function w:SetContent(c) self.__content = c; if c then c.__parent = self end end',
  '  function w:AddChild(c)',
  '    self.__children[#self.__children + 1] = c',
  '    c.__parent = self',
  '    c.Slot = __slot()',
  '    return c.Slot',
  '  end',
  '  function w:AddChildToVerticalBox(c) return w.AddChild(self, c) end',
  '  function w:AddChildToHorizontalBox(c) return w.AddChild(self, c) end',
  '  function w:AddChildToOverlay(c) return w.AddChild(self, c) end',
  '  w.Font = { Size = 12 }',
  '  return w',
  'end',
  '__TEXTCLASS = __w("BP_PalTextBlock_C")',
  '__CANVASCLASS = __w("CanvasPanelClass")',
  '__IMAGECLASS = __w("ImageClass")',
  '__BTNCLASS = __w("ButtonClass")',
  '__SIZECLASS = __w("SizeBoxClass")',
  '__SCROLLCLASS = __w("ScrollBoxClass")',
  '__VBOXCLASS = __w("VerticalBoxClass")',
  '__HBOXCLASS = __w("HorizontalBoxClass")',
  '__OVERLAYCLASS = __w("OverlayClass")',
  '__PLAYER = __w("PlayerController")',
  '__BUILT = { buttons = 0, canvas = 0, image = 0, text = 0, rows = 0, smallButtons = 0, window = 0 }',
  'function __button()',
  '  local b = __w("WBP_MenuESC_Button_S_C")',
  '  b.Text_Main = __w("Text_Main")',
  '  __BUILT.buttons = __BUILT.buttons + 1',
  '  return b',
  'end',
  // THE GAME'S OWN SETTINGS ROW. One class, three shapes -- the fake answers the
  // same methods and the same read-back fields the real one does, so the page's
  // seeding, reading and snap-back are all exercised here.
  '__ROWCLASS = __w("ListContentClass")',
  'function __row()',
  '  local r = __w("WBP_OptionSettings_ListContent_C")',
  '  r.BP_PalTextBlock_Name = __w("BP_PalTextBlock_Name")',
  '  local sw = __w("Switch"); sw.CurrentIsOn = false',
  '  local sl = __w("Slider"); sl.CurrentValue = 0; sl.BP_PalTextBlock_Value = __w("Value")',
  '  local lr = __w("LR"); lr.Current = 0',
  '  r.WBP_OptionSettings_ListContentSwitch = sw',
  '  r.WBP_OptionSettings_ListContentSlider = sl',
  '  r.WBP_OptionSettings_ListContentLR = lr',
  '  function r:SetSwitcher(on) r.__shape = "switch"; sw.CurrentIsOn = on end',
  '  function r:SetSlider(v, lo, hi, step, useStep)',
  '    r.__shape = "slider"; r.__range = { lo, hi, step, useStep }',
  '    -- __NOT_READY stands in for a native row that has not laid out yet: it',
  '    -- keeps whatever it already holds and ignores what we write.',
  '    if not __NOT_READY then sl.CurrentValue = v end',
  '  end',
  '  function r:SetSelecter_String(labels, index)',
  '    r.__shape = "lr"; lr.__labels = labels; lr.Current = index',
  '  end',
  '  __BUILT.rows = __BUILT.rows + 1',
  '  return r',
  'end',
  // The game's small option button -- what a rebind row shows the key on.
  '__SMALLCLASS = __w("MenuButtonClass")',
  'function __smallbutton()',
  '  local b = __w("WBP_OptionSettings_MenuButton_C")',
  '  b.BP_PalTextBlock_Name = __w("BP_PalTextBlock_Name")',
  '  __BUILT.smallButtons = __BUILT.smallButtons + 1',
  '  return b',
  'end',
  '__WINDOWCLASS = __w("CommonWindowClass")',
  // THE GAME'S OWN "PRESS A KEY" OVERLAY. Six probe rounds on 2026-09-26 proved
  // this is how a key is captured without a single RegisterKeyBind: the widget
  // takes focus, receives OnKeyDown, and hands the key to OnKeySetting as a
  // plain hook parameter. Every instance built is remembered so a test can fire
  // the hook as the engine would -- and can fire it as a DIFFERENT instance, to
  // prove the game's own options screen cannot drive our rows.
  '__KEYOVERLAYCLASS = __w("KeyOverlayClass")',
  '__KEYOVERLAYS = {}',
  'function __key_overlay() return __KEYOVERLAYS[#__KEYOVERLAYS] end',
  'function __fire_key(name, who)',
  '  local cb, path',
  '  for k, v in pairs(__HOOKCB) do',
  '    if tostring(k):find("OnKeySetting", 1, true) then cb = v; path = k end',
  '  end',
  '  if cb == nil then return "no hook" end',
  '  who = who or __key_overlay()',
  '  if who == nil then return "no overlay" end',
  '  local fkey = { KeyName = { ToString = function() return name end } }',
  '  cb({ get = function() return who end }, { get = function() return fkey end })',
  '  return "fired"',
  'end',
  // Holding the keyboard is the riskiest thing this screen does -- a player left
  // in UI-only input mode cannot move -- so the fake records the mode and the
  // tests check it is always handed back.
  '__INPUT_MODE = "game"',
  '__LIB = __w("WidgetBlueprintLibrary")',
  'function __LIB:SetInputMode_UIOnlyEx(pc, widget, lock, flush) __INPUT_MODE = "ui" end',
  'function __LIB:SetInputMode_GameAndUIEx(pc, widget, lock, flush, hide) __INPUT_MODE = "game" end',
  'function __LIB:Create(owner, cls, player)',
  '  if cls == __ROWCLASS then return __row() end',
  '  if cls == __SMALLCLASS then return __smallbutton() end',
  '  if cls == __WINDOWCLASS then __BUILT.window = __BUILT.window + 1; return __w("WBP_PalCommonWindow_C") end',
  '  if cls == __KEYOVERLAYCLASS then',
  '    local o = __w("WBP_OptionSettingsOverLayWindow_C")',
  '    o.BP_PalTextBlock_Title = __w("BP_PalTextBlock_Title")',
  '    o.BP_PalTextBlock_Command = __w("BP_PalTextBlock_Command")',
  '    __KEYOVERLAYS[#__KEYOVERLAYS + 1] = o',
  '    return o',
  '  end',
  '  return __button()',
  'end',
  'StaticFindObject = function(p)',
  '  if p == "/Script/UMG.Default__WidgetBlueprintLibrary" then return __LIB end',
  '  if p == "/Script/UMG.CanvasPanel" then return __CANVASCLASS end',
  '  if p == "/Script/UMG.Image" then return __IMAGECLASS end',
  '  if tostring(p):find("WBP_MenuESC_Button_S_C", 1, true) then return __BTNCLASS end',
  '  if tostring(p):find("WBP_OptionSettings_ListContent_C", 1, true) then return __ROWCLASS end',
  '  if tostring(p):find("WBP_OptionSettings_MenuButton_C", 1, true) then return __SMALLCLASS end',
  '  if tostring(p):find("WBP_PalCommonWindow_C", 1, true) then return __WINDOWCLASS end',
  '  if tostring(p):find("WBP_OptionSettingsOverLayWindow_C", 1, true) then return __KEYOVERLAYCLASS end',
  '  if p == "/Script/UMG.HorizontalBox" then return __HBOXCLASS end',
  '  if p == "/Script/UMG.Overlay" then return __OVERLAYCLASS end',
  '  if p == "/Script/UMG.SizeBox" then return __SIZECLASS end',
  '  if p == "/Script/UMG.ScrollBox" then return __SCROLLCLASS end',
  '  if p == "/Script/UMG.VerticalBox" then return __VBOXCLASS end',
  '  return nil',
  'end',
  'StaticConstructObject = function(cls, outer)',
  '  if cls == __CANVASCLASS then __BUILT.canvas = __BUILT.canvas + 1; return __w("CanvasPanel") end',
  '  if cls == __IMAGECLASS then __BUILT.image = __BUILT.image + 1; return __w("Image") end',
  '  if cls == __TEXTCLASS then __BUILT.text = __BUILT.text + 1; return __w("TextBlock") end',
  '  if cls == __SIZECLASS then return __w("SizeBox") end',
  '  if cls == __SCROLLCLASS then return __w("ScrollBox") end',
  '  if cls == __VBOXCLASS then return __w("VerticalBox") end',
  '  if cls == __HBOXCLASS then return __w("HorizontalBox") end',
  '  if cls == __OVERLAYCLASS then return __w("Overlay") end',
  '  return nil',
  'end',
  'LoadAsset = function() return true end',
  // The ESC menu. VerticalBox_293 and CanvasPanel_0 are NOT properties on the
  // real class (checked against this build's object dump), so they are reachable
  // only through the widget tree -- exactly as in game.
  'function __menu()',
  '  local m = __w("WBP_MenuESC_C")',
  '  m.Canvas_Buttons = __w("Canvas_Buttons")',
  '  m.Canvas_Content = __w("Canvas_Content")',
  '  m.Canvas_TabSet = __w("Canvas_TabSet")',
  '  m.WorldOptionCanvas = __w("WorldOptionCanvas")',
  '  m.CanvasPanelPlayerList = __w("CanvasPanelPlayerList")',
  '  m.CanvasPanelServerInfo = __w("CanvasPanelServerInfo")',
  '  m.CanvasPanel_MultiTips = __w("CanvasPanel_MultiTips")',
  '  m.Text_InviteCode = __w("Text_InviteCode")',
  '  local root = __w("CanvasPanel_0")',
  '  local column = __w("VerticalBox_293")',
  '  column.__parent = m.Canvas_Buttons',
  '  column.Slot = __slot({ Minimum = { X = 0, Y = 1 }, Maximum = { X = 1, Y = 1 } },',
  '                       { X = 0, Y = 0 },',
  '                       { Left = 60, Top = -120, Right = 60, Bottom = 56 })',
  '  m.Canvas_Buttons.__children = { column }',
  '  root.__children = { m.Canvas_Buttons, m.Canvas_Content }',
  '  local tree = __w("WidgetTree")',
  '  tree.RootWidget = root',
  '  m.WidgetTree = tree',
  '  m.__column = column',
  '  function m:GetOwningPlayer() return __PLAYER end',
  '  return m',
  'end',
  // Park a row of somebody else's above the column, bottom-anchored, the way
  // another menu mod's entry sits there.
  'function __neighbour(menu, top)',
  '  local other = __w("SomeOtherModRow")',
  '  other.Slot = __slot({ Minimum = { X = 0, Y = 1 }, Maximum = { X = 1, Y = 1 } },',
  '                      { X = 0, Y = 0 },',
  '                      { Left = 60, Top = top, Right = 60, Bottom = 56 })',
  '  other.__parent = menu.Canvas_Buttons',
  '  local kids = menu.Canvas_Buttons.__children',
  '  kids[#kids + 1] = other',
  '  return other',
  'end',
  // Our entry: the button-class child of Canvas_Buttons that we added.
  'function __entry(menu)',
  '  for _, ch in ipairs(menu.Canvas_Buttons.__children) do',
  '    if ch.__name == "WBP_MenuESC_Button_S_C" then return ch end',
  '  end',
  '  return nil',
  'end',
  // Our page: the CanvasPanel we filled into the tree root.
  'function __page(menu)',
  '  for _, ch in ipairs(menu.WidgetTree.RootWidget.__children) do',
  '    if ch.__name == "CanvasPanel" then return ch end',
  '  end',
  '  return nil',
  'end',
  '-- the page\'s buttons live inside boxes now, so this walks the whole subtree',
  'function __find_buttons(w, out)',
  '  if w == nil then return out end',
  '  for _, ch in ipairs(w.__children or {}) do',
  '    if ch.__name == "WBP_MenuESC_Button_S_C" then out[#out + 1] = ch end',
  '    __find_buttons(ch, out)',
  '  end',
  '  if w.__content ~= nil then',
  '    if w.__content.__name == "WBP_MenuESC_Button_S_C" then out[#out + 1] = w.__content end',
  '    __find_buttons(w.__content, out)',
  '  end',
  '  return out',
  'end',
  'function __page_button(menu, text)',
  '  for _, b in ipairs(__find_buttons(__page(menu), {})) do',
  '    if b.Text_Main ~= nil and b.Text_Main.__text == text then return b end',
  '  end',
  '  return nil',
  'end',
  // The rows live in the VerticalBox inside the ScrollBox on the page.
  'function __list(menu)',
  '  local page = __page(menu)',
  '  if page == nil then return nil end',
  '  for _, ch in ipairs(page.__children) do',
  '    if ch.__name == "ScrollBox" then return ch.__children[1] end',
  '  end',
  '  return nil',
  'end',
  'function __contents(menu)',
  '  local out = {}',
  '  local list = __list(menu)',
  '  for _, ch in ipairs((list and list.__children) or {}) do',
  '    if ch.__name == "SizeBox" and ch.__content ~= nil then out[#out + 1] = ch.__content end',
  '  end',
  '  return out',
  'end',
  '-- the game option rows (everything except the rebind rows)',
  'function __rows(menu)',
  '  local out = {}',
  '  for _, c in ipairs(__contents(menu)) do',
  '    if c.__name == "WBP_OptionSettings_ListContent_C" then out[#out + 1] = c end',
  '  end',
  '  return out',
  'end',
  '-- the rebind rows: a label and the small button showing the key',
  'function __key_rows(menu)',
  '  local out = {}',
  '  for _, c in ipairs(__contents(menu)) do',
  '    if c.__name == "Overlay" then',
  '      local row = { line = c }',
  '      for _, ch in ipairs(c.__children) do',
  '        if ch.__name == "TextBlock" then row.label = ch end',
  '        if ch.__name == "SizeBox" and ch.__content ~= nil then row.button = ch.__content end',
  '      end',
  '      out[#out + 1] = row',
  '    end',
  '  end',
  '  return out',
  'end',
  '-- what the page SAYS: its loose text (the title and the note line)',
  'function __page_text(menu)',
  '  local page = __page(menu)',
  '  local out = {}',
  '  for _, ch in ipairs((page and page.__children) or {}) do',
  '    if ch.__name == "TextBlock" and ch.__text ~= nil then out[#out + 1] = ch.__text end',
  '  end',
  '  return table.concat(out, " | ")',
  'end',
  '-- WHAT THE LABEL SHOULD SAY: resolved the way the SCREEN resolves it, so a',
  '-- lookup here also proves the row carries translated text and not the',
  '-- internal setting name.',
  'function __label_of(settingKey)',
  '  for _, e in ipairs(require("Settings").Schema()) do',
  '    if e.key == settingKey then',
  '      local L = require("Locale")',
  '      local text = L.T(e.label)',
  '      -- composed the same way the screen composes it, prefix and all',
  '      if e.labelPrefix ~= nil then return L.T(e.labelPrefix) .. " — " .. text end',
  '      return text',
  '    end',
  '  end',
  '  return nil',
  'end',
  'function __row_for(menu, settingKey)',
  '  local want = __label_of(settingKey)',
  '  for _, r in ipairs(__rows(menu)) do',
  '    if r.BP_PalTextBlock_Name.__text == want then return r end',
  '  end',
  '  return nil',
  'end',
  'function __key_row_for(menu, settingKey)',
  '  local want = __label_of(settingKey)',
  '  for _, r in ipairs(__key_rows(menu)) do',
  '    if r.label ~= nil and r.label.__text == want then return r end',
  '  end',
  '  return nil',
  'end',
  'function __click(btn)',
  '  local fn = __HOOKCB["' + CLICK_EVENT + '"]',
  '  if fn == nil then return "no click hook" end',
  '  fn({ get = function() return btn end })',
  '  return "clicked"',
  'end',
  'function __destruct(menu)',
  '  local fn = __HOOKCB["' + MENU_CLASS + ':Destruct"]',
  '  if fn == nil then return "no destruct hook" end',
  '  fn({ get = function() return menu end })',
  '  return "destructed"',
  'end',
  // Open the menu the way the game does: construct, notify, then let the
  // delayed pass run.
  'function __open()',
  '  local m = __menu()',
  '  __NOTIFY["' + MENU_CLASS + '"](m)',
  '  return m',
  'end',
].join('\n');

function newState(setup) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
    if (st !== lua.LUA_OK) { const e = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_settop(L, 0); return 'LOAD: ' + e; }
    const r = lua.lua_pcall(L, 0, 0, 0);
    if (r !== lua.LUA_OK) {
      const e = lua.lua_tostring(L, -1);
      const msg = e === null ? '(non-string error)' : to_jsstring(e);
      lua.lua_settop(L, 0);
      return msg;
    }
    return null;
  };
  const str = (expr) => {
    const err = run('__OUT = tostring(' + expr + ')', 'ev');
    if (err) return 'ERR: ' + err;
    lua.lua_getglobal(L, to_luastring('__OUT'));
    const s = lua.lua_tostring(L, -1);
    const out = s === null ? 'nil' : to_jsstring(s);
    lua.lua_settop(L, 0);
    return out;
  };
  const must = (code, name) => {
    const e = run(code, name);
    if (e) { console.log('  SETUP ERROR (' + name + '): ' + e); failures++; }
    return e;
  };
  must(fs.readFileSync(path.join(__dirname, 'prelude_323.lua'), 'utf8'), 'prelude');
  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  must('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');
  must([
    // Keep the hook callbacks, not just their names: the click hook is the only
    // way into the dispatch, and it is shared with every native ESC row.
    '__HOOKCB = {}',
    '__HOOKS = __HOOKS or {}',
    'RegisterHook = function(name, fn) __HOOKS[#__HOOKS + 1] = name; __HOOKCB[name] = fn; return 1, 2 end',
    '__NOTIFY = {}',
    'NotifyOnNewObject = function(cls, fn) __NOTIFY[cls] = fn; return true end',
  // A realistic Key table, including entries that must NOT be capturable so the
  // filter is actually exercised.
  '__BINDS = {}',
  'Key = {}',
  'for i, n in ipairs({ "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","G","H","J","K","B","N","M",',
  '                     "W","A","S","D","SPACE_BAR","NUM_ONE",',
  '                     "ESCAPE","BACKSPACE","LEFT_MOUSE_BUTTON","RIGHT_MOUSE_BUTTON","LEFT_SHIFT","LEFT_CONTROL" }) do',
  '  Key[n] = 100 + i',
  'end',
  'RegisterKeyBind = function(code, fn) __BINDS[code] = fn; return true end',
  'function __press(name) local fn = __BINDS[Key[name]]; if fn == nil then return "not watched" end fn() return "pressed" end',
    '__NOT_READY = false',
    // Delays matter now: the row watch runs every 150 ms, a game-thread hop is
    // 1 ms, and the give-up timer on a key capture is 8 s. A queue that ran
    // everything at once would fire that timeout before the player could press
    // anything.
    '__Q = {}',
    'ExecuteInGameThreadWithDelay = function(ms, fn) __Q[#__Q + 1] = { ms = ms or 0, fn = fn } end',
    'function __PUMP(maxMs)',
    '  maxMs = maxMs or 1000',
    '  local q = __Q; __Q = {}',
    '  for _, e in ipairs(q) do',
    '    if e.ms <= maxMs then pcall(e.fn) else __Q[#__Q + 1] = e end',
    '  end',
    'end',
    'function __PENDING() return #__Q end',
    '__LINES = {}',
    'function __said(x) for _, m in ipairs(__LINES) do if tostring(m):find(x, 1, true) then return true end end return false end',
    'function __count(x) local n = 0; for _, m in ipairs(__LINES) do if tostring(m):find(x, 1, true) then n = n + 1 end end return n end',
  ].join('\n'), 'globals');
  must(FAKE_UMG, 'umg');
  must('local L = require("Logger"); local real = L.log; L.log = function(m) __LINES[#__LINES + 1] = tostring(m) end', 'logcap');
  must('Menu = require("Menu"); Menu.Init()', 'init');
  if (setup) must(setup, 'setup');
  return { run, str, must };
}

console.log('\n=== A. Nothing is touched inside the construction callback ===');
{
  // NotifyOnNewObject fires while the engine is still assembling the menu.
  // Building there is an access violation writing 0x80, so the notification
  // must do nothing but schedule.
  const S = newState('__M = __menu()');
  expect('the mod is watching for the pause menu', S.str('tostring(__NOTIFY["' + MENU_CLASS + '"] ~= nil)'), 'true');
  S.must('__NOTIFY["' + MENU_CLASS + '"](__M)', 'notify');
  expect('the notification only schedules', S.str('__PENDING()'), '1');
  expect('...no widget was built yet', S.str('__BUILT.buttons'), '0');
  expect('...and the menu is untouched', S.str('#__M.Canvas_Buttons.__children'), '1');
  S.must('__PUMP()', 'pump');
  expect('the delayed pass adds the entry', S.str('#__M.Canvas_Buttons.__children'), '2');
}

console.log('\n=== B. The entry sits on the canvas above the bottom column ===');
{
  const S = newState('__M = __open(); __PUMP()');
  expect('the entry exists', S.str('tostring(__entry(__M) ~= nil)'), 'true');
  expect('it reads "PalBonds"', S.str('__entry(__M).Text_Main.__text'), 'PalBonds');
  // THE RULE THAT MATTERS: the parent is the canvas, not the VerticalBox.
  expect('its parent is Canvas_Buttons, not the button column',
    S.str('__entry(__M).__parent.__name'), 'Canvas_Buttons');
  expect('the column gained no children', S.str('#__M.__column.__children'), '0');
  expect('it mirrors the column\'s bottom anchor',
    S.str('__entry(__M).Slot:GetAnchors().Minimum.Y'), '1');
  // A stretched slot is made of offsets; writing position/size into one gave a
  // degenerate rectangle and Slate crashed laying it out.
  expect('it inherits the column\'s Left offset (native row width)',
    S.str('__entry(__M).Slot:GetOffsets().Left'), '60');
  expect('...and its Right offset', S.str('__entry(__M).Slot:GetOffsets().Right'), '60');
  expect('it sits one row above the column (-120 - 56 - 8)',
    S.str('__entry(__M).Slot:GetOffsets().Top'), '-184');
  expect('its height is the row height', S.str('__entry(__M).Slot:GetOffsets().Bottom'), '56');
  expect('no position/size was written into the stretched slot',
    S.str('tostring(__entry(__M).Slot.__pos) .. "/" .. tostring(__entry(__M).Slot.__size)'), 'nil/nil');
}

console.log('\n=== C. Sharing the shelf with another menu mod ===');
{
  // Canvas_Buttons is public space: DarnMenu, Better Mod Manager and AntiPhat
  // all pin a row above the same column and compute the same spot we do.
  const S = newState('__M = __menu(); __neighbour(__M, -184); __NOTIFY["' + MENU_CLASS + '"](__M); __PUMP()');
  expect('their row was noticed', S.str('tostring(__said("already parked above the column"))'), 'true');
  expect('ours goes above theirs, not on top of it',
    S.str('__entry(__M).Slot:GetOffsets().Top'), '-248');
}
{
  const S = newState('__M = __open(); __PUMP()');
  expect('with nobody else there, no lift is applied',
    S.str('tostring(__said("already parked above the column"))'), 'false');
}

console.log('\n=== D. The page is built on the first click, never before ===');
{
  // Pre-building a page per menu open is the reference mod's crash family:
  // widget churn inside an open menu, seven incidents before it was stopped.
  const S = newState('__M = __open(); __PUMP()');
  expect('no page after injecting', S.str('tostring(__page(__M) == nil)'), 'true');
  expect('only the entry button was built', S.str('__BUILT.canvas'), '0');
  S.must('__click(__entry(__M))', 'click');
  expect('the first click builds it', S.str('tostring(__page(__M) ~= nil)'), 'true');
  expect('it says PalBonds', S.str('tostring(__said("page opened"))'), 'true');
  expect('the page is visible', S.str('__page(__M).__vis'), '0');
  expect('the menu\'s own buttons are hidden behind it', S.str('__M.Canvas_Buttons.__vis'), '1');
  expect('...and its content panel too', S.str('__M.Canvas_Content.__vis'), '1');
  const canvasCount = S.str('__BUILT.canvas');
  S.must('__click(__entry(__M))', 'click2');
  expect('a second click does not build a second page', S.str('__BUILT.canvas'), canvasCount);
  // Three buttons, and each one does its own job.
  expect('the page offers Save, Cancel and Restore defaults',
    S.str('(function() local n = 0 for _, t in ipairs({ "Save", "Cancel", "Restore defaults" }) do' +
          ' if __page_button(__M, t) ~= nil then n = n + 1 end end return n end)()'), '3');
  S.must('__click(__page_button(__M, "Save"))', 'save');
  // Save used to close, which read as "save doesn't save" -- the only feedback
  // was the screen vanishing.
  expect('Save leaves the page open', S.str('__page(__M).__vis'), '0');
  expect('...and says so on screen', S.str('__page_text(__M)'), (v) => v.indexOf('Saved') >= 0);
  S.must('__click(__page_button(__M, "Cancel"))', 'close');
  expect('Cancel is what closes it', S.str('__page(__M).__vis'), '1');
}

console.log('\n=== E. Clicks: only our own buttons act ===');
{
  const S = newState('__M = __open(); __PUMP()');
  // The hook is registered on the button CLASS, which every native ESC row is
  // an instance of. Options / Link Discord / Return to Title must fall through.
  S.must('__NATIVE = __button()', 'native');
  S.must('__click(__NATIVE)', 'clicknative');
  expect('a native ESC row is ignored', S.str('tostring(__page(__M) == nil)'), 'true');
  // An address the engine recycled into another mod's widget must not inherit
  // our action -- that reads to players as "your mod broke theirs".
  S.must('__FOREIGN = __button(); __FOREIGN.__addr = __entry(__M).__addr', 'foreign');
  S.must('__click(__FOREIGN)', 'clickforeign');
  expect('a foreign widget on our recycled address is refused',
    S.str('tostring(__said("the widget there is not ours"))'), 'true');
  expect('...and no page was opened for it', S.str('tostring(__page(__M) == nil)'), 'true');
  S.must('__click(__entry(__M))', 'clickours');
  expect('our own entry still works', S.str('tostring(__page(__M) ~= nil)'), 'true');
}

console.log('\n=== F. ESC pressed twice: the older menu is left alone ===');
{
  // Two menus in flight. Injecting into the first one now would hang our entry
  // on a menu the player has already moved past, and sweeping it is what ends
  // the reference mod's crash logs.
  const S = newState([
    '__OLD = __menu(); __NOTIFY["' + MENU_CLASS + '"](__OLD)',
    '__NEW = __menu(); __NOTIFY["' + MENU_CLASS + '"](__NEW)',
    '__PUMP()',
  ].join('\n'));
  expect('the superseded menu got no entry', S.str('tostring(__entry(__OLD) == nil)'), 'true');
  expect('the menu on screen got one', S.str('tostring(__entry(__NEW) ~= nil)'), 'true');
  S.must('__click(__entry(__NEW))', 'click');
  expect('its page opens', S.str('tostring(__page(__NEW) ~= nil)'), 'true');
  expect('nothing was drawn on the older menu', S.str('tostring(__page(__OLD) == nil)'), 'true');
}
{
  // A menu that was already injected, then replaced: its entry still exists and
  // is still clickable, and nothing of ours may write to it.
  const S = newState([
    '__OLD = __open(); __PUMP()',
    '__NEW = __open(); __PUMP()',
  ].join('\n'));
  expect('both menus carry an entry',
    S.str('tostring(__entry(__OLD) ~= nil) .. "/" .. tostring(__entry(__NEW) ~= nil)'), 'true/true');
  S.must('__click(__entry(__OLD))', 'clickold');
  expect('a click on the stale menu\'s entry builds nothing on it',
    S.str('tostring(__page(__OLD) == nil)'), 'true');
  expect('its widgets were never removed either (the engine frees them)',
    S.str('tostring(__entry(__OLD).__removed)'), 'nil');
}

console.log('\n=== G. The menu closing forgets it ===');
{
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the page is up', S.str('tostring(__page(__M) ~= nil)'), 'true');
  S.must('__ENTRY = __entry(__M)', 'keep');
  expect('destruct is handled', S.str('__destruct(__M)'), 'destructed');
  expect('nothing of ours was removed by hand', S.str('tostring(__ENTRY.__removed)'), 'nil');
  const opens = S.str('__count("page opened")');
  S.must('__click(__ENTRY)', 'clickafter');
  expect('a click arriving after the menu died opens nothing',
    S.str('__count("page opened")'), opens);
  // A fresh menu after that still works: the state was cleared, not corrupted.
  S.must('__M2 = __open(); __PUMP()', 'reopen');
  expect('the next menu gets its entry', S.str('tostring(__entry(__M2) ~= nil)'), 'true');
  S.must('__click(__entry(__M2))', 'click2');
  expect('...and its page opens', S.str('tostring(__page(__M2) ~= nil)'), 'true');
}

console.log('\n=== H. The settings themselves, on the game\'s own rows ===');
{
  // The list is built from Settings.Schema(), so a setting added to the file
  // appears here with no second place to remember it.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('every setting has a row (option rows + rebind rows)',
    S.str('(function() local n = 0 for _, e in ipairs(require("Settings").Schema()) do if e.key then n = n + 1 end end' +
          ' local got = #__rows(__M) + #__key_rows(__M)' +
          ' return (got == n) and "all" or (got .. "/" .. n) end)()'), 'all');
  expect('the numbers and lists are the GAME\'s row widget',
    S.str('__rows(__M)[1].__name'), 'WBP_OptionSettings_ListContent_C');
  expect('the sections are on screen too (headings from the same schema)',
    S.str('(function() local n = 0 for _, ch in ipairs(__list(__M).__children) do if ch.__name == "TextBlock" then n = n + 1 end end return n > 0 and "yes" or "no" end)()'), 'yes');
  expect('it is framed with the game\'s own panel, not a rectangle of ours',
    S.str('__BUILT.window'), '1');

  // THE LABELS ARE WRITTEN FOR PLAYERS. Not the internal setting name, and not
  // English when the game is in another language.
  // No row may be labelled with a code name. `Language` is left out on purpose:
  // it is the internal key AND the correct English word for that row, so a
  // blanket comparison would flag a label that is right.
  expect('no row is labelled with a code name',
    S.str('(function() local bad = { "Pet", "Play", "FeedBase", "FeedBonusCommon", "FeedBonusRare",' +
          ' "KinshipPeach", "KinshipPeachLesser", "PassivePerTick", "JoinBonus", "ChanceNormal",' +
          ' "ChanceCurious", "ShowPersonalityTags", "KeyPlay", "KeyTags", "KeyPassiveGain" }' +
          ' local shown = {}' +
          ' for _, r in ipairs(__rows(__M)) do shown[r.BP_PalTextBlock_Name.__text] = true end' +
          ' for _, r in ipairs(__key_rows(__M)) do if r.label then shown[r.label.__text] = true end end' +
          ' for _, name in ipairs(bad) do if shown[name] then return "shows " .. name end end' +
          ' return "none" end)()'), 'none');
  expect('...it is the friendly label', S.str('__row_for(__M, "Pet").BP_PalTextBlock_Name.__text'), 'Petting');
  expect('the personality rows reuse the tag the player already sees',
    S.str('__row_for(__M, "ChanceCurious").BP_PalTextBlock_Name.__text'), 'Curious');
  expect('...which is the SAME string the tags draw',
    S.str('tostring(__row_for(__M, "ChanceCurious").BP_PalTextBlock_Name.__text == require("Locale").T("tag_curious"))'), 'true');
}
{
  // ...and they follow the game's language.
  const S = newState([
    '__FS_LANG = "fr"',
    'local L = require("Locale")',
    'L.Current = function() return "fr" end',
    '__M = __open(); __PUMP(); __click(__entry(__M))',
  ].join('\n'));
  expect('in French the rows are French',
    S.str('__row_for(__M, "Pet").BP_PalTextBlock_Name.__text'), 'Caresser');
  expect('...the headings too',
    S.str('(function() for _, ch in ipairs(__list(__M).__children) do' +
          ' if ch.__name == "TextBlock" and ch.__text == require("Locale").T("sec_trust") then return "yes" end end return "no" end)()'), 'yes');
  expect('...and a rebind row',
    S.str('tostring(__key_row_for(__M, "KeyTags") ~= nil)'), 'true');
}
{
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  // The shape of each control comes from the schema's `ui`, never from the
  // validation bounds -- that mistake made a slider unusable.
  expect('a 0-or-1 setting is a switch', S.str('__row_for(__M, "ShowPersonalityTags").__shape'), 'switch');
  expect('a number is a slider', S.str('__row_for(__M, "Pet").__shape'), 'slider');
  expect('a language is a list', S.str('__row_for(__M, "Language").__shape'), 'lr');
  expect('a key is NOT a list any more', S.str('tostring(__row_for(__M, "KeyPlay"))'), 'nil');
  expect('...it is a rebind row with a button', S.str('tostring(__key_row_for(__M, "KeyPlay").button ~= nil)'), 'true');

  // THE RANGES ARE THE SCREEN'S, NOT THE FILE'S.
  expect('Pet\'s slider is the range Dragón asked for, not the file\'s 0..100000',
    S.str('(function() local r = __row_for(__M, "Pet").__range return r[1] .. ".." .. r[2] .. " step " .. r[3] end)()'),
    '0..1000 step 10');
  expect('every interaction and every food share that one scale',
    S.str('(function() for _, k in ipairs({ "Pet", "Play", "FeedBase", "FeedBonusCommon",' +
          ' "FeedBonusUncommon", "FeedBonusRare", "FeedBonusEpic", "FeedBonusLegendary",' +
          ' "KinshipPeachLesser", "KinshipPeach" }) do' +
          ' local r = __row_for(__M, k).__range' +
          ' if not (r[1] == 0 and r[2] == 1000 and r[3] == 10) then return k .. " is " .. r[1] .. ".." .. r[2] end' +
          ' end return "all the same" end)()'), 'all the same');
  expect('the passive drip has its own smaller scale',
    S.str('(function() local r = __row_for(__M, "PassivePerTick").__range return r[1] .. ".." .. r[2] .. " step " .. r[3] end)()'),
    '0..100 step 1');
  expect('...and its default is reachable on it',
    S.str('(function() local r = __row_for(__M, "Pet").__range local v = require("Settings").Get("Pet")' +
          ' return ((v - r[1]) % r[3] == 0) and "reachable" or "off the step" end)()'), 'reachable');
  expect('the join bonus keeps a big range, because friendship ranks are big',
    S.str('(function() local r = __row_for(__M, "JoinBonus").__range return r[2] .. " step " .. r[3] end)()'),
    '200000 step 5000');
  expect('...and its default lands on a step',
    S.str('(function() local r = __row_for(__M, "JoinBonus").__range' +
          ' return (require("Settings").Get("JoinBonus") % r[3] == 0) and "reachable" or "off the step" end)()'), 'reachable');
  expect('a personality chance is 0..100, not the file\'s 0..1000',
    S.str('(function() local r = __row_for(__M, "ChanceNormal").__range return r[1] .. ".." .. r[2] end)()'), '0..100');
  expect('every slider\'s range is small enough to aim with',
    S.str('(function() for _, r in ipairs(__rows(__M)) do if r.__range ~= nil then' +
          ' local steps = (r.__range[2] - r.__range[1]) / r.__range[3]' +
          ' if steps > 100 then return "too many stops: " .. steps end end end return "all aimable" end)()'), 'all aimable');
  expect('a slider starts at the current value',
    S.str('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue .. "/" .. require("Settings").Get("Pet")'),
    (v) => v.split('/')[0] === v.split('/')[1]);
  expect('...and shows the number beside it',
    S.str('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.BP_PalTextBlock_Value.__text'), '50');
  expect('the language list offers auto plus every language',
    S.str('#__row_for(__M, "Language").WBP_OptionSettings_ListContentLR.__labels'), '17');
  // A language code in front of a player is a code name like any other.
  expect('...listed under their own names, not their codes',
    S.str('(function() local l = __row_for(__M, "Language").WBP_OptionSettings_ListContentLR.__labels' +
          ' for _, n in ipairs(l) do if n == "es" or n == "zh-hans" or n == "pt" then return "shows " .. n end end' +
          ' return table.concat({ l[1], l[3] }, "/") end)()'), 'Auto/Español');
  expect('Language is the first thing on the screen',
    S.str('(function() for _, e in ipairs(require("Settings").Schema()) do' +
          ' if e.section then return e.label end end end)()'), 'sec_language');
}
{
  // Moving a row has to reach the setting -- that is the whole point.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue = 200', 'drag');
  expect('nothing has changed before the watch runs', S.str('require("Settings").Get("Pet")'), '50');
  S.must('__PUMP()', 'poll');
  expect('the watch applies what the row says', S.str('require("Settings").Get("Pet")'), '200');
  S.must('__row_for(__M, "ShowPersonalityTags").WBP_OptionSettings_ListContentSwitch.CurrentIsOn = false; __PUMP()', 'switch');
  expect('a switch reaches its setting as 0/1', S.str('require("Settings").Get("ShowPersonalityTags")'), '0');
  S.must('local lr = __row_for(__M, "Language").WBP_OptionSettings_ListContentLR; for i, n in ipairs(lr.__labels) do if n == "Español" then lr.Current = i - 1 end end; __PUMP()', 'lang');
  expect('picking a language by its name stores the code', S.str('require("Settings").Get("Language")'), 'es');
}
{
  // REBINDING TO ANY KEY -- REBUILT 2026-09-26 ON THE GAME'S OWN MODAL.
  //
  // This used to arm ~154 RegisterKeyBind watchers that lived for the whole
  // session and fired on every key press. UE4SS runs those callbacks on its own
  // thread against a lua_State shared with the game thread and no lock (issue
  // #1345), which is what was crashing Dragón every few minutes: LUA_ERRERR,
  // ten hook calls that entered and never returned, a death inside a hook's own
  // Context:get(). Three trace runs, all only when the screen had been opened.
  //
  // The replacement is the game's own press-a-key overlay, read through a hook.
  // So the FIRST thing these checks prove is a negative: nothing is watched.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the button shows the key that is bound now',
    S.str('__key_row_for(__M, "KeyTags").button.Text_Main.__text'), 'F9');
  expect('...on the button class that only fires on a click, never a hover',
    S.str('__key_row_for(__M, "KeyTags").button.__name'), 'WBP_MenuESC_Button_S_C');

  // THE POINT OF THE WHOLE REBUILD.
  expect('NO key watcher is registered, even with the page open',
    S.str('__press("F4")'), 'not watched');
  expect('...not for any key at all',
    S.str('(function() local n = 0 for _ in pairs(__BINDS) do n = n + 1 end return n end)()'), '0');
  expect('...and no overlay is up until one is asked for',
    S.str('tostring(__key_overlay() == nil)'), 'true');

  S.must('__click(__key_row_for(__M, "KeyTags").button)', 'startcapture');
  expect('clicking a rebind row puts up the game\'s own press-a-key overlay',
    S.str('tostring(__key_overlay() ~= nil and __key_overlay().__name)'),
    'WBP_OptionSettingsOverLayWindow_C');
  expect('...added to a canvas of ours, not loose in the menu the game owns',
    S.str('tostring(__key_overlay().__parent ~= nil and __key_overlay().__parent.__name)'), 'CanvasPanel');
  expect('...the row says it is asking',
    S.str('__key_row_for(__M, "KeyTags").button.Text_Main.__text'), 'Press a key');
  expect('...and the game stops acting on what is typed',
    S.str('__INPUT_MODE'), 'ui');

  // THE OVERLAY ARRIVES IN THE PLAYER'S LANGUAGE, NOT THE GAME'S. Dragón's
  // first run showed this widget in Japanese: with KeyConfigParam left nil it
  // never runs the game's own text setup, so both blocks keep their
  // design-time defaults unless we write them.
  expect('the overlay is titled with the row being rebound',
    S.str('__key_overlay().BP_PalTextBlock_Title.__text'), 'Tags key');
  expect('...and tells the player what to do, and how to back out',
    S.str('__key_overlay().BP_PalTextBlock_Command.__text'),
    (v) => v.indexOf('Press a key') >= 0 && v.indexOf('Esc') >= 0);

  // NO DEAF PERIOD. A 0.25s guard used to sit here, left over from the
  // RegisterKeyBind mechanism where an arming burst could deliver a phantom
  // key. It swallowed Dragón's FIRST press four times in one run
  // ("ignoring F6: it arrived before the screen finished asking") and left the
  // keyboard held until he pressed again. A press the instant the overlay is
  // up is a real press.
  S.must('__fire_key("F4")', 'press');
  expect('a key reported the instant the overlay is up still counts',
    S.str('require("Settings").Get("KeyTags")'), 'F4');
  expect('...and the button shows it',
    S.str('__key_row_for(__M, "KeyTags").button.Text_Main.__text'), 'F4');
  expect('...the keyboard is handed back', S.str('__INPUT_MODE'), 'game');
  expect('...and the overlay is taken back off the page',
    S.str('tostring(__key_overlay().__parent == nil)'), 'true');

  // SpaceBar and W are the two keys a curated RegisterKeyBind battery cannot
  // capture (DarnMenu documents exactly that limit). Both came through live.
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button); __CLOCK = __CLOCK + 1; __fire_key("SpaceBar")', 'space');
  // The overlay reports "SpaceBar"; UE4SS's table spells it "SPACE_BAR".
  // Resolving between the two is what makes Space bindable at all.
  expect('Space can be bound -- the old approach could never offer it',
    S.str('require("Settings").Get("KeyTags")'), 'SPACE_BAR');
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button); __CLOCK = __CLOCK + 1; __fire_key("W")', 'w');
  expect('...and so can W, a key the game uses for movement',
    S.str('require("Settings").Get("KeyTags")'), 'W');

  // The hook is class-wide, so the game's OWN key-config screen fires it too.
  // If that drove our rows, rebinding in Palworld's options would silently
  // rewrite a PalBonds setting.
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button)', 'waiting');
  S.must('__CLOCK = __CLOCK + 1; __OTHER = __w("WBP_OptionSettingsOverLayWindow_C"); __fire_key("G", __OTHER)', 'foreign');
  expect('a fire from the GAME\'s own overlay is ignored',
    S.str('require("Settings").Get("KeyTags")'), 'W');
  expect('...and our screen is still waiting for its own',
    S.str('tostring(Menu.WaitingForKey())'), 'true');

  // What the overlay reports still has to be filtered: it reports whatever was
  // pressed, including keys that must never become a binding.
  S.must('__fire_key("LEFT_MOUSE_BUTTON")', 'mouse');
  expect('a mouse button is not an answer', S.str('require("Settings").Get("KeyTags")'), 'W');
  S.must('__fire_key("LEFT_SHIFT")', 'modifier');
  expect('...nor a bare modifier', S.str('require("Settings").Get("KeyTags")'), 'W');
  expect('...and the screen keeps waiting through both',
    S.str('tostring(Menu.WaitingForKey())'), 'true');
  S.must('__fire_key("ESCAPE")', 'escape');
  expect('Escape cancels, the way it does in the game\'s own key config',
    S.str('tostring(Menu.WaitingForKey())'), 'false');
  expect('...leaving the binding alone', S.str('require("Settings").Get("KeyTags")'), 'W');
  expect('...and giving the keyboard back', S.str('__INPUT_MODE'), 'game');
  expect('...and taking the overlay down', S.str('tostring(__key_overlay().__parent == nil)'), 'true');

  // Clicking again gives up rather than leaving the row waiting forever.
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button)', 'again');
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button)', 'cancel');
  expect('clicking twice stops waiting',
    S.str('__key_row_for(__M, "KeyTags").button.Text_Main.__text'), 'W');
  expect('...and gives the keyboard back', S.str('__INPUT_MODE'), 'game');
  S.must('__CLOCK = __CLOCK + 1; __fire_key("F5")', 'stray');
  expect('...and a later report changes nothing', S.str('require("Settings").Get("KeyTags")'), 'W');

  // Two actions on one key is still refused, and the button must not lie.
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyPlay").button); __CLOCK = __CLOCK + 1; __fire_key("W")', 'clash');
  expect('a key another action owns is refused', S.str('require("Settings").Get("KeyPlay")'), 'F8');
  expect('...with the reason on screen', S.str('__page_text(__M)'), (v) => v.indexOf('already used by') >= 0);
  expect('...and the button still shows the real binding',
    S.str('__key_row_for(__M, "KeyPlay").button.Text_Main.__text'), 'F8');

  // While the screen waits, the mod's own keys have to hold still, or choosing
  // F8 for Play would also play with a Pal on the way in.
  expect('the mod is not waiting for a key right now', S.str('tostring(Menu.WaitingForKey())'), 'false');
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button)', 'waitagain');
  expect('...but it says so while it is', S.str('tostring(Menu.WaitingForKey())'), 'true');
  S.must('__CLOCK = __CLOCK + 1; __fire_key("F6")', 'pick');
  expect('...and stops once the key is chosen', S.str('tostring(Menu.WaitingForKey())'), 'false');

  // The give-up timer must still let go of the keyboard: a player stuck in
  // UI-only input cannot move, which is the one unacceptable outcome.
  S.must('__CLOCK = __CLOCK + 1; __click(__key_row_for(__M, "KeyTags").button)', 'timeoutstart');
  expect('waiting holds the keyboard', S.str('__INPUT_MODE'), 'ui');
  S.must('__PUMP(9000)', 'timeout');
  expect('if no key ever comes, the screen lets go by itself', S.str('__INPUT_MODE'), 'game');
  expect('...and stops waiting', S.str('tostring(Menu.WaitingForKey())'), 'false');
  expect('...and the overlay does not stay on screen',
    S.str('tostring(__key_overlay().__parent == nil)'), 'true');
}
{
  // A REFUSED VALUE MUST NOT STAY ON SCREEN. A row still showing a number the
  // mod did not accept is the screen lying about the state of the game.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('for _, k in ipairs({ "ChanceCurious", "ChanceTimid", "ChanceAloof", "ChanceGrumpy", "ChanceHostile", "ChanceFeral" }) do require("Settings").Set(k, 0) end', 'zero');
  S.must('__row_for(__M, "ChanceNormal").WBP_OptionSettings_ListContentSlider.CurrentValue = 0; __PUMP()', 'zeroall');
  expect('zeroing the last chance is refused', S.str('require("Settings").Get("ChanceNormal")'), '35');
  expect('...and the row is put back to the real value',
    S.str('__row_for(__M, "ChanceNormal").WBP_OptionSettings_ListContentSlider.CurrentValue'), '35');
  expect('...with the reason on screen, where the player is looking',
    S.str('__page_text(__M)'), (v) => v.indexOf('at least one personality needs a chance above 0') >= 0);
}
{
  // The menu behind the page is covered completely, and put back exactly.
  const S = newState('__M = __open(); __PUMP()');
  S.must('__M.Canvas_TabSet = __M.Canvas_TabSet or nil', 'noop');
  expect('the tab strip exists on the menu', S.str('tostring(__M.Canvas_TabSet ~= nil)'), 'true');
  S.must('__M.CanvasPanelServerInfo.__vis = 1', 'hiddenalready');
  S.must('__click(__entry(__M))', 'open');
  expect('the buttons are hidden', S.str('__M.Canvas_Buttons.__vis'), '1');
  expect('the tab strip is hidden too (it used to cut the title)', S.str('__M.Canvas_TabSet.__vis'), '1');
  expect('the world settings are hidden', S.str('__M.WorldOptionCanvas.__vis'), '1');
  S.must('__click(__page_button(__M, "Cancel"))', 'close');
  expect('the buttons come back', S.str('__M.Canvas_Buttons.__vis'), '0');
  expect('the tab strip comes back', S.str('__M.Canvas_TabSet.__vis'), '0');
  expect('a panel that was ALREADY hidden stays hidden (it is not ours to show)',
    S.str('__M.CanvasPanelServerInfo.__vis'), '1');
}
{
  // The watch runs only while the page is up, and one write happens at the end.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the watch is scheduled while the page is open', S.str('__PENDING()'), (v) => Number(v) > 0);
  S.must('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue = 150; __PUMP()', 'change');
  expect('the change took', S.str('require("Settings").Get("Pet")'), '150');
  S.must('__click(__page_button(__M, "Save"))', 'save');
  expect('Save writes it', S.str('tostring(__said("settings saved to your file") or __said("settings applied for this session"))'), 'true');
  expect('the page is still open, so the watch is still running', S.str('__PENDING()'), (v) => Number(v) > 0);
  S.must('__click(__page_button(__M, "Cancel"))', 'close');
  S.must('__PUMP(); __PUMP()', 'after');
  expect('...and the watch stops once the page IS closed', S.str('__PENDING()'), '0');
  // Cancel after a Save must not undo the Save: saving moves the point Cancel
  // goes back to, or the screen and the file would disagree.
  expect('a Cancel after a Save keeps the saved value', S.str('require("Settings").Get("Pet")'), '150');
}
{
  // CANCEL PUTS BACK WHAT THE SCREEN FOUND. Changes apply live, so the only way
  // to offer an undo is to remember the state at open and restore it.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('Pet starts where the settings say', S.str('require("Settings").Get("Pet")'), '50');
  S.must('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue = 800; __PUMP()', 'change');
  S.must('__row_for(__M, "ShowPersonalityTags").WBP_OptionSettings_ListContentSwitch.CurrentIsOn = false; __PUMP()', 'switch');
  expect('the changes are live', S.str('require("Settings").Get("Pet") .. "/" .. require("Settings").Get("ShowPersonalityTags")'), '800/0');
  S.must('__WROTE = __said("settings saved to your file")', 'before');
  S.must('__click(__page_button(__M, "Cancel"))', 'cancel');
  expect('Cancel puts every value back', S.str('require("Settings").Get("Pet") .. "/" .. require("Settings").Get("ShowPersonalityTags")'), '50/1');
  expect('...and nothing was saved', S.str('tostring(require("Settings").IsDirty())'), 'false');
  expect('...and the page is closed', S.str('__page(__M).__vis'), '1');
}
{
  // RESTORE DEFAULTS puts the shipped values back, live, and leaves the page up
  // so the player can still change their mind.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue = 800; __PUMP()', 'change');
  S.must('require("Settings").Set("KeyTags", "F1")', 'movekey');
  S.must('__click(__page_button(__M, "Restore defaults"))', 'defaults');
  expect('a number goes back to its default', S.str('require("Settings").Get("Pet")'), '50');
  expect('a key goes back too', S.str('require("Settings").Get("KeyTags")'), 'F9');
  expect('every setting matches its default',
    S.str('(function() for _, e in ipairs(require("Settings").Schema()) do' +
          ' if e.key ~= nil and require("Settings").Get(e.key) ~= e.default then' +
          '  return e.key .. " is " .. tostring(require("Settings").Get(e.key)) end end' +
          ' return "all default" end)()'), 'all default');
  expect('the rows show the new values', S.str('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue'), '50');
  expect('the page stays open so it can still be cancelled', S.str('__page(__M).__vis'), '0');
  S.must('__PUMP(); __PUMP()', 'settle');
  expect('...and the watch does not undo the reset', S.str('require("Settings").Get("Pet")'), '50');
}
{
  // A value the file allows but this screen would not normally offer must not be
  // quietly clamped away -- the row stretches to reach it instead.
  const S = newState('require("Settings").Set("Pet", 5000); __M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the row reaches the out-of-range value',
    S.str('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue'), '5000');
  expect('...by widening, not clamping', S.str('__row_for(__M, "Pet").__range[2]'), '5000');
  expect('...and it says so in the log', S.str('tostring(__said("outside this screen\'s usual range"))'), 'true');
  S.must('__PUMP(); __PUMP(); __PUMP()', 'poll');
  expect('...and the watch leaves it alone', S.str('require("Settings").Get("Pet")'), '5000');
}
{
  // THE GUARD FOR WHAT A NOT-YET-READY WIDGET CAN DO. A native row that answers
  // 0 before it has laid out would otherwise be taken for the player's choice
  // and saved -- a settings screen that empties your settings just by being
  // opened. The row is not believed until it has handed back what we put in it.
  const S = newState('__NOT_READY = true; __M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the row is reporting a value we never set',
    S.str('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue'), '0');
  S.must('__PUMP(); __PUMP()', 'ticks');
  expect('the watch does NOT take that for the player\'s choice',
    S.str('require("Settings").Get("Pet")'), '50');
  S.must('__NOT_READY = false; __PUMP()', 'ready');
  expect('once the row can take it, it is put back to the stored value',
    S.str('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue'), '50');
  expect('...and the setting was never touched', S.str('require("Settings").Get("Pet")'), '50');
  // Once it has agreed, it is the player talking.
  S.must('__PUMP()', 'settle');
  S.must('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue = 0; __PUMP()', 'real');
  expect('a move AFTER that really is the player', S.str('require("Settings").Get("Pet")'), '0');
}
{
  // ...and the guard gives up rather than fighting a row forever.
  const S = newState('__NOT_READY = true; __M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__PUMP(); __PUMP(); __PUMP(); __PUMP(); __PUMP(); __PUMP()', 'many');
  expect('a row that never takes the value is followed in the end, and says so',
    S.str('tostring(__said("would not take the stored value"))'), 'true');
}
{
  // Nothing of this may run on a menu we no longer own.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__destruct(__M)', 'destruct');
  S.must('__PUMP(); __PUMP()', 'pump');
  expect('the watch stops when the menu dies', S.str('__PENDING()'), '0');
}

{
  // THE KEYBOARD MUST ALWAYS COME BACK. A player left in UI-only input mode
  // cannot move, so every way out of a capture is checked, not just the happy one.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__click(__key_row_for(__M, "KeyTags").button)', 'capture');
  expect('the game stops acting on the keyboard', S.str('__INPUT_MODE'), 'ui');
  // Nobody presses anything: the screen gives up by itself rather than leaving
  // the player stuck.
  S.must('__PUMP(10000)', 'timeout');
  expect('it lets go on its own if no key ever comes', S.str('__INPUT_MODE'), 'game');
  expect('...and stops asking', S.str('__key_row_for(__M, "KeyTags").button.Text_Main.__text'), 'F9');
}
{
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__click(__key_row_for(__M, "KeyTags").button)', 'capture');
  S.must('__destruct(__M)', 'menudies');
  expect('a menu dying mid-rebind still hands the keyboard back', S.str('__INPUT_MODE'), 'game');
}
{
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__click(__key_row_for(__M, "KeyTags").button)', 'capture');
  S.must('__click(__page_button(__M, "Cancel"))', 'cancel');
  expect('closing the page mid-rebind hands it back too', S.str('__INPUT_MODE'), 'game');
}
{
  // CHANGING THE LANGUAGE REWRITES THE SCREEN. The subtitle promises it.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the rows start in English', S.str('__row_for(__M, "Pet").BP_PalTextBlock_Name.__text'), 'Petting');
  S.must('local lr = __row_for(__M, "Language").WBP_OptionSettings_ListContentLR;' +
         ' for i, n in ipairs(lr.__labels) do if n == "Français" then lr.Current = i - 1 end end; __PUMP()', 'french');
  expect('the setting took', S.str('require("Settings").Get("Language")'), 'fr');
  expect('the rows are French now, without reopening', S.str('__row_for(__M, "Pet").BP_PalTextBlock_Name.__text'), 'Caresser');
  expect('...the headings too',
    S.str('(function() for _, ch in ipairs(__list(__M).__children) do' +
          ' if ch.__name == "TextBlock" and ch.__text == require("Locale").T("sec_keys") then return "yes" end end return "no" end)()'), 'yes');
  expect('...the buttons too', S.str('tostring(__page_button(__M, require("Locale").T("menu_save")) ~= nil)'), 'true');
  expect('...and the subtitle itself', S.str('__page_text(__M)'), (v) => v.indexOf('aussit\u00f4t') >= 0);
  expect('the language list still reads in each language\'s own name',
    S.str('__row_for(__M, "Language").WBP_OptionSettings_ListContentLR.__labels[3]'), 'Espa\u00f1ol');
}

{
  // The settings Dragón asked for after the second screenshot, on the screen.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the two module switches are there',
    S.str('__row_for(__M, "AbandonmentEnabled").__shape .. "/" .. __row_for(__M, "BetrayalEnabled").__shape'),
    'switch/switch');
  expect('...under a heading that is no longer "Display"',
    S.str('require("Locale").T("sec_display")'), 'Modules');
  expect('the accessibility rows are lists',
    S.str('__row_for(__M, "BarColor").__shape .. "/" .. __row_for(__M, "TagColor").__shape .. "/" .. __row_for(__M, "TagSize").__shape'),
    'lr/lr/lr');
  expect('a colour is offered by name, not by code',
    S.str('table.concat(__row_for(__M, "BarColor").WBP_OptionSettings_ListContentLR.__labels, ",")'),
    'Gold,White,Red,Green,Blue,Purple');
  expect('the tag colour can be left as the name\'s',
    S.str('__row_for(__M, "TagColor").WBP_OptionSettings_ListContentLR.__labels[1]'), 'Same as the name');
  expect('the sizes read as sizes', S.str('table.concat(__row_for(__M, "TagSize").WBP_OptionSettings_ListContentLR.__labels, ",")'),
    'Small,Normal,Large,Very large');
  // Picking one stores the value behind the name.
  S.must('local lr = __row_for(__M, "BarColor").WBP_OptionSettings_ListContentLR;' +
         ' for i, n in ipairs(lr.__labels) do if n == "Blue" then lr.Current = i - 1 end end; __PUMP()', 'pick');
  expect('picking "Blue" stores blue', S.str('require("Settings").Get("BarColor")'), 'blue');
  expect('the friendship section is named after OUR points, not the game\'s',
    S.str('require("Locale").T("sec_trust")'), 'Friendship points');
  expect('the passive row says what it actually does',
    S.str('__row_for(__M, "PassivePerTick").BP_PalTextBlock_Name.__text'),
    'Passive friendship gain while following');
}

{
  // The bonding switches sit directly under their own chance, so a personality's
  // two settings are always read together.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('each personality has a bonding switch',
    S.str('(function() local n = 0 for _, k in ipairs({ "BondNormal", "BondCurious", "BondTimid",' +
          ' "BondAloof", "BondGrumpy", "BondHostile", "BondFeral" }) do' +
          ' local r = __row_for(__M, k) if r ~= nil and r.__shape == "switch" then n = n + 1 end end return n end)()'), '7');
  expect('the row names the personality it belongs to',
    S.str('__row_for(__M, "BondCurious").BP_PalTextBlock_Name.__text'), 'Curious — can be bonded');
  expect('...reusing the very word on the Pal\'s tag',
    S.str('(function() local t = __row_for(__M, "BondFeral").BP_PalTextBlock_Name.__text' +
          ' return tostring(t:find(require("Locale").T("tag_feral"), 1, true) == 1) end)()'), 'true');
  expect('it sits directly under that personality\'s chance',
    S.str('(function() local rows = __rows(__M)' +
          ' local want = __label_of("ChanceCurious")' +
          ' for i, r in ipairs(rows) do' +
          '  if r.BP_PalTextBlock_Name.__text == want then' +
          '   local nxt = rows[i + 1]' +
          '   return (nxt ~= nil and nxt.BP_PalTextBlock_Name.__text == __label_of("BondCurious"))' +
          '     and "right under it" or "somewhere else" end end return "chance row missing" end)()'),
    'right under it');
  expect('and it translates with the rest of the screen',
    S.str('(function() local L = require("Locale") L.Current = function() return "es" end' +
          ' return L.T("set_bondable") end)()'), 'puede vincularse');
}

{
  // NOTHING IS SAID WHEN A CHANGE SIMPLY WORKS. The note line used to print the
  // setting's internal name and value -- code words in front of a player, about
  // a row they can already see.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  S.must('__row_for(__M, "Pet").WBP_OptionSettings_ListContentSlider.CurrentValue = 300; __PUMP()', 'change');
  expect('the change took', S.str('require("Settings").Get("Pet")'), '300');
  expect('...and the screen says nothing about it',
    S.str('__page_text(__M)'), (v) => v.indexOf('Pet') < 0 && v.indexOf('300') < 0);
  // A refusal still has to be explained, and by the row's real name.
  S.must('for _, k in ipairs({ "ChanceCurious", "ChanceTimid", "ChanceAloof", "ChanceGrumpy", "ChanceHostile", "ChanceFeral" }) do require("Settings").Set(k, 0) end', 'zero');
  S.must('__row_for(__M, "ChanceNormal").WBP_OptionSettings_ListContentSlider.CurrentValue = 0; __PUMP()', 'refuse');
  expect('a refusal is still explained', S.str('__page_text(__M)'),
    (v) => v.indexOf('at least one personality needs a chance above 0') >= 0);
  expect('...naming the row the way the player sees it, not by its key',
    S.str('__page_text(__M)'), (v) => v.indexOf('Normal') >= 0 && v.indexOf('ChanceNormal') < 0);
}
{
  // A rebind row is lettered like the rows around it -- it is the one row whose
  // label we draw ourselves, and at our own size it stood out as bigger.
  const S = newState('__M = __open(); __PUMP(); __click(__entry(__M))');
  expect('the rebind label uses the game row\'s own font size',
    S.str('(function() local native = __row_for(__M, "Pet").BP_PalTextBlock_Name.Font.Size' +
          ' local ours = __key_row_for(__M, "KeyPlay").label.Font.Size' +
          ' if ours == nil then return "not sized" end' +
          ' return (ours == native) and "same" or (ours .. " vs " .. native) end)()'), 'same');
  expect('the passive-gain switch is on the screen',
    S.str('__row_for(__M, "PassiveGainEnabled").__shape'), 'switch');
  expect('...named without "while following", which is the amount slider',
    S.str('__row_for(__M, "PassiveGainEnabled").BP_PalTextBlock_Name.__text'), 'Passive friendship gain');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
