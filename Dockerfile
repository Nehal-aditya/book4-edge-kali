## REF: https://hub.docker.com/_/debian
FROM docker.io/debian:stable-slim

RUN /bin/bash -o pipefail -c '\
  ## Update package index
    apt-get update && \
  ## Update OS
    #apt-get -y dist-upgrade && \
  #
  ## Install Kali archive keyring
  #
    env DEBIAN_FRONTEND=noninteractive apt-get --quiet --yes install --no-install-recommends \
        wget ca-certificates \
      && \
    wget -nv -O /tmp/Packages.gz \
        https://kali.download/kali/dists/kali-rolling/main/binary-amd64/Packages.gz && \
    PKG="kali-archive-keyring" && \
    PKG_RECORD=$( gzip -dc /tmp/Packages.gz | awk -v RS= "/(^|\n)Package: ${PKG}\n/" ) && \
    PKG_URL=$( echo "${PKG_RECORD}" | awk "/^Filename:/ { print \$2; exit }" ) && \
    PKG_SHA=$( echo "${PKG_RECORD}" | awk "/^SHA256:/ { print \$2; exit }" ) && \
    wget -nv "https://kali.download/kali/${PKG_URL}" && \
    echo "${PKG_SHA}  ./${PKG_URL##*/}" | sha256sum -c - && \
    dpkg -i ./${PKG}_*_all.deb && \
    rm -v ./${PKG}_*_all.deb && \
    ## Removing later in Kali package section
    #apt-get --quiet --yes purge \
    #    wget ca-certificates \
    #  && \
  #
  ## Get Kali's packages (on non-Kali OS)
  ##   REF: ./README.md
  ##   Alt: echo "deb http://http.kali.org/kali kali-rolling main non-free non-free-firmware contrib" | tee /etc/apt/sources.list.d/kali.list
  #
    PKG="debian-cd" && \
    PKG_RECORD=$( gzip -dc /tmp/Packages.gz | awk -v RS= "/(^|\n)Package: ${PKG}\n/" ) && \
    PKG_URL=$( echo "${PKG_RECORD}" | awk "/^Filename:/ { print \$2; exit }" ) && \
    PKG_SHA=$( echo "${PKG_RECORD}" | awk "/^SHA256:/ { print \$2; exit }" ) && \
    wget -nv "https://kali.download/kali/${PKG_URL}" && \
    echo "${PKG_SHA}  ./${PKG_URL##*/}" | sha256sum -c - && \
    PKG="simple-cdd" && \
    PKG_RECORD=$( gzip -dc /tmp/Packages.gz | awk -v RS= "/(^|\n)Package: ${PKG}\n/" ) && \
    PKG_URL=$( echo "${PKG_RECORD}" | awk "/^Filename:/ { print \$2; exit }" ) && \
    PKG_SHA=$( echo "${PKG_RECORD}" | awk "/^SHA256:/ { print \$2; exit }" ) && \
    wget -nv "https://kali.download/kali/${PKG_URL}" && \
    echo "${PKG_SHA}  ./${PKG_URL##*/}" | sha256sum -c - && \
    ## wget is used by debian-cd
    apt-get --quiet --yes purge \
        wget ca-certificates \
      && \
  #
  ## Install OS packages
  ##   REF: ./README.md
  #
    ## Method #1
    #PKG="debian-cd" && \
    #env DEBIAN_FRONTEND=noninteractive apt-get satisfy --yes --no-install-recommends \
    #    ${PKG} \
    #  && \
    #dpkg -i ./*.deb && \
    ## Method #2
    env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      # > ERROR: You need debian-cd (>= 3.2.1+kali1), but it is not installed
      #  debian-cd \
      # > ERROR: You need simple-cdd (>= 0.6.9), but it is not installed
      #  simple-cdd \
      # > /build/simple-cdd/debian-cd/tools/boot/kali-rolling/common.sh: line 251: cpio: command not found
        cpio \
      # > /build/simple-cdd/debian-cd/tools/boot/kali-rolling/boot-x86: line 433: mcopy: command not found
        mtools \
      # > /build/simple-cdd/debian-cd/tools/boot/kali-rolling/boot-x86: line 497: mkfs.msdos: command not found
        dosfstools \
      # > /build/simple-cdd/debian-cd/tools/make_image: 1: eval: xorriso: not found
        xorriso \
      # ...Any files manually pulled down (e.g. the step/stage before, non-Kali OS)
        ./*.deb \
      ## If using a HTTPS mirror
      # > ERROR: The certificate of 'http.kali.org' is not trusted.
      # > ERROR: The certificate of 'http.kali.org' doesn't have a known issuer.
        ca-certificates \
      && \
    rm -v ./*.deb && \
  #
  ## Clean up
  #
    apt-get --quiet --yes --purge autoremove && \
    apt-get --quiet --yes clean && \
    rm -rfv \
      /usr/share/doc \
      /usr/share/man \
      /var/lib/apt/lists/* \
      /tmp/* \
      /var/tmp/*'
