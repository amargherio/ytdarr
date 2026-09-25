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
| `Dockerfile` | Container image build recipe |
| `ytdarr.container` | Podman Quadlet template |
| `ytdarr-data.volume` | Podman persistent data volume template |
| `ytdarr.service` | Native systemd service unit |
| `scripts/generate-env.sh` | Runtime environment-file generator |
| `scripts/provision-host.sh` | Native host provisioning helper |
| `scripts/activate-release.sh` | Native checksum, backup, migration, activation, and rollback-on-error helper |
| `scripts/rollback-release.sh` | Native retained-release rollback helper |

The current source path builds its container locally with a `BUILDER_IMAGE` override because the Dockerfile's default Hex image tag is unavailable. Use the exact published builder command in the [Docker Compose](https://amargherio.github.io/ytdarr/docs/unreleased/installation/docker-compose/#build-and-start) or [Podman](https://amargherio.github.io/ytdarr/docs/unreleased/installation/podman/#build-and-install-a-local-quadlet) guide. Do not assume an `edge` or `latest` image exists; use an exact tagged app image only after a matching real release is published.

Import browsing is disabled until `YTDARR_IMPORT_ROOTS` lists one or more absolute directories accessible to the Ytdarr process. With the stock Compose mount, create `deploy/downloads/.incoming` (writable by UID/GID `10001`), configure `YTDARR_IMPORT_ROOTS=/downloads/.incoming`, and restart. The rest of `/downloads` holds managed media and should not be an import root. For stronger separation, add a dedicated writable bind mount outside the managed media root and list only its in-container path. Only trusted local processes should be able to write to the source directories: a concurrent symlink swap between pathname checks and file operations is not prevented. Do not expose management routes to untrusted clients.

The native helpers require a trusted host and have an environment-file permission limitation. Immediately after every native provisioning or deployment attempt, including a failure, set the configured environment file to the configured app group and mode `0640`; the default is:

```sh
sudo chown root:ytdarr /etc/ytdarr/ytdarr.env
sudo chmod 0640 /etc/ytdarr/ytdarr.env
stat -c '%a %U:%G' /etc/ytdarr/ytdarr.env
```

The expected result is `640 root:ytdarr`. Use the container route on shared or untrusted multi-user hosts.