inherit annotated;

protected void create(string name) {
	::create(name);
	if (G->G->inotify) destruct(G->G->inotify); //Hack. TODO: Keep the inotify and change the code it calls, rather than closing it and start over.
	object inot = G->G->inotify = System.Inotify.Instance();
	string new_file; int nomnomcookie;
	inot->add_watch(EU4_LOCAL_PATH + "/save games", System.Inotify.IN_CLOSE_WRITE | System.Inotify.IN_MOVED_TO | System.Inotify.IN_MOVED_FROM) {
		[int event, int cookie, string path] = __ARGS__;
		//EU4 seems to always save into a temporary file, then rename it over the target. This
		//sometimes includes renaming the target out of the way first (eg old_autosave.eu4).
		//There are a few ways to detect new save files.
		//1) Watch for a CLOSE_WRITE event, which will be the temporary file (eg autosave.tmp).
		//   When you see that, watch for the next MOVED_FROM event for that same name, and then
		//   the corresponding MOVED_TO event is the target name. Assumes that the file is created
		//   in the savegames directory and only renamed, never moved in.
		//2) Watch for all MOVED_TO events, and arbitrarily ignore any that we don't think are
		//   interesting (eg if starts with "old_" or "older_").
		//3) Watch for any CLOSE_WRITE or MOVED_TO. Wait a little bit. See what the newest file in
		//   the directory is. Assumes that the directory is quiet apart from what we care about.
		//Currently using option 1. Change if this causes problems.
		switch (event) {
			case System.Inotify.IN_CLOSE_WRITE: new_file = path; break;
			case System.Inotify.IN_MOVED_FROM: if (path == new_file) {new_file = 0; nomnomcookie = cookie;} break;
			case System.Inotify.IN_MOVED_TO: if (cookie == nomnomcookie) {nomnomcookie = 0; G->G->parser->process_savefile(path);} break;
		}
	};
	inot->add_watch(SATIS_SAVE_PATH, System.Inotify.IN_CLOSE_WRITE | System.Inotify.IN_DELETE) {
		//In contrast to EU4, which *moves* files to the target name, Satisfactory always writes directly,
		//possibly after moving the old file away. So we take the easy option and just report when a file
		//is closed after being written to.
		[int event, int cookie, string path] = __ARGS__;
		//Note that the same hook is called on deletion as on creation. If you care about the difference,
		//stat the file on arrival.
		values(G->G->inotify_hooks)("satis", basename(path));
	};
	inot->set_nonblocking();
}
