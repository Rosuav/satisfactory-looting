Satisfactory Looting
====================

Parse a Satisfactory game save file, and tell you where to find loot.

Web interface on http://localhost:1200/

Available URLs and corresponding socket groups:

* / - "" - Listing of available savefiles and sessions
* /session/Noob - "Noob*" - Savefile session starting with Noob
* /file/Noob_autosave_1 - "Noob_autosave_1" - Exact savefile with that name (".sav" optional)
* Remote saves??

On a session group, the effective savefile is always the most recently modified file
matching that base name (eg Noob*.sav). If a new file is created/updated within the group,
it will automatically be pushed out.
