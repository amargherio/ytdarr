# Deployment

Ytdarr supports two production targets on `linux/amd64`:

- Docker or Podman using `ghcr.io/amargherio/ytdarr`
- A native OTP release managed by systemd

Both targets run explicit database migrations before startup and expose
`/health/live` and `/health/ready`. TLS should terminate at a reverse proxy.

## Release channels

| Tag | Source | Intended use |
| --- | --- | --- |
| `edge` | Latest successful `main` build | Testing upcoming changes |
| `latest` | Most recent version tag | Stable installations |
| `<version>` | Exact release | Reproducible deployments and rollback |
| `<major>.<minor>` | Most recent patch in a minor line | Controlled patch updates |

Version tags must exactly match `v<VERSION>`. Tagged releases include the
container image, OTP tarball, SHA-256 checksum, provenance, and SBOM.

## Docker Compose

```bash
just generate-env deploy/.env ytdarr.example.com container 4000
mkdir -p deploy/downloads
docker compose -f deploy/compose.yaml up -d
```

Edit `YTDARR_DOWNLOADS_PATH` in the shell or Compose environment to bind a
different media directory. The image runs as UID/GID `10001`; bind-mounted
download directories must be writable by that identity.

### Shared media permissions

Media settings default to ownership by `ytdarr:ytdarr`, file mode `0644`, and
directory mode `0755`. A different media group must exist in the container and
the `ytdarr` process must be a supplementary member before it starts. The stock
image only defines the `ytdarr` group.

For a custom named group, derive an image that creates the same group name and
GID used by the host media service:

```dockerfile
FROM ghcr.io/amargherio/ytdarr:latest
USER root
RUN groupadd --gid 1234 media && usermod --append --groups media ytdarr
USER ytdarr
```

Build that image, set the bind-mounted download directory's group to GID `1234`,
and make it group-writable before selecting `media` in Ytdarr. Adding only a
numeric Compose `group_add` entry is insufficient because Ytdarr validates the
configured group through the container's group database.

To update a stable installation:

```bash
docker compose -f deploy/compose.yaml pull
docker compose -f deploy/compose.yaml up -d
```

Back up the complete `/data` volume before updates when operator-managed
rollback is required. SQLite may create `ytdarr.db-wal` and `ytdarr.db-shm`
alongside the database, so back up the volume rather than only one file.

## Secret files

These secrets support file-based injection:

| Direct variable | File variable |
| --- | --- |
| `SECRET_KEY_BASE` | `SECRET_KEY_BASE_FILE` |
| `TOKEN_SIGNING_SECRET` | `TOKEN_SIGNING_SECRET_FILE` |
| `YTDARR_YOUTUBE_API_KEY` | `YTDARR_YOUTUBE_API_KEY_FILE` |

Set only one form for each value. Mount Docker/Podman secrets read-only and set
the corresponding file variable to the in-container path.

## Podman Quadlet

1. Copy `ytdarr.container` and `ytdarr-data.volume` to
   `/etc/containers/systemd/`.
2. Create `/etc/ytdarr/ytdarr.env` from `env.example` with mode `0640`.
3. Create `/srv/ytdarr/downloads` and grant UID/GID `10001` write access.
4. Run `systemctl daemon-reload && systemctl enable --now ytdarr.service`.

The Quadlet enables Podman registry auto-update. The provided bind mount uses
the `:Z` SELinux relabel option.

## Native systemd

Generate an environment file for native paths:

```bash
just generate-env deploy/native.env ytdarr.example.com native 4000
```

Provision once, then deploy each version:

```bash
just install-host server.example.com deployer deploy/native.env
just deploy server.example.com deployer
```

The SSH account must use key authentication and have passwordless sudo for the
deployment scripts. Host prerequisites are `systemd`, `curl`, `sqlite3`,
`yt-dlp`, and `ffmpeg`.

To share media with Jellyfin or another service, create or select a common group,
add both service users, prepare the media root, and restart the services so they
receive their new supplementary groups:

```bash
sudo groupadd --system media
sudo usermod --append --groups media ytdarr
sudo usermod --append --groups media jellyfin
sudo chgrp media /srv/media
sudo chmod 0775 /srv/media
sudo systemctl restart ytdarr jellyfin
```

Then set the Media Management group to `media`. New writes use the saved group
and exact file/directory modes immediately. Use **Apply to existing media** to
normalize configured roots. Ytdarr never creates groups or elevates privileges;
it rejects a group unavailable to its running process.

Native paths are:

| Purpose | Path |
| --- | --- |
| Versioned releases | `/opt/ytdarr/versions/<version>` |
| Active release | `/opt/ytdarr/current` |
| Runtime environment | `/etc/ytdarr/ytdarr.env` |
| SQLite state | `/var/lib/ytdarr` |
| Upgrade backups | `/var/lib/ytdarr/backups` |

Activation verifies the artifact checksum, stops Ytdarr, backs up SQLite and
its sidecars, runs migrations as the service user, switches the active symlink,
starts the service, and waits for readiness. Failures restore both the previous
database and release automatically.

To explicitly restore a retained version and its pre-upgrade database:

```bash
just rollback server.example.com 0.1.0 deployer
```

The default retention is three releases and three backups. Override it with
`YTDARR_RELEASE_RETENTION` in the privileged activation environment.

## Building locally

```bash
just release
just container-build
```

The native archive and checksum are written under `_build/prod`. The container
build uses Podman by default; Docker can build the same `deploy/Dockerfile`.
