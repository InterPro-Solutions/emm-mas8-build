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

# 0. Check CLI exists, we are logged in, and have permissions
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
core_namespace=$(echo "$namespaces" | grep -Pm 1 "\-core$" || promptuser "Core namespace")
manage_namespace=$(echo "$namespaces" | grep -Pm 1 "\-manage$" || promptuser "Manage namespace")
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
  read -p "Use EMM EAR image name '$emm_ear'? [Y/n]: " -rn 1
  echo
  # Prompt for name if no
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "Enter OPTIONAL name for EMM EAR [$DEFAULT_EMM_EAR]: " -r
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
# 1.2.3 Create BuildConfig
ear_config=${emm_ear}-build-config
deploy_package="ezmaxmobile.zip"
deploy_token='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJidWNrZXQiOiJ0ZXN0LWVtbS1kZXBsb3ltZW50cyIsImtleVJlZyI6Ii4qZXptYXhtb2JpbGVbXi9dKiQifQ.-Npu7D9vSUxZkTEbmDrNgdBswmR8E3U6K-PN95yyJ9o'
echo "EMM deploy package: $deploy_package"
# TODO: Prompt for deploy token
#cat << EOF > test.yaml
oc apply -f- << EOF
kind: BuildConfig
apiVersion: build.openshift.io/v1
metadata:
  name: $ear_config
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
        # This token will be different for each client
        - name: DEPLOY_TOKEN
          value: >-
            $deploy_token
      forcePull: true
  postCommit: {}
  source:
    type: Dockerfile
    dockerfile: >
      FROM cp.icr.io/cp/manage/manageadmin:8.4.5 AS ADMIN


      ENV MXE_MASDEPLOYED=1

      ENV MXE_USESQLSERVERSEQUENCE=1

      ENV LC_ALL=en_US.UTF-8

      ENV LANGUAGE_BASE=en

      ENV LANGUAGE_ADD=

      COPY --chown=maximoinstall:0 additional-server-files/
      /opt/IBM/SMP/maximo/additional-server-files

      WORKDIR /opt/IBM/SMP/maximo/tools/maximo

      COPY --chown=maximoinstall:0 maximo-all-server/
      /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment/maximo-all/maximo-all-server

      WORKDIR /opt/IBM/SMP

      # Get download URL from deploy gateway, then download and build EMM ear

      RUN \\
        EMM_URL=\$(wget -q -O - --header="Authorization: Bearer \$DEPLOY_TOKEN" "\$DEPLOY_GATEWAY_URL") &&\\
        wget -O ezmaxmobile.zip -c "\$EMM_URL" &&\\
        unzip ezmaxmobile.zip &&\\
        cd ezmaxmobile &&\\
        chmod u+x ./buildemmear.sh &&\\
        ./buildemmear.sh &&\\
        ls -al default &&\\
        ls -al was-liberty-default &&\\
        ls -al was-liberty-default/emm-server/apps &&\\
        ls -al /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment/maximo-all/maximo-all-server &&\\
        ls -al /opt/IBM/SMP/maximo/additional-server-files

      WORKDIR /opt/IBM/SMP/maximo/tools/maximo

      #CMD sleep 123456789

    images:
      - from:
          kind: ImageStreamTag
          name: "${masdev_image}:latest"
        paths:
          - sourcePath: >-
              /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment/maximo-all/maximo-all-server
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
  triggers:
    - type: ConfigChange
EOF
# 1.3 Build EMM EAR
#oc start-build $ear_config --wait

# 2. Create EMM Liberty image
# 2.1 Get EMM Liberty image name
emm_liberty=$(echo "$imagestreams" | grep -Pm 1 "$DEFAULT_LIBERTY_EAR" || true)
# Matching EAR found; prompt to use it
if [[ -n "$emm_liberty" ]]; then
  read -p "Use EMM Liberty image name '$emm_liberty'? [Y/n]: " -rn 1
  echo
  # Prompt for name if no
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    read -p "Enter OPTIONAL name for EMM Liberty [$DEFAULT_LIBERTY_EAR]: " -r
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
#cat << EOF > test.yaml
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
# TODO: Register OIDC here
# 2.3.2 Create BuildConfig
liberty_config=${emm_liberty}-build-config
#cat << EOF > test.yaml
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
        - name: OAUTH_USERNAME
          valueFrom:
            secretKeyRef:
              name: $coreidp_binding
              key: oauth-admin-username
        - name: OAUTH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: $coreidp_binding
              key: oauth-admin-password
      forcePull: true
  postCommit: {}
  source:
    type: Git
    git:
      uri: 'git@github.com:InterPro-Solutions/emm-mas8-build.git'
    sourceSecret:
      name: $source_secret
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
# 2.4 Build EMM Liberty
#oc start-build $liberty_config --wait # TODO: DEBUG

# 3. Deploy Application
# 3.1 Gather labels, secrets for deployment
echo "Discovering secrets/configuration for EMM deployment..."
deployments=$(oc get deployments --show-labels=true)
#instance_id=$(echo "$deployments" | grep -Piom 1 'instanceId=[^,]+' | sed -ne 's/instanceId=//ip' || promptuser "instanceId")
app_binding=$(echo "$secrets" | grep -Pm 1 "\-workspace-(application-)?binding" || promptuser "-workspace-binding Secret")
cert_public=$(echo "$secrets" | grep -Pm 1 "\-cert-public-" || promptuser "cert-public Secret")
internal_manage_tls=$(echo "$secrets" | grep -Pm 1 "\-internal-manage-tls" || promptuser "internal_manage_tls Secret")
# Fetch MAS_LOGOUT_URL & MXE_DB_DRIVER by reading the environment of the -masdev-* serverBundle deployment
deployments=$(oc get deployments -l mas.ibm.com/appType=serverBundle -oname | sed -e 's/^.*\///') # remove leading '***/')
masdev_deploy=$(echo "$deployments" | grep -Pm 1 "\-masdev-[\w-]+$" || promptuser "$applicationid-all Deployment")
deploy_env=$(oc set env deployment/$masdev_deploy --list)
mas_logout_url=$(echo "$deploy_env" | grep -Piom 1 '(?<=MAS_LOGOUT_URL=)\S+' || promptuser "MAS_LOGOUT_URL")
mxe_db_driver=$(echo "$deploy_env" | grep -Piom 1 '(?<=MXE_DB_DRIVER=)\S+' || promptuser "MXE_DB_DRIVER environment variable")

# 3.2 Create deployment config
echo "Deploying EZMaxMobile..."
#cat << EOF > test.yaml
oc apply -f- << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $emm_liberty
  namespace: $manage_namespace
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
          command:
            - /bin/bash
            - '-c'
            - '--'
          args:
            - >-
              ./config/getkey.sh && source ./config/setenv.sh &&
              /opt/ibm/wlp/bin/server run defaultServer
          # TODO: Get from imagestream itself
          image: >-
            image-registry.openshift-image-registry.svc:5000/${manage_namespace}/${emm_liberty}:v1
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
              value: dbo
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
            - name: MXE_SECURITY_CRYPTOX_KEY
              valueFrom:
                secretKeyRef:
                  name: $applicationid-manage-encryptionsecret
                  key: MXE_SECURITY_CRYPTOX_KEY
            - name: MXE_SECURITY_CRYPTO_KEY
              valueFrom:
                secretKeyRef:
                  name: $applicationid-manage-encryptionsecret
                  key: MXE_SECURITY_CRYPTO_KEY
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
EOF

# 3.3 Create service
#cat << EOF > test.yaml
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
masdev_route=$(echo "$routes" | grep -Pm 1 "\-manage-$applicationid" || promptuser "manage-$applicationid Route")
route_cert=$(oc get route "$masdev_route" -o custom-columns=:.spec.tls.certificate --no-headers=true)
if [[ "$route_cert" == "<none>" ]]; then echo "Error: Could not find route certificate" && exit 1; fi
route_key=$(oc get route "$masdev_route" -o custom-columns=:.spec.tls.key --no-headers=true)
if [[ "$route_key" == "<none>" ]]; then echo "Error: Could not find route key" && exit 1; fi
route_dest_cert=$(oc get route "$masdev_route" -o custom-columns=:.spec.tls.destinationCACertificate --no-headers=true)
if [[ "$route_dest_cert" == "<none>" ]]; then echo "Error: Could not find route destination certificate" && exit 1; fi

# 3.5 Create Route
#cat << EOF > test.yaml
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
oc rollout status deployment $emm_liberty --watch --timeout=20m
echo "Successfully deployed EZMaxmobile. Deployment name: $emm_liberty"
set +x
set +e
