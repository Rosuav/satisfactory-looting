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

@"Edited as needed, does what's needed":
void test() {
	object parser = G->bootstrap("modules/parser.pike");
	program ObjectRef = parser->ObjectRef;
	if (1) {
		write("------ Stable ------\n");
		parser->low_parse_savefile("Assembly First_autosave_1.sav");
	}
	write("------ Mental ------\n");
	mapping savefile = parser->low_parse_savefile("Mental_autosave_0.sav");
	foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
		if (obj[1] == "/Script/FactoryGame.FGMapManager\0") {
			werror("Highlights: %O\n", obj[-1]->prop->mHighlightedMarkers);
			//We can see that player X has highlighted marker Y, but X and Y are given as
			//object references. The map markers themselves (obj[-1]->prop->mMapMarkers)
			//do not seem to have their reference IDs. Have we already thrown those away
			//at an earlier phase of parsing?
		}
	}
}
