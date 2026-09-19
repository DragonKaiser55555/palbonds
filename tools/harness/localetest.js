// 2026-09-18: translations (Locale.lua).
//
//   A. Engine culture -> language: every code Palworld's 17 languages can
//      report, including regional forms; anything unknown is English.
//   B. Completeness: every string exists in all 16 languages, keeps {name}
//      where English has it, is not empty, and avoids "|" (the game's font
//      draws it as a quote mark).
//   C. The Language setting: "auto" follows the engine, a forced language wins,
//      a failing engine call means English, and the engine is asked at most
//      once every 10 s.
//   D. {name} filling, including a name with a "%" in it.
//   E. The modules show translated text: tags (Indicator) and the F9 toast.
//
// Usage: node localetest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node localetest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');
let failures = 0;

function expect(label, actual, pred) {
  const ok = pred(actual);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

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
  // The engine's language, controllable: __ENGINE_LANG (nil = the call fails).
  must([
    '__ENGINE_LANG = "en"; __ENGINE_CALLS = 0',
    'local realSFO = StaticFindObject',
    'StaticFindObject = function(p)',
    '  if p == "/Script/Engine.Default__KismetInternationalizationLibrary" then',
    '    return { IsValid = function() return true end, GetCurrentLanguage = function()',
    '      __ENGINE_CALLS = __ENGINE_CALLS + 1',
    '      if __ENGINE_LANG == nil then error("no engine") end',
    '      return { ToString = function() return __ENGINE_LANG end } end }',
    '  end',
    '  return realSFO(p)',
    'end',
    '__SETTING = "auto"',
    'package.loaded["Settings"] = { Get = function(k) if k == "Language" then return __SETTING end return nil end }',
  ].join('\n'), 'engine');
  if (setup) must(setup, 'setup');
  return { run, str, must };
}

console.log('\n=== A. Engine culture -> language ===');
{
  const S = newState(null, 'Loc = require("Locale")');
  const cases = [
    ['en', 'en'], ['en-US', 'en'], ['es', 'es'], ['es-MX', 'es'], ['es-ES', 'es'], ['es-419', 'es'],
    ['pt-BR', 'pt'], ['pt-PT', 'pt'], ['fr', 'fr'], ['fr-FR', 'fr'], ['de', 'de'], ['it', 'it'], ['pl', 'pl'],
    ['ru', 'ru'], ['tr', 'tr'], ['vi', 'vi'], ['th', 'th'], ['id', 'id'], ['ja', 'ja'], ['ja-JP', 'ja'], ['ko', 'ko'], ['ko-KR', 'ko'],
    ['zh-Hans', 'zh-hans'], ['zh-CN', 'zh-hans'], ['zh', 'zh-hans'], ['zh-Hant', 'zh-hant'], ['zh-TW', 'zh-hant'], ['zh-HK', 'zh-hant'],
    ['xx-YY', 'en'], ['', 'en'],
  ];
  const got = cases.map(([c]) => S.str('Loc.FromCulture("' + c + '")'));
  const wrong = cases.filter(([c, want], i) => got[i] !== want).map(([c, want], i) => c + '->' + got[cases.findIndex((x) => x[0] === c)] + ' (want ' + want + ')');
  expect('all ' + cases.length + ' culture codes map correctly', wrong.join(', ') || 'ok', (v) => v === 'ok');
  expect('nil -> English', S.str('Loc.FromCulture(nil)'), (v) => v === 'en');
}

console.log('\n=== B. Completeness ===');
{
  const S = newState(null, 'Loc = require("Locale")');
  S.must([
    '__MISSING, __NONAME, __PIPE, __KEYS = {}, {}, {}, 0',
    'for key, entry in pairs(Loc.STRINGS) do',
    '  __KEYS = __KEYS + 1',
    '  for _, lang in ipairs(Loc.LANGUAGES) do',
    '    local forms = entry[lang]',
    '    if type(forms) == "table" then',
    '      __GENDERED = (__GENDERED or 0) + 1',
    '      if type(forms.m) ~= "string" or type(forms.f) ~= "string" or forms.m == forms.f then __BADPAIR = (__BADPAIR or "") .. key .. "/" .. lang .. " " end',
    '    else forms = { forms } end',
    '    for _, t in pairs(forms) do',
    '    if type(t) ~= "string" or t == "" then __MISSING[#__MISSING + 1] = key .. "/" .. lang',
    '    else',
    '      if entry.en:find("{name}", 1, true) and not t:find("{name}", 1, true) then __NONAME[#__NONAME + 1] = key .. "/" .. lang end',
    '      if t:find("|", 1, true) then __PIPE[#__PIPE + 1] = key .. "/" .. lang end',
    '    end',
    '    end',
    '  end',
    'end',
  ].join('\n'), 'scan');
  expect('24 strings', S.str('__KEYS'), (v) => v === '24');
  expect('16 language sets: English + 15 (one Spanish for Spain and Latin America)', S.str('#Loc.LANGUAGES'), (v) => v === '16');
  expect('no string missing in any language', S.str('table.concat(__MISSING, " ")'), (v) => v === '');
  expect('{name} kept everywhere English has it', S.str('table.concat(__NONAME, " ")'), (v) => v === '');
  expect('no "|" anywhere', S.str('table.concat(__PIPE, " ")'), (v) => v === '');
  expect('every gendered entry has a masculine and a different feminine form', S.str('tostring(__BADPAIR)'), (v) => v === 'nil');
  expect('gendered forms exist (es, pt, fr, it, pl, ru)', S.str('__GENDERED'), (v) => Number(v) >= 60);
  expect('English, German and the Asian languages have no gendered forms', S.str('(function() for _, e in pairs(Loc.STRINGS) do for _, l in ipairs({ "en", "de", "tr", "vi", "th", "id", "ja", "ko", "zh-hans", "zh-hant" }) do if type(e[l]) == "table" then return l end end end return "none" end)()'), (v) => v === 'none');
  const src = fs.readFileSync(path.join(scriptsDir, 'Locale.lua'), 'utf8');
  expect('Spanish has no voseo forms', String(/\b(vos|tenés|podés|querés|sos|confiás)\b/i.test(src)), (v) => v === 'false');
}

console.log('\n=== C. Which language ===');
{
  const S = newState(null, 'Loc = require("Locale")');
  expect('auto, engine says en', S.str('Loc.T("tag_curious")'), (v) => v === 'Curious');
  S.must('__ENGINE_LANG = "ja"; __CLOCK = __CLOCK + 11', 'ja');
  expect('auto, engine switched to ja (after the refresh window)', S.str('Loc.T("tag_curious")'), (v) => v === '好奇心旺盛');
  S.must('__ENGINE_LANG = "es-MX"', 'es-soon');
  expect('...not re-read inside the window', S.str('Loc.T("tag_curious")'), (v) => v === '好奇心旺盛');
  S.must('__N = __ENGINE_CALLS; for i = 1, 50 do Loc.T("tag_normal") end', 'many');
  expect('50 lookups inside the window: no engine call', S.str('__ENGINE_CALLS - __N'), (v) => v === '0');
  S.must('__CLOCK = __CLOCK + 11', 'later');
  expect('after it: es-MX -> Spanish', S.str('Loc.T("tag_curious")'), (v) => v === 'Curioso');
  S.must('__SETTING = "de"', 'forced');
  expect('a forced language wins over the engine', S.str('Loc.T("tag_curious")'), (v) => v === 'Neugierig');
  S.must('__SETTING = "auto"; __ENGINE_LANG = nil; __CLOCK = __CLOCK + 11', 'broken');
  expect('the engine call fails: English', S.str('Loc.T("tag_curious")'), (v) => v === 'Curious');
  expect('an unknown key comes back as itself, visibly', S.str('Loc.T("no_such_key")'), (v) => v === 'no_such_key');
}

console.log('\n=== D. {name} ===');
{
  const S = newState(null, 'Loc = require("Locale")');
  expect('English', S.str('Loc.T("betrayed", { name = "Lamball" })'), (v) => v === 'Lamball no longer trusts you. It will not bond with you again.');
  expect('a name with "%" in it', S.str('Loc.T("fell", { name = "100%Pal" })'), (v) => v === '100%Pal fell while fighting alongside you.');
  S.must('__ENGINE_LANG = "ko"; __CLOCK = __CLOCK + 11', 'ko');
  expect('Korean keeps the name first', S.str('Loc.T("joined", { name = "Lamball" })'), (v) => v.startsWith('Lamball'));
}

console.log('\n=== D2. Gender (Dragón: a female Pal tagged "Curioso") ===');
{
  const S = newState(null, '__ENGINE_LANG = "es-MX"; Loc = require("Locale")');
  expect('Spanish, female: Curiosa', S.str('Loc.T("tag_curious", { female = true })'), (v) => v === 'Curiosa');
  expect('Spanish, male: Curioso', S.str('Loc.T("tag_curious", { female = false })'), (v) => v === 'Curioso');
  expect('Spanish, unknown gender: the masculine form', S.str('Loc.T("tag_curious")'), (v) => v === 'Curioso');
  expect('an invariant word stays the same', S.str('Loc.T("tag_hostile", { female = true })'), (v) => v === 'Hostil');
  expect('a message: se dio por vencida', S.str('Loc.T("abandoned", { name = "Lovander", female = true })'), (v) => v === 'Lovander se quedó atrás y se dio por vencida contigo.');
  S.must('__ENGINE_LANG = "en"; __CLOCK = __CLOCK + 11', 'en');
  expect('English ignores it', S.str('Loc.T("tag_curious", { female = true })'), (v) => v === 'Curious');
}
{
  const src = fs.readFileSync(path.join(scriptsDir, 'Personality.lua'), 'utf8');
  expect('Personality stores female from GetGenderType() == 2', String(src.includes('tonumber(param:GetGenderType()) == 2') && src.includes('female = female,')), (v) => v === 'true');
  const S = newState('prelude_person.lua', 'P = require("Personality")');
  expect('Personality.IsFemale exists', S.str('type(P.IsFemale)'), (v) => v === 'function');
  const ind = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('Indicator passes the Pal\'s gender to every tag', String((ind.match(/Locale\.T\([^)]*, g\)/g) || []).length >= 4), (v) => v === 'true');
  const cap = fs.readFileSync(path.join(scriptsDir, 'Capture.lua'), 'utf8');
  expect('Capture passes it to every Pal message', String(cap.includes('female = preResolvedFemale') && cap.includes('female = Capture.IsFemale(pal)') && cap.includes('Locale.T("betrayed", g)')), (v) => v === 'true');
}

console.log('\n=== E. The modules show translated text ===');
{
  // The F9 toast, through the real keybind.
  const S = newState('prelude_emote.lua', [
    '__ENGINE_LANG = "fr"',
    '__TOASTS = {}',
    'package.loaded["Capture"] = nil',
    'package.preload["Capture"] = function() return { ShowToast = function(m) __TOASTS[#__TOASTS + 1] = m end,',
    '  IsAlreadyOwned = function() return false end, HasPermanentlyFled = function() return false end } end',
    'package.loaded["Settings"].Get = function(k) local d = { Language = __SETTING, KeyPlay = "F8", KeyTags = "F9", KeyPassiveGain = "F10",',
    '  Pet = 50, Play = 50, FeedBase = 50, FeedBonusCommon = 10, FeedBonusUncommon = 20, FeedBonusRare = 30, FeedBonusEpic = 40,',
    '  FeedBonusLegendary = 50, KinshipPeachLesser = 250, KinshipPeach = 500, PassivePerTick = 2, JoinBonus = 50000 } return d[k] end',
    'I = require("Interaction"); I.Init()',
    'package.loaded["Indicator"] = { TogglePersonalityLabels = function() return false end }',
  ].join('\n'));
  const bindKey = S.str('(function() for k in pairs(__BINDS) do if tostring(k):find("F9") then return k end end end)()');
  S.must('__BINDS["' + bindKey + '"]()', 'f9');
  expect('F9 toast in French', S.str('__TOASTS[1]'), (v) => v === 'Étiquettes de personnalité : DÉSACTIVÉES');
}
{
  const src = fs.readFileSync(path.join(scriptsDir, 'Indicator.lua'), 'utf8');
  expect('Indicator shows tags through Locale.T', String((src.match(/Locale\.T\(/g) || []).length >= 4), (v) => v === 'true');
  const cap = fs.readFileSync(path.join(scriptsDir, 'Capture.lua'), 'utf8');
  expect('no English message text left in Capture', String(/has chosen to go with you|no longer trusts you|was left behind|flinched away/.test(cap.replace(/--.*$/gm, ''))), (v) => v === 'false');
}

console.log(failures === 0 ? '\nALL CHECKS PASSED' : '\n' + failures + ' CHECK(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
