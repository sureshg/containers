##### Build Image #####
ARG JDK_VERSION=17

FROM eclipse-temurin:${JDK_VERSION}-focal AS jre-build
LABEL org.opencontainers.image.authors="Suresh"

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
# FROM gcr.io/distroless/java:base (Unfortunately no ARM64 support)
# https://github.com/GoogleContainerTools/distroless/blob/main/cosign.pub
# cosign verify -key cosign.pub gcr.io/distroless/java:base
FROM  debian:stable-slim AS openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
# ENV TZ "PST8PDT"
COPY --from=jre-build /javaruntime $JAVA_HOME
COPY --from=jre-build /app /app

# USER nobody:nobody
# COPY --from=jre-build --chown=nobody:nobody /opt/java /opt/java

WORKDIR /app
CMD ["java", "--show-version", "-jar", "app.jar"]
EXPOSE 80/tcp

##### GraalVM NativeImage Build #####
FROM ghcr.io/graalvm/graalvm-ce:latest as graalvm
RUN gu install native-image \
    && native-image --version

WORKDIR /app
COPY App.java /app/App.java
# --enable-all-security-services
# --report-unsupported-elements-at-runtime
# --initialize-at-build-time=kotlinx,kotlin,org.slf4j
RUN javac App.java \
    && native-image \
    --static \
    --no-fallback \
    --allow-incomplete-classpath \
    --install-exit-handlers \
    -H:+ReportExceptionStackTraces \
    App \
    httpserver

##### Static App Image #####
FROM scratch as graalvm-static
# gcr.io/distroless/(static|base)
COPY --from=graalvm /app/httpserver /
CMD ["./httpserver"]
EXPOSE 80/tcp


##### Jshell image #####
# nerdctl build -t jshell --no-cache --target jshell .
# nerdctl run -it --rm -e TZ="UTC" jshell
FROM openjdk:18-alpine as jshell

ENV TZ "PST8PDT"
RUN echo "System.out.println(TimeZone.getDefault().getID());" >> app.jsh
RUN echo "/exit" >> app.jsh

CMD ["jshell", "--enable-preview", "--startup", "JAVASE", "app.jsh"]


##### For Jlinking apps #####
FROM jre-build as jlink


##### Envoy proxy #####
FROM envoyproxy/envoy:v1.20-latest as envoy
COPY config/envoy.yaml /etc/envoy/envoy.yaml
CMD /usr/local/bin/envoy -c /etc/envoy/envoy.yaml -l trace --log-path /tmp/envoy_info.log