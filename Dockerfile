# Containers are processes, born from tarballs, anchored to namespaces, controlled by cgroups
# https://twitter.com/jpetazzo/status/1047179436959956992

##### Build Image #####
ARG JDK_VERSION=17
ARG APP_USER=app
ARG APP_DIR="/app"
ARG SRC_DIR="/src"

# DOCKER_BUILDKIT=1 docker build -t repo/jre-build:$(date +%s) -f Dockerfile --build-arg APP_USER=app --no-cache --target jre-build .
FROM eclipse-temurin:${JDK_VERSION}-focal AS jre-build
# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL maintainer="Suresh"
LABEL org.opencontainers.image.authors="Suresh"
LABEL org.opencontainers.image.title="Containers"
LABEL org.opencontainers.image.description="🐳 Container/K8S/Compose playground using k3s/nerdctl/Rancher Desktop!"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.vendor="Suresh"
LABEL org.opencontainers.image.url="https://github.com/sureshg/containers"
LABEL org.opencontainers.image.source="https://github.com/sureshg/containers"
LABEL org.opencontainers.image.licenses="Apache-2.0"

# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG JDK_VERSION
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG APP_DIR
ARG SRC_DIR

RUN echo "Building jlink custom image using Java ${JDK_VERSION} for ${TARGETPLATFORM} on ${BUILDPLATFORM}"

# Install objcopy for jlink
RUN set -eux; \
    apt -y update && \
    apt -y upgrade && \
    apt -y install --no-install-recommends binutils curl && \
    rm -rf /var/lib/apt/lists/* && \
    apt -y clean && \
    mkdir -p ${APP_DIR}

# Instead of copying, mount the application and build the jar
# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md#build-mounts-run---mount
WORKDIR ${SRC_DIR}
RUN --mount=type=bind,target=.,rw \
    --mount=type=cache,target=/root/.m2 \
    --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    javac -verbose -g -parameters --enable-preview -Werror --release ${JDK_VERSION} *.java -d . && \
    jar cfe ${APP_DIR}/app.jar App *.class

WORKDIR ${APP_DIR}
# Create the application jar
#
# COPY App.java .
# RUN javac *.java \
#    && jar cfe app.jar App *.class

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

# du -kcsh *

##### App Image #####
# FROM gcr.io/distroless/java:base (Unfortunately no ARM64 support)
# https://github.com/GoogleContainerTools/distroless/blob/main/cosign.pub
# cosign verify -key cosign.pub gcr.io/distroless/java:base

# DOCKER_BUILDKIT=1 docker build -t repo/app:1.0 -f Dockerfile --build-arg APP_USER=app --no-cache --target openjdk .
# docker run -it --rm --entrypoint "/bin/bash" repo/app:1.0 -c "id; pwd"
# docker run -it --rm -p 8080:80 repo/app:1.0
# dive repo/app:1.0
FROM debian:stable-slim AS openjdk

ARG APP_USER
ARG APP_DIR

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH "${JAVA_HOME}/bin:${PATH}"
# ENV TZ "PST8PDT"

# These copy will run concurrently on BUILDKIT.
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