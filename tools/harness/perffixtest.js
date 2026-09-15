// 2026-09-15: the microstutter fixes. Profiling showed nearly every stall the
// mod caused was a world-wide object search (FindAllOf / FindFirstOf) run on a
// timer or per event. The fixes replace those searches with references the mod
// already has. An optimisation like that is only safe if it still LETS THROUGH
// everything the old search found, so every section checks both directions:
// the search no longer happens in the common case, AND the fallback still
// happens when the cheap path cannot be trusted.
//
//   A. PlayerRef: one search for many lookups; a still-valid player is kept;
//      an invalid one is searched for immediately; "nobody found" is retried
//      after a short wait, not on every call.
//   B. Personality: a brand-new Pal's first sense does not rebuild the
//      world-wide sensor index; the scan works from hook-reported Pals and only
//      does its world search every 8th scan; with the hook not registered,
//      every scan is still the world search.
//   C. Indicator: nameplates reported by the bind hook get their install pass
//      without a world sweep; the sweep keeps running every tick until the hook
//      registers, a few ticks after, then every 15 ticks.
//
// Usage: node perffixtest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node perffixtest.js <SCRIPTS>'); process.exit(2); }
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
      return e === null ? '(non-string error)' : to_jsstring(e);
    }
    return null;
  };
  const str = (expr) => {
    const err = run('__OUT = tostring(' + expr + ')', 'ev');
    if (err) return 'ERR: ' + err;
    lua.lua_getglobal(L, to_luastring('__OUT'));
    const s = lua.lua_tostring(L, -1);
    return s === null ? 'nil' : to_jsstring(s);
  };
  const must = (code, name) => { const e = run(code, name); if (e) { console.log('  SETUP ERROR (' + name + '): ' + e); failures++; } return e; };
  must(fs.readFileSync(path.join(__dirname, preludeFile), 'utf8'), 'prelude');
  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  // Controllable clock, and a FindAllOf/FindFirstOf wrapper that counts searches per class.
  must([
    '__CLOCK = 1000.0; os.clock = function() return __CLOCK end',
    '__SEARCHES = setmetatable({}, { __index = function() return 0 end })',
    'local realFindAllOf = FindAllOf',
    'FindAllOf = function(n) __SEARCHES[n] = __SEARCHES[n] + 1; return realFindAllOf(n) end',
    'local realFindFirstOf = FindFirstOf',
    'FindFirstOf = function(n) __SEARCHES["first:" .. tostring(n)] = __SEARCHES["first:" .. tostring(n)] + 1; return realFindFirstOf and realFindFirstOf(n) end',
  ].join('\n'), 'counters');
  return { run, str, must };
}

// ---------------------------------------------------------------------------
console.log('\n=== A. PlayerRef ===');
{
  const S = newState('prelude_323.lua');
  S.must('R = require("PlayerRef")', 'req');
  S.must('for i = 1, 50 do __P = R.Get() end', 'many');
  expect('50 lookups in a row: one world search', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '1');
  expect('and it returns the player', S.str('__P == __PLAYER'), (v) => v === 'true');
  S.must('__CLOCK = __CLOCK + 3; __P = R.Get()', 'age3');
  expect('3s later, still valid: no new search', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '1');
  S.must('__CLOCK = __CLOCK + 8; __P = R.Get()', 'age11');
  expect('11s later, still valid and alive: still no new search (no short timer any more)', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '1');
  S.must('__CLOCK = __CLOCK + 50; __P = R.Get()', 'age61');
  expect('past the 60s safety-net interval: searched again', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '2');
  S.must('__PLAYER.IsValid = function() return false end; __P = R.Get()', 'invalid');
  expect('a player that became invalid is searched for immediately', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '3');
  expect('and with nobody valid, Get() returns nil', S.str('__P'), (v) => v === 'nil');
  S.must('for i = 1, 20 do __P = R.Get() end', 'misses');
  expect('nobody found: 20 more lookups within 2s do not search again', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '3');
  S.must('__CLOCK = __CLOCK + 2.1; __PLAYER.IsValid = function() return true end; __P = R.Get()', 'retry');
  expect('after the 2s miss wait, it searches again and finds the player', S.str('__SEARCHES["PalPlayerCharacter"] .. "," .. tostring(__P == __PLAYER)'), (v) => v === '4,true');
  expect('Name() resolves without another search', S.str('R.Name() .. "," .. __SEARCHES["PalPlayerCharacter"]'), (v) => v === 'BP_Player_Female_C_2147477654,4');

  // Death and respawn: noticed without a search; the body is kept while dead;
  // the world is searched every 2s until a different character appears.
  S.must([
    '__DEAD = false',
    '__PLAYER.CharacterParameterComponent = { IsValid = function() return true end, IsDead = function() return __DEAD end, IsDying = function() return false end }',
    '__BASE = __SEARCHES["PalPlayerCharacter"]',
    '__CLOCK = __CLOCK + 1.5; __P = R.Get()',
  ].join('\n'), 'alive');
  expect('alive, death check runs: no search', S.str('__SEARCHES["PalPlayerCharacter"] - __BASE'), (v) => v === '0');
  S.must('__DEAD = true; __CLOCK = __CLOCK + 1.1; __P = R.Get()', 'dies');
  expect('the death is noticed without a search', S.str('__SEARCHES["PalPlayerCharacter"] - __BASE'), (v) => v === '0');
  expect('and the body is still returned while dead', S.str('__P == __PLAYER'), (v) => v === 'true');
  S.must('__CLOCK = __CLOCK + 2.1; __P = R.Get()', 'respawnwait1');
  expect('2s later: one respawn search, which only finds the same body', S.str('__SEARCHES["PalPlayerCharacter"] - __BASE'), (v) => v === '1');
  expect('so the body is still what is returned', S.str('__P == __PLAYER'), (v) => v === 'true');
  S.must([
    '__P2 = __obj("BP_Player_Female_C_RESPAWNED")',
    'FindAllOf = function(n) __SEARCHES[n] = __SEARCHES[n] + 1; if n == "PalPlayerCharacter" then return { __P2 } end return nil end',
    '__CLOCK = __CLOCK + 0.5; __P = R.Get()',
  ].join('\n'), 'respawned-early');
  expect('less than 2s since the last respawn search: no search yet', S.str('__SEARCHES["PalPlayerCharacter"] - __BASE'), (v) => v === '1');
  S.must('__CLOCK = __CLOCK + 1.6; __P = R.Get()', 'respawnfound');
  expect('the next respawn search finds the NEW character', S.str('(__SEARCHES["PalPlayerCharacter"] - __BASE) .. "," .. tostring(__P == __P2)'), (v) => v === '2,true');
  S.must('for i = 1, 10 do __CLOCK = __CLOCK + 0.3; __P = R.Get() end', 'afterrespawn');
  expect('after the respawn: no more searches, still the new character', S.str('(__SEARCHES["PalPlayerCharacter"] - __BASE) .. "," .. tostring(__P == __P2)'), (v) => v === '2,true');

  // A world change clears the reference (Combat.ResetForNewWorld).
  S.must('C = require("Combat"); __B2 = __SEARCHES["PalPlayerCharacter"]; C.ResetForNewWorld("test"); __P = R.Get()', 'worldreset');
  expect('a world reset forces a fresh search on the next lookup', S.str('__SEARCHES["PalPlayerCharacter"] - __B2'), (v) => v === '1');
}

// ---------------------------------------------------------------------------
// Personality, with the hook and the scheduled scan captured.
function personalityState(hookRegisters) {
  const S = newState('prelude_person.lua');
  S.must([
    '__HOOKS = {}',
    'RegisterHook = function(p, pre, post)',
    '  if ' + (hookRegisters ? 'false' : 'tostring(p):find("SelectResponseBySenses")') + ' then error("not hookable yet") end',
    '  __HOOKS[tostring(p)] = pre; return true',
    'end',
    '__PENDING = {}',
    'ExecuteInGameThreadWithDelay = function(ms, fn) __PENDING[#__PENDING + 1] = fn; return true end',
    'function __PUMP(n) for _ = 1, n do local q = __PENDING; __PENDING = {}; for _, fn in ipairs(q) do pcall(fn) end end end',
    // The game's GetComponentByClass is broken for this component; make the
    // test Pal behave the same, so only the cache or the index can find it.
    '__PAL.GetComponentByClass = function() error("GetComponentByClass is broken for PalAISensorComponent in this build") end',
    '__SENSOR.GetAddress = function() return 0x5000 end',
    '__SENSOR.GetOuter = function() return { Pawn = __PAL } end',
    // The sensor needs a preset for GetPresetClassName to name; prelude_person
    // leaves it unset (presettest assigns its own). __CDO is its friendly preset.
    '__SENSOR.AIResponsePreset = __CDO',
    // prelude_person resolves no sensor CLASS, and without one GetPresetClassName
    // returns before it could ever reach the index -- which would make the index
    // checks below pass for the wrong reason.
    '__SENSOR_CLASS = __obj and __obj("PalAISensorComponent") or { IsValid = function() return true end }',
    'local realSFO = StaticFindObject',
    'StaticFindObject = function(p) if p == "/Script/Pal.PalAISensorComponent" then return __SENSOR_CLASS end return realSFO(p) end',
    // The scan is fed hook-reported Pals; the world search returns __WORLD_PALS,
    // which a test can extend with a Pal the hook never reports.
    '__WORLD_PALS = { __PAL }',
    'local realFA = FindAllOf',
    'FindAllOf = function(n) if n == "PalCharacter" then __SEARCHES[n] = __SEARCHES[n] + 1; return __WORLD_PALS end return realFA(n) end',
  ].join('\n'), 'personality-stubs');
  S.must('P = require("Personality")', 'require');
  // fengari (the Lua VM these tests run on) has 32-bit integers, so the real
  // GetStableId's `n % 0x100000000` field mask fails and it always returns nil
  // here -- which silently turns every hook-driven path into an early return.
  // The game's Lua is 64-bit and unaffected. Replace it with a stable id derived
  // from the actor's name; the mod calls it as Personality.GetStableId, so the
  // hook, cache_sensor_for_pal and GetOrInitState all get this one.
  S.must('P.GetStableId = function(actor) if actor == nil or actor.__name == nil then return nil end return "PALID-" .. actor.__name end', 'stableid');
  S.must('P.Init()', 'init');
  return S;
}

console.log('\n=== B. Personality: hook registered ===');
{
  const S = personalityState(true);
  const HOOK = '/Script/Pal.PalAISensorComponent:SelectResponseBySenses';
  expect('the sense hook was captured', S.str('__HOOKS["' + HOOK + '"] ~= nil'), (v) => v === 'true');
  // +31s makes the sensor index stale (its refresh interval is 30s), so any
  // lookup that misses the hook's cache WOULD rebuild it here. A zero count
  // therefore means the cache was used, not that the index happened to be fresh.
  S.must('__CLOCK = __CLOCK + 31; __SEARCHES["PalAISensorComponent"] = 0', 'reset');
  S.must('__HOOKS["' + HOOK + '"]({ get = function() return __SENSOR end })', 'sense');
  expect('a brand-new Pal\'s first sense does NOT rebuild the world-wide sensor index', S.str('__SEARCHES["PalAISensorComponent"]'), (v) => v === '0');
  expect('and the Pal got its personality state from that sense', S.str('P.GetState(P.GetStableId(__PAL)) ~= nil'), (v) => v === 'true');
  S.must('__ID = P.GetStableId(__PAL)', 'id');
  S.must('__CLOCK = __CLOCK + 31; __SEARCHES["PalAISensorComponent"] = 0; __NAME_WITH_ID = P.GetPresetClassName(__PAL, __ID)', 'withid');
  expect('GetPresetClassName with the Pal\'s id uses the hook\'s cached sensor (no index search)', S.str('__SEARCHES["PalAISensorComponent"]'), (v) => v === '0');
  expect('...and actually resolves the preset through it', S.str('__NAME_WITH_ID'), (v) => v !== 'nil');
  S.must('__CLOCK = __CLOCK + 31; __SEARCHES["PalAISensorComponent"] = 0; __NAME_NO_ID = P.GetPresetClassName(__PAL)', 'noid');
  expect('without the id it still falls back to the index (so the check above is meaningful)', S.str('__SEARCHES["PalAISensorComponent"]'), (v) => Number(v) >= 1);
  expect('both routes resolve the same, non-nil preset', S.str('__NAME_WITH_ID ~= nil and __NAME_WITH_ID == __NAME_NO_ID'), (v) => v === 'true');

  S.must('__SEARCHES["PalCharacter"] = 0; __PUMP(7)', 'pump7');
  expect('scans 1-7 with the hook armed: no world search for Pals', S.str('__SEARCHES["PalCharacter"]'), (v) => v === '0');
  expect('...and no world search for the player either', S.str('__SEARCHES["PalPlayerCharacter"]'), (v) => v === '0');
  S.must('__PUMP(1)', 'pump8');
  expect('scan 8: the safety-net world search runs', S.str('__SEARCHES["PalCharacter"]'), (v) => v === '1');
  S.must('__PUMP(8)', 'pump16');
  expect('scan 16: once more, and only once more', S.str('__SEARCHES["PalCharacter"]'), (v) => v === '2');

  // A Pal the safety scan finds but the hook never reports has no cached sensor.
  // The regular (hook-fed) scans must not fall back to the world-wide sensor
  // index for it -- the hook enforces it once its AI senses. Only the safety
  // scan may take the full path.
  S.must([
    '__PAL2 = { __name = "BP_NeverSensed_C_2", IsValid = function() return true end,',
    '  GetFullName = function() return "BP_NeverSensed_C_2" end,',
    '  GetComponentByClass = function() error("GetComponentByClass is broken for PalAISensorComponent in this build") end }',
    '__WORLD_PALS = { __PAL, __PAL2 }',
  ].join('\n'), 'pal2');
  S.must('__PUMP(8)', 'pump24');
  expect('precondition: the scan-24 safety search created a state for the never-sensed Pal',
    S.str('P.GetState("PALID-BP_NeverSensed_C_2") ~= nil'), (v) => v === 'true');
  expect('precondition: and it is not enforced, so the regular scans would try it',
    S.str('(P.GetState("PALID-BP_NeverSensed_C_2") or {}).enforcementApplied'), (v) => v !== 'true');
  S.must('__SEARCHES["PalAISensorComponent"] = 0; for i = 1, 7 do __CLOCK = __CLOCK + 31; __PUMP(1) end', 'pump25to31');
  expect('scans 25-31, sensor index stale before every one: no index rebuild for the never-sensed Pal',
    S.str('__SEARCHES["PalAISensorComponent"]'), (v) => v === '0');
}

console.log('\n=== B2. Personality: hook NOT registered (fallback must still search) ===');
{
  const S = personalityState(false);
  S.must('__SEARCHES["PalCharacter"] = 0; __PUMP(3)', 'pump3');
  expect('every scan is the full world search while the hook is not armed', S.str('__SEARCHES["PalCharacter"]'), (v) => Number(v) >= 3);
}

// ---------------------------------------------------------------------------
function indicatorState(bindHookRegisters) {
  const S = newState('prelude_323.lua');
  S.must([
    'local capture = RegisterHook',
    'RegisterHook = function(p, pre, post)',
    '  if ' + (bindHookRegisters ? 'false' : 'tostring(p):find("NPCHPGauge")') + ' then error("class not loaded yet") end',
    '  return capture(p, pre, post)',
    'end',
    '__GAUGE_TOUCHES = 0',
    '__GAUGE = __obj("WBP_PalNPCHPGauge_C_TEST")',
    'local realName = __GAUGE.GetFullName',
    '__GAUGE.GetFullName = function(self) __GAUGE_TOUCHES = __GAUGE_TOUCHES + 1; return "WBP_PalNPCHPGauge_C_TEST" end',
    'local realFA = FindAllOf',
    'FindAllOf = function(n) if n == "WBP_PalNPCHPGauge_C" then __SEARCHES[n] = __SEARCHES[n] + 1; return {} end return realFA(n) end',
  ].join('\n'), 'indicator-stubs');
  S.must('I = require("Indicator"); I.Init()', 'init');
  return S;
}

console.log('\n=== C. Indicator: bind hook registered ===');
{
  const S = indicatorState(true);
  const BIND = '/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle';
  const UNBIND = '/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:Unbind';
  expect('the bind hook was captured', S.str('__HOOKS["' + BIND + '"] ~= nil'), (v) => v === 'true');
  S.must('__SEARCHES["WBP_PalNPCHPGauge_C"] = 0; __PUMP(30)', 'pump30');
  expect('30 ticks: 5 sweeps after the hook + 2 safety-net sweeps (ticks 15, 30) = 7, not 30',
    S.str('__SEARCHES["WBP_PalNPCHPGauge_C"]'), (v) => v === '7');

  // A nameplate the hook reports must reach install_trust_bar without a sweep.
  const fired = S.str('__FIRE("' + BIND + '", __arg(__GAUGE), __arg({ handle = true }))');
  expect('firing the bind hook works', fired, (v) => v === 'ok');
  S.must('__TOUCH_AFTER_HOOK = __GAUGE_TOUCHES; __SEARCHES["WBP_PalNPCHPGauge_C"] = 0', 'mark');
  S.must('__PUMP(1)', 'tick1');
  expect('next tick: the reported nameplate got an install pass', S.str('__GAUGE_TOUCHES > __TOUCH_AFTER_HOOK'), (v) => v === 'true');
  expect('...on a tick with no world sweep', S.str('__SEARCHES["WBP_PalNPCHPGauge_C"]'), (v) => v === '0');
  S.must('__T2 = __GAUGE_TOUCHES; __PUMP(1)', 'tick2');
  expect('its Pal did not resolve, so it stays pending and is retried', S.str('__GAUGE_TOUCHES > __T2'), (v) => v === 'true');
  S.must('__GAUGE.IsValid = function() return false end; __PUMP(1); __T3 = __GAUGE_TOUCHES; __PUMP(2)', 'invalid');
  expect('once the nameplate is invalid it is dropped (no more install passes)', S.str('__GAUGE_TOUCHES == __T3'), (v) => v === 'true');

  // Unbind drops a pending nameplate too.
  S.must('__G2 = __obj("WBP_PalNPCHPGauge_C_TWO"); __G2T = 0; __G2.GetFullName = function() __G2T = __G2T + 1; return "WBP_PalNPCHPGauge_C_TWO" end', 'g2');
  S.must('__FIRE("' + BIND + '", __arg(__G2), __arg({ handle = true })); __FIRE("' + UNBIND + '", __arg(__G2))', 'bindunbind');
  S.must('__G2BEFORE = __G2T; __PUMP(2)', 'afterunbind');
  expect('a nameplate unbound before its install pass is dropped', S.str('__G2T == __G2BEFORE'), (v) => v === 'true');
}

console.log('\n=== C2. Indicator: bind hook NOT registered (the sweep must keep running) ===');
{
  const S = indicatorState(false);
  S.must('__SEARCHES["WBP_PalNPCHPGauge_C"] = 0; __PUMP(10)', 'pump10');
  expect('10 ticks without the hook: a world sweep on every tick', S.str('__SEARCHES["WBP_PalNPCHPGauge_C"]'), (v) => v === '10');
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
