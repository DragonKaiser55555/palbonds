local function noop() end
RegisterHook = function(name, ...) __HOOKS[#__HOOKS+1] = name; return true end
RegisterKeyBind = function(...) return true end
ExecuteInGameThreadWithDelay = function(ms, fn) return true end
ExecuteInGameThread = function(fn)
  __GAME_THREAD_CALLS = (__GAME_THREAD_CALLS or 0) + 1
  if type(fn) == "function" then fn() end
  return true
end
LoopAsync = function(ms, fn) return true end
FindFirstOf = function(n) return nil end
FindAllOf = function(n) return nil end
StaticFindObject = function(n) return nil end
StaticConstructObject = function(...) return nil end
NotifyOnNewObject = function(...) return true end
IsInGameThread = function() return true end
CreateInvalidObject = function() return nil end
Key = setmetatable({}, {__index = function(_, k) return k end})
ModifierKey = setmetatable({}, {__index = function(_, k) return k end})

package.preload["UEHelpers"] = function()
  return {
    GetPlayer = function() return nil end,
    GetWorld = function() return nil end,
    GetGameInstance = function() return nil end,
    FindOrAddFName = function(s) return s end,
    GetKismetSystemLibrary = function() return nil end,
    GetKismetMathLibrary = function() return nil end,
  }
end
