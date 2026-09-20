// 2026-09-18: PalBonds' own trust points (Dragón's rework).
//
// The bond bar no longer reads or writes the game's friendship
// (FriendshipPoint on the Pal's IndividualParameter). The only write left is
// the flat +50,000 join bonus in Capture.OnTrustMaxed.
//
//   P1. Trust.AddPoints: adds, never goes below 0, refuses an owned Pal.
//   P2. Trust.GetBarRatio: points / bar, capped at 1; a Pal with no record is 0.
//   P3. 50% of the bar starts the follow (500 bar at equal level).
//   P4. Passive gain: +2 per tick while following, none with F10 off.
//   P5. 100% joins after the delay, with no raise-to-rank-3 before it.
//   P6. A player hit on a bonded Pal costs half the bar; the second is betrayal.
//   P7. Anything else hitting a follower costs nothing (the -150 is gone).
//   P8. Drifting past the leash for 3 s empties the bar and ends the bond.
//   P9. A world change forgets every point AND every brief follow (the reset
//       used to write a stray global instead of clearing the table).
//   S.  Source scan: the game's friendship is written in Capture.lua only.
// Throughout, a spy on the Pal's IndividualParameter proves the game's
// friendship is never read or written by any of the above.
//
// Usage: node pointstest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node pointstest.js <SCRIPTS>'); process.exit(2); }
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
    if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
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
  must('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');
  must([
    // The spy: any read or write of the game's friendship is counted.
    '__GAME_TOUCH = 0',
    'function __spyParam()',
    '  local p = __obj("IndividualParameter")',
    '  p.GetFriendshipPoint = function() __GAME_TOUCH = __GAME_TOUCH + 1 return 0 end',
    '  p.GetFriendshipRank = function() __GAME_TOUCH = __GAME_TOUCH + 1 return 0 end',
    '  p.AddFriendShip = function() __GAME_TOUCH = __GAME_TOUCH + 1 end',
    '  return p',
    'end',
    'for _, pal in ipairs({ __PAL, __PAL2 }) do',
    '  local param = __spyParam()',
    '  pal.CharacterParameterComponent = __obj("ParamComp")',
    '  pal.CharacterParameterComponent.GetIndividualParameter = function() return param end',
    '  pal.CharacterParameterComponent.IsDead = function() return false end',
    '  pal.CharacterParameterComponent.IsDying = function() return false end',
    'end',
    'T = require("Trust"); C = require("Combat"); C.Init(); T.Init()',
    'Cap = require("Capture")',
    '__OWNED = false; __MAXED = 0; __LOST = nil',
    'Cap.IsAlreadyOwned = function() return __OWNED end',
    'Cap.HasPermanentlyFled = function() return false end',
    'Cap.NotifyTrustShaken = function() end',
    'Cap.OnTrustMaxed = function() __MAXED = __MAXED + 1 end',
    'Cap.OnTrustLost = function(_, kind) __LOST = kind end',
    '__FOLLOW_TOASTS = {}; Cap.NotifyStartedFollowing = function(n, f) __FOLLOW_TOASTS[#__FOLLOW_TOASTS + 1] = tostring(n) .. ":" .. tostring(f) end',
    'Cap.ResolveDisplayName = function() return "Lamball" end; Cap.IsFemale = function() return true end',
    'function __PTS(p) return T.GetPoints(p or __PAL) end',
    'function __has(x) for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then return true end end return false end',
  ].join('\n'), 'setup');
  return { run, str, must };
}

console.log('\n=== P1. AddPoints ===');
{
  const S = newState();
  expect('no record: 0 points', S.str('__PTS()'), (v) => v === '0');
  expect('+50 from 0', S.str('select(1, T.AddPoints(__PAL, 50, "Pet")) .. "->" .. select(2, T.AddPoints(__PAL, 0, "x"))'), (v) => v === '0->50');
  S.must('T.AddPoints(__PAL, 70, "Feed")', 'feed');
  expect('adds up', S.str('__PTS()'), (v) => v === '120');
  S.must('T.AddPoints(__PAL, -999, "x")', 'neg');
  expect('never below 0', S.str('__PTS()'), (v) => v === '0');
  S.must('__OWNED = true', 'own');
  expect('an owned Pal gets nothing', S.str('tostring(T.AddPoints(__PAL2, 50, "Pet")) .. "," .. __PTS(__PAL2) .. "," .. tostring(T.HasBondingState(__PAL2))'), (v) => v === 'nil,0,false');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}


console.log('\n=== P2. The bar ===');
{
  const S = newState();
  expect('no record: empty bar', S.str('T.GetBarRatio(__PAL2)'), (v) => v === '0');
  S.must('T.AddPoints(__PAL, 250, "x")', 'half');
  expect('250 of a 500 bar = 0.5', S.str('T.GetBarRatio(__PAL)'), (v) => v === '0.5');
  S.must('T.AddPoints(__PAL, 400, "x")', 'over');
  expect('capped at 1', S.str('T.GetBarRatio(__PAL)'), (v) => v === '1');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}

console.log('\n=== P3. 50% starts the follow ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 200, "x"); T.OnInteractionSucceeded(__PAL)', '40');
  expect('40%: not following', S.str('C.IsFollowing(__PAL)'), (v) => v === 'false');
  S.must('T.AddPoints(__PAL, 50, "x"); T.OnInteractionSucceeded(__PAL)', '50');
  expect('50%: following', S.str('C.IsFollowing(__PAL)'), (v) => v === 'true');
  expect('logged with our own numbers', S.str('__has("trust 250 / 500")'), (v) => v === 'true');
  expect('the player is told, once, with the name and gender', S.str('table.concat(__FOLLOW_TOASTS, ",")'), (v) => v === 'Lamball:true');
  S.must('T.AddPoints(__PAL, 50, "x"); T.OnInteractionSucceeded(__PAL)', 'more');
  expect('...and not again on the next interaction', S.str('#__FOLLOW_TOASTS'), (v) => v === '1');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}

console.log('\n=== P4. Passive gain ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 250, "x"); T.OnInteractionSucceeded(__PAL)', 'bond');
  S.must('__PUMP(1)', 'tick');
  expect('+2 per tick while following', S.str('__PTS()'), (v) => v === '252');
  S.must('__PUMP(4)', 'ticks');
  expect('+2 each tick', S.str('__PTS()'), (v) => v === '260');
  S.must('T.TogglePassiveFriendshipGain(); __PUMP(5)', 'f10');
  expect('F10 off: no gain', S.str('__PTS()'), (v) => v === '260');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}

console.log('\n=== P5. 100% joins, with no second bonus ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 500, "Peach"); T.OnInteractionSucceeded(__PAL)', 'full');
  expect('waits for the animation first', S.str('__MAXED'), (v) => v === '0');
  S.must('__PUMP(1)', 'delay');
  expect('then hands over to Capture.OnTrustMaxed once', S.str('__MAXED'), (v) => v === '1');
  expect('no rank-3 raise before it', S.str('__has("capture bonus applied")'), (v) => v === 'false');
  expect('no "starts following" message when the same interaction reaches 100% (only the join shows)', S.str('#__FOLLOW_TOASTS'), (v) => v === '0');
  expect('...but the name is still kept, as for any follower', S.str('tostring(__has("interaction #1"))'), (v) => v === 'true');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');

  // Run 8: for a boss, Capture reports "the player hit it" to the game during
  // the capture (that is what makes the defeat count), and it comes back
  // through our own damage hook. It must not cost the Pal anything.
  S.must('__BEFORE = T.GetPoints(__PAL); T.OnFollowerDamaged(__PAL, true)', 'own-hit');
  expect('the capture\'s own reported hit costs nothing', S.str('T.GetPoints(__PAL) == __BEFORE'), (v) => v === 'true');
  expect('...and says nothing about shaken trust', S.str('tostring(__has("trust shaken") or __has("[BETRAYAL]"))'), (v) => v === 'false');
}

console.log('\n=== P6. The player hitting a bonded Pal ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 400, "x"); T.OnInteractionSucceeded(__PAL)', 'bond');
  S.must('T.OnFollowerDamaged(__PAL, true)', 'hit1');
  expect('first hit: half of the 500 bar gone, still bonded', S.str('__PTS() .. "," .. tostring(C.IsFollowing(__PAL))'), (v) => v === '150,true');
  S.must('__CLOCK = __CLOCK + 2; T.OnFollowerDamaged(__PAL, true)', 'hit2');
  expect('second hit: betrayal, bar empty', S.str('__PTS() .. "," .. tostring(__LOST)'), (v) => v === '0,betrayed');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}

console.log('\n=== P7. Something else hitting a follower costs nothing ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 300, "x"); T.OnInteractionSucceeded(__PAL)', 'bond');
  S.must('__FIRE("/Script/Pal.PalHate:DamageEvent", nil, __arg({ Attacker = __ENEMY, Defender = __PAL, Damage = 40 }))', 'hate');
  S.must('__FIRE("/Script/Pal.PalDamageReactionComponent:OnProcessedActualDamageDelegate__DelegateSignature", nil, __arg(__ENEMY), __arg(__PAL), __arg(40))', 'delegate');
  S.must('T.OnFollowerDamaged(__PAL, false)', 'direct');
  expect('points unchanged, still bonded', S.str('__PTS() .. "," .. tostring(C.IsFollowing(__PAL)) .. "," .. tostring(__LOST)'), (v) => v === '300,true,nil');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}

console.log('\n=== P8. Left behind ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 300, "x"); T.OnInteractionSucceeded(__PAL)', 'bond');
  // Not fighting (the prelude's default action is a combat one, which pauses the leash).
  S.must('__HATE_TARGET = nil; __CURRENT_ACTION.__name = "BP_AIAction_WildLife_C_9"', 'idle');
  S.must('__PAL_LOC = __vec(5000, 0, 0); __PUMP(1)', 'far');
  expect('the grace clock starts, points kept', S.str('tostring(__PTS() >= 300) .. "," .. tostring(__LOST)'), (v) => v === 'true,nil');
  S.must('__CLOCK = __CLOCK + 4; __PUMP(1)', 'gone');
  expect('3 s later: bar empty, abandoned', S.str('__PTS() .. "," .. tostring(__LOST)'), (v) => v === '0,abandoned');
  expect('the game\'s friendship was never touched', S.str('__GAME_TOUCH'), (v) => v === '0');
}

console.log('\n=== P9. A world change forgets everything ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 300, "x"); T.StartBriefFollow(__PAL2, function() return true end)', 'setup');
  expect('(setup) points and a brief follow exist', S.str('__PTS() .. "," .. tostring(T.IsBriefFollowing(__PAL2))'), (v) => v === '300,true');
  S.must('T.ResetForNewWorld()', 'reset');
  expect('points gone', S.str('__PTS() .. "," .. tostring(T.HasBondingState(__PAL))'), (v) => v === '0,false');
  expect('the brief follow is forgotten too', S.str('T.IsBriefFollowing(__PAL2)'), (v) => v === 'false');
  expect('no stray global left behind', S.str('rawget(_G, "briefFollow")'), (v) => v === 'nil');
}

console.log('\n=== P10. A Pal that despawns is forgotten; a follower gets the abandoned toast ===');
{
  const S = newState();
  S.must('__TOASTS = {}; Cap.NotifyBondLostByName = function(n, r) __TOASTS[#__TOASTS + 1] = tostring(n) .. ":" .. tostring(r) end', 'toast-spy');
  S.must('Cap.ResolveDisplayName = function() __GAME_NAME_READS = (__GAME_NAME_READS or 0) + 1 return "Lamball" end', 'name');
  S.must('T.AddPoints(__PAL2, 120, "x"); T.AddPoints(__PAL, 300, "x"); T.OnInteractionSucceeded(__PAL)', 'setup');
  expect('(setup) the follower\'s name is read once, when it starts following', S.str('__GAME_NAME_READS'), (v) => v === '1');
  S.must('__PUMP(1)', 'tick-alive');
  expect('still in the world: kept', S.str('__PTS(__PAL2)'), (v) => v === '120');
  S.must('__PAL2.IsValid = function() return false end; __PUMP(1)', 'despawn-2');
  expect('a despawned non-follower: record dropped, no toast', S.str('tostring(T.HasBondingState(__PAL2)) .. "," .. #__TOASTS'), (v) => v === 'false,0');
  expect('logged', S.str('__has("[DESPAWN]")'), (v) => v === 'true');
  S.must('__PAL.IsValid = function() return false end; __PUMP(1)', 'despawn-1');
  expect('a despawned follower: record dropped', S.str('tostring(T.HasBondingState(__PAL))'), (v) => v === 'false');
  expect('...the abandoned toast, with the cached name', S.str('table.concat(__TOASTS, "|")'), (v) => v === 'Lamball:abandoned');
  expect('...and Combat no longer counts it as a follower', S.str('tostring(C.HasAnyFollower())'), (v) => v === 'false');
  S.must('__PUMP(3)', 'later');
  expect('the toast is shown once', S.str('#__TOASTS'), (v) => v === '1');
}
{
  const S = newState();
  S.must('__TOASTS = {}; Cap.NotifyBondLostByName = function(n, r) __TOASTS[#__TOASTS + 1] = tostring(n) end', 'toast-spy');
  S.must('T.StartBriefFollow(__PAL, function() return true end); __PAL.IsValid = function() return false end; __PUMP(1)', 'brief-despawn');
  expect('a Pal on its 20% calm-down is not bonded: forgotten quietly', S.str('tostring(T.HasBondingState(__PAL)) .. "," .. #__TOASTS .. "," .. tostring(T.IsBriefFollowing(__PAL))'), (v) => v === 'false,0,false');
}

console.log('\n=== P12. Crossing 50% during the 20% calm-down: told, and the name is kept ===');
{
  const S = newState();
  S.must('T.AddPoints(__PAL, 100, "x"); T.StartBriefFollow(__PAL, function() return false end)', 'brief');
  expect('no following message for the calm-down itself', S.str('#__FOLLOW_TOASTS'), (v) => v === '0');
  S.must('T.AddPoints(__PAL, 200, "x"); for i = 1, 8 do __CLOCK = __CLOCK + 0.5; __PUMP(1) end', 'past50');
  expect('it keeps following, and the player is told', S.str('tostring(C.IsFollowing(__PAL)) .. "," .. table.concat(__FOLLOW_TOASTS, ",")'), (v) => v === 'true,Lamball:true');
  S.must('__TOASTS2 = {}; Cap.NotifyBondLostByName = function(n, r, f) __TOASTS2[#__TOASTS2 + 1] = tostring(n) .. ":" .. r .. ":" .. tostring(f) end', 'spy');
  S.must('__PAL.IsValid = function() return false end; __PUMP(1)', 'despawn');
  expect('a later despawn names it (this path used to lose the name)', S.str('table.concat(__TOASTS2, ",")'), (v) => v === 'Lamball:abandoned:true');
}

console.log('\n=== P11. Hitting a Pal that already fled for good changes nothing ===');
{
  const S = newState();
  S.must('P = require("Personality"); __REVERTED = 0; P.RevertForgiveness = function() __REVERTED = __REVERTED + 1 return true end', 'spy');
  S.must('T.AddPoints(__PAL, 100, "x"); T.OnInteractionSucceeded(__PAL); Cap.HasPermanentlyFled = function() return true end', 'fled');
  S.must('T.OnFollowerDamaged(__PAL, true)', 'hit');
  expect('no below-50% rule: no revert, points untouched', S.str('__REVERTED .. "," .. __PTS()'), (v) => v === '0,100');
  expect('not logged as an unbonded hit', S.str('__has("[UNBONDED-HIT]")'), (v) => v === 'false');
  S.must('Cap.HasPermanentlyFled = function() return false end; T.OnFollowerDamaged(__PAL, true)', 'control');
  expect('control: the same hit on a Pal that has not fled does apply the rule', S.str('__REVERTED .. "," .. __PTS()'), (v) => v === '1,0');
}

console.log('\n=== S. Source: only Capture.lua touches the game\'s friendship ===');
{
  const hits = [];
  for (const f of fs.readdirSync(scriptsDir)) {
    if (!f.endsWith('.lua')) continue;
    fs.readFileSync(path.join(scriptsDir, f), 'utf8').split(/\r?\n/).forEach((line, i) => {
      const code = line.replace(/--.*$/, '');
      if (/:(AddFriendShip|GetFriendshipPoint|GetFriendshipRank)\s*\(/.test(code)) hits.push(f + ':' + (i + 1));
    });
  }
  expect('every call is in Capture.lua', hits.join(' '), (v) => v !== '' && v.split(' ').every((h) => h.startsWith('Capture.lua:')));
  expect('exactly one write: the join bonus', String(hits.filter((h) => {
    const [f, n] = h.split(':');
    return /AddFriendShip/.test(fs.readFileSync(path.join(scriptsDir, f), 'utf8').split(/\r?\n/)[Number(n) - 1]);
  }).length), (v) => v === '1');
  const cap = fs.readFileSync(path.join(scriptsDir, 'Capture.lua'), 'utf8');
  // The amount comes from the player's settings (JoinBonus, default 50000; settingstest covers the file).
  expect('the join bonus is the JoinBonus setting', String(/local JOIN_FRIENDSHIP_POINT_GRANT = require\("Settings"\)\.Get\("JoinBonus"\)/.test(cap)), (v) => v === 'true');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
