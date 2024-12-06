# syntax=docker/dockerfile:latest

# Containers are processes, born from tarballs, anchored to namespaces, controlled by cgroups (https://twitter.com/jpetazzo/status/1047179436959956992)
# https://docs.docker.com/develop/develop-images/dockerfile_best-practices/

# Global build args
ARG JDK_VERSION=24
ARG APP_USER=app
ARG APP_VERSION="4.0.0"
ARG APP_DIR="/app"
ARG APP_JAR="app.jar"
ARG SRC_DIR="/src"
ARG RUNTIME_IMAGE="/opt/java/openjdk"

# docker build --progress=plain -t sureshg/jdk-build:$(date +%s) -f Dockerfile --build-arg APP_USER=app --no-cache --target jdk-build .
FROM openjdk:${JDK_VERSION}-slim AS jdk-build

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL maintainer="Suresh" \
      org.opencontainers.image.authors="Suresh" \
      org.opencontainers.image.title="Containers" \
      org.opencontainers.image.description="🐳 Container/K8S/Compose playground!" \
      org.opencontainers.image.version=${APP_VERSION} \
      org.opencontainers.image.vendor="Suresh" \
      org.opencontainers.image.url="https://github.com/sureshg/containers" \
      org.opencontainers.image.source="https://github.com/sureshg/containers" \
      org.opencontainers.image.licenses="Apache-2.0"

# https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
# Platform of the build result. Eg linux/amd64, linux/arm/v7
# ARG TARGETPLATFORM=linux/aarch64
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
# Platform of the node performing the build.
ARG BUILDPLATFORM
ARG BUILDOS
ARG BUILDARCH
# Application specific build args
ARG JDK_VERSION
ARG RUNTIME_IMAGE
ARG APP_DIR
ARG APP_JAR
ARG SRC_DIR

# Set HTTP(s) Proxy
# ENV HTTP_PROXY="http://proxy.test.com:8080" \
#     HTTPS_PROXY="http://proxy.test.com:8080" \
#     NO_PROXY="*.test1.com,*.test2.com,127.0.0.1,localhost"

# Install objcopy for jlink
RUN <<EOT
    # set -o errexit -o nounset -o errtrace -o pipefail
    set -eux
    echo "Building jlink custom image using Java ${JDK_VERSION} for ${TARGETPLATFORM} on ${BUILDPLATFORM}"
    DEBIAN_FRONTEND=noninteractive
    apt -y update
    apt -y upgrade
    apt -y install \
           --no-install-recommends \
           binutils curl libtree \
           tzdata locales ca-certificates
    # wget procps vim unzip \
    # freetype fontconfig \
    # make gcc g++ libc++-dev \
    # openssl gnupg libssl-dev libcrypto++-dev libz.a \
    # software-properties-common

    rm -rf /var/lib/apt/lists/* /tmp/*
    apt -y clean
    mkdir -p ${APP_DIR}
EOT

# Run a command from another image instead of installing.
RUN --mount=from=busybox:latest,src=/bin/,dst=/bin \
    ls -ltrh /bin \
    && wget --help

# Leverage a bind mount to the current directory to avoid having to copy the source code into the container and build the jar.
# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/reference.md#run---mount
# --mount=type=bind,source=App.java,target=App.java,readonly
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
          --release ${JDK_VERSION} \
          src/*.java \
          -d .

    jar cfe ${APP_DIR}/${APP_JAR} App *.class
    cat /secrets/db || exit 0
EOT

WORKDIR ${APP_DIR}

RUN <<EOT
 set -eux
 echo "Getting JDK module dependencies..."
 jdeps -q \
       -R \
       --ignore-missing-deps \
       --print-module-deps \
       --multi-release=${JDK_VERSION} \
       *.jar > ${APP_DIR}/java.modules

 echo "Creating custom JDK runtime image in ${RUNTIME_IMAGE}..."
 INCUBATOR_MODULES=$(java --list-modules | grep -i incubator | sed 's/@.*//' | paste -sd "," - )
 # JAVA_TOOL_OPTIONS="-Djdk.lang.Process.launchMechanism=vfork"
 $JAVA_HOME/bin/jlink \
          --verbose \
          --module-path ${JAVA_HOME}/jmods \
          --add-modules="$(cat ${APP_DIR}/java.modules)" \
          --compress=zip-9 \
          --strip-debug \
          --strip-java-debug-attributes \
          --no-man-pages \
          --no-header-files \
          --save-opts "${APP_DIR}/jlink.opts" \
          --output ${RUNTIME_IMAGE}

  # List all modules included in the custom java runtime
  ${RUNTIME_IMAGE}/bin/java --list-modules

  echo "AOT training run for the app..."
  nohup ${RUNTIME_IMAGE}/bin/java \
        --show-version \
        --enable-preview \
        -XX:+UnlockExperimentalVMOptions \
        -XX:+UseCompactObjectHeaders \
        -XX:+UseZGC \
        -XX:AOTMode=record -XX:AOTConfiguration=${APP_DIR}/app.aotconf \
        -jar ${APP_JAR} & \
  sleep 1 && \
  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors http://localhost/test
  curl -fsSL http://localhost/shutdown || echo "AOT training run completed!"
  # Give some time to dump AOT conf
  sleep 1

  echo "Creating AOT archive..."
  ${RUNTIME_IMAGE}/bin/java \
          --show-version \
          --enable-preview \
          -XX:+UnlockExperimentalVMOptions \
          -XX:+UseCompactObjectHeaders \
          -XX:+UseZGC \
          -XX:AOTMode=create -XX:AOTConfiguration=${APP_DIR}/app.aotconf -XX:AOTCache=${APP_DIR}/app.aot \
          -jar ${APP_JAR}

  du -kcsh * | sort -rh
  du -kcsh ${RUNTIME_IMAGE}
EOT

# Create inline file
COPY <<-EOT ${APP_DIR}/info
 APP=${APP_DIR}/${APP_JAR}
 JDK_VERSION=${JDK_VERSION}
EOT

##### App Image #####
# docker build -t sureshg/openjdk-app:latest --no-cache  --pull --target openjdk .
# docker build -t sureshg/openjdk-app:latest -f Dockerfile --build-arg APP_USER=app --no-cache --secret id=db,src="$(pwd)/compose/config/postgres/pgadmin.env" --target openjdk .
# docker run -it --rm -p 8080:80 sureshg/openjdk-app:latest
FROM  gcr.io/distroless/java-base-debian12:latest AS openjdk
# FROM --platform=$BUILDPLATFORM ... AS openjdk
# FROM debian:stable-slim AS openjdk

ARG APP_DIR
ARG APP_JAR
ARG APP_VERSION
ARG RUNTIME_IMAGE
ARG SOURCE_DATE_EPOCH=0

# Declaration and usage of same ENV var should be in two ENV instructions.
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
ENV JAVA_HOME=${RUNTIME_IMAGE}
ENV PATH="${JAVA_HOME}/bin:${PATH}"
ENV APP_VERSION=${APP_VERSION}
#   LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8' \
#   TZ "PST8PDT"

WORKDIR ${APP_DIR}
# RUN <<EOT
#   echo "Creating a 'app' user/group"
#   useradd --home-dir ${APP_DIR} --create-home --uid 5000 --shell /bin/bash --user-group ${APP_USER}
# EOT
# USER ${APP_USER}

# COPY is same as 'ADD' but without the tar and remote url handling.
# These copy will run concurrently on BUILDKIT.
COPY --link --from=jdk-build --chmod=755 $JAVA_HOME $JAVA_HOME
COPY --link --from=jdk-build --chmod=755 ${APP_DIR} ${APP_DIR}
# COPY --link --from=openjdk:${JDK_VERSION}-slim $JAVA_HOME $JAVA_HOME

# USER nobody:nobody
# COPY --link --from=jdk-build --chown=nobody:nobody $JAVA_HOME $JAVA_HOME

# Shell vs Exec - https://docs.docker.com/engine/reference/builder/#run
# ENTRYPOINT ["java"]

# Both ARG and ENV (eg: APP_DIR_ENV) are not expanded in ENTRYPOINT or CMD
# https://stackoverflow.com/a/36412891/416868
CMD ["java", \
     "--show-version", \
     "--enable-preview", \
     "--enable-native-access=ALL-UNNAMED", \
     "-XX:+UnlockExperimentalVMOptions", \
     "-XX:+UseCompactObjectHeaders", \
     "-XX:+UseZGC", \
     "-XX:+PrintCommandLineFlags", \
     "-XX:+ErrorFileToStderr", \
     "-XX:AOTCache=app.aot", \
     "-XX:MaxRAMPercentage=0.8", \
     "-Djava.security.egd=file:/dev/./urandom", \
     "-jar", "app.jar", \
     "arg1"]

EXPOSE 80/tcp

# HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
#            CMD java --version || exit 1

# Container to print assembly generated by JVM C1/C2 compilers
# docker build -t sureshg/openjdk-hsdis:latest --no-cache  --pull --target openjdk-hsdis .
# docker run -it --rm -p 8080:80 sureshg/openjdk-hsdis:latest
FROM openjdk:${JDK_VERSION}-slim AS openjdk-hsdis

ARG JDK_VERSION
ARG TARGETARCH
ARG APP_DIR

RUN <<EOT
  echo "Building Java ${JDK_VERSION} Hotspot Disassembler image for ${TARGETARCH}"
  DEBIAN_FRONTEND=noninteractive
  apt -y update
  apt -y upgrade
  apt -y install --no-install-recommends curl
  rm -rf /var/lib/apt/lists/* /tmp/*
  apt -y clean
  mkdir -p ${APP_DIR}
EOT

# Install HotSpot disassembler plugin
# https://github.com/openjdk/jdk/blob/master/src/utils/hsdis/README.md
# https://chriswhocodes.com/hsdis/

RUN <<EOT
  set -eux
  # ARCH="$(dpkg --print-architecture)"; \
  case "${TARGETARCH}" in
         amd64|x86_64)
           BINARY_URL='https://builds.shipilev.net/hsdis/hsdis-amd64.so'
           ;;
         aarch64|arm64)
           BINARY_URL='https://builds.shipilev.net/hsdis/hsdis-aarch64.so'
           ;;
         *)
           echo "Unsupported arch: ${TARGETARCH}"
           exit 1
           ;;
  esac;
  HSDIS_FILE="${BINARY_URL##*/}"
  echo "Downloading ${BINARY_URL} ..."
  curl --progress-bar --request GET -L --fail --url "${BINARY_URL}" --output "${HSDIS_FILE}"
  # echo "${SHA256_SUM} $HSDIS_FILE" | sha256sum -c -
  mv $HSDIS_FILE $JAVA_HOME/lib/server
EOT

ENTRYPOINT ["java", "-XX:+UnlockDiagnosticVMOptions", "-XX:+PrintAssembly"]

##### GraalVM community dev build #####
FROM debian:unstable-slim AS graalvm-community-dev

ARG JDK_VERSION
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

RUN <<EOT
  set -eux
  echo "Installing GraalVM Community Dev (JDK ${JDK_VERSION}) for ${TARGETPLATFORM}..."
  DEBIAN_FRONTEND=noninteractive
  apt -y update
  apt -y upgrade
  apt -y install \
         --no-install-recommends \
         binutils curl \
         tzdata locales fontconfig ca-certificates \
         gcc zlib1g-dev
  rm -rf /var/lib/apt/lists/* /tmp/*
  apt -y clean
EOT

ENV JAVA_HOME /opt/java/openjdk
ENV PATH $JAVA_HOME/bin:$PATH
# Default to UTF-8 file.encoding
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

RUN <<EOT
  set -eux
  case "${TARGETARCH}" in
    amd64|x86_64)
      ARCH='amd64'
      ;;
    aarch64|arm64)
      ARCH='aarch64'
      ;;
    *)
      echo "Unsupported arch: ${TARGETARCH}"
      exit 1
      ;;
  esac;

  # Download the GraalVM Dev
  GRAALVM_BASE_URL="https://github.com/graalvm/graalvm-ce-dev-builds/releases"
  GRAALVM_RELEASE=$(curl -Ls -o /dev/null -w %{url_effective} "${GRAALVM_BASE_URL}/latest")
  GRAALVM_TAG="${GRAALVM_RELEASE##*/}"
  GRAALVM_PKG="graalvm-community-java${JDK_VERSION}-${TARGETOS}-${ARCH}-dev.tar.gz"
  DOWNLOAD_URL="${GRAALVM_BASE_URL}/download/${GRAALVM_TAG}/${GRAALVM_PKG}"

  echo "Downloading $DOWNLOAD_URL ..."
  curl --progress-bar --fail --location --retry 3 --url "$DOWNLOAD_URL" --output graalvm-community-dev.tgz

  mkdir -p "$JAVA_HOME"
  tar --extract \
	  --file graalvm-community-dev.tgz \
	  --directory "$JAVA_HOME" \
	  --strip-components 1 \
	  --no-same-owner
  rm -f graalvm-community-dev.tgz ${JAVA_HOME}/src.zip

  java --version
  native-image --help
EOT

ENTRYPOINT ["native-image"]
CMD ["--version"]


##### GraalVM NativeImage Build #####
FROM ghcr.io/graalvm/graalvm-community:latest AS graalvm-build
# FROM graalvm-community-dev AS graalvm-build

WORKDIR /app
COPY src /app

RUN <<EOT
set -eux
# export TOOLCHAIN_DIR="${PWD}/x86_64-linux-musl-native"
# export CC="${TOOLCHAIN_DIR}/bin/gcc"
# export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"
# native-image --static --libc=musl -m jdk.httpserver -o jwebserver.static
# upx --lzma --best jwebserver.static -o jwebserver.static.upx
GRAAL_JDK_VERSION=$(java -XshowSettings:properties -version 2>&1 | grep "java.specification.version =" | awk '{print $3}')
javac --enable-preview \
      --release ${GRAAL_JDK_VERSION} \
      -encoding UTF-8 \
      App.java

native-image \
    --enable-preview \
    --enable-native-access=ALL-UNNAMED \
    --no-fallback \
    --enable-https \
    --install-exit-handlers \
    --static-nolibc \
    -O3 \
    -R:MaxHeapSize=32m \
    -march=compatibility \
    -H:+UnlockExperimentalVMOptions \
    -H:+CompactingOldGen \
    -H:+ReportExceptionStackTraces \
    -J--add-modules -JALL-SYSTEM \
    -o httpserver App
EOT

##### Static App Image #####
# docker build -t sureshg/graalvm-static --no-cache  --pull  --target graalvm-static .
# docker run -it --rm -p 8080:80 sureshg/graalvm-static
FROM gcr.io/distroless/base-debian12 AS graalvm-static
# FROM cgr.dev/chainguard/graalvm-native:latest AS graalvm-static
# RUN ldconfig -p

COPY --from=graalvm-build /app/httpserver /
ENTRYPOINT ["./httpserver"]
EXPOSE 80/tcp


##### Jshell image #####
# docker build -t sureshg/jshell --no-cache --target jshell .
# docker run -it --rm -e TZ="UTC" sureshg/jshell
FROM openjdk:${JDK_VERSION}-slim AS jshell

ENV TZ "PST8PDT"
RUN cat <<EOT > app.jsh
System.out.println(TimeZone.getDefault().getID());
/exit
EOT

CMD ["jshell", "--show-version", "--enable-preview", "--startup", "JAVASE", "--feedback", "concise", "app.jsh"]


##### Slimmer JDK using JLink #####
# docker build -t sureshg/jdk-slim --no-cache --target jdk-slim .
# docker run -it --rm sureshg/jdk-slim
FROM jdk-build AS jdk-slim

ENV JDK_SLIM /opt/java/jdk-slim

RUN <<EOT
  set -eux

  # Example to change the locale
  sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
  locale-gen

  echo "Creating slimmer JDK image..."
  $JAVA_HOME/bin/jlink \
        --verbose \
        --add-modules "$(java --list-modules | sed -e 's/@[0-9].*$/,/' | tr -d \\n)" \
        --no-man-pages \
        --no-header-files \
        --strip-debug \
        --output $JDK_SLIM
  du -ah $JDK_SLIM
  ${JDK_SLIM}/bin/java --version
EOT

ENV TZ "PST8PDT"
ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'


#### C static binary
FROM cgr.dev/chainguard/gcc-glibc AS gcc-glibc-build

COPY <<EOF /app.c
#include <stdio.h>
int main() { printf("App Static Image!"); }
EOF

RUN cc -static /app.c -o /app


#### Chainguard static image
# docker build -t sureshg/cgr-static --target cgr-static .
# docker run -it --rm sureshg/cgr-static
FROM cgr.dev/chainguard/static:latest AS cgr-static
# FROM cgr.dev/chainguard/glibc-dynamic AS cgr-dynamic

COPY --from=gcc-glibc-build /app /app
CMD ["/app"]


#### NetCat Webserver
# docker build -t sureshg/netcat-server --target netcat .
# docker run -p 8080:80 -e PORT=80 -it --rm sureshg/netcat-server
FROM alpine AS netcat
ENTRYPOINT while :; do nc -k -l -p $PORT -e sh -c 'echo -e "HTTP/1.1 200 OK\n\nHello, world $(date)\n---- OS ----\n$(cat /etc/os-release)\n---- Env ----\n$(env)"'; done


# docker build -t sureshg/tools --target tools .
# docker run -it --rm sureshg/tools
FROM nicolaka/netshoot:latest AS tools

ENTRYPOINT ["sh", "-c"]
CMD ["echo Q | openssl s_client --connect suresh.dev:443"]


#### Run Python script as part of build
# docker build --progress=plain -t sureshg/py-script --target python .
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

### SSH Server container with sysstat (sar)
# docker build -t sureshg/ssh-server --target ssh-server .
# docker run -it --rm -p 2222:22 sureshg/ssh-server
# ssh test@localhost -p 2222
FROM debian:stable-slim AS ssh-server

ARG USER=test
ARG PASS=test
ENV HOME /home/$USER

COPY <<EOF /entrypoint.sh
#!/bin/bash
set -e
echo "[Entrypoint] OpenSSH Server, args: "\$@""
echo "Running as $(whoami) user from $(pwd) with permissions: $(sudo -l)"

echo "Collecting system activity report (sar) for 3 seconds..."
for i in \`seq 1 3\` ; do /usr/lib/sysstat/debian-sa1 1 1 ; sleep 1 ; done

echo "Starting the ssh Server..."
ssh-keygen -A
exec "\$@"
EOF

RUN <<EOT
    apt -y update
    apt -y install \
       --no-install-recommends \
       openssh-server sudo sysstat

    useradd -rm -d ${HOME}  -s /bin/bash -g root -G sudo -u 1000 ${USER}
    echo -n "${USER}:${PASS}" | chpasswd
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER}
    chmod 0440 /etc/sudoers.d/${USER}

    # Entrypoint script should be executable
    chmod +x /entrypoint.sh
    # Start SSH service
    service ssh start

    # Enable SAR
    sed -i 's/ENABLED="false"/ENABLED="true"/g' /etc/default/sysstat
    service sysstat restart
EOT

ENTRYPOINT [ "/entrypoint.sh" ]
# HEALTHCHECK --interval=5m --timeout=3s CMD /healthcheck.sh
EXPOSE 22
CMD [ "/usr/sbin/sshd", "-D" ]