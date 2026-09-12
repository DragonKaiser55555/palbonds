// 2026-09-12, run 37: hit lag. The damage hooks looked the player up with a full
// FindAllOf walk up to three times PER damage event. Fires the REAL hooks many
// times and counts how often the object array is actually walked.
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
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

let e = run(fs.readFileSync(process.argv[3], 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');
run('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');
// Count real walks for the player.
run([
  '__WALKS = 0',
  'local realFindAllOf = FindAllOf',
  'FindAllOf = function(n) if n == "PalPlayerCharacter" then __WALKS = __WALKS + 1 end return realFindAllOf(n) end',
].join('\n'), 'count');

e = run('T = require("Trust"); C = require("Combat"); C.Init(); T.Init(); T.StartFollowing(__PAL)', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }

const HATE = '/Script/Pal.PalHate:DamageEvent';
const BETRAY = '/Script/Pal.PalDamageReactionComponent:OnProcessedActualDamageDelegate__DelegateSignature';
function hate(a, d) { run('__FIRE("' + HATE + '", nil, __arg({ Attacker = ' + a + ', Defender = ' + d + ', Damage = 10 }))', 'h'); }
function betray(a, d) { run('__FIRE("' + BETRAY + '", nil, __arg(' + a + '), __arg(' + d + '), __arg(10))', 'b'); }

console.log('\n=== A MULTI-HIT BURST: 30 hits inside one second ===');
run('__WALKS = 0', 'reset');
for (let i = 0; i < 10; i++) {
  hate('__PLAYER', '__ENEMY');   // the player hitting an enemy
  hate('__ENEMY', '__PAL');      // an enemy hitting a companion
  betray('__ENEMY', '__PAL');    // same hit through the damage-reaction delegate
}
expect('the player is looked up at most twice for 30 hits', str('__WALKS'), (v) => Number(v) <= 2);

console.log('\n=== THE CACHE STILL NOTICES A NEW PLAYER ===');
run('__WALKS = 0; __CLOCK = __CLOCK + 3', 'age');
hate('__PLAYER', '__ENEMY');
expect('after the cache ages out, the next hit looks the player up again', str('__WALKS'), (v) => Number(v) >= 1);

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
