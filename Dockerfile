# syntax=docker/dockerfile:1

# Containers are processes, born from tarballs, anchored to namespaces, controlled by cgroups (https://twitter.com/jpetazzo/status/1047179436959956992)
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/

# Global build args
ARG JDK_VERSION=20
ARG APP_USER=app
ARG APP_DIR="/app"
ARG APP_JAR="app.jar"
ARG SRC_DIR="/src"

# DOCKER_BUILDKIT=1 docker build --progress=plain -t sureshg/jre-build:$(date +%s) -f Dockerfile --build-arg APP_USER=app --no-cache --target jre-build .
FROM openjdk:${JDK_VERSION}-slim AS jre-build

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL maintainer="Suresh" \
      org.opencontainers.image.authors="Suresh" \
      org.opencontainers.image.title="Containers" \
      org.opencontainers.image.description="🐳 Container/K8S/Compose playground!" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.vendor="Suresh" \
      org.opencontainers.image.url="https://github.com/sureshg/containers" \
      org.opencontainers.image.source="https://github.com/sureshg/containers" \
      org.opencontainers.image.licenses="Apache-2.0"

# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
ARG JDK_VERSION
ARG TARGETARCH
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG APP_DIR
ARG APP_JAR
ARG SRC_DIR
# ARG TARGETPLATFORM=linux/aarch64

# Set HTTP(s) Proxy
# ENV HTTP_PROXY="http://proxy.test.com:8080" \
#     HTTPS_PROXY="http://proxy.test.com:8080" \
#     NO_PROXY="*.test1.com,*.test2.com,127.0.0.1,localhost"

# Install objcopy for jlink
RUN <<EOT
    set -eux
    echo "Building jlink custom image using Java ${JDK_VERSION} for ${TARGETPLATFORM} on ${BUILDPLATFORM}"
    DEBIAN_FRONTEND=noninteractive
    apt -y update
    apt -y upgrade
    apt -y install --no-install-recommends binutils curl tzdata ca-certificates
    # apt -y install freetype fontconfig
    rm -rf /var/lib/apt/lists/*
    apt -y clean
    mkdir -p ${APP_DIR}
EOT

# Instead of copying, mount the application and build the jar
# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md#build-mounts-run---mount
WORKDIR ${SRC_DIR}
RUN --mount=type=bind,target=.,rw \
    --mount=type=secret,id=db,target=/secrets/db \
    --mount=type=cache,target=/root/.m2 \
    --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt <<EOT
    set -eux
    echo "Building the application jar..."
    javac --enable-preview \
          -verbose \
          -g \
          -parameters \
          -Xlint:all \
          -Xdoclint:none \
          -Werror \
          --release ${JDK_VERSION} \
          src/*.java \
          -d .

    jar cfe ${APP_DIR}/${APP_JAR} App *.class
    cat /secrets/db || exit 0
EOT

WORKDIR ${APP_DIR}
ENV DIST /opt/java/openjdk

RUN <<EOT
 set -eux
 echo "Getting JDK module dependencies..."
 jdeps -q \
       -R \
       --ignore-missing-deps \
       --print-module-deps \
       --multi-release=${JDK_VERSION} \
       *.jar > java.modules

 echo "Creating custom JDK runtime image..."
 JAVA_TOOL_OPTIONS="-Djdk.lang.Process.launchMechanism=vfork"
 $JAVA_HOME/bin/jlink \
          --add-modules="jdk.crypto.ec,jdk.incubator.concurrent,$(cat java.modules)" \
          --strip-debug \
          --no-man-pages \
          --no-header-files \
          --compress=2 \
          --output $DIST

  # Create default CDS archive for jlinked runtime and verify it
  # https://malloc.se/blog/zgc-jdk15#class-data-sharing
  $DIST/bin/java -XX:+UseZGC -Xshare:dump

  # Check if it worked, this will fail if it can't map the archive (lib/server/[classes.jsa,classes_nocoops.jsa])
  $DIST/bin/java -XX:+UseZGC -Xshare:on --version

  # List all modules included in the custom java runtime
  $DIST/bin/java --list-modules

  echo "Creating dynamic CDS archive by running the app..."
  nohup $DIST/bin/java \
        --show-version \
        --enable-preview \
        -XX:+UseZGC \
        -XX:+AutoCreateSharedArchive \
        -XX:SharedArchiveFile=${APP_DIR}/app.jsa \
        -jar ${APP_JAR} & \
  sleep 1 && \
  curl -fsSL http://localhost/test && \
  curl -fsSL http://localhost/shutdown || echo "Shutdown completed!"
  # Give some time to generate the CDS archive
  sleep 1

  du -kcsh * | sort -rh
  du -kcsh $DIST
EOT

# Create inline file
COPY <<-EOT ${APP_DIR}/info
 APP=${APP_DIR}/${APP_JAR}
 JDK_VERSION=${JDK_VERSION}
EOT

##### App Image #####
# DOCKER_BUILDKIT=1 docker build -t sureshg/app:latest --target openjdk .
# DOCKER_BUILDKIT=1 docker build -t sureshg/app:latest -f Dockerfile --build-arg APP_USER=app --no-cache --secret id=db,src="$(pwd)/env/pgadmin.env" --target openjdk .
# docker run -it --rm -p 8080:80 sureshg/app:latest
# docker run -it --rm --entrypoint "/bin/bash" --pull always sureshg/app:latest -c "id; pwd"
FROM --platform=$BUILDPLATFORM gcr.io/distroless/java-base-debian11:nonroot as openjdk
# FROM gcr.io/distroless/java-base:latest AS openjdk
# FROM debian:stable-slim AS openjdk

ARG APP_DIR

# Declaration and usage of same ENV var should be in two ENV instructions.
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"
#   LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' \
#   TZ "PST8PDT"

WORKDIR ${APP_DIR}
# RUN <<EOT
#   echo "Creating a 'app' user/group"
#   useradd --home-dir ${APP_DIR} --create-home --uid 5000 --shell /bin/bash --user-group ${APP_USER}
# EOT
# USER ${APP_USER}

# These copy will run concurrently on BUILDKIT.
COPY --link --from=jre-build --chmod=755 $JAVA_HOME $JAVA_HOME
COPY --link --from=jre-build --chmod=755 ${APP_DIR} ${APP_DIR}
# COPY --link --from=openjdk:${JDK_VERSION}-slim $JAVA_HOME $JAVA_HOME

# USER nobody:nobody
# COPY --link --from=jre-build --chown=nobody:nobody $JAVA_HOME $JAVA_HOME

# Shell vs Exec - https://docs.docker.com/engine/reference/builder/#run
# ENTRYPOINT ["java"]

# Both ARG and ENV are not expanded in ENTRYPOINT or CMD
# https://stackoverflow.com/a/36412891/416868
CMD ["java", \
     "--show-version", \
     "--enable-preview", \
     "--enable-native-access=ALL-UNNAMED", \
     # "-Xlog:cds", \
     "-XX:+UseZGC", \
     "-XX:+PrintCommandLineFlags", \
     "-XX:+AutoCreateSharedArchive", \
     "-XX:SharedArchiveFile=app.jsa", \
     "-XX:MaxRAMPercentage=0.8", \
     "-Djava.security.egd=file:/dev/./urandom", \
     "-jar", "app.jar"]

EXPOSE 80/tcp

# HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
#            CMD java --version || exit 1

# Container to print assembly generated by JVM C1/C2 compilers
FROM openjdk:${JDK_VERSION}-slim as hsdis

ARG JDK_VERSION
ARG TARGETARCH

RUN echo "Building Java ${JDK_VERSION} Hotspot Disassembler image for ${TARGETARCH}" && \
    apt -y update && \
    apt -y install --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/* && \
    apt -y clean

RUN set -eux; \
    # ARCH="$(dpkg --print-architecture)"; \
    case "${TARGETARCH}" in \
       amd64|x86_64) \
         SHA256_SUM='2ebd13ca0dd0a3f20c49b99c12b72e376b6c371975f734403048ddf3d7b51507'; \
         BINARY_URL='https://chriswhocodes.com/hsdis/hsdis-amd64.so'; \
         ;; \
       aarch64|arm64) \
         SHA256_SUM='c531ae2f6002987b1d7ee5713a76e51bb54dc3da7b00c8b1214f021abda4dffb'; \
         BINARY_URL='https://chriswhocodes.com/hsdis/hsdis-aarch64.so'; \
         ;; \
       *) \
         echo "Unsupported arch: ${TARGETARCH}"; \
         exit 1; \
         ;; \
    esac; \
	  wget -O /tmp/openjdk.tar.gz ${BINARY_URL}; \
	  echo "${ESUM} */tmp/openjdk.tar.gz" | sha256sum -c -; \
	  mkdir -p /opt/java/openjdk; \
	  tar --extract \
	      --file /tmp/openjdk.tar.gz \
	      --directory /opt/java/openjdk \
	      --strip-components 1 \
	      --no-same-owner \
	  ; \
    rm -rf /tmp/openjdk.tar.gz;

ENTRYPOINT ["java", "--show-version", "-jar", "app.jar"]


##### GraalVM NativeImage Build #####
FROM ghcr.io/graalvm/native-image:latest as graalvm

WORKDIR /app
COPY src /app

RUN javac App.java && \
    native-image \
    --static \
    --no-fallback \
    --native-image-info \
    --link-at-build-time \
    --install-exit-handlers \
    -H:+ReportExceptionStackTraces \
    -J--add-modules -JALL-SYSTEM \
    App \
    httpserver

##### Static App Image #####
# DOCKER_BUILDKIT=1 docker build -t sureshg/graalvm-static --no-cache --target graalvm-static .
# docker run -it --rm -p 8080:80 sureshg/graalvm-static
# dive sureshg/graalvm-static
FROM scratch as graalvm-static
# gcr.io/distroless/(static|base)
COPY --from=graalvm /app/httpserver /
CMD ["./httpserver"]
EXPOSE 80/tcp


##### Jshell image #####
# DOCKER_BUILDKIT=1 docker build -t sureshg/jshell --no-cache --target jshell .
# docker run -it --rm -e TZ="UTC" sureshg/jshell
FROM azul/zulu-openjdk-alpine:19 as jshell

ENV TZ "PST8PDT"
RUN cat <<EOT > app.jsh
System.out.println(TimeZone.getDefault().getID());
/exit
EOT

CMD ["jshell", "--show-version", "--enable-preview", "--startup", "JAVASE", "--feedback", "concise", "app.jsh"]


##### For Jlinking apps #####
FROM jre-build as jlink


##### Envoy proxy #####
# DOCKER_BUILDKIT=1 docker build -t sureshg/envoy-dev --target envoy .
# docker run -it --rm sureshg/envoy-dev
FROM envoyproxy/envoy-dev:latest as envoy
# COPY --chown=app ...
COPY config/envoy.yaml /etc/envoy/envoy.yaml
CMD /usr/local/bin/envoy -c /etc/envoy/envoy.yaml -l trace --log-path /tmp/envoy_info.log


#### NetCat Webserver
# DOCKER_BUILDKIT=1 docker build -t sureshg/netcat-server --target netcat .
# docker run -p 8080:80 -e PORT=80 -it --rm sureshg/netcat-server
FROM alpine as netcat
ENTRYPOINT while :; do nc -k -l -p $PORT -e sh -c 'echo -e "HTTP/1.1 200 OK\n\nHello, world $(date)\n---- OS ----\n$(cat /etc/os-release)\n---- Env ----\n$(env)"'; done


# DOCKER_BUILDKIT=1 docker build -t sureshg/tools --target tools .
# docker run -it --rm sureshg/tools
FROM nicolaka/netshoot:latest as tools

ENTRYPOINT ["sh", "-c"]
CMD ["echo Q | openssl s_client --connect suresh.dev:443"]


#### Run Python script as part of build
# DOCKER_BUILDKIT=1 docker build --progress=plain -t sureshg/py-script --target python .
# docker run -it --rm sureshg/py-script
FROM python:slim AS python

ARG APP_DIR
ARG APP_JAR

RUN <<EOT
#!/usr/bin/env python
import time
print("Hello ${APP_DIR}/${APP_JAR}")
time.sleep(1)
EOT