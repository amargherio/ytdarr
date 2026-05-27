# Ytdarr

<!-- Badges: add CI / release / container / license badges here -->

Ytdarr is a self-hosted YouTube channel monitor and video downloader that organizes content for Jellyfin, Plex, and Emby. It is built with Elixir, Phoenix LiveView, and the Ash Framework, uses SQLite for zero-dependency storage, and relies on `yt-dlp` for downloads.

## Features

- Monitor YouTube channels for new uploads
- Run automatic background syncs on configurable intervals with `BatchSyncWorker` (default: 60 minutes)
- Download videos through `yt-dlp` with configurable quality profiles and parameter sets
- Organize media as `<channel>/Season YYYY/` with episode numbering and `.nfo` metadata files
- Track playlists and keep playlist metadata in sync
- Use the web UI for channel management, content search, settings, and monitoring
- Use the built-in Oban dashboard at `/oban` to inspect jobs and queues
- Run with SQLite only — no PostgreSQL, Redis, or other external services required beyond `yt-dlp`

## Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- `yt-dlp` installed and available on your `PATH`
- A YouTube Data API v3 key from Google Cloud Console

## Quick Start

```bash
git clone https://github.com/amargherio/ytdarr.git
cd ytdarr
mix setup
YTDARR_YOUTUBE_API_KEY=your_key_here mix phx.server
```

Then visit http://localhost:4000

## Documentation

- [Installation Guide](docs/installation.md) — Dev setup, production deployment, filesystem structure
- [Configuration Reference](docs/configuration.md) — All settings, quality profiles, yt-dlp params

## How It Works

1. Add a YouTube channel via the web UI (search or direct URL)
2. Enable monitoring on the channel
3. Background sync checks for new uploads on the configured interval
4. Queue videos for download — `yt-dlp` handles the fetch
5. Videos are organized into season folders with episode numbers and `.nfo` metadata
6. Point Jellyfin, Plex, or Emby at the configured media root folder

## Development

```bash
mix setup              # install deps, create DB, build assets
mix phx.server         # start dev server with live reload
iex -S mix phx.server  # start with an IEx console
mix test               # run the test suite
mix precommit          # compile (warnings-as-errors), format, test
```

## License

TODO: Add license
