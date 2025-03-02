# Container/Kubernetes Playground!

[![GitHub Workflow Status][gha_badge]][gha_url]
[![Docker Linter][lint_img]][lint_url]
[![OpenJDK App][openjdk_app_img]][container-images]
[![Native Image App][nativeimage_app_img]][container-images]

Container/K8S/Compose playground using [dockerd(moby)][7]/[nerdctl][2]/[Rancher Desktop][3].

### Run Container Images

```bash
# Build OpenJDK jLinked image with AOT cache
$ docker build -t sureshg/openjdk-app:latest --pull --target openjdk .
$ docker run -it --rm -p 8080:80 sureshg/openjdk-app:latest
$ dive sureshg/openjdk-app:latest

# GraalVM native image (For debug, --progress=plain --pull --no-cache)
$ docker build -t sureshg/graalvm-static --pull --target graalvm-static .
$ docker run -it --rm -p 8080:80 sureshg/graalvm-static
$ curl http://localhost:8080
$ dive sureshg/graalvm-static
```

<details>
<summary>Misc Images</summary>

```bash
# GraalVM Dev image
$ docker build --progress=plain --tag sureshg/graalvm-community-dev --pull --target graalvm-community-dev .
$ docker run -it --rm -p 8080:80 sureshg/graalvm-community-dev  --version

# OpenJDK HSDIS image to print assembly
# --mount type=volume,source=new-volume,destination=/var/lib/data \
$ docker build -t sureshg/openjdk-hsdis:latest --target openjdk-hsdis .
$ docker run \
        -it \
        --rm \
        --env APP_NAME=HSDIS \
        --workdir /app \
        --publish 8080:80 \
        --mount type=bind,source=$(pwd),destination=/app,readonly \
        sureshg/openjdk-hsdis:latest src/App.java   
        
# JShell Image  
$ docker build -t sureshg/jshell --no-cache --target jshell .
$ docker run -it --rm -e TZ="UTC" sureshg/jshell 

# JDK Slim Image
$ docker build -t sureshg/jdk-slim --no-cache --target jdk-slim .
$ docker run -it --rm sureshg/jdk-slim   

# Chainguard static image
$ docker build -t sureshg/cgr-static --target cgr-static .
$ docker run -it --rm sureshg/cgr-static 

# NetCat Webserver
$ docker build -t sureshg/netcat-server --target netcat .
$ docker run -p 8080:80 -e PORT=80 -it --rm sureshg/netcat-server 

# Netshoot Image
$ docker build -t sureshg/tools --target tools .
$ docker run -it --rm sureshg/tools 

# Run Python script as part of build
$ docker build --progress=plain -t sureshg/py-script --target python .
$ docker run -it --rm sureshg/py-script

# SSH Server container with sysstat (sar)
$ docker build -t sureshg/ssh-server --target ssh-server .
$ docker run -it --rm -p 2222:22 sureshg/ssh-server
$ ssh test@localhost -p 2222   
```

</details>

### Run Compose

```bash
# OpenJDK App
$ docker compose -f compose/docker-compose.yml up --build --pull=always
$ docker compose watch
$ docker compose -f compose/docker-compose.yml down --remove-orphans --volumes
# curl http://localhost:[8080|8081|8082|8083]

# GraalVM Native Image
$ docker compose -f compose/graalvm-compose.yml up
# docker compose -f compose/graalvm-compose.yml build --no-cache app-arm64
$ docker compose -f compose/graalvm-compose.yml up --remove-orphans --build app-arm64
$ docker compose -f compose/graalvm-compose.yml up --remove-orphans --build app-amd64 
```

<details>
<summary>Compose Misc</summary>

```bash
# Misc Compose files
$ docker compose -f compose/tcpdump-compose.yml up
$ docker compose -f compose/binfmt-compose.yml up
$ docker compose -f compose/clickhouse-compose.yml up
$ docker compose -f compose/grafana-prom-compose.yml up
$ docker compose -f compose/kafka-compose.yml up
```

</details>

### Run images from [GHCR][container-images]

```Bash
# Run the openjdk application
$ docker run \
         --pull always \
         -p 8080:80 \
         -it --rm \
         --name openjdk-app \
         ghcr.io/sureshg/containers:openjdk-latest

# Run the native image application
$ docker run \
         --pull always \
         -p 8080:80 \
         -it --rm \
         --name nativeimage-app \
         ghcr.io/sureshg/containers:nativeimage-latest
        
# Use "--platform=linux/amd64" to run cross platform images.         
```

### Multi-Platform Builds

The following commands are used to build multi-platform images locally using `Docker Buildx` on [Rancher Desktop][3].

```bash
# Create a new buildx builder instance
$ docker buildx create --name=buildkit-container --driver=docker-container
# docker buildx use buildkit-container
# docker buildx inspect
# docker buildx rm buildkit-container

# Docker Bake
$ docker buildx bake --print
$ docker buildx bake

# Build images for all platforms
$ docker buildx \
         --builder buildkit-container \
         build \
         --sbom=true \
         --platform=linux/amd64,linux/arm64 \
         --pull \
         --no-cache  \
         --target openjdk \
         -t sureshg/openjdk-app:latest .

# Load just one platform (ARM64)
$ docker buildx \
         --builder buildkit-container \
         build \
         --load \
         --platform=linux/arm64 \
         --target openjdk \
         -t sureshg/openjdk-app:latest .

# Load another platform with a different tag (AMD64)
$ docker buildx \
         --builder buildkit-container \
         build \
         --load \
         --platform=linux/amd64 \
         --target openjdk \
         -t sureshg/openjdk-app:latest-amd64 .

# Push both platforms as one image manifest list
$ docker buildx \
         --builder buildkit-container \
         build \
         --push \
         --platform=linux/arm64,linux/amd64 \
         --target openjdk \
         -t sureshg/openjdk-app:latest .  
         
# Run the images
$ docker run -it --rm -p 8080:80 sureshg/openjdk-app:latest
$ docker run -it --rm --platform linux/amd64 -p 8080:80 sureshg/openjdk-app:latest-amd64            
```

### Debug Distroless Images

```bash       
# Run the container
$ docker run \
         --pull always \
         -p 8080:80 \
         -it \
         --rm \
         --name openjdk-app \
         ghcr.io/sureshg/containers:openjdk-latest
       
# Install cdebug
$ brew install cdebug  

# Use "--image nixery.dev/busybox/curl" to use custom images.
# Use "--platform linux/arm64" to select platform for busybox image.    
$ cdebug exec \
         --privileged \
         -it \
         --rm \
         docker://openjdk-app
```

### Misc

- Docker Init

  ```bash
  # Initialize the docker file
  $ docker init
  ```

- IntelliJ Support for Rancher Desktop

  ```bash
  # Create a symlink to docker installed by Rancher Desktop
  $ sudo ln -s $(which docker) /usr/local/bin/docker
  ```
- Install [Rancher Desktop][3] with [containerd][0] [multi-platform][1] support

  ```bash
  # Install Rancher Desktop and Select containerd as runtime.
  $ sudo docker run --privileged --rm tonistiigi/binfmt --install all
  $ rdctl shell
     # To list all architectures
     $ ls -1 /proc/sys/fs/binfmt_misc/qemu*
  
  $ docker run --rm --platform=linux/arm64 alpine uname -a
  $ docker run --rm --platform=linux/s390x alpine uname -a
  
  # Check for all the OS archs
  $ for i in `docker images --format {{.ID}}`; do echo $i `docker image inspect $i | grep -e Architecture -e Os`; done
  
  # Remove unused data
  $ docker system prune -f
  ```

- Run a private container registry

  ```bash
  $ docker run -d -p 5000:5000 --restart=always --name registry registry:2
  ```

## Resources

- [Java containerization strategies](https://learn.microsoft.com/en-us/azure/developer/java/containers/)
- [OpenJDK Container Awareness](https://developers.redhat.com/articles/2022/04/19/java-17-whats-new-openjdks-container-awareness)
- [Single Core Java Containers](https://developers.redhat.com/articles/2022/04/19/best-practices-java-single-core-containers#)
- [Docker Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#add-or-copy)
- [Choosing Between RUN, CMD, and ENTRYPOINT](https://www.docker.com/blog/docker-best-practices-choosing-between-run-cmd-and-entrypoint/)
- [A collection of docker-compose files][6]
- [Runtime privilege and Linux capabilities](https://docs.docker.com/engine/reference/run/#runtime-privilege-and-linux-capabilities)
- [Runtime options with Memory, CPUs, and GPUs](https://docs.docker.com/config/containers/resource_constraints/)

## Local Dev Tools

- [Rancher Desktop][3]
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Podman Desktop](https://podman-desktop.io/)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [Lima-Linux VM on Mac](https://github.com/lima-vm/lima)
- [Macpine](https://github.com/beringresearch/macpine)

[0]: https://github.com/containerd/containerd

[1]: https://github.com/containerd/nerdctl/blob/master/docs/multi-platform.md

[2]: https://github.com/containerd/nerdctl

[3]: https://github.com/rancher-sandbox/rancher-desktop

[4]: https://k3s.io/

[5]: https://github.com/jpetazzo/minimage

[6]: https://github.com/jonatan-ivanov/local-services

[7]: https://github.com/moby/moby


[gha_url]: https://github.com/sureshg/containers/actions/workflows/container-build.yml

[gha_img]: https://github.com/sureshg/containers/actions/workflows/container-build.yml/badge.svg

[gha_badge]: https://img.shields.io/github/actions/workflow/status/sureshg/containers/container-build.yml?branch=main&color=green&label=Container%20Build&logo=Github-Actions&logoColor=green

[lint_url]: https://hadolint.github.io/hadolint/

[lint_img]: https://img.shields.io/badge/Dockerfile%20Linter-%E2%9D%A4-2596ec.svg?logo=Docker&logoColor=2596ec

[openjdk_app_img]: https://ghcr-badge.egpl.dev/sureshg/containers/size?tag=openjdk-latest&label=OpenJDK%20App&color=mediumslateblue

[nativeimage_app_img]: https://ghcr-badge.egpl.dev/sureshg/containers/size?tag=nativeimage-latest&label=NativeImage%20App&color=mediumvioletred

[container-images]: https://github.com/sureshg/containers/pkgs/container/containers
