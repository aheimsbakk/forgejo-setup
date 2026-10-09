#!/bin/bash
# Create the self-signed TLS certificate Forgejo serves HTTPS with.
# Run on the target as root. LAN_IP is read from the compose env file so
# the certificate always names the address the instance is published on.
#
# Browsers, git clients and CI pin this certificate. Regenerating it
# breaks those pins, so an existing pair that still covers the current
# address is left untouched.
#
# Loopback names are in the subject alternative names because Forgejo
# calls itself through LOCAL_ROOT_URL (https://localhost:3000/ by
# default); a self-signed certificate has to cover that host too, or
# Forgejo rejects its own requests.
set -euo pipefail

CERT_DIR=/srv/forgejo-certs
CERT_FILE=$CERT_DIR/forgejo.crt
KEY_FILE=$CERT_DIR/forgejo.key
ENV_FILE=/opt/forgejo/.env
DAYS=1825 # 5 years; pins must be re-armed on every client after this
LAN_NAME=forgejo.local

# LAN_IP is read, not sourced: the file is a flat KEY=value list and
# parsing it keeps this script free of dynamic command execution.
[ -f "$ENV_FILE" ] || {
	echo "missing $ENV_FILE; it must define LAN_IP" >&2
	exit 1
}
LAN_IP=$(sed -n 's/^LAN_IP=//p' "$ENV_FILE" | head -n 1)
if [[ ! $LAN_IP =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
	echo "LAN_IP in $ENV_FILE is not an IPv4 address: '$LAN_IP'" >&2
	exit 1
fi

mkdir -p "$CERT_DIR"

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] &&
	openssl x509 -in "$CERT_FILE" -checkend 0 -noout 2>/dev/null; then
	san=$(openssl x509 -in "$CERT_FILE" -noout -ext subjectAltName | tr -d ' \n')
	if [[ $san == *"$LAN_IP"* && $san == *"$LAN_NAME"* ]]; then
		echo "keeping existing certificate (still valid for $LAN_IP)"
		openssl x509 -in "$CERT_FILE" -noout -enddate
		exit 0
	fi
fi

# RSA 2048: the most widely accepted choice for git clients and
# browsers; the pin lifetime is years, so key size is not a bottleneck.
umask 077
openssl req -x509 -newkey rsa:2048 -sha256 -days "$DAYS" -nodes \
	-keyout "$KEY_FILE" -out "$CERT_FILE" \
	-subj "/CN=$LAN_NAME" \
	-addext "subjectAltName=IP:$LAN_IP,IP:127.0.0.1,DNS:$LAN_NAME,DNS:localhost,DNS:$(hostname)"

# uid/gid 1000 is the container user; it must read the key. The key
# never leaves the machine: only the .crt is handed to clients.
chown 1000:1000 "$CERT_DIR" "$CERT_FILE" "$KEY_FILE"
chmod 755 "$CERT_DIR"
chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

echo "created $CERT_FILE and $KEY_FILE"
openssl x509 -in "$CERT_FILE" -noout -subject -enddate -ext subjectAltName
# The fingerprint lets an operator confirm on a client that the pin
# matches what the server presents.
openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256
