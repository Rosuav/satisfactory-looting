Satisfactory Looting and Conquest
=================================

Parse a Satisfactory game save file, and tell you where to find loot.
Also study your Europa Universalis game save file, and tell you where
to find, well, lots of things.

The information can best be viewed using a web browser; the default
port is 1200 but this can be changed. It can be accessed on HTTP or
HTTPS, with the latter requiring that the necessary cert/key be in
the "../stillebot/" directory (don't ask).
TODO: Change to port 8087 when the migration is complete.

Available URLs and corresponding socket groups:

* / - "" - Listing of available savefiles and sessions
* /session/Noob - "Noob*" - Savefile session starting with Noob
* /file/Noob_autosave_1 - "Noob_autosave_1" - Exact savefile with that name (".sav" optional)
* /tag/CAS - EU4 information about Castille
* Remote saves??

On a session group, the effective savefile is always the most recently modified file
from that session. If a new file is created/updated with the same session name,
it will automatically be pushed out.

TODO: Currently, creation of map markers fails if there are no other markers in the
savefile. How can we synthesize the first ever map marker? Is there anything else that
has to be created in parallel?


Europa Universalis IV savefile parser
-------------------------------------

Keep an eye on the state of the game, at least as frequently as your
autosaves happen. Any non-ironman save file should be able to be read
by this script; if you're playing ironman, you probably shouldn't be
using this sort of tool anyway!

Mods are supported and recognized but may cause issues. Please file
bug reports if you find problems.

Both compressed and uncompressed save files can be read.

TODO: Document the key sender and consequent "go to province" feature.

TODO: Add an alert to recommend Strong Duchies if you don't have it, have 2+ march/vassal/PU, and either have >50% LD or over slots
TODO: If annexing a subject, replace its date with progress (X/Y) and maybe rate (Z/month)
TODO: Alert if idle colonist
TODO: War progress.
- "Army strength" is defined as sum(unit.men * unit.morale for army in country for unit in army) + country.max_morale * country.manpower
- Plot each country's army strength in the table with a graph showing its change from one save to the next
- Graph the progression of the war as the sum of each side's army strengths
- Is it possible to show history of battles and how they affected war strength? At very least, show every save sighted.

QUIRK: Sighted an issue with the savefile having an arraymap in it, causing the fast parser
to fail. It happened in the "history" of a now-defunct colonial nation (not sure if it was a
problem while the nation existed), with an empty {} inserted prior to the date-keyed entries.
- The slow parser still worked, so this wasn't a major problem, but it's a nuisance.
- Manually hacking out the empty array from the start fixed the problem, and a subsequent
  save worked fine.
- Sighted a second time 20240722. Does this recur?

TODO: Combat prediction dialog. Select an opposing nation to use their stats, but also show all of the stats broken down.
Key in, or select, an army for each side (for now, assume no merging of stacks).
Assume a midrange combat dice roll, which can be forced in-game with "combat_dice N" (5?)
Predict how combat will go. Test it against the in-game behaviour.
Maybe show red highlights for things that are working against us, green for things that are in our favour?


Test nations at 2919 Luziana and 2892 Araxas

1. Recreate the calculations, using a fixed dice roll of 5
2. Show the impact of changing each modifier. Rank the modifiers by how much effect each would have if changed.
3. Make recommendations about potential changes

TODO: Improve mod support.
May end up switching all definition loading to parse_config_dir even if there's normally only the
one file, since it makes mod handling easier. Will need to handle a replace_path block in the mod
definition, possibly also a dependencies block. See: https://eu4.paradoxwikis.com/Mod_structure



Falsifiable hypotheses to test
------------------------------

* Hypothesis: Stuff gets added to the save file in chunks. A chunk gets triggered (by seeing it or
  getting near it or something) and everything in that chunk gets added.
* Hypothesis: Staying put and building a Radar Tower will cause stuff to get added due to being
  able to see it.
* Hypothesis: Chunks are rigid and there aren't too many of them.

Enumerate all fields and the MapProperty. Count stuff.

Some object classes seem only to be in the save file if we've been near them. Includes:
NutBush/BerryBush/Shroom, CrashSiteDebris, MercerShrine, Crystal, CreatureSpawner

Is BP_Ship_C just another piece of debris? See if it's removable - or more specifically, see if
clearing a crash site gets rid of one of them.
