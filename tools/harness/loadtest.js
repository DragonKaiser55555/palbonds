// Does the mod actually LOAD?
//
// syntaxcheck proves a file parses. It cannot prove the file RUNS, and the gap
// between the two is where a whole mod can disappear: a ported Settings.lua
// summed a list of keys that did not exist in its new schema, died on
// "attempt to perform arithmetic on a nil value" at require time, and took
// main.lua down with it. That happens before the logger opens, so there was no
// mod log at all -- the only symptom in game was the destination silently
// missing from the station, which cost a full test run to diagnose from
// UE4SS.log.
//
// This runs every module for real in fengari, with the UE4SS globals stubbed,
// and fails on any error raised while loading. It does not test behaviour; it
// answers one question -- would this mod come up in game?
//
// Usage: node loadtest.js <SCRIPTS> [entry]   (entry defaults to "main")
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) { console.error('usage: node loadtest.js <SCRIPTS> [entry]'); process.exit(2); }
const entry = process.argv[3] || 'main';
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// --- the UE4SS surface, stubbed to do nothing ------------------------------
// Each returns nil, which is what every call site here is already written to
// survive: the mod has to cope with a function being unavailable in game too.
const noop = ['RegisterHook', 'NotifyOnNewObject', 'ExecuteInGameThreadWithDelay',
              'ExecuteInGameThread', 'LoadAsset', 'RegisterKeyBind', 'FName',
              'StaticFindObject', 'FindAllOf', 'FindFirstOf', 'StaticConstructObject',
              'CreateInvalidObject', 'UnregisterHook', 'print'];
for (const name of noop) {
  lua.lua_pushjsfunction(L, () => { lua.lua_pushnil(L); return 1; });
  lua.lua_setglobal(L, to_luastring(name));
}

// fengari has no io library; the mod reads and writes files, so give it one
// that always reports "no such file". That is the first-launch path, which is
// the one most likely to break.
lua.lua_getglobal(L, to_luastring('io'));
if (lua.lua_isnil(L, -1)) {
  lua.lua_pop(L, 1);
  lua.lua_newtable(L);
  lua.lua_setglobal(L, to_luastring('io'));
  lua.lua_getglobal(L, to_luastring('io'));
}
lua.lua_pushjsfunction(L, () => { lua.lua_pushnil(L); return 1; });
lua.lua_setfield(L, -2, to_luastring('open'));
lua.lua_pop(L, 1);

// --- load the modules ------------------------------------------------------
lua.lua_getglobal(L, to_luastring('package'));
// UE4SS puts shared libraries (UEHelpers) in Mods/shared, outside the mod's own
// folder, so a mod that requires one will not load without that on the path.
const sharedGuesses = [
  scriptsDir + '/../../shared/?.lua',
  scriptsDir + '/../../shared/?/?.lua',
  'C:/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64/ue4ss/Mods/shared/?.lua',
  'C:/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64/ue4ss/Mods/shared/?/?.lua',
];
lua.lua_pushstring(L, to_luastring([scriptsDir + '/?.lua'].concat(sharedGuesses).join(';')));
lua.lua_setfield(L, -2, to_luastring('path'));
lua.lua_pop(L, 1);

const files = fs.readdirSync(scriptsDir).filter(f => f.endsWith('.lua'));
let failures = 0;

// Every module on its own first, so a failure names the file that failed rather
// than whichever one happened to require it.
for (const f of files.sort()) {
  const name = f.replace(/\.lua$/, '');
  if (name === entry) continue;
  const top = lua.lua_gettop(L);
  lua.lua_getglobal(L, to_luastring('require'));
  lua.lua_pushstring(L, to_luastring(name));
  const rc = lua.lua_pcall(L, 1, 1, 0);
  if (rc !== lua.LUA_OK) {
    const err = to_jsstring(lauxlib.luaL_tolstring(L, -1));
    console.log('FAILED       ' + f + '\n             ' + err);
    failures++;
  } else {
    console.log('loads        ' + f);
  }
  lua.lua_settop(L, top);
}

// Then the entry point, which is what UE4SS actually runs.
{
  const top = lua.lua_gettop(L);
  lua.lua_getglobal(L, to_luastring('require'));
  lua.lua_pushstring(L, to_luastring(entry));
  const rc = lua.lua_pcall(L, 1, 1, 0);
  if (rc !== lua.LUA_OK) {
    const err = to_jsstring(lauxlib.luaL_tolstring(L, -1));
    console.log('FAILED       ' + entry + '.lua  (the mod would not start)\n             ' + err);
    failures++;
  } else {
    console.log('loads        ' + entry + '.lua');
  }
  lua.lua_settop(L, top);
}

console.log('');
if (failures === 0) {
  console.log('THE MOD LOADS');
  process.exit(0);
}
console.log(failures + ' module(s) failed to load - the mod would not start in game');
process.exit(1);
