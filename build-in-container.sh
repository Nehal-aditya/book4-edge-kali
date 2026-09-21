#!/usr/bin/env bash
#
# $ ./$0
# $ ./$0 [...] --force
# $ CONTAINER=docker ./$0
#

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Environment
#

set -euEo pipefail
trap 'cleanup' INT TERM

cd "$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Variables
#

CONTAINER="${CONTAINER:-}"
#SUDO=()
FORCE=0
IMAGE="${IMAGE:-kali-build/kali-installer}"
OPTS=()

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Functions
#

## Output bold only if both stdout/stderr are opened on a terminal
if [ -t 1 ] && [ -t 2 ]; then
  b() { tput bold; echo -n "${*}"; tput sgr0; }
else
  b() { echo -n "${*}"; }
fi

point() { echo " * ${*}"; }
warn()  { echo "WARNING: ${*}" 1>&2; }
fail()  { echo "ERROR: ${*}"   1>&2; exit 1; }

vexec() { b "$ ${*}"; echo; exec "${@}"; }   # Last program in this script should use exec
vrun()  { b "$ ${*}"; echo;      "${@}" <&0 & child_pid=${!}; wait "${child_pid}"; }   # Backgrounded + waited on (rather than a plain foreground call) so cleanup() can kill it if we're interrupted

## Kill vrun()
cleanup() { [ -n "${child_pid:-}" ] && kill -TERM "${child_pid}" 2>/dev/null; return 0; }

build_container() {
  local _cache_args=()
  [ "${FORCE}" -eq 1 ] && _cache_args=(--no-cache)

  if [ "${FORCE}" -eq 1 ] || ! "${CONTAINER}" inspect --type image "${IMAGE}" >/dev/null 2>&1; then
    vrun "${CONTAINER}" build --network host "${_cache_args[@]}" --tag "${IMAGE}" .
    echo
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Parse & validate arguments
#

_passthrough=()
while [ $# -gt 0 ]; do
  case "${1}" in
    --force)  FORCE=1;                shift ;;
    ## Consumed, not forwarded - the --volume below needs OUT_DIR, and it must be absolute
    -o|--output)
              OUT_DIR="$( realpath -m -- "${2:-}" )"; shift 2 ;;
    --output=*)
              OUT_DIR="$( realpath -m -- "${1#*=}" )"; shift ;;
    *)        _passthrough+=("${1}"); shift ;;
  esac
done
set -- "${_passthrough[@]}"
unset _passthrough

if command -v podman >/dev/null 2>&1 && \
  { [ -z "${CONTAINER}" ] || [ "${CONTAINER}" == "podman" ]; }; then
  CONTAINER=podman

  ## We don't want stdout in the journal
  OPTS+=( --log-driver none )
elif command -v docker >/dev/null 2>&1 && \
  { [ -z "${CONTAINER}" ] || [ "${CONTAINER}" == "docker" ]; }; then
  CONTAINER=docker
else
  if [ -z "${CONTAINER}" ]; then
    fail "No container engine detected, aborting"
  elif [ "${CONTAINER}" = "podman" ] || [ "${CONTAINER}" = "docker" ]; then
    fail "Requested container engine is not installed: ${CONTAINER}"
  else
    fail "Unknown CONTAINER value: ${CONTAINER}"
  fi
fi

## Permissions & security
OPTS+=(
  ## The list of "--cap-add=[...]" came from `bpftrace` observing cap_capable() during various `./build.sh` runs, all using a --privileged container, with various arguments/options/flags where possible:
  ##   Including kali-linux-default metapackage, custom mirror, custom scratchpad/tmp/output dirs and cross building
  ##   $ sudo bpftrace -e 'kprobe:cap_capable { @[comm, arg2] = count(); }' > /tmp/out.txt
  ## Builds then repeated non-privileged container, starting without any capabilities, adding them in when an issue arises (and documenting why)
  ## The final check was to compare artifacts produced from the "baseline" bare metal build (./build.sh) at the start, with a container (./build-in-container.sh)
  ##   NOTE: but walking the ISO is pointless here - iso9660 stores no Unix metadata, every entry being 0:0 with only modes 0444/0555
  ##   $ bsdtar -tvf output/kali-linux-*.iso
  ## Plus, the d-i initrds are cpio, which keeps mode, owner and device nodes, and they are rebuilt per build - so those are what to read:
  ##   $ sudo mount -t iso9660 -o ro,loop kali-linux-*.iso /mnt/iso
  ##   $ sudo find /mnt/iso -maxdepth 3 -name initrd.gz
  ##   $ zcat initrd.gz | sudo cpio -idm -D initrd-1     # once per initrd found
  ##   $ sudo find initrd-1 initrd-2 -printf '%p %M %U:%G %s\n' | sort
  ##   $ sudo getcap -r initrd-1 initrd-2
  ##   > (nothing)
  ##   $ sudo find initrd-1 initrd-2 -type c -printf '%p\n' | sort
  ##   > initrd-1/dev/console
  ##   > initrd-1/dev/null
  ##   > initrd-2/dev/console
  ##   > initrd-2/dev/null
  ## No filesystem.squashfs to descend into - an installer ISO is a package repository plus the installer, not an installed system. pool/*.deb are byte-copies from the mirror
  ## Items checked for:
  ##   - Size (compression noise excluded)
  ##   - File count
  ##   - Permissions
  ##   - Owner/group
  ##   - Path
  ##   - Content
  ##   - Capabilities and device nodes
  ## Output that differs between two identical builds: none - the initrds are rebuilt every time, but byte-for-byte the same
  --cap-drop=ALL

  --cap-add=CHOWN                      # > chown: changing ownership of '/build/output/': Operation not permitted

  --cap-add=DAC_OVERRIDE               # > cp: cannot create directory 'simple-cdd/debian-cd': Permission denied
                                       #   Will not build without it: simple-cdd cannot create its working directories

  --cap-add=SETGID                     # > E: setgroups 65534 failed - setgroups (1: Operation not permitted)
                                       # > E: setegid 65534 failed - setegid (1: Operation not permitted)
                                       # > E: setgroups 0 failed - setgroups (1: Operation not permitted)

  --cap-add=SETUID                     # > E: seteuid 42 failed - seteuid (1: Operation not permitted)
)

## Core values
OPTS+=(
  --rm

  --network host   # Needed to reach detect_apt_caching_proxy()'s proxy, or a LAN --mirror

  --volume "${PWD}:/build"   # Will not build without it: --workdir /build is empty and the entrypoint is not found   # Alt: ${PWD}:/srv or ${PWD}:/recipes   # Alt: --mount type=bind,source=${PWD},destination=/recipes
  --workdir /build

  ## This is for ./build.sh, so it can hand ${OUT_DIR} back to the invoking user (matters more if ran with sudo)
  --env "HOST_UID=${SUDO_UID:-$( id -u )}"
  --env "HOST_GID=${SUDO_GID:-$( id -g )}"
)

## If stdin is an option, use tty
if [ -t 0 ]; then
  OPTS+=(
    --interactive
    --tty
  )
fi

## Output artifacts location
if [ -n "${OUT_DIR:-}" ]; then
  mkdir -pv "${OUT_DIR}"
  OPTS+=(
    --volume "${OUT_DIR}:${OUT_DIR}"
    --env "OUT_DIR=${OUT_DIR}"
  )
fi

if [ -n "${DEBUG:-}" ]; then
  OPTS+=(
    --env "DEBUG=${DEBUG}"
  )
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Build
#

build_container

vexec "${CONTAINER}" run "${OPTS[@]}" "${IMAGE}" /build/build.sh "${@}"
