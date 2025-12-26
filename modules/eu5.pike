//Various functions for parsing and analyzing EU5 savefiles.
inherit annotated;

void load_savefile(string fn) {
	//TODO
}

@inotify_hook: void savefile_changed(string cat, string fn) {if (cat == "eu4") load_savefile(fn);}
