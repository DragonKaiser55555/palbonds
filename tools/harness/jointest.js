// 2026-09-19: Esaeon's crash (GitHub issue #1) -- the game crashes 5-15 s after
// a Pal joins, PalBonds the only mod, an access violation inside UE4SS. A join
// destroys the wild actor; every module must let go of it at that moment, the
// way a world change already makes them, instead of holding it (up to 10 min
// in Personality) and calling into it after the game has freed it.
//
//   J1. Personality forgets the joined Pal's state and caches.
//   J2. Interaction's pose watchdog stops touching the Pal once it has joined.
//   J3. Indicator's forget runs clean (and matches by id/address, not by
//       calling into the stored actor).
//   J4. Capture wires all three into the join, with the id and address read
//       BEFORE the capture, while the wild actor is alive.
//   J5. The preset writes check the sensor first (Esaeon's suggestion).
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
let failures = 0;
function expect(label, actual, ok) {
  const pass = typeof ok === 'function' ? ok(actual) : actual === ok;
  if (!pass) failures++;
  console.log('  ' + (pass ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}
function newState(prelude) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
    if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
    const r = lua.lua_pcall(L, 0, 0, 0);
    if (r !== lua.LUA_OK) { const e = lua.lua_tostring(L, -1); return to_jsstring(e === null ? to_luastring('?') : e); }
    return null;
  };
  const must = (code, name) => { const e = run(code, name); if (e) { console.log('SETUP ' + name + ': ' + e); process.exit(1); } };
  const str = (expr) => {
    const e = run('__OUT = tostring(' + expr + ')', 'ev');
    if (e) return 'ERR: ' + e;
    lua.lua_getglobal(L, to_luastring('__OUT'));
    const s = lua.lua_tostring(L, -1);
    lua.lua_pop(L, 1);
    return s === null ? 'nil' : to_jsstring(s);
  };
  must(fs.readFileSync(path.join(__dirname, prelude), 'utf8'), 'prelude');
  must('package.path = "' + dir + '/?.lua;" .. package.path', 'path');
  return { must, str };
}

console.log('\n=== J1. Personality forgets a Pal that joined ===');
{
  const S = newState('prelude_person.lua');
  // The real GetStableId can't run here: fengari has no 64-bit integers (its
  // `% 0x100000000` mask divides by zero). A fixed id stands in for it.
  S.must('package.preload["Personality"] = nil; package.loaded["Personality"] = nil; P = require("Personality"); P.GetStableId = function() return "PALID-J1" end; __ID = P.GetOrInitState(__PAL); __KEY = __PAL:GetFullName()', 'state');
  expect('the wild Pal has a personality record', S.str('__ID ~= nil and P.HeldReferencesFor(__ID, __KEY) > 0'), 'true');
  expect('forgetting it drops something', S.str('P.ForgetJoinedPal(__ID, __KEY) > 0'), 'true');
  expect('...and nothing is left', S.str('P.HeldReferencesFor(__ID, __KEY)'), '0');
  expect('forgetting twice is harmless', S.str('P.ForgetJoinedPal(__ID, __KEY)'), '0');
  expect('no id at all is harmless', S.str('P.ForgetJoinedPal(nil, nil)'), '0');
}

console.log('\n=== J2. The pose watchdog stops calling into the Pal once it joined ===');
{
  const S = newState('prelude_emote.lua');
  S.must([
    '__Q = {}',
    'ExecuteInGameThreadWithDelay = function(ms, fn) __Q[#__Q + 1] = fn return true end',
    'function __PUMPQ() local q = __Q; __Q = {}; for _, fn in ipairs(q) do fn() end end',
    '__TOUCHES = 0',
    'local STANDBY = { IsValid = function() return true end, GetFullName = function() return "BP_ActionPairStandby_FeedItem_C /x.S" end }',
    'local CALL = { IsValid = function() return true end, GetFullName = function() return "BP_AIActionPairCall_FeedItem_C /x.C" end }',
    '__PLAYER_AC.GetCurrentAction = function() return STANDBY end',
    'package.loaded["PlayerRef"] = { Get = function() return __PAWN end }',
    'local aic = { IsValid = function() return true end, GetCurrentAction_BP = function() return CALL end }',
    'local ctrl = { IsValid = function() return true end, GetAIActionComponent = function() return aic end }',
    '__JOINER = { GetAddress = function() return 0xBEEF end, Controller = ctrl,',
    '             IsValid = function() __TOUCHES = __TOUCHES + 1 return true end }',
    'I = require("Interaction")',
    'I.WatchPlayerPair(__JOINER, "Feed")',
  ].join('\n'), 'setup');
  S.must('__PUMPQ(); __PUMPQ()', 'watching');
  expect('while it is wild, the watchdog checks on it', S.str('__TOUCHES > 0'), 'true');
  S.must('__BEFORE = __TOUCHES', 'mark');
  expect('the join drops the watched Pal', S.str('I.ForgetJoinedPal(0xBEEF) > 0'), 'true');
  S.must('for i = 1, 10 do __PUMPQ() end', 'after');
  expect('after the join nothing calls into it again', S.str('__TOUCHES - __BEFORE'), '0');
  expect('a different Pal joining leaves the rest alone', S.str('I.ForgetJoinedPal(0xF00D)'), '0');
}

console.log('\n=== J3. Indicator forgets by id and address ===');
{
  const S = newState('prelude_323.lua');
  S.must('Ind = require("Indicator")', 'load');
  expect('nothing tracked -> nothing dropped, no error', S.str('Ind.ForgetJoinedPal("ID", 0x1234)'), '0');
  expect('and nothing held', S.str('Ind.HeldReferencesFor("ID", 0x1234)'), '0');
  const src = fs.readFileSync(path.join(dir, 'Indicator.lua'), 'utf8');
  expect('every tracked bar remembers its actor\'s address while alive',
    String(/trackedBars\[trackKey\] = \{[^}]*actorAddr = address_of_obj\(earlyActor\)/.test(src)), 'true');
  expect('boss entries too', String(/actorAddr = address_of_obj\(actor\) \}/.test(src)), 'true');
  const fn = src.slice(src.indexOf('function Indicator.ForgetJoinedPal'), src.indexOf('function Indicator.HeldReferencesFor'));
  expect('the forget never calls into a stored actor', String(!/entry\.actor[:.]/.test(fn) && !/IsValid/.test(fn)), 'true');
}

console.log('\n=== J4. The join wires it all, with id and address read before the capture ===');
{
  const cap = fs.readFileSync(path.join(dir, 'Capture.lua'), 'utf8');
  const body = cap.slice(cap.indexOf('function Capture.OnTrustMaxed'));
  const idAt = body.indexOf('local joinedId = ');
  const addrAt = body.indexOf('local joinedAddr = ');
  const captureAt = body.indexOf('Capture.TryDirectCapture(pal, player)');
  expect('the id and address are read before the capture', String(idAt > 0 && addrAt > 0 && idAt < captureAt && addrAt < captureAt), 'true');
  for (const call of ['Personality.ForgetJoinedPal(joinedId, name)', 'require("Indicator").ForgetJoinedPal(joinedId, joinedAddr)', 'require("Interaction").ForgetJoinedPal(joinedAddr)']) {
    const at = body.indexOf(call);
    expect('after the capture: ' + call, String(at > captureAt), 'true');
  }
}

console.log('\n=== J5. The preset writes check the sensor first (Esaeon\'s suggestion) ===');
{
  const src = fs.readFileSync(path.join(dir, 'Personality.lua'), 'utf8');
  const writes = [...src.matchAll(/sensor\.AIResponsePreset = fresh/g)].map((m) => m.index);
  expect('two preset writes', String(writes.length), '2');
  for (const w of writes) {
    const before = src.slice(Math.max(0, w - 400), w);
    expect('a sensor check right before the write at ' + w, String(/if not sensor_alive\(sensor\) then/.test(before)), 'true');
  }
  const apply = src.slice(src.indexOf('local function apply_forced_preset'));
  expect('...and at the top of apply_forced_preset', String(apply.indexOf('sensor_alive(sensor)') < apply.indexOf('find_preset_cdo')), 'true');
}

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
