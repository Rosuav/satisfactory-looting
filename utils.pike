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

@"Pair-parse two EU5 savefiles to compare binary and text":
void compareeu5() {
	//TODO: Parameterize with the file names
	object eu5 = G->bootstrap("modules/eu5.pike");
	mapping xtra = eu5->eu5_parse_savefile("SP_HOL_1337_04_01_1509e222-7267-4984-9c47-3071f89972ca_0.eu5");
	mapping savefile = xtra->savefile;
	//savefile->metadata->compatibility->locations = savefile->metadata->flag = "(...)";
	werror("Toplevel: %t %O\n", savefile, indices(savefile));
	if (!xtra->unknownids) return 0; //Yay!

	//If we have a matching text save, try to match the keys.
	array string_sequence = eu5->list_strings("SP_HOL_1337_04_01_1509e222-7267-4984-9c47-3071f89972ca_1.eu5");
	array id_sequence = xtra->id_sequence;
	werror("Got %d IDs and %d strings; %d unknown IDs.\n", sizeof(id_sequence), sizeof(string_sequence), xtra->unknownids);

	//Attempt to diff the two arrays.
	//In the id sequence, anything beginning with a hash (eg "#3206") is incomparable.
	//What we ideally want to see is something like:
	//	ID		String		Meaning
	//	"country"	"country"	Synchronized
	//	"1183"		"1183"		Synchronized
	//	"#2cf1"		"road_network"	Candidate!
	//	"#3802"		"roads"		Candidate!
	//	"#0528"		"from"		Candidate!
	//	"1"		"1"		Resync!
	//What we DON'T want to see is two strings that aren't the same. Example:
	//	ID		String		Meaning
	//	"save_label"	"save_label"	Synchronized
	//	"Autosave"	"1464.5.18.16"	DESYNC
	//	"version"	"version"	Resync
	//This immediately calls into question everything around it. Ideally, we should see
	//multiple synchronization pairs before and after any candidates; these are described
	//as the candidacy quality, given as a pair of numbers (eg "2-1" if the country->1
	//sequence were the entire file).
	int nextid = 0, nextstr = 0;
	array blocks = ({ }), matches = ({ });
	//Elephant in Cairo: Trigger mismatch detection at the very end so that a final block can be detected.
	id_sequence += ({"id_sequence"}); string_sequence += ({"string_sequence"});
	int have_candidate = 0;
	while (nextid < sizeof(id_sequence) && nextstr < sizeof(string_sequence)) {
		string id = id_sequence[nextid], str = string_sequence[nextstr];
		//write("Compare [%d] %O to [%d] %O\n", nextid, id[..50], nextstr, str[..50]);
		werror("Comparing... %.1f%%...\r", nextid * 100.0 / sizeof(id_sequence));
		if (id == str || id[0] == '#' || id == (string)((int)str * 100000) || id == (string)((int)str + (1<<32))) {
			//Could be a match, or a candidate! Hang onto it for future analysis.
			//Note that we consider "4500000" equal to "45" as we are currently
			//unable to determine which integers represent fixed point and which
			//are as-is. Similarly for signed/unsigned numbers.
			matches += ({({id, str})});
			++nextid; ++nextstr;
			if (id[0] == '#') have_candidate = 1;
		} else {
			//We have a mismatch.
			if (sizeof(matches)) {
				//if (have_candidate) foreach (matches[..<10], [string i, string s]) write("\e[%dm%30s | %s\e[0m\n", i != s, i, s);
				//if (have_candidate) exit(0, "Now have %O %O\n", id, str);
				have_candidate = 0;
				//Desynchronization after candidates and/or synchronization. Save the current block,
				//but exclude any candidates on the outside of it - we want something surrounded by
				//synchronization points.
				int start = 0;
				while (start < sizeof(matches) && matches[start][0][0] == '#') ++start;
				if (start < sizeof(matches)) {
					//(if it isn't, there weren't any matches, just a series of incomparables between
					//two desynchronizations)
					int end = sizeof(matches) - 1; //Inclusive-inclusive indexing since that's how Pike slices
					while (matches[end][0][0] == '#') --end; //Guaranteed to terminate; there must be at least one synchronization.
					//So, now that we've trimmed those off... are there any candidates in the middle?
					int candidates = 0;
					for (int i = start; i < end - 1; ++i)
						candidates += (matches[i][0][0] == '#');
					if (candidates) {
						//Okay, we have at least one candidate; the quality is the number of sync points
						//in the block. This isn't perfect, but it's something. Changing the quality
						//algorithm would change prioritization but that's all.
						blocks += ({([
							"quality": end - start + 1 - candidates,
							"candidates": candidates,
							"strings": matches[start..end],
						])});
					}
				}
				matches = ({ });
			}
			//So. We need to scan forward in both arrays until we find a resync.
			//Pretty simple algorithm here; this isn't always going to find the best diff but it's probably fine.
			mapping idskip = ([]), strskip = ([]);
			//First iteration of this loop looks at the same id/str as we already have, then we advance from there.
			//write("DESYNC: [%d] %O to [%d] %O\n", nextid, id[..50], nextstr, str[..50]);
			int found = 0;
			void advance(int skipids, int skipstrs) {
				//Activate this for manual review of every discrepancy that contains an unknown
				if (0) foreach (id_sequence[nextid..nextid+skipids-1], string id) if (id[0] == '#') {
					//If there's any ID with a hash in it, report the block.
					write("- Mismatch, %d:%d -\e[K\n", skipids, skipstrs);
					int i = -1;
					for (; i < skipids || i < skipstrs; ++i)
						write("%30s | %s\n",
							i < skipids ? id_sequence[nextid + i] : "",
							i < skipstrs ? string_sequence[nextstr + i] : "",
						);
					//And one line of context. In reality, the alignment may work better if the
					//gap is somewhere other than immediately before the context line, but this
					//will give at least some idea.
					write("%30s | %s\n", id_sequence[nextid + skipids], string_sequence[nextstr + skipstrs]);
					break;
				}
				nextid += skipids; nextstr += skipstrs; found = 1;
			}
			for (int skip = 0; nextid + skip < sizeof(id_sequence) && nextstr + skip < sizeof(string_sequence); ++skip) {
				id = id_sequence[nextid + skip]; str = string_sequence[nextstr + skip];
				//When skip is (say) 4, we've scanned 4 entries forward in each array.
				//If there are matching entries in the two arrays within that distance, we take
				//that and resume. Note that, as written here, we will try to keep the skip
				//distances similar, rather than taking the earliest match. Ideally, we'd find
				//multi-string matches, rather than accepting the first coincidence we meet.
				if (id == str) {
					//Activate this for manual review of single-line discrepancies, which
					//could indicate that more flexible comparisons are needed.
					if (0 && skip == 1) {
						//We advanced one entry in each array and then found a rematch.
						//This strongly suggests a one-string mismatch, which may well
						//be of interest. Report it, with a little context.
						write("- One-line mismatch block -\n");
						write("%30s | %<s\n", id_sequence[nextid - 1]);
						write("\e[1m%30s | %s\e[0m\n", id_sequence[nextid], string_sequence[nextstr]);
						write("%30s | %<s\n", id);
					}
					advance(skip, skip);
					break;
				}
				//if (id[0] == '#') werror("CHECKING/SKIPPING %O %O\n", id, str);
				if (!undefinedp(idskip[str])) {advance(idskip[str], skip); break;}
				if (!undefinedp(strskip[id])) {advance(skip, strskip[id]); break;}
				idskip[id] = strskip[str] = skip;
			}
			/* else: */ if (!found) break; //If no resync point was found, we must have hit the end.
		}
	}
	werror("Got %d candidacy blocks.\n", sizeof(blocks));
	mapping sighted = ([]), quality = ([]);
	foreach (blocks, mapping blk) {
		write("- %d candidates at quality %d\n", blk->candidates, blk->quality);
		multiset seen = (<>);
		foreach (blk->strings, [string id, string str]) {
			if (seen[id]) continue;
			seen[id] = 1;
			write("\e[%dm%30s | %s\e[0m\n", id != str, id, str); //If they match, it's a context line, not bold. If they're different, bold it.
			if (id[0] == '#') {
				if (sighted[id] && sighted[id] != str) {
					sighted[id] += " :: " + str;
					werror("MISMATCH: %O -> %O\n", id, sighted[id]);
				} else {
					sighted[id] = str;
					quality[id] += blk->quality;
				}
			}
		}
	}
	array can = ({ }), qual = ({ });
	array keep = ({ });
	//Merge in the current string table
	foreach (eu5->id_to_string; int id; string str) if (str[0] != '#') {
		sighted[sprintf("#%04x", id)] = str;
		quality[sprintf("#%04x", id)] = 1<<30;
	}
	foreach (sighted; string id; string str) {
		//Good ones get saved automatically
		if (quality[id] >= 25) keep += ({({id, str})});
		else {
			//Less good ones get saved as candidates. After the ones with higher confidence
			//get saved and used, they can provide context, which will increase quality of
			//others. (That might not actually be a good thing though...)
			can += ({sprintf("%s: [%d] %s\n", id, quality[id], str)});
			qual += ({-quality[id]});
		}
	}
	sort(qual, can);
	if (sizeof(can)) Stdio.write_file("candidates.txt", can * "");
	sort(keep[*][0], keep);
	Stdio.write_file("eu5textid.dat", sprintf("%{%s %s\n%}", keep));
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
