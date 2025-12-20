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
	0x2df2: "char",
	0x02d2: "value",
	0x0500: "boolean",
	0x2dd6: "cult",
	0x2de4: "relg",
	0x2ddc: "regn",
	0x2ddf: "loc",
	0x2cd6: "ctry",
	0x04ff: "prov",
	0x315c: "rebl",
	0x3100: "reli",
	0x393e: "formable_country",
	0x32e3: "international_organization",
	0x2d06: "area",
	0x0165: "none",
	0x355d: "law",
	0x355e: "policy",
	0x3130: "situation",
	0x3646: "disease_outbreak",
	0x2e0b: "patronym",
	0x2e0c: "descendant",
	0x2e90: "estate",
	0x27f6: "location",
	0x27f7: "unit",
	0x27d2: "province",
	0x2e4f: "gathering",
	0x2d4a: "navy",
	0x2d4f: "combat",
	0x3a54: "location_ancient",
	0x2817: "active",
	0x3132: "before",
	0x30e2: "available",
	0x30e3: "hired",
	0x2e73: "construction",
]);

array string_lookup = ({ });
string last_string = "?";
array(int) id_sequence = ({ });
mapping|array read_maparray(Stdio.Buffer buf, string path) {
	mapping map = ([]); array arr = ({ });
	int startpos = sizeof(buf);
	int trace = has_value(path, "#31df");
	if (trace) werror("> [%d] Entering %s\n", startpos, path);
	enum {
		MODE_EMPTY, //No object seen yet (or the last one seen was the value of a key/value pair).
		MODE_GOTOBJ, //Got an object. It might be an array entry and it might be the key in a key/value pair.
		MODE_GOTKEY, //Got an object and it is definitely the key.
	};
	int mode = MODE_EMPTY;
	mixed lastobj; //Relevant in GOTOBJ and GOTKEY modes.
	while (sizeof(buf)) {
		int pos = sizeof(buf);
		if (pos == 32757410) werror("POS %d NEXT%{ %02x%}\n", pos, (array)(string)buf[..255]);
		int|string id = buf->read_le_int(2);
		if (id == 4) break; //End of object
		if (id == 0) {write("[%d] \e[1;31mNULL entry\e[0m at %d\n", startpos, pos); continue;} //Probable misparse of a previous entry
		if (id == 1) {
			if (mode != MODE_GOTOBJ) {write("[%d] \e[1;31mGOT 01 00 WITHOUT KEY\e[0m at %d\n", startpos, pos); continue;} //Probable misparse
			mode = MODE_GOTKEY;
			continue;
		}
		//If we get two objects in a row, without 01 00 between, then the first one was an array entry.
		if (mode == MODE_GOTOBJ) {
			arr += ({lastobj});
			mode = MODE_EMPTY;
			if (trace == 2) werror("| Recording key %s\n", id);
		}
		if (id == 0x4b50) {
			//In a non-debug savefile, everything after the metadata is packaged up as a zip file.
			//It can be recognized by the "PK" signature (50 4b), which is then followed by 03 04.
			//Pike comes with a Filesystem.Zip interface but it's not really optimized for this
			//sort of job, so instead we do our own parsing.
			//(It may be easier, instead, to start at the end of central directory, and not parse
			//the initial uncompressed header. All the content seems to be replicated anyway.)
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
			//Stdio.File str = Stdio.File("string_lookup", "wct"); foreach (string_lookup; int i; string s) str->write("%04x: %s\n", i, s);
			//Sweet. Now we can switch out to the compressed game state.
			buf = Stdio.Buffer(files->gamestate); buf->read_only();
			werror("Switching to compressed gamestate, %d bytes.\n", sizeof(buf));
			id_sequence = ({ });
			continue;
		}
		mixed value;
		switch (id) {
			case 0x0003:
				//FIXME: Adding the ID here will just always give 3
				value = read_maparray(buf, path + "-" + id);
				break;
			case 0x029c: //64-bit integer, used for general-purpose numbers
				[value] = buf->sscanf("%-8c");
				break;
			case 0x000c: //32-bit integer, used for date and version
			case 0x0014: //32-bit integer... for something else.
				//I don't know what the differences between these are. One might be unsigned?
				//value = buf->read_le_int(4);
				[value] = buf->sscanf("%-4c");
				break;
			case 0x0017: //What's the difference between these two?
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
			case 0x0243:
				//RGB color; should always be followed by type 0003 and a subarray.
				if (buf->read(2) != "\x03\x00") exit(1, "UNKNOWN 0243 at pos %d\n", pos);
				value = read_maparray(buf, path + "-" + id + ":rgb");
				break;
			case 0x000e:
				//werror("\e[1;34mGOT BOOLEAN\e[0m NEXT%{ %02x%}\n", (array)(string)buf[..16]);
				//Possibly should use Val.true and Val.false here?
				value = buf->read(1)[0] ? "yes" : "no";
				break;
			default:
				//If misparses happen, start reporting unknowns, as they may actually require additional
				//data bytes.
				if (!id_to_string[id]) {
					//werror("UNKNOWN MAPPING KEY ID %04x at path %s\nLast string: %s\n", id, path, last_string);
					id_to_string[id] = sprintf("#%04x", id);
				}
				value = id_to_string[id];
		}
		if (stringp(value) || intp(value)) id_sequence += ({(string)value});
		if (mode == MODE_EMPTY) {lastobj = value; mode = MODE_GOTOBJ;}
		else {
			map[lastobj] = value;
			mode = MODE_EMPTY;
			if (trace == 2) werror("| Recording key %s\n", id);
		}
	}
	if (sizeof(map) && sizeof(arr)) {
		//werror("WARNING: Mixed map/array at pos %d %s\n%O\n%O\n", startpos, path, map, arr);
		//For now, stick the two parts together; array first, then mapping entries as pairs
		//So an array of "{ 996 995=positive }" will be represented as the two-element array
		//({ 996, ({ "995", "positive" }) }) in the output. Yes, this is lossy.
		arr += (array)map;
	}
	if (trace) werror("< Exiting %s\n", path);
	return sizeof(arr) ? arr : map;
}

array list_keys(Stdio.Buffer buf) {
	array keys = ({ });
	while (1) {
		buf->sscanf("%*[ \t\r\n]");
		if (!sizeof(buf)) break;
		//The key might be followed by an equals sign and then a value, or it might be followed
		//by whitespace (eg in an array), or at the end of an array, a close brace. I'm pretty
		//sure it'll always be one of those. However, we might - in an array - have a quoted
		//string, which will show up as an empty key and a terminator of '"', or an object.
		[string key, int terminator] = buf->sscanf("%[^ \t\r\n=}\"{]%c");
		if (key == "" && terminator == '"') {
			//String literal, presumably in an array.
			//No backslash handling here, for simplicity. If it comes up, deal with it.
			buf->sscanf("%[^\"]\"");
			continue;
		}
		if (key != "") keys += ({key});
		buf->sscanf("%*[ \t\r\n]"); //Ignore whitespace, if any
		if (terminator == '}') ; //Currently we don't actually fully parse, we just find keys
		if (terminator == '=') {
			//We have an equals sign, so we have a value.
			if (array str = buf->sscanf("\"%[^\"]\"")) {
				//String literal. Backslash/quote handling lifted from EU4 parser - it's probably the same.
				string lit = str[0];
				while (lit != "" && lit[-1] == '\\') {
					str = buf->sscanf("%[^\"]\"");
					if (!str) break; //Should possibly be a parse error?
					lit += "\"" + str[0];
				}
				continue;
			}
			if (buf->sscanf("%1[-0-9.A-Za-z_]")) {
				//If we have a word character or digit, read up to the next whitespace,
				//assuming that there will always be some.
				buf->sscanf("%[^ \r\n]");
				continue;
			}
			string ch = buf->read(1);
			if (ch == "{") ; //Increment nesting level. Not implemented. We could recursively read a map/array here.
			else if (ch == "}") error("Bad format, got =}, at pos %d\n", sizeof(buf));
			else error("Unknown, please debug ==> %O\n", ch);
		}
		//Otherwise, it's probably an array entry.
	}
	return keys;
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
	werror("Toplevel: %O\n", indices(toplevel));
	exit(0, "Got %d IDs.\n", sizeof(id_sequence));
	//If we have a matching text save, try to match the keys.
	data = Stdio.read_file(path + "/SP_SPA_1464_05_18_73fb9c8e-b90c-4a4a-88ea-01304061fa99.eu5");
	buf = Stdio.Buffer(data); buf->read_only();
	buf->sscanf("%s\n");
	array string_sequence = list_keys(buf);
	werror("Got %d IDs and %d strings.\n", sizeof(id_sequence), sizeof(string_sequence));
	write("%O\n", string_sequence);
}
