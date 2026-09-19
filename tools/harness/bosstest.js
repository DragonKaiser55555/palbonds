// 2026-09-16: the boss bar, and the 20% ("Friendly") reset spies.
//
//   A. Indicator: a boss HP bar (WBP_BossEnemyHPGauge_C) reported by its
//      SetTargetCharacter hook gets a personality tag, and a trust bar under the
//      HP bar once bonding starts, same length as the HP bar. No timed world
//      search: exactly one FindAllOf for boss bars, right after the hook
//      installs, which also picks up a bar that was already on screen. A hook
//      that cannot install yet retries without searching.
//   B. Personality: crossing 20% starts Trust's brief follow for EVERY wild Pal
//      (Curious too, and a Timid Pal of a friendly species); on release it gets
//      the friendly preset and a re-sense, nothing else.
//   C. Interaction: a pet grants points only once a NEW petting animation is seen.
//   D. Combat: a self-defence fight may reach 3000 from the player (player fights keep 1800).
//   E. Trust: every boss (BOSS_/GYM_/RAID_ id, _BOSS/_GYM/_RAID class, or a boss bar seen) gets x2.
//   B7: human NPCs show Normal and their AI is never touched by the 20% reset.
//   F. Trust.StartBriefFollow: real follow, released once calm (min 3 s, max 15 s),
//      kept if the bar passed 50%.
//   R. 1.1.4 forgiveness (Personality): crossing 20% remembers what the Pal was;
//      RevertForgiveness puts back its tag AND AI (rolled donor, or its species
//      preset for a Normal roll); one forgiveness per Pal, ever; humans keep
//      their AI untouched.
//   U. 1.1.4 forgiveness (Trust): a PLAYER hit below 50% (or during the
//      calm-down) empties the bar and reverts the Pal — no betrayal, no scarred
//      status; the calm-down ends without Friendly being written; bonded Pals keep
//      the old rules; Pal-vs-Pal damage costs nothing; both damage hooks reach it
//      and a hit reported twice counts once.
//   G. 1.1.4 as shipped: the calm-down is the behaviour (no switch), for calm
//      and angry Pals alike; no dev instrument ships (spies, HookConfig,
//      Profiler); the 3000 self-defence reach is off.
//
// Usage: node bosstest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node bosstest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/');
let failures = 0;

function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

function newState(preludeFile) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
    if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
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
  const must = (code, name) => { const e = run(code, name); if (e) { console.log('  SETUP ERROR (' + name + '): ' + e); failures++; } return e; };
  must(fs.readFileSync(path.join(__dirname, preludeFile), 'utf8'), 'prelude');
  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  must('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');
  return { run, str, must };
}

const BOSS_HOOK = '/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_BossEnemyHPGauge.WBP_BossEnemyHPGauge_C:SetTargetCharacter';

// A boss bar widget tree, as far as the mod reads it.
const BOSS_STUBS = [
  '__SEARCHES = setmetatable({}, { __index = function() return 0 end })',
  '__BOSS_LIST = {}',
  'local realFA = FindAllOf',
  'FindAllOf = function(n) __SEARCHES[n] = __SEARCHES[n] + 1; if n == "WBP_BossEnemyHPGauge_C" then return __BOSS_LIST end return realFA(n) end',
  'local realSFO = StaticFindObject',
  'StaticFindObject = function(p) if p == "/Script/UMG.ProgressBar" then return __obj("ProgressBarClass") end return realSFO(p) end',
  '__BUILT = {}',
  'StaticConstructObject = function(cls)',
  '  local w = __obj("Built:" .. tostring(cls and cls.__name))',
  '  w.SetPercent = function(_, p) w.percent = p end',
  '  w.SetText_GDKInternal = function(_, _, t) w.text = t end',
  '  w.SetFillColorAndOpacity = function() end',
  '  w.SetVisibility = function() end',
  '  w.SetRenderScale = function() end',
  '  w.SetRenderOpacity = function() end',
  '  __BUILT[#__BUILT + 1] = w',
  '  return w',
  'end',
  'function __canvas(name)',
  '  local c = __obj(name)',
  '  c.AddChildToCanvas = function(self, child)',
  '    local s = __obj("CanvasPanelSlot")',
  '    s.Parent = c',
  '    s.SetPosition = function(_, p) s.pos = p end',
  '    s.SetSize = function(_, z) s.size = z end',
  '    s.GetPosition = function() return s.pos end',
  '    s.GetSize = function() return s.size end',
  '    s.SetAnchors = function(_, a) s.anchors = a end',
  '    s.SetAlignment = function(_, a) s.alignment = a end',
  '    child.Slot = s',
  '    c.added = (c.added or 0) + 1',
  '    return s',
  '  end',
  '  return c',
  'end',
  // __FP is the Pal's trust in points out of a 100-point bar; the bar reads it
  // through Trust.GetBarRatio (own trust points, 2026-09-18).
  '__FP = 0',
  'function __bossPal(name)',
  '  return __obj(name)',
  'end',
  'function __bossBar(name, pal)',
  '  local panel = __canvas("CanvasPanel BossHP")',
  '  local hpSlot = __obj("HPSlot")',
  '  hpSlot.Parent = panel',
  '  hpSlot.GetPosition = function() return __vec(10, 40, 0) end',
  '  hpSlot.GetSize = function() return __vec(600, 20, 0) end',
  '  hpSlot.GetAnchors = function() return __HP_ANCHORS end',
  '  hpSlot.GetAlignment = function() return { X = 0, Y = 0 } end',
  '  local hp = __obj("ProgressBar BossGaugeHP")',
  '  hp.Slot = hpSlot',
  '  local textClass = __obj("BP_PalTextBlock_C")',
  '  local nameText = __obj("Text_BossName")',
  '  nameText.GetClass = function() return textClass end',
  '  local inner = __obj("WBP_IngameBossHP_C")',
  '  inner.BossGaugeHP = hp',
  '  inner.Text_BossName = nameText',
  '  inner.Text_LvTitle = __obj("Text_LvTitle")',
  '  local w = __obj(name)',
  '  w.WBP_IngameBossHP = inner',
  '  w.TargetCharacter = pal',
  '  w.panel = panel',
  '  return w',
  'end',
  // Fixed-size HP bar by default (anchors min == max): offsets (10,40,600,20)
  // mean pos (10,40), size (600,20).
  '__HP_ANCHORS = { Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } }',
  '__BONDING = false',
  '__DISP = "warlike"',
].join('\n');

function bossState(hookLoadsAfterRounds) {
  const S = newState('prelude_323.lua');
  S.must(BOSS_STUBS, 'boss-stubs');
  if (hookLoadsAfterRounds > 0) {
    S.must([
      '__BOSS_HOOK_TRIES = 0',
      'local capture = RegisterHook',
      'RegisterHook = function(p, pre, post)',
      '  if tostring(p):find("BossEnemyHPGauge") then',
      '    __BOSS_HOOK_TRIES = __BOSS_HOOK_TRIES + 1',
      '    if __BOSS_HOOK_TRIES <= ' + hookLoadsAfterRounds + ' then error("class not loaded yet") end',
      '  end',
      '  return capture(p, pre, post)',
      'end',
    ].join('\n'), 'late-hook');
  }
  S.must([
    'T = require("Trust")',
    'T.HasBondingState = function() return __BONDING end',
    'T.GetBarRatio = function() if not __BONDING then return 0 end local r = __FP / 100; if r > 1 then r = 1 end; return r end',
    'C = require("Capture")',
    'C.IsAlreadyOwned = function() return false end',
    'C.HasPermanentlyFled = function() return false end',
    'P = require("Personality")',
    'P.GetDisposition = function() return __DISP end',
    'P.GetStableId = function(a) return a and ("ID-" .. a.__name) or nil end',
    'I = require("Indicator"); I.Init()',
  ].join('\n'), 'init');
  return S;
}

// ---------------------------------------------------------------------------
console.log('\n=== A1. Boss bar: hook installs at once ===');
{
  const S = bossState(0);
  expect('the boss bar hook is registered', S.str('__HOOKS["' + BOSS_HOOK + '"] ~= nil'), (v) => v === 'true');
  S.must('__PUMP(1)', 'first-tick');
  expect('one search for boss bars already on screen, right after install', S.str('__SEARCHES["WBP_BossEnemyHPGauge_C"]'), (v) => v === '1');

  S.must('__BOSS = __bossPal("BP_Boss_Anubis_C_1"); __W = __bossBar("WBP_BossEnemyHPGauge_C_1", __BOSS)', 'bar');
  expect('the hook fires cleanly', S.str('__FIRE("' + BOSS_HOOK + '", __arg(__W), __arg(__BOSS))'), (v) => v === 'ok');
  S.must('__PUMP(1)', 'tick');
  expect('next tick: the boss got a tag in the HP bar\'s own panel', S.str('__W.panel.added'), (v) => v === '1');
  S.must('__TAG = __BUILT[#__BUILT]', 'tag');
  expect('the tag shows the personality (warlike = Grumpy)', S.str('__TAG.text'), (v) => v === 'Grumpy');
  expect('no trust bar before bonding starts', S.str('#__BUILT'), (v) => v === '1');
  expect('tag sits under where the bar goes: x = HP x', S.str('__TAG.Slot.pos.X'), (v) => v === '10');
  expect('tag y = 40 + 20 + 2 + 7 (bar) + 1', S.str('__TAG.Slot.pos.Y'), (v) => v === '70');
  expect('tag is as wide as the HP bar', S.str('__TAG.Slot.size.X'), (v) => v === '600');

  S.must('__BONDING = true; __FP = 50; __PUMP(1)', 'bond');
  S.must('__BAR = __BUILT[#__BUILT]', 'bar2');
  expect('bonding starts: a trust bar is built', S.str('#__BUILT .. "," .. __W.panel.added'), (v) => v === '2,2');
  expect('bar is directly under the HP bar (y = 40 + 20 + 2)', S.str('__BAR.Slot.pos.X .. "," .. __BAR.Slot.pos.Y'), (v) => v === '10,62');
  expect('bar is the same length as the HP bar', S.str('__BAR.Slot.size.X'), (v) => v === '600');
  expect('bar height scales with the HP bar (20 * 0.35 -> 7)', S.str('__BAR.Slot.size.Y'), (v) => v === '7');
  expect('bar shows 50%', S.str('__BAR.percent'), (v) => v === '0.5');
  expect('tag follows the bar: Bonding at 50%', S.str('__TAG.text'), (v) => v === 'Bonding');
  expect('bar copies the HP bar anchors', S.str('__BAR.Slot.anchors.Maximum.X .. "," .. __BAR.Slot.anchors.Maximum.Y'), (v) => v === '0,0');
  S.must('__FP = 20; __PUMP(1)', 'down');
  expect('bar moves when trust changes', S.str('__BAR.percent'), (v) => v === '0.2');
  expect('tag reads Friendly at 20%', S.str('__TAG.text'), (v) => v === 'Friendly');

  S.must('__PUMP(20)', 'many');
  expect('20 more ticks: still only the one boss-bar search', S.str('__SEARCHES["WBP_BossEnemyHPGauge_C"]'), (v) => v === '1');
  expect('no second tag or bar was built', S.str('#__BUILT'), (v) => v === '2');

  S.must('__FIRE("' + BOSS_HOOK + '", __arg(__W), __arg(__BOSS)); __PUMP(2)', 'refire');
  expect('the same bar reported again builds nothing new', S.str('#__BUILT'), (v) => v === '2');

  S.must('__W.IsValid = function() return false end; __BAR.percent = nil; __FP = 90; __PUMP(2)', 'gone');
  expect('a closed boss bar is dropped (no more writes)', S.str('__BAR.percent'), (v) => v === 'nil');

  S.must('__FP = 0; __BONDING = false; __B2 = __bossPal("BP_Boss_Two_C"); __W2 = __bossBar("WBP_BossEnemyHPGauge_C_2", __B2)', 'two');
  S.must('__W2.TargetCharacter = nil', 'nofield');
  S.must('__FIRE("' + BOSS_HOOK + '", __arg(__W2), __arg(__B2)); __PUMP(1)', 'fire2');
  expect('TargetCharacter not set yet: the Pal from the hook argument is used', S.str('__W2.panel.added'), (v) => v === '1');
}

console.log('\n=== A1b. Stretched boss HP bar (the real game layout, 2026-09-16) ===');
{
  // Live: pos=(4,18) size=(4,8) with a horizontally stretched anchor, i.e.
  // Left=4 Top=18 Right MARGIN=4 Bottom(height)=8. The first build used 4 as
  // a width and drew a 4px bar.
  const S = bossState(0);
  S.must('__HP_ANCHORS = { Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 0 } }', 'stretch');
  S.must('__BOSS = __bossPal("BP_WeaselDragon_BOSS_C_1"); __W = __bossBar("WBP_BossEnemyHPGauge_C_S", __BOSS)', 'bar');
  S.must('local s = __W.WBP_IngameBossHP.BossGaugeHP.Slot; s.GetPosition = function() return __vec(4, 18, 0) end; s.GetSize = function() return __vec(4, 8, 0) end', 'live');
  S.must('__BONDING = true; __FP = 30; __FIRE("' + BOSS_HOOK + '", __arg(__W), __arg(__BOSS)); __PUMP(1)', 'fire');
  S.must('__BAR = nil; for _, w in ipairs(__BUILT) do if w.percent ~= nil then __BAR = w end end', 'find');
  expect('the bar is stretched like the HP bar (anchor max X = 1)', S.str('__BAR.Slot.anchors.Maximum.X'), (v) => v === '1');
  expect('...but not stretched vertically (anchor max Y = min Y)', S.str('__BAR.Slot.anchors.Maximum.Y'), (v) => v === '0');
  expect('same left offset and right margin as the HP bar', S.str('__BAR.Slot.pos.X .. "," .. __BAR.Slot.size.X'), (v) => v === '4,4');
  expect('directly under it: top = 18 + 8 + 2, height 6', S.str('__BAR.Slot.pos.Y .. "," .. __BAR.Slot.size.Y'), (v) => v === '28,6');
}

console.log('\n=== A2. Boss bar already on screen before the hook installs ===');
{
  const S = bossState(3);
  S.must('__BOSS = __bossPal("BP_Boss_Early_C"); __W = __bossBar("WBP_BossEnemyHPGauge_C_EARLY", __BOSS)', 'bar');
  S.must('__DEFAULT = __obj("WBP_BossEnemyHPGauge_C Default__WBP_BossEnemyHPGauge_C")', 'cdo');
  S.must('__BOSS_LIST = { __DEFAULT, __W }', 'list');
  expect('hook not installable yet', S.str('__HOOKS["' + BOSS_HOOK + '"] == nil'), (v) => v === 'true');
  S.must('__PUMP(2)', 'retry2');
  expect('while it retries, no boss-bar search runs', S.str('__SEARCHES["WBP_BossEnemyHPGauge_C"]'), (v) => v === '0');
  S.must('__PUMP(1)', 'retry3');
  expect('the retry installs the hook', S.str('__HOOKS["' + BOSS_HOOK + '"] ~= nil'), (v) => v === 'true');
  S.must('__PUMP(3)', 'after');
  expect('then exactly one search', S.str('__SEARCHES["WBP_BossEnemyHPGauge_C"]'), (v) => v === '1');
  expect('which gave the early boss its tag without any hook call', S.str('__W.panel.added'), (v) => v === '1');
  expect('the class default object was skipped', S.str('#__BUILT'), (v) => v === '1');
}

// ---------------------------------------------------------------------------
function spyState(diagnostics) {
  const S = newState('prelude_person.lua');
  S.must([
    '__PENDING = {}',
    'ExecuteInGameThreadWithDelay = function(ms, fn) __PENDING[#__PENDING + 1] = fn return true end',
    'function __PUMP(n) for _ = 1, n do local q = __PENDING; __PENDING = {}; for _, fn in ipairs(q) do pcall(fn) end end end',
    '__PLAYER = { IsValid = function() return true end, GetAddress = function() return 0x101 end, GetFullName = function() return "BP_Player_Female_C /Game/Maps/x.BP_Player_Female_C_1" end }',
    '__BUDDY = { IsValid = function() return true end, GetAddress = function() return 0x102 end, GetFullName = function() return "BP_FlowerDoll_C /Game/Maps/x.BP_FlowerDoll_C_2" end }',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then return { __PLAYER } end if n == "PalAISensorComponent" then return { __SENSOR } end return nil end',
    '__HATE_TARGET = nil',
    '__HATE = { IsValid = function() return true end, FindMostHateTarget = function() return __HATE_TARGET end }',
    '__CONTROLLER.GetHateSystem = function() return __HATE end',
    '__PAL.GetFullName = function() return "BP_FlowerDoll_C /Game/Maps/x.BP_FlowerDoll_C_1" end',
    '__ATTACK = { IsValid = function() return true end, GetFullName = function() return "BP_AIAction_CombatPal_C /x.BP_AIAction_CombatPal_C_5" end }',
    '__PETTING = { IsValid = function() return true end, GetFullName = function() return "BP_AIActionPairCall_Petting_C /x.BP_AIActionPairCall_Petting_C_3" end }',
    '__ACTION_COMP.GetCurrentAction_BP = function() return __CURRENT end',
    '__CURRENT = __ATTACK',
    // The friendly preset's real defaults, as far as this test cares.
    '__CDO.Discover_Player = 5; __CDO.Damaged_Player = 2; __CDO.Discover_Equal = 1; __CDO.Damaged_Equal = 2',
    '__UTILITY.IsPalMonster = function() return true end',
    'L = require("Logger")',
    'L.DiagnosticsEnabled = function() return ' + (diagnostics ? 'true' : 'false') + ' end',
    'P = require("Personality"); P.Init()',
    'P.GetStableId = function(a) if a == nil then return nil end return "PALID-1" end',
    '__PENDING = {}',
    'P.GetOrInitState(__PAL)',
    '__ST = P.GetState("PALID-1")',
    'function __grep(pat) local t = {} for _, m in ipairs(__LOG) do if m:find(pat) then t[#t + 1] = m end end return table.concat(t, " || ") end',
    'function __called(x) for _, c in ipairs(__CALLS) do if c:find(x, 1, true) then return true end end return false end',
    'function __preset() local p = __SENSOR.AIResponsePreset return p and (tostring(p.Discover_Player) .. "," .. tostring(p.Damaged_Player) .. "," .. tostring(p.Discover_Equal) .. "," .. tostring(p.Damaged_Equal)) or "none" end',
  ].join('\n'), 'spy-setup');
  return S;
}

// Personality side of the 20% brief follow: Trust is stubbed so the callback
// can be driven by hand. The Trust side is tested in section F.
function briefState(diagnostics, startResult) {
  const S = spyState(diagnostics);
  S.must([
    '__BRIEF = {}',
    'package.loaded["Trust"] = { StartBriefFollow = function(pal, hates, done) __BRIEF.pal = pal; __BRIEF.hates = hates; __BRIEF.done = done; return ' + (startResult ? 'true' : 'false') + ' end }',
    '__SENSOR.AIResponsePreset = nil',
  ].join('\n'), 'brief-stub');
  return S;
}

console.log('\n=== B1. 20% on an attacking Timid Pal: the brief follow starts, and nothing else runs ===');
{
  const S = briefState(true, true);
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "escape"; __ST.presetClassName = "BP_AIResponsePreset_friendly_C"; __HATE_TARGET = __PLAYER; __LOG = {}; __CALLS = {}', 'arm');
  S.must('P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)', 'cross');
  expect('the brief follow is started for this Pal', S.str('__BRIEF.pal == __PAL'), (v) => v === 'true');
  expect('no cancel, no rest, no re-sense yet', S.str('#__CALLS'), (v) => v === '0');
  expect('no preset written yet', S.str('__SENSOR.AIResponsePreset == nil'), (v) => v === 'true');
  expect('nothing scheduled by Personality', S.str('#__PENDING'), (v) => v === '0');
  expect('the anger check handed over says "angry" now', S.str('__BRIEF.hates(__PAL)'), (v) => v === 'true');
  S.must('__HATE_TARGET = __BUDDY', 'buddy');
  expect('...and "not angry at the player" when it hates someone else', S.str('__BRIEF.hates(__PAL)'), (v) => v === 'false');
  S.must('__BRIEF.done(true, 4.5, false)', 'released');
  expect('released: a plain friendly preset (player slots NOT overridden)', S.str('__preset()'), (v) => v === '5,2,1,2');
  expect('re-sensed without cancelling anything', S.str('__called("RequestSightCheckAsync") and not __called("AllCancelAction")'), (v) => v === 'true');
  expect('rolled tier recorded as friendly', S.str('__ST.rolledTier'), (v) => v === 'friendly');
  S.must('__LOG = {}; __CALLS = {}; __BRIEF = {}; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)', 'again');
  expect('a later interaction does nothing again', S.str('tostring(__BRIEF.pal) .. "," .. #__CALLS'), (v) => v === 'nil,0');
}

console.log('\n=== B2. Rolled Curious: same brief follow ("friendly > curious") ===');
{
  const S = briefState(false, true);
  S.must('__ST.disposition = "friendly"; __ST.rolledTier = "friendly"; __HATE_TARGET = __PLAYER', 'arm');
  S.must('P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)', 'cross');
  expect('brief follow started', S.str('__BRIEF.pal == __PAL'), (v) => v === 'true');
}

console.log('\n=== B3. The bar passed 50% during the brief follow: it stays a follower, preset untouched ===');
{
  const S = briefState(false, true);
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "escape"; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL); __CALLS = {}', 'cross');
  S.must('__BRIEF.done(true, 3.2, true)', 'stayed');
  expect('no friendly preset over the companion one', S.str('__SENSOR.AIResponsePreset == nil and #__CALLS == 0'), (v) => v === 'true');
}

console.log('\n=== B4. Brief follow could not start: friendly preset only ===');
{
  const S = briefState(false, false);
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "escape"; __LOG = {}; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)', 'cross');
  expect('friendly preset written', S.str('__preset()'), (v) => v === '5,2,1,2');
  expect('logged', S.str('__grep("brief follow not started")'), (t) => t !== '');
}

// ---------------------------------------------------------------------------
function petState() {
  const S = newState('prelude_emote.lua');
  S.must([
    '__PENDING = {}',
    'ExecuteInGameThreadWithDelay = function(ms, fn) __PENDING[#__PENDING + 1] = fn return true end',
    'function __PUMP(n) for _ = 1, n do local q = __PENDING; __PENDING = {}; for _, fn in ipairs(q) do pcall(fn) end end end',
    'package.loaded["Capture"] = nil',
    'package.preload["Capture"] = function() return { ShowToast = function() end, IsAlreadyOwned = function() return false end, HasPermanentlyFled = function() return false end } end',
    'T = require("Trust")',
    'function __PTS() return T.GetPoints(__WILD) end',
    '__CURRENT = nil',
    'local ac = { IsValid = function() return true end, GetCurrentAction_BP = function() return __CURRENT end }',
    'local ctrl = { IsValid = function() return true end, GetAIActionComponent = function() return ac end }',
    '__WILD = { IsValid = function() return __WILD_VALID end, GetFullName = function() return "BP_SheepBall_C /x.BP_SheepBall_C_9" end, Controller = ctrl }',
    '__WILD_VALID = true',
    '__ATTACK = { IsValid = function() return true end, GetFullName = function() return "BP_AIAction_CombatPal_C /x.BP_AIAction_CombatPal_C_5" end }',
    '__PETTING = { IsValid = function() return true end, GetFullName = function() return "BP_AIActionPairCall_Petting_C /x.BP_AIActionPairCall_Petting_C_3" end }',
    'I = require("Interaction")',
    '__NOTIFIED = 0',
    'I.OnWildPalPetted = function() __NOTIFIED = __NOTIFIED + 1 end',
    'function __grep(pat) local t = {} for _, m in ipairs(__LOG) do if m:find(pat) then t[#t + 1] = m end end return table.concat(t, " || ") end',
  ].join('\n'), 'pet-setup');
  return S;
}

console.log('\n=== C1. A pet that happens is granted once it is seen ===');
{
  const S = petState();
  S.must('__CURRENT = nil; I.GrantPetWhenItHappens(__WILD)', 'start');
  expect('nothing granted before the pet starts', S.str('__PTS()'), (v) => v === '0');
  S.must('__CLOCK = __CLOCK + 0.25; __PUMP(1); __CURRENT = __PETTING; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'pet');
  expect('granted once the Pal is being petted', S.str('__PTS() .. "," .. __NOTIFIED'), (v) => v === '50,1');
  S.must('__CLOCK = __CLOCK + 5; __PUMP(20)', 'later');
  expect('granted exactly once', S.str('__PTS() .. "," .. __NOTIFIED'), (v) => v === '50,1');
}

console.log('\n=== C2. A pet that bounces off an attack gives nothing (Dragón, 2026-09-16) ===');
{
  const S = petState();
  S.must('__CURRENT = __ATTACK; I.GrantPetWhenItHappens(__WILD)', 'start');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 0.25; __PUMP(1) end', 'wait');
  expect('no points after 5s of attacking', S.str('__PTS() .. "," .. __NOTIFIED'), (v) => v === '0,0');
  expect('logged as a failed pet, naming what it was doing', S.str('__grep("PET%-CHECK")'),
    (t) => t.indexOf('never happened') !== -1 && t.indexOf('BP_AIAction_CombatPal_C') !== -1);
  expect('and it stopped checking', S.str('#__PENDING'), (v) => v === '0');
}

console.log('\n=== C3. The Pal disappears before the pet ===');
{
  const S = petState();
  S.must('__CURRENT = __ATTACK; I.GrantPetWhenItHappens(__WILD); __WILD_VALID = false; __PUMP(1)', 'gone');
  expect('nothing granted, checking stopped', S.str('__PTS() .. "," .. #__PENDING'), (v) => v === '0,0');
}

console.log('\n=== C4. A second pet chosen while the first is still playing is not paid twice (run 3, Lyleen) ===');
{
  const S = petState();
  S.must('__PET1 = { IsValid = function() return true end, GetAddress = function() return 0x501 end, GetFullName = function() return "BP_AIActionPairCall_Petting_C /x.P_1" end }', 'p1');
  S.must('__PET2 = { IsValid = function() return true end, GetAddress = function() return 0x502 end, GetFullName = function() return "BP_AIActionPairCall_Petting_C /x.P_2" end }', 'p2');
  S.must('__CURRENT = nil; I.GrantPetWhenItHappens(__WILD); __CURRENT = __PET1; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'first');
  expect('first pet paid', S.str('__PTS()'), (v) => v === '50');
  S.must('I.GrantPetWhenItHappens(__WILD)', 'second-chosen');
  expect('second pet chosen during the first animation: not paid at once', S.str('__PTS()'), (v) => v === '50');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 0.25; __PUMP(1) end', 'wait');
  expect('the old animation playing on never pays the second pet', S.str('__PTS()'), (v) => v === '50');
  expect('logged as the previous pet', S.str('__grep("PET%-CHECK")'), (t) => t.indexOf('still the PREVIOUS pet') !== -1);
  S.must('I.GrantPetWhenItHappens(__WILD); __CURRENT = __PET2; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'third');
  expect('a NEW pet animation is paid', S.str('__PTS()'), (v) => v === '100');
  S.must('__PET1.GetAddress = function() return nil end; __PET2.GetAddress = function() return nil end', 'noaddr');
  S.must('__CURRENT = __PET1; I.GrantPetWhenItHappens(__WILD); for i = 1, 3 do __CLOCK = __CLOCK + 0.25; __PUMP(1) end', 'noaddr-same');
  expect('no addresses: a pet already playing is not paid', S.str('__PTS()'), (v) => v === '100');
  S.must('__CURRENT = nil; __CLOCK = __CLOCK + 0.25; __PUMP(1); __CURRENT = __PET2; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'noaddr-gap');
  expect('no addresses: paid after a gap then a pet', S.str('__PTS()'), (v) => v === '150');
}

console.log('\n=== C5. A pet pays only once the player is really petting (run 5, the Nitewing) ===');
function petStateWithPlayer() {
  const S = petState();
  S.must([
    '__PCUR = nil',
    '__PAC5 = { IsValid = function() return true end, GetCurrentAction = function() return __PCUR end }',
    '__ME5 = { IsValid = function() return true end, ActionComponent = __PAC5 }',
    'package.loaded["PlayerRef"] = { Get = function() return __ME5 end }',
    '__STANDBY = { IsValid = function() return true end, GetFullName = function() return "BP_ActionPairStandby_Petting_C /x.S_1" end }',
    '__BEHAV = { IsValid = function() return true end, GetFullName = function() return "BP_ActionPairBehavior_Petting_C /x.B_1" end }',
  ].join('\n'), 'player');
  return S;
}
{
  const S = petStateWithPlayer();
  S.must('__CURRENT = nil; I.GrantPetWhenItHappens(__WILD); __CURRENT = __PETTING; __PCUR = __STANDBY; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'accepted');
  expect('the Pal accepted, the player is still waiting: nothing yet', S.str('__PTS()'), (v) => v === '0');
  S.must('__PCUR = __BEHAV; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'petting');
  expect('the player is petting: paid', S.str('__PTS() .. "," .. __NOTIFIED'), (v) => v === '50,1');
}
{
  const S = petStateWithPlayer();
  S.must('__CURRENT = nil; I.GrantPetWhenItHappens(__WILD); __CURRENT = __PETTING; __PCUR = __STANDBY; __CLOCK = __CLOCK + 0.25; __PUMP(1)', 'accepted');
  S.must('__CURRENT = __ATTACK; __PCUR = nil; for i = 1, 20 do __CLOCK = __CLOCK + 0.25; __PUMP(1) end', 'never-came');
  expect('accepted mid-attack, never came over: nothing paid', S.str('__PTS() .. "," .. __NOTIFIED'), (v) => v === '0,0');
  expect('logged as accepted but never reached', S.str('__grep("PET%-CHECK")'), (t) => t.indexOf('never reached you') !== -1);
}

console.log('\n=== D. Self-defence may reach 3000 from the player (Dragón, 2026-09-16) ===');
{
  const S = newState('prelude_323.lua');
  S.must([
    'T = require("Trust"); C = require("Combat"); C.Init(); T.Init()',
    'T.StartFollowing(__PAL)',
    'C.SELF_DEFENCE_EXTENDED_REACH = true',
    '__CURRENT_ACTION.__name = "BP_AIAction_OtomoFollow_C_1"; __HATE_TARGET = nil',
    '__SHOOTER_LOC = __vec(2500, 0, 0)',
    '__SHOOTER = __obj("BP_Carbunclo_C_7"); __SHOOTER.K2_GetActorLocation = function() return __SHOOTER_LOC end',
    'function __hit() return __FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __SHOOTER, Defender = __PAL, Damage = 10 })) end',
    'function __tick() C.IssueFollowMoveOrder(__PAL, __vec(0, 0, 0), __PLAYER) end',
    'function __has(x) for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then return true end end return false end',
  ].join('\n'), 'd-setup');
  S.must('__hit(); __CLOCK = __CLOCK + 0.5; __tick()', 'shot');
  expect('a shooter 2500 from the player: the Pal fights back', S.str('__has("[SELF-DEFENCE]")'), (v) => v === 'true');
  expect('and the fight is NOT dropped as out of reach', S.str('C.IsSuspendedForCombat(__PAL) and not __has("out of reach")'), (v) => v === 'true');
  S.must('__PAL_LOC = __vec(2400, 0, 0); __PUMP(3)', 'chase');
  expect('chasing it to 2400 from the player: no recall', S.str('__has("[RECALL]")'), (v) => v === 'false');
  S.must('__SHOOTER_LOC = __vec(3500, 0, 0); __CLOCK = __CLOCK + 0.5; __tick()', 'far');
  expect('a shooter 3500 away: dropped, with the distance in the log', S.str('__has("out of reach: 3500 from the player, limit 3000")'), (v) => v === 'true');
}

console.log('\n=== E. Every boss gets the x2 bond meter (run 3: the gym Lyleen did not) ===');
{
  const S = newState('prelude_323.lua');
  S.must([
    'function __levelled(name, charId, level)',
    '  local p = __obj(name)',
    '  local param = __obj("Param")',
    '  param.SaveParameter = { Level = level }',
    '  param.GetCharacterID = function() return { ToString = function() return charId end } end',
    '  p.CharacterParameterComponent = __obj("Comp")',
    '  p.CharacterParameterComponent.GetIndividualParameter = function() return param end',
    '  return p',
    'end',
    'local pparam = __obj("PlayerParam"); pparam.SaveParameter = { Level = 50 }',
    '__PLAYER.CharacterParameterComponent = __obj("PComp")',
    '__PLAYER.CharacterParameterComponent.GetIndividualParameter = function() return pparam end',
    '__PLAYER.CharacterParameterComponent.IsDead = function() return false end',
    '__PLAYER.CharacterParameterComponent.IsDying = function() return false end',
    'T = require("Trust")',
  ].join('\n'), 'e-setup');
  const mult = (expr) => S.str('T.ComputeLevelMultiplier(' + expr + ')');
  expect('an ordinary Pal, same level: x1', mult('__levelled("BP_SheepBall_C /x.BP_SheepBall_C_1", "SheepBall", 50)'), (v) => v === '1.0');
  expect('"BOSS_" id: x2', mult('__levelled("BP_Garm_BOSS_C /x.BP_Garm_BOSS_C_1", "BOSS_Garm", 50)'), (v) => v === '2.0');
  expect('"GYM_" id (the tower Lyleen): x2', mult('__levelled("BP_LilyQueen_GYM_C /x.BP_LilyQueen_GYM_C_1", "GYM_LilyQueen", 50)'), (v) => v === '2.0');
  expect('unknown id but a _BOSS class (predator): x2', mult('__levelled("BP_MummyPal_BOSS_Predator_C /x.M_1", "PREDATOR_MummyPal", 50)'), (v) => v === '2.0');
  S.must('__ODD = __levelled("BP_Oddity_C /x.BP_Oddity_C_1", "ODD_Oddity", 50)', 'odd');
  expect('no marker at all: x1 (and cached)', mult('__ODD'), (v) => v === '1.0');
  S.must('T.MarkBossActor(__ODD)', 'mark');
  expect('...until the game shows it a boss bar: then x2', mult('__ODD'), (v) => v === '2.0');
}

console.log('\n=== B7. Human NPCs: shown as Normal, and the 20% reset leaves their AI alone (run 4) ===');
{
  const S = newState('prelude_person.lua');
  S.must([
    '__IS_MONSTER = false',
    '__UTILITY.IsPalMonster = function() return __IS_MONSTER end',
    '__CDO.Discover_Player = 5',
    '__SENSOR.AIResponsePreset = __CDO',
    'P = require("Personality"); P.Init()',
    'P.GetStableId = function(a) return "HUMAN-1" end',
    'P.GetOrInitState(__PAL)',
    '__ST = P.GetState("HUMAN-1")',
  ].join('\n'), 'human');
  expect('a human is flagged as such', S.str('__ST.isHuman'), (v) => v === 'true');
  expect('and shown as Normal, not the friendly species default (Curious)', S.str('P.GetDisposition("HUMAN-1")'), (v) => v === 'normal');
  S.must('__LOG = {}; __CALLS = {}; P.MaybeBecomeFriendlyByBar("HUMAN-1", __PAL)', 'cross');
  expect('20%: no reset calls', S.str('#__CALLS'), (v) => v === '0');
  expect('...and its AI preset is untouched', S.str('__SENSOR.AIResponsePreset == __CDO'), (v) => v === 'true');
  expect('logged', S.str('table.concat(__LOG, " | ")'), (t) => t.indexOf('human NPC: no reset') !== -1);
}

console.log('\n=== E2. Raid bosses get the x2 bond meter too ===');
{
  const S = newState('prelude_323.lua');
  S.must([
    'local pparam = __obj("PlayerParam"); pparam.SaveParameter = { Level = 50 }',
    '__PLAYER.CharacterParameterComponent = __obj("PComp")',
    '__PLAYER.CharacterParameterComponent.GetIndividualParameter = function() return pparam end',
    '__PLAYER.CharacterParameterComponent.IsDead = function() return false end',
    '__PLAYER.CharacterParameterComponent.IsDying = function() return false end',
    '__R = __obj("BP_LegendDeer_RAID_C /x.BP_LegendDeer_RAID_C_1")',
    'local param = __obj("Param"); param.SaveParameter = { Level = 50 }',
    'param.GetCharacterID = function() return { ToString = function() return "LegendDeer" end } end',
    '__R.CharacterParameterComponent = __obj("Comp")',
    '__R.CharacterParameterComponent.GetIndividualParameter = function() return param end',
    'T = require("Trust")',
  ].join('\n'), 'raid');
  expect('a _RAID class: x2', S.str('T.ComputeLevelMultiplier(__R)'), (v) => v === '2.0');
}

console.log('\n=== F. Trust.StartBriefFollow: real follow, released once calm (run 5 experiment) ===');
function trustState() {
  const S = newState('prelude_323.lua');
  S.must([
    'T = require("Trust"); C = require("Combat"); C.Init(); T.Init()',
    'local param = __obj("Param")',
    '__PAL.CharacterParameterComponent = __obj("Comp"); __PAL.CharacterParameterComponent.GetIndividualParameter = function() return param end',
    'require("Capture").IsAlreadyOwned = function() return false end',
    'function __PTS() return T.GetPoints(__PAL) end',
    'function __SETPTS(x) T.AddPoints(__PAL, x - T.GetPoints(__PAL), "test") end',
    '__SETPTS(30)',

    '__ANGRY = true',
    'function __hates() return __ANGRY end',
    '__DONE = nil',
    'function __done(c, e, s) __DONE = tostring(c) .. "," .. tostring(s) end',
    'function __has(x) for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then return true end end return false end',
  ].join('\n'), 'f-setup');
  return S;
}
{
  const S = trustState();
  expect('starts', S.str('T.StartBriefFollow(__PAL, __hates, __done)'), (v) => v === 'true');
  expect('the Pal is really following (Combat)', S.str('C.IsFollowing(__PAL) and T.IsBriefFollowing(__PAL)'), (v) => v === 'true');
  expect('a second start is refused while it follows', S.str('T.StartBriefFollow(__PAL, __hates, __done)'), (v) => v === 'false');
  S.must('__CLOCK = __CLOCK + 2; __PUMP(1)', 't2');
  S.must('__ANGRY = false; __CLOCK = __CLOCK + 0.5; __PUMP(1)', 'calm-early');
  expect('calm before 3 s: still following (the follow must be visible)', S.str('C.IsFollowing(__PAL)'), (v) => v === 'true');
  S.must('__CLOCK = __CLOCK + 1; for i = 1, 3 do __PUMP(1) end', 'calm');
  expect('calm after 3 s: released', S.str('C.IsFollowing(__PAL) or T.IsBriefFollowing(__PAL)'), (v) => v === 'false');
  expect('onDone(calm=true, stayed=false)', S.str('__DONE'), (v) => v === 'true,false');
  expect('logged', S.str('__has("released after") and __has("NO LONGER angry")'), (v) => v === 'true');
}
{
  const S = trustState();
  S.must('T.StartBriefFollow(__PAL, __hates, __done)', 'start');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 1; __PUMP(1) end', 'wait');
  expect('never calms: released at the 15 s limit', S.str('C.IsFollowing(__PAL)'), (v) => v === 'false');
  expect('onDone(calm=false, stayed=false), logged as STILL angry', S.str('__DONE .. "," .. tostring(__has("STILL angry"))'), (v) => v === 'false,false,true');
}
{
  const S = trustState();
  S.must('T.StartBriefFollow(__PAL, __hates, __done)', 'start');
  S.must('__SETPTS(300); __ANGRY = false; for i = 1, 8 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'past50');
  expect('bar past 50% by the end: keeps following', S.str('C.IsFollowing(__PAL)'), (v) => v === 'true');
  expect('onDone(stayed=true), and no longer a brief follow', S.str('__DONE .. "," .. tostring(T.IsBriefFollowing(__PAL))'), (v) => v === 'true,true,false');
}
{
  const S = trustState();
  S.must('T.StartFollowing(__PAL)', 'real');
  expect('already a real follower: no brief follow', S.str('T.StartBriefFollow(__PAL, __hates, __done)'), (v) => v === 'false');
}

{
  // Run 5: no passive trust while a Pal is only on its brief follow.
  const S = trustState();
  S.must('T.StartBriefFollow(__PAL, __hates, __done); for i = 1, 20 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end', 'brief');
  expect('during the brief follow: no passive friendship', S.str('__PTS()'), (v) => v === '30');
  S.must('__ANGRY = false; __SETPTS(300); for i = 1, 20 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'kept');
  S.must('__P0 = __PTS(); for i = 1, 40 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'real');
  expect('once it is a real follower: passive friendship again', S.str('__PTS() > __P0'), (v) => v === 'true');
}

// ---------------------------------------------------------------------------
// 1.1.4 — THE FORGIVENESS RULES (Dragón, 2026-09-18). "Bonding is a status
// that starts or should start at 50% friendship." Below it, a player hit
// empties the bar and a Pal that had forgiven goes back to what it was — tag
// and AI. One forgiveness per Pal, ever.
console.log('\n=== R1. Forgiving remembers what the Pal was; a hit reverts tag AND AI ===');
{
  const S = briefState(false, true);
  S.must('__ST.disposition = "warlike"; __ST.rolledTier = "warlike"; __ST.presetClassName = "BP_AIResponsePreset_escape_C"', 'arm');
  S.must('P.MaybeBecomeFriendlyByBar("PALID-1", __PAL); __BRIEF.done(true, 3.5, false)', 'forgive');
  expect('(setup) it is Friendly now', S.str('__ST.disposition .. "," .. __ST.rolledTier'), (v) => v === 'friendly,friendly');
  expect('what it was is on record', S.str('__ST.preForgive.disposition .. "," .. __ST.preForgive.rolledTier'), (v) => v === 'warlike,warlike');
  S.must('__LOG = {}; __CALLS = {}; __R = P.RevertForgiveness("PALID-1", __PAL)', 'hit');
  expect('reverted', S.str('__R'), (v) => v === 'true');
  expect('the tag reads what it was (Hostile)', S.str('__ST.disposition .. "," .. __ST.rolledTier'), (v) => v === 'warlike,warlike');
  expect('its own AI is written back: the rolled tier\'s preset', S.str('__grep("original AI is back %(BP_AIResponsePreset_Warlike%)")'), (t) => t !== '');
  expect('re-sensed without cancelling its reaction to the hit', S.str('__called("RequestSightCheckAsync") and not __called("AllCancelAction")'), (v) => v === 'true');
  expect('logged as the one forgiveness spent', S.str('__grep("one forgiveness is spent")'), (t) => t !== '');
}

console.log('\n=== R2. Only once: no second revert, and no second forgiveness ===');
{
  const S = briefState(false, true);
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "escape"; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL); __BRIEF.done(true, 3, false)', 'forgive');
  S.must('P.RevertForgiveness("PALID-1", __PAL)', 'hit1');
  expect('a second revert does nothing', S.str('P.RevertForgiveness("PALID-1", __PAL)'), (v) => v === 'false');
  S.must('__BRIEF = {}; __CALLS = {}; __SENSOR.AIResponsePreset = nil; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)', 'cross-again');
  expect('crossing 20% again: no calm-down', S.str('tostring(__BRIEF.pal)'), (v) => v === 'nil');
  expect('...no switch to Friendly', S.str('__ST.disposition'), (v) => v === 'escape');
  expect('...and nothing touched on the Pal', S.str('#__CALLS .. "," .. tostring(__SENSOR.AIResponsePreset == nil)'), (v) => v === '0,true');
}

console.log('\n=== R3. A Pal that rolled Normal gets its species preset back ===');
{
  const S = briefState(false, true);
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "normal"; __ST.presetClassName = "BP_AIResponsePreset_Escape_to_Battle_C"', 'arm');
  S.must('P.MaybeBecomeFriendlyByBar("PALID-1", __PAL); __BRIEF.done(true, 3, false); __LOG = {}; P.RevertForgiveness("PALID-1", __PAL)', 'cycle');
  expect('its species preset, not a donor', S.str('__grep("original AI is back %(BP_AIResponsePreset_Escape_to_Battle%)")'), (t) => t !== '');
  expect('and the tag it had', S.str('__ST.disposition .. "," .. __ST.rolledTier'), (v) => v === 'escape,normal');
}

console.log('\n=== R4. Nothing to revert: a Pal that never forgave, and a human ===');
{
  const S = briefState(false, true);
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "escape"; __CALLS = {}', 'arm');
  expect('never forgave: nothing happens', S.str('P.RevertForgiveness("PALID-1", __PAL) == false and #__CALLS == 0 and __ST.disposition == "escape"'), (v) => v === 'true');
}
{
  const S = briefState(false, true);
  S.must('__ST.isHuman = true; __ST.disposition = "normal"; __ST.rolledTier = "normal"; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL); __CALLS = {}; __SENSOR.AIResponsePreset = nil', 'human');
  S.must('P.RevertForgiveness("PALID-1", __PAL)', 'hit');
  expect('a human: tag back, AI never touched', S.str('__ST.disposition .. "," .. #__CALLS .. "," .. tostring(__SENSOR.AIResponsePreset == nil)'), (v) => v === 'normal,0,true');
}

// Trust side: the hit itself. Personality is stubbed by prelude_323, so what
// is checked for it is that Trust CALLS RevertForgiveness; R1-R4 cover the
// real Personality function.
function hitState() {
  const S = trustState();
  S.must([
    'P = require("Personality"); __REVERTED = 0',
    'P.GetStableId = function(a) return "ID" end',
    'P.RevertForgiveness = function(id, pal) __REVERTED = __REVERTED + 1 return true end',
    'require("Capture").IsAlreadyOwned = function() return false end',
    'function __count(x) local n = 0 for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then n = n + 1 end end return n end',
  ].join('\n'), 'hit-setup');
  return S;
}

console.log('\n=== U1. A player hit below 50%: bar to 0, back to what it was, no betrayal ===');
{
  const S = hitState();
  S.must('T.OnInteractionSucceeded(__PAL)', 'interact');
  expect('(setup) the Pal has a trust record and 30 points', S.str('T.HasBondingState(__PAL) and __PTS()'), (v) => v === '30');
  S.must('T.OnFollowerDamaged(__PAL, true)', 'hit');
  expect('the bar drops to 0', S.str('__PTS()'), (v) => v === '0');
  expect('its personality is sent back', S.str('__REVERTED'), (v) => v === '1');
  expect('logged as an unbonded hit, not a betrayal', S.str('__has("[UNBONDED-HIT]") and not __has("BETRAYAL —")'), (v) => v === 'true');
  expect('not scarred: it can still be bonded', S.str('tostring(require("Capture").HasPermanentlyFled and require("Capture").HasPermanentlyFled(__PAL))'), (v) => v !== 'true');
  S.must('T.OnFollowerDamaged(__PAL, true)', 'same-hit');
  expect('the second hook reporting the same hit is ignored', S.str('__count("[UNBONDED-HIT]") .. "," .. __REVERTED'), (v) => v === '1,1');
}

console.log('\n=== U2. A hit during the calm-down ends it, and it never turns Friendly ===');
{
  const S = hitState();
  S.must('T.StartBriefFollow(__PAL, __hates, __done)', 'start');
  S.must('__CLOCK = __CLOCK + 1; T.OnFollowerDamaged(__PAL, true)', 'hit');
  expect('the calm-down is over', S.str('T.IsBriefFollowing(__PAL) or C.IsFollowing(__PAL)'), (v) => v === 'false');
  expect('the bar drops to 0 and the personality goes back', S.str('__PTS() .. "," .. __REVERTED'), (v) => v === '0,1');
  S.must('__ANGRY = false; for i = 1, 20 do __CLOCK = __CLOCK + 1; __PUMP(1) end', 'later');
  expect('the release never runs, so Friendly is never written', S.str('tostring(__DONE)'), (v) => v === 'nil');
  expect('no betrayal', S.str('__has("BETRAYAL —")'), (v) => v === 'false');
}

console.log('\n=== U3. At 50% and above nothing changed: a hit on a bonded follower ===');
{
  const S = hitState();
  S.must('T.OnInteractionSucceeded(__PAL); T.StartFollowing(__PAL)', 'bond');
  S.must('__SETPTS(300); T.OnFollowerDamaged(__PAL, true)', 'hit');
  expect('the bonded rules still apply (half the bar, not an unbonded hit)', S.str('__has("the player hit a bonding Pal") and not __has("[UNBONDED-HIT]")'), (v) => v === 'true');
  expect('no personality revert for a bonded Pal', S.str('__REVERTED'), (v) => v === '0');
}

console.log('\n=== U4. Damage that is not the player\'s costs nothing below 50% ===');
{
  const S = hitState();
  S.must('T.OnInteractionSucceeded(__PAL); T.OnFollowerDamaged(__PAL, false)', 'pal-hit');
  expect('bar untouched, no revert', S.str('__PTS() .. "," .. __REVERTED'), (v) => v === '30,0');
}

console.log('\n=== U5. The real route: a player hit arriving through the game\'s damage hooks ===');
{
  const S = hitState();
  S.must('T.OnInteractionSucceeded(__PAL)', 'interact');
  S.must('__FIRE("/Script/Pal.PalDamageReactionComponent:OnProcessedActualDamageDelegate__DelegateSignature", nil, __arg(__PLAYER), __arg(__PAL), __arg(10))', 'delegate');
  expect('the damage delegate reaches the unbonded rule', S.str('__PTS() .. "," .. __REVERTED'), (v) => v === '0,1');
  S.must('__FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __PLAYER, Defender = __PAL, Damage = 10 }))', 'hate');
  expect('the hate hook reporting the same hit changes nothing', S.str('__count("[UNBONDED-HIT]") .. "," .. __REVERTED'), (v) => v === '1,1');
}
{
  const S = hitState();
  S.must('T.OnInteractionSucceeded(__PAL)', 'interact');
  S.must('__FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __PLAYER, Defender = __PAL, Damage = 10 }))', 'hate-only');
  expect('the hate hook alone reaches it too', S.str('__PTS() .. "," .. __REVERTED'), (v) => v === '0,1');
}

console.log('\n=== G. 1.1.4 as shipped ===');
{
  const S = spyState(false);
  S.must([
    '__BRIEF = {}',
    'package.loaded["Trust"] = { StartBriefFollow = function(pal) __BRIEF.pal = pal return true end }',
  ].join('\n'), 'stub');
  expect('the old 1.1.2 switch is gone: the calm-down IS the behaviour', S.str('tostring(P.FRIENDLY_BRIEF_FOLLOW)'), (v) => v === 'nil');
  expect('no forgiveness spy ships', S.str('tostring(P.WON_OVER_SPY) .. "," .. tostring(P.DescribeFight)'), (v) => v === 'nil,nil');
  expect('no crash-hunt switchboard and no profiler ship', S.str('tostring(pcall(require, "HookConfig")) .. "," .. tostring(pcall(require, "Profiler"))'), (v) => v === 'false,false');
  S.must('__ST.disposition = "escape"; __ST.rolledTier = "escape"; __SENSOR.AIResponsePreset = nil; __CALLS = {}', 'arm');
  S.must('P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)', 'cross');
  expect('an angry Pal gets the calm-down', S.str('__BRIEF.pal == __PAL'), (v) => v === 'true');
  expect('and nothing is cancelled on it (the old reset is gone)', S.str('__called("AllCancelAction")'), (v) => v === 'false');
}
{
  const S = spyState(false);
  S.must([
    '__BRIEF = {}',
    'package.loaded["Trust"] = { StartBriefFollow = function(pal) __BRIEF.pal = pal return true end }',
    '__ST.disposition = "friendly"; __ST.rolledTier = "friendly"; P.MaybeBecomeFriendlyByBar("PALID-1", __PAL)',
  ].join('\n'), 'curious');
  expect('a calm (Curious) Pal gets it too', S.str('__BRIEF.pal == __PAL'), (v) => v === 'true');
}
{
  const S = newState('prelude_323.lua');
  S.must([
    'T = require("Trust"); C = require("Combat"); C.Init(); T.Init()',
    'T.StartFollowing(__PAL)',
    '__CURRENT_ACTION.__name = "BP_AIAction_OtomoFollow_C_1"; __HATE_TARGET = nil',
    '__SHOOTER = __obj("BP_Carbunclo_C_7"); __SHOOTER.K2_GetActorLocation = function() return __vec(2500, 0, 0) end',
    'function __has(x) for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then return true end end return false end',
  ].join('\n'), 'sd');
  expect('extended self-defence reach stays off (not in 1.1.4)', S.str('C.SELF_DEFENCE_EXTENDED_REACH'), (v) => v === 'false');
  S.must('__FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __SHOOTER, Defender = __PAL, Damage = 10 })); __CLOCK = __CLOCK + 0.5; C.IssueFollowMoveOrder(__PAL, __vec(0, 0, 0), __PLAYER)', 'shot');
  expect('a shooter 2500 away is out of reach (limit 1800)', S.str('__has("limit 1800")'), (v) => v === 'true');
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
