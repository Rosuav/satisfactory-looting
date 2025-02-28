inherit annotated;

protected void create(string name) {
	::create(name);
	if (G->G->inotify) destruct(G->G->inotify); //Hack. TODO: Keep the inotify and change the code it calls, rather than closing it and start over.
	object inot = G->G->inotify = System.Inotify.Instance();
	inot->add_watch(SATIS_SAVE_PATH, System.Inotify.IN_CLOSE_WRITE | System.Inotify.IN_DELETE) {
		//In contrast to EU4, which *moves* files to the target name, Satisfactory always writes directly,
		//possibly after moving the old file away. So we take the easy option and just report when a file
		//is closed after being written to.
		[int event, int cookie, string path] = __ARGS__;
		//Note that the same hook is called on deletion as on creation. If you care about the difference,
		//stat the file on arrival.
		values(G->G->inotify_hooks)(basename(path));
	};
	inot->set_nonblocking();
}
