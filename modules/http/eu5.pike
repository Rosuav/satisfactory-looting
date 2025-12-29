inherit http_websocket;

constant http_path_pattern = "/eu5/%[^/]";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string tag) {
	return render(req, ([
		"title": "EU5 Savefile Analysis",
		"vars": ([
			"ws_group": Protocols.HTTP.Server.http_decode_string(tag),
		]),
	]));
}

//Find the country ID for a given tag (eg "CAS") or player name (eg "Rosuav")
int group_to_country(mapping data, string tag) {
	if (data->played_country) {
		//See if it's a player identifier. These get rechecked every get_state
		//because they will track the player through tag changes (eg if you were
		//Castille (CAS) and you form Spain (SPA), your tag will change, but you
		//want to see data for Spain now plsthx).
		//FIXME: Get an actual multiplayer session, save it, and see what we see.
		//Do we get an array here?
		if (data->played_country->name == tag) return data->played_country->country;
	}
	//Do we need to iterate over the countries? Is there no direct lookup?
	foreach (data->countries->database; int id; mapping ctry)
		if (ctry->country_name == tag) return id;
	return -1;
}

//JSON can't handle non-string keys, but there are a lot of integer keys in the save file.
mapping stringify_keys(mapping data) {
	if (!mappingp(data)) return data;
	mapping ret = ([]);
	foreach (data; mixed key; mixed val) {
		if (intp(key)) key = (string)key;
		else if (!stringp(key)) key = "<unknown type>"; //What to do about collisions?
		if (arrayp(val)) val = stringify_keys(val[*]);
		else if (mappingp(val)) val = stringify_keys(val);
		ret[key] = val;
	}
	return ret;
}

mapping get_state(string group) {
	mapping data = G->G->last_parsed_eu5_savefile;
	if (!data) return (["error": "Processing savefile... "]);
	if (data->error) return (["error": data->error]);
	//For the landing page, offer a menu of player countries
	if (group == "") return (["error": "TODO"]);
	data = data->savefile; //The meta-metadata isn't very interesting here
	mapping country = data->countries->database[group_to_country(data, group)];
	if (!country) return (["error": "Country/player not found: " + group]);

	return ([
		"name": group + " (" + country->country_name + ")", //TODO: L10N this
		"automated_systems": country->automated_systems, //TODO: Provide recommendations
		"bgcolor": sprintf("#%02x%02x%02x", @country->color),
		"self": stringify_keys(country),
	]);
}
