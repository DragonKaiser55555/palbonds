// Same as harness2 but dumps the list of hook paths actually registered.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');

const dir = process.argv[2];
const preludePath = process.argv[3];

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(code, name) {
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name));
  if (st !== lua.LUA_OK) return 'LOAD: ' + to_jsstring(lua.lua_tostring(L, -1));
  const r = lua.lua_pcall(L, 0, 0, 0);
  if (r !== lua.LUA_OK) {
    const e = lua.lua_tostring(L, -1);
    return to_jsstring(e === null ? to_luastring('(non-string error)') : e);
  }
  return null;
}

lua.lua_newtable(L);
lua.lua_setglobal(L, to_luastring('__HOOKS'));

let e = run(fs.readFileSync(preludePath, 'utf8'), 'prelude');
if (e) { console.error('PRELUDE FAILED:', e); process.exit(1); }

run('package.path = "' + dir + '/?.lua;" .. package.path', 'path');
run('local ro = io.open; io.open = function(n, m) return ro("' + dir + '/__harness_log.txt", m or "w") end', 'io');

e = run('dofile("' + dir + '/main.lua")', 'main');
if (e) console.error('ABORTED: ' + e);

run('__OUT = table.concat(__HOOKS, "\\n")', 'out');
lua.lua_getglobal(L, to_luastring('__OUT'));
const s = lua.lua_tostring(L, -1);
console.log(s === null ? '' : to_jsstring(s));
