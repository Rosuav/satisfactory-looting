inherit http_websocket;

string ws_type = "satisfactory";
constant http_path_pattern = "/";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": (["ws_group": ""])]));
}

mapping get_state(string|int group) {
	array files = glob("*.sav", get_dir(SAVEGAME_DIR));
	return ([
		"files": files,
	]);
}
