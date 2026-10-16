# Deployment files

This directory contains deployment inputs. The links below describe current Unreleased source. Choose the matching release line from the [documentation directory](https://amargherio.github.io/ytdarr/docs/) before following instructions for a tagged installation.

- [Docker Compose installation](https://amargherio.github.io/ytdarr/docs/unreleased/installation/docker-compose/)
- [Podman Quadlet installation](https://amargherio.github.io/ytdarr/docs/unreleased/installation/podman/)
- [Native systemd installation](https://amargherio.github.io/ytdarr/docs/unreleased/installation/native/)
- [Backup and upgrades](https://amargherio.github.io/ytdarr/docs/unreleased/operations/backup-and-upgrades/)
- [Security and network exposure](https://amargherio.github.io/ytdarr/docs/unreleased/operations/security/)

## File index

| File | Purpose |
| --- | --- |
| `compose.yaml` | Local-build Docker Compose service, persistent `/data` volume, and `/downloads` bind mount |
| `Dockerfile` | Shared native build/runtime stages and production container image recipe |
| `ytdarr.container` | Podman Quadlet template |
| `ytdarr-data.volume` | Podman persistent data volume template |
| `ytdarr.service` | Native systemd service unit |
| `scripts/generate-env.sh` | Runtime environment-file generator |
| `scripts/provision-host.sh` | Native host provisioning helper |
| `scripts/activate-release.sh` | Native compatibility gate, backup, migration, activation, and rollback-on-error helper |
| `scripts/rollback-release.sh` | Native retained-release rollback helper |
| `native-targets.tsv` | Supported native OS/version matrix and matching container base images |
| `scripts/build-native.sh` | Host-native, single-target, and full-matrix build entrypoint |
| `scripts/package-native.sh` | Native archive, checksum, and target metadata packaging helper |
| `scripts/smoke-native.sh` | Matching-runtime native release smoke entrypoint |
| `scripts/validate-native.sh` | Strict archive checksum, metadata, OS/version, architecture, and glibc compatibility validator |

The shared `Dockerfile` builds the pinned Erlang/Elixir toolchain from source. Its default final stage remains the production application image; native builds select the appropriate stages and distribution base instead. Container image publishing remains separate from the distribution-specific native archives. Do not assume an `edge` or `latest` image exists; use an exact tagged app image only after a matching real release is published.

Import browsing is disabled until `YTDARR_IMPORT_ROOTS` lists one or more absolute directories accessible to the Ytdarr process. With the stock Compose mount, create `deploy/downloads/.incoming` (writable by UID/GID `10001`), configure `YTDARR_IMPORT_ROOTS=/downloads/.incoming`, and restart. The rest of `/downloads` holds managed media and should not be an import root. For stronger separation, add a dedicated writable bind mount outside the managed media root and list only its in-container path. Only trusted local processes should be able to write to the source directories: a concurrent symlink swap between pathname checks and file operations is not prevented. Do not expose management routes to untrusted clients.

The native helpers require a trusted host and have an environment-file permission limitation. Immediately after every native provisioning or deployment attempt, including a failure, set the configured environment file to the configured app group and mode `0640`; the default is:

```sh
sudo chown root:ytdarr /etc/ytdarr/ytdarr.env
sudo chmod 0640 /etc/ytdarr/ytdarr.env
stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env
```

The expected result is `640 root:ytdarr`. Use the container route on shared or untrusted multi-user hosts.

## Native release commands

```sh
just release                       # host-native, using the installed local toolchain
just release-target fedora-44       # matching container build environment
just release-target ubuntu-26.10
just release-target ubuntu-26.04
just release-target ubuntu-24.04
just release-target rocky-10.2
just release-all                   # all five targets plus the host-native build
bash deploy/scripts/build-native.sh --list
bash deploy/scripts/build-native.sh --matrix
bash deploy/scripts/smoke-native.sh ubuntu-26.04
```

`just release` delegates to `bash deploy/scripts/build-native.sh host`; `release-target` and `release-all` use that same entrypoint with a target ID or `all`. Container builds require Docker or Podman on Linux x86_64 (`CONTAINER_ENGINE` can select either). The resulting binaries run **directly on the matching target OS**, not inside a container. Runtime hosts do not need Erlang, Elixir, or a container engine. Host-native builds use the installed compatible Erlang/Elixir toolchain and native build dependencies; prefer `.tool-versions` for consistency. The actual toolchain versions are recorded in the manifest. Container builders enforce the versions in `.tool-versions` against the download lock.

Each build writes `dist/native/TARGET/ytdarr-VERSION-linux-TARGET-x86_64.tar.gz`, its `.tar.gz.sha256` checksum, and its `.tar.gz.manifest`. The manifest duplicates the archive's plain `release-target` metadata: format, application version, OS ID/version, architecture, glibc, OTP/Elixir versions, source revision, and build date. Host IDs use `/etc/os-release` (`ID-VERSION_ID`, or `ID-rolling` if no version is declared). Rolling-host artifacts such as `cachyos-rolling` are not portable distribution releases; rebuild after host runtime changes.

Deploy only an existing archive selected explicitly for the destination:

```sh
just deploy server.example.com deployer \
  "dist/native/ubuntu-26.04/ytdarr-$(cat VERSION)-linux-ubuntu-26.04-x86_64.tar.gz"
```

Deployment does **not** build automatically. It transfers the chosen archive, adjacent checksum, activation script, and compatibility validator. Activation checks the exact archive checksum and parses (never sources) the embedded metadata before changing permissions, extracting files, or stopping the service. Missing/invalid metadata, a version different from the checkout's `VERSION`, a nonmatching OS/version or architecture, and an older host glibc are rejected. Metadata and a checksum are compatibility/integrity checks, not a publisher signature. On migration/readiness failure, the existing automatic previous-release and database restoration behavior is preserved; `just rollback HOST VERSION USER` still restores a retained release and its backup.

All runtime hosts need systemd, Bash, GNU coreutils/tar, util-linux, glibc, OpenSSL, ncurses, the C++ runtime, zlib, CA certificates, curl, SQLite, yt-dlp, ffmpeg, and rsync. Ubuntu 24.04/26.04/26.10 use `libssl3t64`, `libncurses6`, `libstdc++6`, `zlib1g`, `sqlite3`, `yt-dlp`, and `ffmpeg` (enable universe as needed). Fedora 44 uses `openssl-libs`, `ncurses-libs`, `libstdc++`, `zlib-ng-compat`, `sqlite`, `yt-dlp`, and `ffmpeg-free`. Rocky 10.2 uses `openssl-libs`, `ncurses-libs`, `libstdc++`, `zlib`, `sqlite`, `yt-dlp`, and `ffmpeg-free`; enable CRB and EPEL for media packages. See the [native installation guide](https://amargherio.github.io/ytdarr/docs/unreleased/installation/native/) for package commands, provisioning, and the required post-deployment secret-file permission repair.