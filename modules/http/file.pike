inherit http_websocket;

constant http_path_pattern = "/file/%[^/]";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string filename) {
	return render(req, (["vars": (["ws_group": filename, "item_names": ITEM_NAMES])]));
}

//Validation is done once per socket, and after that, we assume that the file is still valid.
//It may have been deleted, but at least there's no easy abuses with "../" etc.
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!check_savefile_name(msg->group)) return "Not a known save file.";
}

mapping get_state(string|int group) {
	return cached_parse_savefile(group);
}
