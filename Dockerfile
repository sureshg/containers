##### Build Image #####
ARG JDK_VERSION=17

FROM eclipse-temurin:${JDK_VERSION}-focal AS jre-build
MAINTAINER Suresh

# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG JDK_VERSION
ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "Building jlink custom image using Java ${JDK_VERSION} for ${TARGETPLATFORM} on ${BUILDPLATFORM}"

# Install objcopy for jlink
RUN set -eux; \
    apt update \
    && apt -y upgrade \
    && DEBIAN_FRONTEND=noninteractive apt install -y binutils;

# Copy the application
RUN mkdir /app
WORKDIR /app
COPY App.java /app/App.java

# Create the application jar
RUN javac *.java \
    && jar cfe app.jar App *.class

# Get all modules for the app
RUN jdeps \
      -q \
      -R \
      --ignore-missing-deps \
      --print-module-deps \
      --multi-release=${JDK_VERSION} \
      *.jar \
      > java.modules

# Create custom runtime
ENV DIST /javaruntime
RUN JAVA_TOOL_OPTIONS="-Djdk.lang.Process.launchMechanism=vfork" \
    $JAVA_HOME/bin/jlink \
         --add-modules="jdk.crypto.ec,$(cat java.modules)" \
         --strip-debug \
         --no-man-pages \
         --no-header-files \
         --compress=2 \
         --output $DIST

# Create default CDS archive and verify it
RUN $DIST/bin/java -Xshare:dump \
    # check if it worked, this will fail if it can't map the archive
    && $DIST/bin/java -Xshare:on --version \
    # list all modules included in the custom java runtime
    && $DIST/bin/java --list-modules \
    && du -sh $DIST


##### App Image #####
FROM debian:stable-slim AS openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
COPY --from=jre-build /javaruntime $JAVA_HOME
COPY --from=jre-build /app /app

# USER nobody:nobody
# COPY --from=jre-build --chown=nobody:nobody /opt/java /opt/java

WORKDIR /app
CMD ["java", "--show-version", "-jar", "app.jar"]
EXPOSE 80

FROM ghcr.io/graalvm/graalvm-ce:latest as graalvm
RUN gu install native-image \
    && native-image --version

WORKDIR /app
COPY App.java /app/App.java
RUN javac App.java \
    && native-image \
    --static \
    --no-fallback \
    --allow-incomplete-classpath \
    --install-exit-handlers \
    -H:+ReportExceptionStackTraces \
    App \
    httpserver

FROM scratch as graalvm-static
#gcr.io/distroless/(static|base)
COPY --from=graalvm /app/httpserver /
CMD ["./httpserver"]
EXPOSE 80/tcp

FROM jre-build as jlink


FROM envoyproxy/envoy:v1.20-latest as envoy
COPY config/envoy.yaml /etc/envoy/envoy.yaml
CMD /usr/local/bin/envoy -c /etc/envoy/envoy.yaml -l trace --log-path /tmp/envoy_info.log