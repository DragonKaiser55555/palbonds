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

  * Pals forgive you - once. The first time a Pal's trust reaches 20% it lets
    go of any anger towards you: it follows you for a moment, then goes back
    to its own business as a Friendly Pal.

  * Bonded Pals follow you, stay behind you rather than running ahead, and hold
    still while you are looking at them so you can actually interact with them.

  * They fight for you. If something attacks you, your bonded Pals will go
    after it. And if something attacks one of them while you are busy, that
    Pal fights back on its own.

  * Food matters. Feeding gives more trust the rarer the food is. Kinship
    Peaches are special - they can only be found, and they count for a lot.

  * Bosses are harder. On top of the usual level scaling, every boss - alphas,
    tower bosses, predators and raid bosses - needs twice the trust before it
    will join you. Even raid bosses can be won over, if you survive long enough.
    A boss shows its trust bar and personality tag under its big health bar
    at the top of the screen. Winning a boss over also counts as beating it:
    the first time, the game gives you the same rewards as defeating it.

  * A Pal that joins you this way arrives already fond of you, with a large
    friendship head start.

  * Tags and messages follow your game's language, in every language
    Palworld offers.

  * A settings file lets you tune the mod to your liking (see SETTINGS below).


CONTROLS
--------

  4    Radial menu - pet and feed a wild Pal you are looking at
  F8   Play with the wild Pal you are looking at
  F9   Show / hide the personality tags
  F10  Pause / resume passive bonding (followers stop growing closer,
       so you can keep a group instead of them joining your party)

  Stand within about 5 metres and look directly at a Pal for any of these.
  F8, F9 and F10 can be changed in the settings file.


SETTINGS
--------

  The first time you start the game with PalBonds, it creates a settings
  file, PalBonds_settings.lua. In it you can change:

    - how much trust petting, playing and feeding give (each food rarity
      and Kinship Peaches included)
    - how fast your followers warm up to you on their own
    - how much friendship a Pal gets when it joins you
    - how often each personality appears
    - whether the personality tags start shown or hidden
    - the keys for Play, the tags and passive bonding
    - the language of the tags and messages (it follows your game's
      language by default)

  Where to find it: in Steam, right-click Palworld > Manage > Browse local
  files, then open

    - UE4SS from the Steam Workshop:
          Mods/NativeMods/UE4SS/Mods/shared/PalBonds_settings.lua
    - UE4SS installed by hand:
          Pal/Binaries/Win64/ue4ss/Mods/shared/PalBonds_settings.lua

  How to edit it:

    1. Close the game. The file is only read when the game starts.
    2. Open the file with Notepad.
    3. Change a number (or the text in quotes, for keys and the language).
       Every setting has a short explanation above it. Keep the comma at the
       end of the line.
    4. Save, and start the game.

  A value the mod can't use falls back to its default, and the UE4SS console
  says which one. If the file gets messed up, delete it: a fresh one with
  every default is made the next time you start the game.

  When an update adds a new setting, it is added to the file you already have,
  at the end, with your own values left exactly as they were.

  An in-game settings screen is planned for a future update.


REQUIREMENTS
------------

  Palworld, and UE4SS - the September 2026 build or newer. Older builds have
  crashes of their own that look exactly like a mod bug.

  If you installed this from the Steam Workshop, UE4SS is listed as a required
  item and Steam will have installed it for you.

  Installing by hand instead (for example from Nexus Mods): set up UE4SS first,
  then drop the whole PalBonds folder into the Mods folder of the UE4SS you use.

    - UE4SS Experimental (Palworld), installed by hand into the game folder:

          Palworld/Pal/Binaries/Win64/ue4ss/Mods/

    - UE4SS from the Steam Workshop:

          Palworld/Mods/NativeMods/UE4SS/Mods/

  Use ONE UE4SS, never both at once - the game crashes if two copies load.

  The PalBonds folder includes enabled.txt, which is normally all UE4SS needs.
  If the mod still does not load, add a line reading

      PalBonds : 1

  to mods.txt in that same Mods folder.


THINGS WORTH KNOWING
--------------------

  * Singleplayer and your own hosted worlds only. Do not use mods on official
    servers.

  * Your own Pals are never affected. Party members, Palbox Pals and base
    workers are all excluded - this only ever touches genuinely wild Pals.

  * Bonding takes real time. Interactions give the biggest push, but a Pal
    following you also warms to you slowly just by being near you.

  * Distance matters. A bonded Pal that gets too far from you loses its trust
    and goes back to being wild, so do not wander off and leave it behind.

  * Fights get messy. Bonded Pals will defend you, but several of them swinging
    at the same enemy can catch each other in the crossfire. Starting a fight
    with six followers around you is a choice, and it will show.

  * Hitting a Pal that is not bonded yet (under half of its trust bar) drops
    its trust to zero, and it goes back to its old personality. It will not
    forgive you a second time.

  * Hitting a bonded Pal costs it half of its trust bar, and it lets you know.
    A bonded Pal that loses all its trust flees for good and cannot be bonded
    again.

  * A bonded Pal is still a wild Pal until it joins you, so the game can
    still despawn it when you leave its area behind. If that happens, you
    get a message saying it gave up on you.

  * The personality tag toggle (F9) lasts for the current session only. The
    next time you launch the game the tags go back to what the settings file
    says (shown, unless you set ShowPersonalityTags to 0).


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

      Play until the problem happens, then attach palbonds-live.log. It is
      written next to the game's executable:

          Palworld/Pal/Binaries/Win64/palbonds-live.log

      Turn it back off afterwards - it writes to disk constantly and the file
      grows for as long as you play.


CREDITS
-------

  Made by Dragon.
  Built with Claude (Anthropic).

  Thanks to the Palworld modding community, and to the authors of UE4SS.
