inherit annotated;
@retain: mapping(string:mapping(string:mixed)) parse_cache = ([]);
constant CACHE_VALIDITY = 3; //Bump this number to invalidate older cache entries.

//Ensure that a file name is a valid save file. Can be used with completely untrusted names, and
//will only return true if it is both safe and valid.
@export: int(1bit) check_savefile_name(string fn) {
	return has_value(get_dir(SATIS_SAVE_PATH), fn);
}

class ObjectRef(string level, string path, int|void soft) {
	constant _is_object_ref = 1;
	protected void create() {
		level -= "\0"; path -= "\0";
	}
	//Note that the "soft" part of a softobjectreference isn't reflected in the %O. If this
	//becomes a problem, consider making SoftObjectRef a separate class.
	protected string _sprintf(int type) {return (type == 's' || type == 'O') && sprintf("ObjectRef(%O, %O)", level, path);}
	string encode_json() {return sprintf("\"%s :: %s\"", level, path);}
}

//Properties. If chain, expect more meaningful data after the None - otherwise, everything up to the end marker will be discarded.
mapping parse_properties(Stdio.Buffer data, int end, int(1bit) chain, string path) {
	mapping ret = ([]);
	//ret->_raw = ((string)data)[..sizeof(data) - end - 1]; ret->_path = path; //HACK
	ret->_keyorder = ({ });
	while (sizeof(data) > end) {
		[string prop] = data->sscanf("%-4H");
		if (prop == "None\0") break; //There MAY still be a type after that, but it won't be relevant. If there is, it'll be skipped in the END part.
		//To search for something found by scanning the strings:
		//if (prop == "mVisitedAreas\0") write("*** FOUND %O --> %O\n", path, prop);
		[string type] = data->sscanf("%-4H");
		mapping p = (["type": type - "\0"]);
		[int sz, p->idx] = data->sscanf("%-4c%-4c");
		if (p->idx) {
			//Currently the ONLY attribute that uses this is mLastSafeGroundPositions
			//There are three such positions stored, and they're simply duplicated.
			//We wrap it up into another layer, ensuring that we keep everything.
			//Note that this code won't trigger until we hit the second one of the
			//arrayish, so the first one will already have been saved in the regular
			//way. Note that we don't check that the index is actually increasing,
			//just that it's nonzero on all but the first.
			mapping prev = ret[prop - "\0"];
			if (!prev) werror("NO PREV BUT IDX %O %O %O\n", path, prop, p->idx);
			if (prev->type == "_repetition")
				//It's a third or subsequent of the same thing.
				prev->values += ({p});
			else
				//It's the second. Build the array.
				ret[prop - "\0"] = ([
					"type": "_repetition",
					"values": ({prev, p}),
				]);
		}
		else {
			ret[prop - "\0"] = p;
			ret->_keyorder += ({prop - "\0"}); //To ensure perfect round-tripping, sort the keys by original file order
		}
		int end;
		if (type == "BoolProperty\0") {
			//Special-case: Doesn't have a type string, has the value in there instead
			[p->value, int zero] = data->sscanf("%c%c");
		} else if ((<"ArrayProperty\0", "SetProperty\0">)[type]) {
			//Complex types have a single type
			[p->subtype, int zero] = data->sscanf("%-4H%c");
			//Empty array??? Unconfirmed. May have been only due to a prior bug.
			if (p->subtype == "None\0") {write("None type in %O %O", type, path); data->read(sz); sz = 0; continue;}
			p->subtype -= "\0";
			end = sizeof(data) - sz;
			[int elements] = data->sscanf("%-4c");
			array arr = ({ });
			while (elements--) {
				switch (p->subtype) {
					case "InterfaceProperty": //Behaves basically the same as an ObjectRef. Should they be distinguished in any way?
					case "ObjectProperty": arr += ({ObjectRef(@data->sscanf("%-4H%-4H"))}); break;
					case "SoftObjectProperty": arr += ({ObjectRef(@data->sscanf("%-4H%-4H%-4c"))}); break;
					case "StructProperty": {
						mapping struct = ([]);
						if (sizeof(arr)) struct->_type = arr[0]->_type;
						else {
							data->sscanf("%-4H%-4H%-8c"); //Uninteresting - mostly repeated info from elsewhere
							[struct->_type, int zero] = data->sscanf("%-4H%17c");
							struct->_type -= "\0";
						}
						//struct->_raw = ((string)data)[..sizeof(data) - end - 1];
						switch (struct->_type) {
							case "Vector": struct->value = data->sscanf("%-4F%-4F%-4F"); break;
							case "LinearColor": struct->value = data->sscanf("%-4F%-4F%-4F%-4F"); break;
							default: //A lot will be property lists
								struct |= parse_properties(data, end, 1, path + " --> " + prop - "\0");
								break;
						}
						arr += ({struct});
						break;
					}
					case "ByteProperty": arr += data->sscanf("%c"); break;
					case "IntProperty": arr += data->sscanf("%-4c"); break;
					case "Int64Property": arr += data->sscanf("%-8c"); break;
					case "FloatProperty": arr += data->sscanf("%-4F"); break;
					case "EnumProperty": //Enums are stored as strings
					case "StrProperty": arr += data->sscanf("%-4H"); break;
					default:
						//write("UNKNOWN ARRAY SUBTYPE %O [%d elem, %d bytes] %O\n", p->subtype, elements + 1, sizeof(data) - end, ((string)data)[..sizeof(data) - end - 1]);
						elements = 0;
						break;
				}
			}
			sz = sizeof(data) - end;
			p->value = arr;
		} else if (type == "ByteProperty\0") {
			[p->subtype, int zero, p->value] = data->sscanf("%-4H%c%c");
			p->subtype -= "\0";
			--sz;
		} else if (type == "EnumProperty\0") {
			[p->subtype, int zero] = data->sscanf("%-4H%c");
			p->subtype -= "\0";
			end = sizeof(data) - sz;
			p->value = data->sscanf("%-4H")[0] - "\0";
		} else if (type == "MapProperty\0") {
			//Mapping types have two types (key and value)
			[p->keytype, p->valtype, int zero] = data->sscanf("%-4H%-4H%c");
			end = sizeof(data) - sz;
			//write("GOT A MAP %O %O %O\n", path, p->keytype, p->valtype);
			//if (sizeof(ret->_raw) < 2048) werror("Raw: %O\n", ret->_raw);
		} else if (type == "StructProperty\0") {
			//Struct types have more padding
			[p->subtype, int zero] = data->sscanf("%-4H%17c");
			p->subtype -= "\0";
			end = sizeof(data) - sz;
			switch (p->subtype) {
				case "InventoryItem": {
					[int padding, p->value, p->unk] = data->sscanf("%-4c%-4H%-4c");
					break;
				}
				case "LinearColor": {
					p->value = data->sscanf("%-4F%-4F%-4F%-4F");
					break;
				}
				case "Vector": {
					//The wiki says these are floats, but the size seems to be 24,
					//which is enough for three doubles. Is the size always the same?
					p->value = data->sscanf("%-8F%-8F%-8F");
					break;
				}
				case "Quat":
				case "Box":
				case "FluidBox":
				case "RailroadTrackPosition":
				case "DateTime":
				case "ClientIdentityInfo":
				case "Guid":
					//For now these can land in the residue
					//werror("TODO: StructProperty %O\n", p->subtype);
					break;
				default:
					p->value = parse_properties(data, end, 0, path + " --> " + prop - "\0");
					break;
			}
			sz = sizeof(data) - end;
		} else if (type == "IntProperty\0") {
			[int zero, p->value] = data->sscanf("%c%-4c");
			sz -= 4;
		} else if (type == "FloatProperty\0") {
			[int zero, p->value] = data->sscanf("%c%-4F");
			sz -= 4;
		} else if (type == "DoubleProperty\0") {
			[int zero, p->value] = data->sscanf("%c%-8F");
			sz -= 8;
		} else if (type == "StrProperty\0") {
			end = sizeof(data) - sz - 1;
			[int zero, p->value] = data->sscanf("%c%-4H");
			p->value -= "\0";
		} else if (type == "ObjectProperty\0") {
			end = sizeof(data) - sz - 1;
			p->value = ObjectRef(@data->sscanf("%*c%-4H%-4H"));
		} else {
			//Primitive types have no type notation
			[int zero] = data->sscanf("%c");
		}
		if (end) sz = sizeof(data) - end;
		if (sz) p->residue = data->read(sz);
	}
	if (!chain && sizeof(data) > end)
		ret->_residue = data->read(sizeof(data) - end);
	//else ret->_raw = ret->_raw[..sizeof(ret->_raw) - (sizeof(data) - end) - 1]; //More hack
	return ret;
}

@export: mapping cached_parse_savefile(string fn) {
	//NOTE: This does not validate the file name by ensuring that it is found in the directory.
	//If the file name comes from an untrusted source, first call check_savefile_name() above.
	int mtime = file_stat(SATIS_SAVE_PATH + "/" + fn)->?mtime;
	if (!mtime) return (["mtime": 0]); //File not found
	if (mapping c = parse_cache[fn]) {
		if (c->mtime == mtime && c->validity == CACHE_VALIDITY) return parse_cache[fn];
		//Otherwise ignore the cached entry and reconstruct.
	}
	//NOTE: If this function is made asynchronous or there is any other way that this could run
	//reentrantly, place a stub in the cache, and validate the stub before returning, blocking
	//until the first parser has finished.
	return parse_cache[fn] = (["mtime": mtime]) | low_parse_savefile(fn);
}

//Parse a savefile, bypassing the cache. Can be used when mutation is intended.
mapping low_parse_savefile(string|zero fn) {
	if (!fn) {
		//Pick the latest file and parse that.
		array files = get_dir(SATIS_SAVE_PATH), paths = SATIS_SAVE_PATH + "/" + files[*];
		array times = file_stat(paths[*])->mtime;
		sort(times, files);
		fn = files[-1];
	}
	Stdio.Buffer data = Stdio.Buffer(Stdio.read_file(SATIS_SAVE_PATH + "/" + fn));
	data->read_only();
	return parse_savefile_data(data);
}

//Even lower level helper for when you want to test an in-memory buffer
mapping parse_savefile_data(Stdio.Buffer data) {
	mapping ret = ([]);
	//Huh. Unlike the vast majority of games out there, Satisfactory has info on its official wiki.
	//https://satisfactory.wiki.gg/wiki/Save_files
	//mapname is always "Persistent_Level"; sessname is what the user entered to describe the session.
	mapping tree = ret->tree = ([]); //Everything needed to reconstruct the original savefile.
	[int ver1, int ver2, int build] = tree->header = data->sscanf("%-4c%-4c%-4c");
	if (ver1 < 13) return ret; //There seem to be some differences with really really old savefiles
	if (ver1 > 1<<30) return ret; //Probably not a valid savefile.
	if (ver1 >= 14) [tree->savename] = data->sscanf("%-4H");
	[string mapname, string params, string sessname, int playtime] = tree->header1 = data->sscanf("%-4H%-4H%-4H%-4c");
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
	ret->crashsites = ({ }); ret->loot = ({ });
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
			//I'm not sure what changed in version 14 (v1.1) but there seems to be
			//another 4-byte integer here - with a fixed value, I think.
			mapping xtra = ([]);
			if (ver1 >= 14) xtra->unkv14 = data->sscanf("%-4c")[0];
			if (sizeof(obj) < 4) {
				write("\e[1;31m[%X] Bad parse - insufficient values\e[0m %O\n", sizeof(decomp) - sizeof(data), obj);
				if (sizeof(objects)) write("\e[1;33mPrevious entity:\e[0m %O\n", objects[-1]);
			}
			if (obj[0]) {
				//Actor
				obj += data->sscanf("%-4c%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4c"); //Transform (rotation/translation/scale)
			} else {
				//Object/component
				obj += data->sscanf("%-4H");
			}
			obj += ({xtra});
			objects += ({obj});
		}
		sublevel->objects = objects;
		int coll;
		if (sizeof(data) - endpoint >= 4) {
			//The collectables section sometimes seems to be omitted. Make sure there's room
			//for at least the count.
			coll = data->read_le_int(4);
		}
		sublevel->collectables = ({ });
		while (coll--) sublevel->collectables += ({data->sscanf("%-4H%-4H")});
		//Not sure what extra bytes there might be. Also, what if we're already past this point?
		if (sizeof(data) > endpoint) sublevel->post_collectables_bytes = data->read(sizeof(data) - endpoint);
		[int entsz, int nument] = data->sscanf("%-8c%-4c");
		endpoint = sizeof(data) + 4 - entsz;
		//Note that nument ought to be the same as the object count (and therefore sizeof(objects)) from above
		for (int i = 0; i < sizeof(objects) && i < nument; ++i) {
			mapping obj = objects[i][-1];
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
			mapping prop = obj->prop = parse_properties(data, propend, 0, objects[i][1] - "\0");
			if (interesting) write("Properties %O\n", prop);
			if (has_value(objects[i][1], "Pickup_Spawnable")) {
				string id = (replace(prop->mPickupItems->value->Item->value, "\0", "") / ".")[-1];
				ret->loot += ({({id, prop->mPickupItems->value->NumItems->value, objects[i][9..11]})});
			}
			if (has_value(objects[i][1], "FGMapManager") && prop->mMapMarkers) {
				ret->mapmarkers = prop->mMapMarkers->value;
			}
			if (objects[i][1] == "/Game/FactoryGame/World/Benefit/DropPod/BP_DropPod.BP_DropPod_C\0")
				ret->crashsites += ({({(objects[i][3] / ".")[-1], objects[i][9..11]})});
			if (objects[i][1] == "/Game/FactoryGame/Character/Creature/BP_CreatureSpawner.BP_CreatureSpawner_C\0")
				ret->spawners += ({({(objects[i][3] / ".")[-1], objects[i][9..11], prop["mSpawnData\0"]})});
			if (objects[i][1] == "/Game/FactoryGame/Character/Player/Char_Player.Char_Player_C\0")
				ret->players += ({({(prop->mCachedPlayerName->?value || "Unnamed") - "\0", objects[i][9..11], prop})});
			if (string label = ([
				"/Game/FactoryGame/Buildable/Factory/SpaceElevator/Build_SpaceElevator.Build_SpaceElevator_C\0": "Space El",
				"/Game/FactoryGame/Buildable/Factory/TradingPost/Build_TradingPost.Build_TradingPost_C\0": "HUB",
				//TODO: Also include radar towers? Need a way to distinguish them. Do they have names?
				//Would it be worth identifying the biome that a radar tower is in? "Radar Tower (Grasslands)"
			])[objects[i][1]])
				ret->pois += ({({label, objects[i][9..11], prop})});
		}
		if (sizeof(data) > endpoint) sublevel->post_objects_bytes = data->read(sizeof(data) - endpoint);
		//HYPOTHESIS: Save version 14 inserts another integer here. In the sublevels,
		//it has unknown meaning, but in the persistent level, it's the number of...
		//somethings. Of unknown meaning. But they're strings.
		if (ver1 >= 14) {
			[sublevel->unkv14] = data->sscanf("%-4c");
			if (!sublevel->lvlname) sublevel->unkv14 = data->sscanf("%-4H" * sublevel->unkv14);
		}
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
	sort(ret->total_loot[*][1], ret->total_loot);

	//------------- Do some translations and tidyups for convenience -------------//
	array markers = ({ });
	foreach (ret->mapmarkers, mapping mark) {
		//NOTE: A marker with MarkerID\0 of 255 seems possibly to have been deleted??
		//It's like the slot is left in the array but the marker is simply not shown.
		//We suppress those from our array, as they are uninteresting.
		if (mark->MarkerID->?value == 255) continue;
		//Would be nice to show if the marker is highlighted. This info may actually be
		//stored the other way around - a flag on the player saying "highlight this marker".
		mapping m = (["Location": ({
			mark->Location->value->X->value,
			mark->Location->value->Y->value,
			mark->Location->value->Z->value,
		})]);
		foreach ("MarkerID CategoryName Color IconID Name compassViewDistance" / " ", string key)
			m[key] = mark[key]->?value;
		markers += ({m});
	}
	ret->mapmarkers = markers;
	return ret;
}

void add_map_marker(mapping savefile, string label, float x, float y, float z) {
	foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
		if (obj[1] == "/Script/FactoryGame.FGMapManager\0") {
			mapping props = obj[-1]->prop;
			mapping|zero marks = props->mMapMarkers;
			if (!marks) return; //TODO
			mapping newmark = ([
				"_type": "MapMarker",
				"_keyorder": ({"MarkerID", "Location", "Name", "CategoryName", "MapMarkerType", "IconID", "Color", "Scale", "compassViewDistance"}),
				"MarkerID": (["type": "ByteProperty", "subtype": "None"]),
				"Location": (["type": "StructProperty", "subtype": "Vector_NetQuantize", "value": ([
					"X": (["type": "DoubleProperty", "value": x]),
					"Y": (["type": "DoubleProperty", "value": y]),
					"Z": (["type": "DoubleProperty", "value": z]),
					"_keyorder": ({"X", "Y", "Z"}),
				])]),
				"Name": (["type": "StrProperty", "value": label]),
				"CategoryName": (["type": "StrProperty", "value": ""]),
				"MapMarkerType": (["type": "EnumProperty", "subtype": "ERepresentationType", "value": "ERepresentationType::RT_MapMarker"]),
				"IconID": (["type": "IntProperty", "value": 347]), //350 is the default "Home" icon, 347 is a crate
				"Color": (["type": "StructProperty", "subtype": "LinearColor", "value": ({0x66/256.0, 0x33/256.0, 0x99/256.0, 1.0})]),
				"Scale": (["type": "FloatProperty", "value": 1.0]),
				"compassViewDistance": (["type": "EnumProperty", "subtype": "ECompassViewDistance", "value": "ECompassViewDistance::CVD_Off"]),
			]);
			int add = 1;
			foreach (marks->value; int i; mapping mark) if (mark->MarkerID->?value == 255) {
				//Reuse an existing marker slot. I think this is safe?
				newmark->MarkerID->value = i;
				marks->value[i] = newmark;
				add = 0;
				break;
			}
			if (add) { //aka for-else
				newmark->MarkerID->value = sizeof(marks->value);
				marks->value += ({newmark});
			}
		}
	}
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
		add_map_marker(savefile, sprintf("%d %s", details[3], L10n(item)), details[0], details[1], details[2]);
	}
}

void annotate_save(mapping savefile, Image.Image annot_map) {
	Stdio.write_file(SATIS_SAVE_PATH + "/MapMarkersAdded.sav", reconstitute_savefile(savefile->tree));
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

void annotate_fogmask(mapping savefile, Image.Image annot_map) {
	foreach (savefile->tree->savefilebody->sublevels, mapping sl) foreach (sl->objects, array obj) {
		if (obj[1] == "/Script/FactoryGame.FGMapManager\0") {
			array fog = (string)obj[-1]->prop->mFogOfWarRawData->value / 4.0;
			//Each entry in fog[] is a four-byte string representing one unit.
			//There are a total of 262144 such units, giving a resolution of 512x512.
			//Note that every string appears to be of the form "\0\0%c\377", which might
			//indicate that the blue channel is the only one carrying information, or that
			//it's stored in HSVA with the hue and saturation permanently at zero and the
			//alpha permanently full.
			//The thickness of the fog is stored per cell, with each cell being worth about
			//10x10 pixels on the map or 14-15 meters. However, the in-game map does not
			//look blocky to that extent. Current hypothesis: There is a height map for the
			//actual world (which is static), and any time the fog is lower than the height
			//of that point on the world, it is in fog. (Imagine that the fog is a low-lying
			//cloud, or something. I dunno.) The SCIM has a depth map at the same 512x512
			//that the fog itself is stored at, giving it a very blocky appearance.
			//In order to render the fog more accurately, we will need either a heightmap at
			//750000x750000 resolution, or one at 5000x5000. Either way, iterate over that,
			//and then find the correct cell to look up.
			//Fun fact: In FGMapManager.h (check CommunityResources/Headers.zip), the FOWData
			//class has centerPoint, radius, gradientHeightModifier, and useGradientFalloff.
			//Sounds like the savefile stores the height mod, but the others are predictable
			//(presumably the centerPoint is on the grid, and the radius is constant). Would
			//be very interesting to see how they correlate. It also has private members
			//mFogOfWarDataSize and mFogOfWarResolution, which might be interesting.
			foreach (fog / 512; int r; array row) {
				int y1 = r * 5000 / 512, y2 = (r + 1) * 5000 / 512 - 1;
				foreach (row; int c; string cell) {
					int x1 = c * 5000 / 512, x2 = (c + 1) * 5000 / 512 - 1;
					int visibility = cell[2];
					//Arbitrary threshold for testing
					if (visibility < 150) annot_map->box(x1, y1, x2, y2, 0, 0, 0);
				}
			}
		}
	}
}

@export: mapping(string:mixed) annotate_map(mapping|string savefile, array annots) {
	if (stringp(savefile)) savefile = low_parse_savefile(savefile); //Not using the cache so we have the option to mutate
	savefile->annot_map = get_satisfactory_map();
	foreach (annots, array anno) if (anno) {
		function func = this["annotate_" + anno[0]];
		func(savefile, savefile->annot_map, @anno[1..]);
	}
	return savefile;
}

class buffer_size(Stdio.Buffer buf, strict_sprintf_format fmt) {
	int pos, ref; //Position to store the size, and reference position to calculate it
	protected void create() {
		pos = sizeof(buf);
		buf->sprintf(fmt, 0);
		ref = sizeof(buf);
	}
	void apply() {
		string sz = sprintf(fmt, sizeof(buf) - ref);
		foreach (sz; int i; int c) buf[pos + i] = c;
	}
}

//Null-terminate a string if necessary
//Empty strings don't need them, and if it's already there, another won't be added.
string nt(string val) {
	if (val == "" || !val[-1]) return val;
	return val + "\0";
}

void encode_properties(Stdio.Buffer _orig_dest, mapping props) {
	//if (props->_raw) {dest->add(props->_raw); return;}
	Stdio.Buffer dest = Stdio.Buffer();
	//Is the order of properties significant? The game itself seems to be fine with them in any order
	//but SCIM struggles, sometimes failing to load, sometimes loading but with wrong results. Since it
	//isn't TOO costly, we just retain order. Downside: If you add a property that wasn't in the save,
	//eg if map markers had been omitted due to not having any, you have to add it to the key order too.
	//foreach (props; string name; mapping p) if (name[0] != '_') { //Simplify, don't require the key order to be specified
	foreach (props->_keyorder, string name) {mapping p = props[name]; //Enforce output order for perfect round tripping
		foreach (p->type == "_repetition" ? p->values : ({p}), mapping p) {
			dest->sprintf("%-4H%-4H", nt(name), nt(p->type));
			object prop_size = buffer_size(dest, "%-4c");
			dest->sprintf("%-4c", p->idx);
			prop_size->ref += 5; //There should always be a padding byte.
			//TODO: Everything that was resetting end or sz during parse_properties will need to update prop_size->ref
			object struct_size;
			switch (p->type) {
				case "BoolProperty": dest->sprintf("%c%c", p->value, 0); destruct(prop_size); break; //No size for these, leave it zero
				case "ArrayProperty": case "SetProperty": {
					//Complex types have a single type
					dest->sprintf("%-4H%c%-4c", nt(p->subtype), 0, sizeof(p->value));
					prop_size->ref = sizeof(dest) - 4;
					foreach (p->value; int i; mixed elem) switch (p->subtype) {
						case "InterfaceProperty": //See above, is basically same as ObjectProperty
						case "ObjectProperty": dest->sprintf("%-4H%-4H", nt(elem->level), nt(elem->path)); break;
						case "SoftObjectProperty": dest->sprintf("%-4H%-4H%-4c", nt(elem->level), nt(elem->path), elem->soft); break;
						case "StructProperty": {
							if (!i) {
								dest->sprintf("%-4H%-4H", nt(name), "StructProperty\0"); //Repeated info
								struct_size = buffer_size(dest, "%-8c");
								dest->sprintf("%-4H%17c", nt(elem->_type), 0);
								struct_size->ref = sizeof(dest);
							}
							switch (elem->_type) {
								case "Vector": dest->sprintf("%-4F%-4F%-4F", @elem->value); break;
								case "LinearColor": dest->sprintf("%-4F%-4F%-4F%-4F", @elem->value); break;
								default: //A lot will be property lists
									encode_properties(dest, elem);
									break;
							}
							break;
						}
						case "ByteProperty": dest->sprintf("%c", elem); break;
						case "IntProperty": dest->sprintf("%-4c", elem); break;
						case "Int64Property": dest->sprintf("%-8c", elem); break;
						case "FloatProperty": dest->sprintf("%-4F", elem); break;
						case "EnumProperty": //Enums are stored as strings
						case "StrProperty": dest->sprintf("%-4H", elem); break;
						default: break;
					}
					break;
				}
				case "ByteProperty":
					dest->sprintf("%-4H%c", nt(p->subtype), 0);
					prop_size->ref = sizeof(dest);
					dest->sprintf("%c", p->value);
					break;
				case "EnumProperty":
					dest->sprintf("%-4H%c", nt(p->subtype), 0);
					prop_size->ref = sizeof(dest);
					dest->sprintf("%-4H", nt(p->value));
					break;
				case "MapProperty":
					dest->sprintf("%-4H%-4H%c", p->keytype, p->valtype, 0);
					prop_size->ref = sizeof(dest);
					//The actual mapping will be in residue
					break;
				case "StructProperty": {
					//Struct types have more padding
					dest->sprintf("%-4H%17c", nt(p->subtype), 0);
					prop_size->ref = sizeof(dest);
					switch (p->subtype) {
						case "InventoryItem": {
							dest->sprintf("%-4c%-4H%-4c", 0, p->value, p->unk);
							break;
						}
						case "LinearColor": {
							dest->sprintf("%-4F%-4F%-4F%-4F", @p->value);
							break;
						}
						case "Vector": {
							//The wiki says these are floats, but the size seems to be 24,
							//which is enough for three doubles. Is the size always the same?
							//Note also that mLastSafeGroundPositions seems to be repeated.
							//Is it necessary to combine into an array??
							dest->sprintf("%-8F%-8F%-8F", @p->value);
							break;
						}
						case "Quat":
						case "Box":
						case "FluidBox":
						case "RailroadTrackPosition":
						case "DateTime":
						case "ClientIdentityInfo":
						case "Guid":
							//TODO as above, for now they come from residue
							break;
						default:
							encode_properties(dest, p->value);
							break;
					}
					break;
				}
				case "IntProperty": dest->sprintf("%c%-4c", 0, p->value); break;
				case "FloatProperty": dest->sprintf("%c%-4F", 0, p->value); break;
				case "DoubleProperty": dest->sprintf("%c%-8F", 0, p->value); break;
				case "StrProperty": dest->sprintf("%c%-4H", 0, nt(p->value)); break;
				case "ObjectProperty": dest->sprintf("%c%-4H%-4H", 0, nt(p->value->level), nt(p->value->path)); break;
				default: dest->add(0); break; //The rest (if any) will be in residue
			}
			if (p->residue) dest->add(p->residue);
			if (prop_size) prop_size->apply(); //Normally the case, but it may have been destructed
			if (struct_size) struct_size->apply();
		}
	}
	dest->sprintf("%-4H", "None\0"); //End marker. If it had a type originally, it'll be in _residue.
	if (props->_residue) dest->add(props->_residue);
	if (props->_raw && (string)dest != props->_raw) {
		string d = (string)dest, paired = String.common_prefix(({d, props->_raw}));
		//if (sizeof(d) > 1024) write("Encode failed for large [%d] object\n", sizeof(d)); else //Temporarily suppress the big ones
		write("Encode %O\nResult: [%3d] %O\nOrigin: [%3d] %O\nPaired: [%3d] %O\n",
			props, sizeof(dest), (string)dest, sizeof(props->_raw), props->_raw,
			sizeof(paired), paired,
		);
		write("Reparse: %O\n", parse_properties(Stdio.Buffer((string)dest), 0, 0, "reparse"));
	}
	_orig_dest->add(dest);
}

//Reconstruct the main body of a savefile (which gets compressed in chunks for actual serialization)
//The tree will be cached_parse_savefile(...)->tree->savefilebody but may have been mutated.
string reconstitute_savefile_body(int ver1, mapping tree) {
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
			level->sprintf("%-4c%-4H%-4H%-4H", @obj[..3]);
			if (ver1 >= 14) level->sprintf("%-4c", obj[-1]->unkv14);
			if (obj[0]) {
				//Actor
				level->sprintf("%-4c%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4F%-4c", @obj[4..<0]); //Transform (rotation/translation/scale)
			} else {
				//Object/component
				level->sprintf("%-4H", @obj[4..<0]);
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
		if (ver1 >= 14) {
			//See above in the parsing; in the sublevels, this is just an integer, but
			//in the persistent level, there's an array of strings.
			if (arrayp(sublevel->unkv14)) data->sprintf("%-4c%{%-4H%}", sizeof(sublevel->unkv14), sublevel->unkv14);
			else data->sprintf("%-4c", sublevel->unkv14);
		}
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
	string body = reconstitute_savefile_body(tree->header[0], tree->savefilebody);
	Stdio.Buffer data = Stdio.Buffer();
	data->sprintf("%-4c%-4c%-4c", @tree->header);
	if (tree->header[0] >= 14) data->sprintf("%-4H", tree->savename);
	data->sprintf("%-4H%-4H%-4H%-4c", @tree->header1);
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
