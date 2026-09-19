// Dumps Locale.lua's strings as JSON, read by the real Lua file (fengari).
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(require('path').resolve(process.argv[3], 'node_modules', 'fengari'));
const dir = process.argv[2].replace(/\\/g, '/');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const code = `
package.path = "${dir}/?.lua;" .. package.path
package.preload["Settings"] = function() return { Get = function() return "en" end } end
package.preload["Logger"] = function() return { log = function() end } end
local Loc = require("Locale")
local function q(s) return '"' .. s:gsub('\\\\', '\\\\\\\\'):gsub('"', '\\\\"') .. '"' end
local out = {}
local keys = {}
for k in pairs(Loc.STRINGS) do keys[#keys + 1] = k end
for _, k in ipairs(keys) do
  local parts = {}
  for lang, v in pairs(Loc.STRINGS[k]) do
    if type(v) == "table" then
      parts[#parts + 1] = q(lang) .. ':{"m":' .. q(v.m) .. ',"f":' .. q(v.f) .. '}'
    else
      parts[#parts + 1] = q(lang) .. ':' .. q(v)
    end
  end
  out[#out + 1] = q(k) .. ':{' .. table.concat(parts, ',') .. '}'
end
__JSON = '{' .. table.concat(out, ',') .. '}'
`;
if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) { console.error(to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
lua.lua_getglobal(L, to_luastring('__JSON'));
process.stdout.write(to_jsstring(lua.lua_tostring(L, -1)));
