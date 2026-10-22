// Which reward does the release destination actually pay?
//
// Dragón, after a live run: "i had it on and showed berries, then i turned it
// off and showed the full rewards - it did it backwards". Nothing covered this
// at all, which is why a half-working switch reached him twice.
//
// The question is narrow and checkable without a game: after ApplyReward runs,
// WHICH LOTTERY does our row point at? The berries one we rewrote, or the first
// expedition's own? This drives the real Destination.lua against stand-in data
// tables and reads the row back.
//
// Covered: on, off, toggling both ways, and -- the case a toggle test misses --
// a FRESH session that starts with the setting already ON, where nothing has
// ever pointed the row at berries.
//
// Usage: node rewardtest.js <SCRIPTS>
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const dir = process.argv[2];
if (!dir) { console.error('usage: node rewardtest.js <SCRIPTS>'); process.exit(2); }
const scriptsDir = dir.replace(/\\/g, '/').replace(/\/$/, '');
let failures = 0;

function expect(what, got, want) {
  const ok = String(got) === String(want);
  if (!ok) failures++;
  console.log('  ' + (ok ? 'PASS' : 'FAIL') + '  ' + what + '  (' + got + ')');
}

// Stand-in data tables, close enough to the real ones for this question:
//  * the mission table holds our row, the template we clone, and the donor
//  * the lottery table holds rows tagged with the field they belong to
const WORLD = `
local MISSION = {
  DUNGEON_GRASS = { RequiredSeconds = 1800, RecommendedStrength = 100, MaxCharacterNum = 5,
                    RequiredElementNum = 0, TitleTextId = "T_GRASS", ItemFieldLotteryName = "FIELD_GRASS" },
  DUNGEON_WORLDTREEHARD = { RequiredSeconds = 3600, RecommendedStrength = 900, MaxCharacterNum = 5,
                    RequiredElementNum = 0, TitleTextId = "T_WTH", ItemFieldLotteryName = "FIELD_WTH" },
}
local LOTTERY = {
  L1 = { FieldName = "FIELD_WTH",   StaticItemId = "GoldCoin", MinNum = 10, MaxNum = 20, BonusExpRate = 5 },
  L2 = { FieldName = "FIELD_WTH",   StaticItemId = "Ore",      MinNum = 1,  MaxNum = 2,  BonusExpRate = 5 },
  L3 = { FieldName = "FIELD_GRASS", StaticItemId = "Wood",     MinNum = 1,  MaxNum = 2,  BonusExpRate = 1 },
  L4 = { FieldName = "FIELD_OTHER", StaticItemId = "Berries",  MinNum = 1,  MaxNum = 3,  BonusExpRate = 1 },
}
local function tbl(rows)
  local t = {}
  function t:FindRow(n) return rows[n] end
  function t:GetRowNames() local o = {} for k in pairs(rows) do o[#o+1] = k end table.sort(o) return o end
  function t:AddRow(n, src) local c = {} for k, v in pairs(src) do c[k] = v end rows[n] = c end
  return t
end
local MT, LT = tbl(MISSION), tbl(LOTTERY)
__MISSION, __LOTTERY = MISSION, LOTTERY
function StaticFindObject(p)
  if type(p) ~= "string" then return nil end
  if p:find("CharacterTeamMission", 1, true) then return MT end
  if p:find("ItemLottery", 1, true) then return LT end
  return nil
end
function FindAllOf() return nil end
function ExecuteInGameThreadWithDelay() end
function RegisterHook() end
function NotifyOnNewObject() end
function LoadAsset() end
function print() end
`;

function newState(realReward) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name || 'c')) !== lua.LUA_OK) {
      const e = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_settop(L, 0); return 'LOAD: ' + e;
    }
    if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      const e = lua.lua_tostring(L, -1);
      const m = e === null ? '(non-string error)' : to_jsstring(e);
      lua.lua_settop(L, 0); return m;
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
  const must = (code, name) => { const e = run(code, name); if (e) { console.log('  SETUP (' + name + '): ' + e); failures++; } };

  must('package.path = "' + scriptsDir + '/?.lua;" .. package.path', 'path');
  must(WORLD, 'world');
  // A Settings stand-in whose RealReward this test controls.
  must('__REAL = ' + realReward + '\n'
     + 'package.loaded["Settings"] = { Get = function(k) if k == "RealReward" then return __REAL end'
     + ' if k == "DurationMinutes" then return 5 end return nil end,'
     + ' Load = function() end, Schema = function() return {} end,'
     + ' Path = function() return nil end, FileName = function() return "x.lua" end }', 'settings');
  must('package.loaded["Release"] = { HasPending = function() return false end }', 'release');
  must('D = require("Destination")', 'require');
  return { must, str, setReward: (v) => must('__REAL = ' + v, 'set') };
}

const lotteryOf = (S) => S.str('__MISSION.PALRELEASE_WILD and __MISSION.PALRELEASE_WILD.ItemFieldLotteryName');

console.log('\n=== A. Berries by default ===');
{
  const S = newState(0);
  S.must('assert(D.Ensure())', 'ensure');
  S.must('D.ApplyReward()', 'apply');
  expect('the row points at the rewritten (berries) field', lotteryOf(S), 'FIELD_WTH');
  expect('that field really was rewritten to berries', S.str('__LOTTERY.L1.StaticItemId'), 'Berries');
  expect('...and pays no bonus experience', S.str('__LOTTERY.L1.BonusExpRate'), '0');
  expect('the first expedition is left alone', S.str('__LOTTERY.L3.StaticItemId'), 'Wood');
}

console.log('\n=== B. Switching it ON pays the first expedition ===');
{
  const S = newState(0);
  S.must('assert(D.Ensure())', 'ensure');
  S.must('D.ApplyReward()', 'apply-off');
  S.setReward(1);
  S.must('D.ApplyReward()', 'apply-on');
  expect('the row now points at the first expedition', lotteryOf(S), 'FIELD_GRASS');
}

console.log('\n=== C. Switching it back OFF restores berries ===');
{
  const S = newState(0);
  S.must('assert(D.Ensure())', 'ensure');
  S.must('D.ApplyReward()', 'off1');
  S.setReward(1);
  S.must('D.ApplyReward()', 'on');
  S.setReward(0);
  S.must('D.ApplyReward()', 'off2');
  expect('berries again, not left on the real payout', lotteryOf(S), 'FIELD_WTH');
  expect('and it still pays berries', S.str('__LOTTERY.L1.StaticItemId'), 'Berries');
}

console.log('\n=== D. A session that STARTS with it on ===');
{
  // The case a toggle test cannot reach: nothing has ever pointed the row at
  // berries, so a fix that only works by switching away from them would pass
  // every test above and still be wrong on a real save.
  const S = newState(1);
  S.must('assert(D.Ensure())', 'ensure');
  S.must('D.ApplyReward()', 'apply');
  expect('it pays the first expedition from the very first call', lotteryOf(S), 'FIELD_GRASS');
  expect('nothing was rewritten to berries needlessly', S.str('__LOTTERY.L1.StaticItemId'), 'GoldCoin');
}

console.log('');
if (failures === 0) { console.log('ALL CHECKS PASSED'); process.exit(0); }
console.log(failures + ' CHECK(S) FAILED');
process.exit(1);
