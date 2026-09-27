// A one-off: run Settings.TextWithValues against Dragón's REAL settings file,
// not a synthetic one, and prove the result still reads back correctly with his
// own comments and values intact.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const HARNESS = 'C:/Users/Dragon/Proyectos/32-PalBonds/tools/harness';
const SCRIPTS = 'C:/Users/Dragon/Proyectos/32-PalBonds/mod/PalBonds/Scripts';
const REAL = 'C:/Users/Dragon/Proyectos/32-PalBonds/save-backups/PalBonds_settings.before-live-screen.lua';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, name) {
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c'));
  if (st !== lua.LUA_OK) { const e = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_settop(L, 0); return 'LOAD: ' + e; }
  const r = lua.lua_pcall(L, 0, 0, 0);
  if (r !== lua.LUA_OK) { const e = lua.lua_tostring(L, -1); const m = e === null ? '?' : to_jsstring(e); lua.lua_settop(L, 0); return m; }
  return null;
}
function str(expr) {
  const err = run('__OUT = tostring(' + expr + ')', 'ev');
  if (err) return 'ERR: ' + err;
  lua.lua_getglobal(L, to_luastring('__OUT'));
  const s = lua.lua_tostring(L, -1);
  lua.lua_settop(L, 0);
  return s === null ? 'nil' : to_jsstring(s);
}

let bad = 0;
function check(label, actual, pred) {
  const ok = typeof pred === 'function' ? pred(actual) : actual === pred;
  if (!ok) bad++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + label + '  (' + actual + ')');
}

run(fs.readFileSync(path.join(HARNESS, 'prelude_323.lua'), 'utf8'), 'prelude');
run('package.path = "' + SCRIPTS + '/?.lua;" .. package.path', 'path');
run('Key = {}; for _, n in ipairs({ "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","G","H","J","K" }) do Key[n] = n end', 'keys');
const e = run('Set = require("Settings")', 'set');
if (e) { console.log('could not load Settings: ' + e); process.exit(1); }

const real = fs.readFileSync(REAL, 'utf8');
run('__REAL = ' + JSON.stringify(real), 'real');

console.log('\nDragon\'s real settings file, through the save path:');
check('it parses as the mod reads it',
  str('(function() local t = load(__REAL, "c", "t", {}) return t ~= nil and type(t()) end)()'), 'table');

run('__NEW = Set.TextWithValues(__REAL, { Pet = 123, Language = "pt", KeyPlay = "G", ShowPersonalityTags = 0 })', 'edit');
check('the save produced a file', str('type(__NEW)'), 'string');
check('every changed value arrived',
  str('(function() local t = load(__NEW, "c", "t", {})() return t.Pet .. "/" .. t.Language .. "/" .. t.KeyPlay .. "/" .. t.ShowPersonalityTags end)()'),
  '123/pt/G/0');
check('nothing else moved',
  str('(function() local a = load(__REAL, "c", "t", {})() local b = load(__NEW, "c", "t", {})()' +
      ' local changed = { Pet = true, Language = true, KeyPlay = true, ShowPersonalityTags = true }' +
      ' for k, v in pairs(a) do if not changed[k] and b[k] ~= v then return "moved: " .. k end end' +
      ' for k in pairs(b) do if a[k] == nil then return "appeared: " .. k end end return "identical" end)()'),
  'identical');
check('the read-back check passes it',
  str('tostring(Set.UpdatedTextIsGood(__NEW, { Pet = 123, Language = "pt", KeyPlay = "G", ShowPersonalityTags = 0 }, {}))'),
  'true');
check('his comments all survived (same number of comment lines)',
  str('(function() local function n(s) local c = 0 for _ in s:gmatch("\\n%s*%-%-") do c = c + 1 end return c end' +
      ' return (n(__REAL) == n(__NEW)) and "same" or (n(__REAL) .. " vs " .. n(__NEW)) end)()'),
  'same');
check('the file is the same length bar the values',
  str('(function() local d = #__NEW - #__REAL return (d > -20 and d < 20) and "close" or tostring(d) end)()'),
  'close');
check('every line count is unchanged (nothing reflowed)',
  str('(function() local function n(s) local c = 1 for _ in s:gmatch("\\n") do c = c + 1 end return c end' +
      ' return (n(__REAL) == n(__NEW)) and "same" or (n(__REAL) .. " vs " .. n(__NEW)) end)()'),
  'same');

console.log(bad === 0 ? '\nOK against the real file\n' : '\n' + bad + ' PROBLEM(S) against the real file\n');
process.exit(bad === 0 ? 0 : 1);
