Satisfactory Looting and Conquest
=================================

Parse a Satisfactory game save file, and tell you where to find loot.
Also study your Europa Universalis game save file, and tell you where
to find, well, lots of things.

Web interface on http://localhost:1200/ <== TODO: change to 8087

Available URLs and corresponding socket groups:

* / - "" - Listing of available savefiles and sessions
* /session/Noob - "Noob*" - Savefile session starting with Noob
* /file/Noob_autosave_1 - "Noob_autosave_1" - Exact savefile with that name (".sav" optional)
* /tag/CAS - EU4 information about Castille
* Remote saves??

On a session group, the effective savefile is always the most recently modified file
matching that base name (eg Noob*.sav). If a new file is created/updated within the group,
it will automatically be pushed out.
