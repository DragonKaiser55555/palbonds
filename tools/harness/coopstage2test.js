// 2026-09-21: co-op stage 2 -- one host (or dedicated server), several players.
//
// Stage 1 made a guest's pet, feed, follow and join work on the machine that
// owns the world, for ONE guest. This covers what lets several players share
// it:
//
//   S1. Timers carry the player they were scheduled for (PlayerRef).
//   S2. Owner keys: "local" for the player at this machine; a guest's
//       controller for anyone else, so a respawned guest keeps their bonds.
//   S3. Claims (R2/R4): the first player keeps the Pal; the claim ends at 0.
//   S4. The follower tick runs per owner: a guest's follower is measured
//       against THAT guest (drift), the host's against the host.
//   S5. A guest who leaves: their bonds and claims are released (Q3).
//   S6. Fight state per player: the guest fighting does not put the host in
//       a fight.
//   S7. A dedicated server has no player of its own, and "nobody here" never
//       resets the world there.
//   S8. The damage hooks: a guest's fight reaches combat assist as that
//       guest; only a Pal's OWN player betrays it (R3).
//   S9. The join light is sent to a remote owner.
//   S10-S12. Stage 3 (HostView) and the co-op run 2 fixes.
//   S13. The co-op run 3 fixes.
//   S14. A guest's dungeon loading screen: resync with the host.
//   S15. A loading screen leaves followers behind, as abandoned.
//
// Usage: node coopstage2test.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node coopstage2test.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');
let failures = 0;

function expect(label, actual, want) {
  const ok = actual === want;
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

function newState(extra) {
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
    // the player at this machine answers "mine"; guests answer "not mine"
    '__PLAYER.IsLocallyControlled = function() return true end',
    'function __ctrl(name, pawn)',
    '  local c = __obj(name); c.Pawn = pawn; c.__sent = {}',
    '  c.IsLocalPlayerController = function() return false end',
    '  c.Debug_ReceiveCheatCommand_ToClient = function(self, t) c.__sent[#c.__sent + 1] = t end',
    '  if pawn then pawn.Controller = c end',
    '  return c',
    'end',
    'function __guest(name, x)',
    '  local g = __obj(name); g.IsLocallyControlled = function() return false end',
    '  g.__loc = __vec(x or 0, 0, 0); g.K2_GetActorLocation = function() return g.__loc end',
    '  g.GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end',
    '  return g',
    'end',
    '__G = __guest("BP_Player_Male_C_7", 0); __GC = __ctrl("PalPlayerController_7", __G)',
    '__H = __guest("BP_Player_Male_C_8", 0); __HC = __ctrl("PalPlayerController_8", __H)',
    'for _, pal in ipairs({ __PAL, __PAL2 }) do',
    '  pal.CharacterParameterComponent = __obj("ParamComp")',
    '  pal.CharacterParameterComponent.GetIndividualParameter = function() return __obj("Param") end',
    '  pal.CharacterParameterComponent.IsDead = function() return false end',
    '  pal.CharacterParameterComponent.IsDying = function() return false end',
    'end',
    '__PAL2_LOC = __vec(0, 0, 0); __PAL2.K2_GetActorLocation = function() return __PAL2_LOC end',
    'P = require("PlayerRef"); T = require("Trust"); C = require("Combat"); C.Init(); T.Init()',
    'Cap = require("Capture")',
    'Cap.IsAlreadyOwned = function() return false end',
    'Cap.HasPermanentlyFled = function() return false end',
    'Cap.NotifyTrustShaken = function() end',
    'Cap.OnTrustMaxed = function() end',
    '__LOST = {}; Cap.OnTrustLost = function(pal, kind) __LOST[#__LOST + 1] = pal:GetFullName() .. ":" .. tostring(kind) end',
    'Cap.NotifyStartedFollowing = function() end',
    'Cap.ResolveDisplayName = function() return "Lamball" end; Cap.IsFemale = function() return false end',
    'function __has(x) for _, m in ipairs(__ALLLOG) do if m:find(x, 1, true) then return true end end return false end',
    // bond a Pal to 50% as a given player (nil = the host)
    'function __bond(pal, who)',
    '  local f = function() T.AddPoints(pal, 250, "Pet"); T.OnInteractionSucceeded(pal) end',
    '  if who then P.WithPlayer(who, f) else f() end',
    'end',
  ].join('\n'), 'setup');
  if (extra) must(extra, 'extra');
  return { run, str, must };
}

console.log('\n=== S1. Timers carry the player they were scheduled for ===');
{
  const S = newState();
  S.must('P.WithPlayer(__G, function() ExecuteInGameThreadWithDelay(10, function() __SEEN = P.Get() end) end)', 'sched');
  S.must('__PENDING_KEEP = __PENDING; __PENDING = {}; for _, f in ipairs(__PENDING_KEEP) do pcall(f) end', 'fire');
  expect('a timer scheduled for the guest runs as the guest', S.str('__SEEN == __G'), 'true');
  S.must('ExecuteInGameThreadWithDelay(10, function() __SEEN2 = P.Get() end)', 'sched2');
  S.must('__PENDING_KEEP = __PENDING; __PENDING = {}; for _, f in ipairs(__PENDING_KEEP) do pcall(f) end', 'fire2');
  expect('one scheduled outside any scope runs for the player at this machine', S.str('__SEEN2 == __PLAYER'), 'true');
}

console.log('\n=== S2. Owner keys ===');
{
  const S = newState();
  expect('the player at this machine is "local"', S.str('P.OwnerKey(__PLAYER)'), 'local');
  expect('a guest is their controller', S.str('P.OwnerKey(__G)'), 'PalPlayerController_7');
  S.must('__G2 = __guest("BP_Player_Male_C_7_respawned", 0); __GC.Pawn = __G2; __G2.Controller = __GC', 'respawn');
  expect('...and keeps it after respawning as a new character', S.str('P.OwnerKey(__G2)'), 'PalPlayerController_7');
}

console.log('\n=== S3. Claims: the first player keeps the Pal (R2/R4) ===');
{
  const S = newState();
  S.must('P.WithPlayer(__G, T.AddPoints, __PAL, 50, "Pet")', 'g');
  expect('the guest who earned it may keep bonding', S.str('P.WithPlayer(__G, T.MayBond, __PAL)'), 'true');
  expect('another guest may not', S.str('P.WithPlayer(__H, T.MayBond, __PAL)'), 'false');
  expect('the host may not either', S.str('T.MayBond(__PAL)'), 'false');
  expect('a Pal nobody has touched is free for anyone', S.str('P.WithPlayer(__H, T.MayBond, __PAL2)'), 'true');
  S.must('T.AddPoints(__PAL2, 50, "Pet")', 'host');
  expect('a Pal the host earned is the host\'s', S.str('P.WithPlayer(__G, T.MayBond, __PAL2)'), 'false');
  S.must('P.WithPlayer(__G, T.AddPoints, __PAL, -999, "hit")', 'zero');
  expect('the claim ends when the bar reaches 0 (Q3)', S.str('P.WithPlayer(__H, T.MayBond, __PAL)'), 'true');
}

console.log('\n=== S4. The follower tick runs per owner ===');
{
  const S = newState();
  S.must('__bond(__PAL, nil); __bond(__PAL2, __G)', 'bond');
  expect('(setup) the host\'s Pal follows', S.str('C.IsFollowing(__PAL)'), 'true');
  expect('(setup) the guest\'s Pal follows', S.str('C.IsFollowing(__PAL2)'), 'true');
  expect('the follow records who it belongs to', S.str('C.FollowerOwnerKey and C.FollowerOwnerKey(__PAL2)'), 'PalPlayerController_7');
  // The GUEST walks far away. The host and both Pals stay at the origin. Only a
  // tick that measures the guest's Pal against the GUEST sees it left behind.
  // Not fighting (the prelude's default action is a combat one, which pauses the leash).
  S.must('__HATE_TARGET = nil; __CURRENT_ACTION.__name = "BP_AIAction_WildLife_C_9"', 'idle');
  S.must('__G.__loc = __vec(6000, 0, 0); __PUMP(1)', 'far');
  S.must('__CLOCK = __CLOCK + 5; __PUMP(1)', 'grace');
  expect('the guest\'s Pal, left far behind by the guest, is lost', S.str('C.IsFollowing(__PAL2)'), 'false');
  expect('the host\'s Pal, next to the host, still follows', S.str('C.IsFollowing(__PAL)'), 'true');
}

console.log('\n=== S5. A guest who leaves the world ===');
{
  const S = newState();
  S.must('__bond(__PAL2, __G); P.WithPlayer(__H, T.AddPoints, __PAL, 50, "Pet")', 'bond');
  S.must('__GC.IsValid = function() return false end; __HC.IsValid = function() return false end; __PUMP(1)', 'leave');
  expect('their follower is released', S.str('C.IsFollowing(__PAL2)'), 'false');
  expect('...and so is a claim below 50%', S.str('tostring(T.GetOwnerKey(__PAL))'), 'nil');
  expect('...so the next player can bond it', S.str('T.MayBond(__PAL)'), 'true');
  expect('...and the log says why', S.str('__has("its player left the world")'), 'true');
}
{
  const S = newState();
  S.must('__bond(__PAL2, __G)', 'bond');
  S.must('__GC.Pawn = nil; __PUMP(1)', 'dead');
  expect('a guest who is only dead (controller still there) keeps their Pal', S.str('C.IsFollowing(__PAL2)'), 'true');
}

console.log('\n=== S6. One fight state per player ===');
{
  const S = newState();
  S.must('__bond(__PAL2, __G)', 'bond');
  S.must('P.WithPlayer(__G, C.OnPlayerCombatTarget, __ENEMY, __G)', 'fight');
  expect('the guest is fighting', S.str('P.WithPlayer(__G, C.IsPlayerInCombat)'), 'true');
  expect('the host is not', S.str('C.IsPlayerInCombat()'), 'false');
}

console.log('\n=== S7. A dedicated server has no player of its own ===');
{
  const S = newState('Sess = require("Session"); Sess.SetModeForTest("dedicated")');
  expect('nobody, even with one character in the world', S.str('tostring(P.Get())'), 'nil');
  expect('work done for a guest still sees that guest', S.str('P.WithPlayer(__G, P.Get) == __G'), 'true');
  S.must('__bond(__PAL2, __G); C.StartTrainerReassertLoop()', 'loop');
  S.must('for i = 1, 30 do __CLOCK = __CLOCK + 0.2; __PUMP(1) end', 'run');
  expect('"nobody here" never reads as the world ending', S.str('__has("the player left the world") or __has("the player actor went invalid")'), 'false');
  expect('the guest\'s Pal still follows', S.str('C.IsFollowing(__PAL2)'), 'true');
}

console.log('\n=== S8. The damage hooks ===');
{
  const S = newState([
    '__FIGHTS = {}',
    'C.OnPlayerCombatTarget = function(enemy, player) __FIGHTS[#__FIGHTS + 1] = { p = player, seen = P.Get() } end',
    'function __dmg(a, d) return __FIRE("/Script/Pal.PalHate:DamageEvent", __arg(nil), __arg({ Attacker = a, Defender = d, Damage = 10 })) end',
    'function __hit(a, d) return __FIRE("/Script/Pal.PalDamageReactionComponent:OnProcessedActualDamageDelegate__DelegateSignature", __arg(nil), __arg(a), __arg(d), __arg(10)) end',
  ].join('\n'));
  S.must('__bond(__PAL2, __G)', 'bond');
  expect('(setup) the hook is there', S.str('__dmg(__G, __ENEMY)'), 'ok');
  expect('a guest hitting an enemy starts combat assist for THAT guest', S.str('__FIGHTS[1] and __FIGHTS[1].p == __G'), 'true');
  expect('...running as that guest', S.str('__FIGHTS[1] and __FIGHTS[1].seen == __G'), 'true');
  S.must('__before = T.GetPoints(__PAL2)', 'before');
  S.must('__hit(__PLAYER, __PAL2)', 'host-hits');
  expect('the host hitting the guest\'s Pal is not a betrayal (R3)', S.str('T.GetPoints(__PAL2) == __before'), 'true');
  S.must('__CLOCK = __CLOCK + 2; __hit(__G, __PAL2)', 'owner-hits');
  expect('the guest hitting their OWN Pal is', S.str('T.GetPoints(__PAL2) < __before'), 'true');
}

console.log('\n=== S9. The join light reaches a remote owner ===');
{
  const cap = fs.readFileSync(path.join(scriptsDir, 'Capture.lua'), 'utf8');
  expect('the celebration asks for it', String(/spawn_niagara_at\(pal, JOIN_VFX_ASSET_PATH\)\s+show_join_light_to_remote_owner\(pal\)/.test(cap)), 'true');
  expect('the guest side is declared before Init uses it', String(cap.indexOf('local play_join_light_for_host') < cap.indexOf('function Capture.Init()')), 'true');
  const S = newState([
    'require("Personality").GetStableId = function(p) return "PALID" end',
    'Net = require("Net"); Cap.Init()',
    '__MYC = __obj("MyController"); __MYC.IsLocalPlayerController = function() return true end',
  ].join('\n'));
  expect('the guest handles JOINFX', S.str('Net.HandleFromHost(__MYC, "PB1\\tJOINFX\\tPALID")'), 'true');
}

console.log('\n=== S10. Stage 3: a guest\'s nameplates read the host\'s numbers ===');
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("client")',
    'HV = require("HostView"); Net = require("Net"); HV.Init()',
    'require("Personality").GetStableId = function(p) if p == __PAL then return "PALID1" end if p == __PAL2 then return "PALID2" end end',
    '__MYC = __obj("MyController"); __MYC.IsLocalPlayerController = function() return true end',
    'local FS, RS = string.char(30), string.char(31)',
    'function __rec(id, disp, pct, bond, fem, fled, rel) return table.concat({ id, disp, tostring(pct), bond, fem, fled, rel }, FS) end',
    '__INFO = "PB1\\tINFO\\t" .. __rec("PALID1", "friendly", 40, "1", "1", "", "mine") .. RS .. __rec("PALID2", "warlike", 0, "0", "0", "", "other")',
  ].join('\n'));
  expect('before the host says anything: no host view, nameplates stay off', S.str('HV.HostHasPalBonds()'), 'false');
  expect('...and the bar is empty', S.str('T.GetBarRatio(__PAL)'), '0');
  expect('the host\'s INFO is accepted', S.str('Net.HandleFromHost(__MYC, __INFO)'), 'true');
  expect('now the host has PalBonds', S.str('HV.HostHasPalBonds()'), 'true');
  expect('the bar is the host\'s number', S.str('T.GetBarRatio(__PAL)'), '0.4');
  expect('bonding, as the host says', S.str('T.HasBondingState(__PAL)'), 'true');
  expect('a Pal with an empty bar has no bond', S.str('T.HasBondingState(__PAL2)'), 'false');
  expect('another player\'s bond shows as claimed', S.str('C.ClaimedByAnotherPlayer(__PAL2)'), 'true');
  expect('our own bond does not', S.str('C.ClaimedByAnotherPlayer(__PAL)'), 'false');
  expect('personality and gender come from the host', S.str('HV.Disposition("PALID1") .. "," .. tostring(HV.Female("PALID1"))'), 'friendly,true');
  const pers = fs.readFileSync(path.join(scriptsDir, 'Personality.lua'), 'utf8');
  const cap = fs.readFileSync(path.join(scriptsDir, 'Capture.lua'), 'utf8');
  expect('Personality answers a guest from the host view', String(/function Personality\.GetDisposition\(palId\)\s+if palId == nil then return nil end\s+local view = guest_view\(\)/.test(pers) && /function Personality\.IsFemale\(palId\)\s+local view = guest_view\(\)/.test(pers)), 'true');
  expect('a guest never rolls a personality', String(/if guest_view\(\) then return palId end/.test(pers)), 'true');
  expect('Capture answers a guest\'s broken-bond label from the host view', String(/function Capture\.HasPermanentlyFled\(pal\)\s+local view = guest_view\(\)/.test(cap)), 'true');
  const ind = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('Indicator waits for the host view instead of standing down', String((ind.match(/guest_without_host_view\(\)/g) || []).length >= 2 && !/or we_are_a_guest\(\) then return end/.test(ind)), 'true');
}

console.log('\n=== S11. Stage 3: the host sends each guest what changed near them ===');
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    'HV = require("HostView")',
    'local realFind = FindAllOf',
    '__FINDS = 0',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then __FINDS = __FINDS + 1; return { __PLAYER, __G } end return realFind(n) end',
    'require("Personality").GetStableId = function(p) if p == __PAL then return "PALID1" end end',
    'require("Personality").ForEachKnownPal = function(fn) fn("PALID1", __PAL, { disposition = "friendly", female = false }) end',
  ].join('\n'));
  S.must('P.WithPlayer(__G, T.AddPoints, __PAL, 100, "Pet")', 'grant');
  expect('one record sent', S.str('HV.SendUpdates()'), '1');
  expect('...to the guest, not to the host', S.str('#__GC.__sent'), '1');
  expect('...as their own bond at 20%', S.str('(__GC.__sent[1]:find("mine", 1, true) ~= nil) and (__GC.__sent[1]:find(string.char(30) .. "20" .. string.char(30), 1, true) ~= nil)'), 'true');
  expect('nothing changed: nothing sent', S.str('HV.SendUpdates()'), '0');
  S.must('P.WithPlayer(__G, T.AddPoints, __PAL, 100, "Pet")', 'more');
  expect('the bar moved: sent again', S.str('HV.SendUpdates()'), '1');
  S.must('__G.__loc = __vec(20000, 0, 0)', 'away');
  S.must('P.WithPlayer(__G, T.AddPoints, __PAL, 50, "Pet")', 'far-grant');
  expect('a Pal far from the guest is not sent', S.str('HV.SendUpdates()'), '0');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("singleplayer")',
    'HV = require("HostView")',
    // a Pal is known, so only the singleplayer early exit can prevent the search
    'require("Personality").ForEachKnownPal = function(fn) fn("PALID1", __PAL, { disposition = "friendly" }) end',
    'local realFind = FindAllOf',
    '__FINDS = 0',
    'FindAllOf = function(n) __FINDS = __FINDS + 1; return realFind(n) end',
  ].join('\n'));
  expect('singleplayer: nothing is sent', S.str('HV.SendUpdates()'), '0');
  expect('...and not a single world search was made for it', S.str('__FINDS'), '0');
}

console.log('\n=== S12. Co-op run 2 fixes: binds, hello, asking, F9 ===');
{
  const ind = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  const b = ind.indexOf('RegisterHook(hookPath, function(Context, TargetHandle)');
  expect('the bind hook records even before the host has spoken (run 2: the first Cattiva\'s bind was lost)',
    String(b >= 0 && !/guest_without_host_view/.test(ind.slice(b, b + 900))), 'true');
  const bo = ind.indexOf('RegisterHook(BOSS_GAUGE_HOOK_PATH');
  expect('...the boss hook too', String(bo >= 0 && !/guest_without_host_view/.test(ind.slice(bo, bo + 200))), 'true');
  const sc = ind.indexOf('local function scan_for_gauge_widgets()');
  expect('...while the drawing still waits for the host', String(/if guest_without_host_view\(\) then return end/.test(ind.slice(sc, sc + 300))), 'true');
  const inter = fs.readFileSync(path.join(scriptsDir, 'Interaction.lua'), 'utf8');
  const k = inter.indexOf('RegisterKeyBind(Key[TAGS_KEY], function()');
  expect('F9 works on a guest (only a dedicated server ignores it)',
    String(k >= 0 && /if on_dedicated_server\(\) then return end/.test(inter.slice(k, k + 500)) && !/we_are_a_guest\(\)/.test(inter.slice(k, k + 500))), 'true');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    'HV = require("HostView")',
    'local realFind = FindAllOf',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then return { __PLAYER, __G } end return realFind(n) end',
    'require("Personality").ForEachKnownPal = function(fn) end',
  ].join('\n'));
  expect('a new guest with nothing near them still gets a hello', S.str('HV.SendUpdates() .. ":" .. #__GC.__sent'), '0:1');
  expect('...an empty INFO', S.str('__GC.__sent[1]'), 'PB1\tINFO\t');
  S.must('HV.SendUpdates()', 'again');
  expect('...once', S.str('#__GC.__sent'), '1');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    'HV = require("HostView")',
    '__INITS = 0; __REMEMBERED = nil',
    'local Pers = require("Personality")',
    'Pers.GetStableId = function(p) if p == __PAL then return "PALID1" end if p == __PAL2 then return "PALID2" end end',
    'Pers.GetOrInitState = function(p) __INITS = __INITS + 1; return "PALID1" end',
    'Pers.RememberPawn = function(id, p) __REMEMBERED = id end',
    'Pers.GetState = function(id) return { disposition = "warlike", female = true } end',
    'local realFind = FindAllOf',
    'FindAllOf = function(n) if n == "PalCharacter" then return { __PAL, __PAL2 } end return realFind(n) end',
  ].join('\n'));
  expect('the host answers an ASK for a Pal next to the guest', S.str('HV.AnswerAsk(__G, "PALID1")'), '1');
  expect('...giving it a personality if it had none, as singleplayer does', S.str('__INITS'), '1');
  expect('...remembering it for the regular updates', S.str('__REMEMBERED'), 'PALID1');
  expect('...and the answer goes to that guest, with the personality', S.str('#__GC.__sent == 1 and __GC.__sent[1]:find("warlike", 1, true) ~= nil'), 'true');
  expect('a Pal the guest did not ask about is left out', S.str('__GC.__sent[1]:find("PALID2", 1, true) == nil'), 'true');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("client")',
    'HV = require("HostView"); Net = require("Net"); HV.Init()',
    '__MY = __obj("MyController"); __MY.__sent = {}; __MY.IsLocalPlayerController = function() return true end',
    '__MY.Debug_CheatCommand_ToServer = function(self, t) __MY.__sent[#__MY.__sent + 1] = t end',
    '__PLAYER.Controller = __MY',
  ].join('\n'));
  S.must('HV.Disposition("PALID9")', 'unknown');
  expect('before the host has said hello, nothing is asked', S.str('HV.SendAsks()'), '0');
  S.must('Net.HandleFromHost(__MY, "PB1\\tINFO\\t")', 'hello');
  S.must('HV.Disposition("PALID9")', 'unknown2');
  expect('a nameplate showing an unknown Pal asks the host', S.str('HV.SendAsks()'), '1');
  expect('...with its id', S.str('__MY.__sent[1]'), 'PB1\tASK\tPALID9');
  S.must('HV.Disposition("PALID9")', 'again');
  expect('...and not again within 10 s', S.str('HV.SendAsks()'), '0');
  S.must('__CLOCK = __CLOCK + 11; HV.Disposition("PALID9")', 'later');
  expect('...but again after that, if the host still has not answered', S.str('HV.SendAsks()'), '1');
}

console.log('\n=== S13. Co-op run 3 fixes: messages in the guest\'s language, per-player F10, Play and food for a guest, asking backs off ===');
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
  ].join('\n'));
  S.must('Cap.ShowLogFor(__G, "Lamball parece tenerte cariño.", 2, "following", "Lamball", true)', 'send');
  expect('a message for a guest goes as WHICH message, not the host\'s words (run 3: Spanish text on an English guest)',
    S.str('__GC.__sent[1]'), 'PB1\tMSG\t2\tfollowing\tLamball\t1\t');
  S.must('Cap.ShowLogFor(__G, "free text", 1)', 'send2');
  expect('...a message with no key still goes as text', S.str('__GC.__sent[2]'), 'PB1\tTOAST\t1\tfree text');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("client")',
    'Loc = require("Locale"); Loc.Current = function() return __LANG end; __LANG = "en"',
  ].join('\n'));
  expect('the guest writes it in ITS language',
    S.str('select(2, Cap.RenderHostMessage({ "2", "following", "Lamball", "0", "" }))'), 'Lamball seems to like you and starts following you.');
  S.must('__LANG = "es"', 'es');
  expect('...a Spanish guest gets Spanish from the same message',
    S.str('select(2, Cap.RenderHostMessage({ "2", "following", "Lamball", "0", "" })) ~= "Lamball seems to like you and starts following you."'), 'true');
  S.must('__LANG = "en"', 'en');
  expect('...the Pal\'s name is looked up again on the guest from its id',
    S.str('select(2, Cap.RenderHostMessage({ "2", "following", "NombreDelHost", "0", "SheepBall" })):find("Sheep Ball", 1, true) ~= nil'), 'true');
  expect('...a message with no name uses the guest\'s own "a Pal"',
    S.str('select(2, Cap.RenderHostMessage({ "1", "abandoned", "", "0", "" })):find(Loc.T("a_pal"), 1, true) ~= nil'), 'true');
  expect('...and no key means nothing is shown', S.str('Cap.RenderHostMessage({ "1", "", "", "0", "" }) == nil'), 'true');
  const cap = fs.readFileSync(path.join(scriptsDir, 'Capture.lua'), 'utf8');
  expect('every Pal message passes its key (join, following, shaken, bond lost, toasts)',
    String(['"joined" or "joined_unnamed"', '"following", name', '"shaken", palName', 'show_log(player, message, 1, key, palName', 'show_log(player, message, 1, key)'].every(x => cap.includes(x))), 'true');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
  ].join('\n'));
  expect('F10 is per player: a guest switching it off...', S.str('T.TogglePassiveFriendshipGain(P.OwnerKey(__G))'), 'false');
  expect('...turns it off for that guest', S.str('T.IsPassiveGainEnabled(P.OwnerKey(__G))'), 'false');
  expect('...and not for the host', S.str('T.IsPassiveGainEnabled()'), 'true');
  const tru = fs.readFileSync(path.join(scriptsDir, 'Trust.lua'), 'utf8');
  expect('the follower tick reads the switch of the group\'s owner', String(/elseif passiveGainOffBy\[groupKey or "local"\] then/.test(tru)), 'true');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    'I = require("Interaction")',
    'local c = __obj("Container"); c.ID = { ID = { A = 1, B = 2, C = 3, D = 4 } }',
    'local function slot(id, n) local s = __obj("Slot"); s.ItemId = { StaticId = { ToString = function() return id end } }; s.StackCount = n; return s end',
    '__SLOT0 = slot("Wood", 50); __SLOT1 = slot("Berries", 10)',
    'c.ItemSlotArray = { __SLOT0, __SLOT1 }',
    'local other = __obj("Chest"); other.ID = { ID = { A = 9, B = 9, C = 9, D = 9 } }; other.ItemSlotArray = {}',
    'local realFind = FindAllOf',
    'FindAllOf = function(n) if n == "PalItemContainer" then return { other, c } end return realFind(n) end',
  ].join('\n'));
  expect('the host charges a guest\'s food in that guest\'s slot (run 3: the Berries were free)',
    S.str('I.ChargeGuestFood("00000001000000020000000300000004", 1, "Berries", 1)'), 'true');
  expect('...one Berry gone', S.str('__SLOT1.StackCount'), '9');
  expect('a slot that no longer holds that food is left alone',
    S.str('I.ChargeGuestFood("00000001000000020000000300000004", 0, "Berries", 1) == false and __SLOT0.StackCount == 50'), 'true');
  expect('an unknown container charges nothing', S.str('I.ChargeGuestFood("DEADBEEF", 1, "Berries", 1)'), 'false');
  // 1.1.7: a guest names the slot, so the owner charges only that guest's OWN
  // containers -- otherwise a crafted client could empty someone else's.
  expect('a container belonging to someone else is refused',
    S.str('I.ChargeGuestFood("00000001000000020000000300000004", 1, "Berries", 1, { OTHERHEX = true }) == false and __SLOT1.StackCount == 9'), 'true');
  expect('...and their own is still charged',
    S.str('I.ChargeGuestFood("00000001000000020000000300000004", 1, "Berries", 1, { ["00000001000000020000000300000004"] = true })'), 'true');
  const inter = fs.readFileSync(path.join(scriptsDir, 'Interaction.lua'), 'utf8');
  expect('the guest names its slot in the FEED', String(/container = guid_hex\(safe_call\(function\(\) return slot\.ContainerId\.ID end\)\)/.test(inter)), 'true');
  expect('...and the host charges it before anything else in the FEED handler',
    String((() => { const i = inter.indexOf('Net.OnServer("FEED"'); const j = inter.indexOf('charge_guest_food(', i); const k = inter.indexOf('find_wild_pal_near(', i); return i >= 0 && j > i && j < k; })()), 'true');
}
{
  const inter = fs.readFileSync(path.join(scriptsDir, 'Interaction.lua'), 'utf8');
  const k8 = inter.indexOf('RegisterKeyBind(Key[PLAY_KEY], function()');
  expect('F8 works on a guest', String(k8 >= 0 && !/we_are_a_guest\(\)/.test(inter.slice(k8, k8 + 300))), 'true');
  const dp = inter.indexOf('local function do_play()');
  expect('...which sends PLAY to the host instead of moving the Pal itself',
    String(/if we_are_a_guest\(\) then[\s\S]{0,200}SendToServer\("PLAY", palId\)/.test(inter.slice(dp))), 'true');
  const k10 = inter.indexOf('RegisterKeyBind(Key[PASSIVE_KEY], function()');
  expect('F10 on a guest asks the host', String(/SendToServer\("PASSIVE"\)/.test(inter.slice(k10, k10 + 700))), 'true');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    'Net = require("Net")',
    'I = require("Interaction"); I.Init()',
    'require("Personality").GetStableId = function(p) if p == __PAL then return "PALID1" end end',
    'local realFind = FindAllOf',
    'FindAllOf = function(n) if n == "PalCharacter" then return { __PAL } end if n == "PalPlayerCharacter" then return { __PLAYER, __G } end return realFind(n) end',
    '__PLAYS = {}',
    '__PAL.ActionComponent = __obj("PalActions")',
    '__PAL.ActionComponent.ActionIsEmpty = function() return true end',
    '__PAL.ActionComponent.PlayActionByType = function(self, pal, t) __PLAYS[#__PLAYS + 1] = t end',
    '__PAL.ActionComponent.CancelActionByType = function() end',
  ].join('\n'));
  expect('a guest\'s PLAY is taken', S.str('Net.HandleFromPlayer(__GC, "PB1\\tPLAY\\tPALID1")'), 'true');
  expect('...and the host plays the Pal\'s animation', S.str('#__PLAYS'), '1');
  S.must('local q = __PENDING; __PENDING = {}; for _, f in ipairs(q) do pcall(f) end', 'fire');
  expect('...then Happy', S.str('#__PLAYS'), '2');
  expect('...and the trust goes to THAT guest', S.str('T.GetOwnerKey(__PAL) == P.OwnerKey(__G)'), 'true');
  S.must('Net.HandleFromPlayer(__GC, "PB1\\tPASSIVE")', 'f10');
  expect('a guest\'s F10 switches it for that guest only', S.str('tostring(T.IsPassiveGainEnabled(P.OwnerKey(__G))) .. "," .. tostring(T.IsPassiveGainEnabled())'), 'false,true');
  expect('...and tells them, as a message in their language', S.str('__GC.__sent[#__GC.__sent]'), 'PB1\tMSG\t1\tpassive_off\t\t0\t');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("client")',
    'HV = require("HostView"); Net = require("Net"); HV.Init()',
    '__MY = __obj("MyController"); __MY.__sent = {}; __MY.IsLocalPlayerController = function() return true end',
    '__MY.Debug_CheatCommand_ToServer = function(self, t) __MY.__sent[#__MY.__sent + 1] = t end',
    '__PLAYER.Controller = __MY',
  ].join('\n'));
  S.must('Net.HandleFromHost(__MY, "PB1\\tINFO\\t")', 'hello');
  let asked = 0;
  for (let i = 0; i < 3; i++) {
    S.must('HV.Disposition("PALIDX")', 'ask' + i);
    asked += Number(S.str('HV.SendAsks()'));
    S.must('__CLOCK = __CLOCK + 11', 'tick' + i);
  }
  expect('a Pal the host never describes is asked 3 times, 10 s apart', String(asked), '3');
  S.must('HV.Disposition("PALIDX")', 'ask4');
  expect('...then not every 10 s any more (run 3: one Pal asked 15 times)', S.str('HV.SendAsks()'), '0');
  S.must('__CLOCK = __CLOCK + 60; HV.Disposition("PALIDX")', 'ask5');
  expect('...only once a minute, in case it comes closer', S.str('HV.SendAsks()'), '1');
}

console.log('\n=== S14. Co-op run 3b: after a dungeon loading screen the guest gets everything again ===');
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("client")',
    'HV = require("HostView"); Net = require("Net"); HV.Init()',
    '__MY = __obj("MyController"); __MY.__sent = {}; __MY.IsLocalPlayerController = function() return true end',
    '__MY.Debug_CheatCommand_ToServer = function(self, t) __MY.__sent[#__MY.__sent + 1] = t end',
    '__PLAYER.Controller = __MY',
  ].join('\n'));
  expect('no reset: nothing to ask for', S.str('HV.SendResync()'), 'false');
  S.must('C.ResetForNewWorld("the player left the world")', 'dungeon');
  // the session asks again after a world change; in game it says "client" again once the player is in
  S.must('Sess.SetModeForTest("client")', 'back');
  expect('after the reset (a dungeon loading screen), the guest asks the host to start over', S.str('HV.SendResync()'), 'true');
  expect('...with a RESYNC', S.str('__MY.__sent[#__MY.__sent]'), 'PB1\tRESYNC');
  expect('...once', S.str('HV.SendResync()'), 'false');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    'HV = require("HostView"); Net = require("Net"); HV.Init()',
    'local realFind = FindAllOf',
    'FindAllOf = function(n) if n == "PalPlayerCharacter" then return { __PLAYER, __G } end return realFind(n) end',
    'require("Personality").ForEachKnownPal = function(fn) end',
  ].join('\n'));
  S.must('HV.SendUpdates()', 'first');
  expect('(setup) the guest got its hello', S.str('#__GC.__sent'), '1');
  S.must('HV.SendUpdates()', 'second');
  expect('(setup) ...only once', S.str('#__GC.__sent'), '1');
  expect('the host takes a RESYNC', S.str('Net.HandleFromPlayer(__GC, "PB1\\tRESYNC")'), 'true');
  S.must('HV.SendUpdates()', 'third');
  expect('...and starts that guest over: a fresh hello', S.str('#__GC.__sent .. ":" .. __GC.__sent[2]'), '2:PB1\tINFO\t');
}

console.log('\n=== S15. A loading screen (a dungeon) leaves followers behind, as abandoned ===');
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("singleplayer")',
    '__TOLD = {}',
    'Cap.NotifyBondLostByName = function(name, kind, fem) __TOLD[#__TOLD + 1] = tostring(name) .. ":" .. tostring(kind) end',
  ].join('\n'));
  S.must('__bond(__PAL)', 'bond');
  expect('(setup) the Pal is following', S.str('C.IsFollowing(__PAL)'), 'true');
  S.must('C.ResetForNewWorld("the player left the world")', 'dungeon');
  expect('a dungeon loading screen says nothing yet (no screen to say it on)', S.str('#__TOLD'), '0');
  expect('once a world is back, the follower is reported abandoned', S.str('T.FlushWorldChangeAbandonments()'), '1');
  expect('...with the left-behind wording', S.str('__TOLD[1]'), 'Lamball:abandoned');
  expect('...once', S.str('T.FlushWorldChangeAbandonments()'), '0');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("singleplayer")',
    '__TOLD = {}',
    'Cap.NotifyBondLostByName = function(name) __TOLD[#__TOLD + 1] = tostring(name) end',
  ].join('\n'));
  S.must('__bond(__PAL)', 'bond');
  S.must('C.ResetForNewWorld("the player confirmed leaving the world (ConfirmReturnTitle)")', 'quit');
  expect('quitting to the title tells the next world nothing', S.str('T.FlushWorldChangeAbandonments() .. ":" .. #__TOLD'), '0:0');
}
{
  const S = newState([
    'Sess = require("Session"); Sess.SetModeForTest("host")',
    '__TOLD = {}',
    'Cap.NotifyBondLostByName = function(name) __TOLD[#__TOLD + 1] = tostring(name) end',
  ].join('\n'));
  S.must('__bond(__PAL, __G)', 'guest bond');
  S.must('C.ResetForNewWorld("the player left the world")', 'reset');
  expect('a guest\'s follower is not reported on the host\'s screen', S.str('T.FlushWorldChangeAbandonments()'), '0');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
