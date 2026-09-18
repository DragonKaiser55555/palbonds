// Pass 325: retaliation is scoped to OUT of combat, never removed outright.
// The assertion that matters most is the one Dragón raised: out of combat a
// companion must still fight back, because Discover_* is Ignore there and
// Damaged_* is its only defence.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');

const dir = process.argv[2];
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
let failures = 0;

function run(code, name) {
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
  if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
  const r = lua.lua_pcall(L, 0, 0, 0);
  if (r !== lua.LUA_OK) {
    const e = lua.lua_tostring(L, -1);
    return to_jsstring(e === null ? to_luastring('(non-string)') : e);
  }
  return null;
}
function str(expr) {
  const err = run('__OUT = tostring(' + expr + ')', 'ev');
  if (err) return 'ERR: ' + err;
  lua.lua_getglobal(L, to_luastring('__OUT'));
  const s = lua.lua_tostring(L, -1);
  return s === null ? 'nil' : to_jsstring(s);
}
function expect(label, actual, wanted) {
  const ok = actual === wanted;
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
  if (!ok) console.log('        wanted: ' + wanted);
}

let e = run(fs.readFileSync(process.argv[3], 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');

// The preset is only applied to a Pal that is NOT already owned.
run('package.preload["Capture"] = function() return { IsAlreadyOwned = function() return false end } end', 'cap');

e = run('P = require("Personality"); P.Init()', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }

// Capture the preset object written onto the sensor.
run('__WRITTEN = nil', 'w0');
run('__SENSOR.AIResponsePreset = nil', 'w1');

function apply(inCombat) {
  run('__WRITTEN = nil', 'clr');
  const err = run('P.ApplyCompanionPreset("ID", __PAL, true, ' + (inCombat ? 'true' : 'false') + ')', 'apply');
  if (err) { console.log('  apply error: ' + err); failures++; }
  run('__WRITTEN = __SENSOR.AIResponsePreset', 'grab');
}

function slot(name) { return str('__WRITTEN and __WRITTEN.' + name); }

console.log('\n=== OUT OF COMBAT (a companion alone must be able to defend itself) ===');
apply(false);
expect('Discover_Equal  = Ignore (does not start fights)', slot('Discover_Equal'), '0');
expect('Damaged_Equal   = Battle (FIGHTS BACK)', slot('Damaged_Equal'), '2');
expect('Damaged_Greater = Battle (FIGHTS BACK)', slot('Damaged_Greater'), '2');
expect('Damaged_Smaller = Battle (FIGHTS BACK)', slot('Damaged_Smaller'), '2');
expect('Discover_Player = Ignore (never its trainer)', slot('Discover_Player'), '0');
expect('Damaged_Player  = Ignore (never its trainer)', slot('Damaged_Player'), '0');

console.log('\n=== DURING THE PLAYER FIGHT (Discover carries the engagement) ===');
apply(true);
expect('Discover_Equal  = Battle (engages what it notices)', slot('Discover_Equal'), '2');
expect('Discover_Greater= Battle (engages what it notices)', slot('Discover_Greater'), '2');
expect('Damaged_Equal   = Ignore (no retaliation pile-on)', slot('Damaged_Equal'), '0');
expect('Damaged_Player  = Ignore (never its trainer)', slot('Damaged_Player'), '0');

// 2026-09-17: the real Personality.ResetForNewWorld runs here. The
// world-change test stubs this module, so that one can only prove Combat
// CALLS it; this proves the real body executes and reports what it dropped.
// (Seeding a record first is not possible here: GetStableId needs a real
// handle, which this prelude does not fake.)
console.log('\n=== WORLD CHANGE (the real reset must run clean) ===');
run('__SAW_RESET = false', 'arm');
const resetErr = run('P.ResetForNewWorld()', 'reset');
expect('it runs without error', resetErr === null ? 'true' : String(resetErr), 'true');
run('for _, m in ipairs(__LOG) do if m:find("[PalBonds/Personality] [WORLD-RESET]", 1, true) then __SAW_RESET = true end end', 'scan');
expect('and says what it dropped', str('__SAW_RESET'), 'true');

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
