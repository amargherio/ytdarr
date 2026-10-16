#!/usr/bin/env bash
set -euo pipefail
mode="${1:?Expected runtime or build}"
# Only system-owned OS identification is sourced; artifact metadata is never sourced.
source /etc/os-release
case "$ID:$mode" in
  ubuntu:runtime)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl ffmpeg libncurses6 libstdc++6 openssl zlib1g tini tar gzip
    rm -rf /var/lib/apt/lists/*
    ;;
  ubuntu:build)
    apt-get update
    apt-get install -y --no-install-recommends build-essential git autoconf libncurses-dev libssl-dev zlib1g-dev unzip
    rm -rf /var/lib/apt/lists/*
    ;;
  rocky:runtime)
    dnf install -y dnf-plugins-core epel-release
    dnf config-manager --set-enabled crb
    dnf install -y ca-certificates curl-minimal ffmpeg-free ncurses-libs libstdc++ openssl-libs zlib-ng-compat tar gzip findutils shadow-utils
    dnf clean all
    ;;
  fedora:runtime)
    dnf install -y ca-certificates curl-minimal ffmpeg-free ncurses-libs libstdc++ openssl-libs zlib-ng-compat tini tar gzip findutils shadow-utils
    dnf clean all
    ;;
  fedora:build|rocky:build)
    dnf install -y gcc gcc-c++ make git autoconf ncurses-devel openssl-devel zlib-devel unzip perl
    dnf clean all
    ;;
  *) echo "Unsupported package setup: $ID:$mode" >&2; exit 1 ;;
esac
