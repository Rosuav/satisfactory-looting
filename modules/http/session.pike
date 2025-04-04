inherit http_websocket;
inherit annotated;

constant http_path_pattern = "/session/%[^/]";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string session) {
	return render(req, ([
		"title": "Satisfactory Looting",
		"vars": ([
			"ws_group": Protocols.HTTP.Server.http_decode_string(session),
			"ws_code": "file",
		]),
	]));
}

//Note that we don't bother validating the socket; since the state is safe, you'll just get null state back.
mapping get_state(string|int group) {
	string fn = get_session_latest(group);
	if (!fn) return 0;
	mapping savefile = cached_parse_savefile(fn);
	return savefile->mtime && savefile;
}

@inotify_hook: void savefile_changed(string cat, string fn) {if (cat == "satis") call_out(update_by_fn, 0.125, fn);}
void update_by_fn(string fn) {
	if (!has_suffix(fn, ".sav")) return;
	if (string sess = G->G->file_sessions[fn]) send_updates_all(sess);
}

mapping websocket_cmd_findloot(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array loc = msg->refloc;
	if (sizeof(loc) == 2) loc += ({0.0}); //Z coordinate is optional
	if (sizeof(loc) != 3) return 0;
	foreach (loc, mixed coord) if (!intp(coord) && !floatp(coord)) return 0;
	if (!stringp(msg->itemtype)) return 0;
	mapping savefile = annotate_map(get_session_latest(conn->group), ({
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
