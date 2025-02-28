array(string) bootstrap_files = ({"globals.pike", "connection.pike", "modules", "modules/http"});
array(string) restricted_update;
mapping G = (["consolecmd": ([]), "dbsettings": ([]), "instance_config": ([])]);

void console(object stdin, string buf) {
	while (has_value(buf, "\n")) {
		sscanf(buf, "%s\n%s", string line, buf);
		if (line == "update") bootstrap_all();
	}
	if (buf == "update") bootstrap_all();
}

class CompilerErrors {
	int(1bit) reported;
	void compile_error(string filename, int line, string msg) {
		reported = 1;
		werror("\e[1;31m%s:%d\e[0m: %s\n", filename, line, msg);
	}
	void compile_warning(string filename, int line, string msg) {
		reported = 1;
		werror("\e[1;33m%s:%d\e[0m: %s\n", filename, line, msg);
	}
}

object bootstrap(string c)
{
	sscanf(explode_path(c)[-1], "%s.pike", string name);
	program|object compiled;
	object handler = CompilerErrors();
	mixed ex = catch {compiled = compile_file(c, handler);};
	if (handler->reported) return 0; //ANY error or warning, fail the build.
	if (ex) {werror("Exception in compile!\n%s\n", ex->describe()); return 0;} //Compilation exceptions indicate abnormal failures eg unable to read the file.
	if (!compiled) werror("Compilation failed for "+c+"\n"); //And bizarre failures that report nothing but fail to result in a working program should be reported too.
	if (mixed ex = catch {compiled = compiled(name);}) {G->warnings++; werror(describe_backtrace(ex)+"\n");}
	werror("Bootstrapped "+c+"\n");
	return compiled;
}

int bootstrap_all()
{
	if (restricted_update) bootstrap_files = restricted_update;
	else {
		object main = bootstrap(__FILE__);
		if (!main || !main->bootstrap_files) {werror("UNABLE TO RESET ALL\n"); return 1;}
		bootstrap_files = main->bootstrap_files;
	}
	int err = 0;
	foreach (bootstrap_files, string fn)
		if (file_stat(fn)->isdir)
		{
			foreach (sort(get_dir(fn)), string f)
				if (has_suffix(f, ".pike")) err += !bootstrap(fn + "/" + f);
		}
		else err += !bootstrap(fn);
	return err;
}

int|Concurrent.Future main(int argc,array(string) argv) {
	add_constant("G", this);
	G->args = Arg.parse(argv);
	if (G->args->help) G->args->exec = "help";
	if (string fn = G->args->exec) {
		bootstrap("globals.pike");
		object utils = bootstrap("utils.pike");
		if (fn == 1)
			if (sizeof(G->args[Arg.REST])) [fn, G->args[Arg.REST]] = Array.shift(G->args[Arg.REST]);
			else fn = "help";
		return (utils[replace(fn, "-", "_")] || utils->help)();
	}
	bootstrap_all();
	Stdio.stdin->set_read_callback(console);
	return -1;
}
