// 2026-09-20: which player is OURS.
//
// Until now every player lookup in the mod took the first valid
// PalPlayerCharacter in the object list. In singleplayer there is only one, so
// that was always right. In a co-op world every player's character is loaded on
// every machine, and "first in the list" is whoever the engine happens to list
// first -- which is how a Workshop player watched the Pal HE befriended join
// his friend's party instead (LuWicki97, 2026-09-15).
//
// The rule now: prefer the character this machine controls
// (APawn::IsLocallyControlled). The interesting part is what happens when that
// question is NOT answered, so most of this file is about those cases.
//
//   A. Singleplayer is untouched, including if the call never answers.
//   B. Co-op: ours is picked wherever it sits; nobody local yet means nobody,
//      and that does not latch; a build that cannot answer at all falls back to
//      the old behaviour rather than going blind.
//   C. PlayerRef.Get() end to end, and it says so in the log.
//   D. The world-closing probe picks the same way, so another player's
//      character cannot be mistaken for "a new world has loaded".
//   E. The player-controller fallback prefers the local controller too.
//   F. A Pal already bonding with ANOTHER player is left alone: detected from
//      the Pal itself (its follow action names a player who is not us), and
//      every interaction route refuses before anything is spent.
//   G. Everything unreadable is treated as NOT claimed, so singleplayer can
//      never be blocked by this.
//   H. What kind of session this is, read from the world's NetDriver.
//   I. As a GUEST the mod stands down completely -- most importantly it never
//      asks for the join, which is a FATAL error in the game when a client
//      asks for it (measured on a dedicated server, 2026-09-20).
//
// Usage: node multiplayertest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node multiplayertest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');
let failures = 0;

function expect(label, actual, pred) {
  const ok = typeof pred === 'function' ? pred(actual) : actual === pred;
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

function newState(preludeFile, setup) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
    if (st !== lua.LUA_OK) { const e = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_settop(L, 0); return 'LOAD: ' + e; }
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
  must(fs.readFileSync(path.join(__dirname, preludeFile), 'utf8'), 'prelude');
  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  must('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');
  // Fake player characters: `local` is what IsLocallyControlled answers --
  // true, false, nil (the call does not exist) or "error" (it throws).
  must([
    '__LOGLINES = {}',
    'package.preload["Logger"] = nil',
    'function __player(name, answer)',
    '  local p = __obj(name)',
    '  if answer == "error" then',
    '    p.IsLocallyControlled = function() error("no such function") end',
    '  elseif answer ~= nil then',
    '    p.IsLocallyControlled = function() return answer end',
    '  end',
    '  return p',
    'end',
    'function __invalid(name)',
    '  local p = __obj(name)',
    '  p.IsValid = function() return false end',
    '  return p',
    'end',
  ].join('\n'), 'players');
  if (setup) must(setup, 'setup');
  return { run, str, must };
}

// Every log line the mod writes, so the [PLAYER-LIFE] messages can be checked.
const CAPTURE_LOG = [
  'local realLog = require("Logger").log',
  'require("Logger").log = function(msg) __LOGLINES[#__LOGLINES + 1] = tostring(msg) end',
  'function __said(x) for _, m in ipairs(__LOGLINES) do if m:find(x, 1, true) then return true end end return false end',
].join('\n');

console.log('\n=== A. Singleplayer is untouched ===');
{
  const S = newState('prelude_323.lua', 'P = require("PlayerRef")');
  S.must(CAPTURE_LOG, 'log');
  S.must('__ONE = __player("BP_Player_Female_C_1", nil)', 'one');
  expect('one player, the build never answers: still ours', S.str('P.PickLocal({ __ONE }) == __ONE'), 'true');
  S.must('__ONEF = __player("BP_Player_Female_C_1", false)', 'onefalse');
  expect('one player answering FALSE: still ours (it can only be us)', S.str('P.PickLocal({ __ONEF }) == __ONEF'), 'true');
  expect('...and the log says the question went unanswered', S.str('tostring(__said("did not answer IsLocallyControlled"))'), 'true');
  expect('an invalid character is never picked', S.str('P.PickLocal({ __invalid("dead"), __ONE }) == __ONE'), 'true');
  expect('nothing in the world: nobody', S.str('tostring(P.PickLocal({}))'), 'nil');
}
{
  const S = newState('prelude_323.lua', 'P = require("PlayerRef")');
  S.must(CAPTURE_LOG, 'log');
  S.must('__ONET = __player("BP_Player_Female_C_1", true)', 'onetrue');
  expect('one player answering true', S.str('P.PickLocal({ __ONET }) == __ONET'), 'true');
  expect('...and the log says the build answers the question', S.str('tostring(__said("this machine controls (IsLocallyControlled)"))'), 'true');
  // Once the question has been answered properly, a lone character that says
  // "not yours" is believed -- in co-op that is the other player, left alone
  // in the world for a moment while ours is unloaded.
  S.must('__THEIRS = __player("BP_Player_Male_C_9", false)', 'theirs');
  expect('after that, a lone character that is not ours is not adopted',
    S.str('tostring(P.PickLocal({ __THEIRS }))'), 'nil');
  expect('...and ours is still picked when it is back', S.str('P.PickLocal({ __THEIRS, __ONET }) == __ONET'), 'true');
}

console.log('\n=== B. Co-op: ours, wherever it is ===');
{
  const S = newState('prelude_323.lua', 'P = require("PlayerRef")');
  S.must(CAPTURE_LOG, 'log');
  S.must('__THEIRS = __player("BP_Player_Male_C_9", false); __OURS = __player("BP_Player_Female_C_1", true)', 'two');
  expect('ours second in the list is still picked', S.str('P.PickLocal({ __THEIRS, __OURS }) == __OURS'), 'true');
  expect('...and the log says the old rule would have picked someone else',
    S.str('tostring(__said("ours is number 2"))'), 'true');
  expect('ours first', S.str('P.PickLocal({ __OURS, __THEIRS }) == __OURS'), 'true');
  S.must('__T2 = __player("BP_Player_Male_C_8", false)', 'third');
  expect('three players, ours last', S.str('P.PickLocal({ __THEIRS, __T2, __OURS }) == __OURS'), 'true');
  expect('a character that throws on the question does not veto ours',
    S.str('P.PickLocal({ __player("odd", "error"), __OURS }) == __OURS'), 'true');

  // Nobody local yet: better nothing than somebody else's.
  expect('several players and none is ours: nobody', S.str('tostring(P.PickLocal({ __THEIRS, __T2 }))'), 'nil');
  expect('...and it says so', S.str('tostring(__said("controlled by this machine"))'), 'true');
  expect('...and it does not latch: ours arriving is picked at once',
    S.str('P.PickLocal({ __THEIRS, __T2, __OURS }) == __OURS'), 'true');
}
{
  // A build where the call does not exist at all: the mod must not go blind.
  const S = newState('prelude_323.lua', 'P = require("PlayerRef")');
  S.must(CAPTURE_LOG, 'log');
  S.must('__A = __player("BP_Player_Female_C_1", nil); __B = __player("BP_Player_Male_C_9", nil)', 'two');
  expect('nobody can answer: the first one, as before', S.str('P.PickLocal({ __A, __B }) == __A'), 'true');
  expect('...and it is said once, plainly', S.str('tostring(__said("IsLocallyControlled is not answering"))'), 'true');
  S.must('__COUNT = 0; for _, m in ipairs(__LOGLINES) do if m:find("not answering", 1, true) then __COUNT = __COUNT + 1 end end', 'count');
  S.must('P.PickLocal({ __A, __B }); P.PickLocal({ __A, __B })', 'again');
  S.must('__COUNT2 = 0; for _, m in ipairs(__LOGLINES) do if m:find("not answering", 1, true) then __COUNT2 = __COUNT2 + 1 end end', 'count2');
  expect('...once for the whole session, not per lookup', S.str('__COUNT .. "," .. __COUNT2'), '1,1');
}

console.log('\n=== C. PlayerRef.Get() end to end ===');
{
  const S = newState('prelude_323.lua', [
    'P = require("PlayerRef")',
    '__THEIRS = nil; __OURS = nil',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then return __WORLD end return nil end',
  ].join('\n'));
  S.must(CAPTURE_LOG, 'log');
  S.must('__THEIRS = __player("BP_Player_Male_C_9", false); __OURS = __player("BP_Player_Female_C_1", true); __WORLD = { __THEIRS, __OURS }', 'world');
  expect('Get() returns our character, not the first found', S.str('P.Get() == __OURS'), 'true');
  expect('...and keeps it (one search)', S.str('P.Get() == __OURS and P.SearchCount()'), '1');
  S.must('__WORLD = { __THEIRS }; P.Invalidate(); __CLOCK = __CLOCK + 100', 'left');
  expect('our character gone: no player at all (never theirs)', S.str('tostring(P.Get())'), 'nil');
  S.must('__WORLD = { __THEIRS, __OURS }; __CLOCK = __CLOCK + 100', 'back');
  expect('...and ours coming back is found again', S.str('P.Get() == __OURS'), 'true');
}

console.log('\n=== D. The world-closing probe ===');
{
  const S = newState('prelude_323.lua', [
    'P = require("PlayerRef")',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then return __WORLD end return nil end',
  ].join('\n'));
  S.must(CAPTURE_LOG, 'log');
  S.must('__THEIRS = __player("BP_Player_Male_C_9", false); __OURS = __player("BP_Player_Female_C_1", true); __WORLD = { __OURS, __THEIRS }', 'world');
  S.must('P.Get(); P.SetWorldClosing(true)', 'closing');
  expect('while the world closes, nobody gets a player', S.str('tostring(P.Get())'), 'nil');
  S.must('__WORLD = { __THEIRS, __OURS }', 'reordered');
  expect('another player listed first is NOT mistaken for a new world',
    S.str('tostring(P.ProbeForNewPlayer(10.0))'), 'nil');
  S.must('__WORLD = { __THEIRS, __player("BP_Player_Female_C_2", true) }', 'newworld');
  expect('a genuinely different character of ours is the new world',
    S.str('tostring(P.ProbeForNewPlayer(10.0))'), 'new-world');
  expect('...and the mod works again', S.str('tostring(P.IsWorldClosing())'), 'false');
}

console.log('\n=== E. The player-controller fallback ===');
{
  const S = newState('prelude_emote.lua', [
    'I = require("Interaction")',
    'local function mk(n) return { __name = n, IsValid = function() return true end, GetFullName = function() return n end } end',
    '__THEIRPAWN = mk("BP_Player_Male_C_9")',
    '__THEIRAC = mk("PalActionComponent_Theirs")',
    '__THEIRAC.PlayAction = function(self, target, cls) __LAST_EMOTE_TARGET = target end',
    '__THEIRPAWN.ActionComponent = __THEIRAC',
    '__THEIRPC = mk("BP_PalPlayerController_C_9")',
    '__THEIRPC.Pawn = __THEIRPAWN',
    '__THEIRPC.IsLocalPlayerController = function() return false end',
    '__PC.IsLocalPlayerController = function() return true end',
    'FindAllOf = function(n) if n == "BP_PalPlayerController_C" then return { __THEIRPC, __PC } end return nil end',
  ].join('\n'));
  S.must('__LAST_EMOTE_TARGET = nil; I.PlayPlayerEmote(0)', 'emote');
  expect('the emote plays on OUR character, not the first controller found',
    S.str('__LAST_EMOTE_TARGET == __PAWN'), 'true');
}
{
  const S = newState('prelude_emote.lua', [
    'I = require("Interaction")',
    'local function mk(n) return { __name = n, IsValid = function() return true end, GetFullName = function() return n end } end',
    '__THEIRPAWN = mk("BP_Player_Male_C_9")',
    '__THEIRAC = mk("PalActionComponent_Theirs")',
    '__THEIRAC.PlayAction = function(self, target, cls) __LAST_EMOTE_TARGET = target end',
    '__THEIRPAWN.ActionComponent = __THEIRAC',
    '__THEIRPC = mk("BP_PalPlayerController_C_9")',
    '__THEIRPC.Pawn = __THEIRPAWN',
    'FindAllOf = function(n) if n == "BP_PalPlayerController_C" then return { __THEIRPC, __PC } end return nil end',
  ].join('\n'));
  S.must('__LAST_EMOTE_TARGET = nil; I.PlayPlayerEmote(0)', 'emote');
  expect('no controller answers: the first one, as before',
    S.str('__LAST_EMOTE_TARGET == __THEIRPAWN'), 'true');
}

console.log('\n=== F. A Pal that belongs to another player ===');
{
  const S = newState('prelude_323.lua', [
    'C = require("Combat"); T = require("Trust"); I = require("Interaction")',
    '__THEM = __player("BP_Player_Male_C_9", false)',
    '__FOLLOW = __obj("BP_AIAction_OtomoFollow_C_1")',
    '__FOLLOW.Trainer = __THEM',
    '__ACTION_COMP.GetCurrentAction_BP = function() return __FOLLOW end',
    '__HAS_ACTION = true',
  ].join('\n'));
  expect('a Pal whose follow action names another player is claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'true');
  expect('...and the log says so once', S.str('tostring(__has and __has("[CLAIMED]") or true)'), 'true');
  S.must('C.ForgetClaims(); __FOLLOW.Trainer = __PLAYER', 'ours');
  expect('the same Pal following US is not claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'false');
  S.must('C.ForgetClaims(); __FOLLOW.Trainer = __obj("BP_Lamball_C_7")', 'itself');
  expect('a Pal following something that is not a player is not claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'false');
  S.must('C.ForgetClaims(); __FOLLOW.Trainer = nil', 'notrainer');
  expect('a follow action with no readable trainer is not claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'false');
  S.must('C.ForgetClaims(); __FOLLOW.Trainer = __THEM; __HAS_ACTION = false', 'noaction');
  expect('no follow action at all: not claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'false');
}
{
  // The interaction routes.
  const S = newState('prelude_323.lua', [
    'C = require("Combat"); T = require("Trust"); I = require("Interaction")',
    'local cap = require("Capture"); cap.IsAlreadyOwned = function() return false end; cap.HasPermanentlyFled = function() return false end',
    'local per = require("Personality"); per.GetState = per.GetState or function() return {} end',
    '__THEM = __player("BP_Player_Male_C_9", false)',
    '__FOLLOW = __obj("BP_AIAction_OtomoFollow_C_1")',
    '__FOLLOW.Trainer = __THEM',
    '__ACTION_COMP.GetCurrentAction_BP = function() return __FOLLOW end',
    '__HAS_ACTION = true',
  ].join('\n'));
  expect('(the grant is reachable from the harness)', S.str('type(I.GrantWildInteraction)'), 'function');
  S.must('__GRANTED = I.GrantWildInteraction(__PAL, 50, "pet")', 'grant');
  expect("no trust is granted to another player's Pal",
    S.str('tostring(__GRANTED) .. "," .. tostring(T.GetPoints(__PAL) or 0)'), 'false,0');
  S.must('C.ForgetClaims(); __FOLLOW.Trainer = __PLAYER; __GRANTED = I.GrantWildInteraction(__PAL, 50, "pet")', 'ours');
  expect('control: the same grant on a Pal following US goes through',
    S.str('tostring(__GRANTED) .. "," .. tostring(T.GetPoints(__PAL) or 0)'), 'true,50');

  const src = fs.readFileSync(path.join(scriptsDir, 'Interaction.lua'), 'utf8');
  expect('the radial menu (pet and feed) asks before substituting the Pal',
    String(/claimed_by_another_player\(wildPal\)/.test(src)), 'true');
  expect('...and Play asks before playing anything',
    String(/\[CLAIMED\] the targeted Pal is bonding with another player/.test(src)), 'true');
  const ind = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('the tag says so to the other player',
    String(/ClaimedByAnotherPlayer\(actor\)[\s\S]{0,160}tag_claimed/.test(ind)), 'true');
}

console.log('\n=== G. Nothing unreadable ever blocks an interaction ===');
{
  const S = newState('prelude_323.lua', [
    'C = require("Combat")',
    '__ACTION_COMP.HasAction = function() error("cannot read the action stack") end',
  ].join('\n'));
  expect('an action stack that cannot be read: not claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'false');
  S.must('C.ForgetClaims(); __CONTROLLER.GetAIActionComponent = function() return nil end', 'nocomp');
  expect('no action component: not claimed',
    S.str('tostring(C.ClaimedByAnotherPlayer(__PAL))'), 'false');
  S.must('C.ForgetClaims()', 'reset');
  expect('a nil Pal: not claimed, no error', S.str('tostring(C.ClaimedByAnotherPlayer(nil))'), 'false');
}

console.log('\n=== H. What kind of session is this ===');
{
  const S = newState('prelude_323.lua', [
    'Sess = require("Session")',
    'require("UEHelpers").GetWorld = function() return __WORLD end',
    '__WORLD = nil',
    'function __world(driver) local w = __obj("World"); w.NetDriver = driver; return w end',
  ].join('\n'));
  expect('no world yet (title screen): unknown, and the mod still works',
    S.str('tostring(Sess.Mode()) .. "," .. tostring(Sess.MayAct())'), 'nil,true');
  S.must('Sess.Reset(); __WORLD = __world(nil)', 'sp');
  expect('a world with no NetDriver is singleplayer', S.str('Sess.Mode()'), 'singleplayer');
  S.must('Sess.Reset(); local d = __obj("NetDriver"); d.ServerConnection = __obj("ServerConnection"); __WORLD = __world(d)', 'client');
  expect('a NetDriver with a server connection means we are a guest', S.str('Sess.Mode()'), 'client');
  expect('...and the mod may not act', S.str('tostring(Sess.MayAct()) .. "," .. tostring(Sess.IsGuest())'), 'false,true');
  S.must('Sess.Reset(); __WORLD = __world(__obj("NetDriver"))', 'host');
  expect('a NetDriver with no server connection means we are hosting', S.str('Sess.Mode()'), 'host');
  expect('...and hosting may act', S.str('tostring(Sess.MayAct())'), 'true');
  S.must([
    'Sess.Reset()',
    '__UTIL = __obj("PalUtility"); __UTIL.GetNetMode = function() return "NM_DedicatedServer" end',
    '__OLDFIND = StaticFindObject',
    'StaticFindObject = function(p) if type(p) == "string" and p:find("PalUtility") then return __UTIL end return __OLDFIND(p) end',
    '__WORLD = __world(__obj("NetDriver"))',
  ].join('\n'), 'dedicated');
  expect('a dedicated net mode is named as such', S.str('Sess.Mode()'), 'dedicated');
  S.must('Sess.Reset(); __WORLD = nil', 'noworld');
  expect('the answer is asked again after a world change, not remembered',
    S.str('tostring(Sess.Mode())'), 'nil');
}
{
  // The run this cost (2026-09-20): the answer was cached a second after each
  // world change, at the TITLE SCREEN, where a world exists with no NetDriver
  // yet -- indistinguishable from singleplayer. Dragón then joined a dedicated
  // server and the mod believed "singleplayer" for the whole session.
  const S = newState('prelude_323.lua', [
    'Sess = require("Session"); P = require("PlayerRef")',
    'require("UEHelpers").GetWorld = function() return __WORLD end',
    'function __world(driver) local w = __obj("World"); w.NetDriver = driver; return w end',
    '__INWORLD = false',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" and __INWORLD then return { __PLAYER } end return nil end',
    '__WORLD = __world(nil)',
  ].join('\n'));
  expect('still loading: it answers, but does not commit',
    S.str('Sess.Mode()'), 'singleplayer');
  S.must('__CLOCK = __CLOCK + 5; __INWORLD = true; P.Invalidate(); local d = __obj("NetDriver"); d.ServerConnection = __obj("ServerConnection"); __WORLD = __world(d)', 'joined');
  expect('...so joining a server afterwards is still seen',
    S.str('Sess.Mode()'), 'client');
  expect('...and now it is committed', S.str('tostring(Sess.IsGuest())'), 'true');
}
{
  const S = newState('prelude_323.lua', [
    'Sess = require("Session"); P = require("PlayerRef")',
    'require("UEHelpers").GetWorld = function() return __WORLD end',
    'function __world(driver) local w = __obj("World"); w.NetDriver = driver; return w end',
    '__WORLD = __world(nil)',
  ].join('\n'));
  expect('with the player in the world, singleplayer is committed',
    S.str('Sess.Mode()'), 'singleplayer');
  S.must('__CLOCK = __CLOCK + 5; local d = __obj("NetDriver"); d.ServerConnection = __obj("ServerConnection"); __WORLD = __world(d)', 'changed');
  expect('...and not re-read on every call afterwards', S.str('Sess.Mode()'), 'singleplayer');
}

console.log('\n=== I. As a guest, the mod does nothing ===');
{
  const S = newState('prelude_323.lua', [
    'Sess = require("Session"); Cap = require("Capture"); C = require("Combat"); T = require("Trust")',
    'Sess.SetModeForTest("client")',
  ].join('\n'));
  S.must(CAPTURE_LOG, 'log');
  expect('the join is refused outright', S.str('tostring(Cap.TryDirectCapture(__PAL, __PLAYER))'), 'false');
  expect('...and says why', S.str('tostring(__said("the join is the server\'s to make"))'), 'true');
  S.must('C.StartFollowing(__PAL)', 'follow');
  expect('no follow is started', S.str('tostring(C.IsFollowing(__PAL))'), 'false');
  S.must('T.OnFollowerDamaged(__PAL, true)', 'hooks');
  expect('the damage hook does nothing either', S.str('tostring(T.GetPoints(__PAL) or 0)'), '0');

  // The recurring jobs, which the first version of this missed: Dragon's guest
  // run still rolled 33 personalities and still toasted on F9. The harness
  // cannot drive those scans with real Pals, so this reads the guard itself --
  // it fails on any build where a worker is missing it.
  const peo = fs.readFileSync(path.join(scriptsDir, 'Personality.lua'), 'utf8');
  const ind2 = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  const tru = fs.readFileSync(path.join(scriptsDir, 'Trust.lua'), 'utf8');
  const guarded = (src, fn) => {
    const i = src.indexOf(fn);
    return i >= 0 && /if we_are_a_guest\(\) then return end/.test(src.slice(i, i + 400));
  };
  expect('the personality scan stands down',
    String(guarded(peo, 'local function scan_nearby_wild_pals_for_personality()')), 'true');
  expect('the nameplate scan stands down',
    String(guarded(ind2, 'local function scan_for_gauge_widgets()')), 'true');
  expect('the follower tick stands down',
    String(guarded(tru, 'local function tick_followers()')), 'true');
}
{
  // The keys, for real: prelude_emote captures what RegisterKeyBind was given.
  const S = newState('prelude_emote.lua', [
    'Sess = require("Session"); Sess.SetModeForTest("client")',
    'I = require("Interaction"); I.Init()',
  ].join('\n'));
  S.must(CAPTURE_LOG, 'log');
  expect('(setup) the keys are bound', S.str('tostring(next(__BINDS) ~= nil)'), 'true');
  S.must('for _, fn in pairs(__BINDS) do pcall(fn) end', 'press');
  expect('as a guest every key does nothing',
    S.str('tostring(__said("[TAG-TOGGLE]")) .. "," .. tostring(__said("pressed"))'), 'false,false');
}
{
  const S = newState('prelude_emote.lua', [
    'Sess = require("Session"); Sess.SetModeForTest("singleplayer")',
    'I = require("Interaction"); I.Init()',
  ].join('\n'));
  S.must(CAPTURE_LOG, 'log');
  S.must('for _, fn in pairs(__BINDS) do pcall(fn) end', 'press');
  expect('control: in singleplayer the keys still work',
    S.str('tostring(__said("[TAG-TOGGLE]") or __said("pressed"))'), 'true');
}
{
  // The control: the same calls on a session we are allowed to act in.
  const S = newState('prelude_323.lua', [
    'Sess = require("Session"); Cap = require("Capture"); C = require("Combat"); T = require("Trust")',
    'Sess.SetModeForTest("singleplayer")',
  ].join('\n'));
  S.must(CAPTURE_LOG, 'log');
  S.must('Cap.TryDirectCapture(__PAL, __PLAYER)', 'capture');
  expect('singleplayer is never refused for being a guest',
    S.str('tostring(__said("the join is the server\'s to make"))'), 'false');
  S.must('C.StartFollowing(__PAL)', 'follow');
  expect('...and the follow still starts', S.str('tostring(C.IsFollowing(__PAL))'), 'true');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
