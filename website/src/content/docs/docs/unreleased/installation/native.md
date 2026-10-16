---
title: Native systemd installation
description: Build and deploy a distribution-matched Linux x86_64 Ytdarr OTP release to a provisioned systemd host.
sidebar:
  order: 3
---

Native releases target **Linux x86_64** with an exact distribution/version match: **Fedora 44**, **Ubuntu 26.10**, **Ubuntu 26.04**, **Ubuntu 24.04**, and **Rocky Linux 10.2**. There is also a host-native build for the build machine's own distribution. The SSH deploy account needs key authentication and passwordless `sudo` for the supplied helpers. In released documentation, use the exact source tag shown in that page's version notice rather than cloning `main`.

> **Secret-file warning:** the native helpers do not preserve the generator's safe `0600` permissions. Provisioning installs the environment file as `0644` and makes its directory world-readable; every activation repeats that directory widening. Prefer the container route on a shared or untrusted multi-user machine.

## Build for the target host

```sh
# Build for this machine's exact distribution/version with its installed toolchain.
just release

# Build for a different supported host in a matching container.
just release-target ubuntu-26.04

# Build every supported distribution plus the host-native variant.
just release-all

# Equivalent shared entrypoint and supported target discovery.
bash deploy/scripts/build-native.sh host
bash deploy/scripts/build-native.sh --list
bash deploy/scripts/build-native.sh --matrix
```

The matrix IDs are `fedora-44`, `ubuntu-26.10`, `ubuntu-26.04`, `ubuntu-24.04`, and `rocky-10.2`. Container builds need Docker or Podman on a Linux x86_64 build host; set `CONTAINER_ENGINE=docker` or `CONTAINER_ENGINE=podman` to select one explicitly. These containers are **build environments**: the resulting binaries run directly on the matching target host under systemd, with no container engine or Erlang/Elixir installation required there. Container builders enforce `.tool-versions` against the download lock. Host-native builds use the locally installed compatible toolchain and native build dependencies; prefer `.tool-versions` for consistency. The manifest records the actual toolchain versions.

Artifacts are written to `dist/native/TARGET/ytdarr-VERSION-linux-TARGET-x86_64.tar.gz`, alongside `.tar.gz.sha256` and `.tar.gz.manifest`. The archive contains the same plain `release-target` metadata as the manifest, recording the OS/version, architecture, glibc, toolchain, source revision, and build date. `host` resolves to `/etc/os-release`'s `ID` and `VERSION_ID`, falling back to `rolling` when the version is absent, for example `cachyos-rolling`. A rolling-host artifact is a local convenience, **not a portable Linux build**; rebuild after runtime/toolchain changes, and never use it as a substitute for a distribution-targeted artifact.

To exercise a produced release in a matching clean runtime environment, run `bash deploy/scripts/smoke-native.sh ubuntu-26.04` (or `host` for a host-native release).

## Target runtime prerequisites

The target needs systemd, Bash, GNU coreutils/tar, util-linux (`runuser`), CA certificates, glibc, OpenSSL, ncurses, the C++ runtime, zlib, `curl`, SQLite, `yt-dlp`, and `ffmpeg`. Use a fully updated installation of the **exact** target OS version. Typical package commands are:

```sh
# Ubuntu 24.04, 26.04, or 26.10 (enable universe for yt-dlp/ffmpeg if needed).
sudo apt-get update
sudo apt-get install ca-certificates curl sqlite3 yt-dlp ffmpeg \
  libssl3t64 libncurses6 libstdc++6 zlib1g systemd util-linux tar coreutils

# Fedora 44.
sudo dnf install ca-certificates curl sqlite yt-dlp ffmpeg-free \
  openssl-libs ncurses-libs libstdc++ zlib-ng-compat systemd util-linux tar coreutils

# Rocky Linux 10.2: enable CRB and EPEL for the media tools.
sudo dnf install dnf-plugins-core epel-release
sudo dnf config-manager --set-enabled crb
sudo dnf install ca-certificates curl sqlite yt-dlp ffmpeg-free \
  openssl-libs ncurses-libs libstdc++ zlib systemd util-linux tar coreutils
```

Fedora/Rocky's `ffmpeg-free` supplies the `ffmpeg` command; available codecs depend on the distribution package. Install suitable additional codecs separately if your media requires them. For another host-native OS, install its equivalent runtime packages and build on that same OS/version. Install `rsync` on both the build/deploy machine and target, and an SSH client on the deploy machine.

## Provision and deploy

1. Build an archive for the target OS and generate a native environment file (this example targets Ubuntu 26.04):

   ```sh
   just release-target ubuntu-26.04
   just generate-env deploy/native.env ytdarr.example.com native 4000
   ```

2. Provision the target once:

   ```sh
   just install-host server.example.com deployer deploy/native.env
   ```

3. **Immediately after provisioning**, repair and verify the target environment-file permissions before any deployment:

   ```sh
   ssh deployer@server.example.com \
     "sudo chown root:ytdarr /etc/ytdarr/ytdarr.env && sudo chmod 0640 /etc/ytdarr/ytdarr.env && stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env"
   ```

   The expected output is `640 root:ytdarr`. If helper overrides change `YTDARR_ENV_FILE` or `YTDARR_APP_GROUP`, substitute those configured values.

4. Deploy, then repair the file **again immediately after every deployment attempt**, including a failed activation. This form preserves the deployment exit status while ensuring the repair runs:

   ```sh
   set +e
   just deploy server.example.com deployer \
     "dist/native/ubuntu-26.04/ytdarr-$(cat VERSION)-linux-ubuntu-26.04-x86_64.tar.gz"
   deploy_status=$?
   set -e
   ssh deployer@server.example.com \
     "sudo chown root:ytdarr /etc/ytdarr/ytdarr.env && sudo chmod 0640 /etc/ytdarr/ytdarr.env && stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env"
   test "$deploy_status" -eq 0
   ```

   Repeat this repair sequence after every retry. The helpers expose the file during provisioning and activation, so do not defer it until the next maintenance window.

Deployment requires an **explicit existing archive** and its adjacent checksum; it never builds a release implicitly. Keep the checkout's `VERSION` equal to the artifact version. Before changing permissions, extracting files, or stopping the service, activation verifies that checksum against the supplied archive, parses its required metadata without executing it, and rejects a missing/invalid manifest, a version mismatch, a different OS/version or architecture, or a host glibc older than the build's glibc. A valid checksum alone does not establish publisher authenticity: use artifacts from a trusted build or release source.

After validation, deployment stops the service, backs up SQLite, migrates, switches `/opt/ytdarr/current`, starts the service, and waits for readiness. Versioned releases live under `/opt/ytdarr/versions`; persistent state and backups default to `/var/lib/ytdarr`.

## Verify and recover

Check `curl --fail http://server.example.com:4000/health/ready` through the host's intended trusted-network route and inspect `journalctl -u ytdarr`. The deployment scripts automatically restore the preceding release and database when migration or readiness fails. To explicitly restore a retained release and its pre-upgrade database, use:

```sh
just rollback server.example.com RETAINED_VERSION deployer
```

Native activation accepts prerelease suffixes; that does not make them stable releases. Review [backup and upgrades](../../operations/backup-and-upgrades/) before an update.