inherit annotated;

//Manage information about savegame sessions
//This necessitates loading every save file. If this becomes a problem, spin it off onto another
//thread or something. Maybe a separate subprocess the way the EU4 parser did.

@retain: mapping(string:mapping) session_mtimes = ([]);
@retain: mapping(string:string) file_sessions = ([]);

void load_sessions() {
	foreach (glob("*.sav", get_dir(SATIS_SAVE_PATH)), string fn) {
		mapping savefile = cached_parse_savefile(fn);
		string s = savefile->session; if (!s) continue; //File has vanished, or can't be parsed
		if (!session_mtimes[s]) session_mtimes[s] = ([]);
		session_mtimes[s][fn] = savefile->mtime;
		file_sessions[fn] = s;
	}
}

@inotify_hook: void savefile_changed(string cat, string fn) {
	if (cat != "satis" || !has_suffix(fn, ".sav")) return;
	mapping savefile = cached_parse_savefile(fn);
	//Purge it from the previous sessions. Most likely this will only happen on deletion, as it's
	//highly unlikely that a file will move sessions, but it's possible and would be confusing.
	//Note that we never remove from file_sessions[]. It's the last-sighted session for that name.
	if (file_sessions[fn]) m_delete(session_mtimes[file_sessions[fn]], fn);
	string s = savefile->session;
	if (s) {
		if (!session_mtimes[s]) session_mtimes[s] = ([]);
		session_mtimes[s][fn] = savefile->mtime;
	}
}

int maxvalue(mapping x) {return max(@values(x));}

@export: mapping(string:int) list_sessions() {
	//Clean up the list as needed
	foreach (indices(session_mtimes), string sess)
		if (!sizeof(session_mtimes[sess])) m_delete(session_mtimes, sess);
	//Return just the sessions, not the individual files
	return mkmapping(indices(session_mtimes), maxvalue(values(session_mtimes)[*]));
}

@export: string|zero get_session_latest(string sess) {
	string fn; int mtime;
	foreach (session_mtimes[sess] || ([]); string f; int m)
		if (m > mtime) {fn = f; mtime = m;}
	//If there aren't any, fn will still be zero.
	return fn;
}

protected void create(string name) {
	::create(name);
	if (!sizeof(session_mtimes)) load_sessions();
}
