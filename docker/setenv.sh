#!/bin/sh

# Runtime environment variables for deploying EMM

#export ENVIRONMENT_APPID=manage
#export ENVIRONMENT_APPID=ezmaxmobile
# These variables are set during the build process and appended to this file
#export APP_URL=https://manage.inst8809.apps.sno8809.ezmaxcloud.com
# The OIDC URLs *must* be public (not internal service URLs), as users will be redirected to them
#export OIDC_BASE_URL=https://coreidp.mas-inst8809-core.svc/oidc/endpoint/MaximoAppSuite # i.e this doesn't work
#export OIDC_BASE_URL=https://auth.inst8809.apps.sno8809.ezmaxcloud.com/oidc/endpoint/MaximoAppSuite
#export OIDC_DISCOVERY_URL=${OIDC_BASE_URL}/.well-known/openid-configuration
#export DOMAIN_NAME=inst8809.apps.sno8809.ezmaxcloud.com
# MAS_LOGOUT_URL must be set in deployment config
#export MAS_LOGOUT_URL=https://masdev.home.inst8809.apps.sno8809.ezmaxcloud.com/logout

# We take care to give precedence to variables that are already set at runtime, i.e overridden via deployment config
# Export all defined variables
set -a
: ${ENVIRONMENT_APPID:=${APP_ID:=ezmaxmobile}}
# DB URLs, etc must be set in deployment config
#export MXE_DB_URL="jdbc:sqlserver://;serverName=54.209.23.69;databaseName=mas8snodemo;portNumber=1433;encrypt=true;trustServerCertificate=true;"
#export MXE_DB_SCHEMAOWNER=dbo
#export MXE_DB_DRIVER=com.microsoft.sqlserver.jdbc.SQLServerDriver
#export MXE_MAS_WORKSPACEID=masdev
#export MXE_DB_USER=sa
#export MXE_DB_PASSWORD=Captain1
: ${DB_SSL_ENABLED:=nossl}
: ${MXE_MASDEPLOYED:=1}
: ${MXE_USEAPPSERVERSECURITY:=1}
: ${MXE_OLDAUTHINTICATIONTYPE:=local}
: ${MXE_OLDAUTHENTICATIONTYPE:=local}
: ${MXE_USESQLSERVERSEQUENCE:=1}

# Try and set internal API URLs if CORE_NAMESPACE set
if [[ -n $CORE_NAMESPACE ]]; then
  : ${MXE_MASINTERNALAPI:=https://internalapi.$CORE_NAMESPACE}
  : ${MXE_MASINTERNALPUSHNOTIFAPI:=https://push-notification-service-internal.$CORE_NAMESPACE.svc}
fi

# These are set during OIDC registration during build time
#export CLIENT_ID=manage
#export CLIENT_SECRET=rYNS1gPCvKPzjiETVFSkfQQ3ZbTaji1F
#export CLIENT_ID=myemm2
#export CLIENT_SECRET=8zO0gOSGkmoRZDMR0QmrNSVodAkbWIE6m7MkK3kEIHGFVEAwgG7t8OrhYXWq
# These four must be set in deployment config
#export java_truststore=/opt/ibm/wlp/usr/servers/defaultServer/truststore/trust.p12
#export java_keystore=/opt/ibm/wlp/usr/servers/defaultServer/managefiles/key.p12
#export java_truststore_password=9AUZyNWe4jrUN0Xd
#export java_keystore_password=9AUZyNWe4jrUN0Xd
# TODO: Where is this hash from and is it needed?
#export ENCRYPT_PROPERTY_HASH=5556b78805e7223631c659ee0836fa0663b176cb6bafb9fc5ea99f5ea565d84f

# If crypto keys not set, try to extract them from some `bundle.properties`
if [[ -n $MXE_SECURITY_CRYPTO_KEY ]]; then
  export MXE_SECURITY_CRYPTO_KEY=$(grep -Phiorm 1 '(?<=mxe\.security\.crypto\.key=)\S+' /config/manage/ || echo '')
  export MXE_SECURITY_CRYPTOX_KEY=$(grep -Phiorm 1 '(?<=mxe\.security\.cryptox\.key=)\S+' /config/manage/ || echo '')
fi
#export MXE_SECURITY_OLD_CRYPTOX_KEY=swBfNAMPoIWJsZqlhEJtYhDh
#export MXE_SECURITY_OLD_CRYPTO_KEY=XVhIsqOvAOjmMiHCnuvHZmUN
export SETENV_RUN=1
set +a
