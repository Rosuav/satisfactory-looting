//Various functions for parsing and analyzing EU5 savefiles.
inherit annotated;

mapping(int:string) id_to_string = ([]);

mapping(int:string) idx_to_date = ([]); //Convenience lookup - 0 maps to "1.1" for Jan 1st, 364 maps to "12.31"
string date_to_string(int date) {
	int hour = date % 24; date /= 24;
	int year = date / 365 - 5000; date %= 365;
	string d = sprintf("%d.%s", year, idx_to_date[date]);
	if (hour) d += "." + hour;
	return d;
}

//Appended to in main(), is the number of days to add to get to that month.
//January is -1 since day values are 1-based but integers are 0-based.
//And there's a shim because month values are also 1-based (we'll never look up month 0).
array(int) month_offset = ({0, -1});
int date_to_int(int y, int m, int d, int h) {
	return ((y + 5000) * 365 + month_offset[m] + d) * 24 + h;
}

mapping|array read_maparray(Stdio.Buffer buf, string path, mapping xtra) {
	mapping map = ([]); array arr = ({ });
	int startpos = sizeof(buf);
	int trace = 0;
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
		//if (startpos == 50029794) werror("POS %d NEXT%{ %02x%}\n", pos, (array)(string)buf[..255]);
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
			if (trace == 2) werror("| Recording value %O\n", lastobj);
		}
		mixed value;
		switch (id) {
			case 0x0003:
				if (mode == MODE_GOTKEY && (stringp(lastobj) || intp(lastobj)))
					value = read_maparray(buf, path + "-" + lastobj, xtra);
				else if (mode == MODE_EMPTY)
					//It's possible that this is a subobject key, but more likely it's
					//an array entry, so show the path accordingly.
					value = read_maparray(buf, path + "[]", xtra);
				else value = read_maparray(buf, sprintf("%s-%t", path, lastobj), xtra); //eg "base-somekey-somekey-mapping" which is weird but at least it's something
				break;
			case 0x029c: //64-bit integer, used for general-purpose numbers
				[value] = buf->sscanf("%-8c");
				break;
			case 0x000c: //32-bit integer, used for date and version
				//Assuming it's a date, for now. How would we know?
				//For the purposes of synchronization, it's easier to NOT transform to date,
				//and instead to transform the text dates into numbers.
				value = /*date_to_string*/(buf->sscanf("%-4c")[0]);
				break;
			case 0x0014: //32-bit integer... for something else.
				[value] = buf->sscanf("%-4c");
				if (value > (1<<31)) value -= 1<<32; //Are they all signed?
				break;
			case 0x0017: //What's the difference between these two?
			case 0x000f: [value] = buf->sscanf("%-2H"); break;
			case 0x0167:
				//This is shown in the text version as a float.
				//For now, storing the integer value; the true value is this divided by 100000.0
				//(note that this is a change from EU4 where fixed point was to be divided by 1000.0).
				[value] = buf->sscanf("%-8c");
				if (value >= (1<<63)) value -= 1<<64; //Signed integer. I think they're all signed???
				//Or maybe store it smaller, but only if it's an integer?
				if (value % 100000 == 0) value /= 100000;
				//TODO: Do the above translations also for the shorter integers
				break;
			//Fixed-point values are stored as integers. Small fixed-point values eg 0.00049 can be stored compactly.
			//The data type stipulates a number of bytes to read.
			case 0x0d48: [value] = buf->sscanf("%-1c"); break;
			case 0x0d49: [value] = buf->sscanf("%-2c"); break;
			case 0x0d4a: [value] = buf->sscanf("%-3c"); break; //Guessing based on the surroundings
			case 0x0d4b: [value] = buf->sscanf("%-4c"); break; //that these two will be 3-byte and 4-bytes
			case 0x0d4c: [value] = buf->sscanf("%-5c"); break;
			case 0x0d4d: case 0x0d4e: werror("[%d] GOT %04x at pos %d, NEXT%{ %02x%}\n", startpos, id, pos, (array)(string)buf[..9]); break; //Might be looking for six and seven bytes respectively
			case 0x0d4f: [value] = buf->sscanf("%-1c"); value = -value; break; //Small negative values???
			case 0x0d50: [value] = buf->sscanf("%-2c"); value = -value; break; //There isn't room for an eight byte here but maybe that's just 0167
			case 0x0d51: [value] = buf->sscanf("%-3c"); value = -value; break;
			case 0x0d52: [value] = buf->sscanf("%-4c"); value = -value; break;
			case 0x0d53..0x0d56: werror("[%d] GOT %04x at pos %d, NEXT%{ %02x%}\n", startpos, id, pos, (array)(string)buf[..9]); break; //Might be looking for six and seven bytes respectively
			//Lookups into the strings table come in short and long forms. Is it possible for there to be >65535 strings?
			case 0x0d43: //Unsure what is going on here; seems to be the same as 0d40??
			case 0x0d40: value = xtra->last_string = xtra->string_lookup[buf->read_int8()]; break;
			case 0x0d44: //Again, possibly same as 0d3e?? Do these type IDs change when the game updates???
			case 0x0d3e: value = xtra->last_string = xtra->string_lookup[buf->read_le_int(2)]; break;
			case 0x0243:
				//RGB color; should always be followed by type 0003 and a subarray.
				//Hack: Since the text file has the letters "rgb" followed by the subarray,
				//insert that token into the string stream as if we'd found it.
				xtra->id_sequence += ({"rgb"});
				if (buf->read(2) != "\x03\x00") werror("UNKNOWN 0243 at pos %d\n", pos);
				value = read_maparray(buf, path + "-" + lastobj + ":rgb", xtra);
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
					//This could be spammy; consider suppressing the noise if we're going to diff afterwards
					werror("UNKNOWN MAPPING KEY ID %04x at path %s\nLast string: %s\n", id, path, xtra->last_string);
					id_to_string[id] = sprintf("#%04x", id);
					++xtra->unknownids;
				}
				value = id_to_string[id];
		}
		if (stringp(value) || intp(value)) xtra->id_sequence += ({(string)value});
		if (mode == MODE_EMPTY) {lastobj = value; mode = MODE_GOTOBJ;}
		else {
			map[lastobj] = value;
			mode = MODE_EMPTY;
			if (trace == 2) werror("| Recording key %O\n", lastobj);
		}
	}
	if (mode == MODE_GOTOBJ) arr += ({lastobj});
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

mapping eu5_parse_savefile(string fn) {
	string data = Stdio.read_file(fn);
	if (!data) return (["error": "Unable to read file"]);
	Stdio.Buffer buf = Stdio.Buffer(data); buf->read_only();
	[string header] = buf->sscanf("%s\n");
	if (header[..2] != "SAV") return (["error": "Not an EU5 save file"]);
	//If any of these assertions fails, we probably need to make this parser more flexible.
	//They will very likely indicate that changes are needed elsewhere.
	sscanf(header, "SAV%2x%2x%*8x%8x%8x", int version, int type, int metasize, int padding);
	if (version != 2) return (["error": sprintf("Bad version %O", header[3..4])]);
	if (type == 0) return (["error": "TODO: Support text saves too"]);
	else if (type != 3) return (["error": sprintf("Unsupported type %O", header[5..6])]);
	if (padding) return (["error": sprintf("Nonzeropadding %O", header[23..])]);

	array string_lookup = ({ }); //If not part of the save file, will remain empty
	if (type == 3) {
		//Currently the only type supported - compressed binary.
		//Skip the uncompressed metadata block, as it's duplicated into the compressed content.
		buf->consume(metasize);
		if (buf->read(4) != "PK\3\4") return (["error": "Malformed compressed savefile"]);
		//Pike comes with a Filesystem.Zip interface but it's not really optimized for this
		//sort of job, so instead we do our own parsing.
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
	}
	mapping xtra = (["string_lookup": string_lookup, "last_string": "(none)"]);
	xtra->savefile = read_maparray(buf, "base", xtra);
	return xtra;
}

@inotify_hook: void savefile_changed(string cat, string fn) {
	if (cat == "eu5") {
		G->G->last_parsed_eu5_savefile = eu5_parse_savefile(fn);
		object handler = G->G->websocket_types->eu5;
		foreach (handler->websocket_groups; mixed grp;) handler->send_updates_all(grp);
	}
}

array list_strings(string fn) {
	Stdio.Buffer buf = Stdio.Buffer(Stdio.read_file(fn));
	buf->read_only();
	buf->sscanf("%s\n");
	array strings = ({ });
	while (1) {
		buf->sscanf("%*[ \t\r\n]");
		if (!sizeof(buf)) break;
		if (array str = buf->sscanf("\"%[^\"]\"")) {
			//String literal. Backslash/quote handling lifted from EU4 parser - it's probably the same.
			string lit = str[0];
			while (lit != "" && lit[-1] == '\\') {
				str = buf->sscanf("%[^\"]\"");
				if (!str) break; //Should possibly be a parse error?
				lit += "\"" + str[0];
			}
			strings += ({lit});
		}
		else if (array word = buf->sscanf("%[-0-9.A-Za-z_']")) {
			//Atom characters - are there any others?
			//Transform dates back into numbers for better synchronization. I don't know how to
			//recognize which fields in the binary should be treated as dates, so fold them all
			//to numbers here.
			if (sscanf(word[0], "%d.%d.%d.%d%s", int y, int m, int d, int h, string tail) && tail == "")
				strings += ({(string)date_to_int(y, m, d, h)});
			else if (sscanf(word[0], "%d.%d.%d%s", int y, int m, int d, string tail) && tail == "")
				strings += ({(string)date_to_int(y, m, d, 0)});
			//For best results, transform "123.456" into "12345600" to match the fixed-place handling in binary
			else if (sscanf(word[0], "%d.%[0-9]%s", int before, string after, string tail) && tail == "") {
				if (sizeof(after) != 5) after = (after + "00000")[..4];
				string value = (string)before + after;
				//NOTE: For numbers -1<x<0, the leading part will be "-0", which parses as 0.
				//Reattach the hyphen to correct this.
				if (word[0][0] == '-' && !before) value = "-" + value;
				//If the value is less than one (eg 0.0123), we'll build a string like "001230". But
				//in the binary file, it'll just be stored as 1230, and become "1230".
				strings += ({(string)(int)value});
			}
			else strings += word;
		} else {
			string chr = buf->read(1);
			if (!has_value("={}", chr)) werror("WARNING: Unexpected character %O\nLatest strings: %O\n", chr, strings[<3..]);
		}
	}
	return strings;
}

protected void create(string name) {
	::create(name);
	//Build up a convenience mapping for date parsing
	int d = 0;
	foreach (({31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}); int mon; int len) {
		month_offset += ({month_offset[-1] + len});
		for (int i = 0; i < len; ++i)
			idx_to_date[d++] = sprintf("%d.%d", mon + 1, i + 1);
	}
	//Dates consist of (year * 365 + date value) * 24 + hour, where the date value is basically the Julian day number (ignoring leap years).
	foreach ((Stdio.read_file("eu5textid.dat") || "") / "\n", string line)
		if (sscanf(line, "#%x %s", int id, string str) && str != "") id_to_string[id] = str;
}
