# Ytdarr

Ytdarr is a self-hosted YouTube channel monitor and video downloader that organizes selected downloads for Jellyfin, Plex, and Emby. It is built with Elixir, Phoenix LiveView, Ash, SQLite, and yt-dlp.

## Features

- Discover and monitor YouTube channels and playlist metadata
- Synchronize metadata in background jobs
- Manually queue chosen videos for yt-dlp downloads
- Import existing videos only from explicitly configured server-side directories
- Organize media into channel/year seasons with episode NFO files
- Inspect application jobs through the built-in Oban dashboard
- Run with SQLite rather than a separate database service

## Quick start

For a source checkout, install the Elixir/Erlang versions in `.tool-versions`, plus `yt-dlp` and `ffmpeg`, then run:

```sh
git clone https://github.com/amargherio/ytdarr.git
cd ytdarr
mix setup
mix phx.server
```

Open `http://localhost:4000`. Configure a YouTube Data API v3 key and a writable media root in Settings before attempting discovery or sync. Keep the management interface on a trusted network or behind an externally authenticated proxy.

For the Unreleased local container path:

```sh
just generate-env deploy/.env localhost container 4000
mkdir -p deploy/downloads
sudo chown 10001:10001 deploy/downloads
docker compose -f deploy/compose.yaml build \
  --build-arg BUILDER_IMAGE=docker.io/hexpm/elixir:1.20.4-erlang-29.1.1-debian-bookworm-20260918-slim
docker compose -f deploy/compose.yaml up --no-build --pull never -d
```

To enable existing-media imports with the stock Compose mount, create a dedicated `deploy/downloads/.incoming` directory writable by UID/GID `10001`, set `YTDARR_IMPORT_ROOTS=/downloads/.incoming` in `deploy/.env`, and restart. The setting accepts comma-separated absolute directories visible to Ytdarr; unset disables browsing. Do not set it to all of `/downloads`: that directory also contains managed videos. Imports reject paths matching a managed video's media or companions, but source files can be moved and deleted after success. For stronger separation, bind-mount a dedicated staging directory outside the managed media root and allow only its in-container path. Only trusted operators and local processes should have write access to these directories; pathname validation cannot protect against a concurrent symlink swap by another local writer.

## Documentation

The canonical documentation is at <https://amargherio.github.io/ytdarr/docs/>. The links below describe the current Unreleased source; for a tagged installation, select its matching release line on the site before following setup commands.

- [Get started](https://amargherio.github.io/ytdarr/docs/unreleased/getting-started/)
- [Installation](https://amargherio.github.io/ytdarr/docs/unreleased/installation/docker-compose/)
- [Configuration reference](https://amargherio.github.io/ytdarr/docs/unreleased/reference/)
- [Channels, downloads, and media guides](https://amargherio.github.io/ytdarr/docs/unreleased/guides/channels-and-playlists/)
- [Security, backups, and troubleshooting](https://amargherio.github.io/ytdarr/docs/unreleased/operations/security/)
- [Developer and website contribution](https://amargherio.github.io/ytdarr/docs/unreleased/development/)

## Development

```sh
mix setup
mix phx.server
mix test
mix precommit
```

Run the static-site toolchain separately from `website/`; see the [website authoring guide](https://amargherio.github.io/ytdarr/docs/unreleased/development/website/).