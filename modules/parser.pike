inherit annotated;
@retain: mapping(string:mapping(string:mixed)) parse_cache = ([]);

//Ensure that a file name is a valid save file. Can be used with completely untrusted names, and
//will only return true if it is both safe and valid.
@export: int(1bit) check_savefile_name(string fn) {
	return has_value(get_dir(SAVE_PATH), fn);
}

@export: mapping cached_parse_savefile(string fn) {
	//NOTE: This does not validate the file name by ensuring that it is found in the directory.
	//If the file name comes from an untrusted source, first call check_savefile_name() above.
	string filename = SAVE_PATH + "/" + fn;
	int mtime = file_stat(filename)->?mtime;
	if (!mtime) return (["mtime": 0]); //File not found
	if (parse_cache[fn]->?mtime == mtime) return parse_cache[fn];
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
	[int ver1, int ver2, int build, string mapname, string params, string sessname, int playtime] = data->sscanf("%-4c%-4c%-4c%-4H%-4H%-4H%-4c");
	if (ver1 < 13) return ret; //There seem to be some differences with really really old savefiles
	ret->session = sessname[..<1];
	//visibility is "private", "friends only", etc. Not sure what the byte values are.
	//I've no idea what the session ID is at this point but it seems to stay constant for one session. It's always 22 bytes (plus the null).
	[int timestamp, int visibility, int objver, string modmeta, int modflags, string sessid] = data->sscanf("%-8c%c%-4c%-4H%-4c%-4H");
	data->read(24); //A bunch of uninteresting numbers. Possibly includes an RNG seed?
	[int cheats] = data->sscanf("%-4c"); //?? Whether AGSes are used?
	//The rest of the file is a series of compressed chunks. Each blob of deflated data has a
	//header prepended which is 49 bytes long.
	string decomp = "";
	while (sizeof(data)) {
		//Chunk header is a fixed eight byte string
		//Oddly, the inflated size is always 131072, even on the last chunk, which has whatever's left.
		//A lot of this is guesses, esp since most of this seems to be fixed format (eg type is always 3,
		//but I'm guessing that's a one-byte marker saying "gzipped"). In the last 24 bytes, there seem
		//to be more copies of the same information, no idea why.
		//werror("%O\n", ((string)data)[..20]);
		[string chunkhdr, int inflsz, int zero1, int type, int deflsz, int zero2, string unk9] = data->sscanf("%8s%-4c%-4c%c%-4c%-4c%24s");
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
	//Most of these are fixed and have unknown purpose
	[int unk10, string unk11, int zero3, int unk12, int unk13, string unk14, int unk15] = data->sscanf("%-4c%-4H%-4c%-4c%-4c%-4H%-4c");
	for (int i = 0; i < 5; ++i) {
		[string title, int unk17, int unk18, int n] = data->sscanf("%-4H%-4c%-4c%-4c");
		//write("Next section: %d %O (%x/%x)\n", n, title, unk17, unk18);
		while (n--) {
			[string unk19, int unk20] = data->sscanf("%-4H%-4c");
		}
	}
	[int sublevelcount] = data->sscanf("%-4c");
	//write("Sublevels: %d\n", sublevelcount);
	multiset seen = (<>);
	ret->total_loot = ([]);
	ret->crashsites = ({ }); ret->loot = ({ }); ret->visited_areas = ({ });
	ret->spawners = ({ }); ret->mapmarkers = ({ }); ret->players = ({ });
	while (sublevelcount-- > -1) {
		int pos = sizeof(decomp) - sizeof(data);
		//The persistent level (one past the sublevel count) has no name field.
		[string lvlname, int sz, int count] = data->sscanf(sublevelcount < 0 ? "%0s%-8c%-4c" : "%-4H%-8c%-4c");
		int endpoint = sizeof(data) + 4 - sz; //The size includes the count, so adjust our position accordingly
		//write("[%X] Level %O size %d count %d\n", pos, lvlname, sz, count);
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
		[int coll] = data->sscanf("%-4c");
		while (coll--) {
			[string lvl, string path] = data->sscanf("%-4H%-4H");
			//write("Collectable: %O\n", path);
		}
		//Not sure what extra bytes there might be. Also, what if we're already past this point?
		if (sizeof(data) > endpoint) data->read(sizeof(data) - endpoint);
		[int entsz, int nument] = data->sscanf("%-8c%-4c");
		endpoint = sizeof(data) + 4 - entsz;
		//Note that nument ought to be the same as the object count (and therefore sizeof(objects)) from above
		for (int i = 0; i < sizeof(objects) && i < nument; ++i) {
			[int ver, int flg, int sz] = data->sscanf("%-4c%-4c%-4c");
			int propend = sizeof(data) - sz;
			int interesting = 0; //has_value(objects[i][1], "Char_Player");
			if (interesting) write("INTERESTING: %O\n", objects[i]);
			//if (!seen[objects[i][1]]) {write("OBJECT %O\n", (objects[i][1] / ".")[-1] - "\0"); seen[objects[i][1]] = 1;}
			if (objects[i][0]) {
				//Actor
				[string parlvl, string parpath, int components] = data->sscanf("%-4H%-4H%-4c");
				while (components--) {
					[string complvl, string comppath] = data->sscanf("%-4H%-4H");
					if (interesting) write("Component %O %O\n", complvl, comppath);
				}
			} else {
				//Object. Nothing interesting here.
			}
			//Properties. If chain, expect more meaningful data after the None - otherwise, everything up to the end marker will be discarded.
			mapping parse_properties(int end, int(1bit) chain, string path) {
				mapping ret = ([]);
				//write("RAW PROPERTIES %O\n", ((string)data)[..sizeof(data) - end - 1]);
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
				if (!chain && sizeof(data) > end) {
					string rest = data->read(sizeof(data) - end);
					//if (rest != "\0" * sizeof(rest)) write("REST %O\n", rest);
				}
				return ret;
			}
			mapping prop = parse_properties(propend, 0, objects[i][1] - "\0");
			if (interesting) write("Properties %O\n", prop);
			if (has_value(objects[i][1], "Pickup_Spawnable")) {
				string id = (replace(prop["mPickupItems\0"][?"Item\0"] || "", "\0", "") / ".")[-1];
				int num = prop["mPickupItems\0"][?"NumItems\0"];
				ret->total_loot[id] += num;
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
		}
		if (sizeof(data) > endpoint) data->read(sizeof(data) - endpoint);
		[int collected] = data->sscanf("%-4c");
		while (collected--) {
			[string lvl, string path] = data->sscanf("%-4H%-4H");
			//write("Collected %O\n", path);
		}
	}
	//The wiki says there's a 32-bit zero before this count, but I don't see it.
	//It's also possible that this refcnt isn't even here. Presumably no refs??
	if (sizeof(data)) {
		[int refcnt] = data->sscanf("%-4c");
		while (refcnt--) data->sscanf("%-4H%-4H");
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
	return ret;
}
