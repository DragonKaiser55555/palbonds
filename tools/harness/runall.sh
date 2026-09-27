#!/bin/sh
# Every suite in one run, each with the prelude it needs.
#
#   sh runall.sh ../../mod/PalBonds/Scripts        # the source we edit
#   sh runall.sh ../../release/PalBonds/Scripts    # what actually ships
#
# Written because getting a prelude wrong makes a suite ABORT rather than fail,
# and an aborted suite reads like a passing one if you only skim the output.
cd "$(dirname "$0")" || exit 1
S="${1:-../../mod/PalBonds/Scripts}"
run() {
  name="$1"; shift
  out=$(node "$@" < /dev/null 2>&1)
  if echo "$out" | grep -qE "ALL CHECKS PASSED|ALL FILES COMPILE"; then
    printf "  ok    %s\n" "$name"
  else
    printf "  FAIL  %s\n" "$name"
    echo "$out" | grep -E "FAIL|PRELUDE|Error|error:" | head -5
  fi
}
run "syntax"           syntaxcheck.js "$S"
out=$(node harness3.js "$S" prelude.lua < /dev/null 2>&1)
if echo "$out" | grep -q "all modules initialized" && ! echo "$out" | grep -q "ABORTED"; then
  printf "  ok    harness3 (%s hooks)
" "$(echo "$out" | grep -c "^/")"
else
  printf "  FAIL  harness3
"; echo "$out" | tail -5
fi
run "assist"           assisttest.js "$S" prelude_323.lua
run "assist noaddr"    assisttest.js "$S" prelude_323.lua noaddr
run "td2"              td2test.js "$S" prelude_323.lua
run "grace"            gracetest.js "$S" prelude_323.lua
run "preset"           presettest.js "$S" prelude_person.lua
run "ship"             shiptest.js "$S" prelude_emote.lua
run "stop"             stoptest.js "$S" prelude_323.lua
run "selfdefence"      selfdefencetest.js "$S" prelude_323.lua
run "cap"              captest.js "$S" prelude_323.lua
run "reach"            reachtest.js "$S" prelude_323.lua
run "hitcost"          hitcosttest.js "$S" prelude_323.lua
run "perffix"          perffixtest.js "$S"
run "boss"             bosstest.js "$S"
run "worldchange"      worldchangetest.js "$S"
run "feed"             feedtest.js "$S" prelude_emote.lua
run "points"           pointstest.js "$S"
run "settings"         settingstest.js "$S"
run "locale"           localetest.js "$S"
run "playstop"         playstoptest.js "$S" prelude_emote.lua
run "pairwatch"        pairwatchtest.js "$S" prelude_emote.lua
run "join"             jointest.js "$S"
run "nettest"          nettest.js "$S"
run "multiplayer"      multiplayertest.js "$S"
run "coopstage2"       coopstage2test.js "$S"
run "menu"             menutest.js "$S"
