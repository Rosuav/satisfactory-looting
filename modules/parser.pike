inherit annotated;
@retain: mapping(string:mapping(string:mixed)) parse_cache = ([]);
constant CACHE_VALIDITY = 3; //Bump this number to invalidate older cache entries.

//Ensure that a file name is a valid save file. Can be used with completely untrusted names, and
//will only return true if it is both safe and valid.
@export: int(1bit) check_savefile_name(string fn) {
	return has_value(get_dir(SATIS_SAVE_PATH), fn);
}

@export: mapping cached_parse_savefile(string fn) {
	//NOTE: This does not validate the file name by ensuring that it is found in the directory.
	//If the file name comes from an untrusted source, first call check_savefile_name() above.
	string filename = SATIS_SAVE_PATH + "/" + fn;
	int mtime = file_stat(filename)->?mtime;
	if (!mtime) return (["mtime": 0]); //File not found
	if (mapping c = parse_cache[fn]) {
		if (c->mtime == mtime && c->validity == CACHE_VALIDITY) return parse_cache[fn];
		//Otherwise ignore the cached entry and reconstruct.
	}
	//NOTE: If this function is made asynchronous or there is any other way that this could run
	//reentrantly, place a stub in the cache, and validate the stub before returning, blocking
	//until the first parser has finished.
	mapping ret = parse_cache[fn] = (["mtime": mtime]);

	//------------- Parse the save file -------------//
	Stdio.Buffer data = Stdio.Buffer(Stdio.read_file(filename));
	data->read_only();
	//Huh. Unlike the vast majority of games out there, Satisfactory has info on its official wiki.
	//https://satisfactory.wiki.gg/wiki/Save_files
	//mapname is always "Persistent_Level"; sessname is what the user entered to describe the session.
	mapping tree = ret->tree = ([]); //Everything needed to reconstruct the original savefile.
	[int ver1, int ver2, int build, string mapname, string params, string sessname, int playtime] = tree->header = data->sscanf("%-4c%-4c%-4c%-4H%-4H%-4H%-4c");
	if (ver1 < 13) return ret; //There seem to be some differences with really really old savefiles
	ret->session = sessname[..<1];
	//[int timestamp, int visibility, int objver, string modmeta, int modflags, string sessid, string persistent, int cheats]
	//visibility is "private", "friends only", etc. Not sure what the byte values are.
	//I've no idea what the session ID is at this point but it seems to stay constant for one session. It's always 22 bytes (plus the null).
	//The persistent information is mostly uninteresting, but is always constant for any given session (possibly RNG seed).
	//The cheats flag is 1 if AGSes are used, 0 if not (? unconfirmed)
	tree->header2 = data->sscanf("%-8c%c%-4c%-4H%-4c%-4H%24s%-4c");
	//The rest of the file is a series of compressed chunks. Each blob of deflated data has a
	//header prepended which is 49 bytes long.
	string decomp = "";
	while (sizeof(data)) {
		//Chunk header is a fixed eight byte value 0x222222229e2a83c1 (Unreal signature)
		//The maximum size is always 131072, even on the last chunk, which has whatever's left.
		//The actual size is given by the inflsz afterwards. Oddly, the deflated and inflated sizes are
		//each stored twice.
		//A lot of this is guesses, esp since most of this seems to be fixed format (eg type is always 3,
		//but I'm guessing that's a one-byte marker saying "gzipped").
		//[int chunkhdr, int maxsz, int zero, int type, int deflsz, int inflsz, int deflsz2, int inflsz2]
		array chunk = data->sscanf("%-8c%-4c%-4c%c%-8c%-8c%-8c%-8c");
		//????? For some reason, Pike segfaults if we don't first probe the buffer like this.
		//So don't remove this 'raw =' line even if raw itself isn't needed.
		string raw = (string)data;
		object gz = Gz.inflate();
		decomp += gz->inflate((string)data);
		data = Stdio.Buffer(gz->end_of_stream()); data->read_only();
	}
	//Alright. Now that we've unpacked all the REAL data, let's get to parsing.
	//Stdio.write_file("dump", decomp); Process.create_process(({"hd", "dump"}), (["stdout": Stdio.File("dump.hex", "wct")]));
	data = Stdio.Buffer(decomp); data->read_only();
	[int sz] = data->sscanf("%-8c"); //Total size (will be equal to sizeof(data) after this returns)
	tree = tree->savefilebody = ([]);
	//Most of these are fixed and have unknown purpose
	[int unk10, string unk11, int zero3, tree->hdr1, int unk13, string unk14, tree->hdr2] = data->sscanf("%-4c%-4H%-4c%-4c%-4c%-4H%-4c");
	//Level-grouping grids
	for (int i = 0; i < 5; ++i) {
		[string title, int unk17, int unk18, int n] = data->sscanf("%-4H%-4c%-4c%-4c");
		//write("Next section: %d %O (%x/%x)\n", n, title, unk17, unk18);
		array info = ({ });
		while (n--) info += ({data->sscanf("%-4H%-4c")});
		tree->levelgroupinggrids += ({({title, unk17, unk18, info})});
	}
	tree->sublevels = ({ });
	[int sublevelcount] = data->sscanf("%-4c");
	//write("Sublevels: %d\n", sublevelcount);
	multiset seen = (<>);
	ret->crashsites = ({ }); ret->loot = ({ }); ret->visited_areas = ({ });
	ret->spawners = ({ }); ret->mapmarkers = ({ }); ret->players = ({ }); ret->pois = ({ });
	while (sublevelcount-- > -1) {
		mapping sublevel = ([]); tree->sublevels += ({sublevel});
		int pos = sizeof(decomp) - sizeof(data);
		//The persistent level (one past the sublevel count) has no name field.
		if (sublevelcount >= 0) sublevel->lvlname = data->sscanf("%-4H")[0];
		[int sz, int count] = data->sscanf("%-8c%-4c");
		int endpoint = sizeof(data) + 4 - sz; //The size includes the count, so adjust our position accordingly
		//write("[%X] Level %O size %d count %d\n", pos, sublevel->lvlname, sz, count);
		array objects = ({});
		while (count--) {
			//objtype, class, level, prop
			array obj = data->sscanf("%-4c%-4H%-4H%-4H");
			if (obj[0]) {
				//Actor
				obj += data->sscanf("%-4c%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4c"); //Transform (rotation/translation/scale)
			} else {
				//Object/component
				obj += data->sscanf("%-4H");
			}
			objects += ({obj});
		}
		sublevel->objects = objects;
		[int coll] = data->sscanf("%-4c");
		sublevel->collectables = ({ });
		while (coll--) sublevel->collectables += ({data->sscanf("%-4H%-4H")});
		//Not sure what extra bytes there might be. Also, what if we're already past this point?
		if (sizeof(data) > endpoint) sublevel->post_collectables_bytes = data->read(sizeof(data) - endpoint);
		[int entsz, int nument] = data->sscanf("%-8c%-4c");
		endpoint = sizeof(data) + 4 - entsz;
		//Note that nument ought to be the same as the object count (and therefore sizeof(objects)) from above
		for (int i = 0; i < sizeof(objects) && i < nument; ++i) {
			mapping obj = ([]); objects[i] += ({obj});
			[obj->ver, obj->flg, int sz] = data->sscanf("%-4c%-4c%-4c");
			int propend = sizeof(data) - sz;
			int interesting = 0; //has_value(objects[i][1], "Char_Player");
			if (interesting) write("INTERESTING: %O\n", objects[i]);
			//if (!seen[objects[i][1]]) {write("OBJECT %O\n", (objects[i][1] / ".")[-1] - "\0"); seen[objects[i][1]] = 1;}
			if (objects[i][0]) {
				//Actor
				[obj->parlvl, obj->parpath, int components] = data->sscanf("%-4H%-4H%-4c");
				obj->components = ({ });
				while (components--) obj->components += ({data->sscanf("%-4H%-4H")});
			} else {
				//Object. Nothing interesting here.
			}
			//Properties. If chain, expect more meaningful data after the None - otherwise, everything up to the end marker will be discarded.
			mapping parse_properties(int end, int(1bit) chain, string path) {
				mapping ret = ([]);
				ret->_raw = ((string)data)[..sizeof(data) - end - 1]; //HACK
				while (sizeof(data) > end) {
					[string prop] = data->sscanf("%-4H");
					if (prop == "None\0") break; //There MAY still be a type after that, but it won't be relevant. If there is, it'll be skipped in the END part.
					//To search for something found by scanning the strings:
					//if (prop == "mVisitedAreas\0") write("*** FOUND %O --> %O\n", path, prop);
					[string type] = data->sscanf("%-4H");
					if (interesting) write("[%s] Prop %O %O\n", path, prop, type);
					[int sz, int idx] = data->sscanf("%-4c%-4c");
					if (type == "BoolProperty\0") {
						//Special-case: Doesn't have a type string, has the value in there instead
						[ret[prop], int zero] = data->sscanf("%c%c");
					} else if (prop == "mFogOfWarRawData\0") { data->sscanf("%-4H%c"); //HACK - Don't dump the FOW to the console
					} else if ((<"ArrayProperty\0", "SetProperty\0">)[type]) {
						//Complex types have a single type
						[string type, int zero] = data->sscanf("%-4H%c");
						if (type == "None\0") {data->read(sz); sz = 0; continue;} //Empty array???
						int end = sizeof(data) - sz;
						[int elements] = data->sscanf("%-4c");
						array arr = ({ });
						if (interesting) write("Subtype %O, %d elem\n", type, elements);
						while (elements--) {
							switch (type) {
								case "ObjectProperty\0": arr += ({(data->sscanf("%-4H%-4H")[*] - "\0") * " :: "}); break;
								case "StructProperty\0": {
									//if (interesting) {write("Array of struct %O\n", data->read(sizeof(data) - end)); break;}
									mapping struct = ([]);
									if (sizeof(arr)) struct->_type = arr[0]->_type;
									else {
										data->sscanf("%-4H%-4H%-8c"); //Uninteresting - mostly repeated info from elsewhere
										[struct->_type, int zero] = data->sscanf("%-4H%17c");
									}
									//struct->_raw = ((string)data)[..sizeof(data) - end - 1];
									switch (struct->_type) {
										case "SpawnData\0": case "MapMarker\0": //A lot will be property lists
											struct |= parse_properties(end, 1, path + " --> " + prop - "\0");
											break;
										default: break; //Unknown - just skip to the next one
									}
									arr += ({struct});
									break;
								}
								case "ByteProperty\0": arr += data->sscanf("%c"); break;
								default: if (interesting) write("UNKNOWN ARRAY SUBTYPE %O [%d]\n", type, elements + 1); break;
							}
						}
						sz = sizeof(data) - end;
						ret[prop] = arr;
					} else if (type == "ByteProperty\0") {
						[string type, int zero, ret[prop]] = data->sscanf("%-4H%c%c");
						--sz;
					} else if (type == "EnumProperty\0") {
						[string type, int zero] = data->sscanf("%-4H%c");
						int end = sizeof(data) - sz;
						[ret[prop]] = data->sscanf("%-4H");
						sz = sizeof(data) - end;
					} else if (type == "MapProperty\0") {
						//Mapping types have two types (key and value)
						[string keytype, string valtype, int zero] = data->sscanf("%-4H%-4H%c");
					} else if (type == "StructProperty\0") {
						//Struct types have more padding
						[string type, int zero] = data->sscanf("%-4H%17c");
						if (interesting) write("Type %O\n", type);
						int end = sizeof(data) - sz;
						switch (type) {
							case "InventoryStack\0": case "Vector_NetQuantize\0": {
								//The stack itself is a property list. But a StructProperty inside it has less padding??
								//write("RAW INVENTORY %O\n", ((string)data)[..sizeof(data) - end - 1]);
								ret[prop] = parse_properties(end, 0, path + " --> " + prop - "\0");
								break;
							}
							case "InventoryItem\0": {
								[int padding, ret[prop], int unk] = data->sscanf("%-4c%-4H%-4c");
								break;
							}
							case "LinearColor\0": {
								ret[prop] = data->sscanf("%-4F%-4F%-4F%-4F");
								break;
							}
							case "Vector\0": {
								//The wiki says these are floats, but the size seems to be 24,
								//which is enough for three doubles. Is the size always the same?
								//Note also that mLastSafeGroundPositions seems to be repeated.
								//Is it necessary to combine into an array??
								ret[prop] = data->sscanf("%-8F%-8F%-8F");
								break;
							}
							default: break;
						}
						sz = sizeof(data) - end;
					} else if (type == "IntProperty\0") {
						[int zero, ret[prop]] = data->sscanf("%c%-4c");
						sz -= 4;
					} else if (type == "FloatProperty\0") {
						[int zero, ret[prop]] = data->sscanf("%c%-4F");
						sz -= 4;
					} else if (type == "DoubleProperty\0") {
						[int zero, ret[prop]] = data->sscanf("%c%-8F");
						sz -= 8;
					} else if (type == "StrProperty\0") {
						if (sz == 4) {
							//If the string is empty, the padding byte seems to be
							//missing, so there's just four bytes of zeroes, not five.
							ret[prop] = "";
							data->read(1);
						} else {
							int end = sizeof(data) - sz - 1;
							[int zero, ret[prop]] = data->sscanf("%c%-4H");
							sz = sizeof(data) - end;
						}
					} else if (type == "ObjectProperty\0") {
						int end = sizeof(data) - sz - 1;
						[int zero, string lvl, string path] = data->sscanf("%c%-4H%-4H");
						ret[prop] = lvl + " :: " + path;
						sz = sizeof(data) - end;
					} else {
						//Primitive types have no type notation
						[int zero] = data->sscanf("%c");
					}
					if (sz) data->read(sz);
				}
				if (!chain && sizeof(data) > end)
					ret->_residue = data->read(sizeof(data) - end);
				return ret;
			}
			mapping prop = obj->prop = parse_properties(propend, 0, objects[i][1] - "\0");
			if (interesting) write("Properties %O\n", prop);
			if (has_value(objects[i][1], "Pickup_Spawnable")) {
				string id = (replace(prop["mPickupItems\0"][?"Item\0"] || "", "\0", "") / ".")[-1];
				int num = prop["mPickupItems\0"][?"NumItems\0"];
				ret->loot += ({({id, num, objects[i][9..11]})});
				//write("Spawnable: (%.0f,%.0f,%.0f) %d of %s\n", objects[i][9], objects[i][10], objects[i][11], num, id);
			}
			if (has_value(objects[i][1], "PlayerState") && prop["mVisitedAreas\0"]) {
				//write("Have visited: %O\n", prop["mVisitedAreas\0"]);
				ret->visited_areas = prop["mVisitedAreas\0"][*] - "\0";
			}
			if (has_value(objects[i][1], "FGMapManager") && prop["mMapMarkers\0"]) {
				//write("Map markers: %O\n", prop["mMapMarkers\0"]);
				ret->mapmarkers = prop["mMapMarkers\0"];
			}
			if (objects[i][1] == "/Game/FactoryGame/World/Benefit/DropPod/BP_DropPod.BP_DropPod_C\0")
				ret->crashsites += ({({(objects[i][3] / ".")[-1], objects[i][9..11]})});
			if (objects[i][1] == "/Game/FactoryGame/Character/Creature/BP_CreatureSpawner.BP_CreatureSpawner_C\0")
				ret->spawners += ({({(objects[i][3] / ".")[-1], objects[i][9..11], prop["mSpawnData\0"]})});
			if (objects[i][1] == "/Game/FactoryGame/Character/Player/Char_Player.Char_Player_C\0")
				ret->players += ({({prop["mCachedPlayerName\0"] - "\0", objects[i][9..11], prop})});
			if (string label = ([
				"/Game/FactoryGame/Buildable/Factory/SpaceElevator/Build_SpaceElevator.Build_SpaceElevator_C\0": "Space El",
				"/Game/FactoryGame/Buildable/Factory/TradingPost/Build_TradingPost.Build_TradingPost_C\0": "HUB",
				//TODO: Also include radar towers? Need a way to distinguish them. Do they have names?
				//Would it be worth identifying the biome that a radar tower is in? "Radar Tower (Grasslands)"
			])[objects[i][1]])
				ret->pois += ({({label, objects[i][9..11], prop})});
		}
		if (sizeof(data) > endpoint) data->post_objects_bytes = data->read(sizeof(data) - endpoint);
		[int collected] = data->sscanf("%-4c");
		sublevel->collecteds = ({ });
		while (collected--) sublevel->collecteds += ({data->sscanf("%-4H%-4H")});
	}
	//The wiki says there's a 32-bit zero before this count, but I don't see it.
	//It's also possible that this refcnt isn't even here. Presumably no refs??
	if (sizeof(data)) {
		tree->references = ({ });
		[int refcnt] = data->sscanf("%-4c");
		while (refcnt--) tree->references += ({data->sscanf("%-4H%-4H")});
	}
	if (sizeof(data)) write("[%X] Remaining: %d %O\n\n", sizeof(decomp) - sizeof(data), sizeof(data), data->read(128));

	//------------- Augment the loot list from the pristine file -------------//
	//Which loot items do we already have?
	mapping haveloot = ret->haveloot = ([]);
	foreach (ret->loot, [string item, int num, array(float) pos]) {
		if (!haveloot[item]) haveloot[item] = ([]);
		haveloot[item][sprintf("%d,%d,%d", @(array(int))pos)] = num;
	}
	//Which witnesses are we aware of?
	multiset witness_crash = (multiset)ret->crashsites[*][0], witness_spawn = (multiset)ret->spawners[*][0];
	//Okay. So, for all the loot in the pristine file, do we have both its witnesses?
	foreach (persist->loot || ([]); string item; mapping locs) {
		mapping thisloot = haveloot[item];
		foreach (locs; string key; [int num, string cr, float crdist, string sp, float spdist]) {
			//If it's in the savefile and not removed, keep it; it's possible the quantity
			//has dropped (if you had a partial stack of that item and a full inventory, so
			//you picked up only some).
			if (thisloot[?key]) continue;
			//If we have both the witnesses - the nearest crash and the nearest spawner - it's
			//highly likely you've been to the location and removed the item. This is still
			//far from certain, though. You might have gotten close enough to trigger the
			//spawner to be loaded, but not close enough to trigger the item. If that happens,
			//the tool won't report that item until you get close enough to load it in.
			if (witness_crash[cr + "\0"] && witness_spawn[sp + "\0"]) continue;
			//Okay. It looks likely that this one hasn't been loaded. Add it.
			//Note that we don't create the mapping until this point. If all of an item have
			//been collected, they are simply not available any more.
			if (!thisloot) thisloot = haveloot[item] = ([]);
			thisloot[key] = num;
		}
	}
	//Summarize total loot for convenience
	ret->total_loot = ({ });
	foreach (haveloot; string id; mapping locs)
		ret->total_loot += ({({id, L10n(id), `+(@values(locs))})});
	sort(ret->total_loot[*][0], ret->total_loot);

	//------------- Do some translations and tidyups for convenience -------------//
	array markers = ({ });
	foreach (ret->mapmarkers, mapping mark) {
		//NOTE: A marker with MarkerID\0 of 255 seems possibly to have been deleted??
		//It's like the slot is left in the array but the marker is simply not shown.
		//We suppress those from our array, as they are uninteresting.
		if (mark["MarkerID\0"] == 255) continue;
		//Would be nice to show if the marker is highlighted. This info may actually be
		//stored the other way around - a flag on the player saying "highlight this marker".
		markers += ({([
			"MarkerID": mark["MarkerID\0"],
			"CategoryName": mark["CategoryName\0"] - "\0",
			"Color": mark["Color\0"],
			"IconID": mark["IconID\0"],
			"Name": mark["Name\0"] - "\0",
			"compassViewDistance": mark["compassViewDistance\0"] - "\0",
			"Location": ({mark["Location\0"]["X\0"], mark["Location\0"]["Y\0"], mark["Location\0"]["Z\0"]}),
		])});
	}
	ret->mapmarkers = markers;
	//TODO: Locate key structures such as the HUB and Skyscar, providing their coordinates.
	//They can then be used like map markers in the front end.

	return ret;
}

array(int) coords_to_pixels(array(float) pos) {
	//To convert in-game coordinates to pixel positions:
	//1) Rescale from 750000.0,750000.0 to 5000,5000 (TODO: Adjust if the map coords are wrong)
	//2) Reposition since pixel coordinates have to use (0,0) at the corner
	float x = (pos[0] + 324600.0) * 2 / 300;
	float y = (pos[1] + 375000.0) * 2 / 300;
	//Should we limit this to (0,0)-(5000,5000)?
	return ({(int)x, (int)y});
}

void set_pixel_safe(Image.Image img, int x, int y, int r, int g, int b) {
	if (x < 0 || y < 0 || x >= img->xsize() || y >= img->ysize()) return; //Out of bounds, ignore.
	img->setpixel(x, y, r, g, b);
}

//reference can be eg crashsites or creaturespawns
//Note that maxdist is measured diagonally as distance-squared.
array(string|float) find_nearest(array reference, array(float) pos, float|void maxdist) {
	string closest; float distance;
	foreach (reference, array ref) {
		float dist = `+(@((ref[1][*] - pos[*])[*] ** 2));
		if (maxdist && dist > maxdist) continue;
		if (!closest || dist < distance) {closest = ref[0]; distance = dist;}
	}
	return ({closest, distance});
}

void bounds_include(mapping savefile, int x, int y) {
	if (!savefile->bounds) savefile->bounds = ({x, y, x, y});
	if (savefile->bounds[0] > x) savefile->bounds[0] = x;
	if (savefile->bounds[1] > y) savefile->bounds[1] = y;
	if (savefile->bounds[2] < x) savefile->bounds[2] = x;
	if (savefile->bounds[3] < y) savefile->bounds[3] = y;
}

void annotate_find_loot(mapping savefile, Image.Image annot_map, array(float) loc, string item) {
	if (!savefile->haveloot[item]) return 0;
	//The reference location is given as a blue star
	[int basex, int basey] = coords_to_pixels(loc);
	bounds_include(savefile, basex, basey);
	for (int d = -10; d <= 10; ++d) {
		set_pixel_safe(annot_map, basex + d, basey, 0, 0, 128); //Horizontal stroke
		set_pixel_safe(annot_map, basex, basey + d, 0, 0, 128); //Vertical stroke
		int diag = (int)(d * .7071); //Multiply by root two over two
		set_pixel_safe(annot_map, basex + diag, basey + diag, 0, 0, 128); //Solidus
		set_pixel_safe(annot_map, basex + diag, basey - diag, 0, 0, 128); //Reverse Solidus
	}

	//Alright. Now to list the (up to) three instances of that item nearest to the reference location.
	//TODO: Check the quantities, and allow the user to request a certain number of the item
	array distances = ({ }), details = ({ });
	foreach (savefile->haveloot[item]; string pos; int num) {
		sscanf(pos, "%f,%f,%f", float x, float y, float z);
		float dist = (x - loc[0]) ** 2 + (y - loc[1]) ** 2 + (z - loc[2]) ** 2;
		distances += ({dist});
		details += ({({x, y, z, num})});
	}
	sort(distances, details);
	array found = ({ });
	foreach (details[..2]; int i; array details) {
		savefile->found += ({sprintf("Found %d %s at %.0f,%.0f,%.0f - %.0f away\n",
			details[3], L10n(item),
			details[0], details[1], details[2],
			(distances[i] ** 0.5) / 100.0)});
		//Mark the location and draw a line to it
		[int x, int y] = coords_to_pixels(details);
		bounds_include(savefile, x, y);
		annot_map->circle(x, y, 5, 5, 128, 192, 0);
		annot_map->circle(x, y, 4, 4, 128, 192, 0);
		annot_map->circle(x, y, 3, 3, 128, 192, 0);
		annot_map->line(basex, basey, x, y, 32, 64, 0);
	}
}

//TODO: Other map annotation types:
// - all known crash sites
// - loot, indicating (a) in file, (b) removed, (c) not yet added (using pristine file)
// - all reference locations. Using this, the front end can potentially let you click to choose a loc.

void annotate_autocrop(mapping savefile, Image.Image annot_map) {
	int padding = 50;
	savefile->annot_map = annot_map->copy(
		max(savefile->bounds[0] - padding, 0),
		max(savefile->bounds[1] - padding, 0),
		min(savefile->bounds[2] + padding, annot_map->xsize()),
		min(savefile->bounds[3] + padding, annot_map->ysize()),
	);
}

@export: mapping(string:mixed) annotate_map(mapping|string savefile, array annots) {
	if (stringp(savefile)) savefile = cached_parse_savefile(savefile) | ([]);
	savefile->annot_map = get_satisfactory_map();
	foreach (annots, array anno) {
		function func = this["annotate_" + anno[0]];
		func(savefile, savefile->annot_map, @anno[1..]);
	}
	return savefile;
}

void encode_properties(Stdio.Buffer dest, mapping props) {
	if (props->_raw) {dest->add(props->_raw); return;}
	if (props->_residue) dest->add(props->_residue);
}

//Reconstruct the main body of a savefile (which gets compressed in chunks for actual serialization)
//The tree will be cached_parse_savefile(...)->tree->savefilebody but may have been mutated.
string reconstitute_savefile_body(mapping tree) {
	Stdio.Buffer data = Stdio.Buffer();
	data->sprintf("%-4c%-4H%-4c%-4c%-4c%-4H%-4c", 6, "None\0", 0, tree->hdr1, 1, "None\0", tree->hdr2);
	foreach (tree->levelgroupinggrids, [string title, int unk17, int unk18, array info]) {
		data->sprintf("%-4H%-4c%-4c%-4c%{%-4H%-4c%}", title, unk17, unk18, sizeof(info), info);
	}
	data->sprintf("%-4c", sizeof(tree->sublevels) - 1); //Note that our array of sublevels includes the persistent level
	foreach (tree->sublevels; int i; mapping sublevel) {
		if (sublevel->lvlname) data->sprintf("%-4H", sublevel->lvlname); //Absent on the persistent level
		Stdio.Buffer level = Stdio.Buffer();
		//Object headers
		level->sprintf("%-4c", sizeof(sublevel->objects));
		foreach (sublevel->objects, array obj) {
			if (obj[0]) {
				//Actor
				level->sprintf("%-4c%-4H%-4H%-4H%-4c%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4c", @obj[..<0]); //Transform (rotation/translation/scale)
			} else {
				//Object/component
				level->sprintf("%-4c%-4H%-4H%-4H%-4H", @obj[..<0]);
			}
		}
		//Collectables
		level->sprintf("%-4c%{%-4H%-4H%}", sizeof(sublevel->collectables), sublevel->collectables);
		//Still not sure what these might be, if any.
		if (sublevel->post_collectables_bytes) level->add(sublevel->post_collectables_bytes);
		data->sprintf("%-8H", (string)level);
		level = Stdio.Buffer();
		//Objects
		level->sprintf("%-4c", sizeof(sublevel->objects)); //Should always match the number of headers
		foreach (sublevel->objects, array o) {
			mapping obj = o[-1];
			level->sprintf("%-4c%-4c", obj->ver, obj->flg);
			//All the rest of the object's information - possibly including trailing bytes - gets its length stored.
			Stdio.Buffer objbytes = Stdio.Buffer();
			if (o[0]) objbytes->sprintf("%-4H%-4H%-4c%{%-4H%-4H%}", obj->parlvl, obj->parpath, sizeof(obj->components), obj->components);
			encode_properties(objbytes, obj->prop);
			level->sprintf("%-4H", (string)objbytes);
		}
		if (sublevel->post_objects_bytes) level->add(sublevel->post_objects_bytes);
		data->sprintf("%-8H", (string)level);
		//Note that collectables are *included* in the headers size, but collecteds are *excluded* from the objects size.
		//We're still better than Adobe formats though.
		data->sprintf("%-4c%{%-4H%-4H%}", sizeof(sublevel->collecteds), sublevel->collecteds);
	}
	if (tree->references) data->sprintf("%-4c%{%-4H%-4H%}", sizeof(tree->references), tree->references);
	return sprintf("%-8H", (string)data);
}

//Reconstruct a savefile based on the parse tree. This will be cached_parse_savefile(...)->tree
//but may have been mutated in between.
@export: string reconstitute_savefile(mapping tree) {
	//Step 1: Build the savefile body
	string body = reconstitute_savefile_body(tree->savefilebody);
	Stdio.Buffer data = Stdio.Buffer();
	data->sprintf("%-4c%-4c%-4c%-4H%-4H%-4H%-4c", @tree->header);
	data->sprintf("%-8c%c%-4c%-4H%-4c%-4H%24s%-4c", @tree->header2);
	//The body gets its own size prepended to it, then gets deflated in 128k chunks.
	foreach (body / 131072.0, string chunk) {
		string defl = Gz.compress(chunk);
		data->sprintf("%-8c%-4c%-4c%c%-8c%-8c%[4]-8c%[5]-8c",
			0x222222229e2a83c1, //Magic header
			131072, 0, 3, sizeof(defl), sizeof(chunk));
		data->add(defl);
	}
	return (string)data;
}
