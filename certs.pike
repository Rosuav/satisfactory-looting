string totp(string secret, int|void tm) {
	object hmac = Crypto.SHA1.HMAC(MIME.decode_base32(secret));
	int input = (tm || time()) / 30;
	string hash = hmac(sprintf("%8c", input));
	int offset = hash[-1] & 15;
	sscanf(hash[offset..offset+3], "%4c", int code);
	code &= 0x7fffffff; //It's a 31-bit code, mask off the high bit
	return ("00000000" + (string)code)[<7..]; //Assumes eight-digit codes
}

mapping instance_config = (["sugar": "JBSWY3DPEHPK3PXP"]); //Test 2FA secret, won't work in production
class SugarBuyer {
	string buf = "";
	array|zero file_receive = 0;
	object sock;
	Concurrent.Promise|zero pinging;
	mapping(string:string) files = ([]);
	mapping(string:array(Concurrent.Promise)) awaiting = ([]);
	mapping(string:array(SSL.Context)) notify = ([]);

	void readable(object sock, string data) {
		buf += data;
		while (sscanf(buf, "%s\n%s", string line, buf) == 2) {
			if (file_receive) {
				if (line == ".") {
					//File complete! Send it along to anyone who's waiting or interested.
					//We shouldn't receive any certificate that we didn't ask for, so
					//the chances that there's nobody either waiting or interested are
					//very low; so we decode the PEM regardless.
					string fn = file_receive[0];
					werror("GOT FILE %O\n", fn);
					files[fn] = file_receive[1];
					object pem = Standards.PEM.Messages(file_receive[1]);
					file_receive = 0;
					//Those waiting will have inserted promises into the array
					if (array pending = m_delete(awaiting, fn))
						pending->success(pem);
					//And those interested will have stuck SSL contexts into a separate array.
					//These ones remain, so multiple notifications can be sent to the same context.
					if (array interested = notify[fn])
						replace_cert(interested[*], pem);
					continue;
				}
				file_receive[1] += line + "\n";
				continue;
			}
			[string cmd, array args] = Array.shift(line / " ");
			switch (cmd) {
				case "hello":
					write("Sugarmill: Attempting auth...\n");
					sock->write("auth sugar %s\n", totp(instance_config->sugar));
					break;
				case "login":
					write("Sugarmill: Login OK\n");
					//Rerequest any that have previously been requested, either because they're
					//pending or because we already wanted them
					foreach (awaiting; string fn;) sock->write("fetch %s\n", fn);
					break;
				case "certificate": file_receive = ({args[0], ""}); break;
				case "pong":
					write("Sugarmill still alive\n");
					if (pinging) pinging->success(1);
					break;
				default: break;
			}
		}
	}

	void closed(object sock) {
		werror("SUGARMILL DISCONNECTED\n");
		//Autoreconnect?
	}

	__async__ void reconnect() {
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(readable, 0, closed);
		//"/var/run/certmgr" for production (will also need a proper 
		if (!sock->connect_unix("/tmp/certmgr")) werror("SUGARMILL NOT RUNNING\n"); //Autoretry?
	}

	__async__ void ping() {
		pinging = Concurrent.Promise();
		sock->write("ping\n");
		if (catch (await(pinging->timeout(0.5)))) reconnect(); //Ping failed. TODO: Reraise if it wasn't a timeout that got thrown
		pinging = 0;
		//Else ping succeeded, all well
	}

	__async__ Standards.PEM.Messages request(string fn) {
		if (string cert = files[fn]) return Standards.PEM.Messages(cert);
		//If not a string, it should be zero or an array. Add ourselves to it.
		werror("Sugar: Waiting for %s cert...\n", fn);
		object p = Concurrent.Promise();
		awaiting[fn] += ({p});
		if (sizeof(awaiting[fn]) == 1) sock->write("fetch %s\n", fn); //If we're the first, request it
		return await(p->future());
	}

	void register(string fn, SSL.Context ctx) {
		notify[fn] += ({ctx});
	}

	protected void create() {reconnect();}
}

void handler(mixed ... args) { }

void check_cert(SSL.Context ctx) {
	array cps = ctx->find_cert_domain("sikorsky.rosuav.com");
	if (sizeof(cps) != 1) {werror("Cert domain not exactly one %O\n", cps); return;}
	object cp = cps[0];
	array parts = Standards.X509.decode_certificate(cp->certs[0])->validity[1]->value / 2;
	werror("Cert expiration: 20%s-%s-%s %s:%s:%s\n", @parts);
}

void replace_cert(SSL.Context ctx, Standards.PEM.Messages pem) {
	array certs = pem->get_certificates();
	//Find the existing CertificatePair. We assume that the set of domains will not change, so we use the
	//new commonName to look up the CertificatePair, and will not be making any changes to that lookup.
	object cert = Standards.X509.decode_certificate(certs[0]);
	string cn = Standards.PKCS.Certificate.decode_distinguished_name(cert->subject)->commonName[0];
	object cp = ctx->find_cert_domain(cn)[0];
	object key = Standards.PKCS.parse_private_key(pem->get_private_key());
	cp->key = key; cp->certs = certs;
}

class check_conn {
	inherit Concurrent.Promise;
	object sock;
	void sockclosed() {success(1);}

	protected void create(int port) {
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(0, rawwrite, sockclosed);
		sock->connect("127.0.0.1", port);
	}
	void rawwrite() {
		sock = SSL.File(sock, SSL.Context());
		sock->set_nonblocking(0, 0, sockclosed, 0, 0) {
			string cert = sock->get_peer_certificates()[0];
			array parts = Standards.X509.decode_certificate(cert)->validity[1]->value / 2;
			werror("Cert expiration: 20%s-%s-%s %s:%s:%s\n", @parts);
			sock->close();
			success(2);
		};
		sock->connect();
	}
}

int main1() {
	object ctx = SSL.Context();
	object pem = Standards.PEM.Messages(Stdio.read_file("privkey43.pem") + Stdio.read_file("fullchain43.pem"));
	ctx->add_cert(pem->get_private_key(), pem->get_certificates(), ({"*"}));
	check_cert(ctx);
	pem = Standards.PEM.Messages(Stdio.read_file("privkey44.pem") + Stdio.read_file("fullchain44.pem"));
	replace_cert(ctx, pem);
	check_cert(ctx);
}

__async__ int main() {
	object sugar = SugarBuyer();
	object pem = await(sugar->request("stillebot.com"));
	object port = Protocols.WebSocket.SSLPort(handler, handler, 12345, "::",
		pem->get_private_key(), pem->get_certificates());
	sugar->register("stillebot.com", port->ctx);
	await(check_conn(12345));
	//pem = Standards.PEM.Messages(await(sugar->request("sikorsky.stillebot.com")));
	//replace_cert(port->ctx, pem);
	sleep(1);
	await(check_conn(12345));
}
