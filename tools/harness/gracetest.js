// Pass 323: a follower past the leash gets a grace period instead of losing the
// bond in the same instant. Drives the REAL Trust tick.
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
function logs() { return str('table.concat(__LOG, " | ")'); }
function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label);
  if (!ok) console.log('        got: ' + actual);
}

let e = run(fs.readFileSync(process.argv[3], 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');

// Controllable clock, so the grace window can be stepped through deliberately.
run('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');

e = run('T = require("Trust"); C = require("Combat"); C.Init(); T.Init()', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }

e = run('T.StartFollowing(__PAL)', 'follow');
if (e) { console.log('STARTFOLLOW: ' + e); process.exit(1); }
console.log('  (diagnostic) following = ' + str('#T.GetFollowingSnapshot()'));

function tick() { run('__PUMP(1)', 'pump'); }
function clear() { run('__LOG = {}; __CALLS = {}', 'clr'); }
function at(x) { run('__PAL_LOC = __vec(' + x + ', 0, 0)', 'loc'); }
function advance(s) { run('__CLOCK = __CLOCK + ' + s, 'adv'); }

console.log('\n=== DRIFT GRACE PERIOD ===');

// 1. Past the leash while fighting -> protected, no clock.
run('__HATE_TARGET = __ENEMY', 'fighting');
at(4000); clear(); tick();
expect('past the leash but FIGHTING -> protected', logs(),
  (t) => t.indexOf('away FIGHTING') !== -1 && t.indexOf('losing all trust') === -1);

// 2. Fight over (no hate target, no combat action) -> the clock starts, bond alive.
run('__HATE_TARGET = nil; __CURRENT_ACTION.__name = "BP_AIAction_WildLife_C_9"', 'idle');
clear(); tick();
expect('fight over, still far -> grace starts, bond alive', logs(),
  (t) => t.indexOf('has 15s to return') !== -1 && t.indexOf('losing all trust') === -1);

// 3. Inside the window -> nothing happens.
advance(10); clear(); tick();
expect('inside the grace window -> still alive', logs(),
  (t) => t.indexOf('losing all trust') === -1);

// 4. Comes home -> cleared, and it says so.
at(100); clear(); tick();
expect('came back inside the leash -> grace cleared', logs(),
  (t) => t.indexOf('made it back inside the leash') !== -1);

// 5. Strays again and never returns -> the bond ends, but only after the window.
at(4000); clear(); tick();
expect('strays again -> a FRESH grace window, not the old one', logs(),
  (t) => t.indexOf('has 15s to return') !== -1 && t.indexOf('losing all trust') === -1);

advance(20); clear(); tick();
expect('window expired while still away -> bond ends', logs(),
  (t) => t.indexOf('did not come back within 15s') !== -1);

// ------------------------------------------------------------------
console.log('\n=== Combat.IsBusyFighting ===');
run('__HATE_TARGET = nil; __CURRENT_ACTION.__name = "BP_AIAction_CombatPal_C_5"', 'c1');
expect('running a combat action -> busy', str('C.IsBusyFighting(__PAL)'), (v) => v === 'true');
run('__CURRENT_ACTION.__name = "BP_AIAction_WildLife_C_9"; __HATE_TARGET = __ENEMY', 'c2');
expect('idle action but a live hate target -> busy', str('C.IsBusyFighting(__PAL)'), (v) => v === 'true');
run('__HATE_TARGET = nil', 'c3');
expect('idle action and no hate target -> not busy', str('C.IsBusyFighting(__PAL)'), (v) => v === 'false');

if (failures > 0) {
  console.log('\n--- last log ---\n' + logs());
}
console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
