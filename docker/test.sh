#!/bin/bash

set -e # Exit on nonzero status
set -x # Trace TODO: DEBUG
#METADATA_NAME=myemm2-liberty-build-config-14 # TODO: DEBUG
#METADATA_NAMESPACE=mas-inst8809-manage # TODO: DEBUG
#OAUTH_URL=https://auth.inst8809.apps.sno8809.ezmaxcloud.com/oidc/endpoint/MaximoAppSuite # TODO: DEBUG
# Set app ID by cutting off the build config suffix
: ${METADATA_NAME:?}
: ${METADATA_NAMESPACE:?}
APP_ID=$(echo ${METADATA_NAME:?} | sed -e 's/-build-config.*//;t;q1')
# Remove 'auth' subdomain and path from OAUTH_URL to get the base domain name
: ${OAUTH_URL:?}
DOMAIN_NAME=$(echo ${OAUTH_URL:?} | sed -e 's/^https:\/\/auth\.\([^\/]*\).*/\1/;t;q1')
APPS_DOMAIN_NAME=$(echo $DOMAIN_NAME | sed -e 's/.*\(apps.*\)/\1/;t;q1') || echo "Error: Could not find 'apps' base"

# OIDC Client Registration
# Build app url from namespace, app_id, and apps domain name
APP_URL="https://$APP_ID-$METADATA_NAMESPACE.$APPS_DOMAIN_NAME"
# Write registration JSON to file using Bash heredoc
cat << EOF > oidcreg.json
{
"client_name": "ezmaxmobile",
"token_endpoint_auth_method": "client_secret_basic",
"scope": "openid profile email general",
"redirect_uris": ["$APP_URL/ezmaxmobile", "$APP_URL/oidcclient/redirect/oidc"],
"grant_types": ["authorization_code","client_credentials","implicit","refresh_token","urn:ietf:params:oauth:grant-type:jwt-bearer"],
"response_types": ["code","token","id_token token"],
"application_type": "web",
"subject_type":"public",
"post_logout_redirect_uris": ["$APP_URL/ezmaxmobile/logout"],
"preauthorized_scope": "openid profile email general",
"introspect_tokens": true,
"trusted_uri_prefixes": ["$APP_URL/"]
}
EOF
# Register
curl -X POST --insecure --fail -u "${OAUTH_USERNAME:?}:${OAUTH_PASSWORD:?}" -H 'Content-Type: application/json' ${OAUTH_URL:?}/registration -d @oidcreg.json > oidcresp.json
# TODO: DEBUG
#cat << EOF > oidcresp.json
#{
#"client_id": "bar", "client_secret" : "foo",
#"client_secret": "baz",
#}
#EOF
# Extract client id & secret from OIDC response
CLIENT_SECRET=$(grep -Pio -m 1 '"CLIENT_SECRET"\s*:\s*"[^,"]*' oidcresp.json | sed -e 's/.*:\s*"//')
: ${CLIENT_SECRET:?}
CLIENT_ID=$(grep -Pio -m 1 '"CLIENT_ID"\s*:\s*"[^,"]*' oidcresp.json | sed -e 's/.*:\s*"//')
: ${CLIENT_ID:?}

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
CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET
# Miscellaneous/domains
APP_ID=$APP_ID
APP_URL=$APP_URL
DOMAIN_NAME=$DOMAIN_NAME
EOF
cat << EOF >> setenv.sh
#!/bin/bash
set -a
$(cat server.env)
set +a
EOF
chmod 775 server.env
chmod 775 setenv.sh
set +x
set +e
