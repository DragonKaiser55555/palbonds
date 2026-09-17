// 2026-09-15: the development profiler (Profiler.lua). It wraps the UE4SS
// globals every module depends on, so the checks that matter are the ones a
// broken wrapper would silently fail:
//   * OFF (as shipped): nothing is replaced, and the mod registers its 15 hooks (14 + the boss bar hook, 2026-09-16).
//   * ON: the mod still registers the same 15 hooks, in the same order.
//   * ON: a wrapped callback passes through every return value (LoopAsync's
//     "true" stops its loop), re-raises errors, and wraps post-callbacks too.
//   * ON: stalls and world searches are recorded and reported, and a report is
//     never written in the middle of a nested callback.
//
// Usage: node profiletest.js <SCRIPTS>
//
// fengari has no io.open, so each Lua state gets an in-memory one: every file
// opened in "w" mode writes into the global __FILE, "r" mode reads it back, and
// __OPENS counts opens. The profiler itself only ever pcalls io.open, which is
// also what keeps it silent in-game if the file cannot be created.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node profiletest.js <SCRIPTS>'); process.exit(2); }
const profilerSrc = fs.readFileSync(path.join(dir, 'Profiler.lua'), 'utf8');
const preludeSrc = fs.readFileSync(path.join(__dirname, 'prelude.lua'), 'utf8');
const scriptsDir = dir.replace(/\\/g, '/');
let failures = 0;

function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

const FAKE_IO = [
  '__FILE = ""',
  '__OPENS = 0',
  'io = io or {}',
  'io.open = function(name, mode)',
  '  __OPENS = __OPENS + 1',
  '  mode = mode or "r"',
  '  if mode:find("w") then __FILE = "" end',
  '  return {',
  '    write = function(self, s) __FILE = __FILE .. tostring(s) return self end,',
  '    flush = function() return true end,',
  '    close = function() return true end,',
  '    read = function() return __FILE end,',
  '  }',
  'end',
].join('\n');

function newState() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
    if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
    const r = lua.lua_pcall(L, 0, 0, 0);
    if (r !== lua.LUA_OK) {
      const e = lua.lua_tostring(L, -1);
      return e === null ? '(non-string error)' : to_jsstring(e);
    }
    return null;
  };
  const str = (expr) => {
    const err = run('__OUT = tostring(' + expr + ')', 'ev');
    if (err) return 'ERR: ' + err;
    lua.lua_getglobal(L, to_luastring('__OUT'));
    const s = lua.lua_tostring(L, -1);
    return s === null ? 'nil' : to_jsstring(s);
  };
  const e = run(FAKE_IO, 'fake-io');
  if (e) throw new Error('fake io: ' + e);
  return { run, str, file: () => str('__FILE'), opens: () => Number(str('__OPENS')) };
}

// The profiler with its switch turned on, loaded through package.preload so
// the shipped file on disk is never modified.
function preloadProfilerOn(S) {
  const patched = profilerSrc.replace('local PROFILING = false', 'local PROFILING = true');
  const err = S.run('package.preload["Profiler"] = load(' + JSON.stringify(patched) + ', "=Profiler.lua")', 'preload');
  if (err) throw new Error('preload: ' + err);
}

function loadMain(profilingOn) {
  const S = newState();
  S.run('__HOOKS = {}', 'hooks');
  let e = S.run(preludeSrc, 'prelude');
  if (e) throw new Error('prelude: ' + e);
  S.run('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  S.run('__ORIG = { RegisterHook = RegisterHook, FindAllOf = FindAllOf, ExecuteInGameThreadWithDelay = ExecuteInGameThreadWithDelay, LoopAsync = LoopAsync, RegisterKeyBind = RegisterKeyBind }', 'orig');
  if (profilingOn) preloadProfilerOn(S);
  e = S.run('dofile("' + scriptsDir + '/main.lua")', 'main');
  if (e) throw new Error('main: ' + e);
  return S;
}

console.log('\n=== SHIPPED STATE: the switch is off in the source ===');
expect('Profiler.lua contains "local PROFILING = false" exactly once',
  (profilerSrc.match(/local PROFILING = false/g) || []).length, (v) => v === 1);
expect('Profiler.lua does not contain "local PROFILING = true"',
  profilerSrc.includes('local PROFILING = true'), (v) => v === false);

console.log('\n=== OFF: main.lua loads, nothing is replaced ===');
const off = loadMain(false);
const offHooks = off.str('table.concat(__HOOKS, "|")');
expect('15 hooks registered', off.str('#__HOOKS'), (v) => v === '15');
for (const g of ['RegisterHook', 'FindAllOf', 'ExecuteInGameThreadWithDelay', 'LoopAsync', 'RegisterKeyBind']) {
  expect(g + ' is the original function', off.str('rawequal(' + g + ', __ORIG.' + g + ')'), (v) => v === 'true');
}
expect('Profiler.start() returns nil', off.str('require("Profiler").start()'), (v) => v === 'nil');
expect('no file is opened by anything at load', off.opens(), (v) => v === 0);

console.log('\n=== ON: main.lua loads, the same hooks register ===');
const on = loadMain(true);
expect('15 hooks registered', on.str('#__HOOKS'), (v) => v === '15');
expect('same hook paths in the same order', on.str('table.concat(__HOOKS, "|")') === offHooks, (v) => v === true);
expect('RegisterHook was replaced', on.str('rawequal(RegisterHook, __ORIG.RegisterHook)'), (v) => v === 'false');
expect('FindAllOf was replaced', on.str('rawequal(FindAllOf, __ORIG.FindAllOf)'), (v) => v === 'false');
expect('the profile file got its start line', on.file().includes('PalBonds profiler started'), (v) => v === true);

console.log('\n=== ON: wrappers pass everything through ===');
const U = newState();
U.run([
  '__CLOCK = 100.0; os.clock = function() return __CLOCK end',
  '__CAP = {}',
  'RegisterHook = function(path, pre, post) __CAP.pre = pre; __CAP.post = post; return 7, 8 end',
  'LoopAsync = function(ms, fn) __CAP.loop = fn; return true end',
  'RegisterKeyBind = function(key, mods, fn) __CAP.keyMods = mods; __CAP.key = fn; return true end',
  'ExecuteInGameThreadWithDelay = function(ms, fn) __CAP.timer = fn; return true end',
  'FindAllOf = function(n) __CLOCK = __CLOCK + 0.050; return { "a", "b" } end',
].join('\n'), 'stubs');
preloadProfilerOn(U);
let e = U.run('P = require("Profiler"); __INSTALLED = P.InstallGlobalWrappers()', 'install');
if (e) { console.log('INSTALL: ' + e); process.exit(1); }
expect('InstallGlobalWrappers returned true', U.str('__INSTALLED'), (v) => v === 'true');
expect('a second install is refused (no double wrapping)', U.str('P.InstallGlobalWrappers()'), (v) => v === 'false');

U.run([
  '__PRE_ARGS = nil; __POST_RAN = false',
  'local preId, postId = RegisterHook("/Script/Pal.PalAISensorComponent:SelectResponseBySenses",',
  '  function(ctx, x) __PRE_ARGS = tostring(ctx) .. "," .. tostring(x); __CLOCK = __CLOCK + 0.119; return "r1", nil, "r3" end,',
  '  function() __POST_RAN = true end)',
  '__IDS = tostring(preId) .. "," .. tostring(postId)',
].join('\n'), 'reg');
expect('RegisterHook still returns both ids', U.str('__IDS'), (v) => v === '7,8');
U.run('__R = table.pack(__CAP.pre("ctx", 5))', 'callpre');
expect('arguments reach the original pre-callback', U.str('__PRE_ARGS'), (v) => v === 'ctx,5');
expect('all return values pass through, including a nil in the middle',
  U.str('__R.n .. ":" .. tostring(__R[1]) .. "," .. tostring(__R[2]) .. "," .. tostring(__R[3])'), (v) => v === '3:r1,nil,r3');
U.run('__CAP.post()', 'callpost');
expect('the post-callback is wrapped and still runs', U.str('__POST_RAN'), (v) => v === 'true');

// An error must be re-raised, and must not leave the profiler "inside a
// callback" -- if it did, the report further down would never be written,
// because reports only happen at depth 0.
U.run('RegisterHook("/Script/Pal.X:Boom", function() error("boom-original") end)', 'regboom');
U.run('__OK, __ERR = pcall(__CAP.pre)', 'callboom');
expect('an error inside a callback is re-raised', U.str('__OK'), (v) => v === 'false');
expect('with its original message', U.str('__ERR'), (v) => v.includes('boom-original'));

U.run('LoopAsync(1000, function() return true end)', 'loop');
expect('LoopAsync callback still returns true (stops its loop)', U.str('__CAP.loop()'), (v) => v === 'true');

U.run('__KEY_RAN = false; RegisterKeyBind("F9", { "CONTROL" }, function() __KEY_RAN = true end)', 'key');
U.run('__CAP.key()', 'callkey');
expect('RegisterKeyBind: a non-function argument is passed unchanged', U.str('__CAP.keyMods[1]'), (v) => v === 'CONTROL');
expect('RegisterKeyBind: the callback in third position is wrapped and runs', U.str('__KEY_RAN'), (v) => v === 'true');

U.run('__FOUND = FindAllOf("PalCharacter")', 'find');
expect('FindAllOf still returns its result', U.str('#__FOUND'), (v) => v === '2');

U.run('local t0 = P.start(); __CLOCK = __CLOCK + 0.002; P.stop("section test", t0)', 'section');
expect('nothing reported yet (under 10s of clock so far)', U.file().includes('os.clock elapsed'), (v) => v === false);

console.log('\n=== ON: reports are written only at the outermost level ===');
// The timer pushes the clock past the 10s report interval, then makes a world
// search. That search finishes INSIDE the timer, at depth 1, so it must not
// write the report; the timer's own finish at depth 0 must. The probe reads
// the in-memory file from inside the timer, after the inner search returned.
U.run([
  'ExecuteInGameThreadWithDelay(2000, function()',
  '  __CLOCK = __CLOCK + 11.0',
  '  FindAllOf("WBP_PalNPCHPGauge_C")',
  '  __MID_HAS_REPORT = __FILE:find("os.clock elapsed", 1, true) ~= nil',
  'end)',
].join('\n'), 'nested');
e = U.run('__CAP.timer()', 'calltimer');
if (e) console.log('  (timer call error: ' + e + ')');
const report = U.file();

expect('no report while still inside the timer, after its inner search', U.str('__MID_HAS_REPORT'), (v) => v === 'false');
expect('a report was written once the outermost callback finished', report.includes('os.clock elapsed'), (v) => v === true);
expect('the report names the hook by its function', report.includes('hook PalAISensorComponent:SelectResponseBySenses'), (v) => v === true);
expect('the report names world searches by class', report.includes('FindAllOf PalCharacter') && report.includes('FindAllOf WBP_PalNPCHPGauge_C'), (v) => v === true);
expect('the 119ms hook call is listed as a stall', /STALL at [0-9.]+s\s+119\.0 ms\s+hook PalAISensorComponent:SelectResponseBySenses/.test(report), (v) => v === true);
expect('timers are named by source location', /timer \S+:\d+/.test(report), (v) => v === true);
expect('the manual section is reported', report.includes('section test'), (v) => v === true);
expect('the nested timer\'s time includes its inner search (inclusive, >= 11000 ms)',
  (() => { const m = report.match(/timer \S+:\d+\s+calls\s+1 \| total\s+([0-9.]+) ms/); return m ? Number(m[1]) : -1; })(),
  (v) => v >= 11000);
expect('exactly one report block (not one per nesting level)', (report.match(/os\.clock elapsed/g) || []).length, (v) => v === 1);

if (failures > 0) {
  console.log('\n--- report text produced by the unit state, for diagnosing the failures above ---');
  console.log(report || '(empty)');
}
console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
