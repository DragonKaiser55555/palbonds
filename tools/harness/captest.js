// 2026-09-12: the per-Pal follow-install cap must be a RATE. It used to be a
// lifetime count, so a companion whose follow action was destroyed 25 times over
// a long session lost following for good (CLAUDE.md, "never budget a retry").
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
function constructs() {
  return Number(str('(function() local n = 0 for _, c in ipairs(__CALLS) do if c == "Construct" then n = n + 1 end end return n end)()'));
}
function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label);
  if (!ok) console.log('        got: ' + actual);
}

let e = run(fs.readFileSync(process.argv[3], 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');
run('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');

e = run('T = require("Trust"); C = require("Combat"); C.Init(); T.Init()', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }
run('T.StartFollowing(__PAL)', 'follow');
// Idle, no hate, and every installed follow action reads as gone straight away:
// the worst-case churn, one rebuild per tick.
run('__CURRENT_ACTION.__name = "BP_AIAction_WildLife_C_9"; __HATE_TARGET = nil; __HAS_ACTION = false', 'churn');

function tick() { run('C.IssueFollowMoveOrder(__PAL, __vec(0, 0, 0), __PLAYER)', 'tick'); }

console.log('\n=== PER-PAL FOLLOW CAP ===');
run('__CALLS = {}', 'clr');
for (let i = 0; i < 35; i++) { run('__CLOCK = __CLOCK + 1', 'adv'); tick(); }
const burst = constructs();
expect('a churn burst is capped (no more than 25 installs in 35s)', String(burst), (v) => Number(v) <= 25 && Number(v) > 0);
expect('the cap is reported', str('table.concat(__ALLLOG, " | ")'), (t) => t.indexOf('per-Pal install cap') !== -1);

run('__CALLS = {}; __CLOCK = __CLOCK + 61', 'roll');
tick();
expect('after the window rolls over, following can be rebuilt again', String(constructs()), (v) => Number(v) >= 1);

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
