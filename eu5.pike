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

array string_lookup = ({ });
string last_string = "?";
array(string) id_sequence = ({ });
mapping|array read_maparray(Stdio.Buffer buf, string path) {
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
				if (mode == MODE_GOTKEY && (stringp(lastobj) || intp(lastobj)))
					value = read_maparray(buf, path + "-" + lastobj);
				else if (mode == MODE_EMPTY)
					//It's possible that this is a subobject key, but more likely it's
					//an array entry, so show the path accordingly.
					value = read_maparray(buf, path + "[]");
				else value = read_maparray(buf, sprintf("%s-%t", path, lastobj)); //eg "base-somekey-somekey-mapping" which is weird but at least it's something
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
			case 0x0d4d: case 0x0d4e: exit(1, "[%d] GOT %04x at pos %d, NEXT%{ %02x%}\n", startpos, id, pos, (array)(string)buf[..9]); //Might be looking for six and seven bytes respectively
			case 0x0d4f: [value] = buf->sscanf("%-1c"); value = -value; break; //Small negative values???
			case 0x0d50: [value] = buf->sscanf("%-2c"); value = -value; break; //There isn't room for an eight byte here but maybe that's just 0167
			case 0x0d51: [value] = buf->sscanf("%-3c"); value = -value; break;
			case 0x0d52: [value] = buf->sscanf("%-4c"); value = -value; break;
			case 0x0d53..0x0d56: exit(1, "[%d] GOT %04x at pos %d, NEXT%{ %02x%}\n", startpos, id, pos, (array)(string)buf[..9]); //Might be looking for six and seven bytes respectively
			//Lookups into the strings table come in short and long forms. Is it possible for there to be >65535 strings?
			case 0x0d43: //Unsure what is going on here; seems to be the same as 0d40??
			case 0x0d40: value = last_string = string_lookup[buf->read_int8()]; break;
			case 0x0d44: //Again, possibly same as 0d3e?? Do these type IDs change when the game updates???
			case 0x0d3e: value = last_string = string_lookup[buf->read_le_int(2)]; break;
			case 0x0243:
				//RGB color; should always be followed by type 0003 and a subarray.
				//Hack: Since the text file has the letters "rgb" followed by the subarray,
				//insert that token into the string stream as if we'd found it.
				id_sequence += ({"rgb"});
				if (buf->read(2) != "\x03\x00") exit(1, "UNKNOWN 0243 at pos %d\n", pos);
				value = read_maparray(buf, path + "-" + lastobj + ":rgb");
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
			if (trace == 2) werror("| Recording key %O\n", lastobj);
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

array list_strings(Stdio.Buffer buf) {
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

int main() {
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
	#if 1
	string path = "/mnt/sata-ssd/.steam/steamapps/compatdata/3450310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Europa Universalis V/save games";
	string data = Stdio.read_file(path + "/SP_TUR_1337_04_01_907a8a9e-6b68-45d2-9a68-89b2a7381a64.eu5");
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
	werror("Toplevel: %t %O\n", toplevel, indices(toplevel));
	//exit(0, "Got %d IDs.\n", sizeof(id_sequence));
	//If we have a matching text save, try to match the keys.
	data = Stdio.read_file(path + "/SP_TUR_1337_04_01_907a8a9e-6b68-45d2-9a68-89b2a7381a64_0.eu5");
	buf = Stdio.Buffer(data); buf->read_only();
	buf->sscanf("%s\n");
	array string_sequence = list_strings(buf);
	werror("Got %d IDs and %d strings.\n", sizeof(id_sequence), sizeof(string_sequence));
	Stdio.write_file("allstrings.json", Standards.JSON.encode(({id_sequence, string_sequence})));
	#else
	[id_sequence, array string_sequence] = Standards.JSON.decode(Stdio.read_file("allstrings.json"));
	write("Loaded %d IDs and %d strings.\n", sizeof(id_sequence), sizeof(string_sequence));
	#endif

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
		if (id == str || id[0] == '#') {
			//Could be a match, or a candidate! Hang onto it for future analysis.
			matches += ({({id, str})});
			++nextid; ++nextstr;
			if (id[0] == '#') have_candidate = 1;
		} else {
			//We have a mismatch.
			if (sizeof(matches)) {
				//if (have_candidate) foreach (matches, [string i, string s]) write("\e[%dm%30s | %s\e[0m\n", i != s, i, s);
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
			for (int skip = 0; nextid + skip < sizeof(id_sequence) && nextstr + skip < sizeof(string_sequence); ++skip) {
				id = id_sequence[nextid + skip]; str = string_sequence[nextstr + skip];
				//When skip is (say) 4, we've scanned 4 entries forward in each array.
				//If there are matching entries in the two arrays within that distance, we take
				//that and resume. Note that, as written here, we will try to keep the skip
				//distances similar, rather than taking the earliest match. Ideally, we'd find
				//multi-string matches, rather than accepting the first coincidence we meet.
				if (id == str) {
					if (skip == 1) {
						//We advanced one entry in each array and then found a rematch.
						//This strongly suggests a one-string mismatch, which may well
						//be of interest. Report it, with a little context.
						write("- One-line mismatch -\n");
						write("%30s | %<s\n", id_sequence[nextid - 1]);
						write("\e[1m%30s | %s\e[0m\n", id_sequence[nextid], string_sequence[nextstr]);
						write("%30s | %<s\n", id);
					}
					nextid += skip; nextstr += skip; found = 1;
					break;
				}
				if (!undefinedp(idskip[str])) {nextid += idskip[str]; nextstr += skip; found = 1; break;}
				if (!undefinedp(strskip[id])) {nextstr += strskip[id]; nextid += skip; found = 1; break;}
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
	foreach (id_to_string; int id; string str) if (str[0] != '#') {
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
	Stdio.write_file("candidates.txt", can * "");
	sort(keep[*][0], keep);
	Stdio.write_file("eu5textid.dat", sprintf("%{%s %s\n%}", keep));
}
