-- Pass 323 test bed: target discipline driven by the hate table, and the
-- force-march recall driven through the REAL fast loop rather than by calling
-- an internal directly.
__LOG = {}
__ALLLOG = {}
__CALLS = {}
__HAS_ACTION = true
__HATE_TARGET = nil
__PENDING = {}

local function note(x) __CALLS[#__CALLS + 1] = x end
__note = note

-- Set __NO_ADDRESS = true BEFORE loading the modules to simulate a build where
-- UObject:GetAddress() does not work, which is the fail-open case.
__NO_ADDRESS = false
local nextAddress = 0x1000
local function obj(name, fields)
  local t = fields or {}
  t.__name = name
  t.IsValid = function() return true end
  t.GetFullName = function(self) return (self and self.__name) or name end
  nextAddress = nextAddress + 0x10
  local myAddress = nextAddress
  t.GetAddress = function()
    if __NO_ADDRESS then error("GetAddress unsupported on this build") end
    return myAddress
  end
  return t
end
__obj = obj

local function vec(x, y, z) return { X = x, Y = y, Z = z } end
__vec = vec

__COMBAT_CLASS = obj("BlueprintGeneratedClass BP_AIAction_CombatPal_C")
__CURRENT_ACTION = obj("BP_AIAction_CombatPal_C_777")
__CURRENT_ACTION.GetClass = function() return __COMBAT_CLASS end

__ACTION_COMP = obj("ActionsComp")
__ACTION_COMP.SetAction = function() note("SetAction") end
__ACTION_COMP.HasAction = function() return __HAS_ACTION end
__ACTION_COMP.TerminateCurrentActionByClass = function() note("Terminate") end
__ACTION_COMP.GetCurrentAction_BP = function() return __CURRENT_ACTION end
__ACTION_COMP.GetCurrentAIActionCategory = function() return 0 end
__ACTION_COMP.AllCancelAction_Logic_HardScript_Reaction = function() note("AllCancelAction") end
__ACTION_COMP.SetRootComposite = function() note("SetRootComposite") end

__HATE = obj("Hate")
__HATE.ChangeHate = function(self, actor, amt)
  note("ChangeHate(" .. tostring(actor and actor.__name) .. "," .. tostring(amt) .. ")")
end
__HATE.FindMostHateTarget = function() return __HATE_TARGET end

__CONTROLLER = obj("BP_MonsterAIController_Wild_C")
__CONTROLLER.GetAIActionComponent = function() return __ACTION_COMP end
__CONTROLLER.GetHateSystem = function() return __HATE end
__CONTROLLER.SimpleMoveToActorWithLineTraceGround = function(self, goal)
  note("SimpleMoveToActor(" .. tostring(goal and goal.__name) .. ")")
end
__CONTROLLER.PalMoveToLocation = function() note("PalMoveToLocation") return 2 end

-- Where the Pal is. The test moves this to simulate straying.
__PAL_LOC = vec(0, 0, 0)
__PAL = obj("BP_TestPal_C_1")
__PAL.Controller = __CONTROLLER
__PAL.CharacterParameterComponent = nil
__PAL.K2_GetActorLocation = function() return __PAL_LOC end

__PAL2 = obj("BP_TestPal_C_2")
__PAL2.Controller = __CONTROLLER
__PAL2.CharacterParameterComponent = nil
__PAL2.K2_GetActorLocation = function() return vec(0, 0, 0) end

__ENEMY = obj("BP_EnemyPal_C_9")
__BYSTANDER = obj("BP_RandomWildPal_C_42")
__PLAYER = obj("BP_Player_Female_C_2147477654")
__PLAYER.K2_GetActorLocation = function() return vec(0, 0, 0) end
__PLAYER.GetControlRotation = function() return { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 } end

-- Capture hook handlers so tests can fire real engine events at them.
__HOOKS = {}
RegisterHook = function(path, pre, post)
  __HOOKS[tostring(path)] = pre
  return true
end

-- Wraps a value the way UE4SS wraps hook arguments (param:get()).
function __arg(v) return { get = function() return v end } end

-- Fires a captured hook. Returns "ok", "NO HOOK", or the error.
function __FIRE(path, ...)
  local fn = __HOOKS[tostring(path)]
  if fn == nil then return "NO HOOK" end
  local ok, err = pcall(fn, ...)
  return ok and "ok" or tostring(err)
end
RegisterKeyBind = function() return true end
ExecuteInGameThreadWithDelay = function(ms, fn)
  __PENDING[#__PENDING + 1] = fn
  return true
end
ExecuteInGameThread = function(fn)
  __GAME_THREAD_CALLS = (__GAME_THREAD_CALLS or 0) + 1
  if type(fn) == "function" then fn() end
  return true
end
LoopAsync = function() return true end
FindFirstOf = function(n) if n == "PalPlayerCharacter" then return __PLAYER end return nil end
FindAllOf = function(n)
  if n == "PalPlayerCharacter" then return { __PLAYER } end
  return nil
end
StaticFindObject = function(p)
  if type(p) == "string" and p:find("OtomoFollow") then return obj("FollowClass") end
  if type(p) == "string" and p:find("CombatPal") then return __COMBAT_CLASS end
  return nil
end
__ACTION_VALID = true
StaticConstructObject = function()
  note("Construct")
  local a = obj("ConstructedAction")
  a.IsValid = function() return __ACTION_VALID end
  a.SetTargetAndNextAction = function() note("SetTargetAndNextAction") end
  return a
end
NotifyOnNewObject = function() return true end
IsInGameThread = function() return true end
CreateInvalidObject = function() return nil end
Key = setmetatable({}, { __index = function(_, k) return k end })
ModifierKey = setmetatable({}, { __index = function(_, k) return k end })

package.preload["UEHelpers"] = function()
  return { GetPlayer = function() return __PLAYER end, GetWorld = function() return nil end,
           GetGameInstance = function() return nil end, FindOrAddFName = function(s) return s end,
           GetKismetSystemLibrary = function() return nil end, GetKismetMathLibrary = function() return nil end }
end
package.preload["Logger"] = function()
  local M = {}
  function M.Init() end
  -- __LOG is cleared freely by tests; __ALLLOG never is, so once-per-session
  -- latched messages can still be asserted after an intervening clear.
  function M.log(m)
    __LOG[#__LOG + 1] = tostring(m)
    __ALLLOG[#__ALLLOG + 1] = tostring(m)
  end
  function M.DiagnosticsEnabled() return false end
  return M
end
package.preload["Personality"] = function()
  local M = {}
  function M.Init() end
  function M.GetOrInitState() return "ID" end
  function M.GetStableId() return "ID" end
  function M.ApplyCompanionPreset() return true end
  function M.RefreshSightOn() end
  return M
end

-- Drains the scheduled-callback queue N times, so the real fast loop runs.
function __PUMP(n)
  for _ = 1, n do
    local q = __PENDING
    __PENDING = {}
    for _, fn in ipairs(q) do pcall(fn) end
  end
end
