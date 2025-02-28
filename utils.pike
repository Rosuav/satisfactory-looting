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
	mapping persist = Standards.JSON.decode_utf8(Stdio.read_file(CONFIG_FILE) || "{}");
	mapping eu4 = Standards.JSON.decode_utf8(Stdio.read_file("../EU4Parse/preferences.json") || "{}");
	Stdio.write_file(CONFIG_FILE, Standards.JSON.encode(persist | eu4, 7));
}
