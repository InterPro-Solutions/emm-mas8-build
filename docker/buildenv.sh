#!/bin/bash

# Build environment variables needed later in deployment
# Also, register an OIDC client and store the secret, etc for later

set -e # Exit on nonzero status
set -x # Trace TODO: DEBUG
#: ${METADATA_NAME:=myemm2-liberty-build-config-14} # TODO: DEBUG
#: ${METADATA_NAMESPACE:=mas-inst8809-manage} # TODO: DEBUG
#: ${OAUTH_URL:=https://auth.inst8809.apps.sno8809.ezmaxcloud.com/oidc/endpoint/MaximoAppSuite} # TODO: DEBUG
# Set app ID by cutting off the build config suffix
: ${METADATA_NAME:?}
: ${METADATA_NAMESPACE:?}
APP_ID=$(echo ${METADATA_NAME:?} | sed -e 's/-build-config.*//;t;q1')
# Remove 'auth' subdomain and path from OAUTH_URL to get the base domain name
: ${OAUTH_URL:?}
DOMAIN_NAME=$(echo ${OAUTH_URL:?} | sed -e 's/^https:\/\/auth\.\([^\/]*\).*/\1/;t;q1')
APPS_DOMAIN_NAME=$(echo $DOMAIN_NAME | sed -e 's/.*\(apps.*\)/\1/;t;q1') || echo "Error: Could not find 'apps' base"

# Try and get core namespace for later
# -n suppress printing; p prints only if match
CORE_NAMESPACE=$(echo ${METADATA_NAMESPACE:?} | sed -ne 's/-manage$/-core/p')

# OIDC Client Registration
# Build app url from namespace, app_id, and apps domain name
APP_URL="https://$APP_ID-$METADATA_NAMESPACE.$APPS_DOMAIN_NAME"
CLIENT_ID=${APP_ID:?}
# Basic user auth
OAUTH_BASIC="${OAUTH_USERNAME:?}:${OAUTH_PASSWORD:?}"
# Modify client if it exists, otherwise create a new one
oidc_status=$(curl -kw '%{http_code}' -o oidcreg.json -u "${OAUTH_BASIC:?}" "$OAUTH_URL/registration/${CLIENT_ID:?}")
if [[ "$oidc_status" == 200 ]]; then
  method="PUT"
  reg_url="$OAUTH_URL/registration/$CLIENT_ID"
else
  method="POST"
  reg_url="$OAUTH_URL/registration"
fi
# Use bash heredoc to write reg info
cat << EOF > oidcreg.json
{
"client_name": "ezmaxmobile",
"client_id": "$CLIENT_ID",
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
# Add/change registration
curl -kfX ${method:?} -u "$OAUTH_BASIC" -H 'Content-Type: application/json' ${reg_url:?} -d @oidcreg.json > oidcres.json
# TODO: DEBUG
#cat << EOF > oidcres.json
#{
#"client_id": "bar", "client_secret" : "foo",
#"client_secret": "baz",
#}
#EOF
# Extract client id & secret from OIDC response
CLIENT_SECRET=$(grep -Pio -m 1 '"CLIENT_SECRET"\s*:\s*"[^,"]*' oidcres.json | sed -e 's/.*:\s*"//')
: ${CLIENT_SECRET:?}
CLIENT_ID=$(grep -Pio -m 1 '"CLIENT_ID"\s*:\s*"[^,"]*' oidcres.json | sed -e 's/.*:\s*"//')
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
CORE_NAMESPACE=$CORE_NAMESPACE
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
