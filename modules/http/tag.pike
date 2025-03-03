inherit http_websocket;
inherit annotated;

constant http_path_pattern = "/tag/%[^/]";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string tag) {
	return render(req, ([
		"head_scripts": "<style id=ideafilterstyles></style>",
		"title": "EU4 Savefile Analysis",
		"vars": ([
			"ws_group": tag,
			"item_names": ITEM_NAMES,
		]),
	]));
}

//For a group like "TUR", return it unchanged; but a group like "Rosuav" will be
//translated into the actual country tag that that player is controlling.
string group_to_tag(mapping data, string tag) {
	if (!data->countries[tag] && data->players_countries) {
		//See if it's a player identifier. These get rechecked every get_state
		//because they will track the player through tag changes (eg if you were
		//Castille (CAS) and you form Spain (SPA), your tag will change, but you
		//want to see data for Spain now plsthx).
		foreach (data->players_countries / 2, [string name, string trytag])
			if (lower_case(tag) == lower_case(name)) return trytag;
	}
	return tag;
}

//Note that a "tag" might actually be an alias such as a username.
//Preferences stored on a user will be applied to whichever tag that user is
//controlling presently, and will travel with the user.
mapping tag_prefs(string tag) {
	if (!persist->tag_preferences[tag]) persist->tag_preferences[tag] = ([]);
	return persist->tag_preferences[tag];
}

mapping get_state(string group) {
	mapping data = G->G->last_parsed_savefile;
	if (G->G->error) return (["error": G->G->error]);
	if (!data) return (["error": "Processing savefile... "]);
	//For the landing page, offer a menu of player countries
	if (group == "?!?") return (["menu": data->players_countries / 2]);
	string tag = group_to_tag(data, group);
	mapping country = data->countries[tag];
	if (!country) return (["error": "Country/player not found: " + group]);
	mapping ret = analyze_eu4_savefile(data, group, tag, tag_prefs(group));
	//ret->self = data->countries[tag]; ret->capital_province = data->provinces["-" + data->countries[tag]->capital];
	//Enumerate available building types for highlighting. TODO: Check if some changes here need to be backported to the console interface.
	mapping available = ([]);
	mapping tech = country->technology;
	int have_mfg = 0;
	foreach (G->CFG->building_types; string id; mapping bldg) {
		[string techtype, int techlevel] = bldg->tech_required || ({"", 100}); //Ignore anything that's not a regular building
		if ((int)tech[techtype] < techlevel) continue; //Hide IDs you don't have the tech to build
		if (bldg->manufactory && !bldg->show_separate) {have_mfg = 1; continue;} //Collect regular manufactories under one name
		if (bldg->influencing_fort) continue; //You won't want to check forts this way
		available[id] = ([
			"id": id, "name": L10N("building_" + id),
			"cost": bldg->manufactory ? 500 : (int)bldg->cost,
			"raw": bldg,
		]);
	}
	//Restrict to only those buildings for which you don't have an upgrade available
	foreach (indices(available), string id) if (available[G->CFG->building_types[id]->obsoleted_by]) m_delete(available, id);
	if (have_mfg) available->manufactory = ([ //Note that building_types->manufactory is technically valid
		"id": "manufactory", "name": "Manufactory (standard)",
		"cost": 500,
	]);
	array bldg = values(available); sort(indices(available), bldg);
	ret->buildings_available = bldg;
	mapping prefs = tag_prefs(group);
	mapping pp = prefs->pinned_provinces || ([]);
	array ids = indices(pp); sort(values(pp), ids);
	ret->pinned_provinces = map(ids) {return ({__ARGS__[0], data->provinces["-" + __ARGS__[0]]->?name || "(unknown)"});};
	if (prefs->cyclegroup) {ret->cyclegroup = prefs->cyclegroup; ret->cycleprovinces = G->G->provincecycle[group];}

	string term = prefs->search;
	array results = ({ }), order = ({ });
	if (term != "") {
		foreach (sort(indices(data->provinces)), string id) { //Sort by ID for consistency
			mapping prov = data->provinces[id];
			foreach (({({prov->name, ""})}) + (G->CFG->province_localised_names[id - "-"]||({ })), [string|array(string) tryme, string lang]) {
				//I think this is sometimes getting an array of localised names
				//(possibly including a capital name??). Should we pick one, or
				//search all?
				if (arrayp(tryme)) tryme = tryme[0];
				string folded = lower_case(tryme);
				//For searching purposes, it's convenient to allow "München" to match "munc".
				string decomp = Unicode.normalize(folded, "NFKD");
				decomp = replace(decomp, (string)enumerate(0x70, 1, 0x300) / 1, ""); //Remove combining diacritical marks
				string sans_dia = Unicode.normalize(decomp, "NFC");
				//So we now have three strings: the original, the lower-cased, and the no-diacriticals.
				//It's quite likely that they're all the same length, but not guaranteed.
				//So what do we do? We match against any of them.
				int pos = -1; string morph;
				foreach (({tryme, folded, sans_dia}), morph)
					if ((pos = search(morph, term)) != -1) break;
				if (pos == -1) continue;
				//Converting "München" into "munchen" won't break the offset calculations, so
				//pretend that "munc" matched "Münc" in the highlight. However, if the length
				//has changed, show the lower-cased version. Note that this could give bizarre
				//results if there are multiple characters that change length, such that the
				//overall string happens to end up just as long as the original; this seems a
				//rather unlikely possibility, so I won't worry about it for now. (It's just a
				//display issue anyway.)
				if (sizeof(morph) != sizeof(tryme)) tryme = morph;
				int end = pos + sizeof(term);
				string before = tryme[..pos-1], match = tryme[pos..end-1], after = tryme[end..];
				if (lang != "") {before = prov->name + " (" + lang + ": " + before; after += ")";}
				results += ({({(int)(id - "-"), before, match, after})});
				order += ({morph}); //Is it better to sort by the folded or by the tryme?
				break;
			}
			if (sizeof(results) >= 25) break;
		}
		if (sizeof(results) < 25) foreach (sort(indices(ret->countries)), string t) {
			string tryme = ret->countries[t]->name + " (" + t + ")";
			string folded = lower_case(tryme); //TODO: As above. Also, dedup if possible.
			int pos = search(folded, term);
			if (pos == -1) continue;
			int end = pos + sizeof(term);
			string before = tryme[..pos-1], match = tryme[pos..end-1], after = tryme[end..];
			results += ({({t, before, match, after})});
			order += ({folded});
			if (sizeof(results) >= 25) break;
		}
	}
	sort(order, results); //Sort by name for the actual results. So if it's truncated to 25, it'll be the first 25 by (string)id, but they'll be in name order.
	ret->search = (["term": term, "results": results]);

	//Scan all provinces for whether you've discovered them or not
	//Deprecated in favour of the province_info[] mapping
	mapping discov = ret->discovered_provinces = ([]);
	foreach (data->provinces; string id; mapping prov) if (has_value(Array.arrayify(prov->discovered_by), tag)) discov[id - "-"] = 1;

	return ret;
}

void websocket_cmd_highlight(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	if (!G->CFG->building_types[data->building]) m_delete(prefs, "highlight_interesting");
	else prefs->highlight_interesting = data->building;
	persist_save(); send_updates_all(conn->group);
}

void websocket_cmd_fleetpower(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	prefs->fleetpower = threeplace(data->power) || 1000;
	persist_save(); send_updates_all(conn->group);
}

void websocket_cmd_goto(mapping conn, mapping data) {
	indices(G->notifiers)->provnotify(data->tag, (int)data->province);
}

void websocket_cmd_pin(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	mapping pins = prefs->pinned_provinces; if (!pins) pins = prefs->pinned_provinces = ([]);
	if (pins[data->province]) m_delete(pins, data->province);
	else /*if (G->G->last_parsed_savefile->provinces["-" + data->province])*/ pins[data->province] = max(@values(pins)) + 1;
	persist_save(); send_updates_all(conn->group);
}

void websocket_cmd_cyclegroup(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	if (!data->cyclegroup || data->cyclegroup == "") m_delete(prefs, "cyclegroup");
	else prefs->cyclegroup = data->cyclegroup;
	m_delete(G->G->provincecycle, conn->group);
	persist_save(); send_updates_all(conn->group);
}

void websocket_cmd_cycleprovinces(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	if (prefs->cyclegroup != data->cyclegroup) return;
	if (!prefs->cyclegroup || !arrayp(data->provinces)) m_delete(G->G->provincecycle, conn->group);
	else G->G->provincecycle[conn->group] = (array(string))(array(int))data->provinces - ({"0"});
	persist_save(); send_updates_all(conn->group);
}

void websocket_cmd_cyclenext(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	string country = conn->group;
	if (!arrayp(G->G->provincecycle[country])) return; //Can't use this for the default cycling of "interesting" provinces. Pick explicitly.
	[int id, array rest] = Array.shift(G->G->provincecycle[country]);
	G->G->provincecycle[country] = rest + ({id});
	send_updates_all(country);
	indices(G->notifiers)->provnotify(data->tag, (int)id);
}

void websocket_cmd_search(mapping conn, mapping data) {
	mapping prefs = tag_prefs(conn->group);
	prefs->search = stringp(data->term) ? lower_case(data->term) : "";
	persist_save(); send_updates_all(conn->group);
}

void websocket_cmd_set_effect_mode(mapping conn, mapping data) {
	if (!stringp(data->effect)) return;
	if (!has_value("threeplace percent boolean" / " ", data->mode)) return;
	persist->effect_display_mode[data->effect] = data->mode;
	persist_save();
	//Note that currently-connected clients do not get updated.
}

mapping websocket_cmd_listcustoms(mapping conn, mapping data) {
	string customdir = EU4_LOCAL_PATH + "/custom nations";
	mapping nations = ([]);
	foreach (sort(get_dir(customdir)), string fn)
		nations[fn] = G->G->parser->parse_eu4txt(Stdio.read_file(customdir + "/" + fn));
	return ([
		"cmd": "customnations",
		"nations": nations,
		"custom_ideas": G->CFG->custom_ideas,
		"effect_display_mode": persist->effect_display_mode,
		"map_colors": G->CFG->custom_country_colors->color,
	]);
}

mapping websocket_cmd_analyzebattles(mapping conn, mapping msg) {
	//Collect some useful info about the units a country is using
	//NOTE: Can be used for countries you're not at war with (yet), to allow for
	//Luke 14:31-32 style analysis, but be aware that it may provide information
	//that you couldn't have seen in-game about the precise composition of the
	//opposing army. (You can see the totals across the entire nation, but not
	//how many in any given stack, unless they're near your borders.) Unlikely
	//to be of massively unbalancing value, since you could usually see one army
	//and deduce that others will be similar.
	mapping data = G->G->last_parsed_savefile; if (!data) return 0;
	array countries = ({
		//Could add others if necessary eg allies/subjects. For now, reanalyze with those tags.
		data->countries[group_to_tag(data, conn->group)],
		data->countries[msg->tag],
	});
	if (has_value(countries, 0)) return 0;
	array infos = ({ });
	int combat_width = 15;
	foreach (countries, mapping country) {
		mapping info = (["tag": country->tag, "unit_details": ([])]);
		foreach (country->sub_unit; string type; string id) {
			info->unit_details[id] = ([
				"type": type, //eg "infantry"
				"defn": G->CFG->unit_definitions[id],
			]);
		}
		info->armies = ({ });
		foreach (Array.arrayify(country->army), mapping raw) {
			mapping army = ([
				"name": raw->name,
				//TODO: General's pips, if any; otherwise ({0,0,0,0})
				//Also general's trait, if any.
				//Not supported by this tool, but what happens if two armies with two generals
				//combine, and both have traits? Do you get both?
				"regiments": Array.arrayify(raw->regiment), //TODO: Is the arrayify needed? Probably.
				"infantry": 0, "cavalry": 0, "artillery": 0,
			]);
			foreach (army->regiments, mapping reg) army[info->unit_details[reg->type]->type]++;
			info->armies += ({army});
		}
		info->mod = ([]);
		mapping all = G->G->analysis->all_country_modifiers(data, country);
		//TODO: Province bonuses?? local_{defender,attacker}_dice_roll_bonus, own_territory_dice_roll_bonus,
		//terrain, river crossing, landing from ship...
		foreach (({
			"military_tactics", "discipline",
			"infantry_fire", "infantry_shock",
			"cavalry_fire", "cavalry_shock",
			"artillery_fire", "artillery_shock",
			"infantry_power", "cavalry_power", "artillery_power",
			"morale_damage", "morale_damage_received",
			"global_defender_dice_roll_bonus", "global_attacker_dice_roll_bonus",
		}), string mod) info->mod[mod] = all[mod] || 0;
		info->mod->land_morale = all->base_land_morale * (1000 + all->land_morale) / 1000;
		int wid = all->combat_width + 15; //The base combat width is in defines.lua so we just add 15 manually
		if (wid > combat_width) combat_width = wid; //NOTE: If reworking this for naval combat, remember that naval combat width is per side.
		infos += ({info});
	}
	return ([
		"cmd": "analyzebattles",
		"countries": infos,
		"combat_width": combat_width,
	]);
}

constant custnat_keys = "name adjective country_colors index graphical_culture technology_group religion "
			"government government_reform government_rank idea culture monarch heir queen" / " ";
mapping custnat_handlers = ([
	"country_colors": lambda(mapping col) {
		return sprintf(#"{
	flag=%s
	color=%s
	symbol_index=%s
	flag_colors={
		%{%s %}
	}
}", col->flag, col->color, col->symbol_index, col->flag_colors);
	},
	"idea": lambda(array idea) {
		return "{" + sprintf(#"
	{
		level=%s
		index=%s
		name=%q
		desc=%q
	}", idea->level[*], idea->index[*], idea->name[*], idea->desc[*]) * "" + "\n}";
	},
	"monarch": lambda(mapping mon) {
		return sprintf(#"{
	admin=%s
	diplomacy=%s
	military=%s
	age=%s
	religion=%s
	culture=%q
	female=%s
	name=%q
	dynasty=%q
	is_null=%s
	personality={
%{		%q
%}	}
}", mon->admin, mon->diplomacy, mon->military, mon->age, mon->religion, mon->culture || "",
		mon->female ? "yes" : "no", mon->name || "", mon->dynasty || "", mon->is_null ? "yes" : "no",
		mon->personality);
	},
	"heir": "monarch", "queen": "monarch",
]);

string save_custom_nation(mapping data) {
	//In order to save a custom nation:
	//1) The nation definition file must already exist
	//2) It must begin with a manually-added comment line starting "# Editable: "
	//3) The save request must include the rest of the line, which is a sort of password
	//4) All attributes to be saved must be included.
	//It's up to you to make sure the file actually is loadable. The easiest way is to
	//make minor, specific changes to an existing custom nation.
	string customdir = EU4_LOCAL_PATH + "/custom nations";
	string fn = data->filename; if (!fn) return "Need a file name";
	if (!has_value(get_dir(customdir), fn)) return "File not found";
	sscanf(Stdio.read_file(customdir + "/" + fn), "# Editable: %s\n", string pwd);
	if (!pwd || pwd != data->password) return "Permission denied";
	//Okay. Let's build up a file. We'll look for keys in a specific order, to make
	//the file more consistent (no point randomly reordering stuff).
	string output = sprintf("# Editable: %s\n", pwd);
	foreach (custnat_keys, string key) {
		mixed val = data->data[key];
		if (stringp(val) || intp(val)) {
			//Strings that look like numbers get output without quotes
			if ((string)(int)val == val) output += sprintf("%s=%d\n", key, (int)val);
			else output += sprintf("%s=%q\n", key, val);
		}
		else if (arrayp(val) || mappingp(val)) {
			function|string f = custnat_handlers[key];
			if (stringp(f)) f = custnat_handlers[f]; //Alias one to another
			if (f) output += sprintf("%s=%s\n", key, ((function)f)(val));
		}
	}
	Stdio.write_file(customdir + "/" + fn, output);
	return "Saved.";
}

mapping websocket_cmd_savecustom(mapping conn, mapping data) {
	return ([
		"cmd": "savecustom",
		"result": save_custom_nation(data),
	]);
}

protected void create(string name) {
	if (!persist->tag_preferences) persist->tag_preferences = ([]); //Don't bother saving it back though, the next save can catch it
	::create(name);
}
