## Build application
FROM registry.access.redhat.com/ubi9/openjdk-21:latest as builder
WORKDIR /build
USER root

# Download and cache dependencies beforehand
COPY pom.xml /build/connector/
RUN cd /build/connector && mvn dependency:go-offline -B

COPY . /build/connector
RUN cd /build/connector && rm -r src/main/liberty && mvn install

## Final image
FROM --platform=linux/amd64 icr.io/appcafe/websphere-liberty:25.0.0.9-kernel-java21-openj9-ubi-minimal
ARG VERBOSE=true
ENV LICENSE=accept

USER 0
RUN microdnf install -y procps-ng && microdnf clean all

# Import DB2 CA cert into the JVM truststore (for JDBC SSL) and Liberty's
# default keystore (for WSX509TrustManager). The cert is the DB2U CA at
# /secrets/db2ssl/ca.crt on the Maximo cluster.
COPY container/certs/db2-ca.crt /tmp/db2-ca.crt
RUN keytool -importcert -trustcacerts -alias db2-ca \
    -file /tmp/db2-ca.crt \
    -keystore /opt/java/openjdk/lib/security/cacerts \
    -storepass changeit -noprompt && \
    rm /tmp/db2-ca.crt

USER 1001

COPY --chown=1001:0 container/import-certs.sh /opt/import-certs.sh
RUN chmod ug+x /opt/import-certs.sh
COPY --chown=1001:0 container/jvm.options /config/

# Add Liberty server configuration including all necessary features
COPY --chown=1001:0 container/server.xml /config/
RUN features.sh

COPY --from=builder --chown=1001:0 /build/connector/target/ticket-template.war /config/apps/

USER 1001

RUN configure.sh