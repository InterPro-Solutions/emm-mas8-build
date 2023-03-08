#!/bin/sh

# Get keystore from manage TLS

mkdir -p /config/managefiles
openssl pkcs12 -export \
-in /etc/ssl/certs/internal-manage-tls/tls.crt \
-inkey /etc/ssl/certs/internal-manage-tls/tls.key \
-out ${java_keystore} -password pass:${java_keystore_password}
