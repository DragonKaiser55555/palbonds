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
    'function __count(x) local n = 0 for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then n = n + 1 end end return n end',
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

// 2026-09-17: Dragón reproduced a crash on demand with NOTHING following him —
// interact with a wild Pal, quit to the title, load a world. The fast loop's
// world-change check sat below `next(BondingState) == nil`, so with nothing
// bonded the loop returned before it ever looked at the player: no reset, and
// every module kept its references to the old world. These are the checks that
// fail on that code.
console.log('\n=== D. Quitting with NOTHING bonded still drops the old world ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); T = require("Trust"); T.Init(); C.StartTrainerReassertLoop()', 'init');
  S.must([
    // Indicator and Interaction are the real modules here, so their own
    // [WORLD-RESET] lines prove the real functions ran. Personality is stubbed
    // by prelude_323 (it has no ResetForNewWorld), so what is checked for it is
    // that Combat CALLS it — presettest covers the real module.
    'I = require("Indicator"); X = require("Interaction")',
    'P = require("Personality"); __PERS_RESET = 0',
    'P.ResetForNewWorld = function() __PERS_RESET = __PERS_RESET + 1 end',
    'function __count(x) local n = 0 for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then n = n + 1 end end return n end',
  ].join('\n'), 'mods');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 1.0; __PUMP(1) end', 'idle');
  expect('(setup) nothing is following', S.str('C.HasAnyFollower()'), (v) => v === 'false');
  expect('(setup) no reset while the world is up', S.str('__count("[WORLD-RESET] the player")'), (v) => v === '0');
  S.must('__ENGINE_ALIVE = false; __IN_WORLD = false; for i = 1, 5 do __CLOCK = __CLOCK + 1.0; __PUMP(1) end', 'quit');
  expect('the reset ran with no follower at all', S.str('__has("[WORLD-RESET]") and __has("dropped every reference")'), (v) => v === 'true');
  expect('and exactly once, not once per pass', S.str('__count("dropped every reference")'), (v) => v === '1');
  expect('the nameplate and boss bars were dropped', S.str('__has("[PalBonds/Indicator] [WORLD-RESET]")'), (v) => v === 'true');
  expect('Personality was asked to drop its records too', S.str('__PERS_RESET'), (v) => v === '1');
  expect('the radial-menu and aim refs were dropped', S.str('__has("[PalBonds/Interaction] [WORLD-RESET]")'), (v) => v === 'true');
  expect('the bonding records were dropped too', S.str('__has("[PalBonds/Trust] [WORLD-RESET]")'), (v) => v === 'true');
  // A new world comes up: the watch must re-arm, or the next quit goes unnoticed.
  S.must('__ENGINE_ALIVE = true; __IN_WORLD = true; for i = 1, 5 do __CLOCK = __CLOCK + 1.0; __PUMP(1) end', 'newworld');
  expect('a new world re-arms the watch', S.str('__has("a new world is up")'), (v) => v === 'true');
  S.must('__ENGINE_ALIVE = false; __IN_WORLD = false; for i = 1, 5 do __CLOCK = __CLOCK + 1.0; __PUMP(1) end', 'quit2');
  expect('and the SECOND quit resets again', S.str('__count("dropped every reference")'), (v) => v === '2');
}

console.log('\n=== E. The ESC menu quit hook only speeds the watch up ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); C.StartTrainerReassertLoop()', 'init');
  S.must('for i = 1, 5 do __CLOCK = __CLOCK + 1.0; __PUMP(1) end', 'idle');
  S.must('C.ExpectWorldChange("test")', 'expect');
  expect('nothing is dropped when the player merely asks to quit', S.str('__has("dropped every reference")'), (v) => v === 'false');
  expect('logged as watching, nothing dropped', S.str('__has("nothing dropped yet")'), (v) => v === 'true');
  // 300ms of a 100ms loop: too soon for the 1 s cadence, in time for the 200ms one.
  S.must('__ENGINE_ALIVE = false; __IN_WORLD = false; for i = 1, 3 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end', 'quit');
  expect('the world going away is caught within 300 ms', S.str('__has("dropped every reference")'), (v) => v === 'true');
}

// 2026-09-17, second crash: the quit hook fired and the log ENDED there — the
// game serviced no further loop pass before the world was gone. So noticing the
// world change afterwards cannot work, and everything must be released inside
// the hook, while the world is still alive. F covers that release; G covers the
// two ways it can end.
console.log('\n=== F. A confirmed quit releases everything inside the hook ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); T = require("Trust"); T.Init(); C.StartTrainerReassertLoop(); T.StartFollowing(__PAL)', 'init');
  S.must('R = require("PlayerRef"); for i = 1, 20 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end', 'running');
  expect('(setup) following, player readable', S.str('C.HasAnyFollower() and R.Get() ~= nil'), (v) => v === 'true');
  // The confirm hook fires. NOTHING is pumped afterwards: that is the real
  // shape of a quit, and the reason detection alone failed in game.
  S.must('C.OnQuitConfirmed("test confirm")', 'confirm');
  expect('everything was dropped in the hook itself', S.str('__has("dropped every reference")'), (v) => v === 'true');
  expect('no follower survives the quit', S.str('C.HasAnyFollower()'), (v) => v === 'false');
  expect('the player is handed to nobody while the world closes', S.str('R.Get()'), (v) => v === 'nil');
  expect('and the modules are told to stop touching anything', S.str('C.IsShuttingDown()'), (v) => v === 'true');
  S.must('C.OnQuitConfirmed("test confirm again")', 'again');
  expect('a second confirm does not reset twice', S.str('__count("dropped every reference")'), (v) => v === '1');
}

console.log('\n=== G. How a closing world ends: new world, or a cancelled quit ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); C.StartTrainerReassertLoop(); R = require("PlayerRef")', 'init');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end; C.OnQuitConfirmed("quit")', 'confirm');
  // The next world's player is a different actor at a different address.
  S.must('__NEWPLAYER = __obj("BP_Player_Female_C_99"); __NEWPLAYER.GetAddress = function() return 999999 end', 'newp');
  S.must('FindAllOf = function(n) if n == "PalPlayerCharacter" then return { __NEWPLAYER } end return nil end', 'swap');
  S.must('for i = 1, 30 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'load');
  expect('a different player = the new world is up', S.str('__has("a new world is up")'), (v) => v === 'true');
  expect('and the player is handed out again', S.str('R.Get() ~= nil'), (v) => v === 'true');
}
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); C.StartTrainerReassertLoop(); R = require("PlayerRef")', 'init');
  S.must('for i = 1, 20 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end; C.OnQuitConfirmed("quit")', 'confirm');
  // Cancelled: the SAME player is still standing there.
  S.must('for i = 1, 6 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'soon');
  expect('a few seconds in, it is still treated as closing', S.str('R.IsWorldClosing()'), (v) => v === 'true');
  S.must('for i = 1, 30 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'later');
  expect('the same player after 10 s = the quit was cancelled', S.str('__has("the quit was CANCELLED")'), (v) => v === 'true');
  expect('and the mod works again in that world', S.str('R.Get() ~= nil and not C.IsShuttingDown()'), (v) => v === 'true');
}

// 2026-09-17, third crash: releasing at the confirm was still not enough. The
// log's last line was a personality read that came back "PalAIResponsePreset"
// (the engine's raw base name — what reading a half-destroyed object looks
// like), so the game was still calling our HOOKS while it tore the world down.
// UE4SS cannot unregister a hook here, so every hook callback has to go quiet
// on its own while a quit is in progress.
console.log('\n=== H. While the world closes, every hook goes quiet ===');
{
  const S = newState();
  S.must('C = require("Combat"); C.Init(); T = require("Trust"); T.Init(); C.StartTrainerReassertLoop(); T.StartFollowing(__PAL)', 'init');
  S.must('R = require("PlayerRef"); for i = 1, 20 do __CLOCK = __CLOCK + 0.1; __PUMP(1) end', 'running');
  // The hate hook is the busiest of them: it fires on every hit.
  S.must('__LOG = {}; __FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __PAL, Defender = __PLAYER, Damage = 10 }))', 'hit-before');
  expect('(setup) a hit is processed while the world is up', S.str('#__LOG > 0'), (v) => v === 'true');
  S.must('C.OnQuitConfirmed("test confirm")', 'confirm');
  expect('the gate is closed', S.str('R.IsWorldClosing()'), (v) => v === 'true');
  S.must('__LOG = {}; __FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __PAL, Defender = __PLAYER, Damage = 10 }))', 'hit-after');
  expect('the same hit during teardown does nothing at all', S.str('#__LOG'), (v) => v === '0');
  // And the gate cannot strand the mod: it gives up waiting after a minute.
  S.must('__CLOCK = __CLOCK + 61.0', 'later');
  expect('after a minute with no new world it stops holding back', S.str('R.IsWorldClosing()'), (v) => v === 'false');
  expect('and says so', S.str('__has("giving up waiting")'), (v) => v === 'true');
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
