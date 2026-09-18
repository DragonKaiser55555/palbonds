// Shipping-state assertions for the emote work: the F7 probe must be OFF, Play
// must still be bound, and Init must not error.
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
}

let e = run(fs.readFileSync(process.argv[3], 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');

e = run('I = require("Interaction"); I.Init()', 'init');
console.log('\n=== SHIPPING STATE ===');
expect('Interaction.Init completes without error', e === null ? 'ok' : e, 'ok');
expect('the F7 emote probe is OFF', str('__BINDS["F7"] == nil'), 'true');
expect('Play (F8) is still bound', str('__BINDS["F8"] ~= nil'), 'true');
expect('the personality-tag toggle (F9) is still bound', str('__BINDS["F9"] ~= nil'), 'true');
expect('the passive-gain toggle (F10) is still bound', str('__BINDS["F10"] ~= nil'), 'true');

// 2026-09-17 — the world-change crash, found by bisect: a keybind callback
// does NOT run on the game thread, and starting an animation from there
// corrupted engine state so the NEXT world load died. Pet and Feed were
// always safe because they arrive through RegisterHook, inside the game's own
// call stack. Every keybind must hop to the game thread before doing anything.
run('__GAME_THREAD_CALLS = 0; __BINDS["F8"]()', 'f8');
expect('F8 hops to the game thread', str('__GAME_THREAD_CALLS'), '1');
run('__GAME_THREAD_CALLS = 0; __BINDS["F9"]()', 'f9');
expect('F9 hops to the game thread', str('__GAME_THREAD_CALLS'), '1');
run('__GAME_THREAD_CALLS = 0; __BINDS["F10"]()', 'f10');
expect('F10 hops to the game thread', str('__GAME_THREAD_CALLS'), '1');

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
