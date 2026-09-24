# Multiplayer — the rules, and what is still open

Working document for co-op support (own-hosted worlds only; official servers are
out of scope). Dragón's answers are recorded here as they are given, so the next
session does not have to ask again.

Status: design in progress, nothing built beyond step 1 below.

---

## Already built

**Step 2 — a Pal that belongs to another player (2026-09-20, harness-tested,
NOT yet seen in a real co-op world).** Implements R2/R4 with the detection
Dragón chose (the follow trainer):

- `Combat.ClaimedByAnotherPlayer(pal)` answers from the PAL, not from any
  shared state: it is claimed only when a follow action is installed AND that
  action's `Trainer` is a player character that is not ours. Everything else —
  our own Pal, no follow action, a trainer that is another Pal or itself, an
  unreadable trainer, a missing action component — is NOT claimed, so nothing
  unreadable can ever block an interaction. Cached 5 s per Pal.
- Refused in three places: the radial-menu substitution (which covers pet AND
  feed, and is early enough that the game never takes the food), the Play key,
  and the trust grant itself.
- The other player's screen shows `tag_claimed` ("Claimed") where the
  personality tag normally sits, in all 16 languages. The owner sees the normal
  tag, because the question is "does it follow somebody who is not us".
- Tests: `multiplayertest.js` sections F and G, including the control that an
  unclaimed Pal still pays out.


**Step 1 — which player is ours (2026-09-20, live-verified).** Every player
lookup used to take the first `PalPlayerCharacter` in the object list; in co-op
that is whoever the engine lists first, which is how a player watched the Pal he
befriended join his friend's party. `PlayerRef` now prefers the character this
machine controls (`APawn::IsLocallyControlled`), and so does the
player-controller fallback. Confirmed in game: the engine answers the question
on this build.

---

**Step 3 — a guest's copy does nothing (2026-09-20, harness-tested, NOT yet
seen in a real session).** Dragón: "in case a guest has our mod active shouldnt
we just return or do nothing on that regard? ... so they dont crash among
themselves." He also refused to ship a release whose only multiplayer content
was a crash guard: "if we ship a new version lets make them worth doing".

- **`Scripts/Session.lua` (new file — remember it at packaging time)** answers
  what kind of session this is, using the technique read from the Multi Party
  Pals Summons reference mod: no NetDriver on the world = singleplayer, a
  NetDriver with a `ServerConnection` = we are a GUEST, a net mode containing
  "dedicated" = a dedicated server, otherwise we are hosting. Unreadable = we
  may act, because switching the mod off over one failed engine read would be
  worse than the bug it prevents. Re-asked on every world change.
- **Every hook in Indicator, Personality, Trust and Interaction** now stands
  down for a guest through the same gate that already makes the mod go blind
  while a world is closing (one helper per file, 16 call sites).
- **`Capture.TryDirectCapture` and `Capture.OnTrustMaxed` refuse outright** —
  this is the fatal one — and **`Combat.StartFollowing` does not start**, which
  is what caused 25 rebuilds a minute against the server.
- **Guest run 1 (2026-09-20, 21:07): the session was detected correctly
  (`this is a client session`), no crash, no tags, no interactions — but the
  stand-down was INCOMPLETE.** Only the hooks had been gated; the recurring
  jobs and the keys had not. The log still shows 33 personality rolls and 33
  enforcement attempts after the guest was detected, and Dragón's F9 still
  showed its toast. Now gated too: the personality scan, the nameplate scan,
  the follower tick (each inside the worker, never in the scheduler, so the
  loops keep ticking and resume the moment the session changes) and the three
  keys.
- **Guest run 2 (2026-09-20, 21:21): the mod acted as if it were singleplayer.**
  The log showed `this is a singleplayer session` THREE times, each one to two
  seconds after a world reset — i.e. at the TITLE SCREEN, where a world object
  exists with no NetDriver yet, which reads exactly like singleplayer. The
  answer was cached there and believed for the whole server session. Fixed:
  the answer is only remembered once OUR player character is in the world (the
  first moment anything in the mod has work to do); before that it is re-read
  at most twice a second, and the log line says "still loading". Covered by two
  test sections that fail without it.
- Tests: `multiplayertest.js` H (all four modes, including "no world yet") and
  I (the guest refuses the join, starts no follow, ignores its hooks, stands
  every recurring job down and answers no key, with singleplayer controls that
  still do all of it).

## THE PLAN: host-authoritative co-op (Dragón, 2026-09-21)

Dragón: *"we need to make our current mod work for multiplayer, coop, servers,
etc - find whatever way you can to achieve that and work towards it - if
there's a test i can do to help you, just tell me."*

**The shape, from what the guest run measured.** Everything a guest failed at
(AI presets, the follow action, the join) is exactly what the machine that
OWNS the world can do. In a hosted world the host's game IS the server; on a
dedicated server, the server is. So:

- **Authority side** (singleplayer, host, dedicated server): trust records,
  personality rolls and AI writes, follow and combat assist, the join, boss
  credit, claims (R1-R4). Must work per PLAYER, not "our player": every one of
  these currently assumes `PlayerRef.Get()` (the local player), which a
  dedicated server does not even have. `UPalUtility::PalCaptureSuccess(
  AttackerPlayer, Monster)` already takes the player, so a guest's join can be
  done by the host into THAT guest's party.
- **Guest side:** input only (the radial-menu substitution -- a wild Pal
  cannot be petted at all without it, so guests still need the mod) and
  display (tags, bars, messages).
- **Two channels to find:** guest -> authority ("I petted this Pal"), and
  authority -> one guest ("your bar is at 40%", "X joined you").

**Channel candidates (header dump, `APalPlayerController`):**
- Up: the game's own requests, if a guest's pet/feed already reaches the
  server -- `ActionComponent_PlayAction_ToServer_ForPlayer(TargetActor,
  FActionDynamicParameter, ActionClass, issuerID)`,
  `RequestUseItemToCharacter_ToServer(item, TargetCharacterID)`. The server-side
  hook's `self` is the sending player's controller, so the sender is known.
- Up, free text: `Debug_CheatCommand_ToServer(FString)`.
- Down, free text to ONE player: `Debug_ReceiveCheatCommand_ToClient(FString)`.
  (`SendLog_ToClient` only takes the game's own text IDs.)
Whether the Debug_ RPCs are delivered in the shipping game is unknown -- the
net probe answers it.

**Dedicated servers are officially moddable:** `PalServer/Mods/PalModSettings.ini`
has the same `bGlobalEnableMod` / `WorkshopRootDir` / `ActiveModList` keys as
the game client. And `PalServer-Win64-Shipping(-Cmd).exe` imports `dwmapi.dll`
like the client, so the manual UE4SS proxy works there too (used for the probe).

### Net probe run 1 -- SET UP 2026-09-21, awaiting Dragón

Watch-only; nothing gameplay-related is attempted on the server.
- **Server:** manual UE4SS copied from the dev install into
  `PalServer/Pal/Binaries/Win64/` (`dwmapi.dll` + `ue4ss/` with UE4SS.dll,
  settings with the ImGui console OFF, built-in mods). Mods: the built-ins and
  `tools/netprobe/PalBondsNetProbeServer` ONLY -- no PalBonds on the server yet.
  Log: `PalServer/Pal/Binaries/Win64/palbonds-netprobe-server.log`.
  To remove: rename the server's `dwmapi.dll`.
- **Client (guest):** the dev PalBonds with `Session.GUEST_INPUT_PROBE = true`
  in the GAME COPY only (`mod/` ships false; multiplayertest J), so the guest
  keeps the five radial-menu hooks; keys, follow and join still stand down.
  Plus `tools/netprobe/PalBondsNetProbeClient` (F6 = ping). Logs:
  `palbonds-live.log` and `palbonds-netprobe-client.log` in the game's Win64.
- **What each answer decides:**
  `[START]` present = UE4SS runs on the server (else: try the Workshop UE4SS
  through the server's mod manager). `[PLAYERS]` = the server sees the guest as
  a remote player. `[RPC]` / `[PAIR]` on a guest pet/feed = the game's own
  requests carry guest input, and whether the pair animation runs server-side.
  `[SENSORS]` > 0 = the server can do the AI writes the guest could not.
  `[CHANNEL]` ping on the server AND pong on the client = our private line
  works both ways, which is what guest display depends on.

### Net probe run 1 -- RESULTS (2026-09-21, 16:39-16:43)

Logs archived in `docs/bug-reports/netprobe-run1/`. Dragón as a guest on the
local dedicated server; he pressed F6 four times, petted a wild Lamball twice,
fed another once, then caught a Lamball with a sphere and petted/fed it as his
own Pal (the control).

- **UE4SS runs on the dedicated server** (manual `dwmapi.dll` proxy, dev build
  `ba2efd55`, ImGui console off). All five hooks registered.
- **The server sees the guest as a remote player:** `locallyControlled=false`.
- **THE PRIVATE LINE WORKS BOTH WAYS.** 4/4 `Debug_CheatCommand_ToServer`
  pings reached the server, each with the sending player identified (the hook's
  `self` is that player's controller); 4/4 `Debug_ReceiveCheatCommand_ToClient`
  replies reached that client only, in 50-90 ms. **Nothing appeared on screen**,
  so the base game shows nothing for either message -- safe for players
  without the mod.
- **A guest's pet and feed REACH THE SERVER NATIVELY.** The radial-menu
  substitution on the guest makes the game send
  `PlayAction_ToServer_ForPlayer(BP_ActionPairStandby_Petting_C / _FeedItem_C,
  issuer 256)`, and the server runs the real pair: player
  `BP_ActionPairBehavior_Petting`, and the WILD Lamball
  `BP_AIActionPairCall_Petting`. So guest input needs no invention -- the
  authority can see it happen, with the player known. (`actorParam` read nil:
  the Pal is not in the field the probe tried; the server still knew it.)
- **The cut-short was OUR watchdog, not the game.** On the guest,
  `[PAIR-RELEASE]` cancelled the pose 1-2 s in ("the Pal stopped coming")
  because a guest cannot read any Pal's AI; the server shows the player's
  action ending in that same second while the Lamball stayed in its petting
  animation 5-10 s longer. FIXED: `watch_player_pair` returns on a guest
  (multiplayertest K, fails without the guard). The guest's `[PET-CHECK]`
  "never happened" is the same blindness: confirming a pet is authority work.
- A wild FEED sent no `RequestUseItemToCharacter_ToServer` (the owned-Pal feed
  did): the wild feed's item cost is our own client-side decrement in
  singleplayer, so on a guest it must move to the authority too. Whether the
  berry was spent in this run is unknown (the feed was cut short).
- `[SENSORS] 0` was read once, the instant the player joined -- too early to
  mean anything. The next run (PalBonds itself on the server) answers it.
- Sphere capture did not fire `ChallengeCapture_ToServer`; irrelevant to us.

**Consequence:** the host-authoritative plan is viable end to end -- input
arrives through the game's own requests, and the private line carries anything
else in both directions. Next: PalBonds itself running on the authority for
remote players.

### Stage 1 -- BUILT 2026-09-21 (harness-tested), awaiting co-op run 1

The first slice of host-authoritative co-op: a guest's pet and feed are granted
on the machine that owns the world, a guest's Pal follows and joins THAT guest,
and the guest gets the messages. Dragón: "we need to make our current mod work
for multiplayer, coop, servers, etc - find whatever way you can".

- **`Scripts/Net.lua` (NEW FILE -- must reach both release trees and the zip,
  the PlayerRef.lua trap from 1.1.2).** The private line: "PB1" + kind + TAB
  fields over `Debug_CheatCommand_ToServer` / `Debug_ReceiveCheatCommand_ToClient`.
  Owner-side handlers run only for a REMOTE controller (the local path already
  did the work); guest-side handlers only on the machine the message was sent
  TO (the hook also fires on the sender). 2 more hooks: 19 in total.
- **`PlayerRef.WithPlayer / Acting / IsRemote`: the acting player.** Work done
  for a guest runs with that guest as `PlayerRef.Get()`. Work that continues on
  a timer carries the player with it: the pet check's polls, and the join after
  the 5 s wait (from `st.owner`).
- **`Trust`: `st.owner`** = the first player who earned the Pal points while
  this machine worked for someone (R4); `Trust.GetOwner`. nil = local player,
  i.e. all of singleplayer.
- **`Capture.show_log`:** every message goes through one function; for a
  remote player it becomes a TOAST over the line and the guest's copy shows it
  with the same AddLog call.
- **`Interaction`:** on a guest, the radial pet sends `PET <palId>` and the feed
  hook sends `FEED <palId> <amount> <item>` instead of granting; the guest no
  longer writes its own inventory slot. On the owner, `PET` finds the Pal by
  stable id within 2500 of THAT guest and runs the singleplayer pet check with
  `acceptCurrent` (the message can arrive after the pet animation started);
  `FEED` grants the amount, clamped to 0..500. The stuck-pose watchdog never
  runs on a guest (it cannot see the Pal).
- **Tests:** `tools/harness/nettest.js` (A-H, 53 checks); four deliberate
  regressions each caught (acting player lost on the timer -> the server paid 50
  by reading ITS OWN player's pose; acceptCurrent ignored; sender-side guard
  removed; owner never recorded). All 23 suites pass, 19 hooks.

**KNOWN GAPS of stage 1 (by design, next stages):**
1. **Only ONE remote player at a time on a dedicated server, and a host+guest
   world is not yet right.** The recurring jobs -- the follower tick (drift,
   passive gain, death), the fast follow loop (trainer re-assert, recall), the
   damage hooks (betrayal, combat assist) -- still ask `PlayerRef.Get()` with no
   acting player. On a dedicated server with one guest, PlayerRef adopts that
   guest (its "only one character, never answered true" fallback), so they
   work for that guest; with two players they go blind, and on a HOST they
   would treat a guest's follower as the host's. **Stage 2 = these loops per
   owner** (group followers by `st.owner`, run each group inside WithPlayer).
2. **Guests see no trust bar or personality tag** (the guest's Indicator stands
   down; the values live on the owner). Stage 3: the owner sends each guest
   its bars/tags over the line.
3. **A guest's wild feed is not charged** (no inventory write on the guest; the
   owner does not take the item yet).
4. **Messages are in the OWNER's language** (built there, sent as text).
5. **Dedicated server UI work never stops trying:** Indicator's nameplate
   sweep and the radial-menu hook retries keep running on a server with no UI.
   Harmless for the test; skip them when the session is "dedicated".

### Co-op run 1 -- SET UP 2026-09-21

- **Server:** PalBonds itself in `PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalBonds`
  (mod/ + DEBUG_LOGGING + SHOW_DIAGNOSTICS), plus the watch-only server probe.
  Its settings file `ue4ss/Mods/shared/PalBonds_settings.lua` was pre-written
  with **Pet = 125** (TEST VALUE, delete the file after) -- the mod appends the
  rest on first launch. Logs: `PalServer/Pal/Binaries/Win64/palbonds-live.log`
  and `palbonds-netprobe-server.log`.
- **Client (guest):** mod/ + DEBUG_LOGGING + SHOW_DIAGNOSTICS +
  `GUEST_INPUT_PROBE = true`, plus the client probe.

### Co-op run 1 -- RESULTS (2026-09-21, 17:12-17:16): THE WHOLE CHAIN WORKS

Logs in `docs/bug-reports/coop-run1/`. Dragón as a guest on the local dedicated
server, PalBonds on the server. Zero Lua errors on either side.

- **Stable ids match across machines** (`7590C1C3...` sent by the guest, found
  by the server): the individual GUID is the shared identity, as designed.
- **Guest pets granted on the server:** 5 PET messages, 4 paid +125 each
  (confirmed 0.25-0.58 s after arrival). The 5th was refused by the normal
  double-pay rule ("still the PREVIOUS pet") -- same as singleplayer.
  Dragón: the animations played out fully this time.
- **20% calm-down, 50% follow, passive gain:** the brief follow ran on the
  first pet; the second crossed 50% and the guest got "Cattiva parece tenerte
  cariño y empieza a seguirte" over the line; passive gain +34 and +14 while
  following; the follow held (no FOLLOW-RESTORE rebuilds, trainer re-asserted
  with real destinations). Dragón saw the Cattiva (`BP_PinkCat_C`) follow him.
- **The join worked for a remote player:** 548/500 -> 5 s wait -> +50000
  friendship -> `PalCaptureSuccess(guest, pal)` -> the Cattiva in Dragón's
  party with the bonus, join message shown on his screen.
- **Guest FEED:** `FEED <id> 60 Berries` -> +60 on the second Cattiva (12% of
  its bar). No toast for a feed alone, as in singleplayer.
- **Join VFX NOT seen by the guest.** `NS_PalCatch_Success` was spawned on the
  SERVER (component=true), and a spawned effect is local to that machine. Fix:
  the owner tells the guest to spawn it on its side, before the capture.
- **F9 on the SERVER:** two "Etiquetas de personalidad" toggles arrived from
  the server at 17:14:34/35. UE4SS keybinds read the whole machine's keyboard,
  so a key pressed in the game ALSO fired in the server process on the same PC,
  and the server sent its toggle message to the only player. Only possible
  with both on one machine, but a dedicated server must have no keys at all.
- **Session detection said "host" on the dedicated server** (the net-mode
  string did not contain "dedicated"). Harmless so far -- both are the
  authority -- but the dedicated-only parts (no keys, no UI retries) need it
  right. Candidate: `UKismetSystemLibrary::IsDedicatedServer(WorldContext)`.
- Messages arrived in Spanish: built in the server's language (this PC's).

**Next, in order:** stage 2 (the follower tick, fast follow loop and damage
hooks per owner -- required for the friend session, where the host is also a
player), then the small ones above (join VFX on the guest, dedicated detection
+ no keys/UI there), then stage 3 (guest bars/tags), food charging, and
messages in the guest's language.

### Stages 2 and 3 -- BUILT 2026-09-21 (harness-tested), awaiting co-op run 2

Dragón: "advance the development as much as we can before the friend test run".

**Stage 2 -- several players on one host or dedicated server.**
- **Timers carry the acting player** (`PlayerRef`: the global
  `ExecuteInGameThreadWithDelay` is wrapped once at load). Every delay
  scheduled while working for a player runs for that player: pet-check polls,
  the 20% calm-down's release checks, the join wait, combat windows. Timers
  scheduled outside any scope (every recurring loop, all of singleplayer) are
  untouched.
- **Owner keys** (`PlayerRef.OwnerKey`): "local" for the player at this
  machine, otherwise the player's CONTROLLER name, which survives death and
  respawn. Trust records `ownerKey/ownerCtrl/ownerPawn` at the first positive
  grant; Combat records `followerOwnerKey/Ctrl` at StartFollowing.
- **Claims at the authority (R2/R4, Q3):** `Trust.MayBond` refuses another
  player's grant (radial pet and feed paths, `[CLAIMED]`); a claim ends when the
  bar reaches 0, and ALL bonds and claims of a player whose controller no longer
  exists are released (`[COOP] ... its player left the world`). A player who is
  only dead keeps everything.
- **Trust tick per owner:** the follower tick (distance, drift, passive gain,
  move order) runs once per owner group, inside that owner's WithPlayer.
- **Combat per owner:** fight state per owner key (`combatActiveBy`,
  `combatWindowGenBy`, `lastHateTargetNameBy`); `mine(t)` restricts every
  follower loop in `OnPlayerCombatTarget` and the fast loop to the current
  owner's followers; the fast loop's per-follower part (`service`) runs once
  per owner (`for_each_owner`).
- **Damage hooks:** betrayal and "a player hit below 50%" count only the Pal's
  OWN player (R3); a fight involving a guest reaches combat assist as that guest
  (`find_fighter` / `as_player`); remote owners are in the damage gate's
  tracked set.
- **Dedicated server:** detected with `UKismetSystemLibrary::IsDedicatedServer`
  (run 1 had called itself "host"); final at once; `PlayerRef.Get()` returns
  nil there outside a player's scope (it used to adopt the single guest -- and
  with TWO guests would have found nobody, which the fast loop read as the world
  ending and reset every bond: the stage-2 suite reproduces it); the world
  watch and the fast loop's "player gone" reset never run there; keys do
  nothing there; the nameplate sweep does nothing there.
- **Join light for a guest:** the owner sends `JOINFX <palId>` on the
  celebration timer; the guest spawns `NS_PalCatch_Success` at that Pal.

**Stage 3 -- guests see bars and tags (`Scripts/HostView.lua`, NEW FILE).**
The owner sends each remote player, every 2 s, the Pals it knows within 6000
of them -- personality, bar % (measured for that viewer), bonding, broken bond,
and "mine"/"other" -- only what changed since the last message to that player
(`INFO`, records in one message). On a guest, `Trust.GetBarRatio/HasBondingState`,
`Personality.GetDisposition/IsFemale/GetOrInitState`,
`Capture.HasPermanentlyFled/GetFledReason` and `Combat.ClaimedByAnotherPlayer`
answer from that cache, so Indicator draws unchanged. A guest draws NOTHING
until the host's PalBonds has sent something (a guest on a vanilla host sees
no "?" tags). Singleplayer: the sender returns before any world search.

**Tests:** `tools/harness/coopstage2test.js` (S1-S11, 57 checks); every stage-2
and stage-3 fix was broken on purpose and caught (tick not per owner, no timer
carry, dedicated adopting a guest, dedicated world reset, betrayal by any
player, no claims, global fight state, no departure release, guest ratio not
from the host, no send dedupe, singleplayer searching). All 24 suites pass, 19
hooks. **Caught before any run:** `guest_view` placed below its first use in
Personality.lua -- GetOrInitState would have thrown on EVERY call, singleplayer
included (perffixtest/bosstest caught it; hoistcheck.py does too -- run it
after every batch).

**RELEASE NOTES FOR LATER (not decided):**
- Two NEW files must reach both release trees and the zip: `Net.lua`,
  `HostView.lua` (plus `Session.lua` from the 09-20 work).
- `Session.GUEST_INPUT_PROBE` is no longer a probe -- it IS the guest's input
  for co-op, and co-op does not work without it. It is safe on a vanilla host
  (run 1: the server just plays the pet animation; our messages are ignored).
  Rename it and ship it ON when co-op ships -- Dragón's call.
- Still open: guest food not charged; messages in the owner's language; F8
  Play for guests.

### Co-op run 2 -- RESULTS (2026-09-21, 18:35-18:39), and the fixes

Logs in `docs/bug-reports/coop-run2/`. Dragón as a guest, dedicated server.
- WORKED: the server now says "this is a dedicated session"; tags and bars did
  appear on the guest; the "left behind" toast; a Chikipi bonded to the end
  with the join light now visible on the guest's screen.
- **Tags slow, and the first bonded Pal (a Cattiva) never got one. Cause:**
  the guest's nameplate BIND hooks were gated on "the host has spoken". The
  player was in the world at 18:36:54 and the first INFO arrived at 18:37:05;
  every nameplate the game bound in those 11 s lost its bind for good (a
  nameplate learns its Pal only at bind time -- the same mechanism as the Lullu
  bar bug). FIXED: the bind/unbind/boss hooks always record; only the drawing
  waits for the host.
- **F9 did nothing on the guest:** every key had been gated for guests when a
  guest did nothing at all. FIXED: F9 only toggles this screen, so it works on
  a guest; only a dedicated server ignores keys. (F10 stays host-only; F8 Play
  for guests is still open.)
- **Also added:** the host says hello (an empty INFO) to every new guest at
  once, so the guest starts drawing even with no Pal to report; and a guest
  ASKS about any Pal its nameplates show with nothing known (at most 24 ids per
  2 s, the same id not again for 10 s) -- the host gives that Pal a personality
  if it has none (as singleplayer does for a "?" tag), remembers it, and
  answers at once. Before this the host only described Pals its AI hook had
  already noticed.
- coopstage2test S12 (13 checks). All 24 suites pass, 19 hooks.

### Co-op run 3 -- RESULTS (2026-09-21, 19:15-19:28): the guest loop is whole

Logs in `docs/bug-reports/coop-run3/` (live logs + UE4SS logs, both sides).
Dragón as a guest, dedicated server. No Lua errors on either side.
- WORKED: first tags 10 s after entering the world (12 Pals in the first
  INFO), including Pals already on screen; F9 hid/showed tags on the guest
  (4 toggles); 8 Pals bonded to the end by the guest (Gumoss, Pengullet,
  Cattiva, 5 Daedream), each with the join light and toast on the guest;
  guest FEED (Berries, +60) reached the server; **combat assist for a guest's
  followers** (19:23:04, HATE-ASSIST onto the guest's enemy, released at
  fight end); passive gain on a follower (Daedream reached 500 without a
  pet); RECALL march; the abandon toast when the guest teleported 37 000
  units away. One PET was correctly refused (the Pal was asleep).
- **Messages arrive in the server's language:** the server runs `es`, the
  guest `en`, and TOASTs carry the finished Spanish sentence. Open.
- **F8 Play does nothing for a guest:** gated on purpose; not built yet. Open.
- **Guest food is not charged:** the guest skips its local write, and the
  server does not charge it either -- the Berries were free. Open.
- **ASK repeats:** 151 ASKs in 13 min; a few ids asked 11-15 times (Pals the
  guest can see but the host does not find within 6000 units of the guest).
  Cheap, but should give up after a few unanswered asks. Open.
- Dragón felt some lag. The logs show no continuous heavy loop: the known
  40-50 ms hitch per radial-menu open (find_targeted_pal) plus dev logging,
  with the dedicated server running on the same PC.
- Not yet tested: F10 as a guest; two real players (claims, simultaneous
  play, one leaving); a hosted co-op world (not dedicated).

### Run 3 fixes -- BUILT 2026-09-21 (harness-tested), awaiting co-op run 4

- **Messages in each player's own language.** The owner sends a guest WHICH
  message it is (new kind `MSG`: tone, Locale key, the owner's name for the
  Pal, gender, the Pal's CharacterID) instead of the finished sentence; the
  guest writes it with its own Locale and looks the Pal's name up again from
  the CharacterID (`Capture.RenderHostMessage`). The owner remembers which id
  each resolved name came from (`charIdByName`). Messages without a key still
  go as `TOAST` text.
- **F10 per player (Dragón: it decides whether that player keeps followers).**
  `Trust.passiveGainOffBy[ownerKey]`; the follower tick reads the group
  owner's switch. A guest's F10 sends `PASSIVE`; the owner switches it for
  that guest and answers with the toast as a `MSG`. Cost: one table read per
  follower per tick, nothing else -- free.
- **F8 Play for a guest.** Play split into `play_pal_half` (the Pal's idle
  animation, Happy, trust) and the aiming half. A guest aims, sends `PLAY`
  with the Pal's id and cheers on its own character; the owner finds the Pal
  near that guest, checks fled / claimed / busy, and runs `play_pal_half` as
  that guest. Open question for run 4: whether the other screens see the
  guest's cheer (it is played on the guest's own copy).
- **Guest food is charged.** The guest names the slot the food came from
  (container GUID + slot index + count) in the `FEED`; the owner finds that
  container, checks the slot still holds that item, and lowers StackCount --
  the same write singleplayer makes. Done before the Pal lookup, as in
  singleplayer. Open question for run 4: whether the guest's own count
  follows (StackCount is a replicated property; a push-model setup could keep
  the guest's display stale until the slot changes again).
- **Asking backs off.** After 3 unanswered ASKs for the same Pal, it is asked
  again only once a minute.
- coopstage2test S13 (31 checks); multiplayertest's guest-key checks updated
  for F8/F10. Mutations caught: messages as text, passive not per group, host
  ignoring PLAY, off-by-one slot, no guest-side name lookup, no ask backoff.
  All 24 suites pass.

### Co-op run 3b (2026-09-21, 22:07-23:44, Dragón solo as a guest) -- first notes

Logs in `docs/bug-reports/coop-run3b/`. NetProbe removed from both installs
afterwards (its job is done; the source stays in `tools/netprobe/`).
- **A dungeon loading screen counts as a new world on a guest.** Entering
  (23:37:32) and leaving (23:40:53) the Mau dungeon: the guest's own character
  is briefly not locally controlled, PlayerRef answers nil, and Combat's world
  watch resets (386 nameplate bars dropped). Harmless for bonds on a guest (it
  holds none; the dedicated server's watch is off and its bonds survived --
  Mau joined 23:39:47, Rushoar 23:44:04), BUT it emptied HostView while the
  host kept its "already sent" table, so unchanged Pals never came back except
  through ASKs. FIXED: after a reset the guest sends `RESYNC` once its
  character is back; the host treats it as a new viewer (hello + everything
  near them). coopstage2test S14.
- **Open: does a dungeon also reset the world owner** (singleplayer / a
  hosted world)? There it would drop every bond, guests' included. Not seen in
  any log yet -- needs a singleplayer dungeon with a follower.
- **Food:** the server charged 10 guest feeds, but twice the count read the
  old value again later (Berries 117 -> 116 at 22:10:52, then 117 -> 116 at
  22:14:55), which suggests the write does not stick on the server's side or
  is overwritten. Ask Dragón what his on-screen count did.
- F8 (PLAY) and F10 (PASSIVE) from the guest: 8 messages reached the server.

### PERFORMANCE RUN 1 -- SET UP 2026-09-22, MUST BE UNDONE AFTERWARDS

Dragón felt real lag in run 3b and wants to know whether the dedicated server on
the same PC is the cause, "we must always ensure we keep the performance optimal
as much as we can". Both installs are now in RELEASE conditions:
- `Logger.lua` on BOTH the game and the server copies = the source file
  (`DEBUG_LOGGING = false`, `SHOW_DIAGNOSTICS = false`): no live log, no prints.
- The game's `ue4ss/UE4SS-settings.ini`: console and GUI console OFF (it was
  rendering an ImGui window every frame, which no player has). Original saved as
  `UE4SS-settings.ini.devconsole-backup`.
- Unchanged: `Session.GUEST_INPUT_PROBE = true` in the game copy (a guest needs
  it), the server's test settings file (`Pet = 125`).
**TO UNDO:** copy the dev `Logger.lua` back (DEBUG + diagnostics true) and
restore the ini from the backup. Nothing can be diagnosed from this run's logs
because there are none -- it measures feel only.

**A/B, same loader, only the mod swapped (2026-09-22).** Dragón then reported
that SINGLEPLAYER on the dev build feels "significantly laggier" than the
Workshop 1.1.6 -- but those two also differ in UE4SS build (dev `ba2efd55` vs
Workshop `2281fa31`) and, before today, in console and logging, so that
comparison cannot name the cause. The game install now carries both script sets
side by side:
- `ue4ss/Mods/PalBonds/Scripts-116` -- release 1.1.6, exactly as shipped
- `ue4ss/Mods/PalBonds/Scripts-now` -- current source (co-op)
- `Scripts` is whichever is active; **1.1.6 is active now** (run A).
Same loader, same settings, same save and area for both halves, so the only
variable left is our own code.

**Dragón's ruling on dungeons (2026-09-22):** *"bonded pals shouldn't go into
dungeons, because that would imply you despawning them on the overworld and
spawning them inside the generated dungeon, thats putting ourselves into the
horses' hoves, so no - just set them as abandoned, similar to the player
teleporting to another location."* Built: a world change that is NOT a quit to
the title now remembers which Pals were following this machine's own player and
tells them once a world is readable again ("left behind and gave up on you"),
instead of dropping them silently. A guest's followers are left to the guest's
own copy. coopstage2test S15.

---

## Dragón's rulings

**R1. The relationship is per player, not per Pal** (2026-09-20): "we can never
know if the both players are actually friends or not."

**R2. A Pal already bonding with a player is immune to other players**
(2026-09-20): "should we just make it so if a pal is already bonding with a
player, it becomes immune to other player's interactions? and simply treats them
as any other normal base player? ... also that way players would not be able to
steal other players's bonds." Explicit goal attached to it: "ideally we would
not need to do more changes than what singleplayer already has."

**R3. A Pal defends itself from anyone who hits it**, including a player who is
not the one bonding it — that is the Pal acting normally, not a betrayal.

**R4. The first player keeps the Pal.** A second player interacting must not
start their own follow, and must not be able to take the bond.

### What R2 settles

R2 replaces most of the question list below with one rule, and it is the reason
this design got much smaller:

- there is one trust record per Pal, as in singleplayer, plus who it belongs to;
- no per-player trust needs to be stored, synced or drawn;
- the personality/AI conflict disappears: the Pal's AI answers to its own bond,
  exactly as it does today;
- "who gets it at 100%" answers itself: the player it was bonding with;
- the Kinship Peach race cannot happen, because a claimed Pal refuses the
  interaction before the food is consumed.

---

## Answered (Dragón, 2026-09-20)

**Q1. The claim starts at the FIRST interaction.** His own logic pointed at 50%
("bonding > friendly, so friendly shouldnt rule out other players yet"), which
matches the wording players already read, and he is right that it is the more
principled line. He chose the simpler rule when told it was cleaner, and it is
also the safer one: at 50% the claim would go to whoever lands the pet that
CROSSES the line, so a player could do all the work to 49% and lose the Pal to
someone else's single interaction — the exact theft the rule exists to prevent.
The usual worry about claiming from the first pet (running around touching every
Pal to deny them) is already handled by behaviour the mod has: a wild Pal that
is not following is forgotten the moment it despawns, and wild Pals despawn as
soon as the player leaves their area, so a claim you are not maintaining dies on
its own.

**Q2. The other player sees it in the tag** — something like "Claimed" where the
personality tag normally sits, so they understand the Pal will not respond.
Notes: the owner keeps seeing the normal tag (the tag is drawn per client); a
new word needs its 16 translations like every other tag; and this can only
appear on a client that can SEE the claim (see the measurement list below).

**Q3. A claim releases whenever the friendship bar reaches 0** — by
abandonment, betrayal, becoming scarred, any route — and when the owning player
leaves the world, where the Pal becomes abandoned and another nearby player can
claim it.

**Still to confirm with the base game:** a claimed Pal is still an ordinary wild
Pal, so anyone can still catch it with a sphere. We do not try to block that.

## MEASURED: what a GUEST can and cannot do (2026-09-20, local dedicated server)

Dragón ran his own client against a dedicated server on the same machine, as a
guest. This answers the authority questions, and one answer is a crash.

**Works on a guest (all of it local):** the mod loads (UI hooks install once the
world is up, round 38), tags and bars appear, trust is counted, the radial-menu
substitution happens, `PlayerRef` resolves the right character, and the new
claim check never misfires.

**Does NOT work — everything that touches a Pal's brain:**

- **AI presets are never written.** 46 × "no readable AISensorComponent", zero
  successes: a guest cannot reach a Pal's `PalAISensorComponent` at all. The
  personality tag is our local roll; the Pal underneath never receives it, so it
  behaves like an ordinary wild Pal. This is what Dragón saw first.
- **The pet confirmation cannot read the Pal's action** ("the pet never happened
  (Pal was busy: unknown action)"), so some interactions grant nothing.
- **The follow action does not stick.** After 50% the mod installed it and the
  server discarded it, 25 rebuilds in one minute until the per-Pal cap, then the
  recall loop started. The Pal never followed; it wandered like any wild Pal.

**THE CAPTURE HARD-CRASHES A GUEST.** Finishing a bond killed the game with the
game's own fatal assert:

```
LowLevelFatalError [PalNetworkIndividualComponent.cpp:157]
キャラクターの作成リクエストをクライアントから呼ぼうとしました
("a character-creation request was attempted from the client")
```

The sphere-less capture asks the game to create the character; only the server
may do that, and the game answers with a deliberate fatal error rather than a
refusal. **This is almost certainly the crash Toxik reported on Steam
(2026-09-19): his wife, a guest in his world, crashing a few interactions after
the "pal is following you" message — which is exactly when the join fires.** It
is a live bug in the shipped 1.1.6 for anyone playing as a guest.

**The API for the fix exists:** `AActor::HasAuthority()` (Engine.hpp 8008) on
the local player character — true in singleplayer and for the host, false for a
guest — and `UKismetSystemLibrary::IsServer(WorldContext)` (14936) as a second
opinion.

**Consequence for the design:** co-op support means "the host plays with the
mod". A guest cannot bond at all without routing every action through server
RPCs, which is a different and much larger project. Everything in the rules
above still holds for the host.

## Not decisions — things only a co-op session can answer

These shape what is buildable, so they should not be designed around guesses.

1. **Can a guest's client do any of this at all?** The host's game owns wild
   Pals. A guest's capture, AI-preset write and action push may do nothing, or
   may affect only their own screen.
2. **How does another player's client know a Pal is claimed?** Each client runs
   its own copy of the mod and its own records; nothing is shared. The one thing
   plausibly observable from both sides is that the Pal is *following* someone
   (our follow action sets a trainer). If that is readable on a guest, R2 needs
   no syncing at all; if it is not, a claim below the follow threshold cannot be
   seen by the other client.
3. **Does the host need the mod for a guest to use it?** And the reverse.
4. **Can two players pet or feed the same Pal at the same time?** The game's
   pair actions may already serialise this for us.
5. **Whose trust bars and tags appear**, given they are drawn locally.

### The solo run first: a local dedicated server

Palworld's dedicated server is a free, separate Steam tool. Running it on the
same machine and joining it with the normal game makes Dragón a GUEST in
someone else's world, which answers the authority questions without a second
person — and those are the ones that decide what is buildable.

Protocol (report each as works / does nothing / crashes):

1. UE4SS console on the client: does PalBonds load, 17 hooks, no Lua errors?
2. Do personality tags and trust bars appear over wild Pals?
3. Does petting a wild Pal register trust (the bar moves)?
4. Does a hostile Pal actually calm down at 20% — i.e. do our AI writes reach
   the world, or only our screen?
5. At 50%, does the Pal really walk behind us?
6. At 100%, does it actually join the party?
7. If a boss is reachable: does befriending it count as defeated?
8. Save `palbonds-live.log` afterwards.

**The two-player session:** both players with the mod, in a hosted world, working
through: pet a Pal as the host; pet one as the guest; both try the same Pal;
bond one to 50% as each; capture as each; hit a Pal the other is bonding; and
watch what the other player sees each time. A written checklist comes before
the session.
