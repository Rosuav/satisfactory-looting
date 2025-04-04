inherit http_websocket;
inherit annotated;

constant http_path_pattern = "/file/%[^/]";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string filename) {
	return render(req, ([
		"title": "Satisfactory Looting",
		"vars": ([
			"ws_group": Protocols.HTTP.Server.http_decode_string(filename),
		]),
	]));
}

//Validation is done once per socket, and after that, we assume that the file is still valid.
//It may have been deleted, but at least there's no easy abuses with "../" etc.
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!check_savefile_name(msg->group)) return "Not a known save file.";
}

mapping get_state(string|int group) {
	mapping savefile = cached_parse_savefile(group);
	return savefile->mtime && savefile; //If the file doesn't exist, don't return any state at all, it's not useful.
}

@inotify_hook: void savefile_changed(string cat, string fn) {
	if (cat == "satis") send_updates_all(fn);
}

mapping websocket_cmd_findloot(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array loc = msg->refloc;
	if (sizeof(loc) == 2) loc += ({0.0}); //Z coordinate is optional
	if (sizeof(loc) != 3) return 0;
	foreach (loc, mixed coord) if (!intp(coord) && !floatp(coord)) return 0;
	if (!stringp(msg->itemtype)) return 0;
	mapping savefile = annotate_map(conn->group, ({
		({"find_loot", loc, msg->itemtype}),
		({"autocrop"}),
		msg->save && ({"save"}),
	}));

	return ([
		"cmd": "findloot",
		"img": "data:image/png;base64," + MIME.encode_base64(Image.PNG.encode(savefile->annot_map)),
		"found": savefile->found,
	]);
}

protected void create(string name) {::create(name);}
