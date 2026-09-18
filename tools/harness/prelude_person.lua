__LOG = {}
__CALLS = {}
local function note(x) __CALLS[#__CALLS + 1] = x end

local function obj(name, fields)
  local t = fields or {}
  t.__name = name
  t.IsValid = function() return true end
  t.GetFullName = function(self) return (self and self.__name) or name end
  return t
end

-- the AI sensor: records which of the two "re-sense" calls happen
__SENSOR = obj("PalAISensorComponent_1")
__SENSOR.ResetResponsedMaxBiologicalGrade = function() note("ResetResponsedMaxBiologicalGrade") end
__SENSOR.RequestSightCheckAsync = function() note("RequestSightCheckAsync") end

-- the action component: records the destructive cancel
__ACTION_COMP = obj("ActionsComp")
__ACTION_COMP.AllCancelAction_Logic_HardScript_Reaction = function() note("AllCancelAction(DESTRUCTIVE)") end
__ACTION_COMP.GetCurrentAction_BP = function() return nil end

__CONTROLLER = obj("BP_MonsterAIController_Wild_C")
__CONTROLLER.GetAIActionComponent = function() return __ACTION_COMP end
__CONTROLLER.GetHateSystem = function() return nil end

__PAL = obj("BP_FlowerDoll_C_1")
__PAL.Controller = __CONTROLLER
__PAL.AISensorComponent = __SENSOR
__PAL.GetComponentByClass = function() return __SENSOR end
__SENSOR.GetOwner = function() return __PAL end

-- a preset CDO and the native preset class
-- PalUtility -> handle -> individual id, so GetStableId resolves a real id and
-- GetOrInitState actually creates a PersonalityState entry.
__GUID = { A = 1, B = 2, C = 3, D = 4 }
__ID_OBJ = obj("IndividualId")
__ID_OBJ.InstanceId = __GUID
__HANDLE = obj("Handle")
__HANDLE.GetIndividualID = function() return __ID_OBJ end
__UTILITY = obj("Default__PalUtility")
__UTILITY.GetIndividualCharacterHandleByActor = function() return __HANDLE end

__CDO = obj("Default__BP_AIResponsePreset_friendly_C")
__NATIVE = obj("PalAIResponsePreset")

RegisterHook = function() return true end
RegisterKeyBind = function() return true end
ExecuteInGameThreadWithDelay = function() return true end
ExecuteInGameThread = function(fn)
  __GAME_THREAD_CALLS = (__GAME_THREAD_CALLS or 0) + 1
  if type(fn) == "function" then fn() end
  return true
end
LoopAsync = function() return true end
FindFirstOf = function() return nil end
FindAllOf = function(n)
  if n == "PalAISensorComponent" then return { __SENSOR } end
  return nil
end
StaticFindObject = function(p)
  if type(p) ~= "string" then return nil end
  if p:find("Default__PalUtility") then return __UTILITY end
  if p:find("friendly") then return __CDO end
  if p:find("AIResponsePreset") then return __NATIVE end
  return nil
end
StaticConstructObject = function()
  local a = obj("FreshPreset")
  return a
end
NotifyOnNewObject = function() return true end
IsInGameThread = function() return true end
CreateInvalidObject = function() return nil end
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = setmetatable({}, { __index = function(_, k) return k end })

package.preload["UEHelpers"] = function()
  return { GetPlayer = function() return nil end, GetWorld = function() return nil end,
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
-- the Pal must look WILD, or ApplyCompanionPreset refuses outright
package.preload["Capture"] = function()
  local M = {}
  function M.Init() end
  function M.IsAlreadyOwned() return false end
  function M.HasPermanentlyFled() return false end
  return M
end
