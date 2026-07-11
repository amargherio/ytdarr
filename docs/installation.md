# Installation

This guide covers local development and production deployment for Ytdarr, a Phoenix/Elixir application that monitors YouTube channels and downloads videos with `yt-dlp`.

## 1. Prerequisites

Before installing Ytdarr, make sure the following dependencies are available on your system.

### Elixir and Erlang

Install **Elixir 1.15+** and **Erlang/OTP 26+**:

- <https://elixir-lang.org/install.html>

Verify your versions:

```bash
elixir --version
```

### yt-dlp

Install **yt-dlp** and ensure it is available on your shell `PATH`:

- <https://github.com/yt-dlp/yt-dlp#installation>

Verify it is installed:

```bash
yt-dlp --version
```

### YouTube Data API v3 key

Ytdarr uses the YouTube Data API to discover channels, playlists, and videos.

1. Go to <https://console.cloud.google.com/>
2. Create a new project, or select an existing project
3. Open **APIs & Services → Library**
4. Enable **YouTube Data API v3**
5. Open **APIs & Services → Credentials**
6. Create an **API key**

> The free tier provides **10,000 quota units per day**, which is typically enough for home use.

You can provide the key with an environment variable or configure it later in the Ytdarr Settings UI.

## 2. Development Setup

Clone the repository and run the standard setup task:

```bash
git clone https://github.com/amargherio/ytdarr.git
cd ytdarr
mix setup    # installs deps, creates DB, builds assets
```

Set the YouTube API key using either method below:

- Environment variable:

  ```bash
  export YTDARR_YOUTUBE_API_KEY=your_key_here
  ```

- Or configure it later in the Settings UI at <http://localhost:4000/settings>

Start the Phoenix server:

```bash
mix phx.server
# or with an IEx console:
iex -S mix phx.server
```

Open the application at:

- <http://localhost:4000>

Development routes:

- `/dev/dashboard` — Phoenix LiveDashboard
- `/dev/mailbox` — Swoosh email preview
- `/admin` — Ash Admin interface
- `/oban` — Oban job queue dashboard

> `/dev/dashboard`, `/dev/mailbox`, and `/admin` are development-only routes. The current router also mounts `/oban`; if you expose Ytdarr publicly, protect that route appropriately.

## 3. Production Deployment

### Building a release

Build the versioned OTP archive and checksum from the project root:

```bash
just release
```

Artifacts are written to `_build/prod/ytdarr-<version>.tar.gz` and the adjacent
`.sha256` file. The version comes from `VERSION`.

### Required environment variables

| Variable | Required | Description | Example |
| --- | --- | --- | --- |
| `DATABASE_PATH` | Yes | Absolute path to the SQLite database file | `/var/lib/ytdarr/ytdarr.db` |
| `SECRET_KEY_BASE` | Yes | Phoenix secret key used for cookies and encryption | Generate with `mix phx.gen.secret` |
| `TOKEN_SIGNING_SECRET` | Yes | Secret used for token signing | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Yes | Public hostname used for URL generation | `ytdarr.example.com` |
| `PHX_SERVER` | Yes | Must be set so the release starts the HTTP server | `true` |
| `PORT` | No | HTTP listen port | `4000` |
| `POOL_SIZE` | No | SQLite connection pool size (default: 10) | `5` |
| `YTDARR_YOUTUBE_API_KEY` | Recommended | YouTube API key; can also be configured in the UI | `AIza...` |
| `DNS_CLUSTER_QUERY` | No | DNS cluster query for distributed deployments | — |

`SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET`, and `YTDARR_YOUTUBE_API_KEY` also
accept `SECRET_KEY_BASE_FILE`, `TOKEN_SIGNING_SECRET_FILE`, and
`YTDARR_YOUTUBE_API_KEY_FILE`. Set either a direct value or its file variant,
never both.

Generate a mode `0600` environment file with:

```bash
just generate-env deploy/.env ytdarr.example.com container 4000
```

### Running the release

After extracting the release, migrate and start it with:

```bash
bin/migrate
bin/server
```

### Native systemd deployment

The target host needs systemd, `curl`, `sqlite3`, `yt-dlp`, and `ffmpeg`. The SSH
account needs key-based access and passwordless sudo for the provisioning and
activation scripts.

```bash
just generate-env deploy/native.env ytdarr.example.com native 4000
just install-host server.example.com deployer deploy/native.env
just deploy server.example.com deployer
```

Updates stop the service briefly, make a consistent SQLite backup, migrate the
new version, atomically switch `/opt/ytdarr/current`, and wait for readiness. A
failed migration or readiness check restores the previous database and release.

```bash
just rollback server.example.com 0.1.0 deployer
```

See the [Deployment Guide](../deploy/README.md) for paths, retention, sudo, and
backup details.

### Reverse proxy (nginx)

```nginx
server {
    listen 80;
    server_name ytdarr.example.com;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

The WebSocket upgrade headers are required for Phoenix LiveView.

### Reverse proxy (Caddy)

```caddy
ytdarr.example.com {
    reverse_proxy localhost:4000
}
```

Caddy handles WebSocket upgrades and TLS automatically.

## 4. Filesystem Structure

Ytdarr stores downloads in a media-server-friendly structure:

```text
<media_root>/
└── channel_name/
    ├── Season 2025/
    │   ├── Channel Name - S2025E001 - Video Title.mp4
    │   ├── Channel Name - S2025E001 - Video Title.nfo
    │   ├── Channel Name - S2025E002 - Another Video.mp4
    │   ├── Channel Name - S2025E002 - Another Video.nfo
    │   └── ...
    └── Season 2026/
        └── ...
```

### Episode numbering

Videos are numbered sequentially by upload date within each year:

- The first video uploaded in 2025 is `E001`
- The second is `E002`
- If multiple videos share the same upload date, ordering falls back to the internal database ID

### NFO metadata files

Each downloaded video gets a companion `.nfo` file in Kodi/Jellyfin-style `<episodedetails>` XML.

The generated metadata includes:

- Title
- Season (year)
- Episode number
- Description / plot
- Air date
- Source URL
- A `<uniqueid type="youtube">...</uniqueid>` field

### Media root folder

The media root folder is configurable in the Settings UI and defaults to:

- `/downloads`

The Ytdarr process must have read/write access to that directory.

### Media server setup

Point your media server library at the media root folder and configure the library type as **TV Shows**.

Ytdarr's layout maps naturally to common media servers:

- Each YouTube channel becomes a show
- Each year becomes a season
- Each downloaded video becomes an episode

## 5. Docker and Podman

Ytdarr publishes `linux/amd64` images to `ghcr.io/amargherio/ytdarr`. Stable
releases use immutable version tags and `latest`; builds from `main` use `edge`.

```bash
just generate-env deploy/.env ytdarr.example.com container 4000
mkdir -p deploy/downloads
docker compose -f deploy/compose.yaml up -d
```

The container runs as UID/GID `10001`, automatically runs pending migrations,
and stores persistent state under:

- `/data` for SQLite and Oban jobs
- `/downloads` for downloaded media and metadata

A direct Docker invocation is also supported:

```bash
docker run -d --name ytdarr \
    --env-file deploy/.env \
    -p 4000:4000 \
    -v ytdarr-data:/data \
    -v /srv/ytdarr/downloads:/downloads \
    --restart unless-stopped \
    ghcr.io/amargherio/ytdarr:latest
```

Podman Quadlet units are provided in `deploy/ytdarr.container` and
`deploy/ytdarr-data.volume`. Health endpoints are available at `/health/live`
and `/health/ready`.

## 6. Troubleshooting

- **"No YouTube API key configured"**: Set `YTDARR_YOUTUBE_API_KEY` or add the key in **Settings → YouTube**
- **yt-dlp not found**: Ensure `yt-dlp` is installed and available on the `PATH` for the user running Ytdarr
- **Permission denied on downloads**: Ensure the Ytdarr process can write to the configured media root folder
- **Database locked errors**: SQLite uses file locking; run only one Ytdarr instance per database file
- **Quota exceeded**: The YouTube Data API has a daily quota of 10,000 units; reduce sync frequency if needed
