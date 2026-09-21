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
