PalBonds
========

Earn a wild Pal's trust instead of throwing a sphere at it.

Pet it, feed it, play with it. If it decides it likes you, it will start
following you around, defend you when you are attacked, and eventually choose
to join your party on its own. No sphere is ever thrown.


WHAT IT ADDS
------------

  * Pet, feed and play with WILD Pals through the normal radial menu ("4"),
    the same one you already use for your own Pals.

  * A trust bar under a wild Pal's health bar, showing how close it is to
    bonding with you.

  * Personality tags. Every wild Pal is rolled into a personality that changes
    how it reacts to you:

        Normal    behaves the way its species normally does
        Curious   stops and looks at you as you approach
        Timid     runs away when you get close
        Aloof     ignores you almost completely
        Grumpy    postures at you, and joins in if its own kind starts a fight
        Hostile   attacks you on sight
        Feral     attacks anything on sight, not just you

    Once a Pal starts warming to you the tag changes to "Friendly", then
    "Bonding" as it gets closer to joining.

  * Bonded Pals follow you, stay behind you rather than running ahead, and hold
    still while you are looking at them so you can actually interact with them.

  * They fight for you. If something attacks you, your bonded Pals will go
    after it.

  * A Pal that joins you this way arrives already fond of you, with a large
    friendship head start.


CONTROLS
--------

  4    Radial menu - pet and feed a wild Pal you are looking at
  F8   Play with the wild Pal you are looking at
  F9   Show / hide the personality tags

  Stand within about 5 metres and look directly at a Pal for any of these.


REQUIREMENTS
------------

  Palworld, and UE4SS.

  If you installed this from the Steam Workshop, UE4SS is listed as a required
  item and Steam will have installed it for you.

  Installing by hand instead: you need UE4SS (the Palworld/experimental build)
  set up first, then drop the PalBonds folder into

      Palworld/Mods/NativeMods/UE4SS/Mods/

  and add a line reading

      PalBonds : 1

  to mods.txt in that same Mods folder.


THINGS WORTH KNOWING
--------------------

  * Your own Pals are never affected. Party members, Palbox Pals and base
    workers are all excluded - this only ever touches genuinely wild Pals.

  * Bonding takes real time. Interactions give the biggest push, but a Pal
    following you also warms to you slowly just by being near you.

  * Distance matters. A bonded Pal that gets too far from you loses its trust
    and goes back to being wild, so do not wander off and leave it behind.

  * Fights get messy. Bonded Pals will defend you, but several of them swinging
    at the same enemy can catch each other in the crossfire. Starting a fight
    with six followers around you is a choice, and it will show.

  * A Pal that loses all its trust flees for good and cannot be bonded again.

  * The personality tag toggle (F9) lasts for the current session only. It
    comes back on the next time you launch the game.


TROUBLESHOOTING
---------------

  Nothing happens when I press 4 / F8 / F9
      Check UE4SS is actually loading. Its console window should appear when
      the game starts. If it does not, UE4SS is not installed correctly and no
      mod that depends on it will work.

  I want to report a bug
      Open Scripts/Logger.lua and change

          local DEBUG_LOGGING = false
      to
          local DEBUG_LOGGING = true

      Play until the problem happens, then attach palbonds-live.log from the
      mod's folder. Turn it back off afterwards - it writes to disk constantly
      and the file grows for as long as you play.


CREDITS
-------

  Made by Dragon.
  Built with Claude (Anthropic).

  Thanks to the Palworld modding community, and to the authors of UE4SS.
