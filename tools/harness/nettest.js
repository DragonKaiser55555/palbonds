// 2026-09-21: co-op, host-authoritative.
//
// The machine that owns the world does every Pal-side job; a guest supplies
// input and shows messages. Net probe run 1 measured the pieces: a guest's
// pet/feed already reaches the owner through the game's own request, and two
// PlayerController requests carry our own text both ways. This suite covers
// what was built on that:
//
//   A. Net.lua: the message format.
//   B. The owner side only acts on a REMOTE player's message; our own
//      controller (singleplayer, the host's own actions) is ignored, so nothing
//      is ever paid twice.
//   C. The guest side only acts on the machine the message was sent TO -- the
//      hook also fires on the SENDER, where it must do nothing, or a host would
//      show every guest's messages on its own screen.
//   D. PlayerRef's acting player: set, restored, restored after an error.
//   E. A message for a remote player goes over the line; a local one does not.
//   F. Trust records who the Pal is bonding with (R4: the first player).
//   G. A guest's PET, end to end on the owner: found by id near THAT guest,
//      confirmed by the pet check -- and the check's later poll judges the
//      GUEST's pose, not the local player's (the acting player survives the
//      timer). A guest's FEED, with its amount clamped.
//   H. The guest's own copy sends instead of granting (source checks).
//
// Usage: node nettest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node nettest.js <SCRIPTS>'); process.exit(2); }
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
  must([
    // A queue for timers so the pet check's later polls can be pumped.
    '__Q = {}',
    'ExecuteInGameThreadWithDelay = function(ms, fn) __Q[#__Q + 1] = fn; return true end',
    'function __PUMPQ(n) for _ = 1, (n or 1) do local q = __Q; __Q = {}; for _, f in ipairs(q) do pcall(f) end end end',
    // Every log line, whichever Logger stub the prelude installed.
    '__LINES = {}',
    'function __said(x) for _, m in ipairs(__LINES) do if tostring(m):find(x, 1, true) then return true end end return false end',
    'function __o(name) local t = { __name = name }; t.IsValid = function() return true end;',
    '  t.GetFullName = function() return name end; return t end',
    'function __v(x, y, z) return { X = x, Y = y, Z = z } end',
    // A controller that records what was sent through it.
    'function __ctrl(name, isLocal, pawn)',
    '  local c = __o(name); c.Pawn = pawn; c.__sent = {}',
    '  c.IsLocalPlayerController = function() return isLocal end',
    '  c.Debug_ReceiveCheatCommand_ToClient = function(self, text) c.__sent[#c.__sent + 1] = text end',
    '  c.Debug_CheatCommand_ToServer = function(self, text) c.__sent[#c.__sent + 1] = text end',
    '  if pawn then pawn.Controller = c end',
    '  return c',
    'end',
  ].join('\n'), 'helpers');
  if (setup) must(setup, 'setup');
  must('local L = require("Logger"); local real = L.log; L.log = function(m) __LINES[#__LINES + 1] = tostring(m); if real then pcall(real, m) end end', 'logcap');
  return { run, str, must };
}

console.log('\n=== A. The message format ===');
{
  const S = newState('prelude_323.lua', 'Net = require("Net")');
  expect('encode', S.str('Net.Encode("PET", "ABC", 5)'), 'PB1\tPET\tABC\t5');
  expect('decode: kind', S.str('select(1, Net.Decode("PB1\\tFEED\\tABC\\t60\\tBerries"))'), 'FEED');
  expect('decode: fields', S.str('table.concat(select(2, Net.Decode("PB1\\tFEED\\tABC\\t60\\tBerries")), ",")'), 'ABC,60,Berries');
  expect('an empty field survives', S.str('#select(2, Net.Decode(Net.Encode("FEED", "ABC", "", "x")))'), '3');
  expect('a TAB inside a field cannot split it', S.str('#select(2, Net.Decode(Net.Encode("TOAST", "1", "a\\tb\\nc")))'), '2');
  expect('anything not ours is ignored', S.str('tostring(Net.Decode("god mode"))'), 'nil');
  expect('...including the probe\'s ping', S.str('tostring(Net.Decode("PALBONDS-PING 1"))'), 'nil');
}

console.log('\n=== B. The owner acts only on a REMOTE player\'s message ===');
{
  const S = newState('prelude_323.lua', [
    'Net = require("Net"); __GOT = {}',
    'Net.OnServer("PET", function(ctrl, pawn, f) __GOT[#__GOT + 1] = pawn.__name .. ":" .. f[1] end)',
    '__GUEST = __o("BP_Player_Male_C_7"); __GC = __ctrl("GuestController", false, __GUEST)',
    '__ME = __o("BP_Player_Female_C_1"); __MC = __ctrl("MyController", true, __ME)',
  ].join('\n'));
  expect('a guest\'s PET is handled', S.str('Net.HandleFromPlayer(__GC, "PB1\\tPET\\tABC")'), 'true');
  expect('...with that guest\'s character', S.str('__GOT[1]'), 'BP_Player_Male_C_7:ABC');
  expect('our own controller is ignored (the local path already did it)', S.str('Net.HandleFromPlayer(__MC, "PB1\\tPET\\tABC")'), 'false');
  expect('...so nothing was paid twice', S.str('#__GOT'), '1');
  expect('an unknown kind is ignored', S.str('Net.HandleFromPlayer(__GC, "PB1\\tDANCE\\tABC")'), 'false');
  expect('a player with no character is ignored', S.str('Net.HandleFromPlayer(__ctrl("NoPawn", false, nil), "PB1\\tPET\\tABC")'), 'false');
  expect('not ours: ignored', S.str('Net.HandleFromPlayer(__GC, "give me everything")'), 'false');
  S.must('require("PlayerRef").SetWorldClosing(true)', 'closing');
  expect('while the world is closing: ignored', S.str('Net.HandleFromPlayer(__GC, "PB1\\tPET\\tABC")'), 'false');
}

console.log('\n=== C. The guest side acts only on the machine it was sent TO ===');
{
  const S = newState('prelude_323.lua', [
    'Net = require("Net"); __SHOWN = {}',
    'Net.OnClient("TOAST", function(f) __SHOWN[#__SHOWN + 1] = f[2] end)',
    '__MC = __ctrl("MyController", true, __o("me")); __GC = __ctrl("GuestController", false, __o("guest"))',
  ].join('\n'));
  expect('arriving on our own controller: shown', S.str('Net.HandleFromHost(__MC, "PB1\\tTOAST\\t2\\thello")'), 'true');
  expect('seen on the SENDER (someone else\'s controller): nothing', S.str('Net.HandleFromHost(__GC, "PB1\\tTOAST\\t2\\tnot for me")'), 'false');
  expect('only the first one was shown', S.str('table.concat(__SHOWN, "|")'), 'hello');
}

console.log('\n=== D. The acting player ===');
{
  const S = newState('prelude_323.lua', 'P = require("PlayerRef"); __G = __o("BP_Player_Male_C_7")');
  expect('outside any scope: none', S.str('tostring(P.Acting())'), 'nil');
  expect('inside: Get() answers that player', S.str('P.WithPlayer(__G, function() return P.Get() == __G end)'), 'true');
  expect('after: none again', S.str('tostring(P.Acting())'), 'nil');
  expect('an error inside is passed on', S.str('select(1, pcall(P.WithPlayer, __G, function() error("boom") end))'), 'false');
  expect('...and the scope is still restored', S.str('tostring(P.Acting())'), 'nil');
  expect('nested scopes unwind in order',
    S.str('P.WithPlayer(__G, function() local h = __o("H"); local inner = P.WithPlayer(h, function() return P.Get() == h end); return inner and P.Get() == __G end)'), 'true');
  S.must('__G.IsLocallyControlled = function() return false end; __L = __o("L"); __L.IsLocallyControlled = function() return true end; __U = __o("U")', 'remote');
  expect('another machine\'s player is remote', S.str('P.IsRemote(__G)'), 'true');
  expect('ours is not', S.str('P.IsRemote(__L)'), 'false');
  expect('unreadable counts as ours (what every build before co-op assumed)', S.str('P.IsRemote(__U)'), 'false');
}

console.log('\n=== E. A message for a remote player goes over the line ===');
{
  const S = newState('prelude_323.lua', [
    'Cap = require("Capture"); P = require("PlayerRef")',
    '__G = __o("BP_Player_Male_C_7"); __G.IsLocallyControlled = function() return false end; __GC = __ctrl("GuestController", false, __G)',
    '__ME = __o("BP_Player_Female_C_1"); __ME.IsLocallyControlled = function() return true end; __MC = __ctrl("MyController", true, __ME)',
  ].join('\n'));
  expect('to a guest: sent', S.str('Cap.ShowLogFor(__G, "Lamball seems to like you", 2)'), 'true');
  expect('...as a TOAST with its tone and text', S.str('__GC.__sent[1]'), 'PB1\tTOAST\t2\tLamball seems to like you');
  expect('to the player at this machine: never over the line', S.str('(Cap.ShowLogFor(__ME, "hi", 1) and "x" or "") .. #__MC.__sent'), '0');
  S.must('P.WithPlayer(__G, Cap.NotifyStartedFollowing, "Lamball", false)', 'follow');
  expect('a message raised while working for that guest reaches that guest', S.str('#__GC.__sent'), '2');
}

console.log('\n=== F. Trust records who the Pal is bonding with ===');
{
  const S = newState('prelude_323.lua', [
    'T = require("Trust"); P = require("PlayerRef"); require("Capture").IsAlreadyOwned = function() return false end',
    // real guests answer IsLocallyControlled = false, and have a controller
    '__G = __o("BP_Player_Male_C_7"); __G.IsLocallyControlled = function() return false end; __ctrl("GuestController7", false, __G)',
    '__H = __o("BP_Player_Male_C_8"); __H.IsLocallyControlled = function() return false end; __ctrl("GuestController8", false, __H)',
  ].join('\n'));
  S.must('P.WithPlayer(__G, T.AddPoints, __PAL, 50, "Pet")', 'first');
  expect('the first player who earns it points owns the bond', S.str('T.GetOwner(__PAL) == __G'), 'true');
  S.must('P.WithPlayer(__H, T.AddPoints, __PAL, 50, "Pet")', 'second');
  expect('a later player does not take it (R4)', S.str('T.GetOwner(__PAL) == __G'), 'true');
  S.must('T.AddPoints(__PAL2, 50, "Pet")', 'local');
  expect('singleplayer: no owner recorded (the player at this machine)', S.str('tostring(T.GetOwner(__PAL2))'), 'nil');
}

// The owner side of a guest's pet and feed, through the real Interaction.
const GUEST_SETUP = [
  'Sess = require("Session"); Sess.SetModeForTest("dedicated")',
  'T = require("Trust"); I = require("Interaction"); I.Init(); Net = require("Net")',
  'require("Personality").GetStableId = function(p) return p and p.__id end',
  // the guest, far from the map origin, and their controller
  '__GAC_CUR = nil; __GAC = __o("GuestActionComponent"); __GAC.GetCurrentAction = function() return __GAC_CUR end',
  '__GUEST = __o("BP_Player_Male_C_7"); __GUEST.ActionComponent = __GAC',
  '__GUEST.IsLocallyControlled = function() return false end',
  '__GUEST.K2_GetActorLocation = function() return __v(50000, 0, 0) end',
  '__GC = __ctrl("GuestController", false, __GUEST)',
  // the wild Pal next to the guest
  '__AI = nil; __AIC = __o("AIComp"); __AIC.GetCurrentAction_BP = function() return __AI end',
  '__W = __o("BP_SheepBall_C_2147460274"); __W.__id = "PALID1"',
  '__W.Controller = __o("WildAI"); __W.Controller.GetAIActionComponent = function() return __AIC end',
  '__W.K2_GetActorLocation = function() return __v(50300, 0, 0) end',
  // a Pal with the same id far away must never be picked
  '__FAR = __o("BP_SheepBall_C_far"); __FAR.__id = "PALID1"; __FAR.K2_GetActorLocation = function() return __v(0, 0, 0) end',
  'local realFind = FindAllOf',
  'FindAllOf = function(n) if n == "PalCharacter" then return { __FAR, __W } end return realFind(n) end',
  // this machine's own player sits in a petting pose the whole time: if the
  // pet check ever looked at THEM instead of the guest, it would pay wrongly
  '__MY_CUR = __o("BP_ActionPairBehavior_Petting_C_mine")',
  '__PAWN.ActionComponent = { IsValid = function() return true end, GetCurrentAction = function() return __MY_CUR end }',
  'WILD = __o("BP_AIAction_WildLife_C_1"); PET = __o("BP_AIActionPairCall_Petting_C_5")',
  'STANDBY = __o("BP_ActionPairStandby_Petting_C_1"); BEHAVIOR = __o("BP_ActionPairBehavior_Petting_C_1")',
].join('\n');

console.log('\n=== G. A guest\'s PET and FEED, on the machine that owns the world ===');
{
  const S = newState('prelude_emote.lua', GUEST_SETUP);
  S.must('__AI = WILD; __GAC_CUR = nil', 'before');
  expect('the guest\'s PET is accepted', S.str('Net.HandleFromPlayer(__GC, "PB1\\tPET\\tPALID1")'), 'true');
  expect('nothing is paid before the Pal is petted', S.str('T.GetPoints(__W)'), '0');
  S.must('__AI = PET; __GAC_CUR = BEHAVIOR', 'petting');
  S.must('__PUMPQ(1)', 'poll');
  expect('the pet is confirmed on a LATER poll and paid', S.str('T.GetPoints(__W) > 0'), 'true');
  expect('...to the Pal next to the guest, not the one with the same id far away', S.str('T.GetPoints(__FAR)'), '0');
  expect('...and the bond belongs to that guest', S.str('T.GetOwner(__W) == __GUEST'), 'true');
}
{
  // The guest has NOT reached the pet yet (still waiting) while this machine's
  // own player IS in a petting pose. A pet check that lost the guest on the
  // timer would read the local player and pay.
  const S = newState('prelude_emote.lua', GUEST_SETUP);
  S.must('__AI = WILD; __GAC_CUR = nil', 'before');
  S.must('Net.HandleFromPlayer(__GC, "PB1\\tPET\\tPALID1")', 'pet');
  S.must('__AI = PET; __GAC_CUR = STANDBY', 'accepted-not-arrived');
  S.must('__PUMPQ(1)', 'poll');
  expect('the later poll judges the GUEST\'s pose: not paid yet', S.str('T.GetPoints(__W)'), '0');
}
{
  // The pet message can arrive after the Pal already started its animation.
  const S = newState('prelude_emote.lua', GUEST_SETUP);
  S.must('__AI = PET; __GAC_CUR = BEHAVIOR', 'already');
  S.must('Net.HandleFromPlayer(__GC, "PB1\\tPET\\tPALID1")', 'late');
  expect('a guest\'s pet already playing when the message arrives counts', S.str('T.GetPoints(__W) > 0'), 'true');
}
{
  const S = newState('prelude_emote.lua', GUEST_SETUP);
  expect('an id nobody near the guest has: nothing', S.str('Net.HandleFromPlayer(__GC, "PB1\\tPET\\tNOPE") and T.GetPoints(__W)'), '0');
  expect('...and it says so', S.str('__said("cannot find near them")'), 'true');
  S.must('Net.HandleFromPlayer(__GC, "PB1\\tFEED\\tPALID1\\t60\\tBerries")', 'feed');
  expect('a guest\'s FEED pays its amount', S.str('T.GetPoints(__W)'), '60');
  expect('...to that guest', S.str('T.GetOwner(__W) == __GUEST'), 'true');
  S.must('Net.HandleFromPlayer(__GC, "PB1\\tFEED\\tPALID1\\t99999\\tBerries")', 'huge');
  expect('an impossible amount is capped at the largest real feed', S.str('T.GetPoints(__W)'), '560');
  S.must('Net.HandleFromPlayer(__GC, "PB1\\tFEED\\tPALID1\\t-400\\tBerries")', 'negative');
  expect('a negative amount pays nothing (never takes trust away)', S.str('T.GetPoints(__W)'), '560');
}

console.log('\n=== H. On a guest, the mod sends instead of granting ===');
{
  const inter = fs.readFileSync(path.join(scriptsDir, 'Interaction.lua'), 'utf8');
  const care = inter.indexOf('local petTarget = lastRedirectedWildPalActor');
  expect('a guest\'s pet is sent to the host, not checked locally',
    String(care >= 0 && /if we_are_a_guest\(\) then\s+-- Co-op[^\n]*\n\s+safe_call\(function\(\) send_pet_to_host\(petTarget\) end\)/.test(inter.slice(care, care + 400))), 'true');
  const feedHook = inter.indexOf('if guestFeed then\n                send_feed_to_host(');
  expect('a guest\'s feed is sent to the host, not granted locally', String(feedHook >= 0), 'true');
  expect('a guest never writes its own inventory slot', String(/if guestFeed then\s+Logger\.log\([^\n]*no local write/.test(inter)), 'true');
  const trust = fs.readFileSync(path.join(scriptsDir, 'Trust.lua'), 'utf8');
  const fc = trust.indexOf('local function finish_capture_now');
  expect('the join after the 5 s wait runs as the Pal\'s owner',
    String(fc >= 0 && /PlayerRef\.WithPlayer\(owner, Capture\.OnTrustMaxed, pal\)/.test(trust.slice(fc, fc + 1200))), 'true');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
