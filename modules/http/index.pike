//TODO: Make this a useful landing page for both Satisfactory and EU4
//List Satisfactory saves with links to /file/ and /session/, and EU4 tags
//with links to /tag/.

inherit http_websocket;
inherit annotated;

string ws_type = "satisfactory";
constant http_path_pattern = "/";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": (["ws_group": ""])]));
}

mapping get_state(string|int group) {
	array files = glob("*.sav", get_dir(SATIS_SAVE_PATH));
	array paths = (SATIS_SAVE_PATH + "/") + files[*];
	array mtimes = file_stat(paths[*])->?mtime;
	sort(mtimes[*] * -1, files); //Sort by modification time descending, ie newest at the top
	//Sort sessions by the most recent save file in each one
	mapping sessions = list_sessions();
	array sess = indices(sessions);
	sort(values(sessions)[*] * -1, sess);
	return ([
		"files": files,
		"sessions": sess,
	]);
}

@inotify_hook: void savefile_changed(string fn) {
	//Note that there may still be a temporary backup file here. Rather than
	//send out updates twice in quick succession, causing flicker, we delay until
	//the old file has likely been deleted.
	call_out(send_updates_all, 0.25, "");
}

protected void create(string name) {::create(name);}
