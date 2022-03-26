# Container/K8S Playground!

[![GitHub Workflow Status][gha_badge]][gha_url]
[![Docker Linter][lint_img]][lint_url]

 Container/K8S/Compose playground using [k3s][5]/[nerdctl][2]/[Rancher Desktop][3]. 
 Also contains a demo non-native(multi-platform) `openjdk` container image using `nerdctl`

## Install

 - Install [Rancher Desktop][3] with [containerd][0] [multi-platform][1] support
  
   ```bash
   # Install Rancher Desktop and Select containerd as runtime.
   $ sudo docker run --privileged --rm tonistiigi/binfmt --install all
   $ LIMA_HOME="$HOME/Library/Application Support/rancher-desktop/lima" /Applications/Rancher\ Desktop.app/Contents/Resources/resources/darwin/lima/bin/limactl shell 0
      $ ls -1 /proc/sys/fs/binfmt_misc/qemu*
        /proc/sys/fs/binfmt_misc/qemu-aarch64
        /proc/sys/fs/binfmt_misc/qemu-arm
        /proc/sys/fs/binfmt_misc/qemu-mips64
        /proc/sys/fs/binfmt_misc/qemu-mips64el
        /proc/sys/fs/binfmt_misc/qemu-ppc64le
        /proc/sys/fs/binfmt_misc/qemu-riscv64
        /proc/sys/fs/binfmt_misc/qemu-s390x

   $ docker run --rm --platform=linux/arm64 alpine uname -a
   $ docker run --rm --platform=linux/s390x alpine uname -a
   
   
   # Check for all the OS archs
   $ for i in `docker images --format {{.ID}}`; do echo $i `docker image inspect $i | grep -e Architecture -e Os`; done
   
   # Remove unused data
   $ docker system prune -f
   # OR $ docker system df && docker image prune -f && docker container prune -f && docker network prune -f && docker volume prune -f
   
   ```
 
 - Hostnames to access the `Rancher Desktop` host.

   ```markdown
   * 192.168.5.2 (Lima/qemu gateway address)
   * host.docker.internal  
   * host.lima.internal
   * host.rancher-desktop.internal
   * host.k3d.internal
   ```
 - Update [nerdctl][2] on [Rancher Desktop][3]

   ```bash
   $ LIMA_HOME="$HOME/Library/Application Support/rancher-desktop/lima" "/Applications/Rancher Desktop.app/Contents/Resources/resources/darwin/lima/bin/limactl" shell 0
   $ sudo apk add curl
   $ curl -sfL https://github.com/containerd/nerdctl/releases/download/v0.13.0/nerdctl-0.13.0-linux-amd64.tar.gz | sudo tar xz -C /usr/local/bin -f -
   $ nerdctl --version
   ```

[0]: https://github.com/containerd/containerd
[1]: https://github.com/containerd/nerdctl/blob/master/docs/multi-platform.md
[2]: https://github.com/containerd/nerdctl
[3]: https://github.com/rancher-sandbox/rancher-desktop
[4]: https://github.com/Gibdos/compose_collection
[5]: https://k3s.io/

[gha_url]: https://github.com/sureshg/containers/actions/workflows/docker-publish.yml
[gha_img]: https://github.com/sureshg/containers/actions/workflows/docker-publish.yml/badge.svg
[gha_badge]: https://img.shields.io/github/workflow/status/sureshg/containers/Docker?color=green&label=Container%20Build&logo=Github-Actions&logoColor=green&style=for-the-badge

[lint_url]: https://hadolint.github.io/hadolint/
[lint_img]: https://img.shields.io/badge/Dockerfile%20Linter-%E2%9D%A4-2596ec.svg?logo=Docker&style=for-the-badge&logoColor=2596ec