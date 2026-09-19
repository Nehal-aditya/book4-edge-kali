#!/usr/bin/env bash
#
# $ ./$0
# $ ./$0 --branch kali-rolling
# $ ./$0 -b kali-dev -v netinst -a arm64
# $ BUILD_MIRROR=http://kali.download/kali ./$0
# $ http_proxy= ./$0
# $ DEBUG=1 ./$0
#
# REF:
#   - https://gitlab.com/kalilinux/build-scripts/kali-installer
#   - https://gitlab.com/kalilinux/build-scripts/kali-live
#

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Environment
#

set -euEo pipefail
trap 'echo "ERROR: ${BASH_SOURCE[0]}:${LINENO} (status ${?})" >&2' ERR
trap 'cleanup_perms' EXIT
trap 'cleanup_ps' INT TERM   # cleanup_fs is added once ${KEEP} is parsed

cd "$( dirname "$( readlink -f "${BASH_SOURCE[0]}" )" )"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Variables
#

## Defaults
DEFAULT_ARCH="amd64"
DEFAULT_BRANCH="kali-rolling"
DEFAULT_BUILD_MIRROR="http://http.kali.org/kali"
DEFAULT_KALI_HOSTNAME="kali"
DEFAULT_KEEP="false"
DEFAULT_OUT_DIR="${PWD}/output"
DEFAULT_PACKAGES=
DEFAULT_VARIANT="default"

ARCH="${ARCH:-$DEFAULT_ARCH}"
BRANCH="${BRANCH:-$DEFAULT_BRANCH}"
BUILD_MIRROR="${BUILD_MIRROR:-$DEFAULT_BUILD_MIRROR}"
DEBUG="${DEBUG:-}"
HOST_ARCH=$( dpkg --print-architecture 2>/dev/null || true )   # Alt: $( uname -m )
KALI_HOSTNAME="${KALI_HOSTNAME:-$DEFAULT_KALI_HOSTNAME}"
KEEP="${KEEP:-$DEFAULT_KEEP}"
OUT_DIR="${OUT_DIR:-$DEFAULT_OUT_DIR}"
OUT_FILENAME=
PACKAGES="${PACKAGES:-$DEFAULT_PACKAGES}"
PLATFORM="image"
PROJECT="Installer"
PROMPT="#"
VARIANT="${VARIANT:-$DEFAULT_VARIANT}"
VERSION="${VERSION:-}"   # Its default value depends on ${BRANCH}  See: default_version()

## Apt caching proxies to auto-detect
KNOWN_CACHING_PROXIES="\
3142 apt-cacher-ng
8000 squid-deb-proxy"
DETECTED_CACHING_PROXY=

## Supported values
SUPPORTED_ARCHITECTURES="amd64 arm64 armhf i386"
SUPPORTED_BRANCHES="kali-rolling kali-dev kali-last-snapshot"
SUPPORTED_VARIANTS=$( for d in ./kali-config/installer-*/; do d="${d%/}"; echo "${d##*/installer-}"; done | paste -sd' ' )

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Functions
#

## display_help - print usage info and exit
display_help() {
  cat <<EOF
Usage: $( basename "${0}" ) [OPTIONS]

Build a Kali Linux ${PROJECT} ${PLATFORM}.

Build options:
  -a, --arch ARCH              Build an ${PLATFORM} for this architecture (default: $( b "${DEFAULT_ARCH}" ))
                               Supported: ${SUPPORTED_ARCHITECTURES}
  -b, --branch BRANCH          Kali branch used to build the ${PLATFORM} (default: $( b "${DEFAULT_BRANCH}" ))
                               Supported: ${SUPPORTED_BRANCHES}
  -k, --keep                   Keep intermediary build artifacts
  -m, --mirror URL             Mirror used to build the ${PLATFORM} (default: $( b "${DEFAULT_BUILD_MIRROR}" ))
  -o, --output DIR             Output directory (default: $( b "${DEFAULT_OUT_DIR}" ))
  -v, --variant VARIANT        Variant of ${PLATFORM} to build (default: $( b "${DEFAULT_VARIANT}" ))
                               Supported: ${SUPPORTED_VARIANTS}
  -x, --version VERSION        What to name the ${PLATFORM} release as (default: $( b "$( default_version )" ))
  -h, --help                   Show this help and exit

${PROJECT} options:
  -H, --hostname HOSTNAME      Set system host name (default: $( b "${DEFAULT_KALI_HOSTNAME}" ))
  -P, --packages PKGS          Install extra packages (comma/space separated list)

Apt caching proxy:
  Auto-detected: localhost:3142 (apt-cacher-ng), localhost:8000 (squid-deb-proxy).
  If detected and http_proxy is not set, http_proxy is exported automatically.

Supported environment variables:
  http_proxy  HTTP proxy URL, see README.md for details
  DEBUG       Print extra debug output
  Any --flag value can be pre-set via its env var (e.g. ARCH, BUILD_MIRROR, OUT_DIR)

Examples:
  $( basename "${0}" )
  $( basename "${0}" ) --branch kali-rolling
  $( basename "${0}" ) -b kali-dev -v netinst -a arm64
EOF
  exit 0
}

## b <text> - bold-wrap text if writing to a TTY, else pass through
if [ -t 1 ] && [ -t 2 ]; then
  b() { tput bold; echo -n "${*}"; tput sgr0; }
else
  b() { echo -n "${*}"; }
fi

## vrun <cmd> [args] - log timestamped command, then execute it
##   Using pipes with vrun() doesn't work too well
vrun() { { echo -n "[$( date -u +'%H:%M:%S' )] ${PROJECT// /}:~${PROMPT} "; b "${*}"; echo; } 1>&2; "${@}" <&0 & child_pid=${!}; local _rc=0; wait "${child_pid}" || _rc=${?}; return "${_rc}"; }

## point <text> - print a bullet-prefixed line
point() { echo " * ${*}"; }
## warn <msg> - print WARNING-prefixed message to stderr
warn()  { echo "WARNING: ${*}" 1>&2; }
## fail <msg> - print ERROR-prefixed message to stderr and exit 1
fail()  { echo "ERROR: ${*}" 1>&2; exit 1; }
## debug <msg> - print DEBUG-prefixed message to stderr
debug() { [ -n "${DEBUG}" ] && echo "DEBUG: ${*}" 1>&2; return 0; }

## require_arg <flag> <value> - fail if value is empty
require_arg() {
  [ -n "${2:-}" ] || fail "Option ${1} requires an argument";
}

## fail_invalid <flag> <value> [extra...] - fail with "Invalid value 'X' for option Y (...)"
fail_invalid() {
  local _msg="Invalid value '${2}' for option ${1}"

  shift 2
  [ "${#}" -gt 0 ] \
    && _msg="${_msg} (${*})"
  fail "${_msg}"
}

## in_list <word> <list> - return 0 if word matches any item, else 1
in_list() {
  local _word="${1}"
  local _list="${2}"
  local _item=

  # shellcheck disable=SC2086  # ${list} is intentionally word-split
  for _item in ${_list}; do
    [ "${_item}" = "${_word}" ] \
      && return 0
  done
  return 1
}

## kali_message <title> - wrap piped lines in a kali-themed box with bold title
kali_message() {
  local _line=

  echo   "┏━━($( b "$*" ))"
  while IFS= read -r _line; do
    echo "┃ ${_line}"
  done
  echo   "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

## default_version - return BRANCH minus "kali-" prefix (e.g. "last_snapshot" from "kali-last-snapshot")
default_version() {
  local _version="${BRANCH#kali-}"
  #[ -n "${CI_COMMIT_SHORT_SHA:-}" ] \
  #  && _version="${_version}_${CI_COMMIT_SHORT_SHA}"
  echo "${_version//-/_}";   # Alt: echo "${_version//-/_}_$( date -u +%Y_%m_%d )"
}

## is_cross_build - return 0 if HOST_ARCH and ARCH require cross-architecture builds, else 1
is_cross_build() {
  [ "${HOST_ARCH}" != "${ARCH}" ]
}

## cleanup_ps - kill vrun() processes
cleanup_ps() {
  if [ -n "${child_pid:-}" ]; then
    #pkill -TERM -P "${child_pid}" 2>/dev/null || true
    kill -TERM "${child_pid}"     2>/dev/null || true
  fi
}

## cleanup_perms - chown ${OUT_DIR} back to non-root who ran ./build*.sh (matters more if ran with sudo)
cleanup_perms() {
  local _uid="${HOST_UID:-${SUDO_UID:-}}"
  local _gid="${HOST_GID:-${SUDO_GID:-${_uid}}}"

  [ -n "${_uid}" ]      || return 0
  [ -d "${OUT_DIR:-}" ] || return 0
  chown -R "${_uid}:${_gid}" ./ 2>/dev/null || true   # See: ./.gitignore                    # Skipping: $ chown -v [...]   ...too noisy
  chown -R "${_uid}:${_gid}" "${OUT_DIR}/" || true    # In-case ${OUT_DIR} is outside repo   # Skipping: $ chown -v [...]   ...too noisy
}

## detect_container - return engine name if running in a container, else empty
detect_container() {
  local _engine=

  if [ -e /.dockerenv ]; then
    echo "docker"
    return
  fi

  if [ -e /run/.containerenv ]; then
    _engine=$( grep -oE '^engine="?[^"]*"?' /run/.containerenv 2>/dev/null \
                  | sed -E 's/^engine="?([^"]*)"?/\1/' \
                  | head -1 \
                || true )
    echo "${_engine:-podman}"
    return
  fi

  if [ -r /proc/1/environ ]; then
    _engine=$( tr '\0' '\n' < /proc/1/environ 2>/dev/null \
                  | sed -n 's/^container=//p' \
                  | head -1 )
    if [ -n "${_engine}" ]; then
      echo "${_engine}"
      return
    fi
  fi

  if [ -r /proc/1/cgroup ]; then
    _engine=$( grep -oE '(docker|containerd|podman|lxc|kubepods)' /proc/1/cgroup 2>/dev/null \
                  | head -1 \
                || true )
    if [ -n "${_engine}" ]; then
      echo "${_engine}"
      return
    fi
  fi

  return 0
}

## detect_apt_caching_proxy - return "PORT NAME" of a local apt-caching proxy, or empty
detect_apt_caching_proxy() {
  local _port=
  local _proxy=

  ## Use APT's configured proxy if set
  if [ -x /usr/bin/apt-config ]; then
    _proxy=$( apt-config dump --format '%v%n' Acquire::http::Proxy )
    _proxy="${_proxy%/}"
    [[ "${_proxy}" == *:*:* ]] && _port="${_proxy##*:}"
    if [[ "${_port}" =~ ^[0-9]+$ ]]; then
      echo "${_port} apt-config"
      return
    fi
  fi

  ## Attempt to detect well-known http caching proxies on localhost
  ##   See bash(1) section "REDIRECTION". This is not bullet-proof.
  while read -r _port _proxy; do
    ( : </dev/tcp/localhost/"${_port}" ) 2>/dev/null \
      || continue
    echo "${_port} ${_proxy}"
    return
  done <<< "${KNOWN_CACHING_PROXIES}"
}

## create_image - main magic
create_image() {
  local _profiles="kali"
  local _auto_profiles=

  ## Override some debian-cd environment variables ~ https://salsa.debian.org/images-team/debian-cd/-/blob/master/CONF.sh
  BASEDIR="${PWD}/simple-cdd/debian-cd"
  export BASEDIR
  export ARCHES="${ARCH}"
  export ARCH
  DEBVERSION="${VERSION}"
  export DEBVERSION
  CODENAME="${BRANCH}"
  export CODENAME

  if [ "${VARIANT}" = "netinst" ]; then
    export DISKTYPE="NETINST"
    export FORCE_CD_SIZE1="STICK1GB"
  elif [ "${VARIANT}" = "purple" ]; then
    export DISKTYPE="BD"
    export KERNEL_PARAMS="debian-installer/theme=Clearlooks-Purple"
    _profiles="kali kali-purple offline"
  else    # plain installer, or "everything"
    export DISKTYPE="BD"
    _profiles="kali offline"
  fi
  _auto_profiles="${_profiles}"
  debug "DISKTYPE: ${DISKTYPE}"
  debug "profiles: ${_profiles}"
  debug "auto_profiles: ${_auto_profiles}"
  [ -v KERNEL_PARAMS ] \
    && debug "KERNEL_PARAMS: ${KERNEL_PARAMS}"

  #
  ## Clean up
  #
  debug "Stage [1/3] - Clean up"
  cleanup_fs force

  #
  ## Config
  #
  debug "Stage [2/3] - File(s)"
  ## Setup custom debian-cd to make our changes
  vrun cp -aT /usr/share/debian-cd simple-cdd/debian-cd    # Skipping: $ cp -aTv [...]   ...too noisy

  ## Use the same grub theme as in the live images until debian-cd is smart enough: http://bugs.debian.org/1003927
  vrun cp -fv kali-config/common/bootloaders/grub-pc/grub-theme.in "simple-cdd/debian-cd/data/${BRANCH}/grub-theme.in"

  ## Keep 686-pae udebs as we changed the default from 686 to 686-pae in the debian-installer images
  vrun sed -i -e '/686-pae/d' "simple-cdd/debian-cd/data/${BRANCH}/exclude-udebs-i386"

  ## Configure the kali profile with the packages we want
  vrun grep -v '^#' "kali-config/installer-${VARIANT}/packages" | tee ./simple-cdd/profiles/kali.downloads

  ## User-requested extra packages (-P/--packages)
  ##   - kali.packages : To be installed
  ##   - kali.downloads: Included on the disk, not installed
  ##   Not doing `vrun tr [...]`, due to vrun()'s `&` running in the background, so stdin becomes `/dev/null` and the here-string (<<<) is lost
  [ -n "${PACKAGES}" ] && \
    tr ', ' '\n' <<< "${PACKAGES}" | awk 'NF' | tee -a ./simple-cdd/profiles/kali.packages

  ## Tasksel is required in the mirror for debian-cd
  vrun echo tasksel | tee -a ./simple-cdd/profiles/kali.downloads

  if [ "${DEFAULT_KALI_HOSTNAME}" = "${KALI_HOSTNAME}" ]; then
    debug "Skipping injecting/setting hostname"
  else
    debug "${VARIANT} injecting hostname via kali.preseed"

    ## Create a pristine/untouched copy for cleanup_fs()
    [ -f "${PWD}/simple-cdd/profiles/kali.preseed.orig" ] \
      || vrun cp -v "${PWD}/simple-cdd/profiles/kali.preseed" "${PWD}/simple-cdd/profiles/kali.preseed.orig"

    ## Re-enables the netcfg question disabled in kali.preseed (CD/local boot)
    vrun sed -E -i \
      -e "s/^(# )?d-i netcfg\/get_hostname string .*\$/d-i netcfg\/get_hostname string ${KALI_HOSTNAME}/" \
      ./simple-cdd/profiles/kali.preseed
      ## Skip over the hostname screen when installing (true = skip, false = show)
      #-e 's/^(# )?d-i netcfg\/get_hostname seen false$/d-i netcfg\/get_hostname seen false/' \

    ## netboot/netinst/NetworkInstall uses its own/another preseed, which is in initrd.gz
    ##   So the hostname has to be injected into that initrd, rather than passed as a `preseed/url=` or `hostname=` kernel param
    if [ "${VARIANT}" = "netinst" ]; then
      debug "${VARIANT} injecting hostname via initrd.gz"

      local _netboot_work="${PWD}/simple-cdd/tmp/netboot"
      local _netboot_url _netboot_kernel

      if [ "${ARCH}" = "armhf" ]; then
        _netboot_url="${BUILD_MIRROR}dists/${BRANCH}/main/installer-${ARCH}/current/images/netboot"
        _netboot_kernel="vmlinuz"
      else
        _netboot_url="${BUILD_MIRROR}dists/${BRANCH}/main/installer-${ARCH}/current/images/netboot/debian-installer/${ARCH}"
        _netboot_kernel="linux"
      fi
      debug "${_netboot_url} -> ${_netboot_kernel}"

      vrun mkdir -pv "${_netboot_work}/initrd"
      vrun wget -nv -O "${_netboot_work}/linux"     "${_netboot_url}/${_netboot_kernel}"
      vrun wget -nv -O "${_netboot_work}/initrd.gz" "${_netboot_url}/initrd.gz"

      ( cd "${_netboot_work}/initrd" \
        && zcat ../initrd.gz | cpio -idm \
        && sed -E -i \
             -e "s/^(# )?d-i netcfg\/get_hostname string .*\$/d-i netcfg\/get_hostname string ${KALI_HOSTNAME}/" \
             preseed.cfg \
        && find . | cpio -o -H newc 2>/dev/null | gzip -9 > ../initrd.gz.new )
      vrun mv -fv "${_netboot_work}/initrd.gz.new" "${_netboot_work}/initrd.gz"

      vrun cp -fv "${_netboot_work}/linux"     "${OUT_DIR}/${OUT_FILENAME%.iso}.netboot-linux"
      vrun cp -fv "${_netboot_work}/initrd.gz" "${OUT_DIR}/${OUT_FILENAME%.iso}.netboot-initrd.gz"
    fi
  fi

  ## Grub is the only supported bootloader on arm64, so ensure it's on the iso for arm64.
  if [ "${ARCH}" = "arm64" ]; then
    debug "arm64 GRUB"
    vrun echo "grub-efi-arm64" | tee -a ./simple-cdd/profiles/kali.downloads
  fi

  #
  ## Build
  #
  debug "Stage [3/3] - Build"
  pushd simple-cdd/
  vrun build-simple-cdd \
    --verbose \
    --debug \
    --force-root \
    --conf simple-cdd.conf \
    --dist "${BRANCH}" \
    --debian-mirror "${BUILD_MIRROR}" \
    --profiles "${_profiles}" \
    --auto-profiles "${_auto_profiles}"
  popd

  #
  ## Done
  #
  debug "Moving files"
  vrun mv -fv ./simple-cdd/images/kali-*.iso "${OUT_DIR}/${OUT_FILENAME}"
}

## check_os - check the host
check_os() {
  if grep -q -e "^ID=debian" -e "^ID_LIKE=debian" /usr/lib/os-release; then
    # shellcheck disable=SC1091
    debug "OS: $( . /usr/lib/os-release && echo "${NAME}" "${VERSION}" )"
  elif [ -e /etc/debian_version ]; then
    debug "OS: $( cat /etc/debian_version )"
  else
    fail "Non Debian-based OS"
  fi

  ## See: ./README.md
  require_package debian-cd "3.2.1+kali1"
  require_package simple-cdd "0.6.10"
}

## valid_hostname <name> - check name is letters/digits/hyphens, no leading/trailing hyphen
valid_hostname() {
  ## See hostname(7) and netcfg/netcfg-common.c from debian-installer
  local _name="${1}"

  [[ "${_name}" =~ ^[A-Za-z0-9-]+$ ]] \
    || return 1

  ## Alt: [[ "${_name}" =~ ^-|-$ ]]
  [[ "${_name}" == -* || "${_name}" == *- ]] \
    && return 1

  return 0
}

## cleanup_fs [force] - rm temp files
cleanup_fs() {
  [ -n "${DEBUG}" ] && [ -e "${PWD}/simple-cdd/tmp/log/build-debian-cd" ] && \
    vrun cp -fv ${PWD}/simple-cdd/tmp/log/build-debian-cd ${OUT_DIR}/${OUT_FILENAME}.build-debian-cd_$( date -u +%Y_%m_%d ).log

  if [ "${1:-}" != "force" ] && [ "${KEEP}" = "true" ]; then
    debug "Skipping cleanup_fs"
    return 0
  fi

  ## See: ./.gitignore
  vrun rm -rf "${PWD}/simple-cdd/tmp/"
  vrun rm -rf "${PWD}/simple-cdd/debian-cd/"
  vrun rm -rf "${PWD}/simple-cdd/images/"
  vrun rm -fv "${PWD}/simple-cdd/profiles/kali.downloads"
  vrun rm -fv "${PWD}/simple-cdd/profiles/kali.packages"

  ## Put back the pristine/untouched copy before create_image()
  if [ -f "${PWD}/simple-cdd/profiles/kali.preseed.orig" ]; then
    vrun mv -fv "${PWD}/simple-cdd/profiles/kali.preseed.orig" "${PWD}/simple-cdd/profiles/kali.preseed"
  fi
}

## require_package <pkg> <version> - check package minimum version
require_package() {
  local _pkg=${1}
  local _required_version=${2}
  local _pkg_version=

  _pkg_version=$( dpkg-query -f '${Version}' -W "${_pkg}" 2>/dev/null || true )

  if [ -z "${_pkg_version}" ]; then
    fail "You need ${_pkg} (>= ${_required_version}), but it is not installed"
  elif dpkg --compare-versions "${_pkg_version}" lt "${_required_version}"; then
    fail "You need ${_pkg} (>= ${_required_version}), you have ${_pkg_version}"
  else
    debug "Passing: ${_pkg} (>= ${_required_version}), you have ${_pkg_version}"
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Parse & validate arguments
#

while [ "${#}" -gt 0 ]; do
  ## "Fix" any user-input
  case "${1}" in
    ## Boolean flags, behave as if the user just toggled them
    --help=*|--keep=*)
        set -- "${1%%=*}" "${@:2}" ;;
    ## Pre-normalize, drop "=".
    ##   E.g.: "--foo=bar" -> "--foo bar"
    --*=*)
        set -- "${1%%=*}" "${1#*=}" "${@:2}" ;;
  esac

  case "${1}" in
    -a|--arch)             require_arg "${1}" "${2:-}"; ARCH="${2}";                 shift 2 ;;
    -b|--branch)           require_arg "${1}" "${2:-}"; BRANCH="${2}";               shift 2 ;;
    -h|--help)             display_help ;;
    -H|--hostname)         require_arg "${1}" "${2:-}"; KALI_HOSTNAME="${2}";        shift 2 ;;
    -k|--keep)             KEEP=true;                                                shift ;;
    -m|--mirror)           require_arg "${1}" "${2:-}"; BUILD_MIRROR="${2}";         shift 2 ;;
    -o|--output)           require_arg "${1}" "${2:-}"; OUT_DIR="${2}";              shift 2 ;;
    -P|--packages)         require_arg "${1}" "${2:-}"; PACKAGES="${PACKAGES} ${2}"; shift 2 ;;
    -v|--variant)          require_arg "${1}" "${2:-}"; VARIANT="${2}";              shift 2 ;;
    -x|--version)          require_arg "${1}" "${2:-}"; VERSION="${2}";              shift 2 ;;
    *)                     fail "Unknown option: ${1}" ;;
  esac
done

## Handle trap as ${KEEP} is now defined
trap 'cleanup_ps; cleanup_fs' INT TERM

## Normalize ARCH
case "${ARCH,,}" in
  x64|x86_64|x86-64|amd64)
    ARCH=amd64
    ;;
  arm64|aarch64)
    ARCH=arm64
    ;;
  armhf|armv7l|armv7|armv6l)
    ARCH=armhf
    ;;
  i386|i486|i586|i686|x86)
    ARCH=i386
    ;;
esac

## Normalize BRANCH
case ${BRANCH,,} in
  kali-last-release|kali-last-snapshot)
    BRANCH=kali-last-snapshot
    ;;
esac

## Normalize OUT_DIR
OUT_DIR="${OUT_DIR%/}"

## Normalize BUILD_MIRROR
BUILD_MIRROR="${BUILD_MIRROR%/}/"

## Normalize PACKAGES
mapfile -t _pkgs < <( tr ', ' '\n' <<< "${PACKAGES}" | LC_ALL=C sort -u | awk 'NF' )
printf -v PACKAGES '%s, ' "${_pkgs[@]}"
PACKAGES="${PACKAGES%, }"
unset _pkgs

## VERSION depends on other vars, set it now
[ -n "${VERSION}" ] || VERSION="$( default_version )"

## Validate VERSION - it ends up in OUT_FILENAME, so a "/" would escape ${OUT_DIR}
[[ "${VERSION}" == *[[:space:]/]* ]] \
  && fail_invalid -x "${VERSION}" "must not contain spaces or '/'"

## Validate BUILD_MIRROR - it gets handed to apt/debootstrap, where a malformed URL fails late and opaquely
[[ "${BUILD_MIRROR}" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]]+$ ]] \
  || fail_invalid -m "${BUILD_MIRROR}" "must be a URL with no spaces (e.g. http://host/path)"

## Filename structure for final file
if [ "${VARIANT}" = "default" ]; then
  OUT_FILENAME="kali-linux-${VERSION,,}-installer-${ARCH,,}.iso"
else
  OUT_FILENAME="kali-linux-${VERSION,,}-installer-${VARIANT,,}-${ARCH,,}.iso"
fi

valid_hostname "${KALI_HOSTNAME}" \
  || fail_invalid -H "${KALI_HOSTNAME}" "must contain only letters, digits and hyphens"

## Validate options against the supported lists
## Method #1
#echo "${SUPPORTED_ARCHITECTURES}" | grep -qw "${ARCH}"    \
#  || fail "Unsupported architecture: ${ARCH} (must be one of: ${SUPPORTED_ARCHITECTURES})"
## Method #2
#echo "${SUPPORTED_ARCHITECTURES}" | grep -qw "${ARCH}" \
#  || fail_invalid -a "${ARCH}" "must be one of: ${SUPPORTED_ARCHITECTURES}"
## Method #3
in_list "${ARCH}" "${SUPPORTED_ARCHITECTURES}" \
  || fail_invalid -a "${ARCH}"

in_list "${BRANCH}" "${SUPPORTED_BRANCHES}" \
  || fail_invalid -b "${BRANCH}"

in_list "${VARIANT}" "${SUPPORTED_VARIANTS}" \
  || fail_invalid -v "${VARIANT}"

## Host OS checks
check_os

## Attempt to detect well-known http caching proxies on localhost
##   ...only if user didn't override --mirror or if http_proxy environment variable is set
##   - [ -v http_proxy ]                  - isn't always supported (bash >= 4.2, ~2011?)
##   - [ -z ${http_proxy:-} ]             - doesn't behave if "$ http_proxy= ./build.sh" (will try detect, rather than empty the value)
##   - [ $( env | grep '^http_proxy=' ) ] - looks messy
if [ "${BUILD_MIRROR%/}" = "${DEFAULT_BUILD_MIRROR%/}" ] && [ ! -v http_proxy ]; then
  ## Use a proxy to speed up, if available
  DETECTED_CACHING_PROXY="$( detect_apt_caching_proxy )"
  if [ -n "${DETECTED_CACHING_PROXY}" ]; then
    read -r _port _proxy <<< "${DETECTED_CACHING_PROXY}"
    debug "Detected apt caching proxy: $( b "${_proxy}" ) on port $( b "${_port}" )"
    ## TODO: Docker, "host.docker.internal" support
    export http_proxy="http://127.0.0.1:${_port}"
    unset _port _proxy
  fi
fi

## No need to be root, but the message doesn't make much sense in containers
if [ "$( id -u )" -eq 0 ] && \
   [ -z "$( detect_container )" ]; then
  PROMPT="#"
  warn "This script does not require root privileges"
  warn "Please consider running it as a non-root user"
  echo ""
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Overview
#

_cross_build=""
is_cross_build && _cross_build=", so $( b "cross-building ${ARCH} ${PLATFORM}" )"

_env=$( detect_container )
if [ -n "${_env}" ]; then
  _env="container ($( b "${_env}" ))"
elif command -v systemd-detect-virt >/dev/null 2>&1; then
  _virt=$( systemd-detect-virt 2>/dev/null || true )   # prints "none" and exits 1 when not virtualised
  [ "${_virt}" = "none" ] && _virt="bare metal"
  _env="host ($( b "${_virt}" ))"
else
  _env="host"
fi

{
point "Building a Kali Linux $( b "${PROJECT} ${PLATFORM}" ) for $( b "${ARCH}" ) architecture"
echo "# System:"
point "Build environment is $( b "${_env}" )"
point "Host architecture is $( b "${HOST_ARCH}" )${_cross_build}"

echo "# Build:"
point "Branch              : $( b "${BRANCH}" )"
point "Build mirror        : $( b "${BUILD_MIRROR}" )"
point "Keep temporary files: $( b "${KEEP}" )"
point "Output              : $( b "${OUT_DIR}/${OUT_FILENAME}" )"
point "Variant             : $( b "${VARIANT}" )"
point "Version             : $( b "${VERSION}" )"

echo "# ${PROJECT}:"
point "Additional packages :${PACKAGES:+ $( b "${PACKAGES}" )}"
point "Hostname            : $( b "${KALI_HOSTNAME}" )"

echo "# Proxy configuration:"
if [ -n "${DETECTED_CACHING_PROXY}" ]; then
  read -r _port _proxy <<< "${DETECTED_CACHING_PROXY}"
  point "Detected caching proxy $( b "${_proxy}" ) on port $( b "${_port}" )"
elif [ -n "${http_proxy:-}" ]; then
  point "Using proxy via environment variable: $( b "http_proxy=${http_proxy}" )"
elif [ "${DEFAULT_BUILD_MIRROR%/}" != "${BUILD_MIRROR%/}" ]; then
  point "$( b "Skipping detecting" ) apt caching proxy (custom build-mirror)"
else
  point "$( b "No apt caching proxy" ) detected"
fi
} | kali_message "Kali ${PROJECT} ${PLATFORM}"
unset _cross_build _env _virt _port _proxy

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Build
#

## Prepare output directory
vrun mkdir -pv "${OUT_DIR}/"

## Capture all output, stdout & stderror, from here on out into a file
exec &> >( tee -a "${OUT_DIR}/${OUT_FILENAME}.log" )

## Do magic
create_image

## Compress
##   ...N/A - no --zip flag here, the ISO ships as-is

cleanup_fs

## Checksum
( cd "${OUT_DIR}" \
  && find . -maxdepth 1 -type f -name "${OUT_FILENAME}*" ! -name '*.log' ! -name '*.sha512sum' -print0 \
    | while IFS= read -r -d '' _f; do
        _f="${_f#./}"
        vrun sha512sum "${_f}" | tee "${_f}.sha512sum"
      done )
  #&& vrun sha512sum "${OUT_FILENAME}" | tee "${OUT_FILENAME}.sha512sum" )

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#
## Finish
#

cat << EOF
..............
            ..,;:ccc,.
          ......''';lxO.
.....''''..........,:ld;
           .';;;:::;,,.x,
      ..'''.            0Xxoc:,.  ...
  ....                ,ONkc;,;cokOdc',.
 .                   OMo           ':$( b dd )o.
                    dMc               :OO;
                    0M.                 .:o.
                    ;Wd
                     ;XO,
                       ,d0Odlc;,..
                           ..',;:cdOOd::,.
                                    .:d;.':;.
                                       'd,  .'
                                         ;l   ..
                                          .o
                                            c
                                            .'
                                             .
Successful build! The following build artifacts were produced:
EOF
## Alt: stat  "${OUT_DIR}/${OUT_FILENAME}*"
##      ls -h "${OUT_DIR}/${OUT_FILENAME}"* | sed "s_^${PWD}/__; s_^_* _"
find "${OUT_DIR}/" -maxdepth 1 -type f -name "${OUT_FILENAME}*" \
  | while IFS= read -r _f; do echo "* ${_f#"${PWD}/"}"; done \
  | sort
