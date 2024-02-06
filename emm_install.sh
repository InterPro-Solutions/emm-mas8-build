#!/bin/bash
# Installs EMM using the OpenShift CLI
# Within this file are embedded multiple separate YAML files used to create the OpenShift objects.
# Each installation step is numbered to aid navigation.

DEFAULT_EMM_EAR="emm-ear"
DEFAULT_LIBERTY_EAR="emm-liberty"

# Prompts user for name and returns
promptuser() {
  read -p "Missing $1, please enter name: " -r
  if [[ -z "$REPLY" ]]; then echo "Error: Missing value for $1, exiting" >&2 && exit 1; fi
  echo "$REPLY"
}

# 0. Try to source in environment variables from companion file(s)
ENV_FILE=$(find . -maxdepth 1 -name 'emm*.env' | sort | head -n1)
source "$ENV_FILE" > /dev/null 2>&1
# If ASK_ENV set, ask user to provide an .env file
if [[ -n "$ASK_ENV" ]]; then
  read -p "Enter .env file name: " -r
  if [[ -n "$REPLY" ]]; then source "$REPLY"; fi
fi

# 0.1 Check CLI exists, we are logged in, and have permissions
oc_version=$(oc version)
rtn_code=$?
if [[ -z "$oc_version" || rtn_code -eq 127 ]]; then
  echo "OpenShift CLI not installed, check your path or go to https://access.redhat.com/downloads/content/290"
  exit 1
fi
set -e
# 0.2 Check for admin permissions
if [[ $(oc auth can-i '*' '*') != 'yes' ]]; then echo "Insufficient permissions to install. Please copy and paste Login command with permissions and try again." && exit 1; fi
# Try and find core & manage projects
namespaces=$(oc get namespaces -oname | sed -e 's/^.*\///')
[[ -z "$core_namespace" ]] && core_namespace=$(promptuser "Core namespace")
[[ -z "$manage_namespace" ]] && manage_namespace=$(promptuser "Manage namespace")
instance_id=$(echo $core_namespace | grep -Po -- "(?<=-).*(?=-)" || promptuser "Workspace/instance ID")
echo "This script will install EZMaxMobile into your OpenShift Cluster."
echo "Core namespace: $core_namespace"
echo "Manage namespace: $manage_namespace"

# 1. Build EMM EAR image
# 1.1 Switch to manage namespace and create EMM EAR ImageStream
oc project "$manage_namespace"
imagestreams=$(oc get imagestreams -oname | sed -e 's/^.*\///') # remove leading '***/'
applicationid=$(echo "$imagestreams" | grep -Pom 1 "(?<=$instance_id-).*(?=-admin)" || promptuser "masdev application ID")
emm_ear=$(echo "$imagestreams" | grep -Pm 1 "$DEFAULT_EMM_EAR" || true)
# Matching EAR found; prompt to use it
if [[ -n "$emm_ear" ]]; then
  read -p "Use EMM EAR image name '$emm_ear'? [Y/n]: " -r
  # Prompt for name if no
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "Enter name for EMM EAR [$DEFAULT_EMM_EAR]: " -r
    DEFAULT_EMM_EAR="${REPLY:-$DEFAULT_EMM_EAR}"
    emm_ear=$(echo "$imagestreams" | grep -Pm 1 "$DEFAULT_EMM_EAR" || true)
  fi
fi
# Create EMM EAR ImageStream if not exists
if [[ -z "$emm_ear" ]]; then
  emm_ear="$DEFAULT_EMM_EAR"
  oc create imagestream "$emm_ear"
fi
echo "EMM EAR image: $emm_ear"

# 1.2 Create EMM EAR BuildConfig
# 1.2.1 Find masdev image
masdev_image=$(echo "$imagestreams" | grep -Pm 1 "\-$applicationid-admin" || promptuser "$applicationid-admin ImageStream")
echo "masdev image: $masdev_image"
# 1.2.2 Find image secrets & ConfigMaps
echo "Discovering secrets/configuration for EMM EAR build..."
secrets=$(oc get secrets -oname | sed -e 's/^.*\///') # remove leading '***/'
truststorepasswd=$(echo "$secrets" | grep -Pm 1 "\-truststorepasswd" || promptuser "truststorepasswd Secret")
configmaps=$(oc get configmaps -oname | sed -e 's/^.*\///') # remove leading '***/'
truststorecfg=$(echo "$configmaps" | grep -Pm 1 "\-truststore-cfg" || promptuser "truststorecfg ConfigMap")

# 1.2.2 Check if we need to build maximo-all.ear
# This docker section is prepended by default;
# If an all-build doesn't exist, the admin-build's dockerfile is used.
default_ear_prelude() {
cat << EOF
${manage_version}

ENV MXE_MASDEPLOYED=1

ENV MXE_USESQLSERVERSEQUENCE=1

ENV LC_ALL=en_US.UTF-8

ENV LANGUAGE_BASE=en

ENV LANGUAGE_ADD=
EOF
}

# Get manageadmin version from admin-build-config
manage_version=$(oc get buildconfigs -l bundleType=admin -o jsonpath='{.items[0]..dockerfile}' | grep -Pm 1 'FROM\s+.*\s+AS\s+ADMIN' || echo 'FROM cp.icr.io/cp/manage/manageadmin:8.4.5 AS ADMIN')
# manage_version=$(oc get imagestreams -l bundleType=admin -o jsonpath='{.items[0]..labels.version}')
all_build_config=$(oc get buildconfigs -l bundleType=all -oname)
# If all-build doesn't exist, we need to build it as part of the EAR build!
# `BUILD_ALL_EAR` also triggers this
if [[ -z "$all_build_config" || -n "$BUILD_ALL_EAR" ]]; then
  ear_build_insert=$(oc get buildconfigs -l bundleType=admin -o jsonpath='{.items[0]..dockerfile}' | sed -Ee 's/\s*RUN.*buildmaximo\S+\.sh.*$/RUN .\/maximo-all.sh/' | sed -e 'G')
  echo "No 'all' server bundle; will build maximo-all.ear from scratch"
else
  ear_build_insert=$(default_ear_prelude)
fi

# 1.2.3 Write BuildConfig
ear_config=${emm_ear}-build-config
deploy_package="${deploy_package:=ezmaxmobile.zip}"
[[ -z "$deploy_token" ]] && deploy_token='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJidWNrZXQiOiJ0ZXN0LWVtbS1kZXBsb3ltZW50cyIsImtleVJlZyI6Ii4qZXptYXhtb2JpbGVbXi9dKiQifQ.-Npu7D9vSUxZkTEbmDrNgdBswmR8E3U6K-PN95yyJ9o'
echo "EMM deploy package: $deploy_package"
# We need to modify the commands to pull the ezmaxmobile.zip file for the client
# which may have an HTTP server to pull from instead.
# If EMM_URL etc. specified, write them into the build config
deploy_env_config() {
  [[ -n "$EMM_URL" ]] && echo -e "- name: EMM_URL\n  value: $EMM_URL"
  # get username & password from secret
  if [[ -n "$DEPLOY_SECRET" ]]; then
    cat << EOF
- name: DEPLOY_USER
  valueFrom:
    secretKeyRef:
      name: "$DEPLOY_SECRET"
      key: username
- name: DEPLOY_PASSWORD
  valueFrom:
    secretKeyRef:
      name: "$DEPLOY_SECRET"
      key: password
EOF
  else
    [[ -n "$DEPLOY_USER" ]] && echo -e "- name: DEPLOY_USER\n  value: $DEPLOY_USER"
    [[ -n "$DEPLOY_PASSWORD" ]] && echo -e "- name: DEPLOY_PASSWORD\n  value: $DEPLOY_PASSWORD"
  fi
}
emm_url_config() {
  if [[ -n "$EMM_URL" ]]; then
    echo '"$EMM_URL"' # value already set by deploy_env_config
  else
    echo '$(wget -q -O - --header="Authorization: Bearer $DEPLOY_TOKEN" "$DEPLOY_GATEWAY_URL")'
  fi
}
wget_config() {
  # Using S3 AccessKeyId & Secret
  # https://glacius.tmont.com/articles/uploading-to-s3-in-bash
  if [[ -n "$EMM_S3_RESOURCE" ]]; then
    cat << EOM
date_header=\$(date -R) &&\\
stringToSign="GET\n\n\n\$date_header\n/$EMM_S3_RESOURCE" &&\\
signature=\$(echo -en "\$stringToSign" | openssl dgst -sha1 -hmac "\$DEPLOY_PASSWORD" -binary | base64 -w 0) &&\\
auth_header="AWS \$DEPLOY_USER:\$signature" &&\\
echo "\$auth_header \$date_header" &&\\
wget -O ezmaxmobile.zip -c "\$EMM_URL" --header="Authorization: \$auth_header" --header="Date: \$date_header"
EOM
  # pass user & password to wget if set
  elif [[ -n "$DEPLOY_USER" || -n "$DEPLOY_SECRET" ]]; then
    echo -n 'wget -O ezmaxmobile.zip --user "$DEPLOY_USER" --password "$DEPLOY_PASSWORD" -c "$EMM_URL"'
  else
    echo -n 'wget -O ezmaxmobile.zip -c "$EMM_URL"'
  fi
}
# Backslash followed by newline is broken inside subshell heredocs, so use functions instead.
# See https://unix.stackexchange.com/a/534078
# Takes three arguments: build-config name, image tag to pull, and whether to skip config change trigger
apply_ear_config() {
# cat << EOF > $1.yaml
oc apply -f- << EOF
kind: BuildConfig
apiVersion: build.openshift.io/v1
metadata:
  name: "$1"
  namespace: $manage_namespace
spec:
  nodeSelector: null
  output:
    to:
      kind: ImageStreamTag
      name: "${emm_ear}:v1"
  resources:
    limits:
      ephemeral-storage: 100Gi
    requests:
      ephemeral-storage: 30Gi
  strategy:
    type: Docker
    dockerStrategy:
      pullSecret:
        name: ibm-entitlement
      env:
        - name: DEPLOY_GATEWAY_URL
          value: >-
            https://1qbx7rd5w9.execute-api.us-east-1.amazonaws.com/default/ezmax-deploy?key=${deploy_package}
        - name: DEPLOY_TOKEN
          value: >-
            $deploy_token
$(echo "$(deploy_env_config)" | sed 's/^/        /')
      forcePull: true
  postCommit: {}
  source:
    type: Dockerfile
    dockerfile: >
$(echo "$ear_build_insert" | sed 's/^/      /')

      COPY --chown=maximoinstall:0 additional-server-files/ /opt/IBM/SMP/maximo/additional-server-files

      WORKDIR /opt/IBM/SMP/maximo/tools/maximo

      COPY --chown=maximoinstall:0 deployment/ /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment

      WORKDIR /opt/IBM/SMP

      # Download and unzip ezmaxmobile.zip, from deploy gateway or HTTP server override

      RUN \\
        EMM_URL=$(emm_url_config) &&\\
$(echo "$(wget_config)" | sed 's/^/        /') &&\\
        unzip ezmaxmobile.zip

      # Build EMM ear and print some debugging info

      RUN \\
        cd ezmaxmobile &&\\
        find ../maximo/deployment -name "*.ear" &&\\
        EAR_PATH=\$(find ../maximo/deployment -name "maximo-all.ear" | head -n1) &&\\
        sed -i "s@maximo.ear\"\\s*value=\".*\"@maximo.ear\" value=\"\$EAR_PATH\"@g" buildemmear.xml &&\\
        cat buildemmear.xml &&\\
        chmod u+x ./buildemmear.sh &&\\
        ./buildemmear.sh &&\\
        ls -al default &&\\
        ls -al was-liberty-default &&\\
        ls -al was-liberty-default/emm-server/apps &&\\
        ls -al /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment &&\\
        ls -al /opt/IBM/SMP/maximo/additional-server-files

      WORKDIR /opt/IBM/SMP/maximo/tools/maximo

      #CMD sleep 123456789

    images:
      - from:
          kind: ImageStreamTag
          name: "$2"
        paths:
          - sourcePath: >-
              /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment
            destinationDir: .
          - sourcePath: /opt/IBM/SMP/maximo/additional-server-files
            destinationDir: .
    secrets:
      - secret:
          name: $truststorepasswd
        destinationDir: tmp_build_files
    configMaps:
      - configMap:
          name: $truststorecfg
        destinationDir: tmp_build_files
  runPolicy: Serial
$([[ -z "$3" ]] && cat << EOM
  triggers:
    - type: ConfigChange
EOM
)
EOF
}
apply_output=$(apply_ear_config "$ear_config" "${masdev_image}:latest")
# Also create a -rebuild-config just for rebuilding EMM
if [[ -n "$BUILD_ALL_EAR" ]]; then
  ear_build_insert=$(default_ear_prelude) # don't include maximo-all build insert for rebuild
  rebuild_apply_output=$(apply_ear_config "${emm_ear}-rebuild-config" "${emm_ear}:v1" "1")
fi
# 1.3 (Optional) Build EMM EAR
# Build EAR only if config was changed (and not created)
# This is needed because the ConfigChange trigger only builds on initial creation as of 2023-04-28
if [[ -z "$(echo "$apply_output" | grep -Pm 1 'unchanged|created')" ]]; then
  ear_config_changed="1"
  oc start-build $ear_config --wait
fi

# 2. Create EMM Liberty image
# 2.1 Get EMM Liberty image name
emm_liberty=$(echo "$imagestreams" | grep -Pm 1 "$DEFAULT_LIBERTY_EAR" || true)
# Matching EAR found; prompt to use it
if [[ -n "$emm_liberty" ]]; then
  read -p "Use EMM Liberty image name '$emm_liberty'? [Y/n]: " -r
  # Prompt for name if no
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "Enter name for EMM Liberty [$DEFAULT_LIBERTY_EAR]: " -r
    DEFAULT_LIBERTY_EAR=${REPLY:-$DEFAULT_LIBERTY_EAR}
    emm_liberty=$(echo "$imagestreams" | grep -Pm 1 "$DEFAULT_LIBERTY_EAR" || true)
  fi
fi
# Create EMM Liberty ImageStream if not exists
if [[ -z "$emm_liberty" ]]; then
  emm_liberty="$DEFAULT_LIBERTY_EAR"
  oc create imagestream "$emm_liberty"
fi
echo "EMM Liberty image: $emm_liberty"

# 2.2 Create GitHub Source Secret
#cat << EOF > gh-source-secret.yaml
oc apply -f- << EOF
kind: Secret
apiVersion: v1
metadata:
  name: emm-mas8-build-ssh-key
  namespace: $manage_namespace
  annotations:
    build.openshift.io/source-secret-match-uri-1: 'ssh://github.com:InterPro-Solutions/*'
data:
  ssh-privatekey: >-
    LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCWTBWeTBZUi8za2lXU1JKU3J6Q294cmRZcnNiM080NzhkSXQxZUFIa1huQUFBQUtCWFNHZktWMGhuCnlnQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlkwVnkwWVIvM2tpV1NSSlNyekNveHJkWXJzYjNPNDc4ZEl0MWVBSGtYbkEKQUFBRUJXeS9qTnQ5dGR2Z3VQczlUeDB5WWdKT2tuN0FXRWEzbm5SYVFlYWVkb2xGalJYTFJoSC9lU0paSkVsS3ZNS2pHdAoxaXV4dmM3anZ4MGkzVjRBZVJlY0FBQUFHWE51YnprNU1EZ2dSMmwwU0hWaUlHUmxjR3h2ZVNCclpYa0JBZ01FCi0tLS0tRU5EIE9QRU5TU0ggUFJJVkFURSBLRVktLS0tLQo=
type: kubernetes.io/ssh-auth
EOF
source_secret=emm-mas8-build-ssh-key

# 2.3 Create EMM Liberty BuildConfig
# 2.3.1 Gather config info (coreidp secrets etc)
echo "Discovering secrets/configuration for EMM Liberty build..."
coreidp_binding=$(echo "$secrets" | grep -Pm 1 "\-coreidp-system-binding" || promptuser "coreidp-system-binding Secret")

# 2.3.2 Register/Discover OIDC client
oauth_url=$(oc get secret $coreidp_binding --template='{{.data.url|base64decode}}')
oauth_username=$(oc get secret $coreidp_binding -o jsonpath="{.data['oauth-admin-username']}" | base64 -d)
oauth_password=$(oc get secret $coreidp_binding -o jsonpath="{.data['oauth-admin-password']}" | base64 -d)
domain_name=$(echo $oauth_url | grep -Pom 1 "(?<=https://auth.)[^/]*" || promptuser "domain name")
apps_domain_name=$(echo $domain_name | grep -Pom 1 "apps[^/]*" || promptuser "apps domain name")
app_host="${app_host:=$emm_liberty-$manage_namespace.$apps_domain_name}"
app_url="https://$app_host"
# Check for existing OAUTH secret for this app name
oauth_secret=$(echo "$secrets" | grep -Pm 1 "credentials-oauth-$emm_liberty" || true)
# If not found, register OIDC and create secret
# TODO: Re-register based on app-host
if [[ -z $oauth_secret ]]; then
  echo "Registering OIDC client..."
  oauth_basic="${oauth_username}:${oauth_password}"
  # Modify client if it exists, otherwise create a new one
  oidc_status=$(curl -kw '%{http_code}' -o /dev/null -u "$oauth_basic" "$oauth_url/registration/$emm_liberty")
  if [[ "$oidc_status" == 200 ]]; then
    method="PUT"
    reg_url="$oauth_url/registration/$emm_liberty"
  else
    method="POST"
    reg_url="$oauth_url/registration"
  fi
  oidcres=$(
  #cat << EOF
  curl -kfX $method -u "$oauth_basic" -H 'Content-Type: application/json' "$reg_url" -d@- << EOF
{
"client_name": "ezmaxmobile",
"client_id": "$emm_liberty",
"token_endpoint_auth_method": "client_secret_basic",
"scope": "openid profile email general",
"redirect_uris": ["$app_url/ezmaxmobile", "$app_url/oidcclient/redirect/oidc"],
"grant_types": ["authorization_code","client_credentials","implicit","refresh_token","urn:ietf:params:oauth:grant-type:jwt-bearer"],
"response_types": ["code","token","id_token token"],
"application_type": "web",
"subject_type":"public",
"post_logout_redirect_uris": ["$app_url/ezmaxmobile/logout"],
"preauthorized_scope": "openid profile email general",
"introspect_tokens": true,
"trusted_uri_prefixes": ["$app_url/"]
}
EOF
  )
  # Extract client secret from OIDC response
  client_secret=$(echo "$oidcres" | grep -Piom 1 '"CLIENT_SECRET"\s*:\s*"[^,"]*' | sed -e 's/.*:\s*"//')
  # Create secret
#  cat << EOF > oidc-secret.yaml
  oc apply -f- << EOF
kind: Secret
apiVersion: v1
metadata:
  name: credentials-oauth-$emm_liberty
  namespace: $manage_namespace
data:
  password: $(echo -n "$client_secret" | base64 -w 0)
  username: $(echo -n "$emm_liberty" | base64 -w 0)
type: Opaque
EOF
  oauth_secret="credentials-oauth-$emm_liberty"
fi

# 2.3.3 Create BuildConfig
liberty_config=${emm_liberty}-build-config
# Use SSH or HTTPS repo URLs depending on GIT_HTTPS
# Since some clients may not allow SSH traffic
git_config() {
  if [[ -n "$GIT_HTTPS" ]]; then
    echo -e "  uri: 'https://github.com/InterPro-Solutions/emm-mas8-build.git'"
  else
    echo -e "  uri: 'git@github.com:InterPro-Solutions/emm-mas8-build.git'"
    echo -e "sourceSecret:\n  name: $source_secret"
  fi
}
apply_output=$(
#cat << EOF > emm-liberty-build-config.yaml
      # from:
      #   kind: ImageStreamTag
      #   name: 'ubi-wlp-manage:latest'
oc apply -f- << EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: $liberty_config
  namespace: $manage_namespace
spec:
  nodeSelector: null
  output:
    to:
      kind: ImageStreamTag
      name: "${emm_liberty}:v1"
  resources:
    limits:
      ephemeral-storage: 50Gi
    requests:
      ephemeral-storage: 10Gi
  strategy:
    type: Docker
    dockerStrategy:
      pullSecret:
        name: ibm-entitlement
      env:
        - name: METADATA_NAMESPACE
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.namespace
        - name: METADATA_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        - name: OAUTH_URL
          valueFrom:
            secretKeyRef:
              name: $coreidp_binding
              key: url
        - name: APP_ID
          value: $emm_liberty
      forcePull: true
  postCommit: {}
  source:
    type: Git
    git:
$(echo "$(git_config)" | sed 's/^/    /')
    images:
      - from:
          kind: ImageStreamTag
          name: "${emm_ear}:v1"
        paths:
          - sourcePath: /opt/IBM/SMP/ezmaxmobile/was-liberty-default/emm-server
            destinationDir: ./docker
          - sourcePath: /opt/IBM/SMP/maximo/additional-server-files
            destinationDir: ./docker
    contextDir: docker
  triggers:
    - type: ImageChange
      imageChange:
        from:
          kind: ImageStreamTag
          name: "${emm_ear}:v1"
  runPolicy: Serial
EOF
)
# 2.4 Build EMM Liberty
# We only need to rebuild if the liberty_config was changed AND the EAR config was not
# If the EAR config was changed, the liberty config will automatically rebuild
if [[ -z "$(echo "$apply_output" | grep -Pm 1 'unchanged|created' || true)" && -z "$ear_config_changed" ]]; then
  oc start-build $liberty_config --wait
fi

# 3. Deploy Application
# 3.1 Gather labels, secrets for deployment
echo "Discovering secrets/configuration for EMM deployment..."
deployments=$(oc get deployments --show-labels=true)
#instance_id=$(echo "$deployments" | grep -Piom 1 'instanceId=[^,]+' | sed -ne 's/instanceId=//ip' || promptuser "instanceId")
app_binding=$(echo "$secrets" | grep -Pm 1 "\-application-binding" || promptuser "-application-binding Secret")
cert_public=$(echo "$secrets" | grep -Pm 1 "\-cert-public-" || promptuser "cert-public Secret")
internal_manage_tls=$(echo "$secrets" | grep -Pm 1 "\-internal-manage-tls" || promptuser "internal_manage_tls Secret")
# Fetch MAS_LOGOUT_URL & MXE_DB_DRIVER by reading the environment of the -masdev-* serverBundle deployment
deployments=$(oc get deployments -l mas.ibm.com/appType=serverBundle -oname | sed -e 's/^.*\///') # remove leading '***/')
masdev_deploy=$(echo "$deployments" | grep -Pm 1 "\-$applicationid[\w-]+$" || promptuser "$applicationid-all Deployment")
deploy_env=$(oc set env deployment/$masdev_deploy --list)
mas_logout_url=$(echo "$deploy_env" | grep -Piom 1 '(?<=MAS_LOGOUT_URL=)\S+' || promptuser "MAS_LOGOUT_URL")
mxe_db_driver=$(echo "$deploy_env" | grep -Piom 1 '(?<=MXE_DB_DRIVER=)\S+' || promptuser "MXE_DB_DRIVER environment variable")
mxe_schemaowner=$(echo "$deploy_env" | grep -Piom 1 '(?<=MXE_DB_SCHEMAOWNER=)\S+' || promptuser "MXE_DB_SCHEMAOWNER environment variable")
encryption_secret=$(oc get deployments -o jsonpath='{..env[?(@.name == "MXE_SECURITY_CRYPTO_KEY")]..secretKeyRef.name}' | grep -Po '^\S+' || echo '')
# If no encryption secret, fallback to using bundle.properties
if [[ -z "$encryption_secret" ]]; then
  bundle_property=$(echo "$secrets" | grep -Pm 1 "\-bundleproperty" || echo '-bundleproperty Secret')
fi
# Get image repository from image stream itself
image_repo=$(oc get imagestream -o jsonpath="{.items[?(@.metadata.name == \"${emm_liberty}\")]..dockerImageRepository}" || promptuser "emm-liberty ImageStream dockerImageRepository")

# 3.1.1 (Optionally) Fetch offline PVC info
# '_' has special meaning; PVC is looked up from manage deployment
if [[ "$OFFLINE_PVC" == "_" ]]; then
  OFFLINE_PVC=$(oc get deployment ${masdev_deploy} -o jsonpath='{..volumes[?(@.persistentVolumeClaim)]..claimName}' | grep -Po '^\S+' || promptuser "Offline data PVC name")
fi
if [[ -n "$OFFLINE_PVC" ]]; then
  echo "Using offline PVC: $OFFLINE_PVC"
fi

# 3.2 Create deployment config
echo "Deploying EZMaxMobile..."
# https://docs.openshift.com/container-platform/4.8/openshift_images/triggering-updates-on-imagestream-changes.html
#cat << EOF > emm-liberty-deployment.yaml
oc apply -f- << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $emm_liberty
  namespace: $manage_namespace
  # Redeploy whenever the Liberty build completes
  annotations:
    image.openshift.io/triggers: >-
      [
        {
          "from": {
            "kind": "ImageStreamTag",
            "name": "${emm_liberty}:v1",
            "namespace": "$manage_namespace"
          },
          "fieldPath": "spec.template.spec.containers[?(@.name==\\"${emm_liberty}\\")].image",
          "paused": false
        }
      ]
spec:
  selector:
    matchLabels:
      app: $emm_liberty
  replicas: 1
  template:
    metadata:
      labels:
        app: $emm_liberty
        deploymentconfig: $emm_liberty
        mas.ibm.com/appType: serverBundle
        mas.ibm.com/instanceId: $instance_id
    spec:
      containers:
        - name: $emm_liberty
          # TODO: Customize resources/mirror from serverBundles
          command:
            - /bin/bash
            - '-c'
            - '--'
          args:
            - >-
              ./config/getkey.sh && source ./config/setenv.sh &&
              /opt/ibm/wlp/bin/server run defaultServer
          image: ${image_repo}:v1
          # When not using 'latest' tag, pullPolicy defaults to 'IfNotPresent', which won't auto-update
          imagePullPolicy: Always
          ports:
            - containerPort: 9080
              protocol: TCP
            - containerPort: 9443
              protocol: TCP
          env:
            - name: java_truststore
              value: /config/truststore/trust.p12
            - name: java_truststore_password
              valueFrom:
                secretKeyRef:
                  name: $truststorepasswd
                  key: truststorePassword
            - name: java_keystore
              value: /config/managefiles/key.p12
            - name: java_keystore_password
              valueFrom:
                secretKeyRef:
                  name: $truststorepasswd
                  key: truststorePassword
            - name: MAS_LOGOUT_URL
              value: $mas_logout_url
            - name: MXE_DB_URL
              valueFrom:
                secretKeyRef:
                  name: $app_binding
                  key: url
            - name: MXE_DB_USER
              valueFrom:
                secretKeyRef:
                  name: $app_binding
                  key: username
            - name: MXE_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: $app_binding
                  key: password
            - name: MXE_DB_SCHEMAOWNER
              value: $mxe_schemaowner
            - name: MXE_DB_DRIVER
              value: $mxe_db_driver
            - name: MXE_MAS_WORKSPACEID
              value: $applicationid
            - name: DB_SSL_ENABLED
              value: nossl
            - name: additional_serverconfig_hash
              value: nohash
            - name: TZ
              value: GMT
$([[ -n "$encryption_secret" ]] && cat << EOM
            - name: MXE_SECURITY_CRYPTOX_KEY
              valueFrom:
                secretKeyRef:
                  name: $encryption_secret
                  key: MXE_SECURITY_CRYPTOX_KEY
            - name: MXE_SECURITY_CRYPTO_KEY
              valueFrom:
                secretKeyRef:
                  name: $encryption_secret
                  key: MXE_SECURITY_CRYPTO_KEY
EOM
)
            - name: APP_URL
              value: $app_url
            - name: DOMAIN_NAME
              value: $domain_name
            - name: CORE_NAMESPACE
              value: $core_namespace
            - name: CLIENT_ID
              valueFrom:
                secretKeyRef:
                  name: $oauth_secret
                  key: username
            - name: CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: $oauth_secret
                  key: password
          volumeMounts:
            - name: manage-truststore
              readOnly: true
              mountPath: /config/truststore
            - name: manage-public-certs
              readOnly: true
              mountPath: /etc/ssl/certs/public-manage-tls
            - name: internal-manage-tls
              readOnly: true
              mountPath: /etc/ssl/certs/internal-manage-tls
$([[ -n "$bundle_property" ]] && cat << EOM
            - name: bundle-properties
              mountPath: /config/manage/properties
EOM
)
$([[ -n "$OFFLINE_PVC" ]] && cat << EOM
            - name: $OFFLINE_PVC
              mountPath: /data
EOM
)
      volumes:
        - name: manage-truststore
          configMap:
            name: $truststorecfg
            defaultMode: 420
        - name: manage-public-certs
          secret:
            secretName: $cert_public
            defaultMode: 420
        - name: internal-manage-tls
          secret:
            secretName: $internal_manage_tls
            defaultMode: 420
$([[ -n "$bundle_property" ]] && cat << EOM
        - name: bundle-properties
          secret:
            secretName: $bundle_property
            defaultMode: 420
EOM
)
$([[ -n "$OFFLINE_PVC" ]] && cat << EOM
        - name: $OFFLINE_PVC
          persistentVolumeClaim:
            claimName: $OFFLINE_PVC
EOM
)
EOF

# 3.3 Create service
#cat << EOF > emm-liberty-service.yaml
oc apply -f- << EOF
kind: Service
apiVersion: v1
metadata:
  name: $emm_liberty
  namespace: $manage_namespace
  labels:
    app: $emm_liberty
    mas.ibm.com/appType: serverBundle
    mas.ibm.com/instanceId: $instance_id
spec:
  ports:
    - name: 9080-tcp
      protocol: TCP
      port: 9080
    - name: 9443-tcp
      protocol: TCP
      port: 9443
  selector:
    app: $emm_liberty
    deploymentconfig: $emm_liberty
EOF

# 3.4 Get Route cert info
# Fetch Cert info from Manage's Route
routes=$(oc get route -l mas.ibm.com/applicationId=manage -oname | sed -e 's/^.*\///') # remove leading '***/')
masdev_route=$(echo "$routes" | \grep -Pm 1 "\-manage-$applicationid" || promptuser "manage-$applicationid Route")
route_cert=$(oc get route "$masdev_route" -o jsonpath='{..spec.tls.certificate}')
if [[ -z "$route_cert" ]]; then echo "Error: Could not find route certificate" && exit 1; fi
route_key=$(oc get route "$masdev_route" -o jsonpath='{..spec.tls.key}')
if [[ -z "$route_key" ]]; then echo "Error: Could not find route key" && exit 1; fi
route_dest_cert=$(oc get route "$masdev_route" -o jsonpath='{..spec.tls.destinationCACertificate}')
if [[ -z "$route_dest_cert" ]]; then echo "Error: Could not find route destination certificate" && exit 1; fi

# 3.5 Create Route
#cat << EOF > emm-liberty-route.yaml
oc apply -f- << EOF
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: $emm_liberty
  namespace: $manage_namespace
  labels:
    app: $emm_liberty
    mas.ibm.com/appType: serverBundle
    mas.ibm.com/instanceId: $instance_id
spec:
  host: $app_host
  to:
    kind: Service
    name: $emm_liberty
  port:
    targetPort: 9443-tcp
  tls:
    termination: reencrypt
    # Indent each certificate/key with sed
    certificate: |
$(echo "$route_cert" | sed 's/^/      /')
    key: |
$(echo "$route_key" | sed 's/^/      /')
    destinationCACertificate: |
$(echo "$route_dest_cert" | sed 's/^/      /')
  wildcardPolicy: None
EOF

oc rollout status deployment $emm_liberty --watch --timeout=60m
echo "Successfully deployed EZMaxmobile. Deployment name: $emm_liberty"
set +x
set +e
