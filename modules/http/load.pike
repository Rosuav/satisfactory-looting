inherit http_websocket;
inherit annotated;

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string tag) {
	return render(req, ([
		"title": "EU4 Savefiles",
		"vars": (["ws_group": ""]),
	]));
}

mapping get_state(string group) {
	array(string) files = get_dir(EU4_LOCAL_PATH + "/save games");
	array paths = (EU4_LOCAL_PATH + "/save games/") + files[*];
	sort(-1 * file_stat(paths[*])->mtime[*], files);
	return (["files": files]);
}

void websocket_cmd_load(mapping conn, mapping msg) {
	array(string) files = get_dir(EU4_LOCAL_PATH + "/save games");
	if (has_value(files, msg->filename))
		G->G->parser->process_savefile(EU4_LOCAL_PATH + "/save games/" + msg->filename);
}

protected void create(string name) {::create(name);}
