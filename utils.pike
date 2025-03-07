@"This help information":
void help() {
	write("\nUSAGE: pike stillebot --exec=ACTION\nwhere ACTION is one of the following:\n");
	array names = indices(this), annot = annotations(this);
	sort(names, annot);
	foreach (annot; int i; multiset|zero annot)
		foreach (annot || (<>); mixed anno;)
			if (stringp(anno)) write("%-15s: %s\n", names[i], anno);
}

@"Edited as needed, does what's needed":
void test() {
	object parser = G->bootstrap("modules/parser.pike");
	mapping save = parser->cached_parse_savefile("Assembly First_autosave_1.sav");
	write("Got save %O\n", indices(save->tree));
	string data = parser->reconstitute_savefile(save->tree);
	Stdio.write_file(SATIS_SAVE_PATH + "/Reconstructed.sav", data);
	write("Reconstituted save has %d bytes\n", sizeof(data));
}
