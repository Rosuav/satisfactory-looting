inherit annotated;

//Manage information about savegame sessions
//This necessitates loading every save file. If this becomes a problem, spin it off onto another
//thread or something. Maybe a separate subprocess the way the EU4 parser did.

@retain: mapping(string:mapping) sessions = ([]);

void load_sessions() {
	foreach (glob("*.sav", get_dir(SAVE_PATH)), string fn) {
		mapping savefile = cached_parse_savefile(fn);
		string s = savefile->session; if (!s) continue; //File has vanished, or can't be parsed
		if (!sessions[s]) sessions[s] = ([]);
		sessions[s][fn] = savefile->mtime;
	}
}

@inotify_hook: void savefile_changed(string fn) {
	mapping savefile = cached_parse_savefile(fn);
	//Purge it from all previous sessions. Most likely this won't matter, as it's highly unlikely
	//that a file will move from one session to another, but it's possible and would be confusing.
	m_delete(values(sessions)[*], fn);
	string s = savefile->session;
	if (s) {
		if (!sessions[s]) sessions[s] = ([]);
		sessions[s][fn] = savefile->mtime;
	}
}

int maxvalue(mapping x) {return max(@values(x));}

@export: mapping(string:int) list_sessions() {
	//Clean up the list as needed
	foreach (indices(sessions), string sess)
		if (!sizeof(sessions[sess])) m_delete(sessions, sess);
	//Return just the sessions, not the individual files
	return mkmapping(indices(sessions), maxvalue(values(sessions)[*]));
}

protected void create(string name) {
	::create(name);
	if (!sizeof(sessions)) load_sessions();
}
