// 2026-09-12: the player's cheer must stop when the Pal's Play animation ends,
// and nothing else the player is doing may be cancelled by it.
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

run([
  'local function ok(t) t.IsValid = function() return true end return t end',
  '__CANCELLED = {}',
  '__CURRENT = nil',
  '__AC = ok({ GetCurrentAction = function() return __CURRENT end,',
  '            CancelAction = function(self, a) __CANCELLED[#__CANCELLED + 1] = a:GetFullName() end })',
  '__P = ok({ ActionComponent = __AC })',
  'function __action(name) return ok({ GetFullName = function() return name end }) end',
].join('\n'), 'stubs');

e = run('I = require("Interaction")', 'load');
if (e) { console.log('LOAD: ' + e); process.exit(1); }

console.log('\n=== STOPPING THE CHEER ===');
run('__CANCELLED = {}; __CURRENT = __action("BP_Action_Emote_0_C /Game/X.BP_Action_Emote_0_C_2147000001")', 'emote');
expect('the cheer is still playing -> it is cancelled', str('I.StopPlayerCheer(__P)'), 'true');
expect('exactly that action was cancelled', str('#__CANCELLED'), '1');

run('__CANCELLED = {}; __CURRENT = __action("BP_Action_SwordAttack_C_2147000002")', 'attack');
expect('the player is attacking instead -> left alone', str('I.StopPlayerCheer(__P)'), 'false');
expect('nothing was cancelled', str('#__CANCELLED'), '0');

run('__CANCELLED = {}; __CURRENT = nil', 'idle');
expect('the player already moved (no action) -> nothing to do, no error', str('I.StopPlayerCheer(__P)'), 'false');
expect('no player at all -> no error', str('I.StopPlayerCheer(nil)'), 'false');

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
