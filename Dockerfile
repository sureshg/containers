# Containers are processes, born from tarballs, anchored to namespaces, controlled by cgroups
# https://twitter.com/jpetazzo/status/1047179436959956992

##### Build Image #####
ARG JDK_VERSION=17
ARG APP_USER=app
ARG APP_DIR="/app"

FROM eclipse-temurin:${JDK_VERSION}-focal AS jre-build
# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL maintainer="Suresh"
LABEL org.opencontainers.image.authors="Suresh"
LABEL org.opencontainers.image.title="Java JLinked Application"
LABEL org.opencontainers.image.description="Java JLinked Application"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.vendor="Suresh"
LABEL org.opencontainers.image.url="https://github.com/sureshg/nerdctl-xplatform"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG JDK_VERSION
ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "Building jlink custom image using Java ${JDK_VERSION} for ${TARGETPLATFORM} on ${BUILDPLATFORM}"

# Install objcopy for jlink
RUN set -eux; \
    apt -y update && \
    apt -y upgrade && \
    apt -y install --no-install-recommends binutils curl && \
    rm -rf /var/lib/apt/lists/* && \
    apt -y clean

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

# docker build -t repo/app:1.0 -f Dockerfile --build-arg APP_USER=app --no-cache --target openjdk .
# docker run -it --rm --entrypoint "/bin/bash" repo/app:1.0 -c "id; pwd"
# docker run -it --rm -p 8080:80 repo/app:1.0
FROM  debian:stable-slim AS openjdk

ARG APP_USER
ARG APP_DIR

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
# ENV TZ "PST8PDT"
COPY --from=jre-build /javaruntime $JAVA_HOME
COPY --from=jre-build ${APP_DIR} ${APP_DIR}

WORKDIR ${APP_DIR}
RUN useradd --home-dir ${APP_DIR} --create-home --uid 5000 --shell /bin/bash --user-group ${APP_USER}
USER ${APP_USER}

# USER nobody:nobody
# COPY --from=jre-build --chown=nobody:nobody /opt/java /opt/java

# Shell vs Exec - https://docs.docker.com/engine/reference/builder/#run
# ENTRYPOINT ["java"]
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

CMD ["jshell", "--show-version", "--enable-preview", "--startup", "JAVASE", "--feedback", "concise", "app.jsh"]


##### For Jlinking apps #####
FROM jre-build as jlink


##### Envoy proxy #####
FROM envoyproxy/envoy:v1.20-latest as envoy
# COPY --chown=app ...
COPY config/envoy.yaml /etc/envoy/envoy.yaml
CMD /usr/local/bin/envoy -c /etc/envoy/envoy.yaml -l trace --log-path /tmp/envoy_info.log