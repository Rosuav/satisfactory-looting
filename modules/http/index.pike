inherit http_websocket;

string ws_type = "satisfactory";
constant http_path_pattern = "/";

mapping(string:mixed)|string|Concurrent.Future http_request(Protocols.HTTP.Server.Request req) {
	return render(req, (["vars": (["ws_group": ""])]));
}