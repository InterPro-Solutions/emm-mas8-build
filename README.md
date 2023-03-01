# EMM on OpenShift Liberty Installation Guide
Originally by Fan Kong
## Build ear image
1. Create EMM ear image
```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  # your name here
  name: myemm-ear
  namespace: mas-inst8809-manage
```
2. Create EMM ear buildconfig
```yaml
kind: BuildConfig
apiVersion: build.openshift.io/v1
metadata:
  # your name here
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
  successfulBuildsHistoryLimit: 5
  failedBuildsHistoryLimit: 5
  strategy:
    type: Docker
    dockerStrategy:
      pullSecret:
        name: ibm-entitlement
      forcePull: true
  postCommit: {}
  source:
    type: Dockerfile
    dockerfile: >
      FROM cp.icr.io/cp/manage/manageadmin:8.4.5 AS ADMIN


      WORKDIR /opt/IBM/SMP/maximo


      RUN mkdir -p /opt/IBM/SMP/maximo/additional-server-files




      COPY --chown=maximoinstall:0 tmp_build_files .



      RUN rm -rf customizationCredentials && rm trust.p12 && rm
      truststorePassword


      # Remove translation files that will not be used.

      WORKDIR /opt/IBM/SMP/maximo

      RUN rm -f translation_files.zip lang/MaximoLangPkgXliff_Ar.zip
      lang/MaximoLangPkgXliff_Cs.zip lang/MaximoLangPkgXliff_Da.zip
      lang/MaximoLangPkgXliff_De.zip lang/MaximoLangPkgXliff_Es.zip
      lang/MaximoLangPkgXliff_Fi.zip lang/MaximoLangPkgXliff_Fr.zip
      lang/MaximoLangPkgXliff_He.zip lang/MaximoLangPkgXliff_Hr.zip
      lang/MaximoLangPkgXliff_Hu.zip lang/MaximoLangPkgXliff_It.zip
      lang/MaximoLangPkgXliff_Ja.zip lang/MaximoLangPkgXliff_Ko.zip
      lang/MaximoLangPkgXliff_Nl.zip lang/MaximoLangPkgXliff_No.zip
      lang/MaximoLangPkgXliff_Pl.zip lang/MaximoLangPkgXliff_Pt_BR.zip
      lang/MaximoLangPkgXliff_Ru.zip lang/MaximoLangPkgXliff_Sk.zip
      lang/MaximoLangPkgXliff_Sl.zip lang/MaximoLangPkgXliff_Sv.zip
      lang/MaximoLangPkgXliff_Tr.zip lang/MaximoLangPkgXliff_Zh_CN.zip
      lang/MaximoLangPkgXliff_Zh_TW.zip

      RUN rm -rf tools/maximo/ar tools/maximo/cs tools/maximo/da tools/maximo/de
      tools/maximo/es tools/maximo/fi tools/maximo/fr tools/maximo/he
      tools/maximo/hr tools/maximo/hu tools/maximo/it tools/maximo/ja
      tools/maximo/ko tools/maximo/nl tools/maximo/no tools/maximo/pl
      tools/maximo/pt tools/maximo/ru tools/maximo/sk tools/maximo/sl
      tools/maximo/sv tools/maximo/tr tools/maximo/zh tools/maximo/zht


      WORKDIR /opt/IBM/SMP/maximo/tools/maximo


      RUN \
        mkdir -p /opt/IBM/SMP/maximo/applications/maximo/businessobjects/classes/psdi/app/signature/apps &&\
        mkdir -p /opt/IBM/SMP/maximo/tools/maximo/log &&\
        ./pkginstall.sh && ./updatedblitepreprocessor.sh -disconnected &&\
        find /opt/IBM/SMP/maximo/applications -type d -exec chmod 777 {} + &&\
        chmod ugo+rw -R /opt/IBM/SMP/maximo/applications &&\
        find /opt/IBM/SMP/maximo/tools/maximo -type d -exec chmod 777 {} + &&\
        chmod ugo+rw -R /opt/IBM/SMP/maximo/tools/maximo &&\
        chmod 777 /opt/IBM/SMP/maximo/tools/maximo/log &&\
        find /opt/IBM/SMP/maximo/tools/maximo/en -type f -name postupdatedb.sh -exec chmod -v 777 {} +

      WORKDIR /opt/IBM/SMP/maximo/deployment/was-liberty-default

      # TODO: Use Maximo ear from existing pod/image
      RUN ./maximo-all.sh && ./buildmaximoui-war.sh && ./buildmaximo-xwar.sh &&
      ./maximo-cron.sh


      ENV MXE_MASDEPLOYED=1

      ENV MXE_USESQLSERVERSEQUENCE=1

      ENV LC_ALL=en_US.UTF-8

      ENV LANGUAGE_BASE=en

      ENV LANGUAGE_ADD=

      WORKDIR /opt/IBM/SMP/maximo/tools/maximo

      WORKDIR /opt/IBM/SMP
      
      # TODO: Pull EMM files from GitHub with authentication

      RUN \
        wget -c http://124.222.21.115:3000/ezmaxmobile.zip &&\
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
3. Run build
## Build liberty image
1. Create Liberty ImageStream
```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: myemm-liberty # choose name here
  namespace: mas-inst8809-manage
```
2. Create liberty build config
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myemm-liberty-build-config
  namespace: mas-inst8809-manage
spec:
  nodeSelector: null
  output:
    to:
      kind: ImageStreamTag
      name: 'myemm-liberty:v1'
  resources:
    limits:
      ephemeral-storage: 50Gi
    requests:
      ephemeral-storage: 10Gi
  successfulBuildsHistoryLimit: 5
  failedBuildsHistoryLimit: 5
  strategy:
    type: Docker
    dockerStrategy:
      pullSecret:
        name: ibm-entitlement
      forcePull: true
  postCommit: {}
  source:
    type: Dockerfile
    dockerfile: >
      FROM cp.icr.io/cp/manage/ubi-wlp-manage:2.2.13 AS LIBERTY


      #ARG VERBOSE=true


      COPY --chown=1001:0 emm-server/apps/  /config/dropins

      RUN rm /opt/ibm/wlp/usr/servers/defaultServer/server.env && mkdir
      /managefiles/additional-server-files


      COPY --chown=1001:0 additional-server-files/ 
      /managefiles/additional-server-files/


      ENV MXE_MASDEPLOYED=1

      ENV MXE_USESQLSERVERSEQUENCE=1

      ENV LC_ALL=en_US.UTF-8

      USER 1001


      # This is overridden by container cmd when deployed in OpenShift

      # CMD /opt/ibm/wlp/bin/server run defaultServer

      CMD sleep 123456789
    images:
      - from:
          kind: ImageStreamTag
          name: 'myemm-ear:v1'
        paths:
          - sourcePath: >-
              /opt/IBM/SMP/ezmaxmobile/was-liberty-default/emm-server
            destinationDir: .
          - sourcePath: /opt/IBM/SMP/maximo/additional-server-files
            destinationDir: .
  triggers:
    - type: ImageChange
      imageChange:
        lastTriggeredImageID: >-
          image-registry.openshift-image-registry.svc:5000/mas-inst8809-manage/myemm-ear@sha256:b047eb1cf0b5689cdcb724775ce255edd70401b7e510e0e712217a091fd6d1d3
        from:
          kind: ImageStreamTag
          name: 'myemm-ear:v1'
  runPolicy: Serial
```
3. Build Liberty image
## Deploy Image
1. Need to add two labels when deploying image:
```
mas.ibm.com/appType=serverBundle 
mas.ibm.com/instanceId=inst8809
```
2. Copy server.xml, etc files to pod TODO
3. Register OIDC
```bash
curl -XPOST --insecure -H 'Authorization: Basic ZHlRR2E5SlJ6SWNLU095bGRuWTVOMENsT3FLMUhDWVA6eFI2VTBVOXYyTVlTMnB0RHdXcWFuWTA3cXI4MVBFVjA=' -H 'Content-Type: application/json' https://coreidp.mas-inst8809-core.svc/oidc/endpoint/MaximoAppSuite/registration -d '
{"client_id": "ezmaxmobile","client_name": "ezmaxmobile","token_endpoint_auth_method":"client_secret_basic","scope":"openid profile email general","grant_types":["authorization_code","client_credentials","implicit","refresh_token","urn:ietf:params:oauth:grant-type:jwt-bearer"],"response_types":["code","token","id_token token"],"application_type":"web","subject_type":"public","post_logout_redirect_uris":["https://emm-liberty-mas-inst8809-manage.apps.sno8809.ezmaxcloud.com/ezmaxmobile/logout"],"preauthorized_scope":"openid profile email general","introspect_tokens":true,"trusted_uri_prefixes":["https://emm-liberty-mas-inst8809-manage.apps.sno8809.ezmaxcloud.com/"],"redirect_uris":["https://emm-liberty-mas-inst8809-manage.apps.sno8809.ezmaxcloud.com/ezmaxmobile/callback"]
}'
```

