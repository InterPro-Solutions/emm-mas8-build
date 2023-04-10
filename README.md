# EMM on OpenShift Liberty Installation Guide
This is loosely based off of Fan's original installation guide, but in Markdown, with inline YAML files.

For the most part, the entire process is done in `Administrator` mode.

For each step, you will have to scroll down, reading the entire YAML
and replacing commented fields to match your environment.
## Build ear image
1. Create an ImageStream for the EMM ear file. (Builds -> ImageStreams)

The EAR file has to be built separately, as the image used for actual deployment doesn't
have the tools necessary to build it.
```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  # your name here
  name: myemm-ear
  namespace: mas-inst8809-manage
```
2. Create EMM ear buildconfig (Builds -> BuildConfigs)

Note the references to the ImageStream just created, as well as the DEPLOY_TOKEN.

This token and DEPLOY_GATEWAY_URL grant access to the actual EMM build files for a client.
```yaml
kind: BuildConfig
apiVersion: build.openshift.io/v1
metadata:
  # Name of ImageStream + -build-config
  name: myemm-ear-build-config
  namespace: mas-inst8809-manage
spec:
  nodeSelector: null
  output:
    to:
      # Same name as ImageStream
      kind: ImageStreamTag
      name: 'myemm-ear:v1'
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
            https://1qbx7rd5w9.execute-api.us-east-1.amazonaws.com/default/ezmax-deploy?key=ezmaxmobile.zip
        # This token will be different for each client
        - name: DEPLOY_TOKEN
          value: >-
            eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJidWNrZXQiOiJ0ZXN0LWVtbS1kZXBsb3ltZW50cyIsImtleVJlZyI6Ii4qZXptYXhtb2JpbGVbXi9dKiQifQ.-Npu7D9vSUxZkTEbmDrNgdBswmR8E3U6K-PN95yyJ9o
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

      RUN \
        EMM_URL=$(wget -q -O - --header="Authorization: Bearer $DEPLOY_TOKEN" "$DEPLOY_GATEWAY_URL") &&\
        wget -O ezmaxmobile.zip -c "$EMM_URL" &&\
        unzip ezmaxmobile.zip &&\
        cd ezmaxmobile &&\
        chmod u+x ./buildemmear.sh &&\
        ./buildemmear.sh &&\
        ls -al default &&\
        ls -al was-liberty-default &&\
        ls -al was-liberty-default/emm-server/apps &&\
        ls -al /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment/maximo-all/maximo-all-server &&\
        ls -al /opt/IBM/SMP/maximo/additional-server-files

      WORKDIR /opt/IBM/SMP/maximo/tools/maximo

      #CMD sleep 123456789

    images:
      - from:
          kind: ImageStreamTag
          # Instance name + -masdev-admin:latest
          name: 'inst8809-masdev-admin:latest'
        paths:
          - sourcePath: >-
              /opt/IBM/SMP/maximo/deployment/was-liberty-default/deployment/maximo-all/maximo-all-server
            destinationDir: .
          - sourcePath: /opt/IBM/SMP/maximo/additional-server-files
            destinationDir: .
    secrets:
      - secret:
          name: inst8809-masdev-manage-truststorepasswd
        destinationDir: tmp_build_files
    configMaps:
      - configMap:
          name: inst8809-masdev-truststore-cfg
        destinationDir: tmp_build_files
  runPolicy: Serial
```
3. Actions -> Start build
## Build liberty image
1. Create Liberty ImageStream (Builds -> ImageStreams)

The name used here is important for the rest of the process.
Since the OIDC client registration is registered with a URL based on this name,
it should match the deployed app name later.
```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: myemm-liberty # choose name here
  namespace: mas-inst8809-manage
```
2. Create a source secret for GitHub, to allow pulling the Dockerfile: (Workloads -> Secrets)
```yaml
kind: Secret
apiVersion: v1
metadata:
  name: emm-mas8-build-ssh-key
  # Manage namespace
  namespace: mas-inst8809-manage
  annotations:
    build.openshift.io/source-secret-match-uri-1: 'ssh://github.com:InterPro-Solutions/*'
data:
  ssh-privatekey: >-
    LS0tLS1CRUdJTiBPUEVOU1NIIFBSSVZBVEUgS0VZLS0tLS0KYjNCbGJuTnphQzFyWlhrdGRqRUFBQUFBQkc1dmJtVUFBQUFFYm05dVpRQUFBQUFBQUFBQkFBQUFNd0FBQUF0emMyZ3RaVwpReU5UVXhPUUFBQUNCWTBWeTBZUi8za2lXU1JKU3J6Q294cmRZcnNiM080NzhkSXQxZUFIa1huQUFBQUtCWFNHZktWMGhuCnlnQUFBQXR6YzJndFpXUXlOVFV4T1FBQUFDQlkwVnkwWVIvM2tpV1NSSlNyekNveHJkWXJzYjNPNDc4ZEl0MWVBSGtYbkEKQUFBRUJXeS9qTnQ5dGR2Z3VQczlUeDB5WWdKT2tuN0FXRWEzbm5SYVFlYWVkb2xGalJYTFJoSC9lU0paSkVsS3ZNS2pHdAoxaXV4dmM3anZ4MGkzVjRBZVJlY0FBQUFHWE51YnprNU1EZ2dSMmwwU0hWaUlHUmxjR3h2ZVNCclpYa0JBZ01FCi0tLS0tRU5EIE9QRU5TU0ggUFJJVkFURSBLRVktLS0tLQo=
type: kubernetes.io/ssh-auth
```
3. Create liberty build config (Builds -> BuildConfigs)
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  # Same as image stream + -build-config
  name: myemm-liberty-build-config
  namespace: mas-inst8809-manage
spec:
  nodeSelector: null
  output:
    to:
      kind: ImageStreamTag
      # Name of ImageStream
      name: 'myemm-liberty:v1'
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
        # These 3 are just the instance name + -coreidp-system-binding for the secret name
        - name: OAUTH_URL
          valueFrom:
            secretKeyRef:
              name: inst8809-coreidp-system-binding
              key: url
        - name: OAUTH_USERNAME
          valueFrom:
            secretKeyRef:
              name: inst8809-coreidp-system-binding
              key: oauth-admin-username
        - name: OAUTH_PASSWORD
          valueFrom:
            secretKeyRef:
              name: inst8809-coreidp-system-binding
              key: oauth-admin-password
      forcePull: true
  postCommit: {}
  source:
    type: Git
    git:
      uri: 'git@github.com:InterPro-Solutions/emm-mas8-build.git'
    # source secret created earlier
    sourceSecret:
      name: emm-mas8-build-ssh-key
    images:
      - from:
          kind: ImageStreamTag
          # Name of EAR ImageStream from earlier
          name: 'myemm-ear:v1'
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
          # Name of EAR ImageStream from earlier
          name: 'myemm-ear:v1'
  runPolicy: Serial
```
4. Actions -> Start Build
## Deploy Image
Finally, we need to create a deployment, service, and route for the app.

1. Go to Workloads -> Deployments and create a new deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  # Must match Liberty build config name!
  name: myemm-liberty
  namespace: mas-inst8809-manage
spec:
  selector:
    matchLabels:
      # App name
      app: myemm-liberty
  replicas: 1
  template:
    metadata:
      labels:
        # App name
        app: myemm-liberty
        deploymentconfig: myemm-liberty
        mas.ibm.com/appType: serverBundle
        # Instance name
        mas.ibm.com/instanceId: inst8809
    spec:
      containers:
        - name: myemm-liberty
          command:
            - /bin/bash
            - '-c'
            - '--'
          args:
            - >-
              ./config/getkey.sh && source ./config/setenv.sh &&
              /opt/ibm/wlp/bin/server run defaultServer
          # Registry/<manage namespace>/<app name>:latest
          image: >-
            image-registry.openshift-image-registry.svc:5000/mas-inst8809-manage/myemm-liberty:latest
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
                  # Instance name + -masdev-manage-truststorepasswd
                  name: inst8809-masdev-manage-truststorepasswd
                  key: truststorePassword
            - name: java_keystore
              value: /config/managefiles/key.p12
            - name: java_keystore_password
              valueFrom:
                secretKeyRef:
                  # Instance name + -masdev-manage-truststorepasswd
                  name: inst8809-masdev-manage-truststorepasswd
                  key: truststorePassword
            - name: MAS_LOGOUT_URL
              # http://masdev.home.<instance name>.apps.sno8809.<domain>/logout
              value: 'https://masdev.home.inst8809.apps.sno8809.ezmaxcloud.com/logout'
            - name: MXE_DB_URL
              valueFrom:
                secretKeyRef:
                  # Look in 'secrets' for workspace application binding
                  name: inst8809-masdev-jdbccfg-workspace-application-binding
                  key: url
            - name: MXE_DB_USER
              valueFrom:
                secretKeyRef:
                  name: inst8809-masdev-jdbccfg-workspace-application-binding
                  key: username
            - name: MXE_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: inst8809-masdev-jdbccfg-workspace-application-binding
                  key: password
            - name: MXE_DB_SCHEMAOWNER
              value: dbo
            - name: MXE_DB_DRIVER
              value: com.microsoft.sqlserver.jdbc.SQLServerDriver
            - name: MXE_MAS_WORKSPACEID
              value: masdev
            - name: DB_SSL_ENABLED
              value: nossl
            - name: additional_serverconfig_hash
              value: nohash
            - name: TZ
              value: GMT
            - name: MXE_SECURITY_CRYPTOX_KEY
              valueFrom:
                secretKeyRef:
                  name: masdev-manage-encryptionsecret
                  key: MXE_SECURITY_CRYPTOX_KEY
            - name: MXE_SECURITY_CRYPTO_KEY
              valueFrom:
                secretKeyRef:
                  name: masdev-manage-encryptionsecret
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
          # Each volume seems to just be <instance name> + the rest of the name
          configMap:
            name: inst8809-masdev-truststore-cfg
            defaultMode: 420
        - name: manage-public-certs
          secret:
            secretName: inst8809-masdev-cert-public-81
            defaultMode: 420
        - name: internal-manage-tls
          secret:
            secretName: inst8809-internal-manage-tls
            defaultMode: 420
```
2. Next, the service: (Networking -> Services)
```yaml
kind: Service
apiVersion: v1
metadata:
  # App name
  name: myemm-liberty
  namespace: mas-inst8809-manage
  labels:
    # App name
    app: myemm-liberty
    mas.ibm.com/appType: serverBundle
    # Instance name
    mas.ibm.com/instanceId: inst8809
spec:
  ports:
    - name: 9080-tcp
      protocol: TCP
      port: 9080
    - name: 9443-tcp
      protocol: TCP
      port: 9443
  selector:
    # App name
    app: myemm-liberty
    deploymentconfig: myemm-liberty
```
3. Finally, the route: (Networking -> Routes -> Create Route -> Edit YAML)
```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  # App name
  name: myemm-liberty
  namespace: mas-inst8809-manage
  labels:
    # App name
    app: myemm-liberty
    mas.ibm.com/appType: serverBundle
    # Instance name
    mas.ibm.com/instanceId: inst8809
spec:
  to:
    kind: Service
    name: myemm-liberty
  port:
    targetPort: 9443-tcp
  tls:
    termination: reencrypt
  # TODO: certificate, key, destinationCACertificate
  wildcardPolicy: None
```

