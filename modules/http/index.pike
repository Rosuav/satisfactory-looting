inherit http_websocket;

string ws_type = "satisfactory";
string page_html = #"<h1>Hello, world</h1>\n";
constant http_path_pattern = "/";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": (["ws_group": ""])]));
}