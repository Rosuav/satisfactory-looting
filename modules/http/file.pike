inherit http_websocket;

constant http_path_pattern = "/file/%[^/]";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req, string filename) {
	return render(req, (["vars": ([
		"ws_group": Protocols.HTTP.Server.http_decode_string(filename),
		"item_names": ITEM_NAMES,
	])]));
}

//Validation is done once per socket, and after that, we assume that the file is still valid.
//It may have been deleted, but at least there's no easy abuses with "../" etc.
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!check_savefile_name(msg->group)) return "Not a known save file.";
}

mapping get_state(string|int group) {
	return cached_parse_savefile(group);
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

//TODO: Other map annotation types:
// - all known crashes
// - loot, indicating (a) in file, (b) removed, (c) not yet added (using pristine file)
// - all reference locations. Using this, the front end can potentially let you click to choose a loc.

mapping websocket_cmd_findloot(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array loc = msg->refloc;
	if (sizeof(loc) == 2) loc += ({0.0}); //Z coordinate is optional
	if (sizeof(loc) != 3) return 0;
	foreach (loc, mixed coord) if (!intp(coord) && !floatp(coord)) return 0;
	mapping savefile = cached_parse_savefile(conn->group); //Should normally come from cache and be fast
	string item = msg->itemtype;
	if (!savefile->haveloot[item]) return 0;

	object annot_map = get_satisfactory_map();

	//The reference location is given as a blue star
	[int x, int y] = coords_to_pixels(loc);
	for (int d = -10; d <= 10; ++d) {
		set_pixel_safe(annot_map, x + d, y, 0, 0, 128); //Horizontal stroke
		set_pixel_safe(annot_map, x, y + d, 0, 0, 128); //Vertical stroke
		int diag = (int)(d * .7071); //Multiply by root two over two
		set_pixel_safe(annot_map, x + diag, y + diag, 0, 0, 128); //Solidus
		set_pixel_safe(annot_map, x + diag, y - diag, 0, 0, 128); //Reverse Solidus
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
		found += ({sprintf("Found %d %s at %.0f,%.0f,%.0f - %.0f away\n",
			details[3], L10n(item),
			details[0], details[1], details[2],
			(distances[i] ** 0.5) / 100.0)});
		//Mark the location and draw a line to it
		[int basex, int basey] = coords_to_pixels(loc);
		[int x, int y] = coords_to_pixels(details);
		annot_map->circle(x, y, 5, 5, 128, 192, 0);
		annot_map->circle(x, y, 4, 4, 128, 192, 0);
		annot_map->circle(x, y, 3, 3, 128, 192, 0);
		annot_map->line(basex, basey, x, y, 32, 64, 0);
	}

	//TODO: Optionally crop the image to a square containing the refloc and all (up to) three loot, with a 10px buffer around it

	return ([
		"cmd": "findloot",
		"img": "data:image/png;base64," + MIME.encode_base64(Image.PNG.encode(annot_map)),
		"found": found,
	]);
}
