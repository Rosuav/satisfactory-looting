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

TODO: Add "All nearby" loot type, mainly for crash sites. Find any type of loot but
only within the "nearby" threshold (100m?), don't stop at 3.

TODO: Rerollable flag??
TODO: Make new pristine file for 1.1 - spawners may have changed


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

TODO: Count the total number of provinces with the local_fortress modifier, and how many you have.
If I'm understanding correctly, the total will only ever increase. (It's the 25% local defense till end of game.)


NOTE: EU5 is imminent and a lot of the above TODOs will be irrelevant unless they apply also to EU5.

TODO: Have a "for=" parameter eg /tag/Rosuav?for=Stephen+Angelico
Clicking on a province will send the GOTO message to your own tag, but all display details will be
for the target. If I ever add authentication to this, you would authenticate with your own tag,
with the target granting you permission to view it.


Europa Universalis V
--------------------

This is all plans and TODOs, and may change before implementation.

* Saves are "unreadable" if you aren't in debug mode. Are they encrypted or is it something simple?
  They looked like maybe they were compressed. Explore this. (This is w/o Ironman which will of
  course encrypt.)
* Make a new endpoint /eu5/ and maybe eventually shift /session to /satisfactory ? Not using /file.
* A lot of things will be unnecessary since they're now in core, so this will start fresh with the
  things that I deem necessary during actual gameplay.

Savefile notes
* The beginning of a save file is eg "SAV02003fb9bd370004e75d00000000\n" if text
* The beginning of a save file is eg "SAV0203d64d49f0000634fd00000000\n" if binary
* File begins "SAV", seems to be fixed
* Next two are possibly a version number? Was "01" for earlier files, is now "02". I don't think
  this has anything to do with Ironman (which I'm not going to concern myself with greatly, but
  it would be nice if I could at least recognize them and say "hey, this is an ironman save").
* Next two are "03" for binary, "00" for text. Might have more flags.
* Then eight digits of a save ID of some sort, or maybe a checksum: "3fb9bd37". It changes from 
  one save to another within a campaign.
* Four digits "0004" for text, "0006" for binary
* Four digits of some kind of checksum, but not the same one displayed to the user
* Eight zeroes. All of these are ASCII lowercase hex.
* Newline - even in binary format.

* Every value appears to have an introduction consisting of a two-byte value likely representing
  a keyword.
  - 0000 null?? Seems to be followed by another 00 00??
  - 0003 ?? array entry?
  - 000f ?? array entry, no keyword?
  - 0004 End of mapping/array
  - 006e "speed"
  - 00ee "version"
  - 00f0 "data"
  - 0384 "flag"
  - 0555 "variables"
  - 06b3 "random_seed"
  - 06b4 "random_count"
  - 06b5 "date"
  - 096e "playthrough_id"
  - 096f "playthrough_name"
  - 0971 "save_label"
  - 09de "metadata"
  - 2ce7 "enabled_dlcs"
  - 2dc0 "locations"
  - 2f44 "current_age"
  - 3234 "start_of_day"
  - 3237 "compatibility"
  - 3238 "locations_hash"
  - 3477 "code_version_info"
  - 3478 "code_hash_long"
  - 3479 "code_hash_short"
  - 347a "code_timestamp"
  - 347b "code_branch"
  - 347c "game_code_info"
  - 347d "engine_code_info"
  - 35c3 "code_commit"
* Then there's a four byte value, or two two-byte values, which may be a type marker
  - "01 00 03 00" mapping/array
  - "01 00 0c 00" date? or 32-bit integer?
  - "01 00 9c 02" integer (32-bit)
  - "01 00 0f 00" string
  - "01 00 14 00" integer (32-bit) - maybe unsigned?
  - "01 00 40 0d" Take the next string from string_lookup
* Strings are stored %-2H and are probably UTF-8 but I haven't confirmed this
* Date might be stored as a number of hours since game start??? 0x036012e8 means 1464-5-18 at 16:00
* Start date of 1337-4-1 and is 0x034f14a8


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
- Seems it is, I think. So it's not particularly useful.
