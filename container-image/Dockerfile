FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        curl \
        ca-certificates \
        git \
        git-lfs \
        iproute2 \
        kmod \
        qemu-system \
        qemu-system-modules-spice \
        qemu-utils \
        iptables \
        virtiofsd \
        gdisk \
    && curl -LO http://ftp.debian.org/debian/pool/main/l/lxd/lxd_5.0.2-5_amd64.deb \
    && curl -LO http://ftp.debian.org/debian/pool/main/l/lxd/lxd-agent_5.0.2-5_amd64.deb \
    && curl -LO http://ftp.debian.org/debian/pool/main/l/lxd/lxd-client_5.0.2-5_amd64.deb \
    && apt-get -y install ./lxd*.deb \
    && rm -rf ./lxd*.deb \
    && curl -LO https://security.debian.org/debian-security/pool/updates/main/e/edk2/ovmf_2022.11-6+deb12u1_all.deb \
    && dpkg -i ovmf*.deb \
    && rm -rf ovmf*.deb \
    && apt-get -y autoclean \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    && curl -qL --output /usr/local/bin/gitlab-runner "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64" \
    && chmod +x /usr/local/bin/gitlab-runner

WORKDIR /root
