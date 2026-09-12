// 2026-09-12, runs 35/36: the recall and the combat assist undid each other.
// A companion must not be sent at an enemy past the recall distance, nor
// pulled out of a recall march to fight. Drives the REAL fast loop for the recall.
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

e = run('T = require("Trust"); C = require("Combat"); C.Init(); T.Init(); C.StartFollowing(__PAL)', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }
run('__CURRENT_ACTION.__name = "BP_AIAction_OtomoFollow_C_1"; __HATE_TARGET = nil', 'idle');

// Enemies at known distances from the player, who stands at the origin.
run([
  '__FAR = __obj("BP_FarEnemy_C_1"); __FAR.K2_GetActorLocation = function() return __vec(5000, 0, 0) end',
  '__NEAR = __obj("BP_NearEnemy_C_2"); __NEAR.K2_GetActorLocation = function() return __vec(600, 0, 0) end',
  '__NEAR2 = __obj("BP_NearEnemy_C_3"); __NEAR2.K2_GetActorLocation = function() return __vec(700, 0, 0) end',
].join('\n'), 'enemies');

console.log('\n=== AN ENEMY PAST THE RECALL DISTANCE ===');
run('C.OnPlayerCombatTarget(__FAR, __PLAYER)', 'far');
expect('companions are NOT sent after it', str('C.IsSuspendedForCombat(__PAL)'), (v) => v === 'false');
expect('and it says why', str('table.concat(__ALLLOG, " | ")'), (t) => t.indexOf('keep following instead of chasing') !== -1);

console.log('\n=== A COMPANION THE RECALL IS MARCHING HOME ===');
// Same setup td2test uses: follow must exist and the fast loop must be running.
run('C.IssueFollowMoveOrder(__PAL, {X=0,Y=0,Z=0}, __PLAYER)', 'buildfollow');
run('C.StartTrainerReassertLoop()', 'startloop');
run('__PAL_LOC = __vec(2500, 0, 0)', 'stray');
run('__PUMP(12)', 'pump');
expect('(setup) the recall engaged', str('table.concat(__ALLLOG, " | ")'), (t) => t.indexOf('[RECALL]') !== -1 && t.indexOf('strayed') !== -1);
run('__CLOCK = __CLOCK + 10; C.OnPlayerCombatTarget(__NEAR, __PLAYER)', 'near');
expect('is NOT pulled out of the march to fight', str('C.IsSuspendedForCombat(__PAL)'), (v) => v === 'false');

console.log('\n=== AND THE NORMAL CASE STILL WORKS ===');
run('__PAL_LOC = __vec(0, 0, 0)', 'home');
run('__PUMP(12)', 'pump2');
run('__CLOCK = __CLOCK + 10; C.OnPlayerCombatTarget(__NEAR2, __PLAYER)', 'near2');
expect('home, enemy in reach -> sent into the fight', str('C.IsSuspendedForCombat(__PAL)'), (v) => v === 'true');

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
