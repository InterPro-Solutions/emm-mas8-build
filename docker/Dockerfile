FROM cp.icr.io/cp/manage/ubi-wlp-manage:2.2.13 AS LIBERTY


#ARG VERBOSE=true

COPY --chown=1001:0 emm-server/apps/  /config/dropins
COPY --chmod=775 --chown=1001:0 test.sh /config/
COPY --chmod=775 --chown=1001:0 setenv.sh /config/
COPY --chown=1001:0 server.xml /config/
COPY --chown=1001:0 jvm.options /config/

RUN rm /opt/ibm/wlp/usr/servers/defaultServer/server.env && mkdir /managefiles/additional-server-files

WORKDIR /config/

RUN pwd && ls -la && id && ./test.sh

# Move EAR file
RUN mv /config/dropins/ezmaxmobile.ear /config/apps/emm.ear

COPY --chown=1001:0 additional-server-files/ /managefiles/additional-server-files/

WORKDIR /


ENV MXE_MASDEPLOYED=1

ENV MXE_USESQLSERVERSEQUENCE=1

ENV LC_ALL=en_US.UTF-8

USER 1001


# This is overridden by container cmd when deployed in OpenShift

# CMD /opt/ibm/wlp/bin/server run defaultServer

CMD sleep 123456789
