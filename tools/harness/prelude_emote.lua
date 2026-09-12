-- Emote-probe test bed. Captures keybinds so the F7 handler can be invoked,
-- and records the exact native call made on the player controller.
__LOG = {}
__CALLS = {}
__BINDS = {}
__TOASTS = {}
__EMOTE_MISSING = {}   -- set of emote numbers that must NOT resolve

local function note(x) __CALLS[#__CALLS + 1] = x end

local function obj(name, fields)
  local t = fields or {}
  t.__name = name
  t.IsValid = function() return true end
  t.GetFullName = function(self) return (self and self.__name) or name end
  return t
end

__PAWN = obj("BP_Player_Female_C_1")
__PC = obj("BP_PalPlayerController_C_1")
__PC.Pawn = __PAWN
__PC.ActionComponent_PlayAction_ToServer_ForPlayer = function(self, pawn, param, cls, n)
  note("PlayAction(pawn=" .. tostring(pawn and pawn.__name)
      .. ", param=" .. type(param)
      .. ", cls=" .. tostring(cls and cls.__name)
      .. ", n=" .. tostring(n) .. ")")
end

RegisterHook = function() return true end
RegisterKeyBind = function(key, fn) __BINDS[tostring(key)] = fn; return true end
ExecuteInGameThreadWithDelay = function() return true end
ExecuteInGameThread = function() return true end
ExecuteWithDelay = function() return true end
LoopAsync = function() return true end
NotifyOnNewObject = function() return true end
IsInGameThread = function() return true end
CreateInvalidObject = function() return nil end

FindFirstOf = function(n) return nil end
FindAllOf = function(n)
  if n == "BP_PalPlayerController_C" then return { __PC } end
  return nil
end
StaticFindObject = function(p)
  if type(p) ~= "string" then return nil end
  local num = p:match("BP_Action_Emote_(%d+)%.")
  if num ~= nil then
    if __EMOTE_MISSING[tonumber(num)] then return nil end
    return obj("BP_Action_Emote_" .. num .. "_C")
  end
  return nil
end
StaticConstructObject = function() return nil end

Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = setmetatable({}, { __index = function(_, k) return k end })

package.preload["UEHelpers"] = function()
  return { GetPlayer = function() return __PAWN end, GetWorld = function() return nil end,
           GetGameInstance = function() return nil end, FindOrAddFName = function(s) return s end,
           GetKismetSystemLibrary = function() return nil end, GetKismetMathLibrary = function() return nil end }
end
package.preload["Logger"] = function()
  local M = {}
  function M.Init() end
  function M.log(m) __LOG[#__LOG + 1] = tostring(m) end
  function M.DiagnosticsEnabled() return false end
  return M
end
package.preload["Capture"] = function()
  local M = {}
  function M.ShowToast(t) __TOASTS[#__TOASTS + 1] = tostring(t) end
  function M.IsAlreadyOwned() return false end
  return M
end
package.preload["Indicator"] = function()
  return { Init = function() end, TogglePersonalityLabels = function() return true end }
end

function __PRESS(key)
  local fn = __BINDS[tostring(key)]
  if fn == nil then return "NO BIND" end
  local ok, err = pcall(fn)
  return ok and "ok" or tostring(err)
end
