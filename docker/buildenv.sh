#!/bin/bash

# Build environment variables needed later in deployment
# Used to register OIDC, now just sets a few environment variables

set -e # Exit on nonzero status
#set -x # Trace TODO: DEBUG
#: ${METADATA_NAME:=myemm2-liberty-build-config-14} # TODO: DEBUG
#: ${METADATA_NAMESPACE:=mas-inst8809-manage} # TODO: DEBUG
#: ${OAUTH_URL:=https://auth.inst8809.apps.sno8809.ezmaxcloud.com/oidc/endpoint/MaximoAppSuite} # TODO: DEBUG

# Export environment variables
cat << EOF > server.env
# This file (server.env) can be sourced into bash by running:
# set -a
# source ./server.env
# set +a
# OIDC-related variables
AUTH_ISSUER_URL=$OAUTH_URL
AUTH_DISCOVERY_URL=$OAUTH_URL/.well-known/openid-configuration
OIDC_DISCOVERY_URL=$OAUTH_URL/.well-known/openid-configuration
AUTH_LOGOUT_URL=$OAUTH_URL/logout
EOF
# Prepend environment variables to setenv
cat << EOF > setenv2.sh
#!/bin/bash
set -a
$(cat server.env)
set +a
$(cat setenv.sh)
EOF
mv setenv2.sh setenv.sh
chmod 775 server.env
chmod 775 setenv.sh
set +x
set +e
