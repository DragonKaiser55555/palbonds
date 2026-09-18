// 2026-09-18: the player's settings file (Settings.lua).
//
// fengari has no `io`, so each state gets a small in-memory file system: io.open,
// os.rename, os.remove and loadfile work against __FS, and a folder can be made
// read-only to force the fallback location.
//
//   A. The written default file parses and reproduces every default exactly.
//   B. Validation: bad types, out of range, fractions, unknown names, bad keys,
//      all-zero chances -> defaults, each reported.
//   C. First launch: the file is created in UE4SS's shared folder (atomic write).
//   D. Shared folder not writable: created in our own mod folder instead.
//   E. An existing file is read and never rewritten; a broken one is left alone.
//   F. The file is sandboxed: it cannot call anything.
//   G. The modules use the values: keys, feed amounts, join bonus, passive gain,
//      personality weights.
//
// Usage: node settingstest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node settingstest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');
let failures = 0;

function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

// Lua source of the fake file system. Paths are normalised (a/b/../c -> a/c)
// so the mod's relative paths resolve the way Windows would resolve them.
const FAKE_FS = [
  '__FS = {}; __READONLY = {}; __WRITES = 0',
  'local function norm(p)',
  '  p = tostring(p):gsub("\\\\", "/")',
  '  local out = {}',
  '  for part in p:gmatch("[^/]+") do',
  '    if part == ".." then table.remove(out) elseif part ~= "." then out[#out + 1] = part end',
  '  end',
  '  return (p:sub(1, 1) == "/" and "/" or "") .. table.concat(out, "/")',
  'end',
  '__norm = norm',
  'local function dirof(p) return (norm(p):match("^(.*)/[^/]*$")) or "" end',
  'io = {}',
  'io.open = function(p, mode)',
  '  p = norm(p); mode = mode or "r"',
  '  if mode:sub(1, 1) == "r" then',
  '    local c = __FS[p]; if c == nil then return nil, p .. ": No such file" end',
  '    return { read = function() return c end, close = function() end }',
  '  end',
  '  if __READONLY[dirof(p)] then return nil, p .. ": Permission denied" end',
  '  local buf = {}',
  '  return { write = function(self, s) buf[#buf + 1] = s return self end,',
  '           close = function() __FS[p] = table.concat(buf); __WRITES = __WRITES + 1 end }',
  'end',
  'os.rename = function(a, b) a = norm(a); b = norm(b); if __FS[a] == nil then return nil end; __FS[b] = __FS[a]; __FS[a] = nil; return true end',
  'os.remove = function(a) __FS[norm(a)] = nil return true end',
  'loadfile = function(p, mode, env)',
  '  local c = __FS[norm(p)]; if c == nil then return nil, "cannot open " .. tostring(p) end',
  '  return load(c, "@" .. tostring(p), mode, env)',
  'end',
].join('\n');

const MOD = scriptsDir;                                   // .../Mods/PalBonds/Scripts
const SHARED_FILE = MOD + '/../../shared/PalBonds_settings.lua';
const MODROOT_FILE = MOD + '/../PalBonds_settings.lua';

function newState(prelude, setup) {
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
  must(fs.readFileSync(path.join(__dirname, prelude || 'prelude_323.lua'), 'utf8'), 'prelude');
  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  must('__CLOCK = 1000.0; os.clock = function() return __CLOCK end', 'clock');
  must(FAKE_FS, 'fakefs');
  // A realistic Key table: only real names exist.
  must('Key = {}; for _, n in ipairs({ "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","G","H","J","K","ONE","NUM_ZERO" }) do Key[n] = "KEY_" .. n end', 'keys');
  must('__PRINTS = {}; print = function(s) __PRINTS[#__PRINTS + 1] = tostring(s) end', 'print');
  must('function __said(x) for _, m in ipairs(__PRINTS) do if m:find(x, 1, true) then return true end end return false end', 'said');
  must('SHARED = __norm("' + SHARED_FILE + '"); MODROOT = __norm("' + MODROOT_FILE + '")', 'paths');
  if (setup) must(setup, 'setup');
  return { run, str, must };
}

console.log('\n=== A. The default file ===');
{
  const S = newState(null, 'Set = require("Settings")');
  S.must('__TEXT = Set.DefaultFileText(); __T = load(__TEXT, "d", "t", {})()', 'parse');
  expect('the written file parses to a table', S.str('type(__T)'), (v) => v === 'table');
  expect('...with no problems', S.str('#select(2, Set.Validate(__T))'), (v) => v === '0');
  expect('...and every default', S.str('__T.Pet .. "," .. __T.Play .. "," .. __T.FeedBase .. "," .. __T.FeedBonusLegendary .. "," .. __T.KinshipPeachLesser .. "," .. __T.KinshipPeach .. "," .. __T.PassivePerTick .. "," .. __T.JoinBonus'),
    (v) => v === '50,50,50,50,250,500,2,50000');
  expect('personality chances 35/30/10/10/5/5/5', S.str('__T.ChanceNormal .. "," .. __T.ChanceCurious .. "," .. __T.ChanceTimid .. "," .. __T.ChanceAloof .. "," .. __T.ChanceGrumpy .. "," .. __T.ChanceHostile .. "," .. __T.ChanceFeral'),
    (v) => v === '35,30,10,10,5,5,5');
  expect('keys F8/F9/F10', S.str('__T.KeyPlay .. "," .. __T.KeyTags .. "," .. __T.KeyPassiveGain'), (v) => v === 'F8,F9,F10');
  expect('every value has a comment above it', S.str('select(2, __TEXT:gsub("\\n    %-%- ", ""))'), (v) => Number(v) >= 23);
}

console.log('\n=== B. Validation ===');
{
  const S = newState(null, 'Set = require("Settings")');
  S.must('__M, __P = Set.Validate({ Pet = "lots", Play = -5, FeedBase = 12.5, JoinBonus = 250000, KinshipPeach = 900, Petting = 3, KeyPlay = "g", KeyTags = "NOPE", KeyPassiveGain = 10 })', 'bad');
  expect('wrong type -> default', S.str('__M.Pet'), (v) => v === '50');
  expect('below the minimum -> default', S.str('__M.Play'), (v) => v === '50');
  expect('a fraction -> default', S.str('__M.FeedBase'), (v) => v === '50');
  expect('JoinBonus above 200000 -> default', S.str('__M.JoinBonus'), (v) => v === '50000');
  expect('a good value is kept', S.str('__M.KinshipPeach'), (v) => v === '900');
  expect('a key name in lower case is accepted', S.str('__M.KeyPlay'), (v) => v === 'G');
  expect('an unknown key name -> default', S.str('__M.KeyTags'), (v) => v === 'F9');
  expect('a key given as a number -> default', S.str('__M.KeyPassiveGain'), (v) => v === 'F10');
  expect('every problem is reported, including the typo', S.str('#__P'), (v) => v === '7');
  expect('the typo is named', S.str('table.concat(__P, " | "):find("Petting", 1, true) ~= nil'), (v) => v === 'true');
  S.must('__M, __P = Set.Validate({ ChanceNormal = 0, ChanceCurious = 0, ChanceTimid = 0, ChanceAloof = 0, ChanceGrumpy = 0, ChanceHostile = 0, ChanceFeral = 0 })', 'zero');
  expect('every chance 0 -> the default chances', S.str('__M.ChanceNormal .. "," .. __M.ChanceFeral .. "," .. #__P'), (v) => v === '35,5,1');
  S.must('__M, __P = Set.Validate({ ChanceFeral = 0, JoinBonus = 0, PassivePerTick = 0 })', 'zeros-ok');
  expect('0 is a legal value where it means "off"', S.str('__M.ChanceFeral .. "," .. __M.JoinBonus .. "," .. __M.PassivePerTick .. "," .. #__P'), (v) => v === '0,0,0,0');
}

console.log('\n=== C. First launch: created in the shared folder ===');
{
  const S = newState(null, 'Set = require("Settings")');
  expect('status: created', S.str('select(1, Set.Status())'), (v) => v === 'created');
  expect('...in UE4SS\'s shared folder', S.str('__FS[SHARED] ~= nil and __FS[MODROOT] == nil'), (v) => v === 'true');
  expect('...with the default text', S.str('__FS[SHARED] == Set.DefaultFileText()'), (v) => v === 'true');
  expect('no temporary file left behind', S.str('__FS[SHARED .. ".tmp"] == nil'), (v) => v === 'true');
  expect('the console says where', S.str('__said("created")'), (v) => v === 'true');
  expect('...as a clean path, no "Scripts/../.." in it', S.str('__PRINTS[1]'), (v) => v.indexOf('Scripts/..') === -1 && v.indexOf('/shared/PalBonds_settings.lua') !== -1);
  expect('...said once', S.str('#__PRINTS'), (v) => v === '1');
  expect('defaults in use', S.str('Set.Get("Pet") .. "," .. Set.Get("KeyPlay")'), (v) => v === '50,F8');
}

console.log('\n=== D. Shared folder not writable: our own mod folder ===');
{
  const S = newState(null, '__READONLY[SHARED:match("^(.*)/[^/]*$")] = true; Set = require("Settings")');
  expect('created in the mod folder instead', S.str('__FS[SHARED] == nil and __FS[MODROOT] ~= nil'), (v) => v === 'true');
  S.must('__READONLY[MODROOT:match("^(.*)/[^/]*$")] = true; __FS[MODROOT] = nil; Set.Load()', 'neither');
  expect('neither writable: defaults, and the console says so', S.str('Set.Get("Pet") .. "," .. tostring(__said("could not create"))'), (v) => v === '50,true');
}

console.log('\n=== E. An existing file ===');
{
  const S = newState(null, '__FS[SHARED] = "return { Pet = 80, KeyPlay = \\"G\\", JoinBonus = 999999 }"; Set = require("Settings")');
  expect('read', S.str('select(1, Set.Status()) .. "," .. Set.Get("Pet") .. "," .. Set.Get("KeyPlay")'), (v) => v === 'loaded,80,G');
  expect('a bad value falls back and is reported on the console', S.str('Set.Get("JoinBonus") .. "," .. tostring(__said("JoinBonus"))'), (v) => v === '50000,true');
  expect('missing settings use their defaults', S.str('Set.Get("Play") .. "," .. Set.Get("ChanceNormal")'), (v) => v === '50,35');
  expect('the file is never rewritten', S.str('__WRITES .. "," .. tostring(__FS[SHARED]:find("999999", 1, true) ~= nil)'), (v) => v === '0,true');
  S.must('__FS[SHARED] = "return { Pet = 80,,, "; __PRINTS = {}; Set.Load()', 'broken');
  expect('a file that does not parse: every default, file left as it is', S.str('select(1, Set.Status()) .. "," .. Set.Get("Pet") .. "," .. __WRITES .. "," .. tostring(__FS[SHARED] == "return { Pet = 80,,, ")'),
    (v) => v === 'unreadable,50,0,true');
  expect('...and the console says it can be fixed', S.str('__said("left as it is")'), (v) => v === 'true');
  S.must('__FS[MODROOT] = "return { Pet = 5 }"; __FS[SHARED] = "return { Pet = 7 }"; Set.Load()', 'both');
  expect('a file in both places: the shared one wins', S.str('Set.Get("Pet")'), (v) => v === '7');
}

console.log('\n=== F. The file cannot run anything ===');
{
  const S = newState(null, '__FS[SHARED] = "__PWNED = true; return { Pet = 60 }"; Set = require("Settings")');
  expect('globals written by the file do not leak out', S.str('tostring(__PWNED)'), (v) => v === 'nil');
  S.must('__FS[SHARED] = "os.execute(\\"x\\"); return { Pet = 60 }"; Set.Load()', 'call');
  expect('a file that calls a function is rejected, defaults apply', S.str('select(1, Set.Status()) .. "," .. Set.Get("Pet")'), (v) => v === 'unreadable,50');
}

console.log('\n=== G. The modules use the values ===');
{
  const USER = 'return { Pet = 70, Play = 30, FeedBase = 40, KinshipPeachLesser = 111, KinshipPeach = 222, PassivePerTick = 7, JoinBonus = 12345, ' +
               'KeyPlay = "G", KeyTags = "H", KeyPassiveGain = "J", ChanceNormal = 0, ChanceCurious = 0, ChanceTimid = 0, ChanceAloof = 0, ChanceGrumpy = 0, ChanceHostile = 1, ChanceFeral = 0 }';
  const S = newState('prelude_emote.lua', '__FS[SHARED] = ' + JSON.stringify(USER) + '; I = require("Interaction"); I.Init()');
  expect('the three keys are bound from the file', S.str('tostring(__BINDS["KEY_G"] ~= nil) .. "," .. tostring(__BINDS["KEY_H"] ~= nil) .. "," .. tostring(__BINDS["KEY_J"] ~= nil)'), (v) => v === 'true,true,true');
  expect('...and not the old ones', S.str('tostring(__BINDS["KEY_F8"]) .. "," .. tostring(__BINDS["KEY_F9"]) .. "," .. tostring(__BINDS["KEY_F10"])'), (v) => v === 'nil,nil,nil');
  // AffectionFruit_02 is the Lesser Kinship Peach, _01 the full one (Interaction.FeedGrantAmount).
  expect('Kinship Peaches use the file', S.str('select(1, I.FeedGrantAmount("AffectionFruit_02")) .. "," .. select(1, I.FeedGrantAmount("AffectionFruit_01"))'), (v) => v === '111,222');
  expect('food with unreadable rarity: the file\'s FeedBase', S.str('select(1, I.FeedGrantAmount("Berries"))'), (v) => v === '40');

  const src = (f) => fs.readFileSync(path.join(scriptsDir, f), 'utf8');
  expect('Capture reads JoinBonus', String(/JOIN_FRIENDSHIP_POINT_GRANT = require\("Settings"\)\.Get\("JoinBonus"\)/.test(src('Capture.lua'))), (v) => v === 'true');
  expect('Trust reads PassivePerTick', String(/REAL_PASSIVE_FRIENDSHIP_PER_TICK = require\("Settings"\)\.Get\("PassivePerTick"\)/.test(src('Trust.lua'))), (v) => v === 'true');
  expect('Interaction reads Pet and Play', String(/PET_FRIENDSHIP_GAIN = Settings\.Get\("Pet"\)/.test(src('Interaction.lua')) && /PLAY_FRIENDSHIP_GAIN = Settings\.Get\("Play"\)/.test(src('Interaction.lua'))), (v) => v === 'true');
}
{
  // Real values end to end: join bonus and passive gain through the real modules.
  const USER = 'return { JoinBonus = 12345, PassivePerTick = 7, ChanceNormal = 0, ChanceCurious = 0, ChanceTimid = 0, ChanceAloof = 0, ChanceGrumpy = 0, ChanceHostile = 1, ChanceFeral = 0 }';
  const S = newState(null, '__FS[SHARED] = ' + JSON.stringify(USER) + '; T = require("Trust"); C = require("Combat"); C.Init(); T.Init()');
  S.must([
    'local cap = require("Capture"); cap.IsAlreadyOwned = function() return false end; cap.HasPermanentlyFled = function() return false end',
    'local param = __obj("Param"); __PAL.CharacterParameterComponent = __obj("Comp")',
    '__PAL.CharacterParameterComponent.GetIndividualParameter = function() return param end',
    '__PAL.CharacterParameterComponent.IsDead = function() return false end; __PAL.CharacterParameterComponent.IsDying = function() return false end',
    'T.AddPoints(__PAL, 250, "x"); T.OnInteractionSucceeded(__PAL); __PUMP(1)',
  ].join('\n'), 'follow');
  expect('passive gain uses the file (+7 per tick)', S.str('T.GetPoints(__PAL)'), (v) => v === '257');
}
{
  // Personality weights: every Pal rolls the only tier with weight > 0.
  const USER = 'return { ChanceNormal = 0, ChanceCurious = 0, ChanceTimid = 0, ChanceAloof = 0, ChanceGrumpy = 0, ChanceHostile = 1, ChanceFeral = 0 }';
  const S = newState('prelude_person.lua', '__FS[SHARED] = ' + JSON.stringify(USER));
  const src = fs.readFileSync(path.join(scriptsDir, 'Personality.lua'), 'utf8');
  expect('Personality weights come from the file', String(/weight = SettingsP\.Get\("ChanceHostile"\)/.test(src) && /weight = SettingsP\.Get\("ChanceFeral"\)/.test(src)), (v) => v === 'true');
  expect('(Personality loads with a settings file present)', S.str('type(require("Personality"))'), (v) => v === 'table');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
