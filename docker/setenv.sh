#!/bin/sh

#export ENVIRONMENT_APPID=manage
export ENVIRONMENT_APPID=ezmaxmobile
export APP_URL=https://manage.inst8809.apps.sno8809.ezmaxcloud.com
export MAS_LOGOUT_URL=https://masdev.home.inst8809.apps.sno8809.ezmaxcloud.com/logout
# The OIDC URLs *must* be public (not internal service URLs), as users will be directed to them
#export OIDC_BASE_URL=https://coreidp.mas-inst8809-core.svc/oidc/endpoint/MaximoAppSuite # doesn't work
export OIDC_BASE_URL=https://auth.inst8809.apps.sno8809.ezmaxcloud.com/oidc/endpoint/MaximoAppSuite
export OIDC_DISCOVERY_URL=${OIDC_BASE_URL}/.well-known/openid-configuration
export DOMAIN_NAME=inst8809.apps.sno8809.ezmaxcloud.com
export DB_SSL_ENABLED=nossl
export MXE_DB_URL="jdbc:sqlserver://;serverName=54.209.23.69;databaseName=mas8snodemo;portNumber=1433;encrypt=true;trustServerCertificate=true;"
export MXE_DB_SCHEMAOWNER=dbo
export MXE_DB_DRIVER=com.microsoft.sqlserver.jdbc.SQLServerDriver
export MXE_MAS_WORKSPACEID=masdev
export MXE_MASDEPLOYED=1
export MXE_USEAPPSERVERSECURITY=1
export MXE_OLDAUTHINTICATIONTYPE=local
export MXE_DB_USER=sa
export MXE_DB_PASSWORD=Captain1
export MXE_MASINTERNALAPI=https://internalapi.mas-inst8809-core.svc
export MXE_MASINTERNALPUSHNOTIFAPI=https://push-notification-service-internal.mas-inst8809-core.svc
export MXE_USESQLSERVERSEQUENCE=1
#export CLIENT_ID=manage
#export CLIENT_SECRET=rYNS1gPCvKPzjiETVFSkfQQ3ZbTaji1F
export CLIENT_ID=myemm2
export CLIENT_SECRET=8zO0gOSGkmoRZDMR0QmrNSVodAkbWIE6m7MkK3kEIHGFVEAwgG7t8OrhYXWq
# These four must be set in deployment config
#export java_truststore=/opt/ibm/wlp/usr/servers/defaultServer/truststore/trust.p12
#export java_keystore=/opt/ibm/wlp/usr/servers/defaultServer/managefiles/key.p12
#export java_truststore_password=9AUZyNWe4jrUN0Xd
#export java_keystore_password=9AUZyNWe4jrUN0Xd
export ENCRYPT_PROPERTY_HASH=5556b78805e7223631c659ee0836fa0663b176cb6bafb9fc5ea99f5ea565d84f
export MXE_SECURITY_CRYPTO_KEY=XVhIsqOvAOjmMiHCnuvHZmUN
export MXE_SECURITY_OLD_CRYPTOX_KEY=swBfNAMPoIWJsZqlhEJtYhDh
export MXE_SECURITY_CRYPTOX_KEY=swBfNAMPoIWJsZqlhEJtYhDh
export MXE_SECURITY_OLD_CRYPTO_KEY=XVhIsqOvAOjmMiHCnuvHZmUN

