// 2026-09-12: feed amount by item rarity (Dragón's scale: base 50, +10..+50).
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
  return s === null ? 'nil' : to_jsstring(s);
}
function expect(label, actual, wanted) {
  const ok = actual === wanted;
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

let e = run(fs.readFileSync(process.argv[3], 'utf8'), 'prelude');
if (e) { console.log('PRELUDE: ' + e); process.exit(1); }
run('package.path = "' + dir + '/?.lua;" .. package.path', 'p');

// A fake item database behind the real call chain.
run([
  '__RARITY = { Berries = 0, Honey = 2, CakeX = 4, OddItem = 7 }',
  '__DATA_CALLS = 0',
  'local function ok(t) t.IsValid = function() return true end return t end',
  '__MANAGER = ok({ GetStaticItemData = function(self, fname)',
  '  __DATA_CALLS = __DATA_CALLS + 1',
  '  local r = __RARITY[tostring(fname)]',
  '  if r == nil then return nil end',
  '  return ok({ Rarity = r })',
  'end })',
  '__UTIL = ok({ GetItemIDManager = function(self, ctx) return __MANAGER end })',
  'local realSFO = StaticFindObject',
  'StaticFindObject = function(p) if p == "/Script/Pal.Default__PalUtility" then return __UTIL end return realSFO(p) end',
  '__CTX = ok({})',
].join('\n'), 'db');

e = run('I = require("Interaction")', 'load');
if (e) { console.log('LOAD: ' + e); process.exit(1); }

console.log('\n=== AMOUNTS ===');
expect('common (rarity 0) -> 60', str('select(1, I.FeedGrantAmount("Berries", __CTX))'), '60');
expect('rare (rarity 2) -> 80', str('select(1, I.FeedGrantAmount("Honey", __CTX))'), '80');
expect('legendary (rarity 4) -> 100', str('select(1, I.FeedGrantAmount("CakeX", __CTX))'), '100');
expect('above the scale -> treated as legendary, 100', str('select(1, I.FeedGrantAmount("OddItem", __CTX))'), '100');
expect('unreadable rarity -> base 50 only', str('select(1, I.FeedGrantAmount("NoSuchItem", __CTX))'), '50');
expect('Kinship Peach keeps its own amount', str('select(1, I.FeedGrantAmount("AffectionFruit_01", __CTX))'), '500');

console.log('\n=== STATIC DATA IS READ ONCE PER ITEM ===');
run('__DATA_CALLS = 0', 'r');
run('I.FeedGrantAmount("Berries", __CTX); I.FeedGrantAmount("Berries", __CTX)', 'again');
expect('a cached item makes no further native lookups', str('__DATA_CALLS'), '0');

console.log('\n' + (failures === 0 ? 'ALL CHECKS PASSED' : failures + ' CHECK(S) FAILED'));
process.exit(failures === 0 ? 0 : 1);
