// 2026-09-12, run 34: a companion hit by something while the player is NOT
// fighting must fight back (only that Pal), and return to follow once the fight
// goes quiet. Fires the REAL damage hook and drives the REAL follow tick.
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
function count(needle) {
  return Number(str('(function() local n = 0 for _, m in ipairs(__ALLLOG) do if m:find("' +
    needle + '", 1, true) then n = n + 1 end end return n end)()'));
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
run('T.StartFollowing(__PAL); T.StartFollowing(__PAL2)', 'follow');
run('__CURRENT_ACTION.__name = "BP_AIAction_OtomoFollow_C_1"; __HATE_TARGET = nil', 'idle');

const HOOK = '/Script/Pal.PalHate:DamageEvent';
function hit(attacker, defender) {
  return run('__FIRE("' + HOOK + '", nil, __arg({ Attacker = ' + attacker +
             ', Defender = ' + defender + ', Damage = 10 }))', 'fire');
}
function advance(s) { run('__CLOCK = __CLOCK + ' + s, 'adv'); }
function tick() { run('C.IssueFollowMoveOrder(__PAL, __vec(0, 0, 0), __PLAYER)', 'tick'); }

console.log('\n=== A WILD PAL ATTACKS A COMPANION, PLAYER NOT FIGHTING ===');
run('__LOG = {}; __CALLS = {}', 'clr');
hit('__ENEMY', '__PAL');
expect('it fights back ([SELF-DEFENCE] logged)', logs(), (t) => t.indexOf('[SELF-DEFENCE]') !== -1);
expect('its follow is suspended for the fight', str('C.IsSuspendedForCombat(__PAL)'), (v) => v === 'true');
expect('a combat action is installed', str('table.concat(__CALLS, ",")'), (t) => t.indexOf('Construct') !== -1);
expect('hate is pushed at the attacker', str('table.concat(__CALLS, ",")'),
  (t) => t.indexOf('ChangeHate(BP_EnemyPal_C_9') !== -1);
expect('only the Pal that was hit responds', str('C.IsSuspendedForCombat(__PAL2)'), (v) => v === 'false');

const engagedOnce = count('[SELF-DEFENCE]');
advance(1); hit('__ENEMY', '__PAL');
expect('a second hit from the same attacker does not re-engage', String(count('[SELF-DEFENCE]')),
  (v) => Number(v) === engagedOnce);

console.log('\n=== THE FIGHT LASTS WHILE HITS KEEP LANDING ===');
run('__CURRENT_ACTION.__name = "BP_AIAction_CombatPal_C_5"; __HATE_TARGET = __ENEMY', 'fighting');
// Kept inside the 25s suspension ceiling on purpose, so what ends the fight
// below is the self-defence window and not that older backstop.
advance(2); hit('__PAL', '__ENEMY');   // t=3: the companion lands a hit
advance(10); run('__LOG = {}', 'clr'); tick();
expect('13s after being attacked, 10s after its own hit -> still fighting',
  str('C.IsSuspendedForCombat(__PAL)'), (v) => v === 'true');

console.log('\n=== ...AND ENDS WHEN IT GOES QUIET ===');
run('__CURRENT_ACTION.__name = "BP_AIAction_WildLife_C_9"; __HATE_TARGET = nil', 'quiet');
advance(10); run('__LOG = {}', 'clr'); tick();   // t=23: 20s since the last hit
expect('no hits either way for the window -> back to follow', logs(),
  (t) => t.indexOf('self-defence over') !== -1);
expect('no longer suspended', str('C.IsSuspendedForCombat(__PAL)'), (v) => v === 'false');

console.log('\n=== WHAT MUST NOT START A FIGHT ===');
advance(1); run('__LOG = {}', 'clr');
hit('__PAL2', '__PAL');
expect('another companion clipping it (friendly fire) -> no self-defence', logs(),
  (t) => t.indexOf('[SELF-DEFENCE]') === -1);

run([
  '__OTOMO = __obj("BP_PartyPal_C_3")',
  '__OTOMO.CharacterParameterComponent = { IsValid = function() return true end, IsOtomo = function() return true end }'
].join('\n'), 'otomo');
advance(1); run('__LOG = {}', 'clr');
hit('__OTOMO', '__PAL');
expect('the player\'s own party Pal clipping it -> no self-defence', logs(),
  (t) => t.indexOf('[SELF-DEFENCE]') === -1);

run('C.OnPlayerCombatTarget(__ENEMY)', 'playerfight');
advance(1); run('__LOG = {}', 'clr');
hit('__BYSTANDER', '__PAL');
expect('during a player fight -> the player-fight path owns it, no self-defence', logs(),
  (t) => t.indexOf('[SELF-DEFENCE]') === -1);

if (failures > 0) console.log('\n--- all log ---\n' + str('table.concat(__ALLLOG, "\\n")'));
console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
