inherit annotated;

//Not retained. After this file gets updated, everyone that cares about notifications
//should also be updated, and can request the notification.
array notify_me = ({ });

@export:
void inotify_hook(function cb) {notify_me += ({cb});}

protected void create(string name) {
	::create(name);
	if (G->G->inotify) destruct(G->G->inotify); //Hack. TODO: Keep the inotify and change the code it calls, rather than closing it and start over.
	object inot = G->G->inotify = System.Inotify.Instance();
	string new_file; int nomnomcookie;
	inot->add_watch(SAVE_PATH, System.Inotify.IN_CLOSE_WRITE | System.Inotify.IN_MOVED_TO | System.Inotify.IN_MOVED_FROM) {
		[int event, int cookie, string path] = __ARGS__;
		constant eventname = ([
			System.Inotify.IN_CLOSE_WRITE: "CW",
			System.Inotify.IN_MOVED_FROM: "MF",
			System.Inotify.IN_MOVED_TO: "MT",
		]);
		write("Inotify %O Cookie %15d Path %O\n", eventname[event], cookie, path);
		switch (event) {
			case System.Inotify.IN_CLOSE_WRITE: new_file = path; break;
			case System.Inotify.IN_MOVED_FROM: if (path == new_file) {new_file = 0; nomnomcookie = cookie;} break;
			case System.Inotify.IN_MOVED_TO: if (cookie == nomnomcookie) {nomnomcookie = 0; /*G->G->parser->process_savefile(path);*/} break;
		}
	};
	inot->set_nonblocking();
}
