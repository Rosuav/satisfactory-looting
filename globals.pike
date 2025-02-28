protected void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	foreach (Program.annotations(this_program); string anno;)
		if (stringp(anno) && sscanf(anno, "G->G->%s", string gl) && gl)
			if (!G->G[gl]) G->G[gl] = ([]);
}

//TODO: Figure out a way to ask Steam where a game is installed, and what the active user is
string SAVE_PATH = "../.steam/steam/steamapps/compatdata/526870/pfx/drive_c/users/steamuser/Local Settings/Application Data/FactoryGame/Saved/SaveGames/76561198043731689";
string CONFIG_FILE = "preferences.json";
//If anything mutates this, call persist_save().
mapping persist = Standards.JSON.decode_utf8(Stdio.read_file(CONFIG_FILE) || "{}");
void persist_save() {
	//Clean out any empty tag prefs, which just clutter up the config file for nothing
	foreach (indices(persist->tag_preferences), string tag) {
		mapping tp = persist->tag_preferences[tag];
		if (tp->search == "") m_delete(tp, "search");
		if (!sizeof(tp->pinned_provinces)) m_delete(tp, "pinned_provinces");
		if (!sizeof(tp)) m_delete(persist->tag_preferences, tag);
	}
	Stdio.write_file(CONFIG_FILE, Standards.JSON.encode(persist, 5));
}

//Can this be loaded from a localization file or something?
constant ITEM_NAMES = ([
	"Desc_AluminumPlateReinforced_C": "Heat Sink",
	"Desc_AluminumPlate_C": "Alclad Aluminum Sheet",
	"Desc_Biofuel_C": "Solid Biofuel",
	"Desc_CartridgeSmart_C": "Rifle Smartridge",
	"Desc_CartridgeStandard_C": "Rifle Ammo",
	"Desc_Cement_C": "Concrete",
	"Desc_ComputerSuper_C": "Supercomputer",
	"Desc_Filter_C": "Gas Filter",
	"Desc_Fuel_C": "Packaged Fuel",
	"Desc_HighSpeedConnector_C": "High-Speed Connector",
	"Desc_HighSpeedWire_C": "Quickwire",
	"Desc_IronPlateReinforced_C": "Reinforced Iron Plate",
	"Desc_IronScrew_C": "Screw",
	"Desc_Medkit_C": "Medicinal Inhaler",
	"Desc_ModularFrameFused_C": "Fused Modular Frame",
	"Desc_ModularFrameHeavy_C": "Heavy Modular Frame",
	"Desc_MotorLightweight_C": "Turbo Motor",
	"Desc_NobeliskCluster_C": "Cluster Nobelisk",
	"Desc_NobeliskExplosive_C": "Nobelisk",
	"Desc_NobeliskGas_C": "Gas Nobelisk",
	"Desc_NobeliskShockwave_C": "Pulse Nobelisk",
	"Desc_PackagedBiofuel_C": "Packaged Liquid Biofuel",
	"Desc_Rebar_Explosive_C": "Explosive Rebar",
	"Desc_Rebar_Spreadshot_C": "Shatter Rebar",
	"Desc_Rebar_Stunshot_C": "Stun Rebar",
	"Desc_SpikedRebar_C": "Iron Rebar",
	"Desc_SteelPlateReinforced_C": "Encased Industrial Beam",
	"Desc_SteelPlate_C": "Steel Beam",
	"Desc_TurboFuel_C": "Packaged Turbofuel",
	"BP_EquipmentDescriptorJumpingStilts_C": "Blade Runners",
	"BP_EquipmentDescriptorShockShank_C": "Xeno-Zapper",
	"BP_EquipmentDescriptorStunSpear_C": "Xeno-Basher",
]);

string L10n(string id) {
	if (ITEM_NAMES[id]) return ITEM_NAMES[id];
	sscanf(id, "Desc_%s_C", id);
	return String.trim(Regexp.SimpleRegexp("[A-Z][a-z]+")->replace(id) {return __ARGS__[0] + " ";});
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
