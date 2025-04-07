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
	mapping savefile = parser->low_parse_savefile("Mental_autosave_0.sav");
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
	write("------ Mental ------\n");
	mapping savefile = parser->low_parse_savefile("Mental_autosave_0.sav");
	//write("Reconstituted %d bytes.\n", sizeof(parser->reconstitute_savefile(savefile->tree)));
	write("Markers: %O\n", savefile->mapmarkers);
	//Add some markers, build a savefile, then reparse.
	parser->add_map_marker(savefile, "Origin", 0.0, 0.0, 0.0);
	string rebuilt = parser->reconstitute_savefile(savefile->tree);
	mapping reparsed = parser->parse_savefile_data(Stdio.Buffer(rebuilt));
	write("Now markers: %O\n", reparsed->mapmarkers);
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
