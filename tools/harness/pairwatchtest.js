// 2026-09-19: the stuck waiting pose (Goldaer's Reindrix).
//
// The watchdog is driven step by step with our own clock, through the same
// objects the game gives it: the player's current action (a BP_ActionPair*
// while posing) and the Pal's AI action (BP_AIActionPairCall_* while it comes
// over and eats). Sequences copied from Dragón's 2026-09-19 [PAIR-WATCH] log.
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
  lua.lua_pop(L, 1);
  return s === null ? 'nil' : to_jsstring(s);
}
function expect(label, actual, wanted) {
  const ok = actual === wanted;
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

const preludePath = process.argv[3] || (__dirname + '/prelude_emote.lua');
let e = run(fs.readFileSync(preludePath, 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');

run([
  'local function ok(t) t.IsValid = function() return __VALID[t] ~= false end return t end',
  '__VALID = {}',
  'function __action(name) return ok({ GetFullName = function() return name end }) end',
  '__CANCELLED = {}',
  '__PLAYER_CUR = nil',
  '__PAC = ok({ GetCurrentAction = function() return __PLAYER_CUR end,',
  '             CancelAction = function(self, a) __CANCELLED[#__CANCELLED + 1] = a:GetFullName(); __PLAYER_CUR = nil end })',
  '__MONTAGE = nil; __STOPPED = {}',
  '__ANIM = ok({ GetCurrentActiveMontage = function() return __MONTAGE end,',
  '              Montage_Stop = function(self, t, m) __STOPPED[#__STOPPED + 1] = m:GetFullName(); __MONTAGE = nil end })',
  '__PL = ok({ ActionComponent = __PAC, Mesh = ok({ GetAnimInstance = function() return __ANIM end }) })',
  'POSE = __action("AnimMontage /Game/Pal/Blueprint/Action/X.AM_Player_Petting_Loop")',
  '__PAL_AI = nil',
  '__AIC = ok({ GetCurrentAction_BP = function() return __PAL_AI end })',
  '__CTRL = ok({ GetAIActionComponent = function() return __AIC end })',
  '__PAL = ok({ Controller = __CTRL, GetFullName = function() return "BP_Reindrix_C /Game/X.BP_Reindrix_C_1" end })',
  'STANDBY  = __action("BP_ActionPairStandby_FeedItem_C /Game/X.BP_ActionPairStandby_FeedItem_C_1")',
  'BEHAVIOR = __action("BP_ActionPairBehavior_FeedItem_C /Game/X.BP_ActionPairBehavior_FeedItem_C_1")',
  'ROLL     = __action("BP_ActionStep_New_Rolling_C /Game/X.BP_ActionStep_New_Rolling_C_1")',
  'CALL     = __action("BP_AIActionPairCall_FeedItem_C /Game/X.BP_AIActionPairCall_FeedItem_C_1")',
  'COMBAT   = __action("BP_AIAction_CombatPal_C /Game/X.BP_AIAction_CombatPal_C_1")',
  'WILD     = __action("BP_AIAction_WildLife_C /Game/X.BP_AIAction_WildLife_C_1")',
  // at(t, playerAction, palAI) sets the scene, steps once, returns the result
  'function __new() __ST = { startedAt = 0, label = "Feed" }; __CANCELLED = {}; __STOPPED = {}; __MONTAGE = nil; __VALID[__PAL] = true end',
  'function at(t, p, ai) __PLAYER_CUR = p; __PAL_AI = ai; return I.PairWatchStep(__ST, __PL, __PAL, t) end',
].join('\n'), 'stubs');

e = run('I = require("Interaction")', 'load');
if (e) { console.log('LOAD: ' + e); process.exit(1); }

console.log('\n=== A. A normal feed is never touched (14:57:23 in the log) ===');
run('__new()', 'a');
expect('picker open, nothing yet', str('at(0.0, nil, nil)'), 'wait');
expect('waiting pose, Pal walking over', str('at(1.5, STANDBY, CALL)'), 'wait');
expect('eating together', str('at(1.9, BEHAVIOR, CALL)'), 'wait');
expect('still eating (Happy)', str('at(5.4, BEHAVIOR, CALL)'), 'wait');
expect('both finish -> done', str('at(7.3, nil, WILD)'), 'done');
expect('nothing was cancelled', str('#__CANCELLED'), '0');

console.log('\n=== B. The Pal stops coming (attacks instead) -> the pose is released ===');
run('__new()', 'b');
expect('waiting pose, Pal coming', str('at(1.0, STANDBY, CALL)'), 'wait');
expect('the Pal switches to fighting', str('at(3.0, STANDBY, COMBAT)'), 'wait');
expect('1 s later, still inside the grace', str('at(4.0, STANDBY, COMBAT)'), 'wait');
expect('1.5 s later -> released', str('at(4.5, STANDBY, COMBAT)'), 'released');
expect('exactly the waiting pose was cancelled', str('__CANCELLED[1]'), 'BP_ActionPairStandby_FeedItem_C /Game/X.BP_ActionPairStandby_FeedItem_C_1');

console.log('\n=== C. A short blip out of the pair call is forgiven ===');
run('__new()', 'c');
expect('waiting', str('at(1.0, STANDBY, CALL)'), 'wait');
expect('Pal briefly elsewhere', str('at(2.0, STANDBY, COMBAT)'), 'wait');
expect('back in its pair call', str('at(3.0, STANDBY, CALL)'), 'wait');
expect('much later, still coming -> still waiting', str('at(6.0, STANDBY, CALL)'), 'wait');
expect('nothing cancelled', str('#__CANCELLED'), '0');

console.log('\n=== D. The player ends a moment after the Pal (normal tail) ===');
run('__new()', 'd');
str('at(1.0, STANDBY, CALL)'); str('at(2.0, BEHAVIOR, CALL)');
expect('Pal done, player still finishing', str('at(7.0, BEHAVIOR, WILD)'), 'wait');
expect('player finishes 1 s later', str('at(8.0, nil, WILD)'), 'done');
expect('nothing cancelled', str('#__CANCELLED'), '0');

console.log('\n=== E. The Pal is gone (joined, despawned) ===');
run('__new()', 'e');
str('at(1.0, STANDBY, CALL)');
run('__VALID[__PAL] = false', 'gone');
expect('gone, inside the grace', str('at(1.5, STANDBY, CALL)'), 'wait');
expect('gone, past the grace -> released', str('at(3.0, STANDBY, CALL)'), 'released');

console.log('\n=== F. The Pal keeps "coming" forever -> released after 12 s ===');
run('__new()', 'f');
str('at(1.0, STANDBY, CALL)');
expect('11 s of waiting', str('at(12.9, STANDBY, CALL)'), 'wait');
expect('12 s of waiting -> released', str('at(13.0, STANDBY, CALL)'), 'released');

console.log('\n=== G. Eating pose past 15 s -> released ===');
run('__new()', 'g');
str('at(1.0, BEHAVIOR, CALL)');
expect('14 s', str('at(15.0, BEHAVIOR, CALL)'), 'wait');
expect('15 s -> released', str('at(16.0, BEHAVIOR, CALL)'), 'released');

console.log('\n=== H. Nothing but the pair pose is ever cancelled ===');
run('__new()', 'h');
expect('the player rolls away from an attacking Pal', str('at(1.0, ROLL, COMBAT)'), 'wait');
expect('still rolling, well past the grace', str('at(4.0, ROLL, COMBAT)'), 'wait');
expect('the feed never started -> the watch ends', str('at(6.0, ROLL, COMBAT)'), 'done');
expect('the roll was never cancelled', str('#__CANCELLED'), '0');
expect('no player -> done, no error', str('I.PairWatchStep({ startedAt = 0 }, nil, __PAL, 1)'), 'done');

console.log('\n=== I. Run 5, the Nitewing: the game ends the pose but its animation keeps playing ===');
run('__new(); __ST.label = "Pet"', 'i');
expect('waiting, the Pal accepted the pet mid-attack', str('at(0.2, STANDBY, CALL)'), 'wait');
run('__MONTAGE = POSE', 'pose');
expect('the game ends the action before the Pal ever came -> failed', str('at(2.7, nil, COMBAT)'), 'failed');
expect('the leftover animation is stopped', str('__STOPPED[1]'), 'AnimMontage /Game/Pal/Blueprint/Action/X.AM_Player_Petting_Loop');
expect('...and no action needed cancelling', str('#__CANCELLED'), '0');

console.log('\n=== J. A pair that finished normally leaves the player\'s animations alone ===');
run('__new()', 'j');
str('at(1.0, STANDBY, CALL)'); str('at(2.0, BEHAVIOR, CALL)');
run('__MONTAGE = POSE', 'pose');
expect('ended after the shared animation -> done', str('at(7.0, nil, WILD)'), 'done');
expect('nothing stopped', str('#__STOPPED'), '0');

console.log('\n=== K. When the watchdog releases a pose, a leftover animation goes too ===');
run('__new()', 'k');
str('at(1.0, STANDBY, CALL)'); str('at(3.0, STANDBY, COMBAT)');
run('__MONTAGE = POSE', 'pose');
expect('released', str('at(4.5, STANDBY, COMBAT)'), 'released');
expect('and its animation stopped', str('#__STOPPED'), '1');
expect('no animation playing -> nothing to stop, no error', str('I.StopLeftoverPose(__PL, "x")'), 'false');

console.log('\n=== L. Only the waiting pose is ever stopped (run 6: it stopped a "got hit" animation) ===');
run('__new(); __MONTAGE = __action("AnimMontage /Game/Pal/Animation/Character/Player/Female/AM_Player_Female_hit.AM_Player_Female_hit")', 'hit');
expect('a hit animation is left alone', str('I.StopLeftoverPose(__PL, "x")'), 'false');
expect('nothing stopped', str('#__STOPPED'), '0');

console.log('\n=== M. Run 6: the pose survives the stop -> the player gets a fresh action, like a roll ===');
run([
  '__Q = {}',
  'ExecuteInGameThreadWithDelay = function(ms, fn) __Q[#__Q + 1] = fn return true end',
  'function __PUMPQ() local q = __Q; __Q = {}; for _, fn in ipairs(q) do fn() end end',
  'BECKON = __action("AnimMontage /Game/Pal/Animation/Character/Player/Female/AM_Player_Female_Petting_Middle_Beckon.AM_Player_Female_Petting_Middle_Beckon")',
].join('\n'), 'queue');
run('__new(); __LAST_EMOTE_TARGET = nil; __PLAYER_CUR = nil; __MONTAGE = BECKON', 'm1');
expect('the waiting pose is stopped', str('I.StopLeftoverPose(__PL, "Pet")'), 'true');
run('__MONTAGE = BECKON; __PUMPQ()', 'still');
expect('0.4 s later it is still playing -> a fresh action (the cheer) is started', str('__LAST_EMOTE_TARGET == __PAWN'), 'true');

run('__new(); __LAST_EMOTE_TARGET = nil; __PLAYER_CUR = nil; __MONTAGE = BECKON; __Q = {}', 'm2');
str('I.StopLeftoverPose(__PL, "Pet")');
run('__PUMPQ()', 'gone');
expect('the stop worked -> no fresh action needed', str('__LAST_EMOTE_TARGET'), 'nil');

run('__new(); __LAST_EMOTE_TARGET = nil; __MONTAGE = BECKON; __Q = {}', 'm3');
str('I.StopLeftoverPose(__PL, "Pet")');
run('__MONTAGE = BECKON; __PLAYER_CUR = ROLL; __PUMPQ()', 'busy');
expect('the pose is back but the player is rolling -> left alone', str('__LAST_EMOTE_TARGET'), 'nil');

console.log('\n=== N. Run 7: a hit animation on top is waited out, then the pose underneath is stopped ===');
run('__new(); __LAST_EMOTE_TARGET = nil; __PLAYER_CUR = nil; __Q = {}; HIT = __action("AnimMontage /Game/Pal/Animation/Character/Player/Female/AM_Player_Female_hit.AM_Player_Female_hit")', 'n');
run('__MONTAGE = HIT', 'hit');
expect('the hit is on top: nothing stopped yet', str('I.StopLeftoverPose(__PL, "Feed")'), 'false');
expect('...and the hit is not touched', str('#__STOPPED'), '0');
run('__PUMPQ()', 'still-hit');
expect('0.4 s later still the hit: still waiting', str('#__STOPPED'), '0');
run('__MONTAGE = BECKON; __PUMPQ()', 'pose-back');
expect('the hit ended, the waiting pose is back on top -> stopped', str('__STOPPED[1]'), 'AnimMontage /Game/Pal/Animation/Character/Player/Female/AM_Player_Female_Petting_Middle_Beckon.AM_Player_Female_Petting_Middle_Beckon');
run('__new(); __Q = {}; __MONTAGE = HIT; I.StopLeftoverPose(__PL, "Feed"); for i = 1, 8 do __PUMPQ() end', 'endless-hit');
expect('something else keeps playing: gives up after a few checks, never stops it', str('#__STOPPED .. "," .. #__Q'), '0,0');

console.log('\n=== O. A joining boss is reported to the game as hit by the player (run 8) ===');
// Dragón, run 8: one bullet before bonding made the game record the defeat and
// pay the first-kill reward; no bullet, no record. This is the same thing a
// capture sphere reports when it lands, with no damage.
e = run('package.preload["Capture"] = nil; package.loaded["Capture"] = nil; C = require("Capture")', 'capture');
if (e) { console.log('LOAD Capture: ' + e); process.exit(1); }
run([
  'function __withDrc(name)',
  '  local calls = {}',
  '  local drc = { IsValid = function() return true end,',
  '                ForceDamageDelegateForCaptureBall = function(self, who) calls[#calls + 1] = who end }',
  '  return { IsValid = function() return true end, GetFullName = function() return name end, DamageReactionComponent = drc }, calls',
  'end',
  '__ME = { IsValid = function() return true end, GetFullName = function() return "BP_Player_Female_C /x.P" end }',
  'B1, B1CALLS = __withDrc("BP_BerryGoat_Dark_BOSS_C /Game/Pal/Maps/X.BP_BerryGoat_Dark_BOSS_C_1")',
  'N1, N1CALLS = __withDrc("BP_SheepBall_C /Game/Pal/Maps/X.BP_SheepBall_C_2")',
  'R1 = { IsValid = function() return true end, GetFullName = function() return "BP_X_RAID_C /x.R" end }',
  '__OK_BOSS = C.RegisterPlayerHitOnBoss(B1, __ME)',
  '__OK_NORMAL = C.RegisterPlayerHitOnBoss(N1, __ME)',
  '__OK_NODRC = C.RegisterPlayerHitOnBoss(R1, __ME)',
].join('\n'), 'boss');
expect('boss: reported once', str('#B1CALLS'), '1');
expect('...naming the player as the attacker', str('B1CALLS[1] == __ME'), 'true');
expect('...and it reports success', str('__OK_BOSS'), 'true');
expect('a normal Pal is left alone', str('#N1CALLS .. "," .. tostring(__OK_NORMAL)'), '0,false');
expect('a boss with no damage component: no error, reports failure', str('__OK_NODRC'), 'false');

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
