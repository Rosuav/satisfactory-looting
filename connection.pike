inherit annotated;

__async__ void http_handler(Protocols.HTTP.Server.Request req) {
	array args = ({ });
	//Simple lookups are like http_endpoints["listrewards"], without the slash.
	function handler = G->G->http_endpoints[req->not_query[1..]];
	if (!handler) foreach (G->G->http_endpoints; string pat; function h) if (has_prefix(pat, "/")) {
		//Match against an sscanf pattern, and require that the entire
		//string be consumed. If there's any left (the last piece is
		//non-empty), it's not a match - look for a deeper pattern.
		array pieces = array_sscanf(req->not_query, pat + "%s");
		if (pieces && sizeof(pieces) && pieces[-1] == "") {handler = h; args = pieces[..<1]; break;}
	}
	mapping|string resp;
	if (mixed ex = handler && catch {
		mixed h = handler(req, @args); //Either a promise or a result (mapping/string).
		resp = objectp(h) && h->on_await ? await(h) : h; //Await if promise, otherwise we already have it.
	}) {
		werror("HTTP handler crash: %O\n", req->not_query);
		werror(describe_backtrace(ex));
		resp = (["error": 500, "data": "Internal server error\n", "type": "text/plain; charset=\"UTF-8\""]);
	}
	if (!resp) resp = ([
		"data": "No such page.\n",
		"type": "text/plain; charset=\"UTF-8\"",
		"error": 404,
	]);
	if (stringp(resp)) resp = (["data": resp, "type": "text/plain; charset=\"UTF-8\""]);
	//All requests should get to this point with a response.

	//As of 20190122, the Pike HTTP server doesn't seem to handle keep-alive.
	//The simplest fix is to just add "Connection: close" to all responses.
	if (!resp->extra_heads) resp->extra_heads = ([]);
	resp->extra_heads->Connection = "close";
	resp->extra_heads["Access-Control-Allow-Origin"] = "*";
	resp->extra_heads["Access-Control-Allow-Private-Network"] = "true";
	req->response_and_finish(resp);
}

void ws_msg(Protocols.WebSocket.Frame frm, mapping conn) {
	if (function f = bounce(this_function)) {f(frm, conn); return;}
	mixed data;
	if (catch {data = Standards.JSON.decode(frm->text);}) return; //Ignore frames that aren't text or aren't valid JSON
	if (!stringp(data->cmd)) return;
	if (data->cmd == "init") {
		//Initialization is done with a type and a group.
		//The type has to match a module ("inherit http_websocket")
		//The group has to be a string or integer.
		if (conn->type) return; //Can't init twice
		object handler = G->G->websocket_types[data->type];
		if (!handler) return; //Ignore any unknown types.
		if (string err = handler->websocket_validate(conn, data)) {
			conn->sock->send_text(Standards.JSON.encode((["cmd": "*DC*", "error": err])));
			conn->sock->close();
			return;
		}
		string|int group = (stringp(data->group) || intp(data->group)) ? data->group : "";
		conn->type = data->type; conn->group = group;
		handler->websocket_groups[group] += ({conn->sock});
	}
	if (object handler = G->G->websocket_types[conn->type]) handler->websocket_msg(conn, data);
}

void ws_close(int reason, mapping conn) {
	if (function f = bounce(this_function)) {f(reason, conn); return;}
	if (object handler = G->G->websocket_types[conn->type])
		handler->websocket_groups[conn->group] -= ({conn->sock});
	m_delete(conn, "sock"); //De-floop
}

void ws_handler(array(string) proto, Protocols.WebSocket.Request req) {
	if (function f = bounce(this_function)) {f(proto, req); return;}
	if (req->not_query != "/ws") {
		req->response_and_finish((["error": 404, "type": "text/plain", "data": "Not found"]));
		return;
	}
	string remote_ip = req->get_ip(); //Not available after accepting the socket for some reason
	Protocols.WebSocket.Connection sock = req->websocket_accept(0);
	mapping conn = (["sock": sock, //Minstrel Hall style floop
		"remote_ip": remote_ip,
	]);
	sock->set_id(conn);
	sock->onmessage = ws_msg;
	sock->onclose = ws_close;
}

protected void create(string name)
{
	::create(name);
	register_bouncer(ws_handler); register_bouncer(ws_msg); register_bouncer(ws_close);
	mapping http = G->G->instance_config;
	if (mixed ex = catch {
		string cert = Stdio.read_file("../stillebot/certificate.pem");
		string cert2 = Stdio.read_file("../stillebot/certificate_local.pem");
		string combined = (cert || "") + (cert2 || ""); //If either cert changes, update both certs and keys
		if (object http = combined != G->G->httpserver_certificate && m_delete(G->G, "httpserver")) {
			//Cert(s) has/have changed. Force the server to be restarted.
			http->close();
			werror("Resetting HTTP server.\n");
		}

		if (G->G->httpserver) G->G->httpserver->callback = http_handler;
		else {
			G->G->httpserver_certificate = combined;
			G->G->opportunistic_tls_ctx = SSL.Context();
			array|zero wildcard = ({"*"});
			foreach (({"", "_local"}), string tag) {
				string cert = Stdio.read_file("../stillebot/certificate" + tag + ".pem");
				string key = Stdio.read_file("../stillebot/privkey" + tag + ".pem");
				if (key && cert) {
					string pk = Standards.PEM.simple_decode(key);
					array certs = Standards.PEM.Messages(cert)->get_certificates();
					G->G->opportunistic_tls_ctx->add_cert(pk, certs, wildcard);
					wildcard = UNDEFINED; //Only one wildcard cert.
				}
			}
			G->G->httpserver = Protocols.WebSocket.Port(http_handler, ws_handler, 1200, "::");
			G->G->httpserver->request_program = Function.curry(trytls)(ws_handler);
		}
	}) {
		werror("NO HTTP SERVER AVAILABLE\n%s\n", describe_backtrace(ex));
		werror("Continuing without.\n");
		//Ensure that we don't accidentally use something unsafe (eg if it's an SSL issue)
		if (object http = m_delete(G->G, "httpserver")) catch {http->close();};
	}
}
