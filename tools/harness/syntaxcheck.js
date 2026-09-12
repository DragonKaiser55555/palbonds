// Compile-only syntax check for every .lua file in a directory.
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
let bad = 0;
for (const f of fs.readdirSync(dir).filter(x => x.endsWith('.lua')).sort()) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const code = fs.readFileSync(path.join(dir, f), 'utf8');
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(f));
  if (st !== lua.LUA_OK) {
    bad++;
    console.log('SYNTAX ERROR  ' + f + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
  } else {
    console.log('ok            ' + f);
  }
}
console.log(bad === 0 ? '\nALL FILES COMPILE' : '\n' + bad + ' file(s) failed');
process.exit(bad === 0 ? 0 : 1);
