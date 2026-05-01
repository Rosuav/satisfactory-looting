//Sugar buyer - connect to CSR and get a certificate
inherit annotated;

string totp(string secret, int|void tm) {
	object hmac = Crypto.SHA1.HMAC(MIME.decode_base32(secret));
	int input = (tm || time()) / 30;
	string hash = hmac(sprintf("%8c", input));
	int offset = hash[-1] & 15;
	sscanf(hash[offset..offset+3], "%4c", int code);
	code &= 0x7fffffff; //It's a 31-bit code, mask off the high bit
	return ("00000000" + (string)code)[<7..]; //Assumes eight-digit codes
}

//Replace a certificate in an SSL context. I don't know if this is actually a supported concept,
//but it works fine, and future operations will use the new certificate.
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

mapping instance_config = (["sugar": "JBSWY3DPEHPK3PXP"]); //Test 2FA secret, won't work in production
class SugarBuyer {
	string buf = "";
	array|zero file_receive = 0;
	object sock;
	Concurrent.Promise|zero pinging;
	mapping(string:Standards.PEM.Messages) certs = ([]);
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
					object pem = Standards.PEM.Messages(file_receive[1]);
					certs[fn] = pem;
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
					foreach (notify; string fn;) sock->write("fetch %s\n", fn);
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
		call_out(reconnect, 0.125);
	}

	__async__ void reconnect() {
		sock = Stdio.File();
		sock->open_socket();
		sock->set_nonblocking(readable, 0, closed);
		//"/var/run/certmgr" for production (will also need a proper 2FA secret)
		if (!sock->connect_unix("/tmp/certmgr")) {
			werror("SUGARMILL NOT RUNNING\n");
			call_out(reconnect, 0.25);
		}
	}

	__async__ void ping() {
		pinging = Concurrent.Promise();
		sock->write("ping\n");
		if (catch (await(pinging->timeout(0.5)))) reconnect(); //Ping failed. TODO: Reraise if it wasn't a timeout that got thrown
		pinging = 0;
		//Else ping succeeded, all well
	}

	__async__ Standards.PEM.Messages request(string fn) {
		if (Standards.PEM.Messages cert = certs[fn]) return cert;
		werror("Sugar: Waiting for %s cert...\n", fn);
		object p = Concurrent.Promise();
		awaiting[fn] += ({p});
		sock->write("fetch %s\n", fn); //In theory we could skip this if someone else is waiting, but that's unlikely, and it won't hurt (we'll get an immediate "unilateral" transmission)
		return await(p->future());
	}

	void register(string fn, SSL.Context ctx) {
		notify[fn] += ({ctx});
	}

	protected void create() {reconnect();}
}

//TODO: Move the actual code into here, ideally making the class just maintain basic state
@export: Standards.PEM.Messages request_certificate(string fn) {
	return G->G->sugarbuyer->request(fn);
}
@export: void register_ssl_certificate(string fn, SSL.Context ctx) {
	G->G->sugarbuyer->register(fn, ctx);
}

//Retain an existing sugar buyer if reasonable, else establish a new one
constant VERSION = 1; //Increment if it's unreasonable to retain
protected void create(string name) {
	::create(name);
	object|zero sug = G->G->sugarbuyer;
	if (sug && sug->VERSION != VERSION) {sug->sock->close(); sug = 0;}
	if (!sug) G->G->sugarbuyer = SugarBuyer();
}
