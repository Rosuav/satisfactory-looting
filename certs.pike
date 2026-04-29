string totp(string secret, int|void tm) {
	object hmac = Crypto.SHA1.HMAC(MIME.decode_base32(secret));
	int input = (tm || time()) / 30;
	string hash = hmac(sprintf("%8c", input));
	int offset = hash[-1] & 15;
	sscanf(hash[offset..offset+3], "%4c", int code);
	code &= 0x7fffffff; //It's a 31-bit code, mask off the high bit
	return ("00000000" + (string)code)[<7..]; //Assumes eight-digit codes
}

mapping instance_config = Standards.JSON.decode(Stdio.read_file("../stillebot/instance-config.json"));
class SugarBuyer {
	string buf = "";
	array|zero file_receive = 0;
	object sock;
	Concurrent.Promise|zero pinging;
	mapping(string:string|array) files = ([]);

	void readable(object sock, string data) {
		buf += data;
		while (sscanf(buf, "%s\n%s", string line, buf) == 2) {
			if (file_receive) {
				if (line == ".") {
					//File complete! See if anyone's waiting on it.
					//Note that this has a very small race condition. I would like an atomic
					//"replace mapping value and return the previous value" but we're single
					//threaded so it shouldn't happen.
					string|array pending = files[file_receive[0]];
					files[file_receive[0]] = file_receive[1];
					if (arrayp(pending)) pending->success(file_receive[1]);
					file_receive = 0;
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
					foreach (files; string fn;) sock->write("fetch %s\n", fn);
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
		if (!sock->connect_unix("/var/run/certmgr")) werror("SUGARMILL NOT RUNNING\n"); //Autoretry?
	}

	__async__ void ping() {
		pinging = Concurrent.Promise();
		sock->write("ping\n");
		if (catch (await(pinging->timeout(0.5)))) reconnect(); //Ping failed. TODO: Reraise if it wasn't a timeout that got thrown
		pinging = 0;
		//Else ping succeeded, all well
	}

	__async__ string request(string fn) {
		mixed cert = files[fn];
		if (stringp(cert)) return cert;
		//If not a string, it should be zero or an array. Add ourselves to it.
		werror("Sugar: Waiting for %s cert...\n", fn);
		object p = Concurrent.Promise();
		files[fn] += ({p});
		if (!cert) sock->write("fetch %s\n", fn); //If there previously wasn't any queue, we're the first, so request it
		return await(p->future());
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
		werror("Connecting...\n");
		sock->connect("127.0.0.1", port);
	}
	void rawwrite() {
		werror("SSLing...\n");
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
	object pem = Standards.PEM.Messages(await(sugar->request("stillebot.com")));
	object port = Protocols.WebSocket.SSLPort(handler, handler, 12345, "::",
		pem->get_private_key(), pem->get_certificates());
	await(check_conn(12345));
	pem = Standards.PEM.Messages(await(sugar->request("sikorsky.stillebot.com")));
	replace_cert(port->ctx, pem);
	await(check_conn(12345));
}
