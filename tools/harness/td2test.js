// Pass 323: target discipline (hate-driven, fail-safe) and the force-march recall.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');

const dir = process.argv[2];
const prelude = process.argv[3];
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

let failures = 0;

function run(code, name) {
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'chunk'));
  if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
  const r = lua.lua_pcall(L, 0, 0, 0);
  if (r !== lua.LUA_OK) {
    const e = lua.lua_tostring(L, -1);
    return to_jsstring(e === null ? to_luastring('(non-string error)') : e);
  }
  return null;
}

function str(expr) {
  const err = run('__OUT = tostring(' + expr + ')', 'eval');
  if (err) return 'ERR: ' + err;
  lua.lua_getglobal(L, to_luastring('__OUT'));
  const s = lua.lua_tostring(L, -1);
  return s === null ? 'nil' : to_jsstring(s);
}

function calls() { return str('table.concat(__CALLS, ", ")'); }
function logs() { return str('table.concat(__LOG, " | ")'); }

function expect(label, actual, wanted) {
  const ok = wanted(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label);
  if (!ok) console.log('        got: ' + actual);
}

let e = run(fs.readFileSync(prelude, 'utf8'), 'prelude');
if (e) { console.log('PRELUDE FAILED: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'path');

e = run('C = require("Combat"); C.Init(); C.StartFollowing(__PAL); C.StartFollowing(__PAL2)', 'init');
if (e) { console.log('INIT FAILED: ' + e); process.exit(1); }

// ------------------------------------------------------- target discipline
console.log('\n=== TARGET DISCIPLINE ===');

function td(label, setup, check) {
  run(setup + '; __LOG = {}; __CALLS = {}', 'setup');
  const err = run('C.IssueFollowMoveOrder(__PAL, {X=0,Y=0,Z=0}, __PLAYER)', 'tick');
  if (err) { console.log('  FAIL  ' + label + '  (lua error: ' + err + ')'); failures++; return; }
  check(label);
}

// The player is fighting __ENEMY.
run('__HATE_TARGET = __ENEMY', 'a');
run('C.OnPlayerCombatTarget(__ENEMY)', 'engage');

td("fights the player's enemy -> LEFT ALONE",
  '__HATE_TARGET = __ENEMY',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') === -1));

td('fights the PLAYER -> cancelled',
  '__HATE_TARGET = __PLAYER',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') !== -1));

td('fights ANOTHER BONDED COMPANION -> cancelled',
  '__HATE_TARGET = __PAL2',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') !== -1));

td('fights a bystander DURING the player fight -> cancelled',
  '__HATE_TARGET = __BYSTANDER',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') !== -1));

// THE REGRESSION TEST for run 27: an unreadable target must not cancel.
td('target UNREADABLE -> left alone (run-27 regression)',
  '__HATE_TARGET = nil',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') === -1));

// RUN-28 REGRESSION. Dragón ran out of arrows, hit his own Petallia in melee,
// and that set her as his "current enemy" -- so target discipline cancelled
// every companion fighting the real goat. Hitting your own Pal must not touch
// the player's real target.
run('__HATE_TARGET = __ENEMY; __LOG = {}; __CALLS = {}', 'pre');
run('C.OnPlayerCombatTarget(__ENEMY)', 'realenemy');
run('__LOG = {}', 'clearlog');
run('C.OnPlayerCombatTarget(__PAL2)', 'hit own pal');
expect('hitting a companion is refused and logged', logs(),
  (t) => t.indexOf('one of our own companions') !== -1);
td("hit your own Pal, then a companion fights your real enemy -> LEFT ALONE",
  '__HATE_TARGET = __ENEMY',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') === -1));

// Out of combat, a companion defending itself against a wild Pal is its own business.
run('C.ResetForNewWorld("test"); C.StartFollowing(__PAL); C.StartFollowing(__PAL2)', 'reset');
td('fights a bystander OUT of combat -> left alone (self-defence)',
  '__HATE_TARGET = __BYSTANDER',
  (l) => expect(l, calls(), (c) => c.indexOf('Terminate') === -1));

// -------------------------------------------------------------- the recall
console.log('\n=== FORCE-MARCH RECALL (through the real fast loop) ===');

// Realistic state: the follower tick has run at least once, so the follow
// action exists exactly as it would in game.
run('__HATE_TARGET = __ENEMY', 'r0');
run('C.IssueFollowMoveOrder(__PAL, {X=0,Y=0,Z=0}, __PLAYER)', 'buildfollow');
run('__LOG = {}; __CALLS = {}', 'r1');
run('C.StartTrainerReassertLoop()', 'startloop');
console.log('  (diagnostic) is __PAL following = ' + str('C.IsFollowing(__PAL)'));

// Inside the recall distance: nothing should happen.
run('__PAL_LOC = __vec(100, 0, 0); __LOG = {}; __CALLS = {}', 'near');
run('__PUMP(12)', 'pump');
expect('inside 1800 units -> no march', calls(), (c) => c.indexOf('SimpleMoveToActor') === -1);

// Strayed well past the recall distance.
run('__PAL_LOC = __vec(2500, 0, 0); __LOG = {}; __CALLS = {}', 'far');
run('__PUMP(12)', 'pump');
const farCalls = calls();
expect('past 1800 units -> action cancelled', farCalls, (c) => c.indexOf('AllCancelAction') !== -1);
expect('past 1800 units -> marched at the player', farCalls, (c) => c.indexOf('SimpleMoveToActor(BP_Player_Female_C_2147477654)') !== -1);
expect('past 1800 units -> logs the recall', logs(), (t) => t.indexOf('[RECALL]') !== -1 && t.indexOf('marched back to you') !== -1);
expect('recall no longer pushes negative hate', farCalls, (c) => c.indexOf('ChangeHate') === -1);

// Came home again.
run('__PAL_LOC = __vec(200, 0, 0); __LOG = {}; __CALLS = {}', 'home');
run('__PUMP(12)', 'pump');
expect('returning inside the limit -> reported and cleared', logs(), (t) => t.indexOf('the march worked') !== -1);

// --------------------------------------------------------------- summary
if (failures > 0) {
  console.log('\n--- diagnostic dump ---');
  console.log('LOG: ' + logs());
  console.log('CALLS: ' + calls());
  console.log('pending callbacks: ' + str('#__PENDING'));
  console.log('has any follower: ' + str('C.HasAnyFollower()'));
}
console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
