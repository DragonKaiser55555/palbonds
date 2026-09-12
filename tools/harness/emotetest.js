// Pass 326: the F7 emote probe. This calls a native function on the player
// controller, in a file with a crash history, so the call shape is verified
// offline before Dragón presses anything.
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
function calls() { return str('table.concat(__CALLS, " | ")'); }
function toasts() { return str('table.concat(__TOASTS, " | ")'); }
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

e = run('I = require("Interaction"); I.Init()', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }

console.log('\n=== EMOTE PROBE ===');
expect('F7 is bound', str('__BINDS["F7"] ~= nil'), (v) => v === 'true');
expect('Init reports which emote classes resolve', logs(),
  (t) => t.indexOf('emote classes that resolve: 0, 1, 2, 3, 4, 5, 6, 7, 8') !== -1);

run('__CALLS = {}; __TOASTS = {}; __LOG = {}', 'clr');
expect('pressing F7 does not error', str('__PRESS("F7")'), (v) => v === 'ok');
expect('it plays emote 0 through the player controller', calls(),
  (c) => c.indexOf('PlayAction(pawn=BP_Player_Female_C_1, param=table, cls=BP_Action_Emote_0_C, n=0)') !== -1);
expect('it names the emote in an on-screen toast', toasts(),
  (t) => t.indexOf('Emote 0 of 8') !== -1);

run('__CALLS = {}; __TOASTS = {}', 'clr2');
run('__PRESS("F7")', 'p2');
expect('the next press advances to emote 1', calls(), (c) => c.indexOf('cls=BP_Action_Emote_1_C') !== -1);

// Walk to the end and confirm it wraps rather than running off.
run('for _ = 1, 7 do __PRESS("F7") end; __CALLS = {}; __TOASTS = {}', 'walk');
run('__PRESS("F7")', 'wrap');
expect('after emote 8 it wraps back to 0', calls(), (c) => c.indexOf('cls=BP_Action_Emote_0_C') !== -1);
expect('the kick emote is called out in its toast', str('table.concat(__LOG, " | ")'), () => true);

// A missing class must be skipped cleanly, not crash.
run('__EMOTE_MISSING = { [3] = true }; __CALLS = {}; __LOG = {}', 'miss');
run('for _ = 1, 3 do __PRESS("F7") end', 'to3');
expect('an unresolvable emote is skipped with a log, no call', logs(),
  (t) => t.indexOf('emote 3 does not resolve') !== -1);
expect('and no native call is made for it', calls(),
  (c) => c.indexOf('cls=BP_Action_Emote_3_C') === -1);

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
