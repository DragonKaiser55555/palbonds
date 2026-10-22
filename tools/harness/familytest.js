// Does the befriending declaration actually get written?
//
// The family wiring is wrapped in pcall at the call site, so a failure inside it
// is silent -- which is exactly what happened: no declaration files on disk and
// not one "family:" line in the log. This calls Register and Declare for real
// and prints whatever error comes back.
//
// Usage: node familytest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');

const dir = process.argv[2];
if (!dir) { console.error('usage: node familytest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

for (const name of ['RegisterHook','NotifyOnNewObject','ExecuteInGameThreadWithDelay',
                    'LoadAsset','StaticFindObject','FindAllOf','FName','print']) {
  lua.lua_pushjsfunction(L, () => { lua.lua_pushnil(L); return 1; });
  lua.lua_setglobal(L, to_luastring(name));
}

// An in-memory file system: the declaration has to be WRITTEN, so io.open must
// work for "w" and report back what was produced.
const FS = {};
lua.lua_getglobal(L, to_luastring('io'));
if (lua.lua_isnil(L, -1)) { lua.lua_pop(L,1); lua.lua_newtable(L); lua.lua_setglobal(L, to_luastring('io')); lua.lua_getglobal(L, to_luastring('io')); }
lua.lua_pushjsfunction(L, (S) => {
  const path = to_jsstring(lauxlib.luaL_checkstring(S, 1));
  const mode = lua.lua_gettop(S) > 1 ? to_jsstring(lauxlib.luaL_checkstring(S, 2)) : 'r';
  if (mode.indexOf('r') >= 0 && FS[path] === undefined) { lua.lua_pushnil(S); return 1; }
  if (mode.indexOf('w') >= 0) FS[path] = '';
  lua.lua_newtable(S);
  lua.lua_pushjsfunction(S, (S2) => {           // write
    FS[path] = (FS[path] || '') + to_jsstring(lauxlib.luaL_checkstring(S2, 2));
    lua.lua_pushboolean(S2, true); return 1;
  });
  lua.lua_setfield(S, -2, to_luastring('write'));
  lua.lua_pushjsfunction(S, (S2) => { lua.lua_pushstring(S2, to_luastring(FS[path] || '')); return 1; });
  lua.lua_setfield(S, -2, to_luastring('read'));
  lua.lua_pushjsfunction(S, () => 0);
  lua.lua_setfield(S, -2, to_luastring('close'));
  return 1;
}, 'open');
lua.lua_setfield(L, -2, to_luastring('open'));
lua.lua_pop(L, 1);

lua.lua_getglobal(L, to_luastring('package'));
lua.lua_pushstring(L, to_luastring(scriptsDir + '/?.lua'));
lua.lua_setfield(L, -2, to_luastring('path'));
lua.lua_pop(L, 1);

function run(src, label) {
  if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) {
    console.log('FAILED  ' + label + '\n        ' + to_jsstring(lauxlib.luaL_tolstring(L, -1)));
    lua.lua_pop(L, 1);
    return false;
  }
  return true;
}

let bad = 0;
// A settings file has to exist for Settings.Path() to resolve to anything.
FS['Pal/Binaries/Win64/ue4ss/Mods/shared/PalFarewell_settings.lua'] = 'return {}\n';

if (!run('Settings = require("Settings") Settings.Load()', 'Settings.Load')) bad++;
if (!run('Family = require("Family")', 'require Family')) bad++;
if (!run('assert(Family.Register())', 'Family.Register')) bad++;
if (!run('assert(Family.Declare(true))', 'Family.Declare')) bad++;

// --- the other half: does a HOST read what the add-on declared? -----------
// This is the piece that failed in game -- the add-on wrote nothing, so there
// was nothing to read, and the screen showed PalBonds only. Both halves are
// checked here so neither can fail silently again.
const host = process.argv[3];
if (host) {
  const hostDir = host.replace(/\\/g, '/').replace(/\/$/, '');
  // The host only trusts a declaration while the add-on is still installed.
  FS['Pal/Binaries/Win64/ue4ss/Mods/PalFarewell/enabled.txt'] = '';
  FS['Pal/Binaries/Win64/ue4ss/Mods/shared/PalBonds_settings.lua'] = 'return {}\n';
  const H = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(H);
  for (const name of ['RegisterHook','NotifyOnNewObject','ExecuteInGameThreadWithDelay',
                      'LoadAsset','StaticFindObject','FindAllOf','FName','print']) {
    lua.lua_pushjsfunction(H, () => { lua.lua_pushnil(H); return 1; });
    lua.lua_setglobal(H, to_luastring(name));
  }
  lua.lua_getglobal(H, to_luastring('io'));
  if (lua.lua_isnil(H, -1)) { lua.lua_pop(H,1); lua.lua_newtable(H); lua.lua_setglobal(H, to_luastring('io')); lua.lua_getglobal(H, to_luastring('io')); }
  lua.lua_pushjsfunction(H, (S) => {
    const path = to_jsstring(lauxlib.luaL_checkstring(S, 1));
    const mode = lua.lua_gettop(S) > 1 ? to_jsstring(lauxlib.luaL_checkstring(S, 2)) : 'r';
    if (mode.indexOf('r') >= 0 && FS[path] === undefined) { lua.lua_pushnil(S); return 1; }
    if (mode.indexOf('w') >= 0) FS[path] = '';
    lua.lua_newtable(S);
    lua.lua_pushjsfunction(S, (S2) => { FS[path] = (FS[path]||'') + to_jsstring(lauxlib.luaL_checkstring(S2, 2)); lua.lua_pushboolean(S2, true); return 1; });
    lua.lua_setfield(S, -2, to_luastring('write'));
    lua.lua_pushjsfunction(S, (S2) => { lua.lua_pushstring(S2, to_luastring(FS[path]||'')); return 1; });
    lua.lua_setfield(S, -2, to_luastring('read'));
    lua.lua_pushjsfunction(S, () => 0);
    lua.lua_setfield(S, -2, to_luastring('close'));
    return 1;
  }, 'open');
  lua.lua_setfield(H, -2, to_luastring('open'));
  lua.lua_pop(H, 1);
  // loadfile must see the in-memory files too, since declarations are read with it.
  lua.lua_pushjsfunction(H, (S) => {
    const path = to_jsstring(lauxlib.luaL_checkstring(S, 1));
    if (FS[path] === undefined) { lua.lua_pushnil(S); lua.lua_pushstring(S, to_luastring('no file')); return 2; }
    if (lauxlib.luaL_loadstring(S, to_luastring(FS[path])) !== lua.LUA_OK) { lua.lua_pushnil(S); return 1; }
    return 1;
  }, 'loadfile');
  lua.lua_setglobal(H, to_luastring('loadfile'));
  lua.lua_getglobal(H, to_luastring('package'));
  lua.lua_pushstring(H, to_luastring(hostDir + '/?.lua'));
  lua.lua_setfield(H, -2, to_luastring('path'));
  lua.lua_pop(H, 1);

  // Reading is half of it. The player will CHANGE a value and press Save, and
  // that write goes into the add-on's OWN file from the host's Lua state -- the
  // one path nothing covered.
  const src = 'local S = require("Settings") S.Load()'
    + ' local n = 0 for _, e in ipairs(S.Schema()) do if e.addon then n = n + 1 end end'
    + ' S.Set("PalFarewell.DurationMinutes", 9)'
    + ' return n';
  if (lauxlib.luaL_dostring(H, to_luastring(src)) !== lua.LUA_OK) {
    console.log('FAILED  host reading declarations\n        ' + to_jsstring(lauxlib.luaL_tolstring(H, -1)));
    bad++;
  } else {
    const n = lua.lua_tointeger(H, -1);
    if (n > 0) console.log('host rendered ' + n + ' add-on row(s)');
    else { console.log('FAILED  the host read no add-on rows'); bad++; }
  }
}

if (host) {
  const vals = FS['Pal/Binaries/Win64/ue4ss/Mods/shared/PalFarewell_settings.lua'] || '';
  if (vals.indexOf('DurationMinutes = 9') >= 0) {
    console.log('host wrote the new value back into the add-on file');
  } else {
    console.log('FAILED  saving an add-on setting did not reach its file - now: ' + JSON.stringify(vals));
    bad++;
  }
}

const written = Object.keys(FS).filter(k => k.indexOf('befriending') >= 0);
console.log('');
if (written.length === 0) {
  console.log('NOTHING WAS DECLARED - no befriending file was written');
  bad++;
} else {
  for (const w of written) {
    console.log('wrote ' + w + '  (' + FS[w].length + ' bytes)');
    console.log(FS[w].split('\n').slice(0, 12).join('\n'));
  }
}
process.exit(bad === 0 ? 0 : 1);
