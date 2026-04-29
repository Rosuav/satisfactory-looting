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
	object pem = Standards.PEM.Messages(Stdio.read_file("privkey43.pem") + Stdio.read_file("fullchain43.pem"));
	object port = Protocols.WebSocket.SSLPort(handler, handler, 12345, "::",
		pem->get_private_key(), pem->get_certificates());
	await(check_conn(12345));
	pem = Standards.PEM.Messages(Stdio.read_file("privkey44.pem") + Stdio.read_file("fullchain44.pem"));
	replace_cert(port->ctx, pem);
	await(check_conn(12345));
}
