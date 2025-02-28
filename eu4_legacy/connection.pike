mapping respond(Protocols.HTTP.Server.Request req) {
	if (sscanf(req->not_query, "/flags/%[A-Z_a-z0-9]%[-0-9A-F].%s", string tag, string color, string ext) && tag != "" && ext == "png") {
		//Generate a country flag in PNG format
		string etag; Image.Image img;
		if (tag == "Custom") {
			//Custom nation flags are defined by a symbol and four colours.
			sscanf(color, "-%d-%d-%d-%d-%d%s", int symbol, int flag, int color1, int color2, int color3, color);
			if (!color || sizeof(color) != 7 || color[0] != '-') color = "";
			//If flag (the "Background" in the UI) is 0-33 (1-34 in the UI), it is a two-color
			//flag defined in gfx/custom_flags/pattern.tga, which is a spritesheet of 128x128
			//sections, ten per row, four rows. Replace red with color1, green with color2.
			//If it is 34-53 (35-54 in the UI), it is a three-color flag from pattern2.tga,
			//also ten per row, two rows, also 128x128. Replace blue with color3.
			//(Some of this could be parsed out of custom_country_colors. Hardcoded for now.)
			[Image.Image backgrounds, int bghash] = G->G->parser->load_image(PROGRAM_PATH + "/gfx/custom_flags/pattern" + "2" * (flag >= 34) + ".tga", 1);
			//NOTE: Symbols for custom nations are drawn from a pool of 120, of which client states
			//are also selected, but restricted by religious group. (Actually there seem to be 121 on
			//the spritesheet, but the last one isn't available to customs.)
			//The symbol spritesheet is 4 rows of 32, each 64x64. It might be possible to find
			//this info in the edit files somewhere, but for now I'm hard-coding it.
			[mapping symbols, int symhash] = G->G->parser->load_image(PROGRAM_PATH + "/gfx/interface/client_state_symbols_large.dds", 1);
			//Note that if the definitions of the colors change but the spritesheets don't,
			//we'll generate the exact same etag. Seems unlikely, and not that big a deal anyway.
			etag = sprintf("W/\"%x-%x-%d-%d-%d-%d-%d%s\"", bghash, symhash, symbol, flag, color1, color2, color3, color);
			if (has_value(req->request_headers["if-none-match"] || "", etag)) return (["error": 304]); //Already in cache
			if (flag >= 34) flag -= 34; //Second sheet of patterns
			int bgx = 128 * (flag % 10), bgy = 128 * (flag / 10);
			int symx = 64 * (symbol % 32), symy = 64 * (symbol / 32);
			img = backgrounds->copy(bgx, bgy, bgx + 127, bgy + 127)
				->change_color(255, 0, 0, @(array(int))G->CFG->custom_country_colors->flag_color[color1])
				->change_color(0, 255, 0, @(array(int))G->CFG->custom_country_colors->flag_color[color2])
				->change_color(0, 0, 255, @(array(int))G->CFG->custom_country_colors->flag_color[color3])
				->paste_mask(
					symbols->image->copy(symx, symy, symx + 63, symy + 63),
					symbols->alpha->copy(symx, symy, symx + 63, symy + 63),
				32, 32);
		}
		else {
			//Standard flags are loaded as-is.
			[img, int hash] = G->G->parser->load_image(PROGRAM_PATH + "/gfx/flags/" + tag + ".tga", 1);
			if (!img) return 0;
			//For colonial nations, instead of using the country's own tag (eg C03), we get
			//a flag definition based on the parent country and a colour.
			if (!color || sizeof(color) != 7 || color[0] != '-') color = "";
			//NOTE: Using weak etags since the result will be semantically identical, but
			//might not be byte-for-byte (since the conversion to PNG might change it).
			etag = sprintf("W/\"%x%s\"", hash, color);
			if (has_value(req->request_headers["if-none-match"] || "", etag)) return (["error": 304]); //Already in cache
		}
		if (sscanf(color, "-%2x%2x%2x", int r, int g, int b))
			img = img->copy()->box(img->xsize() / 2, 0, img->xsize(), img->ysize(), r, g, b);
		//TODO: Mask flags off with shield_mask.tga or shield_fancy_mask.tga or small_shield_mask.tga
		//I'm using 128x128 everywhere, but the fancy mask (the largest) is only 92x92. For inline
		//flags in text, small_shield_mask is the perfect 24x24.
		return ([
			"type": "image/png", "data": Image.PNG.encode(img),
			"extra_heads": (["ETag": etag, "Cache-Control": "max-age=604800"]),
		]);
	}
	if (sscanf(req->not_query, "/load/%s", string fn) && fn) {
		if (fn != "") {
			G->G->parser->process_savefile(SAVE_PATH + "/" + fn);
			return (["type": "text/plain", "data": "Loaded"]);
		}
		//Show a list of loadable files
		array(string) files = get_dir(SAVE_PATH);
		sort(file_stat((SAVE_PATH + "/" + files[*])[*])->mtime[*] * -1, files);
		return ([
			"type": "text/html",
			"data": sprintf(#"<!DOCTYPE HTML><html lang=en>
<head><title>EU4 Savefile Analysis</title><link rel=stylesheet href=\"/eu4_parse.css\"></head>
<body><main><h1>Select a file</h1><ul>%{<li><a href=%q>%<s</a></li>%}</ul></main></body></html>
", files),
		]);
	}
}
