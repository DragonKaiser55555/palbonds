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
//   E. An existing file is read, its own text kept; a broken one is left alone.
//   F. The file is sandboxed: it cannot call anything.
//   G. The modules use the values: keys, feed amounts, join bonus, passive gain,
//      personality weights.
//   H. Settings added by a later version are appended to the player's own file:
//      their values and text survive, the result parses, it happens once, and a
//      file that cannot take the insertion safely is left alone.
//   I. The personality tags start hidden when the file says so.
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
  // Windows: rename FAILS when the destination already exists (this is real -- it is
  // why 1.1.6's first attempt at appending a setting could not write the file).
  'os.rename = function(a, b) a = norm(a); b = norm(b); if __FS[a] == nil or __FS[b] ~= nil then return nil end; __FS[b] = __FS[a]; __FS[a] = nil; return true end',
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
  expect('JoinBonus says 200000 is the game\'s highest rank', S.str('__TEXT:find("200000 is the game\'s highest friendship rank", 1, true) ~= nil'), (v) => v === 'true');
  expect('the chances are explained as weights, with an example', S.str('__TEXT:find("weights, not percentages", 1, true) ~= nil and __TEXT:find("100/260", 1, true) ~= nil'), (v) => v === 'true');
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
  S.must('__M, __P = Set.Validate({ Language = "ES" })', 'lang-ok');
  expect('Language: a listed language, any case', S.str('__M.Language .. "," .. #__P'), (v) => v === 'es,0');
  S.must('__M, __P = Set.Validate({ Language = "klingon" })', 'lang-bad');
  expect('Language: anything else -> auto, reported', S.str('__M.Language .. "," .. #__P'), (v) => v === 'auto,1');
  expect('Language defaults to auto', S.str('select(1, Set.Validate({})).Language'), (v) => v === 'auto');
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
  expect('the player\'s own text is kept as it was', S.str('tostring(__FS[SHARED]:find("return { Pet = 80, KeyPlay = \\"G\\", JoinBonus = 999999", 1, true) ~= nil)'), (v) => v === 'true');
  S.must('Set.Load()', 'reload');
  expect('...and re-reads to the same values', S.str('Set.Get("Pet") .. "," .. Set.Get("KeyPlay")'), (v) => v === '80,G');
  S.must('__FS[SHARED] = "return { Pet = 80,,, "; __PRINTS = {}; Set.Load()', 'broken');
  S.must('__WRITES = 0; Set.Load()', 'broken-load');
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

console.log('\n=== H. Settings added by a later version ===');
{
  // A file written by an older version: every setting of its day, none of the new one.
  const OLD = [
    '-- PalBonds settings',
    'return {',
    '    -- Petting a wild Pal.',
    '    Pet = 80,',
    '    Play = 50, FeedBase = 50, FeedBonusCommon = 10, FeedBonusUncommon = 20, FeedBonusRare = 30,',
    '    FeedBonusEpic = 40, FeedBonusLegendary = 50, KinshipPeachLesser = 250, KinshipPeach = 500,',
    '    PassivePerTick = 2, JoinBonus = 50000,',
    '    ChanceNormal = 35, ChanceCurious = 30, ChanceTimid = 10, ChanceAloof = 10,',
    '    ChanceGrumpy = 5, ChanceHostile = 5, ChanceFeral = 5,',
    '    Language = "es",',
    '    KeyPlay = "G", KeyTags = "F9", KeyPassiveGain = "F10",',
    '}',
    '',
  ].join('\n');
  const S = newState(null, '__OLD = ' + JSON.stringify(OLD) + '; __FS[SHARED] = __OLD; Set = require("Settings")');
  expect('the missing setting is added', S.str('tostring(__FS[SHARED]:find("ShowPersonalityTags = 1,", 1, true) ~= nil)'), (v) => v === 'true');
  expect('...with its comment', S.str('tostring(__FS[SHARED]:find("0 starts with them hidden", 1, true) ~= nil)'), (v) => v === 'true');
  expect('...under a heading saying where it came from', S.str('tostring(__FS[SHARED]:find("ADDED BY A NEWER PALBONDS", 1, true) ~= nil)'), (v) => v === 'true');
  expect('the player\'s file is kept, not rewritten', S.str('tostring(__FS[SHARED]:sub(1, #__OLD:gsub("%s*$", "") - 1) == __OLD:gsub("%s*$", ""):sub(1, -2))'), (v) => v === 'true');
  S.must('Set.Load()', 'reload');
  expect('their own values survive', S.str('Set.Get("Pet") .. "," .. Set.Get("KeyPlay") .. "," .. Set.Get("Language")'), (v) => v === '80,G,es');
  expect('...and the new setting reads as its default', S.str('Set.Get("ShowPersonalityTags")'), (v) => v === '1');
  expect('no problems reported for it', S.str('#select(3, Set.Status())'), (v) => v === '0');
  // The message lists every setting that was missing, so it no longer starts
  // with this one -- what matters is that it is named.
  expect('the console says what was added',
    S.str('tostring(__said("added ") and __said("ShowPersonalityTags"))'), (v) => v === 'true');
  S.must('__WRITES = 0; Set.Load()', 'again');
  expect('a second launch adds nothing and writes nothing', S.str('__WRITES .. "," .. select(2, __FS[SHARED]:gsub("ShowPersonalityTags", ""))'), (v) => v === '0,1');
  expect('no temporary file left behind', S.str('tostring(__FS[SHARED .. ".tmp"] == nil and __FS[SHARED .. ".bak"] == nil)'), (v) => v === 'true');
}
{
  // The file cannot be replaced (read-only folder, antivirus, whatever): the
  // player's own file must survive untouched and nothing may be left behind.
  const S = newState(null, '__FS[SHARED] = "return { Pet = 80 }"; __RENAME = os.rename; os.rename = function() return nil end; Set = require("Settings")');
  expect('a failed write leaves the file exactly as it was', S.str('__FS[SHARED]'), (v) => v === 'return { Pet = 80 }');
  expect('...with no leftovers', S.str('tostring(__FS[SHARED .. ".tmp"] == nil and __FS[SHARED .. ".bak"] == nil)'), (v) => v === 'true');
  expect('...the values still load', S.str('Set.Get("Pet") .. "," .. Set.Get("ShowPersonalityTags")'), (v) => v === '80,1');
  expect('...and the console says so', S.str('tostring(__said("could not write"))'), (v) => v === 'true');
}
{
  // The awkward shapes: no trailing comma, and a file that is one line.
  const S = newState(null, '__FS[SHARED] = "return { Pet = 80 }"; Set = require("Settings")');
  S.must('Set.Load()', 'reload');
  expect('a last value with no comma still parses afterwards', S.str('select(1, Set.Status()) .. "," .. Set.Get("Pet") .. "," .. Set.Get("ShowPersonalityTags")'), (v) => v === 'loaded,80,1');
  S.must('__FS[SHARED] = "return {}"; Set.Load()', 'empty');
  expect('an empty table takes every setting', S.str('select(2, __FS[SHARED]:gsub("=", "")) .. "," .. Set.Get("Pet")'), (v) => Number(v.split(',')[0]) >= 23 && v.split(',')[1] === '50');
}
{
  // The guard: nothing is written unless the result reads back correctly.
  const S = newState(null, 'Set = require("Settings")');
  expect('a table with no closing brace is refused', S.str('tostring(Set.TextWithMissingKeys("return ", { "ShowPersonalityTags" }))'), (v) => v === 'nil');
  expect('nothing missing -> nothing to write', S.str('tostring(Set.TextWithMissingKeys("return { Pet = 80 }", {}))'), (v) => v === 'nil');
  expect('the check accepts a good insertion', S.str('tostring(Set.AppendedTextIsGood(Set.TextWithMissingKeys("return { Pet = 80, }", { "ShowPersonalityTags" }), { Pet = 80 }, { "ShowPersonalityTags" }))'), (v) => v === 'true');
  expect('...refuses one that does not parse', S.str('tostring(Set.AppendedTextIsGood("return { Pet = 80 ShowPersonalityTags = 1 }", { Pet = 80 }, { "ShowPersonalityTags" }))'), (v) => v === 'false');
  expect('...refuses one that lost the player\'s value', S.str('tostring(Set.AppendedTextIsGood("return { Pet = 50, ShowPersonalityTags = 1 }", { Pet = 80 }, { "ShowPersonalityTags" }))'), (v) => v === 'false');
  expect('...refuses one where the new setting is not at its default', S.str('tostring(Set.AppendedTextIsGood("return { Pet = 80, ShowPersonalityTags = 0 }", { Pet = 80 }, { "ShowPersonalityTags" }))'), (v) => v === 'false');
  expect('...refuses a file that can run code', S.str('tostring(Set.AppendedTextIsGood("os.time() return { Pet = 80, ShowPersonalityTags = 1 }", { Pet = 80 }, { "ShowPersonalityTags" }))'), (v) => v === 'false');
  expect('a fresh default file has the new setting in the MODULES section', S.str('tostring(Set.DefaultFileText():find("===== MODULES =====", 1, true) ~= nil and Set.DefaultFileText():find("ShowPersonalityTags = 1,", 1, true) ~= nil)'), (v) => v === 'true');
  expect('0 and 1 are accepted, 2 is not', S.str('select(1, Set.Validate({ ShowPersonalityTags = 0 })).ShowPersonalityTags .. "," .. select(1, Set.Validate({ ShowPersonalityTags = 2 })).ShowPersonalityTags'), (v) => v === '0,1');
}

console.log('\n=== I. The tags start as the file says ===');
{
  const src = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('Indicator starts the tags from the setting', String(/local personalityLabelsVisible = \(require\("Settings"\)\.Get\("ShowPersonalityTags"\) ~= 0\)/.test(src)), (v) => v === 'true');
  const S = newState('prelude_323.lua', '__FS[SHARED] = "return { ShowPersonalityTags = 0 }"; I = require("Indicator")');
  expect('with 0 in the file the tags start hidden', S.str('tostring(I.TogglePersonalityLabels())'), (v) => v === 'true');
  const S2 = newState('prelude_323.lua', '__FS[SHARED] = "return { ShowPersonalityTags = 1 }"; I = require("Indicator")');
  expect('with 1 in the file they start shown', S2.str('tostring(I.TogglePersonalityLabels())'), (v) => v === 'false');
}

console.log('\n=== J. Changing a setting while the game is running (2026-09-25) ===');
{
  // The in-game screen writes through Settings.Set. It has to validate exactly
  // the way the file does, or the screen could put a value in memory that the
  // file would have refused -- and then the two disagree about what the setting
  // even is.
  const S = newState(null, '__FS[SHARED] = "return { Pet = 50 }"; Set = require("Settings")');
  expect('a value applies immediately', S.str('tostring(Set.Set("Pet", 90)) .. "," .. Set.Get("Pet")'), (v) => v === '90,90');
  expect('out of range is refused, with a reason', S.str('(function() local v, why = Set.Set("Pet", 999999) return tostring(v) .. "|" .. tostring(why) end)()'),
    (v) => v.startsWith('nil|must be between'));
  expect('...and the old value stands', S.str('Set.Get("Pet")'), (v) => v === '90');
  expect('a fraction is refused', S.str('tostring(Set.Set("Pet", 1.5))'), (v) => v === 'nil');
  expect('a string where a number belongs is refused', S.str('tostring(Set.Set("Pet", "lots"))'), (v) => v === 'nil');
  expect('a key that is not ours is refused', S.str('tostring(Set.Set("Nonsense", 1))'), (v) => v === 'nil');
  expect('a language is lowercased like the file path does', S.str('tostring(Set.Set("Language", "ES")) .. "," .. Set.Get("Language")'), (v) => v === 'es,es');
  expect('a language we do not have is refused', S.str('tostring(Set.Set("Language", "kl"))'), (v) => v === 'nil');
  expect('a key name is upper-cased', S.str('tostring(Set.Set("KeyPlay", "g")) .. "," .. Set.Get("KeyPlay")'), (v) => v === 'G,G');
  expect('a key UE4SS does not know is refused', S.str('tostring(Set.Set("KeyPlay", "SPOON"))'), (v) => v === 'nil');
}
{
  // Two rules the FILE never needed, because a file is validated as a whole
  // while the screen arrives one value at a time.
  const S = newState(null, 'Set = require("Settings")');
  S.must('for _, k in ipairs({ "ChanceCurious", "ChanceTimid", "ChanceAloof", "ChanceGrumpy", "ChanceHostile", "ChanceFeral" }) do Set.Set(k, 0) end', 'zero');
  expect('the chances can all be zeroed but one', S.str('Set.Get("ChanceCurious") .. "," .. Set.Get("ChanceNormal")'), (v) => v === '0,35');
  expect('the LAST one is refused rather than emptying the roll',
    S.str('(function() local v, why = Set.Set("ChanceNormal", 0) return tostring(v) .. "|" .. tostring(why) end)()'),
    (v) => v === 'nil|at least one personality needs a chance above 0');
  expect('...so the roll always has something to pick', S.str('Set.Get("ChanceNormal")'), (v) => v === '35');
  expect('two actions cannot share a key',
    S.str('(function() local v, why = Set.Set("KeyPlay", "F9") return tostring(v) .. "|" .. tostring(why) end)()'),
    (v) => v === 'nil|that key is already used by KeyTags');
  expect('...but moving one out of the way first works',
    S.str('tostring(Set.Set("KeyTags", "F7")) .. "," .. tostring(Set.Set("KeyPlay", "F9"))'), (v) => v === 'F7,F9');
}
{
  // Listeners: every module refreshes its own locals from one.
  const S = newState(null, 'Set = require("Settings"); __SEEN = {}');
  S.must('Set.OnChange(function(k, v) __SEEN[#__SEEN + 1] = tostring(k) .. "=" .. tostring(v) end)', 'listen');
  S.must('Set.OnChange(function() error("this listener is broken") end)', 'broken');
  S.must('Set.OnChange(function(k) __LAST = k end)', 'third');
  S.must('Set.Set("Pet", 77)', 'set');
  expect('a listener is told what changed', S.str('__SEEN[1]'), (v) => v === 'Pet=77');
  expect('a listener that throws does not stop the others', S.str('tostring(__LAST)'), (v) => v === 'Pet');
  expect('...nor the change itself', S.str('Set.Get("Pet")'), (v) => v === '77');
  S.must('__SEEN = {}; Set.Set("Pet", 77)', 'same');
  expect('setting the same value again tells nobody', S.str('#__SEEN'), (v) => v === '0');
}
{
  // A slider drags through dozens of values; none of them is a disk write.
  const S = newState(null, '__FS[SHARED] = "return { Pet = 50 }"; Set = require("Settings"); __WRITES = 0');
  S.must('for i = 1, 20 do Set.Set("Pet", i) end', 'drag');
  expect('nothing is written while the value is changing', S.str('__WRITES'), (v) => v === '0');
  expect('the file still says what it said', S.str('tostring(__FS[SHARED]:find("Pet = 50", 1, true) ~= nil)'), (v) => v === 'true');
  expect('there is something to save', S.str('tostring(Set.IsDirty())'), (v) => v === 'true');
  expect('Flush saves it', S.str('tostring(Set.Flush())'), (v) => v === 'true');
  expect('...in place, keeping the file\'s own shape', S.str('tostring(__FS[SHARED]:find("Pet = 20", 1, true) ~= nil and __FS[SHARED]:find("Pet = 50", 1, true) == nil)'), (v) => v === 'true');
  expect('...once', S.str('__WRITES'), (v) => v === '1');
  expect('nothing is left to save', S.str('tostring(Set.IsDirty())'), (v) => v === 'false');
  S.must('__WRITES = 0; Set.Flush()', 'again');
  expect('flushing with nothing changed writes nothing', S.str('__WRITES'), (v) => v === '0');
  expect('no temporary file left behind', S.str('tostring(__FS[SHARED .. ".tmp"] == nil)'), (v) => v === 'true');
}
{
  // THE PLAYER'S FILE IS THEIRS. An in-place save must not reformat it, reorder
  // it, or lose a comment -- the same promise the append path makes.
  const FILE = [
    '-- my own notes at the top',
    'return {',
    '    -- ===== TRUST POINTS =====',
    '    Pet = 50,        -- I like this one low',
    '    Play = 50,',
    '    Language = "auto",',
    '    KeyPlay = "F8",',
    '}',
    '',
  ].join('\n');
  const S = newState(null, '__FS[SHARED] = ' + JSON.stringify(FILE) + '; Set = require("Settings")');
  S.must('Set.Set("Pet", 120); Set.Set("Language", "pt"); Set.Set("KeyPlay", "G"); Set.Flush()', 'save');
  expect('the number changed', S.str('tostring(__FS[SHARED]:find("Pet = 120,", 1, true) ~= nil)'), (v) => v === 'true');
  expect('the comment after it survived', S.str('tostring(__FS[SHARED]:find("Pet = 120,        -- I like this one low", 1, true) ~= nil)'), (v) => v === 'true');
  expect('the player\'s own header survived', S.str('tostring(__FS[SHARED]:find("-- my own notes at the top", 1, true) ~= nil)'), (v) => v === 'true');
  expect('the section comment survived', S.str('tostring(__FS[SHARED]:find("===== TRUST POINTS =====", 1, true) ~= nil)'), (v) => v === 'true');
  expect('a string is written quoted, like the mod writes one', S.str('tostring(__FS[SHARED]:find(\'Language = "pt",\', 1, true) ~= nil)'), (v) => v === 'true');
  expect('...and so is a key name', S.str('tostring(__FS[SHARED]:find(\'KeyPlay = "G",\', 1, true) ~= nil)'), (v) => v === 'true');
  expect('a value nobody touched is untouched', S.str('tostring(__FS[SHARED]:find("Play = 50,", 1, true) ~= nil)'), (v) => v === 'true');
  expect('the file still reads back as the mod reads it',
    S.str('(function() local t = load(__FS[SHARED], "c", "t", {})() return t.Pet .. "," .. t.Language .. "," .. t.KeyPlay end)()'),
    (v) => v === '120,pt,G');
}
{
  // TextWithValues is pure, so the awkward shapes are tested directly rather
  // than through a file.
  const S = newState(null, 'Set = require("Settings")');
  expect('a value on the very first line is reachable',
    S.str('tostring(Set.TextWithValues("return { Pet = 50 }", { Pet = 7 }))'), (v) => v === 'return { Pet = 7 }');
  expect('a mention inside a comment is NOT the setting',
    S.str('Set.TextWithValues("-- Pet = 999 is too much\\nreturn {\\n Pet = 50,\\n}", { Pet = 7 })'),
    (v) => v.indexOf('-- Pet = 999 is too much') === 0 && v.indexOf('Pet = 7,') > 0);
  expect('KinshipPeach does not match KinshipPeachLesser',
    S.str('Set.TextWithValues("return {\\n KinshipPeachLesser = 250,\\n KinshipPeach = 500,\\n}", { KinshipPeach = 1 })'),
    (v) => v.indexOf('KinshipPeachLesser = 250,') > 0 && v.indexOf('KinshipPeach = 1,') > 0);
  expect('a key that is not in the file at all: nothing is written',
    S.str('tostring(Set.TextWithValues("return { Play = 50 }", { Pet = 7 }))'), (v) => v === 'nil');
  expect('a negative number is replaced whole',
    S.str('Set.TextWithValues("return { Pet = -5 }", { Pet = 7 })'), (v) => v === 'return { Pet = 7 }');
  expect('an unterminated string is left alone',
    S.str('tostring(Set.TextWithValues(\'return { Language = "auto\\n }\', { Language = "es" }))'), (v) => v === 'nil');
  // The read-back check is the only thing between a bad edit and a file the mod
  // can no longer read, so it gets its own checks.
  expect('the check accepts a good result',
    S.str('tostring(Set.UpdatedTextIsGood("return { Pet = 7, Play = 50 }", { Pet = 7 }, { Play = 50 }))'), (v) => v === 'true');
  expect('...refuses one where the change did not arrive',
    S.str('tostring(Set.UpdatedTextIsGood("return { Pet = 50 }", { Pet = 7 }, {}))'), (v) => v === 'false');
  expect('...refuses one where something else moved',
    S.str('tostring(Set.UpdatedTextIsGood("return { Pet = 7, Play = 1 }", { Pet = 7 }, { Play = 50 }))'), (v) => v === 'false');
  expect('...refuses one that does not parse',
    S.str('tostring(Set.UpdatedTextIsGood("return { Pet = 7,,, }", { Pet = 7 }, {}))'), (v) => v === 'false');
  expect('...refuses one that can run code',
    S.str('tostring(Set.UpdatedTextIsGood("os.time() return { Pet = 7 }", { Pet = 7 }, {}))'), (v) => v === 'false');
}
{
  // A file the player still has to fix by hand must never be overwritten by a
  // save -- the values stay live for the session instead.
  const S = newState(null, '__FS[SHARED] = "return { Pet = 80,,, "; Set = require("Settings"); __WRITES = 0');
  S.must('Set.Set("Pet", 33)', 'set');
  expect('the value is live anyway', S.str('Set.Get("Pet")'), (v) => v === '33');
  expect('saving is refused', S.str('tostring(Set.Flush())'), (v) => v === 'false');
  expect('...and the broken file is left exactly as it is', S.str('__FS[SHARED]'), (v) => v === 'return { Pet = 80,,, ');
  expect('...with nothing written', S.str('__WRITES'), (v) => v === '0');
  expect('and it does not keep retrying', S.str('tostring(Set.IsDirty())'), (v) => v === 'false');
}

console.log('\n=== K. The modules follow a live change ===');
{
  // Each module refreshes its own locals from a listener, so a change reaches
  // the gameplay without any use site asking Settings at use time.
  const S = newState('prelude_emote.lua', '__FS[SHARED] = "return { FeedBase = 50, KinshipPeach = 500 }"; Set = require("Settings"); I = require("Interaction"); I.Init()');
  expect('a feed is worth the base amount to begin with', S.str('I.FeedGrantAmount("Bread")'), (v) => v === '50');
  S.must('Set.Set("FeedBase", 100)', 'change');
  expect('...and follows the new number at once', S.str('I.FeedGrantAmount("Bread")'), (v) => v === '100');
  expect('a Kinship Peach has its own amount', S.str('I.FeedGrantAmount("AffectionFruit_01")'), (v) => v === '500');
  S.must('Set.Set("KinshipPeach", 111)', 'peach');
  expect('...which follows the screen too', S.str('I.FeedGrantAmount("AffectionFruit_01")'), (v) => v === '111');
}
{
  // The roll function is local and Personality ships no accessor for it (and
  // should not gain one just for a test -- section G takes the same view). What
  // is checked here is the wiring: the weights are rewritten IN PLACE in the
  // table the roll already holds, so a change reaches the roll without it
  // knowing anything about settings. The rule that stops every weight reaching
  // 0 is covered behaviourally in section J.
  const src = fs.readFileSync(path.join(scriptsDir, 'Personality.lua'), 'utf8');
  expect('Personality listens for a chance change',
    String(/SettingsP\.OnChange\(function\(key\)/.test(src)), (v) => v === 'true');
  expect('...and only for those keys',
    String(/if type\(key\) ~= "string" or not key:find\("\^Chance"\) then return end/.test(src)), (v) => v === 'true');
  expect('...rewriting the weights in the table the roll holds',
    String(/for _, entry in ipairs\(PERSONALITY_TIERS\) do[\s\S]{0,200}entry\.weight = SettingsP\.Get\(chanceKey\)/.test(src)), (v) => v === 'true');
  expect('...for every tier the roll can produce',
    String(/normal = "ChanceNormal"[\s\S]{0,300}kill_all = "ChanceFeral"/.test(src)), (v) => v === 'true');
  const S = newState('prelude_person.lua', '__FS[SHARED] = "return { ChanceNormal = 100 }"; Set = require("Settings"); P = require("Personality")');
  expect('(and a live change does not break it)',
    S.str('(function() Set.Set("ChanceCurious", 7) return type(require("Personality")) end)()'), (v) => v === 'table');
}
{
  const S = newState(null, '__FS[SHARED] = "return { ShowPersonalityTags = 1 }"; Set = require("Settings"); I = require("Indicator")');
  // TogglePersonalityLabels returns the state AFTER flipping, so a first call
  // returning false means it was on.
  expect('the tags start shown', S.str('tostring(I.TogglePersonalityLabels())'), (v) => v === 'false');
  // They are hidden now (the toggle flipped them). Setting the file value to 0
  // and back to 1 has to move them, which is what "applies now" means.
  S.must('Set.Set("ShowPersonalityTags", 0)', 'off');
  expect('turning them off applies now, not next launch', S.str('tostring(I.TogglePersonalityLabels())'), (v) => v === 'true');
  S.must('Set.Set("ShowPersonalityTags", 1)', 'on');
  expect('...and turning them back on does too', S.str('tostring(I.TogglePersonalityLabels())'), (v) => v === 'false');
}
{
  // The keys are the hard case: UE4SS cannot unbind, so the OLD key must go
  // inert rather than keep firing.
  const S = newState('prelude_emote.lua', [
    '__FS[SHARED] = \'return { KeyTags = "F9" }\'',
    'Set = require("Settings")',
    '__FIRED = 0',
    'package.loaded["Indicator"] = { TogglePersonalityLabels = function() __FIRED = __FIRED + 1 return false end }',
    'I = require("Interaction"); I.Init()',
  ].join('\n'));
  S.must('__BINDS["KEY_F9"]()', 'f9');
  expect('the configured key works', S.str('__FIRED'), (v) => v === '1');
  S.must('Set.Set("KeyTags", "F7")', 'rebind');
  expect('the new key is bound', S.str('tostring(__BINDS["KEY_F7"] ~= nil)'), (v) => v === 'true');
  S.must('__BINDS["KEY_F7"]()', 'f7');
  expect('...and works', S.str('__FIRED'), (v) => v === '2');
  S.must('__BINDS["KEY_F9"]()', 'oldkey');
  expect('the old key does nothing any more (it cannot be unbound)', S.str('__FIRED'), (v) => v === '2');
  S.must('Set.Set("KeyTags", "F9"); __BINDS["KEY_F9"]()', 'back');
  expect('moving back to it works without binding it twice', S.str('__FIRED'), (v) => v === '3');
  // While the settings screen is waiting for a key, our own keys must not act on
  // the press that is choosing them.
  S.must('package.loaded["Menu"] = { WaitingForKey = function() return true end }', 'waiting');
  S.must('__BINDS["KEY_F9"]()', 'whilewaiting');
  expect('a press being captured does not also do its old job', S.str('__FIRED'), (v) => v === '3');
  S.must('package.loaded["Menu"] = { WaitingForKey = function() return false end }; __BINDS["KEY_F9"]()', 'done');
  expect('...and it works again afterwards', S.str('__FIRED'), (v) => v === '4');
}

console.log('\n=== L. The Modules and Accessibility settings (2026-09-25) ===');
{
  // A setting whose value is one of a named list. Same validation for the file
  // and for the screen, like every other kind.
  const S = newState(null, 'Set = require("Settings")');
  expect('a colour is accepted', S.str('tostring(Set.Set("BarColor", "blue"))'), (v) => v === 'blue');
  expect('...case does not matter', S.str('tostring(Set.Set("BarColor", "RED"))'), (v) => v === 'red');
  expect('a colour we do not have is refused, and says what there is',
    S.str('(function() local v, why = Set.Set("BarColor", "beige") return tostring(v) .. "|" .. tostring(why) end)()'),
    (v) => v.startsWith('nil|must be one of:') && v.indexOf('gold') > 0);
  expect('...and the old value stands', S.str('Set.Get("BarColor")'), (v) => v === 'red');
  expect('a number where a name belongs is refused', S.str('tostring(Set.Set("TagSize", 3))'), (v) => v === 'nil');
  expect('the tag colour can be "same as the name"', S.str('tostring(Set.Set("TagColor", "name"))'), (v) => v === 'name');
  expect('a size is one of four', S.str('tostring(Set.Set("TagSize", "huge")) .. "," .. tostring(Set.Set("TagSize", "enormous"))'),
    (v) => v === 'huge,nil');
  // The file path validates the same way.
  expect('a bad colour in the FILE falls back to the default',
    S.str('select(1, Set.Validate({ BarColor = "beige" })).BarColor'), (v) => v === 'gold');
  expect('...and says so', S.str('tostring(#select(2, Set.Validate({ BarColor = "beige" })) > 0)'), (v) => v === 'true');
  expect('a fresh file writes them quoted',
    S.str('tostring(Set.DefaultFileText():find(\'BarColor = "gold",\', 1, true) ~= nil)'), (v) => v === 'true');
  expect('...under an Accessibility heading',
    S.str('tostring(Set.DefaultFileText():find("===== ACCESSIBILITY =====", 1, true) ~= nil)'), (v) => v === 'true');
  expect('the two switches are 0-or-1 like the tags one',
    S.str('select(1, Set.Validate({ AbandonmentEnabled = 2 })).AbandonmentEnabled .. "," .. select(1, Set.Validate({ BetrayalEnabled = 0 })).BetrayalEnabled'),
    (v) => v === '1,0');
}
{
  // The two endings can each be switched off, and the bond then survives what
  // would have ended it. The decision point is one function, so this checks the
  // gate is inside it and ahead of everything it guards.
  const src = fs.readFileSync(path.join(scriptsDir, 'Trust.lua'), 'utf8');
  const at = src.indexOf('local function on_follower_lost_all_trust');
  const body = src.slice(at, at + 1200);
  expect('the loss path asks whether this ending is switched on',
    String(/if not trigger_enabled\(kindNow\) then/.test(body)), (v) => v === 'true');
  expect('...before it stops the Pal following',
    String(body.indexOf('trigger_enabled') < body.indexOf('Trust.StopFollowing')), (v) => v === 'true');
  expect('...and before it tells the player the bond is gone',
    String(body.indexOf('trigger_enabled') < body.indexOf('Capture.OnTrustLost')), (v) => v === 'true');
  expect('distance reads the abandonment switch and damage the betrayal one',
    String(/AbandonmentEnabled.*BetrayalEnabled/s.test(src)), (v) => v === 'true');
  expect('a switched-off ending floors the points so it cannot fire again next tick',
    String(/st\.points = TRIGGER_OFF_FLOOR/.test(src)), (v) => v === 'true');
}
{
  // BETRAYAL OFF MEANS A HIT COSTS NOTHING. Not a smaller penalty: no points
  // lost, no trust-shaken effect, no ending.
  const WITH = 'return { BetrayalEnabled = 1 }';
  const WITHOUT = 'return { BetrayalEnabled = 0 }';
  const setup = (file) => [
    '__FS[SHARED] = ' + JSON.stringify(file),
    'T = require("Trust"); C = require("Combat"); C.Init(); T.Init()',
    'local cap = require("Capture"); cap.IsAlreadyOwned = function() return false end',
    'cap.HasPermanentlyFled = function() return false end',
    '__SHAKEN = 0; cap.NotifyTrustShaken = function() __SHAKEN = __SHAKEN + 1 end',
    'local param = __obj("Param"); __PAL.CharacterParameterComponent = __obj("Comp")',
    '__PAL.CharacterParameterComponent.GetIndividualParameter = function() return param end',
    '__PAL.CharacterParameterComponent.IsDead = function() return false end',
    '__PAL.CharacterParameterComponent.IsDying = function() return false end',
    'T.AddPoints(__PAL, 400, "x"); T.OnInteractionSucceeded(__PAL); __PUMP(1)',
  ].join('\n');

  const on = newState(null, setup(WITH));
  const before = on.str('T.GetPoints(__PAL)');
  on.must('T.OnFollowerDamaged(__PAL, true)', 'hit');
  expect('with betrayal ON a hit still costs friendship points',
    on.str('tostring(T.GetPoints(__PAL) < ' + before + ')'), (v) => v === 'true');

  const off = newState(null, setup(WITHOUT));
  const kept = off.str('T.GetPoints(__PAL)');
  off.must('T.OnFollowerDamaged(__PAL, true)', 'hit');
  expect('with it OFF the hit costs nothing at all', off.str('T.GetPoints(__PAL)'), (v) => v === kept);
  expect('...and there is no trust-shaken effect', off.str('__SHAKEN'), (v) => v === '0');
  off.must('for i = 1, 5 do T.OnFollowerDamaged(__PAL, true) end', 'more');
  expect('...however many times the player hits it', off.str('T.GetPoints(__PAL)'), (v) => v === kept);
}
{
  // ABANDONMENT OFF ALSO SILENCES THE DESPAWN MESSAGE. Dragón's point: a
  // disabled trigger that still shows its message reads as a broken setting --
  // the player should just assume their Pal despawned.
  const setup = (file) => [
    '__FS[SHARED] = ' + JSON.stringify(file),
    'T = require("Trust")',
    '__TOLD = 0',
    'package.loaded["Capture"] = package.loaded["Capture"] or {}',
    'package.loaded["Capture"].NotifyBondLostByName = function() __TOLD = __TOLD + 1 end',
    'T.NoteWorldChangeAbandonedForTest = nil',
  ].join('\n');

  const on = newState(null, setup('return { AbandonmentEnabled = 1 }'));
  expect('(nothing to report when nothing was left behind)',
    on.str('T.FlushWorldChangeAbandonments()'), (v) => v === '0');

  const off = newState(null, setup('return { AbandonmentEnabled = 0 }'));
  expect('the switch is off', off.str('require("Settings").Get("AbandonmentEnabled")'), (v) => v === '0');
  // The source is what proves the two message sites consult it, since reaching
  // them needs a live world change.
  const src = fs.readFileSync(path.join(scriptsDir, 'Trust.lua'), 'utf8');
  expect('the loading-screen message asks first',
    String(/if not trigger_enabled\("abandoned"\) then[\s\S]{0,300}follower\(s\) were left behind and the player is not told/.test(src)),
    (v) => v === 'true');
  expect('the despawn message asks too',
    String(/if wasBonded and trigger_enabled\("abandoned"\) then/.test(src)), (v) => v === 'true');
  expect('a hit asks before anything it would cost',
    String(/if attackerIsPlayer and not trigger_enabled\("betrayed"\) then return end/.test(src)), (v) => v === 'true');
}
{
  // The appearance settings reach the drawing, and a change redraws what is
  // already on screen rather than only the next Pal.
  const src = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('the bar colour comes from the setting',
    String(/return named_color\(barColorName\) or NAMED_COLORS\.gold/.test(src)), (v) => v === 'true');
  expect('the tag colour is applied over the copied name style',
    String(/local wanted = named_color\(tagColorName\)/.test(src)), (v) => v === 'true');
  expect('"same as the name" means we leave the name colour alone',
    String(/tagColorName = \(tag ~= nil and tag ~= "name"\) and tag or nil/.test(src)), (v) => v === 'true');
  expect('the size is a scale on the name\'s own font, not an absolute',
    String(/font\.Size = math\.max\(6, math\.floor\(base \* tagSizeScale/.test(src)), (v) => v === 'true');
  expect('a change redraws the Pals already on screen',
    String(/Indicator\.RefreshAppearance\(\)/.test(src) && /function Indicator\.RefreshAppearance/.test(src)), (v) => v === 'true');
  const S = newState(null, '__FS[SHARED] = \'return { BarColor = "blue", TagColor = "red", TagSize = "large" }\'; Set = require("Settings"); I = require("Indicator")');
  expect('(Indicator loads with them set, and can redraw)',
    S.str('(function() I.RefreshAppearance() return "ok" end)()'), (v) => v === 'ok');
}

console.log('\n=== M. A personality can be switched off for bonding (2026-09-25) ===');
{
  // Unknown personality means ALLOWED: a Pal that has not rolled one yet must
  // not be refused by a switch that cannot apply to it.
  const S = newState('prelude_person.lua', '__FS[SHARED] = \'return { BondFeral = 0 }\'; T = require("Trust"); P = require("Personality")');
  expect('a Pal with no personality yet may still bond',
    S.str('tostring(T.PersonalityMayBond(__PAL))'), (v) => v === 'true');
  expect('nil is not refused either', S.str('tostring(T.PersonalityMayBond(nil))'), (v) => v === 'true');
}
{
  // With the switch off, that personality earns nothing through ANY path --
  // AddPoints is the funnel every one of them ends in.
  const setup = (file) => [
    '__FS[SHARED] = ' + JSON.stringify(file),
    'T = require("Trust"); P = require("Personality")',
    'local cap = require("Capture"); cap.IsAlreadyOwned = function() return false end',
    'cap.HasPermanentlyFled = function() return false end',
    // Give the Pal a known personality without needing the real roll.
    '__ID = "pal-under-test"',
    'P.GetStableId = function() return __ID end',
    // The switch follows the DISPOSITION, which is what the tag shows -- not the
    // rolled tier, which is "normal" for a Pal whose species is already Feral.
    'P.GetDisposition = function(id) return (id == __ID) and "kill_all" or "normal" end',
  ].join('\n');

  const on = newState('prelude_person.lua', setup('return { BondFeral = 1 }'));
  on.must('T.AddPoints(__PAL, 100, "pet")', 'grant');
  expect('a Feral Pal earns points while its switch is on', on.str('T.GetPoints(__PAL)'), (v) => v === '100');
  expect('...and may bond', on.str('tostring(T.MayBond(__PAL))'), (v) => v === 'true');

  const off = newState('prelude_person.lua', setup('return { BondFeral = 0 }'));
  expect('with the switch off it may not bond', off.str('tostring(T.PersonalityMayBond(__PAL))'), (v) => v === 'false');
  expect('...which is what refuses the interaction before food is spent',
    off.str('tostring(T.MayBond(__PAL))'), (v) => v === 'false');
  off.must('T.AddPoints(__PAL, 100, "pet")', 'grant');
  expect('...and no points reach it by any path', off.str('T.GetPoints(__PAL)'), (v) => v === '0');
  // AddPoints reports a refusal by returning nothing, which is what every
  // caller checks; __said reads the console, and this line goes to the mod log.
  expect('...and the grant reports that it did nothing',
    off.str('tostring(T.AddPoints(__PAL, 100, "pet"))'), (v) => v === 'nil');
  // A personality that is still switched ON is untouched by its neighbour.
  off.must('P.GetDisposition = function() return "normal" end', 'other');
  expect('another personality still bonds normally', off.str('tostring(T.PersonalityMayBond(__PAL))'), (v) => v === 'true');
}
{
  // Every tier the roll can produce has a switch, or one of them would be
  // silently unswitchable.
  const src = fs.readFileSync(path.join(scriptsDir, 'Trust.lua'), 'utf8');
  const psrc = fs.readFileSync(path.join(scriptsDir, 'Personality.lua'), 'utf8');
  const tiers = [...psrc.matchAll(/\{ tier = "([a-z_]+)", weight/g)].map((m) => m[1]);
  expect('(the roll produces seven tiers)', String(tiers.length), (v) => v === '7');
  expect('each one has a bonding switch',
    String(tiers.filter((t) => new RegExp(t + ' = "Bond').test(src)).length), (v) => v === '7');
  const ssrc = fs.readFileSync(path.join(scriptsDir, 'Settings.lua'), 'utf8');
  expect('...and each switch is a real setting',
    String(['BondNormal', 'BondCurious', 'BondTimid', 'BondAloof', 'BondGrumpy', 'BondHostile', 'BondFeral']
      .filter((k) => ssrc.indexOf('key = "' + k + '"') >= 0).length), (v) => v === '7');
  const isrc = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('a Pal that cannot bond gets no bar',
    String(/if hasBonding and Trust\.PersonalityMayBond and not Trust\.PersonalityMayBond\(earlyActor\) then/.test(isrc)),
    (v) => v === 'true');
  expect('...but keeps its tag (the label is not touched by that gate)',
    String(isrc.indexOf('hasBonding = false') > 0 && !/personalityLabelsVisible = false/.test(isrc)), (v) => v === 'true');
}

console.log('\n=== N. Where passive gain starts, and Play immunity (2026-09-25) ===');
{
  // The key still toggles it for the session; this is what it STARTS as, the
  // same shape as ShowPersonalityTags.
  const on = newState(null, '__FS[SHARED] = "return { PassiveGainEnabled = 1 }"; T = require("Trust")');
  expect('with it on, passive gain starts on', on.str('tostring(T.IsPassiveGainEnabled())'), (v) => v === 'true');

  const off = newState(null, '__FS[SHARED] = "return { PassiveGainEnabled = 0 }"; T = require("Trust")');
  expect('with it off, passive gain starts off', off.str('tostring(T.IsPassiveGainEnabled())'), (v) => v === 'false');
  expect('...and the key still turns it on for the session',
    off.str('tostring(T.TogglePassiveFriendshipGain())'), (v) => v === 'true');
  expect('...and off again', off.str('tostring(T.TogglePassiveFriendshipGain())'), (v) => v === 'false');
  // Changing it on the screen applies at once, like every other setting.
  off.must('require("Settings").Set("PassiveGainEnabled", 1)', 'live');
  expect('changing it on the screen applies now', off.str('tostring(T.IsPassiveGainEnabled())'), (v) => v === 'true');
  off.must('require("Settings").Set("PassiveGainEnabled", 0)', 'live2');
  expect('...both ways', off.str('tostring(T.IsPassiveGainEnabled())'), (v) => v === 'false');
  // It is per machine, not per remote player: a guest's own toggle is theirs.
  expect('a remote player is not switched off by this machine\'s setting',
    off.str('tostring(T.IsPassiveGainEnabled("SomeGuest"))'), (v) => v === 'true');
}
{
  // Play does not go through the radial menu, so it needs its own refusal --
  // "immune" has to mean immune, not just "earns nothing".
  const src = fs.readFileSync(path.join(scriptsDir, 'Interaction.lua'), 'utf8');
  const at = src.indexOf('local function do_play()');
  const body = src.slice(at, src.indexOf('local function play_refusal', at) + 1 || at + 4000);
  expect('Play asks whether this personality may bond',
    String(/if Trust\.PersonalityMayBond and not Trust\.PersonalityMayBond\(pal\) then/.test(body)), (v) => v === 'true');
  expect('...before it starts any animation',
    String(body.indexOf('PersonalityMayBond') < body.indexOf('play_refusal(pal')), (v) => v === 'true');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
