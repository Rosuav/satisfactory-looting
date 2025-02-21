inherit http_websocket;
inherit annotated;

string ws_type = "satisfactory";
constant http_path_pattern = "/";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": (["ws_group": ""])]));
}

mapping get_state(string|int group) {
	array files = glob("*.sav", get_dir(SAVE_PATH));
	array paths = (SAVE_PATH + "/") + files[*];
	array mtimes = file_stat(paths[*])->?mtime;
	sort(mtimes[*] * -1, files); //Sort by modification time descending, ie newest at the top
	//HACK: Instead of reading every file to see what its session name is,
	//we assume two things: Firstly, every session will have at least one autosave in it;
	//and secondly, all save files for a session (and no others) begin with that name.
	//This means that a brand new session won't show up until its first autosave, but that
	//if you make a dedicated save as part of an existing session, it should be fine.
	array sessions = ({ });
	foreach (files, string fn) {
		if (has_suffix(fn, "_autosave_0.sav") || has_suffix(fn, "_autosave_1.sav") || has_suffix(fn, "_autosave_2.sav")) {
			string sess = fn[..<15];
			if (!has_value(sessions, sess)) sessions += ({sess});
		}
	}
	return ([
		"files": files,
		"sessions": sessions,
	]);
}

@inotify_hook: void savefile_changed(string fn) {
	//Note that there may still be a temporary backup file here. Rather than
	//send out updates twice in quick succession, causing flicker, we delay until
	//the old file has likely been deleted.
	call_out(send_updates_all, 0.25, "");
}

protected void create(string name) {::create(name);}
