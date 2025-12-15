mapping(int:string) id_to_string = ([
	0x001b: "name",
	0x0041: "object",
 	0x006d: "duration",
 	0x006e: "speed",
	0x00db: "identity",
	0x00e1: "type",
 	0x00ee: "version",
 	0x00f0: "data",
	0x025a: "top",
	0x0351: "list",
	0x0352: "item",
 	0x0384: "flag",
 	0x0555: "variables",
 	0x06b3: "random_seed",
 	0x06b4: "random_count",
 	0x06b5: "date",
 	0x096e: "playthrough_id",
 	0x096f: "playthrough_name",
 	0x0971: "save_label",
 	0x09de: "metadata",
 	0x0c53: "members",
	0x2915: "power",
 	0x2cd7: "country",
 	0x2ce7: "enabled_dlcs",
 	0x2dc0: "locations",
 	0x2dc1: "ironman_manager",
 	0x2f44: "current_age",
	0x30a1: "great_power_manager",
	0x314a: "language_manager",
 	0x3224: "start_of_day",
 	0x3237: "compatibility",
 	0x3238: "locations_hash",
 	0x325b: "hegemons",
 	0x3477: "code_version_info",
 	0x3478: "code_hash_long",
 	0x3479: "code_hash_short",
 	0x347a: "code_timestamp",
 	0x347b: "code_branch",
 	0x347c: "game_code_info",
 	0x347d: "engine_code_info",
 	0x35c3: "code_commit",
	0x3bb5: "player_country_name",
]);

array string_lookup = ({ });
string last_string = "?";
mapping|array read_maparray(Stdio.Buffer buf, string path) {
	mapping map = ([]); array arr = ({ });
	int startpos = sizeof(buf);
	//werror("> [%d] Entering %s\n", startpos, path);
	while (sizeof(buf)) {
		int pos = sizeof(buf);
		if (pos == 173054894) werror("POS %d NEXT%{ %02x%}\n", pos, (array)(string)buf[..64]);
		int|string id = buf->read_le_int(2);
		if (id == 4) break; //End of object
		if (id == 0) {/*write("NULL entry at %d\n", pos);*/ continue;} //Do these always come in pairs? If so, it might be that it brings with it another pair of null bytes.
		//IDs 3, 12, and 15 have only ever been used for arrays. Unlike ID 20, which is used for both.
		if (id == 15) {arr += buf->sscanf("%-2H"); continue;}
		if (id == 12) {arr += buf->sscanf("%-4c"); continue;}
		if (id == 3) {arr += ({read_maparray(buf, path + "[]")}); continue;}
		if (id == 0x4b50) {
			//In a non-debug savefile, everything after the metadata is packaged up as a zip file.
			//It can be recognized by the "PK" signature (50 4b), which is then followed by 03 04.
			//Pike comes with a Filesystem.Zip interface but it's not really optimized for this
			//sort of job, so instead we do our own parsing.
			if (buf->read(2) != "\3\4") werror("WARNING: MALFORMED ZIP ARCHIVE\n");
			mapping files = ([]);
			while (sizeof(buf)) {
				[int minver, int flags, int comp, int ignore, int compsz, int decompsz, int fnlen, int xtralen] = buf->sscanf("%-2c%-2c%-2c%-8c%-4c%-4c%-2c%-2c");
				string fn = buf->read(fnlen);
				string xtra = buf->read(xtralen);
				string raw = buf->read(compsz);
				string decomp = Gz.inflate(-15)->inflate(raw);
				//assert sizeof(decomp) == decompsz
				files[fn] = decomp;
				if (buf->read(4) != "PK\3\4") break; //After all files, there's a "PK\1\2" central directory, which we don't need
			}
			//Note that we have to read both files before we can parse, as the string_lookup is generally
			//placed *after* the gamestate. No big deal as we have to have it all in memory anyway.
			buf = Stdio.Buffer(files->string_lookup); buf->read_only();
			[int unk1, int count, int unk3] = buf->sscanf("%c%-2c%-2c");
			while (sizeof(buf)) string_lookup += buf->sscanf("%-2H");
			//Sweet. Now we can switch out to the compressed game state.
			buf = Stdio.Buffer(files->gamestate); buf->read_only();
			werror("Switching to compressed gamestate, %d bytes.\n", sizeof(buf));
			continue;
		}
		//If the ID is 0d3e, check string_lookup. TODO: Probably also if it's 0d40?
		if (id == 0x0d3e) id = last_string = string_lookup[buf->read_le_int(2)];
		//If the ID is 0017, it's an immediate string. I have NO idea why "resolution_manager"
		//is stored immediate where all the others are by their IDs.
		else if (id == 0x0017) [id] = buf->sscanf("%-2H");
		//If the ID is 0014, the key is a number, not a string. Casting to string so we can save as JSON if desired.
		else if (id == 0x0014) id = (string)buf->read_le_int(4);
		else {
			if (!id_to_string[id]) {
				werror("UNKNOWN MAPPING KEY ID %04x at path %s\nLast string: %s\n", id, path, last_string);
				id_to_string[id] = sprintf("#%04x", id);
			}
			id = id_to_string[id];
		}
		[int marker] = buf->sscanf("%-2c");
		//If the key is not followed by 01 00, it's an array entry; so far only seen with ID 20.
		//When that happens, the next entry follows immediately, so put back the bytes just read.
		if (marker != 1) {buf->unread(2); arr += ({id}); continue;}
		[int type] = buf->sscanf("%-2c");
		mixed value;
		switch (type) {
			case 0x0003: value = read_maparray(buf, path + "-" + id); break;
			case 0x000c: //32-bit integer, used for date and version
			case 0x029c: //32-bit integer, used for general-purpose numbers
			case 0x0014: //32-bit integer... for something else.
				//I don't know what the differences between these are. One might be unsigned?
				//value = buf->read_le_int(4);
				[value] = buf->sscanf("%-4c");
				break;
			case 0x000f: [value] = buf->sscanf("%-2H"); break;
			case 0x0167:
				//This is shown in the text version as a float.
				//For now, storing the integer value; the true value is this divided by 100000.0
				//(note that this is a change from EU4 where fixed point was to be divided by 1000.0).
				[value] = buf->sscanf("%-8c");
				break;
			//Lookups into the strings table come in short and long forms. Is it possible for there to be >65535 strings?
			case 0x0d40: value = last_string = string_lookup[buf->read_int8()]; break;
			case 0x0d3e: value = last_string = string_lookup[buf->read_le_int(2)]; break;
			//This might be an enumeration??
			case 0x2df2: value = "char"; break;
			case 0x02d2: value = "value"; break;
			case 0x0500: value = "boolean"; break;
			case 0x2ddf: value = "loc"; break;
			case 0x2cd6: value = "ctry"; break;
			case 0x393e: value = "formable_country"; break;
			case 0x32e3: value = "international_organization"; break;
			case 0x2d06: value = "area"; break;
			case 0x0165: value = "none"; break;
			case 0x355d: value = "law"; break;
			case 0x355e: value = "policy"; break;
			case 0x000e: value = "yes"; break; //Possibly should use Val.true here
			default:
				werror("UNKNOWN DATA TYPE %04x at pos %d:%{ %02x%}\nPath %s, last string %s\n", type, pos, (array)((string)buf)[..16], path, last_string);
				exit(1);
		}
		map[id] = value;
	}
	if (sizeof(map) && sizeof(arr)) werror("WARNING: Mixed map/array at pos %d\n", startpos);
	//werror("< Exiting %s\n", path);
	return sizeof(arr) ? arr : map;
}

int main() {
	string path = "/mnt/sata-ssd/.steam/steamapps/compatdata/3450310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Europa Universalis V/save games";
	string data = Stdio.read_file(path + "/autosave_73fb9c8e-b90c-4a4a-88ea-01304061fa99.eu5");
	Stdio.Buffer buf = Stdio.Buffer(data); buf->read_only();
	[string header] = buf->sscanf("%s\n");
	if (header[..2] != "SAV") exit(1, "Not an EU5 save file\n");
	//If any of these assertions fails, we probably need to make this parser more flexible.
	//They will very likely indicate that changes are needed elsewhere.
	if (header[3..4] != "02") exit(1, "Bad version %O\n", header[3..4]);
	if (header[5..6] == "00") exit(1, "TODO: Support debug-mode saves too\n");
	if (header[5..6] != "03") exit(1, "Bad type %O\n", header[5..6]);
	if (header[15..18] != "0006") exit(1, "Bad type %O\n", header[15..18]);
	if (header[23..] != "00000000") exit(1, "Bad end-of-header %O\n", header[23..]);
	mapping toplevel = read_maparray(buf, "base");
	//toplevel->metadata->compatibility->locations = toplevel->metadata->flag = "(...)";
	werror("Toplevel: %O\n", toplevel);
}
