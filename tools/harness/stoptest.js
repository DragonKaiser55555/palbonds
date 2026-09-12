// 2026-09-12: a Pal that stops following (joins the party, betrayal, bond lost)
// must not stay in the fight bookkeeping. Run 33 showed the combat-window close
// trying to rebuild follow on a Petallia that had joined 9 seconds earlier.
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

e = run('T = require("Trust"); C = require("Combat"); C.Init(); T.Init()', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }
e = run('T.StartFollowing(__PAL)', 'follow');
if (e) { console.log('STARTFOLLOW: ' + e); process.exit(1); }

console.log('\n=== FIGHT STATE IS DROPPED WITH THE BOND ===');

e = run('C.OnPlayerCombatTarget(__ENEMY)', 'fight');
expect('a player fight suspends follow on the companion', str('C.IsSuspendedForCombat(__PAL)'),
  (v) => v === 'true');

e = run('__LOG = {}; C.StopFollowing(__PAL)', 'stop');
expect('StopFollowing completes', e === null ? 'ok' : e, (v) => v === 'ok');
expect('after StopFollowing it is no longer suspended for combat', str('C.IsSuspendedForCombat(__PAL)'),
  (v) => v === 'false');

if (failures > 0) console.log('\n--- last log ---\n' + logs());
console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
