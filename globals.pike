protected void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	foreach (Program.annotations(this_program); string anno;)
		if (stringp(anno) && sscanf(anno, "G->G->%s", string gl) && gl)
			if (!G->G[gl]) G->G[gl] = ([]);
	load_satisfactory_l10n("en-US");
	load_eu5_l10n("english");
}

//TODO: Figure out a way to ask Steam where a game is installed, and what the active user is
constant SATIS_SAVE_PATH = "../.steam/steam/steamapps/compatdata/526870/pfx/drive_c/users/steamuser/Local Settings/Application Data/FactoryGame/Saved/SaveGames/76561198043731689";
constant SATIS_PROGRAM_PATH = "../.steam/steamapps/common/Satisfactory";
constant EU4_LOCAL_PATH = "../.local/share/Paradox Interactive/Europa Universalis IV";
//constant EU4_SAVE_PATH = LOCAL_PATH + "/save games"; //Not actually a constant
constant EU4_PROGRAM_PATH = "../.steam/steam/steamapps/common/Europa Universalis IV"; //Append /map or /common etc to access useful data files
constant EU5_PROGRAM_PATH = "../.steam/steam/steamapps/common/Europa Universalis V";
constant EU5_SAVE_PATH = "../.steam/steam/steamapps/compatdata/3450310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Europa Universalis V/save games";

constant CONFIG_FILE = "preferences.json";

//If anything mutates this, call persist_save().
mapping persist = Standards.JSON.decode_utf8(Stdio.read_file(CONFIG_FILE) || "{}");
void persist_save() {
	//Clean out any empty tag prefs, which just clutter up the config file for nothing
	foreach (indices(persist->tag_preferences), string tag) {
		mapping tp = persist->tag_preferences[tag];
		if (tp->search == "") m_delete(tp, "search");
		if (tp->pinned_provinces && !sizeof(tp->pinned_provinces)) m_delete(tp, "pinned_provinces");
		if (!sizeof(tp)) m_delete(persist->tag_preferences, tag);
	}
	Stdio.write_file(CONFIG_FILE, Standards.JSON.encode(persist, 5));
}

void load_satisfactory_l10n(string lang) {
	//Is this always present?
	string fn = SATIS_PROGRAM_PATH + "/CommunityResources/Docs/" + lang + ".json";
	//The l10n files are stored in UTF-16. For some reason.
	//The file consists of an array of native classes and their corresponding collections
	//of internal classes. We don't care about the distinctions and will just map an
	//internal class name to its display name.
	array natives = Standards.JSON.decode(unicode_to_string(Stdio.read_file(fn)));
	mapping l10n = G->G->satis_l10n = ([
		//Special-case anything that isn't in the files themselves.
		"Desc_CartridgeSmart_C": "Rifle Smartridge",
	]);
	foreach (natives, mapping native) {
		//native->NativeClass is the path to the native class
		foreach (native->Classes, mapping cls) {
			l10n[cls->ClassName] = cls->mDisplayName;
			//There's a bunch of other info too, which might be useful for colorization.
		}
	}
}

//Simplified YAML parsing. Seems enough to handle EU4/EU5 localization files.
void parse_localisation(string data, mapping L10n) {
	array lines = utf8_to_string("#" + data) / "\n"; //Hack: Pretend that the heading line is a comment
	foreach (lines, string line) {
		sscanf(line, "%s#", line);
		sscanf(line, " %s:%*[0-9 ]\"%s\"", string key, string val);
		if (key && val) L10n[key] = val;
	}
}

void l10n_scan_dir(string dir, mapping xlat) {
	foreach (sort(get_dir(dir) || ({ })), string fn) {
		string path = dir + "/" + fn;
		if (file_stat(path)->isdir) l10n_scan_dir(path, xlat);
		else parse_localisation(Stdio.read_file(path), xlat);
	}
}

void load_eu5_l10n(string lang) {
	mapping xlat = ([]);
	foreach (sort(get_dir(EU5_PROGRAM_PATH + "/game")), string section)
		l10n_scan_dir(EU5_PROGRAM_PATH + "/game/" + section + "/localization/" + lang, xlat);
	G->G->EU5_L10N = xlat;
}

//Handle potentially-asynchronous results. Can be used to paper over a distinction between
//async and sync functions (forcing them all to be async).
__async__ mixed spawn_task(mixed gen) {
	return objectp(gen) && gen->on_await ? await(gen) : gen;
}

@"G->G->bouncers";
void register_bouncer(function f) {G->G->bouncers[sprintf("%O", f)] = f;}
function|void bounce(function f) {
	function current = G->G->bouncers[sprintf("%O", f)];
	if (current != f) return current;
	return UNDEFINED;
}

@"G->G->exports";
class annotated {
	protected void create(string name) {
		//TODO: Find a good way to move prev handling into the export class or object below
		mapping prev = G->G->exports[name];
		G->G->exports[name] = ([]);
		foreach (Array.transpose(({indices(this), annotations(this)})), [string key, mixed ann]) {
			if (ann) foreach (indices(ann), mixed anno) {
				if (functionp(anno)) anno(this, name, key);
			}
		}
		//Purge any that are no longer being exported (handles renames etc)
		if (prev) foreach (prev - G->G->exports[name]; string key;)
			add_constant(key);
	}
}
void export(object module, string modname, string key) {
	add_constant(key, module[key]);
	G->G->exports[modname][key] = 1;
}

void retain(object module, string modname, string key) {
	if (!G->G[key]) G->G[key] = module[key];
	else module[key] = G->G[key];
}

@"G->G->inotify_hooks";
void inotify_hook(object module, string modname, string key) {
	G->G->inotify_hooks[modname] = module[key];
}

@"G->G->template_defaults";
mapping(string:mixed)|string render_template(string template, mapping replacements)
{
	//No Markdown support here; inline HTML will be inserted into an HTML template, that's all
	string content;
	if (has_value(template, '\n')) {content = template; template = "<inline>.html";}
	else content = utf8_to_string(Stdio.read_file("templates/" + template));
	if (!content) error("Unable to load templates/" + template + "\n");
	array pieces = content / "$$";
	if (!(sizeof(pieces) & 1)) error("Mismatched $$ in templates/" + template + "\n");
	function static_fn = G->G->template_defaults["static"];
	if (replacements->vars) {
		//Set vars to a mapping of variable name to value and they'll be made available to JS.
		//To trigger automatic synchronization, set ws_type to a keyword, and ws_group to a string or int.
		//Provide a static file that exports render(state). By default, that's the same name
		//as the ws_type (so if ws_type is "raidfinder", it'll load "raidfinder.js"), but
		//this can be overridden by explicitly setting ws_code.
		string jsonvar(array nv) {return sprintf("let %s = %s;", nv[0], Standards.JSON.encode(nv[1], 5));}
		array vars = jsonvar(sort((array)(replacements->vars - (["ws_code":""])))[*]);
		if (replacements->vars->ws_type) {
			string code = replacements->vars->ws_code || replacements->vars->ws_type;
			if (!has_suffix(code, ".js")) code += ".js";
			vars += ({
				jsonvar(({"ws_code", static_fn(code)})),
				"let ws_sync = null; import('" + static_fn("ws_sync.js") + "').then(m => ws_sync = m);",
			});
		}
		replacements->js_variables = "<script>" + vars * "\n" + "</script>";
	}
	replacements->head_scripts = "";
	//Set js to a string or an array of strings, and those files will be loaded.
	if (replacements->js) foreach (Array.arrayify(replacements->js), string fn) {
		if (!has_value(fn, ".")) fn += ".js";
		replacements->head_scripts += "<script type=module src=\"" + static_fn(fn) + "\"></script>\n";
	}
	//Similarly for CSS files.
	if (replacements->css) foreach (Array.arrayify(replacements->css), string fn) {
		if (!has_value(fn, ".")) fn += ".css";
		replacements->head_scripts += "<link rel=\"stylesheet\" href=\"" + static_fn(fn) + "\">\n";
	}

	for (int i = 1; i < sizeof(pieces); i += 2)
	{
		string token = pieces[i];
		if (token == "") {pieces[i] = "$$"; continue;} //Escape a $$ by doubling it ($$$$)
		if (sizeof(token) > 200) //TODO: Check more reliably for it being a 'token'
			error("Invalid token name %O in templates/%s - possible mismatched marker\n",
				"$$" + token[..80] + "$$", template);
		sscanf(token, "%s||%s", token, string dflt);
		int trim_before = has_prefix(token, ">");
		int trim_after  = has_suffix(token, "<");
		token = token[trim_before..<trim_after];
		string|function repl = replacements[token] || G->G->template_defaults[token];
		if (!repl)
		{
			if (dflt) pieces[i] = dflt;
			else error("Token %O not found in templates/%s\n", "$$" + token + "$$", template);
		}
		else if (callablep(repl)) pieces[i] = ((function)repl)(dflt);
		else pieces[i] = repl;
		if (pieces[i] == "")
		{
			if (trim_before) pieces[i-1] = String.trim("^" + pieces[i-1])[1..];
			if (trim_after)  pieces[i+1] = String.trim(pieces[i+1] + "$")[..<1];
		}
	}
	content = pieces * "";
	return ([
		"data": string_to_utf8(content),
		"type": "text/html; charset=\"UTF-8\"",
	]);
}

@"G->G->http_endpoints";
class http_endpoint
{
	//Set to an sscanf pattern to handle multiple request URIs. Otherwise will handle just "/myname".
	constant http_path_pattern = 0;
	//May be a continue function or may return a Future. May also return a string (recommended for
	//debugging only, as it'll be an ugly text/plain document).
	mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) { }

	protected void create(string name) {
		if (http_path_pattern) G->G->http_endpoints[http_path_pattern] = http_request;
		else G->G->http_endpoints[name] = http_request;
	}
}

//An HTTP handler that uses websockets
@"G->G->websocket_types"; @"G->G->websocket_groups";
class http_websocket {
	inherit http_endpoint;

	string ws_type; //Will be set in create(), but can be overridden (also in create) if necessary
	string page_html = "PLEASE FILL ME IN";
	mapping(string|int:array(object)) websocket_groups;

	//Generate a state mapping for a particular connection group. If state is 0, no
	//information is sent; otherwise it must be a JSON-compatible mapping. An ID will
	//be given if update_one was called, otherwise it will be 0. Type is rarely needed
	//but is used only in conjunction with an ID.
	mapping|Concurrent.Future get_state(string|int group, string|void id, string|void type) { }
	//__async__ mapping get_state(string|int group, string|void id, string|void type) { } //Alternate (equivalent) signature

	//Override to validate any init requests. Return 0 to allow the socket
	//establishment, or an error message.
	string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) { }

	//If msg->cmd is "init", it's a new client and base processing has already been done.
	//If msg is 0, a client has disconnected and is about to be removed from its group.
	//Use websocket_groups[conn->group] to find an array of related sockets.
	void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (msg->cmd == "refresh" || msg->cmd == "init") _send_updates(({conn->sock}), conn->group);
		if (function f = this["websocket_cmd_" + msg->cmd]) {
			mixed ret = f(conn, msg);
			if (ret) spawn_task(ret)->then() {if (__ARGS__[0]) send_msg(conn, __ARGS__[0]);};
		}
	}

	void websocket_cmd_chgrp(mapping(string:mixed) conn, mapping(string:mixed) msg) {
		if (string err = websocket_validate(conn, msg)) {
			conn->sock->send_text(Standards.JSON.encode((["cmd": "*DC*", "error": err])));
			conn->sock->close();
			return;
		}
		websocket_groups[conn->group] -= ({conn->sock});
		websocket_groups[conn->group = msg->group] += ({conn->sock});
		_send_updates(({conn->sock}), conn->group);
	}

	void _low_send_updates(mapping resp, array(object) socks) {
		if (!resp) return;
		string text = Standards.JSON.encode(resp | (["cmd": "update"]), 4);
		foreach (socks, object sock)
			if (sock && sock->state == 1) sock->send_text(text);
	}
	void _send_updates(array(object) socks, string|int group, mapping|void data) {
		if (!data) data = get_state(group);
		if (objectp(data) && data->then) data->then() {_low_send_updates(__ARGS__[0], socks);};
		else _low_send_updates(data, socks);
	}

	void send_msg(mapping(string:mixed) conn, mapping msg) {
		if (conn->sock && conn->sock->state == 1) conn->sock->send_text(Standards.JSON.encode(msg, 4));
	}

	//Update all connections in a given group.
	//Generates just one state object and sends it everywhere.
	void send_updates_all(string|int group, mapping|void data) {
		array dest = websocket_groups[group];
		if (dest && sizeof(dest)) _send_updates(dest, group, data);
	}

	void update_all_groups() {send_updates_all(indices(websocket_groups)[*]);}
	void send_to_all(mapping msg) {_low_send_updates(msg, values(websocket_groups) * ({ }));}

	protected void create(string name)
	{
		::create(name);
		if (!ws_type) ws_type = name;
		if (!(websocket_groups = G->G->websocket_groups[ws_type]))
			websocket_groups = G->G->websocket_groups[ws_type] = ([]);
		G->G->websocket_types[ws_type] = this;
	}

	mapping(string:mixed) render(Protocols.HTTP.Server.Request req, mapping replacements) {
		if (replacements->vars->?ws_group) {
			if (!replacements->vars->ws_type) replacements->vars->ws_type = ws_type;
		}
		return render_template("default.html", replacements);
	}
}

class trytls {
	inherit Protocols.WebSocket.Request;
	void opportunistic_tls(string s) {
		SSL.File ssl = SSL.File(my_fd, G->G->opportunistic_tls_ctx);
		ssl->accept(s);
		attach_fd(ssl, server_port, request_callback);
	}
}

object get_satisfactory_map() {
	string mapfile = "satisfactory-map.jpg";
	if (!file_stat(mapfile)) {
		//For annotations, we need the background map
		werror("Downloading map...\n");
		string raw = Protocols.HTTP.get_url_data(
			"https://satisfactory.wiki.gg/images/e/ea/Map.jpg",
			([]),
			(["User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"]),
		);
		if (!raw) werror("Unable to download map\n"); //No explanation, whatevs.
		else {Stdio.write_file(mapfile, raw); werror("Map downloaded and saved to %O.\n", mapfile);}
	}
	return Image.JPEG.decode(Stdio.read_file(mapfile));
}

//Inherit one of these classes to make a localization function available.
class L10n_Satisfactory {
	string L10n(string key) {return G->G->satis_l10n[key] || key;}
}
class L10n_EU4 {
	string L10N(string key) {return G->CFG->L10n[key] || key;} //Deprecated
	string L10n(string key) {return G->CFG->L10n[key] || key;} //Preferred
}

int threeplace(string value) {
	//EU4 uses three-place fixed-point for a lot of things. Return the number as an integer,
	//ie "3.142" is returned as 3142. Can handle "-0.1" and "-.1", although to my knowledge,
	//the EU4 files never contain the latter.
	if (!value) return 0;
	sscanf(value, "%[-]%[0-9].%[0-9]", string neg, string whole, string frac);
	return (neg == "-" ? -1 : 1) * ((int)whole * 1000 + (int)sprintf("%.03s", frac + "000"));
}

void trace_on_signal() {
	//Call to enable Ctrl-\ for a traceback
	signal(3) { //SIGQUIT
		werror("TRACEBACK/^\n%s\n", describe_backtrace(backtrace())); //heh heh... there'll probably be a "\^" at the start of the line...
	};
}
