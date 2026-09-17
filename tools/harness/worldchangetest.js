// 2026-09-16: the world-change crash (0x338) came back in 1.1.2.
//
// 1.1.1 re-searched for the player every ~4 s from Combat's fast loop; when
// Dragón quit to the menu that search came back empty and the world reset ran.
// 1.1.2's PlayerRef kept handing back the old character, so the reset never
// ran. These checks pin the two things PlayerRef now does about it:
//
//   A. The engine's own IsValid (UKismetSystemLibrary) is asked about the kept
//      character at most once a second; "false" forces a real search, and an
//      empty search returns nil (which is what makes Combat reset).
//   B. While a Pal is following, a real search runs every 4 s — 1.1.1's
//      cadence. With nothing following it does not run (no new stutter).
//   C. End to end: with a follower, quitting (no player in the world any more)
//      makes Combat's fast loop drop every reference.
//
// Usage: node worldchangetest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node worldchangetest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/');
let failures = 0;

function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

function newState() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
    if (st !== lua.LUA_OK) { const m = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_settop(L, 0); return 'LOAD: ' + m; }
    const r = lua.lua_pcall(L, 0, 0, 0);
    if (r !== lua.LUA_OK) {
      const e = lua.lua_tostring(L, -1);
      const msg = e === null ? '(non-string error)' : to_jsstring(e);
      lua.lua_settop(L, 0);
      return msg;
    }
    return null;
  };
  const str = (expr) => {
    const err = run('__OUT = tostring(' + expr + ')', 'ev');
    if (err) return 'ERR: ' + err;
    lua.lua_getglobal(L, to_luastring('__OUT'));
    const s = lua.lua_tostring(L, -1);
    const out = s === null ? 'nil' : to_jsstring(s);
    lua.lua_settop(L, 0);
    return out;
  };
  const must = (code, name) => { const e = run(code, name); if (e) { console.log('  SETUP ERROR (' + name + '): ' + e); failures++; } return e; };
  must(fs.readFileSync(path.join(__dirname, 'prelude_323.lua'), 'utf8'), 'prelude');
  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  must([
    '__CLOCK = 1000.0; os.clock = function() return __CLOCK end',
    '__SEARCHES = 0',
    '__IN_WORLD = true',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then __SEARCHES = __SEARCHES + 1; if __IN_WORLD then return { __PLAYER } end return {} end return nil end',
    '__ENGINE_ALIVE = true',
    // The library CDO must pass UE4SS's obj:IsValid() and answer the engine's
    // kismet:IsValid(p); one function serves both call shapes.
    '__KISMET = { IsValid = function(self, o) if o == nil then return true end return __ENGINE_ALIVE end }',
    'package.loaded["UEHelpers"] = { GetKismetSystemLibrary = function() return __KISMET end, GetPlayer = function() return __PLAYER end }',
    'function __has(x) for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then return true end end return false end',
  ].join('\n'), 'setup');
  return { run, str, must };
}

console.log('\n=== A. The engine says the kept player is gone ===');
{
  const S = newState();
  S.must('R = require("PlayerRef"); __P = R.Get()', 'first');
  S.must('for i = 1, 30 do __CLOCK = __CLOCK + 0.5; __P = R.Get() end', 'alive');
  expect('alive for 15 s, nobody following: only the first search', S.str('__SEARCHES'), (v) => v === '1');
  S.must('__ENGINE_ALIVE = false; __IN_WORLD = false; __CLOCK = __CLOCK + 1; __P = R.Get()', 'torn');
  expect('engine IsValid=false -> searched at once', S.str('__SEARCHES'), (v) => v === '2');
  expect('and with nobody in the world, Get() returns nil', S.str('__P'), (v) => v === 'nil');
  expect('logged as the world going away', S.str('__has("[PLAYER-LIFE] engine IsValid=false") and __has("world going away")'), (v) => v === 'true');
  S.must('__CLOCK = __CLOCK + 0.5; __P = R.Get()', 'miss');
  expect('then the normal 2 s miss wait applies (no search every call)', S.str('__SEARCHES'), (v) => v === '2');
}

console.log('\n=== B. While a Pal follows: a real search every 4 s, and only then ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); T = require("Trust"); T.Init()', 'init');
  S.must('R = require("PlayerRef"); __P = R.Get()', 'first');
  S.must('__BASE = __SEARCHES; for i = 1, 20 do __CLOCK = __CLOCK + 0.5; __P = R.Get() end', 'nofollow');
  expect('10 s with nobody following: no extra search', S.str('__SEARCHES - __BASE'), (v) => v === '0');
  S.must('C.StartFollowing(__PAL); __BASE = __SEARCHES; for i = 1, 24 do __CLOCK = __CLOCK + 0.5; __P = R.Get() end', 'follow');
  expect('12 s with a follower: a search about every 4 s (3)', S.str('__SEARCHES - __BASE'), (v) => v === '3');
  expect('and the player is still returned', S.str('__P == __PLAYER'), (v) => v === 'true');
  S.must('__IN_WORLD = false; __CLOCK = __CLOCK + 4.1; __P = R.Get()', 'quit');
  expect('quit while following: the re-check finds nobody -> nil', S.str('__P'), (v) => v === 'nil');
  expect('logged', S.str('__has("[PLAYER-LIFE] follower re-check")'), (v) => v === 'true');
}

console.log('\n=== C. End to end: the fast loop drops the old world ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); T = require("Trust"); T.Init(); C.StartTrainerReassertLoop(); T.StartFollowing(__PAL)', 'init');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end', 'running');
  expect('(setup) following', S.str('C.HasAnyFollower()'), (v) => v === 'true');
  // Quit: the old character still passes UE4SS IsValid (that was the bug), the
  // engine says otherwise, and the world has no player any more.
  S.must('__ENGINE_ALIVE = false; __IN_WORLD = false; for i = 1, 80 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end', 'quit');
  expect('the world reset ran', S.str('__has("[WORLD-RESET]") and __has("dropped every reference")'), (v) => v === 'true');
  expect('no follower is kept from the old world', S.str('C.HasAnyFollower()'), (v) => v === 'false');
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
