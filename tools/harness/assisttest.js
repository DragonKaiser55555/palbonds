// REGRESSION TEST for run 31: the world-wide damage hook must still reach
// Combat.OnPlayerCombatTarget when the player hits a wild enemy.
//
// Pass 331 added an address gate to that hook to stop two wild Pals brawling in
// the distance from costing two GetFullName() path builds per hit. The gate was
// built from State (the bonded Pals) only -- but in a player-versus-wild hit
// NEITHER side is a bonded Pal, so it rejected the single event the whole
// combat-assist feature depends on. Run 31: zero [HATE-ASSIST] lines.
//
// This test drives the REAL registered hook rather than calling internals.
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

// Pass "noaddr" to simulate a build where UObject:GetAddress() does not work.
const noAddr = process.argv[4] === 'noaddr';
if (noAddr) {
  run('__NO_ADDRESS = true', 'noaddr');
  console.log('  (running with GetAddress() unavailable — the gate must fail OPEN)');
}

// Record every call into Combat.OnPlayerCombatTarget.
e = run('T = require("Trust"); C = require("Combat"); C.Init(); T.Init()', 'init');
if (e) { console.log('INIT: ' + e); process.exit(1); }
run([
  '__ASSIST = {}',
  '__realOPCT = C.OnPlayerCombatTarget',
  'C.OnPlayerCombatTarget = function(enemy)',
  '  __ASSIST[#__ASSIST+1] = tostring(enemy and enemy.__name)',
  '  return __realOPCT(enemy)',
  'end'
].join('\n'), 'spy');

// A Pal must be bonding, or the outer `next(State) == nil` guard short-circuits
// before the address gate is ever reached.
run('T.StartFollowing(__PAL)', 'follow');

const HOOK = '/Script/Pal.PalHate:DamageEvent';
expect('the damage hook is registered', str('__HOOKS["' + HOOK + '"] ~= nil'), (v) => v === 'true');

function hit(attacker, defender) {
  run('__ASSIST = {}; __CLOCK = __CLOCK + 5', 'reset');
  return run('__FIRE("' + HOOK + '", nil, __arg({ Attacker = ' + attacker +
             ', Defender = ' + defender + ', Damage = 10 }))', 'fire');
}

console.log('\n=== THE RUN-31 REGRESSION ===');
hit('__PLAYER', '__ENEMY');
expect('player hits a wild enemy -> combat assist is told about it',
  str('table.concat(__ASSIST, ",")'), (v) => v.indexOf('BP_EnemyPal_C_9') !== -1);

hit('__ENEMY', '__PLAYER');
expect('a wild enemy hits the player -> also counts as the player\'s enemy',
  str('table.concat(__ASSIST, ",")'), (v) => v.indexOf('BP_EnemyPal_C_9') !== -1);

console.log('\n=== AND THE SAVING THAT GATE EXISTS FOR ===');
run('__LOG = {}', 'clearlog');
hit('__BYSTANDER', '__ENEMY');
if (noAddr) {
  expect('with no addresses the gate lets everything through (fail open)',
    str('table.concat(__ALLLOG, " | ")'), (t) => t.indexOf('[DAMAGE-GATE]') !== -1);
} else {
  expect('two wild Pals brawling -> ignored before any name is built',
    str('#__ASSIST'), (v) => v === '0');
}

// A hit ON one of our Pals does not go through OnPlayerCombatTarget (only the
// player's own hits do) -- it takes the trust-penalty path, so assert that.
run('__LOG = {}', 'clearlog2');
hit('__ENEMY', '__PAL');
expect('a wild enemy hits one of OUR Pals -> reaches the trust path',
  str('table.concat(__LOG, " | ")'),
  (t) => t.indexOf('damaged by something other than the player') !== -1);

if (!noAddr) {
  expect('the gate did NOT have to fall back to open',
    str('table.concat(__ALLLOG, " | ")'), (t) => t.indexOf('[DAMAGE-GATE]') === -1);
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
