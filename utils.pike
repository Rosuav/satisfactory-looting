@"This help information":
void help() {
	write("\nUSAGE: pike stillebot --exec=ACTION\nwhere ACTION is one of the following:\n");
	array names = indices(this), annot = annotations(this);
	sort(names, annot);
	foreach (annot; int i; multiset|zero annot)
		foreach (annot || (<>); mixed anno;)
			if (stringp(anno)) write("%-15s: %s\n", names[i], anno);
}

//Walk a mapping/array hierarchy, calling the handler for each node
//The handler will be called with the current node and the path to get here,
//which consists of a series of x["y"][0]["z"][2] etc. Note that arrow notation
//is not used even if it would be valid (simpler that way).
/* Example:
	walk(savefile, "savefile") {[mixed node, string path] = __ARGS__;
		if (mappingp(node) && node->mFogOfWarRawData) write("%s->mFogOfWarRawData: %O\n", path, node);
	};
*/
void walk(mixed tree, string path, function handler) {
	handler(tree, path);
	if (arrayp(tree) || mappingp(tree))
		foreach (tree; mixed key; mixed val)
			walk(val, sprintf("%s[%O]", path, key), handler);
}

@"Dump out current hard drive library":
void hd() {
	object parser = G->bootstrap("modules/parser.pike");
	mapping savefile = parser->low_parse_savefile(0);
	array avail = ({ }), unclaimed = ({ });
	foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
		if (obj[1] == "/Script/FactoryGame.FGRecipeManager\0")
			avail = obj[-1]->prop->mAvailableRecipes->value;
		if (obj[1] == "/Game/FactoryGame/Recipes/Research/BP_ResearchManager.BP_ResearchManager_C\0")
			unclaimed = obj[-1]->prop->mUnclaimedHardDriveData->value;
	}
	//TODO: Record the recipes, and for each schematic in the hard drives, look up which recipes it
	//unlocks. The info is in the same JSON file that has the l10n.
	array want = ({
		"Schematic_Alternate_HeavyOilResidue_C",
		"Schematic_Alternate_DilutedPackagedFuel_C", //TODO: Or Diluted Fuel
		"Schematic_Alternate_Plastic1_C", //Recycled Plastic
		"Schematic_Alternate_RecycledRubber_C",
	});
	foreach (unclaimed, mapping hd) {
		if (!hd->PendingRewardsRerollsExecuted->value) werror("HD: Reroll available\n");
		else werror("HD: (no reroll)\n");
		foreach (hd->PendingRewards->value, object rew)
			werror("\t%s\n", L10n((rew->path / ".")[1]));
	}
	//TODO: Make a way to check what's still needed for a particular set of recipes
	//Possibly offer options, too?
	//Example: Heavy Oil Residue, Diluted Fuel | Diluted Packaged Fuel, Recycled Plastic, Recycled Rubber
	// == Ouroboros. For each one, is it already available? Is it currently in an unclaimed HD? And maybe
	//see if its prereqs are fulfilled - not sure if I can see that.
}

string describe(array player, array stuff, int|void idx) {
	float nearest, furthest;
	foreach (stuff, array item) {
		array loc = item[idx || 1]; //Most of the arrays have the location in slot 1, but loot has it in slot 2.
		float dist = `+(@((loc[*] - player[*])[*]**2)); //Distance squared from player to this item
		if (!furthest) nearest = furthest = dist;
		else if (dist < nearest) nearest = dist;
		else if (dist > furthest) furthest = dist;
	}
	return sprintf("%3d %4.0f-%-4.0f", sizeof(stuff), nearest ** 0.5 / 100, furthest ** 0.5 / 100);
}

@"Count the things that might and might not be in the savefile":
void counter() {
	object parser = G->bootstrap("modules/parser.pike");
	write("%-10s %-14s %-14s %-14s Ships\n", "Save", "Spawn", "Crash", "Loot");
	foreach (sort(glob("Exploration*.sav", get_dir(SATIS_SAVE_PATH))), string fn) {
		mapping savefile = parser->low_parse_savefile(fn, (["pristine": ([])]));
		sscanf(fn, "Exploration_%s.sav", string label);
		[string name, array player, mapping attrs] = savefile->players[0];
		//List all object classes, and how far away the furthest from the player is.
		//Some object classes appear to only be saved when they've been close to us.
		if (0) {
			mapping distances = ([]);
			foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
				if (obj[4]) continue; //Ignore child objects
				if (obj[9] == 0.0 && obj[10] == 0.0 && obj[11] == 0.0) continue; //Ignore objects that only exist at the origin
				if (!distances[obj[1]]) distances[obj[1]] = (["label": ((obj[1] - "\0") / "/")[-1]]);
				mapping info = distances[obj[1]];
				float dist = `+(@((obj[9..11][*] - player[*])[*]**2)) ** 0.5 / 100.0;
				if (dist > info->maxdist) info->maxdist = dist;
				info->totdist += dist; info->count++;
			}
			array dists = values(distances); sort(dists->maxdist, dists);
			foreach (dists, mapping cls) {
				write("[%4.0f/%-4.0f] %s\n", cls->totdist / cls->count, cls->maxdist, cls->label);
			}
		}
		array descs = ({ }), dists = ({ });
		mapping searchfor = ([
			"/Game/FactoryGame/World/Benefit/DropPod/BP_DropPod.BP_DropPod_C\0": "Pod",
			"/Game/FactoryGame/World/Benefit/DropPod/BP_Ship.BP_Ship_C\0": "Ship",
		]);
		mapping object_counts = ([]);
		foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
			object_counts[obj[1]]++;
			string label = searchfor[obj[1]];
			if (!label) continue;
			descs += ({sprintf("%s: %.0f,%.0f,%.0f\n", label, obj[9] / 100.0, obj[10] / 100.0, obj[11] / 100.0)});
			dists += ({`+(@((obj[9..11][*] - player[*])[*]**2))});
		}
		//sort(dists, descs); write(descs * ""); //List them all, nearest to furthest
		if (label == "4_North" || label == "4a_North") Stdio.write_file(label + ".json", Standards.JSON.encode(savefile->tree, 7));
		parser->annotate_map(savefile, ({({"crashsites"}), ({"spawners"}), ({"all_loot"}), ({"all_stuff"})}));
		Stdio.write_file(label + ".png", Image.PNG.encode(savefile->annot_map));
		write("%-10s %-14s %-14s %-14s %5d\n", label,
			describe(player, savefile->spawners),
			describe(player, savefile->crashsites),
			describe(player, savefile->loot, 2),
			object_counts["/Game/FactoryGame/World/Benefit/DropPod/BP_Ship.BP_Ship_C\0"],
		);
	}
}

@"Edited as needed, does what's needed":
void test() {
	trace_on_signal();
	object parser = G->bootstrap("modules/parser.pike");
	program ObjectRef = parser->ObjectRef;
	if (0) {
		write("------ Stable ------\n");
		mapping savefile = parser->low_parse_savefile("Assembly First_autosave_1.sav");
		write("Reconstituted %d bytes.\n", sizeof(parser->reconstitute_savefile(savefile->tree)));
	}
	if (0) foreach (sort(get_dir(SATIS_SAVE_PATH)), string fn) {
		mapping savefile = parser->low_parse_savefile(fn);
		if (!savefile->tree->savefilebody) write("%s parse failed\n", fn);
		else write("%s unkv14 %O\n", fn, savefile->tree->savefilebody->sublevels[-1]->unkv14);
	}
	write("------ Naval ------\n");
	mapping savefile = parser->low_parse_savefile("Naval Warfare_autosave_0.sav");
	if (1) {
		string reconst = parser->reconstitute_savefile(savefile->tree);
		write("Reconstituted %d bytes.\n", sizeof(reconst));
		Stdio.Buffer data = Stdio.Buffer(reconst);
		data->read_only();
		mapping reparsed = parser->parse_savefile_data(data);
		write("Original: %O\nReparsed: %O\n",
			savefile->tree->savefilebody->sublevels[-1]->unkv14,
			reparsed->tree->savefilebody->sublevels[-1]->unkv14);
	}
	foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
		if (obj[1] == "/Script/FactoryGame.FGMapManager\0") {
			//werror("Highlights: %O\n", obj[-1]->prop->mHighlightedMarkers);
			//We can see that player X has highlighted marker Y, but X and Y are given as
			//object references. The map markers themselves (obj[-1]->prop->mMapMarkers)
			//do not seem to have their reference IDs. Have we already thrown those away
			//at an earlier phase of parsing?
		}
	}
}
