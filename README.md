# Kali-Installer Build-Script

_Kali Linux installer ISO builder, via `simple-cdd` (with `debian-cd`)._

These are the same [build-scripts](https://gitlab.com/kalilinux/build-scripts) that the [Kali team](https://www.kali.org/) uses to generate the official Kali Linux base images, found on [kali.org/get-kali/](https://www.kali.org/get-kali/).

These images can be used to install Kali with various customization during setup, from a CD/DVD/Blu-ray/USB/sdCard. For being able to live boot (e.g. try Kali out without altering any existing operating system), see [kali-live](https://gitlab.com/kalilinux/build-scripts/kali-live):
- [kali-installer](https://gitlab.com/kalilinux/build-scripts/kali-installer) uses [Simple-CDD](https://wiki.debian.org/Simple-CDD) _(which is a wrapper for [debian-cd](https://wiki.debian.org/debian-cd))_
- [kali-live](https://gitlab.com/kalilinux/build-scripts/kali-live) uses [live-build](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html)

_Build [your Kali](https://www.kali.org/docs/introduction/kali-linux-image-overview/), today!_

## Prerequisites

_We recommend building on a Linux-based host, which matches the desired architecture._

There are various ways to get ready to use kali-installer build-script. You can either:

- `build.sh` - [Build straight from your machine](#build-from-the-host-kali)
- `build-in-container.sh` - [Build from within a container](#build-from-within-a-container) _(such as Docker or Podman)_ <!-- Should be able to use other alts, but they are untested -->

For `build.sh` to work, it **will require super user access** (e.g. sudo or a rootful container). However, KVM isn't required.

- - -

First install git, and make sure that the repository is cloned locally:

```console
$ sudo apt-get install --no-install-recommends \
    git ca-certificates
$ git clone https://gitlab.com/kalilinux/build-scripts/kali-installer.git
$ cd ./kali-installer/
```

### Build From The Host (Kali)

To build directly on your host, with `build.sh`, install the build dependencies:

```console
$ sudo apt-get install --no-install-recommends \
    simple-cdd debian-cd \
    cpio \
    mtools \
    dosfstools \
    xorriso
```

- - -

Now you can use `./build.sh`, which will build a Kali installer ISO straight on your machine.

### Build From The Host (Debian-based, non-Kali)

If you are NOT using Kali as the base OS, you will need to install Kali's `kali-archive-keyring` in order for `simple-cdd` to fetch Kali's packages.

```console
$ sudo apt-get install --no-install-recommends \
    wget ca-certificates
$ wget https://http.kali.org/pool/main/k/kali-archive-keyring/kali-archive-keyring_20YY.X_all.deb
$ sudo apt-get install ./kali-archive-keyring_*_all.deb
$ wget https://http.kali.org/pool/main/d/debian-cd/debian-cd_*_all.deb
$ sudo apt-get install ./debian-cd_*_all.deb
```
<!-- Alt: $ dpkg -i ./kali-archive-keyring_20YY.X_all.deb -->

_NOTE: Replace `20YY.X` with the values shown [here, in `kali-archive-keyring`](https://http.kali.org/pool/main/k/kali-archive-keyring/)._

Depending on when you run this, you may also need a certain version of [simple-cdd](https://http.kali.org/kali/pool/main/s/simple-cdd/) _(Package Tracker: [Debian](https://tracker.debian.org/pkg/simple-cdd)/[Kali](https://pkg.kali.org/pkg/simple-cdd))_ and/or [debian-cd](https://http.kali.org/kali/pool/main/d/debian-cd/) _(Package Tracker: [Debian](https://tracker.debian.org/pkg/debian-cd)/[Kali](https://pkg.kali.org/pkg/debian-cd))_.
<!-- Alt: $ sudo apt-get satisfy --no-install-recommends debian-cd -->

- - -

Now you can follow [Build From The Host (Kali)](#build-from-the-host-kali) to install build dependencies.

### Build From Within A Container

_We will skip over setting up any container software._

If you prefer to build from within a container, you will need to install and configure either `docker` or `podman` on your machine.

- `docker` requires the user to be added to the Docker group, or using the root account (e.g. `$ sudo ./build-in-container.sh`).
- `podman` has been tested with rootful (e.g. `$ sudo ./build-in-container.sh`), however rootless is not supported at this time.

- - -

`build-in-container.sh` is a wrapper on top of `build.sh`. It detects which OCI-compliant container engine to use, takes care of creating the [container image](./Dockerfile) if missing, and then it starts the container to perform the build from within.

You have three ways to provide the container image:

```console
$ # Option #1 - Automated build (recommended)
$ ./build-in-container.sh
$ ./build-in-container.sh --force   # If you need to rebuild the image from scratch
$
$
$
$ # Option #2 - Manual build
$ docker build -t kali-build/kali-installer .
$ # ...OR...
$ podman build -t kali-build/kali-installer .
$
$
$
$ # Option #3 - Use the pre-generated
$ docker pull registry.gitlab.com/kalilinux/build-scripts/kali-installer:latest
$ docker tag registry.gitlab.com/kalilinux/build-scripts/kali-installer:latest kali-build/kali-installer
$ # ...OR...
$ podman pull registry.gitlab.com/kalilinux/build-scripts/kali-installer:latest
$ podman tag registry.gitlab.com/kalilinux/build-scripts/kali-installer:latest kali-build/kali-installer
$
$ # ...then point the build at it:
$ ./build-in-container.sh                                                                           # Locally built (automated or manual)
$ IMAGE=registry.gitlab.com/kalilinux/build-scripts/kali-installer:latest ./build-in-container.sh   # Pre-generated
```

- - -

If you have both `docker` and `podman` installed, `build-in-container.sh` will default to using `podman`. To change this, prefix `CONTAINER=docker` before `./build-in-container.sh`:

```console
$ CONTAINER=docker ./build-in-container.sh [...]
```

- - -

Now you can use `./build-in-container.sh` (rather than `./build.sh`), to build an image.

## Help

```console
$ ./build.sh --help
Usage: build.sh [OPTIONS]

Build a Kali Linux Installer image.

Build options:
  -a, --arch ARCH              Build an image for this architecture (default: amd64)
                               Supported: amd64 arm64 armhf i386
  -b, --branch BRANCH          Kali branch used to build the image (default: kali-rolling)
                               Supported: kali-rolling kali-dev kali-last-snapshot
  -k, --keep                   Keep intermediary build artifacts
  -m, --mirror URL             Mirror used to build the image (default: http://http.kali.org/kali)
  -o, --output DIR             Output directory (default: /home/kali/kali-installer/output)
  -v, --variant VARIANT        Variant of image to build (default: default)
                               Supported: default everything netinst purple
  -x, --version VERSION        What to name the image release as (default: rolling)
  -h, --help                   Show this help and exit

Installer options:
  -H, --hostname HOSTNAME      Set system host name (default: kali)
  -P, --packages PKGS          Install extra packages (comma/space separated list)

Apt caching proxy:
  Auto-detected: localhost:3142 (apt-cacher-ng), localhost:8000 (squid-deb-proxy).
  If detected and http_proxy is not set, http_proxy is exported automatically.

Supported environment variables:
  http_proxy  HTTP proxy URL, see README.md for details
  DEBUG       Print extra debug output
  Any --flag value can be pre-set via its env var (e.g. ARCH, BUILD_MIRROR, OUT_DIR)

Examples:
  build.sh
  build.sh --branch kali-rolling
  build.sh -b kali-dev -v netinst -a arm64
```

_NOTE: Three flags do not share their variable's name: `--mirror` is `BUILD_MIRROR`, `--hostname` is `KALI_HOSTNAME` (bash already sets `HOSTNAME`) and `--output` is `OUT_DIR`. Every other flag is its own name, upper-cased (e.g. `--branch` is `BRANCH`)._

<!-- _NOTE: Setting a "--flag" value as an environment variable only really works on the host (e.g. `./build.sh`). `build-in-container.sh` passes `OUT_DIR` through, plus its own `HOST_UID`/`HOST_GID`; every other variable you set is dropped._ -->

For more information and/or examples, please see:

- [kali.org/docs/development/live-build-a-custom-kali-iso/](https://www.kali.org/docs/development/live-build-a-custom-kali-iso/)
- [kali-preseed-examples](https://gitlab.com/kalilinux/recipes/kali-preseed-examples)
- [live-build-config-examples](https://gitlab.com/kalilinux/recipes/live-build-config-examples)
- [kali-live](https://gitlab.com/kalilinux/build-scripts/kali-live)

## Build + Custom Values

Use either `build.sh` or `build-in-container.sh`, at your preference.
From this point we will use `build.sh` for brevity.

The default options will build a [Kali rolling](https://www.kali.org/docs/general-use/kali-branches/) image, for AMD64 architecture:

```console
$ sudo ./build.sh
┏━━(Kali Installer image)
┃  * Building a Kali Linux Installer image for amd64 architecture
┃ # System:
┃  * Build environment is host (bare metal)
┃  * Host architecture is amd64
┃ # Build:
┃  * Branch              : kali-rolling
┃  * Build mirror        : http://http.kali.org/kali/
┃  * Keep temporary files: false
┃  * Output              : /home/kali/kali-installer/output/kali-linux-rolling-installer-amd64.iso
┃  * Variant             : default
┃  * Version             : rolling
┃ # Installer:
┃  * Additional packages :
┃  * Hostname            : kali
┃ # Proxy configuration:
┃  * No apt caching proxy detected
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[...]
```

- - -

Build a different installer image variant (`-v`/`--variant`), one which has every tool, or a network install:

```console
$ sudo ./build.sh --variant everything
$
$ sudo ./build.sh --variant netinst
```

- - -

If you wish to debug a failed run, it might be handy to keep the intermediary build artifacts around afterwards (`-k`/`--keep`), as well as to pull from a specific [Kali mirror](https://www.kali.org/docs/community/kali-linux-mirrors/) using `-m`/`--mirror`, with as much output as possible (`DEBUG=1`):

```console
$ sudo DEBUG=1 ./build.sh --keep --mirror http://kali.download/kali
```

## Caching Proxy Configuration

When building OS images, it is useful to have a caching mechanism in place, to avoid downloading all the packages from the Internet, again and again.
To this effect, the build script attempts to detect known caching proxies that would be running on the local host. It first refers to the local APT configuration `Acquire::http::Proxy`. If not set, it then tries to detect `apt-cacher-ng` and `squid-deb-proxy` by checking if a service is listening on their default port. This mechanism doesn't work for `approx` (a well-known APT caching proxy), as it's auto-started on demand.

_NOTE: This detection only runs when using the default mirror. If you pass your own `-m/--mirror` value, detection is skipped._

To override this detection, you can export the environment variable `http_proxy` yourself.
For example, if you want to use a proxy that is running on your machine on the port `9876`, use: `export http_proxy=http://127.0.0.1:9876`.
If you want to make sure that no proxy is used, use: `$ http_proxy= ./build.sh`.

Alternatively, you can set up a [local Kali mirror](https://www.kali.org/docs/community/setting-up-a-kali-linux-mirror/).

## Deploy Installer Image

The resulting `.iso` is a hybrid image: it can be written to a USB/sdCard drive, or burned to a CD/DVD/Blu-ray, to boot the Kali installer.
If you would rather try it out, without altering any existing operating system(s), see [kali-live](https://gitlab.com/kalilinux/build-scripts/kali-live).

### Flash to a USB drive (dd)

```console
$ lsblk
$ sudo dd if=output/kali-linux-rolling-installer-amd64.iso of=/dev/<usb-drive> bs=4M status=progress oflag=sync
```

_NOTE: Make sure to use your actual USB device, such as `sdb` instead of `<usb-drive>`._

**CAUTION: This will format the USB drive and erase all its contents!**

#### From Windows (balenaEtcher / Rufus)

You can use [balenaEtcher](https://etcher.balena.io/) or [Rufus](https://rufus.ie/) to flash the image onto the USB drive. Start the tool, select the image file, select the target (the USB drive), then flash.

### Running in QEMU

Being a hybrid ISO, it can also be run directly with QEMU:

```console
$ sudo apt-get install --no-install-recommends \
    qemu-system-x86
$ qemu-system-x86_64 \
    -cdrom output/kali-linux-rolling-installer-amd64.iso \
    -enable-kvm \
    -cpu host \
    -m 4096 \
    -smp cores=4
```

## Structure

<!--
Yes, this is a wrapper, for a wrapper...

./build.sh -> simple-cdd -> debian-cd
-->

- `./build.sh` - the main entrypoint _(calls `simple-cdd`, which drives `debian-cd`)_
- `./build-in-container.sh` - wraps `./build.sh` inside the build-helper container environment _(using [`./Dockerfile`](./Dockerfile))_
- `./Dockerfile` - the build-helper container
- `./kali-config/` - the `debian-cd` config tree: `common/` (shared) plus one `installer-*/` directory per variant _(`default`/`everything`/`netinst`/`purple`)_
- `./simple-cdd/` - the `simple-cdd` profile config _(`profiles/`, `local_packages`, `disc-end-hook`, `simple-cdd.conf`)_

## CI Overview

The [`./.gitlab-ci.yml`](./.gitlab-ci.yml) pipeline:

- **`lint`** - `shellcheck`/`yamllint`/`hadolint` against the scripts and Dockerfile
- **`build_push_container`** - builds the build-helper container ([`./Dockerfile`](./Dockerfile)) and [publishes it](https://gitlab.com/kalilinux/build-scripts/kali-installer/container_registry)

## Known Limitations

There are a few known limitations of using this build-script:

- [Docker rootless](https://docs.docker.com/engine/security/rootless/) is untested
- `podman` rootless is not supported at this time, see [Build From Within A Container](#build-from-within-a-container)

_If you find something, [let us know](https://gitlab.com/kalilinux/build-scripts/kali-installer/-/work_items)!_
