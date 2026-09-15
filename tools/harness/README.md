# Offline test harness

There is no Lua interpreter on this machine. These tests run the **real mod
source** under [fengari](https://github.com/fengari-lua/fengari), a Lua 5.3 VM
in JavaScript, with the UE4SS globals stubbed by a prelude. They cannot prove
in-game behaviour, but they have caught several bugs that a live test run could
not have distinguished from "it didn't work again" — including two that shipped
and cost a play session each.

## Setup

```bash
cd tools/harness
npm install fengari
```

## Running everything

`<SCRIPTS>` is the directory holding the mod's `.lua` files — normally
`mod/PalBonds/Scripts`, or the live install to verify what is actually deployed.

```bash
node syntaxcheck.js <SCRIPTS>                      # every file compiles
node harness3.js    <SCRIPTS> prelude.lua          # main.lua loads; expect 14 hooks
node assisttest.js  <SCRIPTS> prelude_323.lua      # combat assist reaches the hook
node assisttest.js  <SCRIPTS> prelude_323.lua noaddr   # ...and fails OPEN without GetAddress
node td2test.js     <SCRIPTS> prelude_323.lua      # target discipline + force-march recall
node gracetest.js   <SCRIPTS> prelude_323.lua      # drift grace period + IsBusyFighting
node presettest.js  <SCRIPTS> prelude_person.lua   # all 8 companion preset slots
node shiptest.js    <SCRIPTS> prelude_emote.lua    # shipping keybind state
node stoptest.js    <SCRIPTS> prelude_323.lua      # fight state is dropped when a Pal stops following
node selfdefencetest.js <SCRIPTS> prelude_323.lua  # a companion hit outside a player fight fights back
node captest.js     <SCRIPTS> prelude_323.lua      # per-Pal install caps recover (rate, not lifetime)
node reachtest.js   <SCRIPTS> prelude_323.lua      # no fight past the recall distance or during a recall
node hitcosttest.js <SCRIPTS> prelude_323.lua      # a multi-hit burst must not walk the object array per hit
node profiletest.js <SCRIPTS>                      # the dev profiler: off = untouched globals, on = same 14 hooks, returns/errors pass through, reports only at depth 0
node perffixtest.js <SCRIPTS>                      # microstutter fixes: PlayerRef keeps the player, no sensor-index rebuild on a new Pal, hook-fed personality scan, hook-fed nameplates -- and every fallback still searches
node feedtest.js    <SCRIPTS> prelude_emote.lua    # feed amount by item rarity
node playstoptest.js <SCRIPTS> prelude_emote.lua   # the player's cheer stops with the Pal's Play animation
python hoistcheck.py <SCRIPTS>                     # calls before their definition
python undefcheck.py <SCRIPTS>                     # calls to functions never defined
```

Every suite prints `ALL CHECKS PASSED` or a list of failures and exits non-zero.

**Known false positives in the static checkers** (both pre-existing, both fine):
`hoistcheck` flags `tick` in `Combat.lua` (the word appears inside a log string)
and `grant_wild_interaction` in `Interaction.lua` (forward-declared at line 144
in a form the checker doesn't recognise). `undefcheck` flags `continueFn` and
`onFire`, which are function parameters.

## Why the preludes matter

`prelude_323.lua` is the important one. It does three things the others don't:

- **captures scheduled callbacks** (`ExecuteInGameThreadWithDelay`) into
  `__PENDING`, so `__PUMP(n)` drives the mod's real fast loop rather than the
  test calling internals directly. This is what exposed a loop early-out that
  silently disabled the recall for the only Pal that needed it.
- **captures hook handlers** (`RegisterHook`) into `__HOOKS`, so `__FIRE(path, ...)`
  fires a real engine event at the real handler. `__arg(v)` wraps a value the way
  UE4SS wraps hook arguments.
- **mocks `GetAddress()`**, and honours `__NO_ADDRESS = true` to simulate a build
  where it doesn't work — which is how the damage gate's fail-open path is tested.

`__LOG` is cleared freely by tests; `__ALLLOG` never is, so once-per-session
latched log lines can still be asserted after a clear.

## The rule these exist to enforce

**A regression test must be run against the broken code too.** A test that passes
both before and after a fix proves nothing. Every bug-driven suite here was
verified by reverting the fix in a throwaway copy and confirming the test fails
there — `assisttest.js` against the pass-331 gate, `td2test.js` against the
pass-324 statement order. Do the same for the next one.
